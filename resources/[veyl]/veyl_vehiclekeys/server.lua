-- veyl_vehiclekeys server: the single key provider. Grants are keyed by veyl_vehicles' vehicle id and citizenid.
-- The entity state bag 'veylKeys' mirrors grants for display/driving checks only; the server map is the authority.

local keys = {} -- [vehicleId] = { [citizenid] = true }

Veyl.Startup({ 'veyl_core', 'veyl_vehicles' }, function() return true end)

local function sync(vehicleId)
    local entity = exports.veyl_vehicles:GetEntity(vehicleId)
    if not entity or not DoesEntityExist(entity) then return end
    local list = {}
    for cid in pairs(keys[vehicleId] or {}) do list[#list + 1] = cid end
    Entity(entity).state:set('veylKeys', list, true)
end

exports('GiveKey', function(vehicleId, citizenid)
    if type(vehicleId) ~= 'string' or type(citizenid) ~= 'string' then return false end
    keys[vehicleId] = keys[vehicleId] or {}
    keys[vehicleId][citizenid] = true
    sync(vehicleId)
    return true
end)

exports('RevokeKey', function(vehicleId, citizenid)
    if not keys[vehicleId] then return false end
    keys[vehicleId][citizenid] = nil
    sync(vehicleId)
    return true
end)

exports('HasKey', function(vehicleId, citizenid)
    return keys[vehicleId] ~= nil and keys[vehicleId][citizenid] == true
end)

AddEventHandler('veyl_vehicles:removed', function(vehicleId) keys[vehicleId] = nil end)

Veyl.RegisterCallback('toggleLock', function(src, citizenid, netId)
    if not Veyl.Validate.int(netId, 1) then return Veyl.Err('INVALID_INPUT', 'Invalid vehicle') end
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return Veyl.Err('NOT_FOUND', 'Vehicle not found') end
    local vehicleId = exports.veyl_vehicles:GetVehicleIdFromEntity(entity)
    if not vehicleId or not (keys[vehicleId] and keys[vehicleId][citizenid]) then
        return Veyl.Err('NO_PERMISSION', 'You do not have keys to this vehicle')
    end
    local pc = Veyl.GetPlayerCoords(src)
    if not pc or #(pc - GetEntityCoords(entity)) > KeysConfig.LockDistance then return Veyl.Err('TOO_FAR', 'Too far away') end
    local locked = GetVehicleDoorLockStatus(entity) >= 2
    SetVehicleDoorsLocked(entity, locked and 1 or 2)
    TriggerClientEvent('veyl_vehiclekeys:lockFeedback', src, netId, not locked)
    return Veyl.Ok({ locked = not locked }, locked and 'Vehicle unlocked' or 'Vehicle locked')
end, { cooldown = 750 })
