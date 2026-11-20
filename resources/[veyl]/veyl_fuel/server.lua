-- veyl_fuel server: the single fuel provider for VeylCore vehicles. Fuel is server-held and mirrored to the
-- entity state bag 'veylFuel' for display.

local tracked = {} -- [vehicleId] = { entity, fuel }

Veyl.Startup({ 'veyl_core', 'veyl_vehicles' }, function() return true end)

AddEventHandler('veyl_vehicles:spawned', function(vehicleId, entity, info)
    local fuel = math.max(0.0, math.min(100.0, tonumber(info and info.fuel) or 100.0))
    tracked[vehicleId] = { entity = entity, fuel = fuel }
    Entity(entity).state:set('veylFuel', fuel, true)
end)

AddEventHandler('veyl_vehicles:removed', function(vehicleId) tracked[vehicleId] = nil end)

exports('GetFuel', function(vehicleId) return tracked[vehicleId] and tracked[vehicleId].fuel or nil end)
exports('SetFuel', function(vehicleId, value)
    local t = tracked[vehicleId]
    if not t then return false end
    t.fuel = math.max(0.0, math.min(100.0, tonumber(value) or t.fuel))
    if DoesEntityExist(t.entity) then Entity(t.entity).state:set('veylFuel', t.fuel, true) end
    return true
end)

CreateThread(function()
    while true do
        Wait(FuelConfig.TickMs)
        for id, t in pairs(tracked) do
            if not DoesEntityExist(t.entity) then
                tracked[id] = nil
            elseif t.fuel > 0 and GetIsVehicleEngineRunning(t.entity) then
                local vel = GetEntityVelocity(t.entity)
                local speed = math.sqrt(vel.x * vel.x + vel.y * vel.y + vel.z * vel.z)
                t.fuel = math.max(0.0, t.fuel - FuelConfig.IdleUse - speed * FuelConfig.SpeedUse)
                Entity(t.entity).state:set('veylFuel', t.fuel, true)
            end
        end
    end
end)

Veyl.RegisterCallback('refuel', function(src, citizenid, netId)
    if not Veyl.Validate.int(netId, 1) then return Veyl.Err('INVALID_INPUT', 'Invalid vehicle') end
    local entity = NetworkGetEntityFromNetworkId(netId)
    local vehicleId = entity and exports.veyl_vehicles:GetVehicleIdFromEntity(entity)
    local t = vehicleId and tracked[vehicleId]
    if not t then return Veyl.Err('NOT_FOUND', 'This vehicle cannot be refuelled here') end
    local pc, vc = Veyl.GetPlayerCoords(src), GetEntityCoords(entity)
    if not pc or #(pc - vc) > 6.0 then return Veyl.Err('TOO_FAR', 'Stand next to the vehicle') end
    local atStation = false
    for _, s in ipairs(FuelConfig.Stations) do
        if #(vc - s) <= FuelConfig.StationRadius then atStation = true break end
    end
    if not atStation then return Veyl.Err('TOO_FAR', 'Park at a fuel pump') end
    local units = math.floor(100 - t.fuel)
    if units < 1 then return Veyl.Err('INVALID_STATE', 'The tank is already full') end
    local cost = units * FuelConfig.PricePerUnit
    local pay = Veyl.Await('veyl_core', 'DebitOnce', 15000, citizenid, 'cash', cost, 'Fuel purchase', Veyl.NewId('fuel'))
    if not pay.ok then return pay end
    t.fuel = math.min(100.0, t.fuel + units)
    Entity(entity).state:set('veylFuel', t.fuel, true)
    return Veyl.Ok({ fuel = t.fuel }, ('Refuelled for $%d'):format(cost))
end, { cooldown = 3000 })
