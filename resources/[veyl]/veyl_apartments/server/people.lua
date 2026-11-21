-- Roommates, guest passes, the doorbell / visitor directory, and blocked visitors.
-- People are identified by stable character id (citizenid). Players pick someone by phone number or as a nearby player.

People = {}
local D = AptConfig.Doorbell
local visits = {}       -- [id] = { id, leaseId, visitorCid, visitorSrc, name, expires }
local lastRing = {}     -- [visitorCid .. ':' .. leaseId] = timestamp
local nextVisit = 0

--- Resolves a target given as { number = '555-1234' } or { serverId = 12 } (must be nearby, same world).
function People.Resolve(src, target)
    if type(target) ~= 'table' then return nil end
    if target.serverId then
        local t = tonumber(target.serverId)
        if not t or t == src or not GetPlayerName(t) then return nil end
        local a, b = Veyl.GetPlayerCoords(src), Veyl.GetPlayerCoords(t)
        if not a or not b or #(a - b) > 5.0 or GetPlayerRoutingBucket(src) ~= GetPlayerRoutingBucket(t) then return nil end
        return Veyl.GetCitizenId(t)
    end
    if target.number and Apt.Has('phone') then
        local ok, cid = pcall(function() return exports.veyl_phone:GetCitizenByNumber(tostring(target.number)) end)
        return ok and cid or nil
    end
    return nil
end

local function leaseFor(citizenid, leaseId, perm)
    local lease = Veyl.Validate.int(leaseId, 1) and Access.Lease(leaseId)
    if not lease or not Access.Can(lease, citizenid, perm) then return nil end
    return lease
end

---------------------------------------------------------------------------
-- Roommates
---------------------------------------------------------------------------
Veyl.RegisterCallback('roommateInvite', function(src, citizenid, leaseId, target)
    local lease = leaseFor(citizenid, leaseId, 'roommates')
    if not lease then return Veyl.Err('NO_PERMISSION', 'Only the leaseholder can add roommates') end
    local cid = People.Resolve(src, target)
    if not cid then return Veyl.Err('NOT_FOUND', 'Person not found. Use their phone number or stand next to them.') end
    if cid == lease.citizenid then return Veyl.Err('INVALID_INPUT', 'You already live here') end
    if Access.LeaseOf(cid) or MySQL.scalar.await("SELECT 1 FROM veyl_apartment_members WHERE citizenid = ? AND status = 'active'", { cid }) then
        return Veyl.Err('UNAVAILABLE', 'They already have a home')
    end
    local count = MySQL.scalar.await('SELECT COUNT(*) FROM veyl_apartment_members WHERE lease_id = ?', { lease.id }) or 0
    if count >= AptConfig.Roommates.Max then return Veyl.Err('LIMIT', ('Up to %d roommates'):format(AptConfig.Roommates.Max)) end
    MySQL.query.await([[INSERT INTO veyl_apartment_members (lease_id, citizenid, perms, status, expires_at) VALUES (?, ?, ?, 'invited', DATE_ADD(NOW(), INTERVAL ? HOUR))
        ON DUPLICATE KEY UPDATE status = IF(status = 'active', 'active', 'invited'), expires_at = VALUES(expires_at)]],
        { lease.id, cid, json.encode(AptConfig.DefaultRoommatePermissions), AptConfig.Roommates.InviteHours })
    local unit = Apt.Unit(lease.unit_id)
    Apt.Notify(cid, 'Roommate invitation', ('%s invited you to live at %s. Answer in the Apartments app.'):format(Apt.CharName(citizenid), Apt.UnitLabel(unit)))
    Apt.Audit(src, 'roommate_invited', { lease = lease.id, target = cid })
    return Veyl.Ok(nil, 'Invitation sent')
end, { cooldown = 1500 })

