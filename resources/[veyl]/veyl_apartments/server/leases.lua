-- Leases: browsing, signing, rent, reminders, overdue/grace/eviction, cancellation and deposit refunds.
-- All money moves through durable core operations with an id per purpose:
--   apt:lease:<leaseId>            first period + deposit
--   apt:rent:<leaseId>:<period>    each rent period (automatic AND manual payments share it -> never charged twice)
--   apt:deposit:<leaseId>          deposit refund
-- Billing uses database timestamps, so it runs whether or not the resident is online.

Lease = {}
local B = AptConfig.Billing

---------------------------------------------------------------------------
-- Front desk location (derived from the rooms; ground height is found client-side)
---------------------------------------------------------------------------
function Lease.DeskPoint(buildingId)
    local b = Apt.buildings[buildingId]
    if not b then return nil end
    local sx, sy, n = 0, 0, 0
    for _, u in ipairs(b.units) do
        if u.floor == 1 then
            local p = AptGeometry.ToWorld(u, AptGeometry.Outside)
            sx, sy, n = sx + p.x, sy + p.y, n + 1
        end
    end
    if n == 0 then return nil end
    return vector2(sx / n, sy / n)
end

local function nearDesk(src, buildingId)
    local p = Lease.DeskPoint(buildingId)
    local pc = Veyl.GetPlayerCoords(src)
    return p and pc and #(vector2(pc.x, pc.y) - p) <= 8.0
end
Lease.NearDesk = nearDesk

---------------------------------------------------------------------------
-- Shapes
---------------------------------------------------------------------------
function Lease.Terms(t)
    return {
        ('Rent is $%d every %d days, charged from your bank account when each period ends.'):format(t.rent, t.intervalDays),
        ('You pay the first period and a $%d deposit today.'):format(t.deposit),
        ('If a payment fails we retry every %d hours; after %d days overdue the lease ends and your storage moves to recovery.'):format(B.RetryHours, B.GraceDays),
        ('Belongings are never deleted: after a lease ends you can collect them at the front desk for %d days.'):format(B.RecoveryDays),
        'If you move out yourself with no rent owed, your deposit is refunded. Rent already paid is not refunded.',
    }
end

function Lease.Public(lease)
    if not lease then return nil end
    local unit = Apt.Unit(lease.unit_id)
    -- Dates as unix seconds (oxmysql returns DATETIME as milliseconds; asking MariaDB keeps this exact everywhere).
    local ts = MySQL.single.await([[SELECT UNIX_TIMESTAMP(paid_until) AS pu, UNIX_TIMESTAMP(next_charge_at) AS nc, UNIX_TIMESTAMP(overdue_since) AS od,
        UNIX_TIMESTAMP(started_at) AS st, UNIX_TIMESTAMP(NOW()) AS now FROM veyl_apartment_leases WHERE id = ?]], { lease.id }) or {}
    return {
        id = lease.id, unitId = lease.unit_id, number = unit and unit.number, floor = unit and unit.floor,
        building = unit and unit.building, buildingLabel = unit and AptBuildings[unit.building].label,
        address = unit and AptBuildings[unit.building].address,
        status = lease.status, rent = lease.rent, deposit = lease.deposit, intervalDays = lease.interval_days,
        paidUntil = ts.pu, nextChargeAt = ts.nc, autopay = lease.autopay == 1 or lease.autopay == true, serverTime = ts.now,
        overdueSince = ts.od, directory = lease.directory == 1 or lease.directory == true,
        startedAt = ts.st, periodsPaid = lease.periods_paid,
    }
end

