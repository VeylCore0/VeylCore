-- Staff tools (chat/console commands, like veyl_admin). Read access and destructive actions are separate ACEs:
--   veyl.apartments.view    /aptfind /aptinfo /aptpos
--   veyl.apartments.manage  /aptend /aptkick /aptunit /aptstorage /aptpass
-- Every use is audited. Residents never get these through their own panel.

local function reply(src, msg, kind)
    if src == 0 then print('[veyl_apartments] ' .. msg) else Veyl.Notify(src, msg, kind or 'info', 9000) end
end

local function staff(name, perm, fn)
    RegisterCommand(name, function(src, args, raw)
        if not Veyl.HasPermission(src, perm) and not Veyl.HasPermission(src, 'admin') then
            Apt.Audit(src, 'admin_denied', { command = name })
            return reply(src, 'You do not have permission to use this command.', 'error')
        end
        Apt.Audit(src, 'admin_' .. name, { raw = raw:sub(1, 200) })
        CreateThread(function()
            local ok, err = pcall(fn, src, args)
            if not ok then reply(src, 'Command failed: ' .. tostring(err), 'error') end
        end)
    end, false)
end

local function leaseLine(l)
    local u = Apt.Unit(l.unit_id)
    return ('#%d %s | %s (%s) | %s | rent $%d/%dd | paid until %s%s'):format(l.id, u and Apt.UnitLabel(u) or ('unit ' .. l.unit_id),
        Apt.CharName(l.citizenid), l.citizenid, l.status, l.rent, l.interval_days, tostring(l.paid_until), l.overdue_since and ' | OVERDUE' or '')
end

staff('aptfind', 'apartments.view', function(src, args)
    local q = table.concat(args, ' ')
    local rows
    if q:match('^%d+$') then
        rows = MySQL.query.await("SELECT l.* FROM veyl_apartment_leases l JOIN veyl_apartment_units u ON u.id = l.unit_id WHERE (u.number = ? OR l.id = ?) AND l.status IN ('active','pending') LIMIT 10", { tonumber(q), tonumber(q) })
    elseif q ~= '' then
        rows = MySQL.query.await("SELECT * FROM veyl_apartment_leases WHERE citizenid = ? ORDER BY id DESC LIMIT 10", { q })
    else
        rows = MySQL.query.await("SELECT * FROM veyl_apartment_leases WHERE status = 'active' ORDER BY id DESC LIMIT 15")
    end
    if not rows or #rows == 0 then return reply(src, 'No leases found.') end
    for _, l in ipairs(rows) do reply(src, leaseLine(l)) end
end)

staff('aptinfo', 'apartments.view', function(src, args)
    local l = Access.Lease(tonumber(args[1]) or -1)
    if not l then return reply(src, 'Usage: /aptinfo <leaseId>', 'error') end
    reply(src, leaseLine(l))
    for _, m in ipairs(MySQL.query.await('SELECT * FROM veyl_apartment_members WHERE lease_id = ?', { l.id }) or {}) do
        reply(src, ('  roommate %s (%s) %s perms=%s'):format(Apt.CharName(m.citizenid), m.citizenid, m.status, m.perms))
    end
    for _, g in ipairs(MySQL.query.await('SELECT * FROM veyl_apartment_guests WHERE lease_id = ? AND revoked_at IS NULL AND expires_at > NOW()', { l.id }) or {}) do
        reply(src, ('  guest %s until %s (%s)'):format(g.citizenid, tostring(g.expires_at), g.source))
    end
    for _, p in ipairs(MySQL.query.await('SELECT * FROM veyl_apartment_payments WHERE lease_id = ? ORDER BY id DESC LIMIT 5', { l.id }) or {}) do
        reply(src, ('  payment %s period %d $%d by %s (%s)'):format(p.kind, p.period, p.amount, p.paid_by, p.op_id))
    end
    for _, s in ipairs(MySQL.query.await('SELECT * FROM veyl_apartment_storage WHERE lease_id = ?', { l.id }) or {}) do
        reply(src, ('  storage %s %s %s until %s'):format(s.stash_id, s.kind, s.status, tostring(s.recover_until)))
    end
    local f = MySQL.query.await("SELECT state, COUNT(*) AS n FROM veyl_apartment_furniture WHERE lease_id = ? GROUP BY state", { l.id }) or {}
    for _, r in ipairs(f) do reply(src, ('  furniture %s: %d'):format(r.state, r.n)) end
end)