Veyl.RegisterCallback('roommateRespond', function(src, citizenid, leaseId, accept)
    if not Veyl.Validate.int(leaseId, 1) then return Veyl.Err('INVALID_INPUT', 'Invalid') end
    return Apt.WithLock('cid:' .. citizenid, function()
        local inv = MySQL.single.await([[SELECT * FROM veyl_apartment_members WHERE lease_id = ? AND citizenid = ? AND status = 'invited' AND expires_at > NOW()]], { leaseId, citizenid })
        local lease = Access.Lease(leaseId)
        if not inv or not lease or lease.status ~= 'active' then return Veyl.Err('NOT_FOUND', 'That invitation has expired') end
        if not accept then
            MySQL.update.await('DELETE FROM veyl_apartment_members WHERE lease_id = ? AND citizenid = ?', { leaseId, citizenid })
            Apt.Notify(lease.citizenid, 'Invitation declined', ('%s declined to move in.'):format(Apt.CharName(citizenid)), { phoneOnly = true })
            return Veyl.Ok(nil, 'Invitation declined')
        end
        if Access.LeaseOf(citizenid) then return Veyl.Err('UNAVAILABLE', 'Move out of your own home first') end
        MySQL.update.await("UPDATE veyl_apartment_members SET status = 'active', expires_at = NULL WHERE lease_id = ? AND citizenid = ?", { leaseId, citizenid })
        Storage.EnsureLocker(leaseId, citizenid)
        Furniture.AttachStored(citizenid, leaseId)
        Apt.Notify(lease.citizenid, 'New roommate', ('%s moved in.'):format(Apt.CharName(citizenid)))
        Apt.Audit(src, 'roommate_joined', { lease = leaseId })
        return Veyl.Ok(nil, 'Welcome home! Your key is active.')
    end)
end, { cooldown = 1000 })

Veyl.RegisterCallback('roommatePerms', function(src, citizenid, leaseId, target, perms)
    local lease = leaseFor(citizenid, leaseId, 'roommates')
    if not lease then return Veyl.Err('NO_PERMISSION', 'Only the leaseholder can change permissions') end
    local clean = Access.CleanPerms(perms)
    local n = MySQL.update.await("UPDATE veyl_apartment_members SET perms = ? WHERE lease_id = ? AND citizenid = ? AND status = 'active'", { json.encode(clean), lease.id, target })
    if n ~= 1 then return Veyl.Err('NOT_FOUND', 'Roommate not found') end
    Apt.Audit(src, 'roommate_perms', { lease = lease.id, target = target, perms = clean })
    Access.Recheck(lease.id)
    return Veyl.Ok({ perms = clean }, 'Permissions updated')
end, { cooldown = 500 })

local function removeMember(lease, cid)
    local n = MySQL.update.await('DELETE FROM veyl_apartment_members WHERE lease_id = ? AND citizenid = ?', { lease.id, cid })
    if n ~= 1 then return false end
    Storage.LockerToRecovery(lease.id, cid)
    Furniture.DetachOwner(lease.id, cid) -- their furniture leaves with them (stored, still theirs)
    Access.Recheck(lease.id)
    return true
end

Veyl.RegisterCallback('roommateRemove', function(src, citizenid, leaseId, target)
    local lease = leaseFor(citizenid, leaseId, 'roommates')
    if not lease then return Veyl.Err('NO_PERMISSION', 'Only the leaseholder can remove roommates') end
    if not removeMember(lease, target) then return Veyl.Err('NOT_FOUND', 'Roommate not found') end
    Apt.Notify(target, 'Removed from home', ('You no longer live at %s. Your locker is waiting at the front desk.'):format(Apt.UnitLabel(Apt.Unit(lease.unit_id))))
    Apt.Audit(src, 'roommate_removed', { lease = lease.id, target = target })
    return Veyl.Ok(nil, 'Roommate removed')
end, { cooldown = 1000 })

Veyl.RegisterCallback('roommateLeave', function(src, citizenid, leaseId)
    local lease = Veyl.Validate.int(leaseId, 1) and Access.Lease(leaseId)
    if not lease or not removeMember(lease, citizenid) then return Veyl.Err('NOT_FOUND', 'You are not a roommate there') end
    Apt.Notify(lease.citizenid, 'Roommate moved out', ('%s moved out.'):format(Apt.CharName(citizenid)))
    return Veyl.Ok(nil, 'You moved out. Your locker is waiting at the front desk.')
end, { cooldown = 1000 })

