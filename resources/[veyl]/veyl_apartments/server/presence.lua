-- Presence: entering and leaving homes, tours, revocation while inside, and reconnect/restart recovery.
-- A private home is a real MLO room (physical mode). Its occupants are moved into a runtime routing bucket for that
-- unit, so people outside never see, collide with, or interact with them, and the room's furniture is spawned only on
-- the clients inside. The DB keeps only the stable unit/lease ids (veyl_apartment_presence); bucket numbers are recomputed.

Presence = { bySrc = {} }
local E = AptConfig.Entry
local tourTimers = {}

local function setBucket(src, bucket)
    if bucket ~= 0 then
        SetRoutingBucketPopulationEnabled(bucket, false)
        SetRoutingBucketEntityLockdownMode(bucket, 'strict') -- clients cannot create networked entities in a home
    end
    SetPlayerRoutingBucket(src, bucket)
end

local function standPoint(unit, l, localAngle)
    local p = AptGeometry.Stand(unit, l)
    return { x = p.x, y = p.y, z = p.z, heading = AptGeometry.Heading(unit, localAngle) }
end
function Presence.OutsidePoint(unit) return standPoint(unit, AptGeometry.Outside, 0.0) end
function Presence.InsidePoint(unit) return standPoint(unit, AptGeometry.Inside, 180.0) end

function Presence.Of(src) return Presence.bySrc[src] end
function Presence.IsInside(src, leaseId) local p = Presence.bySrc[src] return p ~= nil and p.kind == 'home' and p.leaseId == leaseId end