--- Prints your position in a room's local space (for configuring) and in world space.
staff('aptpos', 'apartments.view', function(src)
    local pc = Veyl.GetPlayerCoords(src)
    local ped = GetPlayerPed(src)
    reply(src, ('world vector4(%.2f, %.2f, %.2f, %.1f)'):format(pc.x, pc.y, pc.z, GetEntityHeading(ped)))
    for _, u in pairs(Apt.unitsById) do
        if AptGeometry.Contains(u, pc, 0.0) then local l = AptGeometry.ToLocal(u, pc) reply(src, ('inside room %d: local (%.2f, %.2f, %.2f)'):format(u.number, l.x, l.y, l.z)) end
    end
end)

staff('aptend', 'apartments.manage', function(src, args)
    local l = Access.Lease(tonumber(args[1]) or -1)
    local reason = table.concat(args, ' ', 2)
    if not l or l.status ~= 'active' or #reason < 3 then return reply(src, 'Usage: /aptend <leaseId> <reason (required)>', 'error') end
    Lease.End(l, 'admin', ('%s: %s'):format(Veyl.GetCitizenId(src) or 'console', reason):sub(1, 64))
    reply(src, ('Lease #%d ended. Storage and furniture moved to recovery.'):format(l.id), 'success')
end)

staff('aptkick', 'apartments.manage', function(src, args)
    local unit = Apt.Unit(tonumber(args[1]) or -1)
    if not unit then return reply(src, 'Usage: /aptkick <unitId>', 'error') end
    Presence.ClearUnit(unit.id, 'Building staff asked everyone to step outside.')
    reply(src, 'Everyone inside was returned to the door.', 'success')
end)

staff('aptunit', 'apartments.manage', function(src, args)
    local unit = Apt.Unit(tonumber(args[1]) or -1)
    local on = args[2] == 'enable'
    if not unit or (args[2] ~= 'enable' and args[2] ~= 'disable') then return reply(src, 'Usage: /aptunit <unitId> enable|disable', 'error') end
    MySQL.update.await('UPDATE veyl_apartment_units SET disabled = ? WHERE id = ?', { on and 0 or 1, unit.id })
    unit.disabled = not on
    reply(src, ('%s is now %s for new leases.'):format(Apt.UnitLabel(unit), on and 'available' or 'unavailable'), 'success')
end)

staff('aptstorage', 'apartments.manage', function(src, args)
    if src == 0 then return reply(src, 'Run this in game.') end
    if not args[1] then return reply(src, 'Usage: /aptstorage <stashId> (see /aptinfo)', 'error') end
    if not Storage.AdminOpen(src, args[1]) then reply(src, 'Unknown stash.', 'error') end
end)

--- Gives yourself a short single-visit pass (e.g. to resolve a report). Recorded.
staff('aptpass', 'apartments.manage', function(src, args)
    local l = Access.Lease(tonumber(args[1]) or -1)
    local cid = Veyl.GetCitizenId(src)
    if not l or l.status ~= 'active' or not cid then return reply(src, 'Usage: /aptpass <leaseId>', 'error') end
    MySQL.insert.await([[INSERT INTO veyl_apartment_guests (lease_id, citizenid, granted_by, source, single_use, expires_at)
        VALUES (?, ?, ?, 'maintenance', 1, DATE_ADD(NOW(), INTERVAL 15 MINUTE))]], { l.id, cid, 'staff:' .. cid })
    reply(src, 'You have a 15-minute single-visit pass. The resident was notified.', 'success')
    Apt.Notify(l.citizenid, 'Building staff access', 'A staff member was given a short access pass to your home.', { phoneOnly = true })
end)
