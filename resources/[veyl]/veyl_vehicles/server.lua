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
        {
            id = '002_owned_service',
            sql = {
                -- created_op: the purchase/grant operation that created the row (one row per operation, ever).
                [[ALTER TABLE veyl_player_vehicles
                    ADD COLUMN IF NOT EXISTS label VARCHAR(64) NULL,
                    ADD COLUMN IF NOT EXISTS created_op VARCHAR(100) NULL,
                    ADD COLUMN IF NOT EXISTS impound_fee INT UNSIGNED NOT NULL DEFAULT 0,
                    ADD COLUMN IF NOT EXISTS impound_reason VARCHAR(64) NULL,
                    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP]],
                [[CREATE UNIQUE INDEX IF NOT EXISTS uq_created_op ON veyl_player_vehicles (created_op)]],
            },
        },
        {
            id = '003_insurance',
            sql = { [[ALTER TABLE veyl_player_vehicles ADD COLUMN IF NOT EXISTS insured_until DATETIME NULL]] },
        },
        {
            -- props_version: bumped by every authoritative change of the saved looks (veyl_customs purchases).
            id = '004_props_version',
            sql = { [[ALTER TABLE veyl_player_vehicles ADD COLUMN IF NOT EXISTS props_version INT UNSIGNED NOT NULL DEFAULT 0]] },
        },
    })
end)

-- Vehicles left "out" when the server stopped have no entity any more: they go back to their last garage.
CreateThread(function()
    while not Veyl.IsReady() do Wait(250) end
    local n = MySQL.update.await("UPDATE veyl_player_vehicles SET state = 'garaged' WHERE state = 'out'")
    if n and n > 0 then print(('^5[veyl_vehicles] %d vehicle(s) left out before the restart were returned to their garage^7'):format(n)) end
end)

local ownedActive = {} -- [ownedId] = vehicleId (at most one live instance per owned vehicle)

local function impoundRow(ownedId, reason, fee)
    -- Insured vehicles that were wrecked or abandoned are recovered and repaired for free (services.lua sells cover).
    local insured = MySQL.scalar.await('SELECT 1 FROM veyl_player_vehicles WHERE id = ? AND insured_until > NOW()', { ownedId })
    if insured then
        MySQL.update.await([[UPDATE veyl_player_vehicles SET state = 'impound', impound_reason = ?, impound_fee = 0, engine = 1000, body = 1000
            WHERE id = ? AND state = 'out']], { ('%s (insured)'):format(reason):sub(1, 64), ownedId })
        return
    end
    MySQL.update.await("UPDATE veyl_player_vehicles SET state = 'impound', impound_reason = ?, impound_fee = ? WHERE id = ? AND state = 'out'",
        { reason, fee, ownedId })
end

local function removeTracking(id, reason, deleteEntity)
    local v = vehicles[id]
    if not v then return false end
    vehicles[id] = nil
    byEntity[v.entity] = nil
    if deleteEntity and DoesEntityExist(v.entity) then DeleteEntity(v.entity) end
    if v.ownedId then
        ownedActive[v.ownedId] = nil
        -- An owned vehicle that disappears without being parked goes to the impound lot.
        if reason ~= 'stored' and reason ~= 'owner_stopped' then
            CreateThread(function() impoundRow(v.ownedId, reason == 'missing' and 'abandoned' or reason, VehiclesConfig.ImpoundFee) end)
        end
    end
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
    local plate = type(req.plate) == 'string' and req.plate or makePlate(req.platePrefix)
    SetVehicleNumberPlateText(entity, plate)
    if SetEntityOrphanMode then SetEntityOrphanMode(entity, 2) end
    local v = {
        id = id, entity = entity, netId = NetworkGetNetworkIdFromEntity(entity), plate = plate,
        owner = owner or 'veyl_vehicles', temporary = req.temporary ~= false, citizenid = req.citizenid, ownedId = req.ownedId,
    }
    vehicles[id] = v
    byEntity[entity] = id
    if req.ownedId then ownedActive[req.ownedId] = id end
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
--- Used by services.lua after a plate change or an ownership transfer.
exports('SetTrackedPlate', function(id, plate) local v = vehicles[id] if v then v.plate = plate end return v ~= nil end)
exports('SetTrackedOwner', function(id, citizenid) local v = vehicles[id] if v then v.citizenid = citizenid end return v ~= nil end)
exports('GetEntity', function(id) local v = vehicles[id]; return v and v.entity or nil end)