--- Optional contribution: a roommate sends money to the leaseholder (a real bank transfer with a record). Never automatic.
Veyl.RegisterCallback('contribute', function(src, citizenid, leaseId, amount, clientOp)
    local lease = Veyl.Validate.int(leaseId, 1) and Access.Lease(leaseId)
    local role = lease and Access.Get(lease, citizenid)
    if role ~= 'roommate' then return Veyl.Err('NO_PERMISSION', 'Only roommates can contribute') end
    if not Veyl.Validate.int(amount, 1, 100000) or not Apt.ValidOp(clientOp) then return Veyl.Err('INVALID_INPUT', 'Enter an amount') end
    local op = ('apt:contrib:%s:%s'):format(citizenid, clientOp)
    local res = Apt.Core('TransferMoney', citizenid, 'bank', lease.citizenid, 'bank', amount, 'Rent contribution', op)
    if res.ok or res.code == 'DUPLICATE_OPERATION' then
        MySQL.insert.await([[INSERT IGNORE INTO veyl_apartment_payments (lease_id, kind, period, amount, paid_by, method, op_id, note)
            VALUES (?, 'contribution', 0, ?, ?, 'bank', ?, 'Roommate contribution')]], { lease.id, amount, citizenid, op })
        Apt.Notify(lease.citizenid, 'Rent contribution', ('%s sent you $%d.'):format(Apt.CharName(citizenid), amount), { phoneOnly = true })
        return Veyl.Ok(nil, ('Sent $%d to the leaseholder'):format(amount))
    end
    return res
end, { cooldown = 1500 })

---------------------------------------------------------------------------
-- Guest passes
---------------------------------------------------------------------------
Veyl.RegisterCallback('guestGrant', function(src, citizenid, leaseId, target, hours, singleUse)
    local lease = leaseFor(citizenid, leaseId, 'guests')
    if not lease then return Veyl.Err('NO_PERMISSION', 'You cannot give out keys') end
    local cid = People.Resolve(src, target)
    if not cid then return Veyl.Err('NOT_FOUND', 'Person not found. Use their phone number or stand next to them.') end
    if Access.Get(lease, cid) == 'leaseholder' or Access.Get(lease, cid) == 'roommate' then return Veyl.Err('INVALID_INPUT', 'They already live here') end
    hours = math.max(1, math.min(AptConfig.Guests.MaxHours, math.floor(tonumber(hours) or AptConfig.Guests.DefaultHours)))
    local active = MySQL.scalar.await('SELECT COUNT(*) FROM veyl_apartment_guests WHERE lease_id = ? AND revoked_at IS NULL AND expires_at > NOW()', { lease.id }) or 0
    if active >= AptConfig.Guests.MaxActive then return Veyl.Err('LIMIT', 'Too many active guest passes. Revoke one first.') end
    MySQL.insert.await([[INSERT INTO veyl_apartment_guests (lease_id, citizenid, granted_by, source, single_use, expires_at)
        VALUES (?, ?, ?, 'pass', ?, DATE_ADD(NOW(), INTERVAL ? HOUR))]], { lease.id, cid, citizenid, singleUse and 1 or 0, hours })
    Apt.Notify(cid, 'Guest pass', ('You can visit %s for %d hour%s%s.'):format(Apt.UnitLabel(Apt.Unit(lease.unit_id)), hours, hours == 1 and '' or 's', singleUse and ' (one visit)' or ''))
    Apt.Audit(src, 'guest_granted', { lease = lease.id, target = cid, hours = hours })
    return Veyl.Ok(nil, 'Guest pass sent')
end, { cooldown = 1000 })

Veyl.RegisterCallback('guestRevoke', function(src, citizenid, passId)
    local pass = Veyl.Validate.int(passId, 1) and MySQL.single.await('SELECT * FROM veyl_apartment_guests WHERE id = ?', { passId })
    local lease = pass and leaseFor(citizenid, pass.lease_id, 'guests')
    if not lease then return Veyl.Err('NO_PERMISSION', 'You cannot change keys') end
    MySQL.update.await('UPDATE veyl_apartment_guests SET revoked_at = NOW() WHERE id = ? AND revoked_at IS NULL', { passId })
    Access.Recheck(lease.id)
    Apt.Audit(src, 'guest_revoked', { lease = lease.id, pass = passId })
    return Veyl.Ok(nil, 'Pass revoked')
end, { cooldown = 500 })