--- Everyone currently inside a lease's home (server ids).
function Presence.Occupants(leaseId)
    local out = {}
    for src, p in pairs(Presence.bySrc) do if p.kind == 'home' and p.leaseId == leaseId then out[#out + 1] = src end end
    return out
end

local function blocked(src)
    local ped = GetPlayerPed(src)
    if ped == 0 then return 'Not ready' end
    if GetVehiclePedIsIn(ped, false) ~= 0 then return 'Get out of the vehicle first' end
    if not E.AllowWhileDead and GetEntityHealth(ped) <= 0 then return 'You cannot do that right now' end
    local st = Player(src).state
    for _, key in ipairs(E.BlockedStateBags) do if st[key] then return 'You cannot do that right now' end end
    return nil
end

local function nearDoor(src, unit)
    local pc = Veyl.GetPlayerCoords(src)
    local door = AptGeometry.ToWorld(unit, AptGeometry.Outside)
    return pc and #(vector3(pc.x, pc.y, 0) - vector3(door.x, door.y, 0)) <= E.Distance + 1.0 and math.abs(pc.z - (door.z + AptGeometry.FloorZ + 1.0)) < 1.8 -- floors are 3.1 m apart
end

local function context(src, unit, lease, kind)
    local role, perms = 'tour', {}
    if lease then role, perms = Access.Get(lease, Veyl.GetCitizenId(src)) end
    return {
        unitId = unit.id, number = unit.number, building = unit.building, label = Apt.UnitLabel(unit), kind = kind,
        leaseId = lease and lease.id or nil, role = role, perms = perms,
        furniture = (kind == 'home' and lease) and Furniture.PlacedFor(lease.id) or {},
        menu = AptGeometry.ToWorld(unit, AptGeometry.Menu), floorZ = unit.origin.z + AptGeometry.FloorZ,
    }
end
Presence.Context = context

---------------------------------------------------------------------------
-- Enter / exit
---------------------------------------------------------------------------
Veyl.RegisterCallback('enter', function(src, citizenid, unitId)
    local unit = Apt.Unit(unitId)
    if not unit then return Veyl.Err('NOT_FOUND', 'Unknown room') end
    if E.Mode == 'walk' then return Veyl.Err('INVALID_STATE', 'Unlock the door and walk in') end
    if Presence.bySrc[src] then return Veyl.Err('INVALID_STATE', 'You are already inside') end
    if not nearDoor(src, unit) then return Veyl.Err('TOO_FAR', 'Stand at the door') end
    local why = blocked(src)
    if why then return Veyl.Err('BLOCKED', why) end
    local lease = Access.ActiveLeaseForUnit(unit.id)
    -- Vacant and unauthorised doors answer the same way (no information about who lives where).
    if not lease then return Veyl.Err('LOCKED', 'The door is locked') end
    local role, perms, guest = Access.Get(lease, citizenid)
    if not role or not perms.enter then return Veyl.Err('LOCKED', 'The door is locked') end
    if guest and (guest.single_use == 1 or guest.single_use == true) and not guest.used_at then
        local n = MySQL.update.await('UPDATE veyl_apartment_guests SET used_at = NOW() WHERE id = ? AND used_at IS NULL', { guest.id })
        if n ~= 1 then return Veyl.Err('LOCKED', 'That pass was already used') end
    end
    Presence.bySrc[src] = { unitId = unit.id, leaseId = lease.id, kind = 'home', citizenid = citizenid, revoked = false }
    MySQL.query.await([[INSERT INTO veyl_apartment_presence (citizenid, unit_id, lease_id, kind, origin) VALUES (?, ?, ?, 'home', NULL)
        ON DUPLICATE KEY UPDATE unit_id = VALUES(unit_id), lease_id = VALUES(lease_id), kind = 'home', origin = NULL, entered_at = NOW()]],
        { citizenid, unit.id, lease.id })
    setBucket(src, Apt.Bucket(unit))
    if role == 'guest' or guest then
        Apt.Notify(lease.citizenid, 'Visitor arrived', ('%s came in.'):format(Apt.CharName(citizenid)), { phoneOnly = true })
    end
    return Veyl.Ok({ point = Presence.InsidePoint(unit), context = context(src, unit, lease, 'home') })
end, { cooldown = 1500 })

--- Leaving is ALWAYS allowed (even after access was revoked), so nobody can be trapped.
function Presence.Blocked(src) return blocked(src) end

local function exitNow(src, reason)
    local p = Presence.bySrc[src]
    if not p then return nil end
    local unit = Apt.Unit(p.unitId)
    Presence.bySrc[src] = nil
    if tourTimers[src] then tourTimers[src] = nil end
    local cid = p.citizenid
    local origin = p.origin
    MySQL.update.await('DELETE FROM veyl_apartment_presence WHERE citizenid = ?', { cid })
    setBucket(src, 0)
    if p.kind == 'tour' and origin then return { x = origin.x, y = origin.y, z = origin.z, heading = origin.heading or 0.0 }, reason end
    return Presence.OutsidePoint(unit), reason
end
Presence.Exit = exitNow

Veyl.RegisterCallback('exit', function(src)
    local point = exitNow(src, 'left')
    if not point then return Veyl.Err('INVALID_STATE', 'You are not inside') end
    return Veyl.Ok({ point = point })
end, { cooldown = 1000 })

--- Emergency exit (/aptstuck): works even without presence if you are inside any room's walls.
Veyl.RegisterCallback('stuck', function(src)
    local point = exitNow(src, 'stuck')
    if point then return Veyl.Ok({ point = point }) end
    local pc = Veyl.GetPlayerCoords(src)
    for _, unit in pairs(Apt.unitsById) do
        if pc and AptGeometry.Contains(unit, pc, 0.0) then setBucket(src, 0) return Veyl.Ok({ point = Presence.OutsidePoint(unit) }) end
    end
    return Veyl.Err('NOT_INSIDE', 'You are not inside a room')
end, { cooldown = 5000 })

---------------------------------------------------------------------------
-- Tours of vacant rooms (isolated: one bucket per touring player; nothing can be stored or placed)
---------------------------------------------------------------------------
Veyl.RegisterCallback('tour', function(src, citizenid, unitId)
    if not AptConfig.Tour.Enabled then return Veyl.Err('UNAVAILABLE', 'Tours are not available') end
    local unit = Apt.Unit(unitId)
    if not unit or unit.disabled then return Veyl.Err('NOT_FOUND', 'Unknown room') end
    if Presence.bySrc[src] then return Veyl.Err('INVALID_STATE', 'You are already inside') end
    if not Lease.NearDesk(src, unit.building) then return Veyl.Err('TOO_FAR', 'Talk to the front desk') end
    local why = blocked(src)
    if why then return Veyl.Err('BLOCKED', why) end
    if Access.ActiveLeaseForUnit(unit.id) then return Veyl.Err('TAKEN', 'That room is not vacant') end
    local ped = GetPlayerPed(src)
    local c = GetEntityCoords(ped)
    local origin = { x = c.x, y = c.y, z = c.z, heading = GetEntityHeading(ped) }
    Presence.bySrc[src] = { unitId = unit.id, kind = 'tour', citizenid = citizenid, origin = origin }
    MySQL.query.await([[INSERT INTO veyl_apartment_presence (citizenid, unit_id, lease_id, kind, origin) VALUES (?, ?, NULL, 'tour', ?)
        ON DUPLICATE KEY UPDATE unit_id = VALUES(unit_id), lease_id = NULL, kind = 'tour', origin = VALUES(origin), entered_at = NOW()]],
        { citizenid, unit.id, json.encode(origin) })
    setBucket(src, AptConfig.TourBucketBase + src)
    local token = {}
    tourTimers[src] = token
    SetTimeout(AptConfig.Tour.Seconds * 1000, function()
        if tourTimers[src] ~= token then return end
        local point = exitNow(src, 'tour_over')
        if point then TriggerClientEvent('veyl_apartments:forceExit', src, point, 'Your tour is over.') end
    end)
    return Veyl.Ok({ point = Presence.InsidePoint(unit), context = context(src, unit, nil, 'tour'), seconds = AptConfig.Tour.Seconds })
end, { cooldown = 3000 })

---------------------------------------------------------------------------
-- Revocation: protected actions stop immediately (every action re-checks); then a controlled exit if configured.
---------------------------------------------------------------------------
function Presence.RecheckLease(leaseId)
    for src, p in pairs(Presence.bySrc) do
        if p.kind == 'home' and p.leaseId == leaseId then
            local lease = Access.Lease(leaseId)
            local ok = lease and lease.status == 'active' and Access.Can(lease, p.citizenid, 'enter')
            if ok then
                -- Permissions may have changed: refresh what the client shows.
                local unit = Apt.Unit(p.unitId)
                TriggerClientEvent('veyl_apartments:context', src, context(src, unit, lease, 'home'))
            elseif not p.revoked then
                p.revoked = true
                TriggerClientEvent('veyl_apartments:revoked', src, AptConfig.RevokedExitSeconds)
                if AptConfig.RevokedExitSeconds then
                    SetTimeout(AptConfig.RevokedExitSeconds * 1000, function()
                        local cur = Presence.bySrc[src]
                        if cur and cur.revoked and cur.leaseId == leaseId then
                            local point = exitNow(src, 'revoked')
                            if point then TriggerClientEvent('veyl_apartments:forceExit', src, point, 'You no longer have access to this home.') end
                        end
                    end)
                end
            end
        end
    end
end

--- Staff/admin: walk everyone out of a unit.
function Presence.ClearUnit(unitId, message)
    for src, p in pairs(Presence.bySrc) do
        if p.unitId == unitId then
            local point = exitNow(src, 'cleared')
            if point then TriggerClientEvent('veyl_apartments:forceExit', src, point, message or 'You were returned outside.') end
        end
    end
end

---------------------------------------------------------------------------
-- Reconnect / spawn (called by veyl_spawn before it places the player)
---------------------------------------------------------------------------
--- ResolveSpawn(src, position) -> nil (no change) or { x, y, z, heading, reason }
--- (Presence.ResolveSpawn can be extended by the walk-in module; the export always calls the current one.)
exports('ResolveSpawn', function(...) return Presence.ResolveSpawn(...) end)
function Presence.ResolveSpawn(src, position, mode)
    if not Apt.ready then return nil end
    local citizenid = Veyl.GetCitizenId(src)
    if not citizenid then return nil end
    if mode == 'hospital' then
        MySQL.update.await('DELETE FROM veyl_apartment_presence WHERE citizenid = ?', { citizenid })
        return nil
    end
    local row = MySQL.single.await('SELECT * FROM veyl_apartment_presence WHERE citizenid = ?', { citizenid })
    if row then
        local unit = Apt.Unit(row.unit_id)
        if row.kind == 'tour' or not unit then
            MySQL.update.await('DELETE FROM veyl_apartment_presence WHERE citizenid = ?', { citizenid })
            local o = Apt.Decode(row.origin, nil)
            if o then return { x = o.x, y = o.y, z = o.z, heading = o.heading or 0.0, reason = 'tour_ended' } end
            return unit and Presence.OutsidePoint(unit) or nil
        end
        local lease = Access.ActiveLeaseForUnit(unit.id)
        local role, perms
        if lease then role, perms = Access.Get(lease, citizenid) end
        -- A single-visit guest who disconnected mid-visit continues that visit (until the pass expires).
        if lease and lease.id == row.lease_id and role and perms.enter then
            Presence.bySrc[src] = { unitId = unit.id, leaseId = lease.id, kind = 'home', citizenid = citizenid, revoked = false, restoring = true }
            setBucket(src, Apt.Bucket(unit))
            local p = Presence.InsidePoint(unit)
            p.reason = 'home'
            return p
        end
        MySQL.update.await('DELETE FROM veyl_apartment_presence WHERE citizenid = ?', { citizenid })
        local p = Presence.OutsidePoint(unit)
        p.reason = 'access_ended'
        return p
    end
    -- No record but the saved position is inside a room (e.g. the record was lost): never spawn inside a home.
    if type(position) == 'table' and position.x then
        local pos = vector3(position.x, position.y, position.z)
        for _, unit in pairs(Apt.unitsById) do
            if AptGeometry.Contains(unit, pos, 0.0) then local p = Presence.OutsidePoint(unit) p.reason = 'outside' return p end
        end
    end
    return nil
end

AddEventHandler('VeylCore:Server:OnPlayerSpawned', function(src)
    local p = Presence.bySrc[src]
    if not p or not p.restoring then return end
    p.restoring = nil
    local unit = Apt.Unit(p.unitId)
    local lease = Access.Lease(p.leaseId)
    TriggerClientEvent('veyl_apartments:context', src, context(src, unit, lease, 'home'))
end)

AddEventHandler('VeylCore:Server:OnPlayerUnload', function(src, citizenid, reason)
    local p = Presence.bySrc[src]
    if not p then return end
    -- Logging out inside keeps the DB record for reconnect; the runtime state and bucket are cleared.
    Presence.bySrc[src] = nil
    tourTimers[src] = nil
    if GetPlayerName(src) then SetPlayerRoutingBucket(src, 0) end
end)

AddEventHandler('playerDropped', function()
    Presence.bySrc[source] = nil
    tourTimers[source] = nil
end)

-- Resource restart: players still inside get their context back (the DB record is the source of truth).
AddEventHandler('veyl_apartments:ready', function()
    for _, src in ipairs(GetPlayers()) do
        src = tonumber(src)
        local cid = Veyl.GetCitizenId(src)
        local row = cid and MySQL.single.await('SELECT * FROM veyl_apartment_presence WHERE citizenid = ?', { cid })
        if row and row.kind == 'home' and Walk then
            Walk.Restore(src, cid, row) -- walk-in mode: no private world; only single-visit guests have a 'home' row
        elseif row then
            local unit = Apt.Unit(row.unit_id)
            local lease = row.kind == 'home' and unit and Access.ActiveLeaseForUnit(unit.id)
            if row.kind == 'home' and lease and lease.id == row.lease_id and Access.Can(lease, cid, 'enter') then
                Presence.bySrc[src] = { unitId = unit.id, leaseId = lease.id, kind = 'home', citizenid = cid, revoked = false }
                setBucket(src, Apt.Bucket(unit))
                TriggerClientEvent('veyl_apartments:context', src, context(src, unit, lease, 'home'))
            else
                MySQL.update.await('DELETE FROM veyl_apartment_presence WHERE citizenid = ?', { cid })
                local o = row.kind == 'tour' and Apt.Decode(row.origin, nil)
                local point = o and { x = o.x, y = o.y, z = o.z, heading = o.heading or 0 } or (unit and Presence.OutsidePoint(unit))
                setBucket(src, 0)
                if point then TriggerClientEvent('veyl_apartments:forceExit', src, point, 'You were returned outside.') end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    -- Put everyone back in the shared world; their DB record restores them when the resource starts again.
    for src in pairs(Presence.bySrc) do if GetPlayerName(src) then SetPlayerRoutingBucket(src, 0) end end
end)