---------------------------------------------------------------------------
-- Owned vehicles (veyl_player_vehicles). Garages, the dealership and staff tools use these exports; nothing else
-- writes ownership or storage state.
---------------------------------------------------------------------------
local PLATE_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'

local function randomPlate()
    local t = {}
    for i = 1, 8 do
        local n = math.random(1, #PLATE_CHARS)
        t[i] = PLATE_CHARS:sub(n, n)
    end
    t[4] = ' ' -- e.g. "ABC 1234"-style spacing: 3 + space + 4
    return table.concat(t)
end

local function ownedRow(ownedId)
    return MySQL.single.await([[SELECT id, citizenid, model, plate, label, props, state, garage, fuel, engine, body,
        impound_fee, impound_reason FROM veyl_player_vehicles WHERE id = ?]], { ownedId })
end

local function publicRow(r)
    return { id = r.id, model = r.model, plate = r.plate, label = r.label, state = r.state, garage = r.garage,
        fuel = math.floor((r.fuel or 0) + 0.5), engine = math.floor((r.engine or 0) / 10 + 0.5), body = math.floor((r.body or 0) / 10 + 0.5),
        impoundFee = r.impound_fee or 0, impoundReason = r.impound_reason, out = ownedActive[r.id] ~= nil }
end

--- Client-supplied vehicle properties: cosmetic data only, bounded and type-checked.
local function cleanProps(p)
    if type(p) ~= 'table' then return nil end
    local ok, s = pcall(json.encode, p)
    if not ok or #s > VehiclesConfig.MaxPropsBytes then return nil end
    local function numbers(t, max)
        if type(t) ~= 'table' then return nil end
        local out = {}
        for k, v in pairs(t) do
            if #out > max then break end
            if type(v) == 'number' and v == v and math.abs(v) < 100000 then out[k] = math.floor(v) elseif type(v) == 'boolean' then out[k] = v end
        end
        return out
    end
    local out = {}
    for _, k in ipairs({ 'color1', 'color2', 'pearl', 'wheelColor', 'wheelType', 'windowTint', 'plateIndex', 'livery', 'dirt' }) do
        if type(p[k]) == 'number' and p[k] == p[k] then out[k] = math.floor(p[k]) end
    end
    out.mods = numbers(p.mods, 60)
    out.neon = numbers(p.neon, 4)
    out.neonColor = numbers(p.neonColor, 3)
    out.tyreSmoke = numbers(p.tyreSmoke, 3)
    out.toggles = numbers(p.toggles, 8)
    out.extras = numbers(p.extras, 20)
    out.customPrimary = numbers(p.customPrimary, 3)
    out.customSecondary = numbers(p.customSecondary, 3)
    for _, k in ipairs({ 'interiorColor', 'dashboardColor', 'xenonColor' }) do
        if type(p[k]) == 'number' and p[k] == p[k] then out[k] = math.floor(p[k]) end
    end
    if type(p.customTyres) == 'boolean' then out.customTyres = p.customTyres end
    return out
end
CleanVehicleProps = cleanProps

--- RegisterOwnedVehicle(citizenid, model, { label?, garage?, opId? }) -> Ok({ ownedId, plate }).
--- With opId, the same operation can never create a second vehicle (a repeat returns the first one).
Veyl.AsyncExport('RegisterOwnedVehicle', function(citizenid, model, opts)
    opts = type(opts) == 'table' and opts or {}
    if not Veyl.Validate.str(citizenid, 1, 16) or not Veyl.Validate.str(model, 1, 64, '^[%w_]+$') then
        return Veyl.Err('INVALID_INPUT', 'Invalid vehicle registration')
    end
    if opts.opId then
        local existing = MySQL.single.await('SELECT id, plate FROM veyl_player_vehicles WHERE created_op = ?', { opts.opId })
        if existing then return Veyl.Ok({ ownedId = existing.id, plate = existing.plate, existing = true }) end
    end
    for _ = 1, 8 do
        local plate = randomPlate()
        local ok, id = pcall(MySQL.insert.await, [[INSERT INTO veyl_player_vehicles (citizenid, model, plate, label, state, garage, created_op)
            VALUES (?, ?, ?, ?, 'garaged', ?, ?)]], { citizenid, model, plate, opts.label, opts.garage, opts.opId })
        if ok and id then return Veyl.Ok({ ownedId = id, plate = plate }) end
        if opts.opId then
            local existing = MySQL.single.await('SELECT id, plate FROM veyl_player_vehicles WHERE created_op = ?', { opts.opId })
            if existing then return Veyl.Ok({ ownedId = existing.id, plate = existing.plate, existing = true }) end
        end
        -- otherwise: plate collision, try another plate
    end
    return Veyl.Err('DATABASE_ERROR', 'Could not register the vehicle')
end)

--- GetOwnedVehicles(citizenid) -> list of public rows.
Veyl.AsyncExport('GetOwnedVehicles', function(citizenid)
    local rows = MySQL.query.await([[SELECT id, citizenid, model, plate, label, state, garage, fuel, engine, body, impound_fee, impound_reason
        FROM veyl_player_vehicles WHERE citizenid = ? ORDER BY id]], { citizenid }) or {}
    local list = {}
    for i, r in ipairs(rows) do list[i] = publicRow(r) end
    return Veyl.Ok(list)
end)

--- GetOwnedVehicleCoords(citizenid, ownedId) -> Ok({ x, y, z }) for the owner's vehicle while it is out on the road.
Veyl.AsyncExport('GetOwnedVehicleCoords', function(citizenid, ownedId)
    if not Veyl.Validate.int(ownedId, 1) then return Veyl.Err('INVALID_INPUT', 'Invalid vehicle') end
    local owner = MySQL.scalar.await('SELECT citizenid FROM veyl_player_vehicles WHERE id = ?', { ownedId })
    if owner ~= citizenid then return Veyl.Err('NOT_FOUND', 'Vehicle not found') end
    local vid = ownedActive[ownedId]
    local v = vid and vehicles[vid]
    if not v or not v.entity or not DoesEntityExist(v.entity) then return Veyl.Err('NOT_FOUND', 'That vehicle is not out on the road') end
    local c = GetEntityCoords(v.entity)
    return Veyl.Ok({ x = c.x, y = c.y, z = c.z })
end)

--- SpawnOwnedVehicle(src, citizenid, ownedId, coords(vector4), { from = 'garaged'|'impound', garage? })
--- Reserves the row first (state -> 'out' only if it is still where the caller says), so two requests can never
--- produce two copies. Applies saved fuel, condition and properties. -> Ok({ vehicleId, netId, plate })
Veyl.AsyncExport('SpawnOwnedVehicle', function(src, citizenid, ownedId, coords, opts)
    opts = type(opts) == 'table' and opts or {}
    if not Veyl.Validate.int(ownedId, 1) or not coords then return Veyl.Err('INVALID_INPUT', 'Invalid vehicle') end
    if ownedActive[ownedId] then return Veyl.Err('INVALID_STATE', 'That vehicle is already out') end
    local from = opts.from == 'impound' and 'impound' or 'garaged'
    local affected
    if from == 'garaged' and opts.garage then
        affected = MySQL.update.await("UPDATE veyl_player_vehicles SET state = 'out' WHERE id = ? AND citizenid = ? AND state = 'garaged' AND garage = ?",
            { ownedId, citizenid, opts.garage })
    else
        affected = MySQL.update.await("UPDATE veyl_player_vehicles SET state = 'out', impound_fee = 0, impound_reason = NULL WHERE id = ? AND citizenid = ? AND state = ?",
            { ownedId, citizenid, from })
    end
    if affected ~= 1 then return Veyl.Err('INVALID_STATE', 'That vehicle is not available here') end
    local row = ownedRow(ownedId)
    local res = spawnVehicle({
        model = row.model, coords = coords, citizenid = citizenid, temporary = false, ownedId = ownedId,
        plate = row.plate, fuel = row.fuel,
    }, GetInvokingResource())
    if not res.ok then
        -- Undo the reservation: the vehicle never left. A paid impound release stays paid: it waits at that lot as garaged.
        MySQL.update.await("UPDATE veyl_player_vehicles SET state = 'garaged', garage = COALESCE(?, garage) WHERE id = ? AND state = 'out'",
            { opts.garage, ownedId })
        return res
    end
    local okProps, props = pcall(json.decode, row.props or 'null')
    TriggerClientEvent('veyl_vehicles:applyOwned', src, res.data.netId, okProps and props or nil, row.engine, row.body)
    return res
end)

--- StoreOwnedVehicle(src, citizenid, netId, garage, props) -> Ok(). Only the owner can park it, and nobody may be inside.
Veyl.AsyncExport('StoreOwnedVehicle', function(src, citizenid, netId, garage, props)
    if not Veyl.Validate.int(netId, 1) or not Veyl.Validate.str(garage, 1, 64) then return Veyl.Err('INVALID_INPUT', 'Invalid vehicle') end
    local entity = NetworkGetEntityFromNetworkId(netId)
    local id = entity and entity ~= 0 and byEntity[entity]
    local v = id and vehicles[id]
    if not v or not v.ownedId then return Veyl.Err('NOT_FOUND', 'This is not a vehicle you can park here') end
    if v.citizenid ~= citizenid then return Veyl.Err('NO_PERMISSION', 'Only the owner can park this vehicle') end
    for seat = -1, 6 do
        local ped = GetPedInVehicleSeat(entity, seat)
        if ped and ped ~= 0 then return Veyl.Err('INVALID_STATE', 'Everyone needs to get out first') end
    end
    local fuel = GetResourceState('veyl_fuel') == 'started' and exports.veyl_fuel:GetFuel(id) or 100.0
    local clean = cleanProps(props)
    if v.authProps then
        -- Purchased looks are authoritative: a stale or edited client report cannot undo them.
        clean = clean or {}
        for k, val in pairs(v.authProps) do if k ~= 'dirt' then clean[k] = val end end
    end
    local affected = MySQL.update.await([[UPDATE veyl_player_vehicles SET state = 'garaged', garage = ?, fuel = ?, engine = ?, body = ?,
        props = COALESCE(?, props) WHERE id = ? AND citizenid = ? AND state = 'out']],
        { garage, fuel or 100.0, math.max(0.0, GetVehicleEngineHealth(entity)), math.max(0.0, GetVehicleBodyHealth(entity)),
          clean and json.encode(clean) or nil, v.ownedId, citizenid })
    if affected ~= 1 then return Veyl.Err('DATABASE_ERROR', 'Could not park the vehicle') end
    removeTracking(id, 'stored', true)
    return Veyl.Ok()
end)

--- ImpoundOwnedVehicle(ownedId, reason, fee): staff/police tools. Removes a live instance.
exports('ImpoundOwnedVehicle', function(ownedId, reason, fee)
    local vid = ownedActive[ownedId]
    if vid then removeTracking(vid, 'stored', true) end
    MySQL.update.await("UPDATE veyl_player_vehicles SET state = 'impound', impound_reason = ?, impound_fee = ? WHERE id = ?",
        { tostring(reason or 'impounded'):sub(1, 64), math.max(0, math.floor(tonumber(fee) or VehiclesConfig.ImpoundFee)), ownedId })
    return true
end)

--- ApplyOwnedProps(ownedId, props, expectedVersion?) -> Ok({ version }) | Err('STALE')
--- The authoritative way to change an owned vehicle's saved looks (used by veyl_customs after payment). Cleans the
--- props, writes them with a version check, and makes them authoritative for the live entity until it is parked.
Veyl.AsyncExport('ApplyOwnedProps', function(ownedId, props, expectedVersion)
    if not Veyl.Validate.int(ownedId, 1) then return Veyl.Err('INVALID_INPUT', 'Invalid vehicle') end
    local clean = cleanProps(props)
    if not clean then return Veyl.Err('INVALID_INPUT', 'Invalid properties') end
    local n
    if expectedVersion ~= nil then
        n = MySQL.update.await('UPDATE veyl_player_vehicles SET props = ?, props_version = props_version + 1 WHERE id = ? AND props_version = ?',
            { json.encode(clean), ownedId, tonumber(expectedVersion) or -1 })
    else
        n = MySQL.update.await('UPDATE veyl_player_vehicles SET props = ?, props_version = props_version + 1 WHERE id = ?', { json.encode(clean), ownedId })
    end
    if n ~= 1 then return Veyl.Err('STALE', 'The vehicle was changed elsewhere') end
    local vid = ownedActive[ownedId]
    if vid and vehicles[vid] then vehicles[vid].authProps = clean end
    return Veyl.Ok({ version = MySQL.scalar.await('SELECT props_version FROM veyl_player_vehicles WHERE id = ?', { ownedId }) })
end)

--- GetOwnedProps(ownedId) -> Ok({ props, version, model, plate, citizenid, state })
Veyl.AsyncExport('GetOwnedProps', function(ownedId)
    if not Veyl.Validate.int(ownedId, 1) then return Veyl.Err('INVALID_INPUT', 'Invalid vehicle') end
    local r = MySQL.single.await('SELECT citizenid, model, plate, props, props_version, state, label FROM veyl_player_vehicles WHERE id = ?', { ownedId })
    if not r then return Veyl.Err('NOT_FOUND', 'Vehicle not found') end
    local ok, p = pcall(json.decode, r.props or 'null')
    return Veyl.Ok({ props = ok and p or nil, version = r.props_version, model = r.model, plate = r.plate, citizenid = r.citizenid, state = r.state, label = r.label })
end)

exports('GetOwnedVehicleIdFromEntity', function(entity)
    local id = byEntity[entity]
    return id and vehicles[id] and vehicles[id].ownedId or nil
end)

-- Destruction / disappearance monitoring.
CreateThread(function()
    while true do
        Wait(3000)
        local now = GetGameTimer()
        for id, v in pairs(vehicles) do
            v.born = v.born or now
            if not DoesEntityExist(v.entity) then
                -- Gone twice in a row (not a one-off blip) before it counts as abandoned.
                v.missing = (v.missing or 0) + 1
                if v.missing >= 2 then removeTracking(id, 'missing', false) end
            else
                v.missing = 0
                -- A wreck needs real evidence: the server's GetEntityHealth reads 0 for a vehicle no client has synced
                -- yet (fresh spawns), so it is not used. Only an exploded engine (<= -3900) reported by an owning client,
                -- on a vehicle older than 15 s, two checks in a row.
                local owner = NetworkGetEntityOwner(v.entity)
                if not v.destroyed and now - v.born > 15000 and owner and owner > 0 and GetVehicleEngineHealth(v.entity) <= -3900.0 then
                    v.wreckHits = (v.wreckHits or 0) + 1
                else
                    v.wreckHits = 0
                end
            end
            if v.wreckHits and v.wreckHits >= 2 and not v.destroyed and vehicles[id] then
                v.destroyed = true
                TriggerEvent('veyl_vehicles:destroyed', id)
                if v.ownedId then
                    -- Wrecked owned vehicles are towed to the impound lot; the wreck is cleared after a short delay.
                    SetTimeout(VehiclesConfig.WreckClearMs, function()
                        local cur = vehicles[id]
                        -- Repaired in the meantime (or not really a wreck): keep it.
                        if cur and DoesEntityExist(cur.entity) and GetVehicleEngineHealth(cur.entity) > -3900.0 then
                            cur.destroyed, cur.wreckHits = false, 0
                            return
                        end
                        removeTracking(id, 'destroyed', true)
                    end)
                end
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
