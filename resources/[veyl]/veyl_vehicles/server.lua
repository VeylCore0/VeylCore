-- veyl_vehicles server: the only resource that spawns VeylCore vehicles. Every vehicle it spawns
-- has a stable vehicle id, a cleanup owner (the requesting resource) and server-held key grants.

local vehicles = {}   -- [vehicleId] = { entity, netId, plate, keys = { [charId] = true }, owner, temporary, fuel }
local byEntity = {}   -- [entity] = vehicleId
local nextId = 0

Veyl.Startup({ 'veyl_core' }, function() return true end)

local function keyList(v)
    local list = {}
    for charId in pairs(v.keys) do list[#list + 1] = charId end
    return list
end

local function syncState(v)
    if not DoesEntityExist(v.entity) then return end
    local st = Entity(v.entity).state
    st:set('veylId', v.id, true)
    st:set('veylKeys', keyList(v), true)
    st:set('veylFuel', v.fuel, true)
end

local function deleteVehicle(id, reason)
    local v = vehicles[id]
    if not v then return false end
    vehicles[id] = nil
    byEntity[v.entity] = nil
    if DoesEntityExist(v.entity) then DeleteEntity(v.entity) end
    TriggerEvent('veyl_vehicles:removed', id, reason or 'deleted')
    return true
end

local function makePlate(prefix)
    local p = (prefix or 'VEYL'):upper():gsub('[^A-Z0-9]', ''):sub(1, 4)
    return ('%s%04d'):format(p, math.random(0, 9999))
end

--- SpawnAuthorizedVehicle({ model, coords = vector4, characterId, temporary = true, platePrefix, fuel, vehicleType })
--- -> Ok({ vehicleId, netId, plate }). The caller resource owns cleanup; its vehicles are removed when it stops.
Veyl.AsyncExport('SpawnAuthorizedVehicle', function(req)
    if type(req) ~= 'table' or type(req.model) ~= 'string' or not req.coords then
        return Veyl.Err('INVALID_INPUT', 'Invalid spawn request')
    end
    local c = req.coords
    local hash = joaat(req.model)
    local entity = CreateVehicleServerSetter(hash, req.vehicleType or 'automobile', c.x, c.y, c.z, c.w or 0.0)
    local deadline = GetGameTimer() + 5000
    while not DoesEntityExist(entity) do
        if GetGameTimer() > deadline then return Veyl.Err('TIMEOUT', 'Vehicle did not spawn') end
        Wait(25)
    end
    nextId = nextId + 1
    local id = ('v%d_%d'):format(os.time(), nextId)
    local plate = makePlate(req.platePrefix)
    SetVehicleNumberPlateText(entity, plate)
    if SetEntityOrphanMode then
        SetEntityOrphanMode(entity, 2) -- keep the entity if its owner client leaves; we clean it up ourselves
    end
    local v = {
        id = id, entity = entity, netId = NetworkGetNetworkIdFromEntity(entity), plate = plate, keys = {},
        owner = GetInvokingResource() or 'veyl_vehicles', temporary = req.temporary ~= false,
        fuel = tonumber(req.fuel) or 100.0,
    }
    if req.characterId then v.keys[req.characterId] = true end
    vehicles[id] = v
    byEntity[entity] = id
    syncState(v)
    return Veyl.Ok({ vehicleId = id, netId = v.netId, plate = plate })
end)

exports('DeleteVehicle', function(id) return deleteVehicle(id, 'deleted') end)

exports('GiveKey', function(id, charId)
    local v = vehicles[id]
    if not v or not charId then return false end
    v.keys[charId] = true
    syncState(v)
    return true
end)

exports('RevokeKey', function(id, charId)
    local v = vehicles[id]
    if not v then return false end
    v.keys[charId] = nil
    syncState(v)
    return true
end)

exports('HasKey', function(id, charId)
    local v = vehicles[id]
    return v ~= nil and v.keys[charId] == true
end)

exports('GetVehicle', function(id)
    local v = vehicles[id]
    if not v then return nil end
    return { vehicleId = v.id, netId = v.netId, plate = v.plate, fuel = v.fuel, exists = DoesEntityExist(v.entity),
        coords = DoesEntityExist(v.entity) and GetEntityCoords(v.entity) or nil }
end)

---------------------------------------------------------------------------
-- Locks
---------------------------------------------------------------------------
Veyl.RegisterCallback('toggleLock', function(src, charId, netId)
    if not Veyl.Validate.int(netId, 1) then return Veyl.Err('INVALID_INPUT', 'Invalid vehicle') end
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return Veyl.Err('NOT_FOUND', 'Vehicle not found') end
    local id = byEntity[entity]
    local v = id and vehicles[id]
    if not v or not v.keys[charId] then return Veyl.Err('NO_PERMISSION', 'You do not have keys to this vehicle') end
    local pc = Veyl.GetPlayerCoords(src)
    if not pc or #(pc - GetEntityCoords(entity)) > VehiclesConfig.LockDistance then return Veyl.Err('TOO_FAR', 'Too far away') end
    local locked = GetVehicleDoorLockStatus(entity) >= 2
    SetVehicleDoorsLocked(entity, locked and 1 or 2)
    TriggerClientEvent('veyl_vehicles:lockFeedback', src, netId, not locked)
    return Veyl.Ok({ locked = not locked }, locked and 'Vehicle unlocked' or 'Vehicle locked')
end, { cooldown = 750 })

---------------------------------------------------------------------------
-- Fuel + destruction monitoring
---------------------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(VehiclesConfig.FuelTickMs)
        for id, v in pairs(vehicles) do
            if not DoesEntityExist(v.entity) then
                vehicles[id] = nil
                byEntity[v.entity] = nil
                TriggerEvent('veyl_vehicles:removed', id, 'missing')
            elseif GetVehicleEngineHealth(v.entity) <= -3900.0 or GetEntityHealth(v.entity) <= 0 then
                if not v.destroyed then
                    v.destroyed = true
                    TriggerEvent('veyl_vehicles:destroyed', id)
                end
            elseif GetIsVehicleEngineRunning(v.entity) and v.fuel > 0 then
                local vel = GetEntityVelocity(v.entity)
                local speed = math.sqrt(vel.x * vel.x + vel.y * vel.y + vel.z * vel.z)
                v.fuel = math.max(0.0, v.fuel - VehiclesConfig.FuelIdleUse - speed * VehiclesConfig.FuelSpeedUse)
                Entity(v.entity).state:set('veylFuel', v.fuel, true)
            end
        end
    end
end)

