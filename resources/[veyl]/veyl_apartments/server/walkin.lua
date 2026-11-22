-- Walk-in mode (AptConfig.Entry.Mode = 'walk'): the room's real MLO door is the lock.
--   * Residents and guests unlock the door (server-checked); the state is synced to every client and the door relocks
--     itself after AutoLockSeconds. Anyone standing inside can always open it to leave (never trapped).
--   * "Inside" is decided by the server from the player's position against the room's real bounds, so storage,
--     wardrobe and furniture work only while you are physically in that room.
--   * Furniture is shown to every client near the motel (guests and passers-by see the same room).
-- Teleport mode keeps working for tours and as a configurable fallback.

if AptConfig.Entry.Mode ~= 'walk' then return end

Walk = { doors = {} } -- [unitId] = { locked = bool, token }
local E = AptConfig.Entry

local function unitAt(pos)
    if not pos then return nil end
    for _, u in pairs(Apt.unitsById) do if AptGeometry.Contains(u, pos, 0.0) then return u end end
    return nil
end
Presence.UnitAt = unitAt

---------------------------------------------------------------------------
-- Presence from position
---------------------------------------------------------------------------
local baseOf = Presence.Of
function Presence.Of(src)
    local p = baseOf(src)
    if p then return p end
    local u = unitAt(Veyl.GetPlayerCoords(src))
    if not u then return nil end
    local lease = Access.ActiveLeaseForUnit(u.id)
    if not lease then return nil end
    return { unitId = u.id, leaseId = lease.id, kind = 'home', citizenid = Veyl.GetCitizenId(src), walk = true }
end

function Presence.IsInside(src, leaseId)
    local p = Presence.Of(src)
    return p ~= nil and p.kind == 'home' and p.leaseId == leaseId
end

