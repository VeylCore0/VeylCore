-- Front-desk services and the resident dashboard: parcels, noticeboard, maintenance, and the data behind the
-- resident panel (used by both the phone app and the standalone panel, so they share every rule).

Community = {}
local N, M, P = AptConfig.Noticeboard, AptConfig.Maintenance, AptConfig.Parcels

local function homeBuilding(cid)
    for _, h in ipairs(Access.HomesOf(cid)) do
        if h.role ~= 'guest' then local u = Apt.Unit(h.unit_id) if u then return u.building, h end end
    end
end

---------------------------------------------------------------------------
-- Parcels (held at the front desk; delivery drivers never get into homes)
---------------------------------------------------------------------------
--- exports.veyl_apartments:SendParcel(citizenid, { sender, label, items = { { name, count, metadata? } }, sourceOp })
--- -> Ok({ id }) | Err('NO_HOME'). sourceOp makes a delivery idempotent (sending twice stores one parcel).
exports('SendParcel', function(citizenid, parcel)
    if type(citizenid) ~= 'string' or type(parcel) ~= 'table' or type(parcel.items) ~= 'table' or #parcel.items == 0 or #parcel.items > 20 then
        return Veyl.Err('INVALID_INPUT', 'Invalid parcel')
    end
    if type(parcel.sourceOp) ~= 'string' or #parcel.sourceOp < 3 or #parcel.sourceOp > 90 then return Veyl.Err('INVALID_INPUT', 'sourceOp required') end
    local building = homeBuilding(citizenid)
    if not building then return Veyl.Err('NO_HOME', 'Recipient has no home') end
    local items = {}
    for _, it in ipairs(parcel.items) do
        if type(it.name) ~= 'string' or not Veyl.Validate.int(it.count, 1, 1000) then return Veyl.Err('INVALID_INPUT', 'Invalid item') end
        items[#items + 1] = { name = it.name, count = it.count, metadata = type(it.metadata) == 'table' and it.metadata or nil }
    end
    MySQL.insert.await([[INSERT IGNORE INTO veyl_apartment_parcels (citizenid, building, sender, label, items, source_op) VALUES (?, ?, ?, ?, ?, ?)]],
        { citizenid, building, Apt.Clean(parcel.sender, 48) or 'Courier', Apt.Clean(parcel.label, 64) or 'Parcel', json.encode(items), parcel.sourceOp:sub(1, 90) })
    local id = MySQL.scalar.await('SELECT id FROM veyl_apartment_parcels WHERE source_op = ?', { parcel.sourceOp:sub(1, 90) })
    Apt.Notify(citizenid, 'Parcel waiting', ('%s left a parcel for you at the %s front desk.'):format(Apt.Clean(parcel.sender, 48) or 'A courier', AptBuildings[building].label),
        { dedupe = 'parcel:' .. tostring(id) })
    return Veyl.Ok({ id = id })
end)

Veyl.RegisterCallback('parcels', function(_, citizenid)
    local rows = MySQL.query.await([[SELECT id, building, sender, label, items, status, UNIX_TIMESTAMP(created_at) AS at FROM veyl_apartment_parcels
        WHERE citizenid = ? AND (status = 'waiting' OR created_at > DATE_SUB(NOW(), INTERVAL 7 DAY)) ORDER BY id DESC LIMIT 30]], { citizenid }) or {}
    for _, r in ipairs(rows) do r.items = Apt.Decode(r.items, {}) r.buildingLabel = AptBuildings[r.building] and AptBuildings[r.building].label end
    return Veyl.Ok(rows)
end, { cooldown = 400 })

--- collectParcel(id): at the front desk of that building. Each item is delivered once (operation id per item), so a
--- retry after a full inventory or a crash only delivers what is still missing.
Veyl.RegisterCallback('collectParcel', function(src, citizenid, id)
    if not Veyl.Validate.int(id, 1) then return Veyl.Err('INVALID_INPUT', 'Invalid') end
    return Apt.WithLock('parcel:' .. id, function()
        local p = MySQL.single.await("SELECT * FROM veyl_apartment_parcels WHERE id = ? AND citizenid = ? AND status = 'waiting'", { id, citizenid })
        if not p then return Veyl.Err('NOT_FOUND', 'No parcel waiting') end
        if not Lease.NearDesk(src, p.building) then return Veyl.Err('TOO_FAR', 'Collect it at the front desk') end
        local items = Apt.Decode(p.items, {})
        for i, it in ipairs(items) do
            local op = ('apt:parcel:%d:%d'):format(p.id, i)
            local done = Veyl.Await('veyl_inventory', 'GetOperation', 10000, op)
            if not (done.ok and done.data) then
                local can = Veyl.Await('veyl_inventory', 'CanCarry', 10000, citizenid, it.name, it.count, it.metadata)
                if not can.ok then return Veyl.Err('INVENTORY_FULL', 'Make room in your pockets first. Nothing was lost.') end
                local res = Veyl.Await('veyl_inventory', 'GiveItem', 15000, citizenid, it.name, it.count, it.metadata, op)
                if not res.ok and res.code ~= 'DUPLICATE_OPERATION' then return Veyl.Err(res.code or 'FAILED', res.message or 'Could not hand over the parcel') end
            end
        end
        MySQL.update.await("UPDATE veyl_apartment_parcels SET status = 'collected', collected_at = NOW() WHERE id = ? AND status = 'waiting'", { p.id })
        Apt.Audit(src, 'parcel_collected', { id = p.id })
        return Veyl.Ok(nil, ('Collected: %s'):format(p.label))
    end)
end, { cooldown = 800 })

---------------------------------------------------------------------------
-- Noticeboard (per building; residents post, anyone at the desk reads; reports hide abusive posts)
---------------------------------------------------------------------------
local CATS = { announcement = true, roommate = true, event = true, forsale = true }

Veyl.RegisterCallback('notices', function(src, citizenid, buildingId)
    if not AptBuildings[buildingId] then return Veyl.Err('NOT_FOUND', 'Unknown building') end
    local staff = Veyl.HasPermission(src, 'apartments.manage')
    local rows = MySQL.query.await([[SELECT id, citizenid, author, category, title, body, reports, UNIX_TIMESTAMP(created_at) AS at FROM veyl_apartment_notices
        WHERE building = ? AND removed_by IS NULL AND expires_at > NOW() AND (reports < ? OR ?) ORDER BY id DESC LIMIT 40]],
        { buildingId, N.HideAfterReports, staff and 1 or 0 }) or {}
    for _, r in ipairs(rows) do r.mine = r.citizenid == citizenid r.canRemove = r.mine or staff r.citizenid = nil end
    local b = homeBuilding(citizenid)
    return Veyl.Ok({ items = rows, canPost = b == buildingId, staff = staff })
end, { cooldown = 300 })

Veyl.RegisterCallback('noticePost', function(src, citizenid, buildingId, category, title, body)
    if homeBuilding(citizenid) ~= buildingId then return Veyl.Err('NO_PERMISSION', 'Only residents can post here') end
    if not CATS[category] then return Veyl.Err('INVALID_INPUT', 'Pick a category') end
    title, body = Apt.Clean(title, N.TitleLength), Apt.Clean(body, N.BodyLength)
    if not title or not body then return Veyl.Err('INVALID_INPUT', 'Add a title and some text') end
    if not Apt.Rate(src, 'notice', N.PostCooldownSeconds * 1000) then return Veyl.Err('RATE_LIMITED', 'Wait a moment before posting again') end
    local active = MySQL.scalar.await('SELECT COUNT(*) FROM veyl_apartment_notices WHERE citizenid = ? AND removed_by IS NULL AND expires_at > NOW()', { citizenid }) or 0
    if active >= N.MaxActivePerResident then return Veyl.Err('LIMIT', 'Remove one of your notices first') end
    MySQL.insert.await([[INSERT INTO veyl_apartment_notices (building, citizenid, author, category, title, body, expires_at)
        VALUES (?, ?, ?, ?, ?, ?, DATE_ADD(NOW(), INTERVAL ? DAY))]], { buildingId, citizenid, Apt.CharName(citizenid), category, title, body, N.Days })
    return Veyl.Ok(nil, 'Notice posted')
end)

Veyl.RegisterCallback('noticeRemove', function(src, citizenid, id)
    local n = Veyl.Validate.int(id, 1) and MySQL.single.await('SELECT citizenid FROM veyl_apartment_notices WHERE id = ? AND removed_by IS NULL', { id })
    if not n then return Veyl.Err('NOT_FOUND', 'Notice not found') end
    local staff = Veyl.HasPermission(src, 'apartments.manage')
    if n.citizenid ~= citizenid and not staff then return Veyl.Err('NO_PERMISSION', 'Not your notice') end
    MySQL.update.await('UPDATE veyl_apartment_notices SET removed_by = ? WHERE id = ?', { n.citizenid == citizenid and 'author' or ('staff:' .. citizenid), id })
    if staff and n.citizenid ~= citizenid then Apt.Audit(src, 'notice_removed', { id = id }) end
    return Veyl.Ok(nil, 'Notice removed')
end, { cooldown = 300 })

Veyl.RegisterCallback('noticeReport', function(_, citizenid, id)
    if not Veyl.Validate.int(id, 1) then return Veyl.Err('INVALID_INPUT', 'Invalid') end
    local ok = pcall(MySQL.insert.await, 'INSERT INTO veyl_apartment_notice_reports (notice_id, citizenid) VALUES (?, ?)', { id, citizenid })
    if ok then MySQL.update.await('UPDATE veyl_apartment_notices SET reports = reports + 1 WHERE id = ?', { id }) end
    return Veyl.Ok(nil, 'Thanks, the front desk will review it')
end, { cooldown = 1000 })

---------------------------------------------------------------------------
-- Maintenance
---------------------------------------------------------------------------
local MCATS = {}
for _, c in ipairs(M.Categories) do MCATS[c] = true end
local function isStaff(src) return Veyl.HasPermission(src, M.StaffPermission) end

Veyl.RegisterCallback('maintenanceCreate', function(src, citizenid, leaseId, category, description, preference, allowEntry)
    local lease = Veyl.Validate.int(leaseId, 1) and Access.Lease(leaseId)
    local role = lease and Access.Get(lease, citizenid)
    if role ~= 'leaseholder' and role ~= 'roommate' then return Veyl.Err('NO_PERMISSION', 'Not your home') end
    if not MCATS[category] then return Veyl.Err('INVALID_INPUT', 'Pick a category') end
    description = Apt.Clean(description, 300)
    if not description then return Veyl.Err('INVALID_INPUT', 'Describe the problem') end
    if not Apt.Rate(src, 'maint', 30000) then return Veyl.Err('RATE_LIMITED', 'Wait a moment') end
    local open = MySQL.scalar.await("SELECT COUNT(*) FROM veyl_apartment_maintenance WHERE lease_id = ? AND status NOT IN ('completed','cancelled')", { lease.id }) or 0
    if open >= 3 then return Veyl.Err('LIMIT', 'You already have open requests') end
    MySQL.insert.await([[INSERT INTO veyl_apartment_maintenance (lease_id, unit_id, citizenid, category, description, preference, allow_entry)
        VALUES (?, ?, ?, ?, ?, ?, ?)]], { lease.id, lease.unit_id, citizenid, category, description, Apt.Clean(preference, 60), allowEntry and 1 or 0 })
    for _, s in ipairs(GetPlayers()) do if isStaff(tonumber(s)) then Veyl.Notify(tonumber(s), 'New apartment maintenance request', 'info') end end
    return Veyl.Ok(nil, 'Request sent to building maintenance')
end)

Veyl.RegisterCallback('maintenanceList', function(src, citizenid, leaseId)
    if leaseId == 'staff' then
        if not isStaff(src) then return Veyl.Err('NO_PERMISSION', 'Staff only') end
        local rows = MySQL.query.await([[SELECT m.*, UNIX_TIMESTAMP(m.created_at) AS at FROM veyl_apartment_maintenance m
            WHERE status NOT IN ('completed','cancelled') ORDER BY id LIMIT 50]]) or {}
        for _, r in ipairs(rows) do local u = Apt.Unit(r.unit_id) r.unitLabel = u and Apt.UnitLabel(u) end
        return Veyl.Ok(rows)
    end
    local lease = Veyl.Validate.int(leaseId, 1) and Access.Lease(leaseId)
    local role = lease and Access.Get(lease, citizenid)
    if role ~= 'leaseholder' and role ~= 'roommate' then return Veyl.Err('NO_PERMISSION', 'Not your home') end
    local rows = MySQL.query.await([[SELECT id, category, description, preference, allow_entry, status, staff_name, scheduled_for, note,
        UNIX_TIMESTAMP(created_at) AS at FROM veyl_apartment_maintenance WHERE lease_id = ? ORDER BY id DESC LIMIT 20]], { lease.id }) or {}
    return Veyl.Ok(rows)
end, { cooldown = 300 })

--- Staff workflow: accept -> schedule -> start (temporary access only if the resident allowed entry) -> complete.
Veyl.RegisterCallback('maintenanceUpdate', function(src, citizenid, id, action, text)
    if not isStaff(src) then return Veyl.Err('NO_PERMISSION', 'Staff only') end
    local r = Veyl.Validate.int(id, 1) and MySQL.single.await('SELECT * FROM veyl_apartment_maintenance WHERE id = ?', { id })
    if not r then return Veyl.Err('NOT_FOUND', 'Request not found') end
    local name = Apt.CharName(citizenid)
    if action == 'accept' and r.status == 'open' then
        MySQL.update.await("UPDATE veyl_apartment_maintenance SET status = 'accepted', staff_cid = ?, staff_name = ? WHERE id = ?", { citizenid, name, id })
    elseif action == 'schedule' and (r.status == 'accepted' or r.status == 'scheduled') then
        MySQL.update.await("UPDATE veyl_apartment_maintenance SET status = 'scheduled', scheduled_for = ? WHERE id = ?", { Apt.Clean(text, 60) or 'Soon', id })
    elseif action == 'start' and (r.status == 'accepted' or r.status == 'scheduled') then
        MySQL.update.await("UPDATE veyl_apartment_maintenance SET status = 'in_progress' WHERE id = ?", { id })
        if r.allow_entry == 1 or r.allow_entry == true then
            -- Explicitly authorised by the resident when they filed the request: a time-limited, single-visit pass.
            MySQL.insert.await([[INSERT INTO veyl_apartment_guests (lease_id, citizenid, granted_by, source, single_use, expires_at)
                VALUES (?, ?, ?, 'maintenance', 1, DATE_ADD(NOW(), INTERVAL ? MINUTE))]], { r.lease_id, citizenid, r.citizenid, M.AccessMinutes })
            Apt.Audit(src, 'maintenance_access', { request = id, lease = r.lease_id, minutes = M.AccessMinutes })
        end
    elseif action == 'complete' and r.status ~= 'completed' and r.status ~= 'cancelled' then
        MySQL.update.await("UPDATE veyl_apartment_maintenance SET status = 'completed', note = ? WHERE id = ?", { Apt.Clean(text, 200), id })
        MySQL.update.await("UPDATE veyl_apartment_guests SET revoked_at = NOW() WHERE lease_id = ? AND citizenid = ? AND source = 'maintenance' AND revoked_at IS NULL", { r.lease_id, citizenid })
        Access.Recheck(r.lease_id)
        Apt.Audit(src, 'maintenance_completed', { request = id })
    else
        return Veyl.Err('INVALID_STATE', 'That step is not available now')
    end
    Apt.Notify(r.citizenid, 'Maintenance update', ({ accept = 'Your request was accepted.', schedule = 'A visit was scheduled.', start = 'Maintenance is on the way.',
        complete = 'Your request was completed.' })[action], { phoneOnly = true })
    return Veyl.Ok(nil, 'Updated')
end, { cooldown = 500 })

Veyl.RegisterCallback('maintenanceCancel', function(_, citizenid, id)
    local r = Veyl.Validate.int(id, 1) and MySQL.single.await("SELECT * FROM veyl_apartment_maintenance WHERE id = ? AND status IN ('open','accepted','scheduled')", { id })
    local lease = r and Access.Lease(r.lease_id)
    local role = lease and Access.Get(lease, citizenid)
    if role ~= 'leaseholder' and role ~= 'roommate' then return Veyl.Err('NOT_FOUND', 'Request not found') end
    MySQL.update.await("UPDATE veyl_apartment_maintenance SET status = 'cancelled' WHERE id = ?", { id })
    return Veyl.Ok(nil, 'Request cancelled')
end, { cooldown = 500 })

---------------------------------------------------------------------------
-- Resident dashboard (phone app + standalone panel)
---------------------------------------------------------------------------
Veyl.RegisterCallback('dashboard', function(src, citizenid)
    local homes = Access.HomesOf(citizenid)
    local list = {}
    for _, h in ipairs(homes) do
        local unit = Apt.Unit(h.unit_id)
        local item = Lease.Public(h)
        item.role = h.role
        local _, perms = Access.Get(h, citizenid)
        item.perms = perms
        if h.role ~= 'guest' then
            item.roommates = {}
            for _, m in ipairs(MySQL.query.await('SELECT citizenid, perms, status, UNIX_TIMESTAMP(expires_at) AS expires FROM veyl_apartment_members WHERE lease_id = ?', { h.id }) or {}) do
                item.roommates[#item.roommates + 1] = { citizenid = m.citizenid, name = Apt.CharName(m.citizenid), status = m.status,
                    perms = Access.CleanPerms(Apt.Decode(m.perms, {})), expires = m.expires }
            end
            item.leaseholder = { citizenid = h.citizenid, name = Apt.CharName(h.citizenid) }
            item.guests = {}
            if perms.guests then
                for _, g in ipairs(MySQL.query.await([[SELECT id, citizenid, source, single_use, used_at, UNIX_TIMESTAMP(expires_at) AS expires FROM veyl_apartment_guests
                    WHERE lease_id = ? AND revoked_at IS NULL AND expires_at > NOW() ORDER BY expires_at]], { h.id }) or {}) do
                    item.guests[#item.guests + 1] = { id = g.id, name = Apt.CharName(g.citizenid), source = g.source, singleUse = g.single_use == 1,
                        used = g.used_at ~= nil, expires = g.expires }
                end
                item.visits = People.PendingVisits(h.id)
                item.blocked = {}
                for _, b in ipairs(MySQL.query.await('SELECT citizenid FROM veyl_apartment_blocks WHERE lease_id = ?', { h.id }) or {}) do
                    item.blocked[#item.blocked + 1] = { citizenid = b.citizenid, name = Apt.CharName(b.citizenid) }
                end
            end
            item.overdue = h.overdue_since ~= nil
            item.furnitureLimit = Apt.Type(unit).furnitureLimit
            local b = AptBuildings[unit.building]
            item.parking = b.parking and Community.Parking(b.parking) or nil
        end
        item.waypoint = { x = AptGeometry.ToWorld(unit, AptGeometry.Outside).x, y = AptGeometry.ToWorld(unit, AptGeometry.Outside).y }
        list[#list + 1] = item
    end
    local invites = {}
    for _, i in ipairs(MySQL.query.await([[SELECT m.lease_id, l.citizenid, l.unit_id FROM veyl_apartment_members m JOIN veyl_apartment_leases l ON l.id = m.lease_id
        WHERE m.citizenid = ? AND m.status = 'invited' AND m.expires_at > NOW() AND l.status = 'active']], { citizenid }) or {}) do
        invites[#invites + 1] = { leaseId = i.lease_id, from = Apt.CharName(i.citizenid), label = Apt.UnitLabel(Apt.Unit(i.unit_id)) }
    end
    local parcels = MySQL.scalar.await("SELECT COUNT(*) FROM veyl_apartment_parcels WHERE citizenid = ? AND status = 'waiting'", { citizenid }) or 0
    local recovery = MySQL.scalar.await("SELECT COUNT(*) FROM veyl_apartment_storage WHERE owner_cid = ? AND status = 'recovery' AND recover_until > NOW()", { citizenid }) or 0
    local p = Presence.Of(src)
    local pd = Veyl.GetPlayerData(src)
    return Veyl.Ok({
        homes = list, invites = invites, parcels = parcels, recovery = recovery,
        inside = p and { unitId = p.unitId, leaseId = p.leaseId, kind = p.kind } or nil,
        balances = { bank = pd and pd.money.bank or 0, cash = pd and pd.money.cash or 0 },
        categories = M.Categories, roommatePermissions = AptConfig.RoommatePermissions, phone = Apt.Has('phone'),
        maxGuestHours = AptConfig.Guests.MaxHours,
    })
end, { cooldown = 300 })

--- Parking: shown only when a building names a veyl_garages garage and that resource runs.
function Community.Parking(garageId)
    if not Apt.Has('garages') then return nil end
    local ok, places = pcall(function() return exports.veyl_garages:GetPlaces() end)
    if not ok or type(places) ~= 'table' then return nil end
    for _, p in ipairs(places) do if p.id == garageId then return { id = p.id, label = p.label, x = p.x, y = p.y } end end
    return nil
end

---------------------------------------------------------------------------
-- Periodic housekeeping (called from the billing tick)
---------------------------------------------------------------------------
function Community.Tick()
    if M.NpcFallbackMinutes then
        for _, r in ipairs(MySQL.query.await("SELECT id, citizenid FROM veyl_apartment_maintenance WHERE status = 'open' AND created_at < DATE_SUB(NOW(), INTERVAL ? MINUTE) LIMIT 20",
            { M.NpcFallbackMinutes }) or {}) do
            local n = MySQL.update.await([[UPDATE veyl_apartment_maintenance SET status = 'completed', staff_name = 'Front desk',
                note = 'Handled by building staff.' WHERE id = ? AND status = 'open']], { r.id })
            if n == 1 then Apt.Notify(r.citizenid, 'Maintenance update', 'The front desk handled your request.', { phoneOnly = true }) end
        end
    end
    -- Uncollected parcels are returned to sender after KeepDays (recorded; the items were never created).
    MySQL.update.await("UPDATE veyl_apartment_parcels SET status = 'returned' WHERE status = 'waiting' AND created_at < DATE_SUB(NOW(), INTERVAL ? DAY)", { P.KeepDays })
end