---------------------------------------------------------------------------
-- Doorbell: at a room's door, or through the front-desk directory (opted-in residents only)
---------------------------------------------------------------------------
local function answerers(lease)
    local out = {}
    for _, cid in ipairs({ lease.citizenid }) do out[#out + 1] = cid end
    for _, m in ipairs(MySQL.query.await("SELECT citizenid, perms FROM veyl_apartment_members WHERE lease_id = ? AND status = 'active'", { lease.id }) or {}) do
        local perms = {}
        for _, p in ipairs(Access.CleanPerms(Apt.Decode(m.perms, {}))) do perms[p] = true end
        if perms.guests then out[#out + 1] = m.citizenid end
    end
    local online = {}
    for _, cid in ipairs(out) do local s = Veyl.GetSourceByCitizenId(cid) if s then online[#online + 1] = { cid = cid, src = s } end end
    return online
end

local function ring(src, citizenid, lease)
    local NO_ANSWER = Veyl.Err('NO_ANSWER', 'No one answered')
    if not lease or Access.IsBlocked(lease.id, citizenid) then return NO_ANSWER end
    if Access.Get(lease, citizenid) then return Veyl.Err('INVALID_INPUT', 'You already have a key. Use the door.') end
    local key = citizenid .. ':' .. lease.id
    if (lastRing[key] or 0) + D.CooldownSeconds > os.time() then return Veyl.Err('RATE_LIMITED', 'Give them a moment to answer') end
    local pending = 0
    for _, v in pairs(visits) do if v.leaseId == lease.id and v.expires > os.time() then pending = pending + 1 end end
    if pending >= D.MaxPendingPerApartment then return NO_ANSWER end
    local who = answerers(lease)
    if #who == 0 then return NO_ANSWER end
    lastRing[key] = os.time()
    nextVisit = nextVisit + 1
    local name = Apt.CharName(citizenid)
    local v = { id = nextVisit, leaseId = lease.id, visitorCid = citizenid, visitorSrc = src, name = name, expires = os.time() + D.RequestSeconds }
    visits[v.id] = v
    for _, r in ipairs(who) do
        TriggerClientEvent('veyl_apartments:visitRequest', r.src, { id = v.id, name = name, expires = D.RequestSeconds })
        Apt.Notify(r.cid, 'Visitor at the door', ('%s is requesting access.'):format(name), { phoneOnly = true, dedupe = 'visit:' .. v.id .. ':' .. r.cid })
    end
    return Veyl.Ok({ seconds = D.RequestSeconds }, 'You rang the bell')
end

--- Knock at a specific room's door (the visitor is standing there).
Veyl.RegisterCallback('ringDoor', function(src, citizenid, unitId)
    local unit = Apt.Unit(unitId)
    if not unit then return Veyl.Err('NOT_FOUND', 'Unknown room') end
    local pc, door = Veyl.GetPlayerCoords(src), AptGeometry.ToWorld(unit, AptGeometry.Outside)
    if not pc or #(vector2(pc.x, pc.y) - vector2(door.x, door.y)) > AptConfig.Entry.Distance + 1.0 then return Veyl.Err('TOO_FAR', 'Stand at the door') end
    return ring(src, citizenid, Access.ActiveLeaseForUnit(unit.id))
end, { cooldown = 2000 })

--- Directory at the front desk: residents who opted in, by name only (no room numbers).
Veyl.RegisterCallback('directory', function(src, citizenid, buildingId, query)
    if not Apt.buildings[buildingId] or not AptBuildings[buildingId].directory then return Veyl.Err('UNAVAILABLE', 'No directory here') end
    if not Lease.NearDesk(src, buildingId) then return Veyl.Err('TOO_FAR', 'Use the directory at the front desk') end
    local q = type(query) == 'string' and query:lower():gsub('[^%w ]', ''):sub(1, 24) or ''
    local unitIds = {}
    for _, u in ipairs(Apt.buildings[buildingId].units) do unitIds[#unitIds + 1] = u.id end
    if #unitIds == 0 then return Veyl.Ok({}) end
    local rows = MySQL.query.await(('SELECT id, citizenid FROM veyl_apartment_leases WHERE status = \'active\' AND directory = 1 AND unit_id IN (%s)')
        :format(table.concat(unitIds, ',')), {}) or {}
    local out = {}
    for _, r in ipairs(rows) do
        local name = Apt.CharName(r.citizenid)
        if q == '' or name:lower():find(q, 1, true) then out[#out + 1] = { leaseId = r.id, name = name } end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return Veyl.Ok(out)
end, { cooldown = 500 })

Veyl.RegisterCallback('ringDirectory', function(src, citizenid, leaseId)
    local lease = Veyl.Validate.int(leaseId, 1) and Access.Lease(leaseId)
    if not lease or lease.status ~= 'active' or not (lease.directory == 1 or lease.directory == true) then return Veyl.Err('NO_ANSWER', 'No one answered') end
    if not Lease.NearDesk(src, Apt.Unit(lease.unit_id).building) then return Veyl.Err('TOO_FAR', 'Use the directory at the front desk') end
    return ring(src, citizenid, lease)
end, { cooldown = 2000 })

--- respondVisit(id, 'allow'|'decline'|'block')
Veyl.RegisterCallback('respondVisit', function(src, citizenid, id, action)
    local v = visits[tonumber(id) or -1]
    if not v or v.expires < os.time() then return Veyl.Err('EXPIRED', 'That request has expired') end
    local lease = Access.Lease(v.leaseId)
    if not Access.Can(lease, citizenid, 'guests') then return Veyl.Err('NO_PERMISSION', 'You cannot let people in') end
    visits[v.id] = nil
    local unit = Apt.Unit(lease.unit_id)
    if action == 'allow' then
        MySQL.insert.await([[INSERT INTO veyl_apartment_guests (lease_id, citizenid, granted_by, source, single_use, expires_at)
            VALUES (?, ?, ?, 'doorbell', 1, DATE_ADD(NOW(), INTERVAL ? MINUTE))]], { lease.id, v.visitorCid, citizenid, D.PassMinutes })
        if GetPlayerName(v.visitorSrc) then
            TriggerClientEvent('veyl_apartments:visitAnswer', v.visitorSrc, { allowed = true, unitId = unit.id, number = unit.number,
                floor = unit.floor, minutes = D.PassMinutes, door = AptGeometry.ToWorld(unit, AptGeometry.Outside) })
        end
        return Veyl.Ok(nil, ('Let %s in'):format(v.name))
    end
    if action == 'block' then
        MySQL.query.await('INSERT IGNORE INTO veyl_apartment_blocks (lease_id, citizenid) VALUES (?, ?)', { lease.id, v.visitorCid })
    end
    if GetPlayerName(v.visitorSrc) then TriggerClientEvent('veyl_apartments:visitAnswer', v.visitorSrc, { allowed = false }) end
    return Veyl.Ok(nil, action == 'block' and 'Blocked' or 'Declined')
end, { cooldown = 300 })

function People.PendingVisits(leaseId)
    local out = {}
    for _, v in pairs(visits) do if v.leaseId == leaseId and v.expires > os.time() then out[#out + 1] = { id = v.id, name = v.name, expires = v.expires } end end
    return out
end

Veyl.RegisterCallback('unblock', function(_, citizenid, leaseId, target)
    local lease = leaseFor(citizenid, leaseId, 'guests')
    if not lease then return Veyl.Err('NO_PERMISSION', 'Not allowed') end
    MySQL.update.await('DELETE FROM veyl_apartment_blocks WHERE lease_id = ? AND citizenid = ?', { lease.id, target })
    return Veyl.Ok(nil, 'Unblocked')
end, { cooldown = 300 })

-- Expired visit requests are dropped.
CreateThread(function()
    while true do
        Wait(15000)
        local now = os.time()
        for id, v in pairs(visits) do if v.expires < now then visits[id] = nil end end
        for k, t in pairs(lastRing) do if t + 600 < now then lastRing[k] = nil end end
    end
end)
People._visits = visits