local baseOccupants = Presence.Occupants
function Presence.Occupants(leaseId)
    local out, seen = {}, {}
    for _, s in ipairs(baseOccupants(leaseId)) do out[#out + 1] = s seen[s] = true end
    local lease = Access.Lease(leaseId)
    local u = lease and Apt.Unit(lease.unit_id)
    if u then
        for _, s in ipairs(GetPlayers()) do
            s = tonumber(s)
            if not seen[s] and unitAt(Veyl.GetPlayerCoords(s)) == u then out[#out + 1] = s end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Doors
---------------------------------------------------------------------------
local function state(unitId)
    Walk.doors[unitId] = Walk.doors[unitId] or { locked = true }
    return Walk.doors[unitId]
end

function Walk.SetDoor(unit, locked)
    local d = state(unit.id)
    d.locked = locked == true
    local token = {}
    d.token = token
    TriggerClientEvent('veyl_apartments:doorState', -1, unit.id, d.locked)
    if not d.locked and (E.AutoLockSeconds or 0) > 0 then
        SetTimeout(E.AutoLockSeconds * 1000, function()
            if d.token == token and not d.locked then Walk.SetDoor(unit, true) end
        end)
    end
end

Veyl.RegisterCallback('doorStates', function()
    local out = {}
    for id, d in pairs(Walk.doors) do if not d.locked then out[#out + 1] = id end end
    return Veyl.Ok({ unlocked = out, mode = 'walk' })
end, { cooldown = 1000 })

local function nearDoor(src, unit)
    local pc = Veyl.GetPlayerCoords(src)
    if not pc then return false end
    local door = AptGeometry.ToWorld(unit, AptGeometry.Door.pos)
    local floor = unit.origin.z + AptGeometry.FloorZ
    return #(vector3(pc.x, pc.y, 0) - vector3(door.x, door.y, 0)) <= 2.6 and pc.z > floor - 0.6 and pc.z < floor + 2.6
end

--- door(unitId, locked): unlock with a key (lease, roommate or guest pass), or from inside; lock from either side.
Veyl.RegisterCallback('door', function(src, citizenid, unitId, locked)
    local unit = Apt.Unit(unitId)
    if not unit then return Veyl.Err('NOT_FOUND', 'Unknown room') end
    if not nearDoor(src, unit) then return Veyl.Err('TOO_FAR', 'Stand at the door') end
    local ped = GetPlayerPed(src)
    if ped == 0 or GetVehiclePedIsIn(ped, false) ~= 0 then return Veyl.Err('BLOCKED', 'Get out of the vehicle first') end
    local inside = unitAt(Veyl.GetPlayerCoords(src)) == unit
    local lease = Access.ActiveLeaseForUnit(unit.id)
    local role, perms, guest
    if lease then role, perms, guest = Access.Get(lease, citizenid) end
    local hasKey = role ~= nil and perms.enter == true
    locked = locked == true
    if not hasKey and not inside then return Veyl.Err('LOCKED', 'The door is locked') end
    if state(unit.id).locked == locked then return Veyl.Ok({ locked = locked }) end
    if not locked and hasKey and not inside and guest and (guest.single_use == 1 or guest.single_use == true) and not guest.used_at then
        -- A single-visit pass is used by this visit; it stays valid while the guest is inside (presence row).
        MySQL.update.await('UPDATE veyl_apartment_guests SET used_at = NOW() WHERE id = ? AND used_at IS NULL', { guest.id })
        MySQL.query.await([[INSERT INTO veyl_apartment_presence (citizenid, unit_id, lease_id, kind, origin) VALUES (?, ?, ?, 'home', NULL)
            ON DUPLICATE KEY UPDATE unit_id = VALUES(unit_id), lease_id = VALUES(lease_id), kind = 'home', origin = NULL, entered_at = NOW()]],
            { citizenid, unit.id, lease.id })
        Walk.visiting[src] = unit.id
    end
    Walk.SetDoor(unit, locked)
    if not locked and role == 'guest' and not inside then
        Apt.Notify(lease.citizenid, 'Visitor arrived', ('%s opened your door.'):format(Apt.CharName(citizenid)), { phoneOnly = true })
    end
    return Veyl.Ok({ locked = locked }, locked and 'Locked' or 'Unlocked')
end, { cooldown = 600 })

--- The room you are standing in, with your role there (for the in-room menu). nil when not in a leased room.
Veyl.RegisterCallback('here', function(src, citizenid)
    local u = unitAt(Veyl.GetPlayerCoords(src))
    if not u then return Veyl.Ok(nil) end
    local lease = Access.ActiveLeaseForUnit(u.id)
    if not lease then return Veyl.Ok({ unitId = u.id, number = u.number, building = u.building, label = Apt.UnitLabel(u), kind = 'vacant', perms = {} }) end
    local ctx = Presence.Context(src, u, lease, 'home')
    ctx.furniture = nil -- furniture is streamed to everyone separately in walk-in mode
    ctx.role = ctx.role or 'visitor'
    ctx.perms = ctx.perms or {}
    return Veyl.Ok(ctx)
end, { cooldown = 300 })

---------------------------------------------------------------------------
-- Single-visit guests: the visit ends when they leave the room
---------------------------------------------------------------------------
Walk.visiting = {} -- [src] = unitId
CreateThread(function()
    while true do
        Wait(3000)
        for src, unitId in pairs(Walk.visiting) do
            local u = Apt.Unit(unitId)
            local pc = GetPlayerName(src) and Veyl.GetPlayerCoords(src)
            if not pc then
                Walk.visiting[src] = nil
            elseif unitAt(pc) ~= u then
                -- Grace distance: still on the doorstep counts as inside for a moment (walking in through the door).
                local door = AptGeometry.ToWorld(u, AptGeometry.Door.pos)
                if #(vector3(pc.x, pc.y, 0) - vector3(door.x, door.y, 0)) > 4.0 then
                    Walk.visiting[src] = nil
                    local cid = Veyl.GetCitizenId(src)
                    if cid then MySQL.update.await("DELETE FROM veyl_apartment_presence WHERE citizenid = ? AND kind = 'home'", { cid }) end
                end
            end
        end
    end
end)
AddEventHandler('playerDropped', function() Walk.visiting[source] = nil end)

--- Resource restart: a single-visit guest's visit continues (the watcher ends it once they leave); stale rows go.
function Walk.Restore(src, cid, row)
    local u = Apt.Unit(row.unit_id)
    local lease = u and Access.ActiveLeaseForUnit(u.id)
    if lease and lease.id == row.lease_id and Access.Can(lease, cid, 'enter') then
        Walk.visiting[src] = u.id
    else
        MySQL.update.await('DELETE FROM veyl_apartment_presence WHERE citizenid = ?', { cid })
    end
end

---------------------------------------------------------------------------
-- Revocation and lease end: lock the door, refresh menus, walk people without access out
---------------------------------------------------------------------------
local baseRecheck = Presence.RecheckLease
function Presence.RecheckLease(leaseId)
    baseRecheck(leaseId)
    local lease = Access.Lease(leaseId)
    local u = lease and Apt.Unit(lease.unit_id)
    if not u then return end
    if lease.status ~= 'active' then
        Walk.SetDoor(u, true)
        Furniture.Broadcast(leaseId)
    end
    for _, s in ipairs(GetPlayers()) do
        s = tonumber(s)
        if not Presence.bySrc[s] and unitAt(Veyl.GetPlayerCoords(s)) == u then
            local cid = Veyl.GetCitizenId(s)
            local ok = lease.status == 'active' and cid and Access.Can(lease, cid, 'enter')
            if ok then
                TriggerClientEvent('veyl_apartments:refreshHere', s)
            else
                TriggerClientEvent('veyl_apartments:revoked', s, AptConfig.RevokedExitSeconds)
                if AptConfig.RevokedExitSeconds then
                    SetTimeout(AptConfig.RevokedExitSeconds * 1000, function()
                        if unitAt(Veyl.GetPlayerCoords(s)) ~= u then return end
                        local l2 = Access.Lease(leaseId)
                        local c2 = Veyl.GetCitizenId(s)
                        if l2 and l2.status == 'active' and c2 and Access.Can(l2, c2, 'enter') then return end
                        TriggerClientEvent('veyl_apartments:forceExit', s, Presence.OutsidePoint(u), 'You no longer have access to this home.')
                    end)
                end
            end
        end
    end
end

local baseClear = Presence.ClearUnit
function Presence.ClearUnit(unitId, message)
    baseClear(unitId, message)
    local u = Apt.Unit(unitId)
    for _, s in ipairs(GetPlayers()) do
        s = tonumber(s)
        if unitAt(Veyl.GetPlayerCoords(s)) == u then
            TriggerClientEvent('veyl_apartments:forceExit', s, Presence.OutsidePoint(u), message or 'You were returned outside.')
        end
    end
end

---------------------------------------------------------------------------
-- Furniture for everyone nearby
---------------------------------------------------------------------------
function Furniture.Broadcast(leaseId)
    local lease = Access.Lease(leaseId)
    if not lease then return end
    local list = lease.status == 'active' and Furniture.PlacedFor(leaseId) or {}
    TriggerClientEvent('veyl_apartments:unitFurniture', -1, lease.unit_id, list)
end

Veyl.RegisterCallback('furnitureAll', function()
    local out = {}
    for _, l in ipairs(MySQL.query.await("SELECT id, unit_id FROM veyl_apartment_leases WHERE status = 'active'") or {}) do
        local list = Furniture.PlacedFor(l.id)
        if #list > 0 then out[#out + 1] = { unitId = l.unit_id, items = list } end
    end
    return Veyl.Ok(out)
end, { cooldown = 2000 })

---------------------------------------------------------------------------
-- Spawning: a resident who logged out in their room comes back there; anyone else is put at the door
---------------------------------------------------------------------------
local baseResolve = Presence.ResolveSpawn
function Presence.ResolveSpawn(src, position, mode)
    if not Apt.ready then return nil end
    local cid = Veyl.GetCitizenId(src)
    if not cid then return nil end
    local row = MySQL.single.await('SELECT * FROM veyl_apartment_presence WHERE citizenid = ?', { cid })
    if mode == 'hospital' or (row and row.kind == 'tour') then return baseResolve(src, position, mode) end
    local u = row and Apt.Unit(row.unit_id)
    if row and not u then return baseResolve(src, position, mode) end
    local t = type(position)
    local pos = (t == 'table' or t == 'vector3' or t == 'vector4') and position.x and vector3(position.x, position.y, position.z) or nil
    if not u and pos then u = unitAt(pos) end
    if not u then return nil end
    local lease = Access.ActiveLeaseForUnit(u.id)
    local role, perms, guest
    if lease then role, perms, guest = Access.Get(lease, cid) end
    if role and perms.enter then
        -- No private world in walk-in mode. A single-visit guest's visit continues; any other record (e.g. left over
        -- from teleport mode) is cleared.
        if row and guest then Walk.visiting[src] = u.id
        elseif row then MySQL.update.await('DELETE FROM veyl_apartment_presence WHERE citizenid = ?', { cid }) end
        if pos and unitAt(pos) == u then return nil end -- stays where they logged out
        local p = Presence.InsidePoint(u)
        p.reason = 'home'
        return p
    end
    if row then MySQL.update.await('DELETE FROM veyl_apartment_presence WHERE citizenid = ?', { cid }) end
    local p = Presence.OutsidePoint(u)
    p.reason = 'access_ended'
    return p
end
