-- Ground drops on the client: a local bag prop near each drop and a "Ground" target zone that opens the inventory
-- (which shows the nearest drop in the right-hand box). The server decides what is in a drop and who may reach it.

local drops = {} -- [id] = { id, coords, prop, zone }
local SPAWN_RANGE = 60.0

local function addZone(d)
    if GetResourceState('veyl_target') ~= 'started' then return end
    d.zone = exports.veyl_target:addSphereZone({
        name = 'veyl_drop_' .. d.id, title = 'Ground', coords = d.coords + vector3(0.0, 0.0, 0.3), radius = 1.0,
        options = { { name = 'veyl_drop_open_' .. d.id, label = 'Pick up items', icon = 'hand', distance = InventoryConfig.DropDistance,
            onSelect = function() CreateThread(function() OpenInventory(nil) end) end } },
    })
end

local function removeDrop(id)
    local d = drops[id]
    if not d then return end
    if d.prop and DoesEntityExist(d.prop) then DeleteEntity(d.prop) end
    if d.zone and GetResourceState('veyl_target') == 'started' then exports.veyl_target:removeZone(d.zone) end
    drops[id] = nil
end

local function addDrop(info)
    if drops[info.id] then return end
    local c = info.coords
    local d = { id = info.id, coords = vector3(c.x, c.y, c.z) }
    drops[info.id] = d
    addZone(d)
end

RegisterNetEvent('veyl_inventory:drops:sync', function(list)
    for id in pairs(drops) do removeDrop(id) end
    for _, info in ipairs(list or {}) do addDrop(info) end
end)
RegisterNetEvent('veyl_inventory:drops:add', addDrop)
RegisterNetEvent('veyl_inventory:drops:remove', removeDrop)

-- Bag props only exist while you are near (local, non-networked objects).
CreateThread(function()
    local model = joaat(InventoryConfig.DropProp)
    while true do
        local pos = GetEntityCoords(PlayerPedId())
        for _, d in pairs(drops) do
            local near = #(pos - d.coords) < SPAWN_RANGE
            if near and not (d.prop and DoesEntityExist(d.prop)) then
                RequestModel(model)
                local timeout = GetGameTimer() + 3000
                while not HasModelLoaded(model) and GetGameTimer() < timeout do Wait(10) end
                if HasModelLoaded(model) and drops[d.id] then
                    d.prop = CreateObject(model, d.coords.x, d.coords.y, d.coords.z + 0.2, false, false, false)
                    PlaceObjectOnGroundProperly(d.prop)
                    FreezeEntityPosition(d.prop, true)
                    SetEntityCollision(d.prop, false, false)
                    SetModelAsNoLongerNeeded(model)
                end
            elseif not near and d.prop then
                if DoesEntityExist(d.prop) then DeleteEntity(d.prop) end
                d.prop = nil
            end
        end
        Wait(1000)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, d in pairs(drops) do if d.prop and DoesEntityExist(d.prop) then DeleteEntity(d.prop) end end
end)
