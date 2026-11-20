-- veyl_interact: the single interaction provider.
--
-- AddZone({ id, coords = vector3, radius = 2.0, label, event, args, options = { { label, event, args } },
--           canInteract = function() return bool end, onSelect = function(args) end })
-- AddPed({ id, model, coords = vector4, scenario, label, event, args, options, radius })
-- AddEntity({ id, netId | entity, radius, label, event, args, options })
-- Remove(id)
--
-- Selecting an option triggers a LOCAL client event (preferred) or calls onSelect. Servers must still
-- validate every resulting request; client-side distance checks are UX only.

local zones = {}   -- [id] = zone
local peds = {}    -- [id] = { handle, zone }
local activeId = nil
local busy = false

local function owner() return GetInvokingResource() or GetCurrentResourceName() end

local function normalise(def)
    assert(type(def) == 'table' and def.id, 'interaction requires an id')
    def.radius = def.radius or 2.0
    def.owner = def.owner or owner()
    if not def.options then
        def.options = { { label = def.label or 'Interact', event = def.event, args = def.args, onSelect = def.onSelect, canInteract = def.canInteract } }
    end
    return def
end

exports('AddZone', function(def)
    def = normalise(def)
    def.kind = 'zone'
    zones[def.id] = def
    return def.id
end)

exports('AddEntity', function(def)
    def = normalise(def)
    def.kind = 'entity'
    zones[def.id] = def
    return def.id
end)

local function deletePed(id)
    local p = peds[id]
    if p and p.handle and DoesEntityExist(p.handle) then DeleteEntity(p.handle) end
    peds[id] = nil
end

exports('AddPed', function(def)
    def = normalise(def)
    def.kind = 'ped'
    def.coords = def.coords
    zones[def.id] = def
    peds[def.id] = { handle = nil, def = def }
    return def.id
end)

exports('Remove', function(id)
    zones[id] = nil
    deletePed(id)
end)

---------------------------------------------------------------------------
-- Ped streaming: local (non-networked) peds spawn near the player and despawn far away
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
                end
            elseif dist > 100.0 and p.handle then
                if DoesEntityExist(p.handle) then DeleteEntity(p.handle) end
                p.handle = nil
            end
        end
        Wait(1000)
    end
end)

---------------------------------------------------------------------------
-- Prompt loop
---------------------------------------------------------------------------
local function zonePosition(z)
    if z.kind == 'entity' then
        local ent = z.entity
        if z.netId and NetworkDoesNetworkIdExist(z.netId) then ent = NetworkGetEntityFromNetworkId(z.netId) end
        if ent and DoesEntityExist(ent) then return GetEntityCoords(ent) end
        return nil
    end
    return vector3(z.coords.x, z.coords.y, z.coords.z)
end

local function availableOptions(z)
    local list = {}
    for _, o in ipairs(z.options) do
        local ok = true
        if o.canInteract then
            local s, r = pcall(o.canInteract)
            ok = s and r ~= false
        end
        if ok then list[#list + 1] = o end
    end
    return list
end

local function fire(option)
    if option.onSelect then
        local ok, err = pcall(option.onSelect, option.args)
        if not ok then print(('^1[veyl_interact] onSelect error: %s^7'):format(tostring(err))) end
    elseif option.event then
        TriggerEvent(option.event, option.args)
    end
end

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
            activeId = best and best.id or nil
            if best and not busy and not exports.veyl_ui:IsModalOpen() then
                local options = availableOptions(best)
                if #options > 0 then
                    local label = #options == 1 and options[1].label or (best.label or 'Interact')
                    Veyl.HelpText('~INPUT_CONTEXT~ ' .. label)
                    if IsControlJustReleased(0, 38) then
                        busy = true
                        CreateThread(function()
                            if #options == 1 then
                                fire(options[1])
                            else
                                local items = {}
                                for i, o in ipairs(options) do items[i] = { label = o.label, description = o.description, value = i } end
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

exports('GetActive', function() return activeId end)

---------------------------------------------------------------------------
-- Cleanup when an owning resource stops
---------------------------------------------------------------------------
AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        for id in pairs(peds) do deletePed(id) end
        return
    end
    for id, z in pairs(zones) do
        if z.owner == res then
            zones[id] = nil
            deletePed(id)
        end
    end
end)
