-- veyl_vehicles server: the only resource that spawns VeylCore vehicles. Every spawned vehicle gets a stable
-- runtime id, a cleanup owner (the requesting resource) and lifecycle events. Keys and fuel are separate
-- providers (veyl_vehiclekeys, veyl_fuel) that react to these events.

local vehicles = {}   -- [vehicleId] = { id, entity, netId, plate, owner, temporary, citizenid, ownedId }
local byEntity = {}   -- [entity] = vehicleId
local nextId = 0

Veyl.Startup({ 'veyl_core' }, function()
    return Veyl.Migrate({
        {
            id = '001_player_vehicles',
            sql = {
                -- Owned vehicles (garages/dealership in later milestones). ox_inventory stores glovebox/trunk here.
                [[CREATE TABLE IF NOT EXISTS veyl_player_vehicles (
                    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                    citizenid VARCHAR(16) NOT NULL,
                    model VARCHAR(64) NOT NULL,
                    plate VARCHAR(8) NOT NULL,
                    props LONGTEXT NULL,
                    state ENUM('out','garaged','impound') NOT NULL DEFAULT 'garaged',
                    garage VARCHAR(64) NULL,
                    fuel FLOAT NOT NULL DEFAULT 100,
                    engine FLOAT NOT NULL DEFAULT 1000,
                    body FLOAT NOT NULL DEFAULT 1000,
                    glovebox LONGTEXT NULL,
                    trunk LONGTEXT NULL,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (id),
                    UNIQUE KEY uq_plate (plate),
                    KEY idx_citizen (citizenid)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            },
        },
    })
end)

local function removeTracking(id, reason, deleteEntity)
    local v = vehicles[id]
    if not v then return false end
    vehicles[id] = nil
    byEntity[v.entity] = nil
    if deleteEntity and DoesEntityExist(v.entity) then DeleteEntity(v.entity) end
    TriggerEvent('veyl_vehicles:removed', id, reason)
    return true
end

local function makePlate(prefix)
    local p = (prefix or 'VEYL'):upper():gsub('[^A-Z0-9]', ''):sub(1, 4)
    return ('%s%04d'):format(p, math.random(0, 9999))
end

local function spawnVehicle(req, owner)
    if type(req) ~= 'table' or type(req.model) ~= 'string' or not req.coords then
        return Veyl.Err('INVALID_INPUT', 'Invalid spawn request')
    end
    local c = req.coords
    local entity = CreateVehicleServerSetter(joaat(req.model), req.vehicleType or 'automobile', c.x, c.y, c.z, c.w or 0.0)
    local deadline = GetGameTimer() + 5000
    while not DoesEntityExist(entity) do
        if GetGameTimer() > deadline then return Veyl.Err('TIMEOUT', 'Vehicle did not spawn') end
        Wait(25)
    end
    nextId = nextId + 1
    local id = ('v%d_%d'):format(os.time(), nextId)
    local plate = makePlate(req.platePrefix)
    SetVehicleNumberPlateText(entity, plate)
    if SetEntityOrphanMode then SetEntityOrphanMode(entity, 2) end
    local v = {
        id = id, entity = entity, netId = NetworkGetNetworkIdFromEntity(entity), plate = plate,
        owner = owner or 'veyl_vehicles', temporary = req.temporary ~= false, citizenid = req.citizenid, ownedId = req.ownedId,
    }
    vehicles[id] = v
    byEntity[entity] = id
    local st = Entity(entity).state
    st:set('veylVehicleId', id, true)
    if req.ownedId then st:set('veylOwnedId', req.ownedId, true) end
    TriggerEvent('veyl_vehicles:spawned', id, entity, { citizenid = req.citizenid, fuel = req.fuel, temporary = v.temporary })
    if req.citizenid and GetResourceState('veyl_vehiclekeys') == 'started' then
        exports.veyl_vehiclekeys:GiveKey(id, req.citizenid)
    end
    return Veyl.Ok({ vehicleId = id, netId = v.netId, plate = plate })
end

--- SpawnAuthorizedVehicle({ model, coords = vector4, citizenid?, temporary = true, platePrefix?, fuel?, vehicleType?, ownedId? }, cb)
--- Call with Veyl.Await. -> Ok({ vehicleId, netId, plate }). The calling resource becomes the cleanup owner:
--- its temporary vehicles are removed when it stops.
exports('SpawnAuthorizedVehicle', function(req, cb)
    local owner = GetInvokingResource()
    CreateThread(function()
        if not Veyl.IsReady() then return cb(Veyl.Err('NOT_READY', 'Vehicle service not ready')) end
        local ok, res = pcall(spawnVehicle, req, owner)
        if not ok then
            print(('^1[veyl_vehicles] spawn error: %s^7'):format(tostring(res)))
            res = Veyl.Err('INTERNAL', 'internal error')
        end
        cb(res)
    end)
end)

exports('DeleteVehicle', function(id) return removeTracking(id, 'deleted', true) end)

exports('GetVehicle', function(id)
    local v = vehicles[id]
    if not v then return nil end
    local exists = DoesEntityExist(v.entity)
    return { vehicleId = v.id, netId = v.netId, plate = v.plate, exists = exists, citizenid = v.citizenid,
        coords = exists and GetEntityCoords(v.entity) or nil }
end)

exports('GetVehicleIdFromEntity', function(entity) return byEntity[entity] end)
exports('GetEntity', function(id) local v = vehicles[id]; return v and v.entity or nil end)

-- Destruction / disappearance monitoring.
CreateThread(function()
    while true do
        Wait(3000)
        for id, v in pairs(vehicles) do
            if not DoesEntityExist(v.entity) then
                removeTracking(id, 'missing', false)
            elseif not v.destroyed and (GetVehicleEngineHealth(v.entity) <= -3900.0 or GetEntityHealth(v.entity) <= 0) then
                v.destroyed = true
                TriggerEvent('veyl_vehicles:destroyed', id)
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    for id, v in pairs(vehicles) do
        if res == GetCurrentResourceName() or (v.owner == res and v.temporary) then
            removeTracking(id, 'owner_stopped', true)
        end
    end
end)
