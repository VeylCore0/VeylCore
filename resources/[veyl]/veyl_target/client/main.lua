-- veyl_target main loop: one asynchronous camera shape test + a nearby-zone index. Presentation only:
-- every server action must re-validate distance, groups, entity and activity state itself.

local active, disabled = false, false
local current = { options = {}, selected = 1, entity = 0, coords = nil, sig = '' }
local nearbyZones = {}
local toggleMode = GetConvar('veyl_target:toggle', 'false') == 'true'

---------------------------------------------------------------------------
-- Overlay (passive NUI: never takes focus)
---------------------------------------------------------------------------
local function pushOverlay(force)
    local list = {}
    for i, o in ipairs(current.options) do list[i] = { index = i, label = o.label, icon = o.icon } end
    local sig = ('%s|%d|%d'):format(active and '1' or '0', current.selected, #list)
    for i = 1, #list do sig = sig .. '|' .. current.options[i].key end
    if not force and sig == current.sig then return end
    current.sig = sig
    SendNUIMessage({ action = 'target:state', data = { active = active, options = list, selected = current.selected } })
end

local function clear()
    current.options, current.selected, current.entity, current.coords = {}, 1, 0, nil
    pushOverlay()
end

---------------------------------------------------------------------------
-- Camera ray
---------------------------------------------------------------------------
local function rotToDir(rot)
    local z, x = math.rad(rot.z), math.rad(rot.x)
    local num = math.abs(math.cos(x))
    return vector3(-math.sin(z) * num, math.cos(z) * num, math.sin(x))
end

local rayHandle = nil
local lastHit = { hit = false, coords = nil, entity = 0 }

local function updateRay(ped)
    if rayHandle then
        local status, hit, endCoords, _, entity = GetShapeTestResult(rayHandle)
        if status == 1 then return end -- still pending: keep using the previous result
        rayHandle = nil
        if status == 2 then lastHit = { hit = hit == 1 or hit == true, coords = endCoords, entity = entity or 0 } end
    end
    local cam = GetFinalRenderedCamCoord()
    local dest = cam + rotToDir(GetFinalRenderedCamRot(2)) * TargetConfig.MaxRayDistance
    rayHandle = StartShapeTestLosProbe(cam.x, cam.y, cam.z, dest.x, dest.y, dest.z, 511, ped, 4)
end

---------------------------------------------------------------------------
-- Option collection
---------------------------------------------------------------------------
local function entityKind(entity)
    local t = GetEntityType(entity)
    if t == 1 then return IsPedAPlayer(entity) and 'player' or 'ped' end
    if t == 2 then return 'vehicle' end
    if t == 3 then return 'object' end
    return nil
end

local function allowed(opt, entity, distance, coords, zoneId)
    if distance > opt.distance then return false end
    if not Adapters.hasGroups(opt.groups) then return false end
    if not Adapters.hasItems(opt.items) then return false end
    if opt.canInteract then
        local ok, r = pcall(opt.canInteract, entity, distance, coords, opt.name, zoneId)
        if not ok or r == false or r == nil then return false end
    end
    return true
end

local function collect(ped)
    local pos = GetEntityCoords(ped)
    local found = {}
    local entity = lastHit.hit and lastHit.entity or 0
    local hitCoords = lastHit.hit and lastHit.coords or nil
    local distance = hitCoords and #(pos - hitCoords) or math.huge

    local function consider(bucket, ent, zoneId)
        if not bucket then return end
        for _, opt in pairs(bucket) do
            if allowed(opt, ent, distance, hitCoords, zoneId) then
                found[#found + 1] = { opt = opt, distance = distance }
            end
        end
    end

    if entity ~= 0 and DoesEntityExist(entity) then
        local kind = entityKind(entity)
        consider(Registry.localEntities[entity], entity)
        if NetworkGetEntityIsNetworked(entity) then consider(Registry.entities[NetworkGetNetworkIdFromEntity(entity)], entity) end
        consider(Registry.models[GetEntityModel(entity)], entity)
        if kind then consider(Registry.globals[kind], entity) end
    else
        entity = 0
    end

    if hitCoords then
        for _, z in ipairs(nearbyZones) do
            if Registry.zones[z.id] == z and z.zone:contains(hitCoords) then consider(z.options, entity, z.id) end
        end
    end

    -- Deterministic order: priority, then hit distance, then registration order.
    table.sort(found, function(a, b)
        if a.opt.priority ~= b.opt.priority then return a.opt.priority > b.opt.priority end
        if a.distance ~= b.distance then return a.distance < b.distance end
        return a.opt.order < b.opt.order
    end)
    local list = {}
    for i, f in ipairs(found) do list[i] = f.opt end
    return list, entity, hitCoords, distance
end

---------------------------------------------------------------------------
-- Dispatch: exactly one declared action
---------------------------------------------------------------------------
local function dispatch(opt, entity, coords, distance)
    local data = { entity = entity, coords = coords, distance = distance, name = opt.name, args = opt.args }
    local ok, err = pcall(function()
        if opt.action == 'onSelect' then
            opt.handler(data)
        elseif opt.action == 'export' then
            local res, fn = tostring(opt.handler):match('^([^.]+)%.(.+)$')
            if not res then error('export must be "resource.exportName"') end
            exports[res][fn](nil, data)
        elseif opt.action == 'event' then
            TriggerEvent(opt.handler, data)
        elseif opt.action == 'serverEvent' then
            -- Local entity handles mean nothing to the server: send a network id or 0.
            local netId = (entity ~= 0 and NetworkGetEntityIsNetworked(entity)) and NetworkGetNetworkIdFromEntity(entity) or 0
            TriggerServerEvent(opt.handler, { netId = netId, coords = coords, name = opt.name, args = opt.args })
        elseif opt.action == 'command' then
            ExecuteCommand(opt.handler)
        end
    end)
    if not ok then print(('^1[veyl_target] option %s failed: %s^7'):format(opt.key, tostring(err))) end
end

---------------------------------------------------------------------------
-- Loop
---------------------------------------------------------------------------
local function setActive(v)
    if active == v then return end
    active = v
    if not v then clear() else pushOverlay(true) end
end


-- Nearby zone index refresh (cheap, twice a second).
CreateThread(function()
    while true do
        local pos = GetEntityCoords(PlayerPedId())
        local list = {}
        for _, z in pairs(Registry.zones) do
            if z.zone:distance(pos) <= TargetConfig.ZoneScanRadius then list[#list + 1] = z end
        end
        nearbyZones = list
        Wait(500)
    end
end)

CreateThread(function()
    while true do
        if not active then
            Wait(100)
        else
            local ped = PlayerPedId()
            if disabled or IsEntityDead(ped) or IsPauseMenuActive() or exports.veyl_lib:IsModalOpen() then
                setActive(false)
            else
                DisableControlAction(0, 24, true)  -- attack
                DisableControlAction(0, 25, true)  -- aim
                DisableControlAction(0, 14, true)  -- weapon wheel next
                DisableControlAction(0, 15, true)  -- weapon wheel prev
                DisableControlAction(0, 16, true)
                DisableControlAction(0, 17, true)
                DisableControlAction(0, 37, true)  -- weapon select
                DisablePlayerFiring(PlayerId(), true)

                updateRay(ped)
                local list, entity, coords, distance = collect(ped)
                current.options, current.entity, current.coords = list, entity, coords
                if current.selected > #list then current.selected = math.max(1, #list) end

                if #list > 1 then
                    if IsDisabledControlJustPressed(0, 14) or IsControlJustPressed(0, 173) then
                        current.selected = current.selected % #list + 1
                    elseif IsDisabledControlJustPressed(0, 15) or IsControlJustPressed(0, 172) then
                        current.selected = (current.selected - 2) % #list + 1
                    end
                end
                pushOverlay()

                if #list > 0 and (IsControlJustPressed(0, 38) or IsDisabledControlJustPressed(0, 24)) then
                    local opt = list[current.selected]
                    if not toggleMode then active = false end
                    setActive(false) -- close the overlay before any action opens a modal
                    dispatch(opt, entity, coords, distance)
                end
            end
            Wait(0)
        end
    end
end)

---------------------------------------------------------------------------
-- Exports (client)
---------------------------------------------------------------------------
local function owner() return GetInvokingResource() or GetCurrentResourceName() end

exports('addSphereZone', function(data) return Registry.addZone(owner(), 'sphere', data) end)
exports('addBoxZone', function(data) return Registry.addZone(owner(), 'box', data) end)
exports('removeZone', function(id) Registry.removeZone(id) end)
exports('zoneExists', function(id) return Registry.zones[id] ~= nil end)
exports('addEntity', function(netIds, options) Registry.addEntity(owner(), netIds, options) end)
exports('removeEntity', function(netIds, names) Registry.removeEntity(owner(), netIds, names) end)
exports('addLocalEntity', function(handles, options) Registry.addLocalEntity(owner(), handles, options) end)
exports('removeLocalEntity', function(handles, names) Registry.removeLocalEntity(owner(), handles, names) end)
exports('addModel', function(models, options) Registry.addModel(owner(), models, options) end)
exports('removeModel', function(models, names) Registry.removeModel(owner(), models, names) end)
for _, kind in ipairs({ 'Ped', 'Vehicle', 'Object', 'Player' }) do
    exports('addGlobal' .. kind, function(options) Registry.addGlobal(owner(), kind:lower(), options) end)
    exports('removeGlobal' .. kind, function(names) Registry.removeGlobal(owner(), kind:lower(), names) end)
end
exports('disableTargeting', function(value)
    disabled = value == true
    if disabled then setActive(false) end
end)
exports('isActive', function() return active end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then return end
    Registry.removeOwner(res)
end)

-- A broker reset (veyl_lib restart) closes the overlay.
AddEventHandler('veyl_lib:brokerReset', function() setActive(false) end)

RegisterNUICallback('ui:ready', function(_, cb)
    cb({ ok = true })
    pushOverlay(true)
end)

-- Registered last so an input-setup problem can never prevent the exports above from existing.
vlib.addKeybind({
    name = 'veyl_target', description = 'Target / interact', defaultKey = TargetConfig.DefaultKey,
    onPressed = function()
        if toggleMode then setActive(not active) else setActive(true) end
    end,
    onReleased = function()
        if not toggleMode then setActive(false) end
    end,
})