Veyl.RegisterCallback('refuel', function(src, charId, netId)
    if not Veyl.Validate.int(netId, 1) then return Veyl.Err('INVALID_INPUT', 'Invalid vehicle') end
    local entity = NetworkGetEntityFromNetworkId(netId)
    local id = entity and byEntity[entity]
    local v = id and vehicles[id]
    if not v then return Veyl.Err('NOT_FOUND', 'This vehicle cannot be refuelled here') end
    local pc = Veyl.GetPlayerCoords(src)
    local vc = GetEntityCoords(entity)
    if not pc or #(pc - vc) > 6.0 then return Veyl.Err('TOO_FAR', 'Stand next to the vehicle') end
    local atStation = false
    for _, s in ipairs(VehiclesConfig.FuelStations) do
        if #(vc - s) <= VehiclesConfig.FuelStationRadius then atStation = true break end
    end
    if not atStation then return Veyl.Err('TOO_FAR', 'Park at a fuel pump') end
    local units = math.floor(100 - v.fuel)
    if units < 1 then return Veyl.Err('INVALID_STATE', 'The tank is already full') end
    local cost = units * VehiclesConfig.FuelPricePerUnit
    local pay = Veyl.Await('veyl_banking', 'TryDebit', 10000, charId, 'cash', cost, 'Fuel purchase', Veyl.NewId('fuel'))
    if not pay.ok then return pay end
    v.fuel = math.min(100.0, v.fuel + units)
    Entity(entity).state:set('veylFuel', v.fuel, true)
    return Veyl.Ok({ fuel = v.fuel }, ('Refuelled for $%d'):format(cost))
end, { cooldown = 3000 })

---------------------------------------------------------------------------
-- Cleanup ownership
---------------------------------------------------------------------------
AddEventHandler('onResourceStop', function(res)
    for id, v in pairs(vehicles) do
        if res == GetCurrentResourceName() or (v.owner == res and v.temporary) then
            if DoesEntityExist(v.entity) then DeleteEntity(v.entity) end
            vehicles[id] = nil
            byEntity[v.entity] = nil
        end
    end
end)