---------------------------------------------------------------------------
-- Browsing
---------------------------------------------------------------------------
Veyl.RegisterCallback('catalog', function(src, citizenid, buildingId)
    local b = Apt.buildings[buildingId]
    if not b then return Veyl.Err('NOT_FOUND', 'Unknown building') end
    if not nearDesk(src, buildingId) then return Veyl.Err('TOO_FAR', 'Talk to the front desk') end
    local taken = {}
    for _, r in ipairs(MySQL.query.await("SELECT unit_id FROM veyl_apartment_leases WHERE status IN ('pending','active')") or {}) do taken[r.unit_id] = true end
    local types, units = {}, {}
    for _, u in ipairs(b.units) do
        local t = AptTypes[u.type]
        types[u.type] = types[u.type] or { id = u.type, label = t.label, description = t.description, rent = t.rent, intervalDays = t.intervalDays,
            deposit = t.deposit, initial = t.rent + t.deposit, storage = t.storage.slots, furnitureLimit = t.furnitureLimit, image = t.image,
            amenities = t.amenities, terms = Lease.Terms(t), available = 0 }
        local free = not taken[u.id] and not u.disabled
        if free then types[u.type].available = types[u.type].available + 1 end
        units[#units + 1] = { id = u.id, number = u.number, floor = u.floor, wing = u.wing, type = u.type, available = free }
    end
    local list = {}
    for _, t in pairs(types) do list[#list + 1] = t end
    local mine = Access.LeaseOf(citizenid)
    local pd = Veyl.GetPlayerData(src)
    return Veyl.Ok({
        building = { id = buildingId, label = b.def.label, address = b.def.address, amenities = b.def.amenities },
        types = list, units = units, myLease = Lease.Public(mine),
        canLease = (MySQL.scalar.await("SELECT COUNT(*) FROM veyl_apartment_leases WHERE citizenid = ? AND status IN ('pending','active')", { citizenid }) or 0) < AptConfig.MaxLeasesPerCharacter,
        balances = { bank = pd and pd.money.bank or 0, cash = pd and pd.money.cash or 0 },
        tour = AptConfig.Tour.Enabled,
    })
end, { cooldown = 400 })

---------------------------------------------------------------------------
-- Signing
---------------------------------------------------------------------------
local function activate(lease, method)
    MySQL.update.await("UPDATE veyl_apartment_leases SET status = 'active' WHERE id = ? AND status = 'pending'", { lease.id })
    MySQL.insert.await([[INSERT IGNORE INTO veyl_apartment_payments (lease_id, kind, period, amount, paid_by, method, op_id, note)
        VALUES (?, 'initial', 1, ?, ?, ?, ?, 'First period + deposit')]], { lease.id, lease.rent + lease.deposit, lease.citizenid, method or 'bank', 'apt:lease:' .. lease.id })
    Storage.EnsureForLease(lease.id)
    Furniture.AttachStored(lease.citizenid, lease.id)
    local unit = Apt.Unit(lease.unit_id)
    Apt.Notify(lease.citizenid, 'Welcome home', ('%s is yours. Your digital key is active.'):format(Apt.UnitLabel(unit)), { kind = 'success', dedupe = 'lease:' .. lease.id })
end

--- lease({ unitId, method, clientOp, autopay }) -> Ok(lease)
Veyl.RegisterCallback('lease', function(src, citizenid, req)
    if type(req) ~= 'table' or not Apt.ValidOp(req.clientOp) then return Veyl.Err('INVALID_INPUT', 'Invalid request') end
    local unit = Apt.Unit(req.unitId)
    if not unit then return Veyl.Err('NOT_FOUND', 'Unknown room') end
    if not nearDesk(src, unit.building) then return Veyl.Err('TOO_FAR', 'Talk to the front desk') end
    local method = req.method == 'cash' and 'cash' or 'bank'
    return Apt.WithLock('cid:' .. citizenid, function()
        -- A repeated click with the same request id returns what already happened.
        local prior = MySQL.single.await('SELECT * FROM veyl_apartment_leases WHERE citizenid = ? AND client_op = ?', { citizenid, req.clientOp })
        if prior then
            if prior.status == 'active' then return Veyl.Ok(Lease.Public(prior), 'Your lease is active') end
            if prior.status == 'pending' then return Veyl.Err('PENDING', 'Your payment is being confirmed') end
            return Veyl.Err('FAILED', 'That lease request did not go through. Start again.')
        end
        local live = MySQL.scalar.await("SELECT COUNT(*) FROM veyl_apartment_leases WHERE citizenid = ? AND status IN ('pending','active')", { citizenid }) or 0
        if live >= AptConfig.MaxLeasesPerCharacter then return Veyl.Err('LIMIT', 'You already have a home') end
        if unit.disabled then return Veyl.Err('UNAVAILABLE', 'That room is not available') end
        local t = Apt.Type(unit)
        local total = t.rent + t.deposit
        local ok, id = pcall(MySQL.insert.await, [[INSERT INTO veyl_apartment_leases
            (unit_id, citizenid, status, rent, deposit, interval_days, periods_paid, started_at, paid_until, next_charge_at, autopay, client_op)
            VALUES (?, ?, 'pending', ?, ?, ?, 1, NOW(), DATE_ADD(NOW(), INTERVAL ? DAY), DATE_ADD(NOW(), INTERVAL ? DAY), ?, ?)]],
            { unit.id, citizenid, t.rent, t.deposit, t.intervalDays, t.intervalDays, t.intervalDays, req.autopay == false and 0 or 1, req.clientOp })
        if not ok or not id then return Veyl.Err('TAKEN', 'Someone just leased that room. Pick another.') end
        local lease = Access.Lease(id)
        local pay = Apt.Core('DebitOnce', citizenid, method, total, ('Lease: %s'):format(Apt.UnitLabel(unit)), 'apt:lease:' .. id)
        if pay.ok or pay.code == 'DUPLICATE_OPERATION' then
            activate(lease, method)
            Apt.Audit(src, 'lease_signed', { lease = id, unit = unit.key, total = total })
            return Veyl.Ok(Lease.Public(Access.Lease(id)), ('Room %d is yours'):format(unit.number))
        end
        if pay.code == 'TIMEOUT' then return Veyl.Err('PENDING', 'Your payment is being confirmed. Check back in a moment.') end
        MySQL.update.await("UPDATE veyl_apartment_leases SET status = 'void', end_reason = 'payment_failed', ended_at = NOW() WHERE id = ?", { id })
        if pay.code == 'INSUFFICIENT_FUNDS' then return Veyl.Err('INSUFFICIENT_FUNDS', ('You need $%d in your %s'):format(total, method == 'bank' and 'bank account' or 'wallet')) end
        return Veyl.Err(pay.code or 'FAILED', pay.message or 'Payment failed')
    end)
end)

--- Resolves leases whose first payment never confirmed (crash or timeout during signing).
function Lease.ReconcilePending()
    local rows = MySQL.query.await("SELECT * FROM veyl_apartment_leases WHERE status = 'pending' AND created_at < DATE_SUB(NOW(), INTERVAL ? MINUTE)",
        { B.PendingLeaseMinutes }) or {}
    for _, l in ipairs(rows) do
        local op = Apt.Core('GetMoneyOperation', 'apt:lease:' .. l.id)
        if op.ok and op.data then activate(l, 'bank')
        elseif op.ok then MySQL.update.await("UPDATE veyl_apartment_leases SET status = 'void', end_reason = 'payment_unconfirmed', ended_at = NOW() WHERE id = ? AND status = 'pending'", { l.id }) end
    end
end

---------------------------------------------------------------------------
-- Rent
---------------------------------------------------------------------------
--- Marks `period` as paid once (guarded by periods_paid so it can never advance twice).
local function recordPeriod(lease, period, method, payer, op)
    MySQL.insert.await([[INSERT IGNORE INTO veyl_apartment_payments (lease_id, kind, period, amount, paid_by, method, op_id)
        VALUES (?, 'rent', ?, ?, ?, ?, ?)]], { lease.id, period, lease.rent, payer, method, op })
    -- next_charge_at is assigned BEFORE paid_until: MariaDB evaluates SET left to right with updated values.
    MySQL.update.await([[UPDATE veyl_apartment_leases SET periods_paid = ?, next_charge_at = DATE_ADD(paid_until, INTERVAL interval_days DAY),
        paid_until = DATE_ADD(paid_until, INTERVAL interval_days DAY), overdue_since = NULL WHERE id = ? AND periods_paid = ?]],
        { period, lease.id, period - 1 })
end

local function overdue(lease)
    MySQL.update.await([[UPDATE veyl_apartment_leases SET overdue_since = COALESCE(overdue_since, paid_until),
        next_charge_at = DATE_ADD(NOW(), INTERVAL ? HOUR) WHERE id = ?]], { B.RetryHours, lease.id })
end

--- Charges the next period of one lease if it is due. Safe to call repeatedly (and after a crash).
function Lease.ChargeDue(leaseId)
    return Apt.WithLock('lease:' .. leaseId, function()
        local lease = Access.Lease(leaseId)
        if not lease or lease.status ~= 'active' then return end
        local due = MySQL.scalar.await('SELECT next_charge_at <= NOW() FROM veyl_apartment_leases WHERE id = ?', { leaseId })
        if due ~= 1 and due ~= true then return end
        local period = lease.periods_paid + 1
        local op = ('apt:rent:%d:%d'):format(lease.id, period)
        local unit = Apt.Unit(lease.unit_id)
        if lease.autopay == 1 or lease.autopay == true then
            local res = Apt.Core('DebitOnce', lease.citizenid, 'bank', lease.rent, ('Rent: %s (period %d)'):format(Apt.UnitLabel(unit), period), op)
            if res.ok or res.code == 'DUPLICATE_OPERATION' then
                recordPeriod(lease, period, 'bank', lease.citizenid, op)
                Apt.Notify(lease.citizenid, 'Rent paid', ('$%d for %s'):format(lease.rent, Apt.UnitLabel(unit)), { phoneOnly = true, dedupe = op })
                return
            end
            if res.code == 'TIMEOUT' then return end -- unknown outcome: the next tick retries the SAME operation id
            overdue(lease)
            Apt.Notify(lease.citizenid, 'Rent payment failed', ('We could not take $%d. Pay from your phone or the front desk.'):format(lease.rent),
                { kind = 'error', dedupe = op .. ':failed' })
        else
            overdue(lease)
            Apt.Notify(lease.citizenid, 'Rent is due', ('$%d for %s. Pay from your phone or the front desk.'):format(lease.rent, Apt.UnitLabel(unit)),
                { kind = 'warning', dedupe = op .. ':due' })
        end
        local l2 = Access.Lease(leaseId)
        local late = l2.overdue_since and MySQL.scalar.await('SELECT DATE_ADD(overdue_since, INTERVAL ? DAY) <= NOW() FROM veyl_apartment_leases WHERE id = ?', { B.GraceDays, leaseId })
        if (late == 1 or late == true) and B.EvictionPolicy == 'end_lease' then
            Lease.End(l2, 'evicted', 'system')
        end
    end)
end

--- Manual payment of the next period (leaseholder, or anyone with the 'lease' permission). Pays at most one period ahead.
Veyl.RegisterCallback('payRent', function(src, citizenid, leaseId, method, clientOp)
    if not Veyl.Validate.int(leaseId, 1) or not Apt.ValidOp(clientOp) then return Veyl.Err('INVALID_INPUT', 'Invalid request') end
    method = method == 'cash' and 'cash' or 'bank'
    return Apt.WithLock('lease:' .. leaseId, function()
        local lease = Access.Lease(leaseId)
        if not Access.Can(lease, citizenid, 'lease') then return Veyl.Err('NO_PERMISSION', 'Only the leaseholder can pay rent') end
        if method == 'cash' and not nearDesk(src, Apt.Unit(lease.unit_id).building) then return Veyl.Err('TOO_FAR', 'Pay cash at the front desk') end
        local ahead = MySQL.scalar.await('SELECT paid_until > DATE_ADD(NOW(), INTERVAL interval_days DAY) FROM veyl_apartment_leases WHERE id = ?', { leaseId })
        if ahead == 1 or ahead == true then return Veyl.Err('PAID_AHEAD', 'Rent is already paid for the next period') end
        local period = lease.periods_paid + 1
        local op = ('apt:rent:%d:%d'):format(lease.id, period)
        local unit = Apt.Unit(lease.unit_id)
        local res = Apt.Core('DebitOnce', citizenid, method, lease.rent, ('Rent: %s (period %d)'):format(Apt.UnitLabel(unit), period), op)
        if res.ok or res.code == 'DUPLICATE_OPERATION' then
            recordPeriod(lease, period, method, citizenid, op)
            Apt.Audit(src, 'rent_paid', { lease = leaseId, period = period })
            return Veyl.Ok(Lease.Public(Access.Lease(leaseId)), ('Paid $%d rent'):format(lease.rent))
        end
        if res.code == 'TIMEOUT' then return Veyl.Err('PENDING', 'Payment is being confirmed. It will not be charged twice.') end
        if res.code == 'INSUFFICIENT_FUNDS' then return Veyl.Err('INSUFFICIENT_FUNDS', ('You need $%d'):format(lease.rent)) end
        return res
    end)
end)

Veyl.RegisterCallback('setAutopay', function(_, citizenid, leaseId, on)
    local lease = Veyl.Validate.int(leaseId, 1) and Access.Lease(leaseId)
    if not Access.Can(lease, citizenid, 'lease') then return Veyl.Err('NO_PERMISSION', 'Only the leaseholder can change this') end
    MySQL.update.await('UPDATE veyl_apartment_leases SET autopay = ? WHERE id = ?', { on and 1 or 0, leaseId })
    return Veyl.Ok({ autopay = on == true }, on and 'Automatic rent is on' or 'Automatic rent is off')
end, { cooldown = 500 })

Veyl.RegisterCallback('setDirectory', function(_, citizenid, leaseId, on)
    local lease = Veyl.Validate.int(leaseId, 1) and Access.Lease(leaseId)
    if not Access.Can(lease, citizenid, 'lease') then return Veyl.Err('NO_PERMISSION', 'Only the leaseholder can change this') end
    MySQL.update.await('UPDATE veyl_apartment_leases SET directory = ? WHERE id = ?', { on and 1 or 0, leaseId })
    return Veyl.Ok({ directory = on == true }, on and 'Visitors can find you at the front desk' or 'You are hidden from the visitor directory')
end, { cooldown = 500 })

Veyl.RegisterCallback('payments', function(_, citizenid, leaseId, beforeId)
    local lease = Veyl.Validate.int(leaseId, 1) and Access.Lease(leaseId)
    local role = lease and Access.Get(lease, citizenid)
    if role ~= 'leaseholder' and role ~= 'roommate' then return Veyl.Err('NO_PERMISSION', 'Not your home') end
    local rows = MySQL.query.await([[SELECT id, kind, period, amount, method, note, UNIX_TIMESTAMP(created_at) AS at FROM veyl_apartment_payments
        WHERE lease_id = ? AND id < ? ORDER BY id DESC LIMIT 20]], { leaseId, Veyl.Validate.int(beforeId, 1) and beforeId or 2147483647 }) or {}
    return Veyl.Ok({ items = rows, nextBefore = #rows == 20 and rows[#rows].id or nil })
end, { cooldown = 300 })

---------------------------------------------------------------------------
-- Ending a lease
---------------------------------------------------------------------------
local function refundDeposit(lease)
    if lease.deposit <= 0 or lease.deposit_returned == 1 then return true end
    local op = 'apt:deposit:' .. lease.id
    local res = Apt.Core('CreditOnce', lease.citizenid, 'bank', lease.deposit, 'Deposit refund', op)
    if res.ok or res.code == 'DUPLICATE_OPERATION' then
        MySQL.update.await('UPDATE veyl_apartment_leases SET deposit_returned = 1 WHERE id = ?', { lease.id })
        MySQL.insert.await([[INSERT IGNORE INTO veyl_apartment_payments (lease_id, kind, period, amount, paid_by, method, op_id, note)
            VALUES (?, 'refund', 0, ?, ?, 'bank', ?, 'Deposit refund')]], { lease.id, lease.deposit, lease.citizenid, op })
        return true
    end
    return false -- retried by the billing tick
end

--- Ends an active lease. reason: 'moved_out' | 'evicted' | 'admin' | 'character_deleted'.
function Lease.End(lease, reason, by)
    local n = MySQL.update.await([[UPDATE veyl_apartment_leases SET status = 'ended', ended_at = NOW(), end_reason = ?, ended_by = ?
        WHERE id = ? AND status = 'active']], { reason, tostring(by):sub(1, 64), lease.id })
    if n ~= 1 then return false end
    Storage.ToRecovery(lease.id)
    Furniture.DetachOnEnd(lease.id)
    MySQL.update.await('UPDATE veyl_apartment_guests SET revoked_at = NOW() WHERE lease_id = ? AND revoked_at IS NULL', { lease.id })
    local members = MySQL.query.await('SELECT citizenid FROM veyl_apartment_members WHERE lease_id = ?', { lease.id }) or {}
    MySQL.update.await('DELETE FROM veyl_apartment_members WHERE lease_id = ?', { lease.id })
    local unit = Apt.Unit(lease.unit_id)
    local label = unit and Apt.UnitLabel(unit) or 'your home'
    if reason == 'moved_out' and not lease.overdue_since then refundDeposit(Access.Lease(lease.id)) end
    local why = ({ moved_out = 'You moved out', evicted = 'Your lease ended after unpaid rent', admin = 'Your lease was ended by management' })[reason] or 'Your lease ended'
    Apt.Notify(lease.citizenid, why, ('%s. Collect your belongings at the front desk within %d days.'):format(label, B.RecoveryDays), { kind = 'warning', dedupe = 'end:' .. lease.id })
    for _, m in ipairs(members) do Apt.Notify(m.citizenid, 'Home closed', ('%s is no longer leased.'):format(label), { dedupe = 'end:' .. lease.id .. ':' .. m.citizenid }) end
    Presence.RecheckLease(lease.id)
    return true
end

Veyl.RegisterCallback('moveOut', function(src, citizenid, leaseId, confirmText)
    if not Veyl.Validate.int(leaseId, 1) then return Veyl.Err('INVALID_INPUT', 'Invalid request') end
    if confirmText ~= 'MOVE OUT' then return Veyl.Err('CONFIRM', 'Type MOVE OUT to confirm') end
    return Apt.WithLock('lease:' .. leaseId, function()
        local lease = Access.Lease(leaseId)
        if not lease or lease.citizenid ~= citizenid or lease.status ~= 'active' then return Veyl.Err('NO_PERMISSION', 'Only the leaseholder can end the lease') end
        Lease.End(lease, 'moved_out', citizenid)
        Apt.Audit(src, 'lease_moved_out', { lease = leaseId })
        return Veyl.Ok(nil, 'You moved out. Your storage is waiting at the front desk.')
    end)
end)

---------------------------------------------------------------------------
-- Scheduler: timestamp-driven, bounded batches, never a tight loop
---------------------------------------------------------------------------
local function tick()
    Lease.ReconcilePending()
    for _, r in ipairs(MySQL.query.await("SELECT id FROM veyl_apartment_leases WHERE status = 'active' AND next_charge_at <= NOW() ORDER BY next_charge_at LIMIT 25") or {}) do
        Lease.ChargeDue(r.id)
    end
    -- Advance reminders (once per period).
    for _, l in ipairs(MySQL.query.await([[SELECT * FROM veyl_apartment_leases WHERE status = 'active' AND overdue_since IS NULL
        AND paid_until <= DATE_ADD(NOW(), INTERVAL ? HOUR) AND reminded_for < periods_paid + 1 LIMIT 50]], { B.ReminderHours }) or {}) do
        local unit = Apt.Unit(l.unit_id)
        MySQL.update.await('UPDATE veyl_apartment_leases SET reminded_for = ? WHERE id = ?', { l.periods_paid + 1, l.id })
        Apt.Notify(l.citizenid, 'Rent due soon', ('$%d for %s %s'):format(l.rent, unit and Apt.UnitLabel(unit) or 'your home',
            (l.autopay == 1 or l.autopay == true) and 'will be taken from your bank automatically.' or 'is due. Pay from your phone.'),
            { phoneOnly = true, dedupe = ('remind:%d:%d'):format(l.id, l.periods_paid + 1) })
    end
    -- Deposit refunds that failed earlier.
    for _, l in ipairs(MySQL.query.await([[SELECT * FROM veyl_apartment_leases WHERE status = 'ended' AND end_reason = 'moved_out' AND overdue_since IS NULL
        AND deposit > 0 AND deposit_returned = 0 LIMIT 20]]) or {}) do refundDeposit(l) end
    -- Deleted characters (core soft-deletes): their lease ends; storage and furniture stay recoverable by staff.
    for _, l in ipairs(MySQL.query.await([[SELECT l.* FROM veyl_apartment_leases l JOIN veyl_players p ON p.citizenid = l.citizenid
        WHERE l.status = 'active' AND p.deleted_at IS NOT NULL LIMIT 10]]) or {}) do Lease.End(l, 'character_deleted', 'system') end
    for _, m in ipairs(MySQL.query.await([[SELECT m.lease_id, m.citizenid FROM veyl_apartment_members m JOIN veyl_players p ON p.citizenid = m.citizenid
        WHERE p.deleted_at IS NOT NULL LIMIT 10]]) or {}) do
        MySQL.update.await('DELETE FROM veyl_apartment_members WHERE lease_id = ? AND citizenid = ?', { m.lease_id, m.citizenid })
        Storage.LockerToRecovery(m.lease_id, m.citizenid)
        Furniture.DetachOwner(m.lease_id, m.citizenid)
    end
    if Community and Community.Tick then Community.Tick() end
end

AddEventHandler('veyl_apartments:ready', function()
    CreateThread(function()
        while true do
            local ok, err = pcall(tick)
            if not ok then print(('^1[veyl_apartments] billing tick failed: %s^7'):format(tostring(err))) end
            Wait(B.TickSeconds * 1000)
        end
    end)
end)
Lease.Tick = tick
Lease.RefundDeposit = refundDeposit
