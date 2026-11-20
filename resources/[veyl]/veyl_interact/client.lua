-- veyl_interact: the single interaction API for VeylCore resources.
--
-- AddZone({ id, coords = vector3, radius = 2.0, label, icon, event, args, groups, options = { { label, icon, event, args, groups, canInteract, onSelect } } })
-- AddPed({ id, model, coords = vector4, scenario, radius, label/options... })
-- AddEntity({ id, netId, radius, label/options... })
-- Remove(id)
--
-- Selecting an option triggers a LOCAL client event (preferred) or calls onSelect. Servers must still validate
-- every resulting request; client-side checks (distance, groups) are presentation only.

local useTarget = InteractConfig.Provider == 'ox_target' and GetResourceState('ox_target') == 'started'
local useEKey = not useTarget or InteractConfig.EKeyAlongsideTarget

local zones = {}   -- [id] = def
local peds = {}    -- [id] = { handle, def }
local busy = false

local function owner() return GetInvokingResource() or GetCurrentResourceName() end

-- Group filters checked against VeylCore PlayerData (ox_target's own `groups` is not enforced under VeylCore).
local function hasGroup(filter)
    if not filter then return true end
    local pd = exports.veyl_core:GetPlayerData() or {}
    local groups = {}
    for k, v in pairs(pd.jobs or {}) do groups[k] = v end
    for k, v in pairs(pd.gangs or {}) do groups[k] = v end
    if type(filter) == 'string' then return groups[filter] ~= nil end
    if filter[1] ~= nil then
        for _, n in ipairs(filter) do if groups[n] ~= nil then return true end end
        return false
    end
    for name, minGrade in pairs(filter) do
        if groups[name] ~= nil and groups[name] >= (tonumber(minGrade) or 0) then return true end
    end
    return false
end

local function optionAllowed(o)
    if not hasGroup(o.groups) then return false end
    if o.canInteract then
        local ok, r = pcall(o.canInteract)
        return ok and r ~= false
    end
    return true
end

local function fire(o)
    if o.onSelect then
        local ok, err = pcall(o.onSelect, o.args)
        if not ok then print(('^1[veyl_interact] onSelect error: %s^7'):format(tostring(err))) end
    elseif o.event then
        TriggerEvent(o.event, o.args)
    end
end

local function normalise(def)
    assert(type(def) == 'table' and def.id, 'interaction requires an id')
    def.radius = def.radius or 2.0
    def.owner = def.owner or owner()
    if not def.options then
        def.options = { { label = def.label or 'Interact', icon = def.icon, event = def.event, args = def.args,
            onSelect = def.onSelect, canInteract = def.canInteract, groups = def.groups } }
    end
    return def
end

local function targetOptions(def)
    local list = {}
    for i, o in ipairs(def.options) do
        list[i] = {
            name = ('%s:%d'):format(def.id, i),
            label = o.label or 'Interact',
            icon = o.icon or InteractConfig.DefaultIcon,
            distance = math.max(1.5, def.radius),
            canInteract = function() return Veyl.IsLoaded() and optionAllowed(o) end,
            onSelect = function() fire(o) end,
        }
    end
    return list
end

local function optionNames(def)
    local names = {}
    for i = 1, #def.options do names[i] = ('%s:%d'):format(def.id, i) end
    return names
end

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------
local function removeInternal(id)
    local def = zones[id]
    zones[id] = nil
    local p = peds[id]
    if p then
        if useTarget and p.handle then pcall(function() exports.ox_target:removeLocalEntity(p.handle, optionNames(p.def)) end) end
        if p.handle and DoesEntityExist(p.handle) then DeleteEntity(p.handle) end
        peds[id] = nil
    end
    if def and useTarget then
        if def.kind == 'zone' and def.targetId then
            pcall(function() exports.ox_target:removeZone(def.targetId, true) end)
        elseif def.kind == 'entity' and def.netId then
            pcall(function() exports.ox_target:removeEntity(def.netId, optionNames(def)) end)
        end
    end
end

exports('AddZone', function(def)
    def = normalise(def)
    if zones[def.id] then removeInternal(def.id) end
    def.kind = 'zone'
    zones[def.id] = def
    if useTarget then
        def.targetId = exports.ox_target:addSphereZone({
            coords = vector3(def.coords.x, def.coords.y, def.coords.z), radius = def.radius, debug = false,
            options = targetOptions(def),
        })
    end
    return def.id
end)

exports('AddEntity', function(def)
    def = normalise(def)
    if zones[def.id] then removeInternal(def.id) end
    def.kind = 'entity'
    zones[def.id] = def
    if useTarget and def.netId then exports.ox_target:addEntity(def.netId, targetOptions(def)) end
    return def.id
end)

exports('AddPed', function(def)
    def = normalise(def)
    if zones[def.id] then removeInternal(def.id) end
    def.kind = 'ped'
    zones[def.id] = def
    peds[def.id] = { handle = nil, def = def }
    return def.id
end)

exports('Remove', function(id) removeInternal(id) end)

---------------------------------------------------------------------------
-- Ped streaming: local peds spawn near the player and despawn far away
---------------------------------------------------------------------------
CreateThread(function()
    while true do
        local pos = GetEntityCoords(PlayerPedId())
        for id, p in pairs(peds) do
            local c = p.def.coords
            local dist = #(pos - vector3(c.x, c.y, c.z))
            if dist < 80.0 and not (p.handle and DoesEntityExist(p.handle)) then
                local hash = Veyl.LoadModel(p.def.model or 's_m_m_postal_01', 5000)
                if hash and peds[id] == p then
                    local ped = CreatePed(4, hash, c.x, c.y, c.z - 1.0, c.w or 0.0, false, true)
                    SetEntityAsMissionEntity(ped, true, true)
                    SetBlockingOfNonTemporaryEvents(ped, true)
                    SetEntityInvincible(ped, true)
                    FreezeEntityPosition(ped, true)
                    SetPedCanRagdoll(ped, false)
                    if p.def.scenario then TaskStartScenarioInPlace(ped, p.def.scenario, 0, true) end
                    SetModelAsNoLongerNeeded(hash)
                    p.handle = ped
                    if useTarget then exports.ox_target:addLocalEntity(ped, targetOptions(p.def)) end
                end
            elseif dist > 100.0 and p.handle then
                if useTarget then pcall(function() exports.ox_target:removeLocalEntity(p.handle, optionNames(p.def)) end) end
                if DoesEntityExist(p.handle) then DeleteEntity(p.handle) end
                p.handle = nil
            end
        end
        Wait(1000)
    end
end)

---------------------------------------------------------------------------
-- E-key provider (fallback, or alongside ox_target when configured)
---------------------------------------------------------------------------
local function zonePosition(z)
    if z.kind == 'entity' then
        if z.netId and NetworkDoesNetworkIdExist(z.netId) then
            local ent = NetworkGetEntityFromNetworkId(z.netId)
            if ent and DoesEntityExist(ent) then return GetEntityCoords(ent) end
        end
        return nil
    end
    return vector3(z.coords.x, z.coords.y, z.coords.z)
end

if useEKey then
    CreateThread(function()
        while true do
            local sleep = 400
            local ped = PlayerPedId()
            if Veyl.IsLoaded() and not IsEntityDead(ped) and not IsPauseMenuActive() then
                local pos = GetEntityCoords(ped)
                local best, bestDist = nil, 1e9
                local inVehicle = IsPedInAnyVehicle(ped, false)
                for _, z in pairs(zones) do
                    if not inVehicle or z.allowInVehicle then
                        local zp = zonePosition(z)
                        if zp then
                            local dist = #(pos - zp)
                            if dist < 15.0 then sleep = 0 end
                            if dist <= z.radius and dist < bestDist then best, bestDist = z, dist end
                        end
                    end
                end
                if best and not busy and not exports.veyl_ui:IsModalOpen() then
                    local options = {}
                    for _, o in ipairs(best.options) do if optionAllowed(o) then options[#options + 1] = o end end
                    if #options > 0 then
                        Veyl.HelpText('~INPUT_CONTEXT~ ' .. (#options == 1 and options[1].label or (best.label or 'Interact')))
                        if IsControlJustReleased(0, 38) then
                            busy = true
                            CreateThread(function()
                                if #options == 1 then
                                    fire(options[1])
                                else
                                    local items = {}
                                    for i, o in ipairs(options) do items[i] = { label = o.label, value = i } end
                                    local idx = Veyl.UI.Menu({ title = best.label or 'Interact', items = items })
                                    if idx and options[idx] then fire(options[idx]) end
                                end
                                Wait(300)
                                busy = false
                            end)
                        end
                    end
                end
            end
            Wait(sleep)
        end
    end)
end

---------------------------------------------------------------------------
-- Cleanup when an owning resource stops
---------------------------------------------------------------------------
AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        for id in pairs(zones) do removeInternal(id) end
        return
    end
    for id, z in pairs(zones) do
        if z.owner == res then removeInternal(id) end
    end
end)
