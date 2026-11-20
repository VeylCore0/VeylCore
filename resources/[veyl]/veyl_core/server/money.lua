-- veyl_core money: the single authority for personal cash/bank/crypto.
--
-- Two call styles over one ledger:
--   * Legacy (QB contract) Add/Remove/Set: validated against the in-memory balance, return a boolean
--     immediately, and write through to the DB in order via the per-citizen queue (with retries).
--   * Durable CreditOnce/DebitOnce/Transfer: return only after the DB transaction commits. The operation id
--     is UNIQUE in veyl_money_ledger, so the same id can never apply twice (DUPLICATE_OPERATION).
--
-- Every DB change is: conditional UPDATE (balance + delta >= 0) + ledger INSERT in one transaction.
-- In-memory balances for online players always equal DB balance + still-queued deltas.

Money = {}

local TYPES = {}
for _, t in ipairs(VeylConfig.MoneyTypes) do TYPES[t] = true end

function Money.IsType(t) return TYPES[t] == true end

local function validAmount(amount)
    return type(amount) == 'number' and amount == amount and amount % 1 == 0 and amount > 0
        and amount <= VeylServerConfig.MaxSingleMoneyChange
end

local function validReason(reason) return type(reason) == 'string' and #reason >= 1 and #reason <= 128 end
local function validOp(opId) return type(opId) == 'string' and #opId >= 3 and #opId <= 90 end

local function emitChange(p, moneyType, amount, action, reason)
    if not p then return end
    TriggerEvent('VeylCore:Server:OnMoneyChange', p.source, p.citizenid, moneyType, amount, action, reason)
    TriggerClientEvent('VeylCore:Client:OnMoneyChange', p.source, moneyType, amount, action, reason)
    Core.SyncPlayer(p)
end

---------------------------------------------------------------------------
-- DB primitive (runs inside the citizen queue)
---------------------------------------------------------------------------
local function dbApply(citizenid, moneyType, delta, reason, opId, actor)
    if MySQL.scalar.await('SELECT 1 FROM veyl_money_ledger WHERE op_id = ?', { opId }) then
        return Veyl.Err('DUPLICATE_OPERATION', 'Operation already processed')
    end
    local ok = MySQL.transaction.await({
        {
            query = [[UPDATE veyl_money SET balance = balance + ?, last_op = ?
                WHERE citizenid = ? AND type = ? AND balance + ? >= 0]],
            values = { delta, opId, citizenid, moneyType, delta },
        },
        {
            query = [[INSERT INTO veyl_money_ledger (op_id, citizenid, type, delta, balance_after, reason, actor)
                SELECT ?, citizenid, type, ?, balance, ?, ? FROM veyl_money WHERE citizenid = ? AND type = ? AND last_op = ?]],
            values = { opId, delta, reason, actor, citizenid, moneyType, opId },
        },
    })
    if not ok then
        if MySQL.scalar.await('SELECT 1 FROM veyl_money_ledger WHERE op_id = ?', { opId }) then
            return Veyl.Err('DUPLICATE_OPERATION', 'Operation already processed')
        end
        return Veyl.Err('DATABASE_ERROR', 'Database write failed; no money was moved')
    end
    local after = MySQL.scalar.await('SELECT balance_after FROM veyl_money_ledger WHERE op_id = ?', { opId })
    if after == nil then return Veyl.Err('INSUFFICIENT_FUNDS', 'Insufficient funds') end
    return Veyl.Ok({ balance = after })
end

--- Legacy write-through with retries (memory has already changed and the caller already got `true`).
local function writeThrough(p, moneyType, delta, reason, actor)
    local citizenid = p.citizenid
    local opId = Veyl.NewId('m')
    CoreEnqueue(citizenid, function()
        local res
        for attempt = 1, VeylServerConfig.MoneyWriteRetries do
            res = dbApply(citizenid, moneyType, delta, reason, opId, actor)
            if res.ok or res.code ~= 'DATABASE_ERROR' then break end
            Wait(2000 * attempt)
        end
        if not res.ok and res.code ~= 'DUPLICATE_OPERATION' then
            print(('^1[veyl_core] CRITICAL: money write for %s (%s %d) failed: %s^7'):format(citizenid, moneyType, delta, res.code))
            exports.veyl_core:Audit(nil, 'veyl_core', 'money_write_failed',
                { citizenid = citizenid, type = moneyType, delta = delta, reason = reason, code = res.code })
        end
        return res
    end)
end

---------------------------------------------------------------------------
-- Legacy (synchronous) API for online players
---------------------------------------------------------------------------
function Money.Get(src, moneyType)
    local p = Core.Players[tonumber(src)]
    if not p or not Money.IsType(moneyType) then return 0 end
    return p.money[moneyType] or 0
end

function Money.Add(src, moneyType, amount, reason, actor)
    local p = Core.Players[tonumber(src)]
    amount = tonumber(amount)
    if not p or not Money.IsType(moneyType) or not validAmount(amount) then return false end
    reason = validReason(reason) and reason or 'unspecified'
    p.money[moneyType] = p.money[moneyType] + amount
    writeThrough(p, moneyType, amount, reason, actor or GetInvokingResource())
    emitChange(p, moneyType, amount, 'add', reason)
    return true
end

function Money.Remove(src, moneyType, amount, reason, actor)
    local p = Core.Players[tonumber(src)]
    amount = tonumber(amount)
    if not p or not Money.IsType(moneyType) or not validAmount(amount) then return false end
    if p.money[moneyType] < amount then return false end
    reason = validReason(reason) and reason or 'unspecified'
    p.money[moneyType] = p.money[moneyType] - amount
    writeThrough(p, moneyType, -amount, reason, actor or GetInvokingResource())
    emitChange(p, moneyType, amount, 'remove', reason)
    return true
end

function Money.Set(src, moneyType, amount, reason)
    local p = Core.Players[tonumber(src)]
    amount = tonumber(amount)
    if not p or not Money.IsType(moneyType) or type(amount) ~= 'number' or amount < 0 or amount % 1 ~= 0 then return false end
    local delta = amount - p.money[moneyType]
    if delta == 0 then return true end
    if math.abs(delta) > VeylServerConfig.MaxSingleMoneyChange then return false end
    reason = validReason(reason) and reason or 'set'
    p.money[moneyType] = amount
    writeThrough(p, moneyType, delta, reason, GetInvokingResource())
    emitChange(p, moneyType, math.abs(delta), 'set', reason)
    return true
end

---------------------------------------------------------------------------
-- Durable (repeat-safe) API. Works for online and offline characters.
---------------------------------------------------------------------------
local function durable(citizenid, moneyType, delta, reason, opId, actor)
    if type(citizenid) ~= 'string' or not Money.IsType(moneyType) or not validAmount(math.abs(delta))
        or not validReason(reason) or not validOp(opId) then
        return Veyl.Err('INVALID_INPUT', 'Invalid money operation')
    end
    local src = Core.ByCitizen[citizenid]
    local p = src and Core.Players[src]
    -- Debits reserve against the live balance first, so concurrent legacy removals cannot overspend.
    if p and delta < 0 then
        if p.money[moneyType] < -delta then
            return Veyl.Err('INSUFFICIENT_FUNDS', 'Insufficient funds', { balance = p.money[moneyType] })
        end
        p.money[moneyType] = p.money[moneyType] + delta
    end
    local res = Citizen.Await(CoreEnqueue(citizenid, function()
        return dbApply(citizenid, moneyType, delta, reason, opId, actor)
    end))
    -- Only touch the object that existed when we started; a re-login reloads from the DB after this write.
    if p and Core.Players[p.source] == p then
        if delta < 0 and not res.ok then
            p.money[moneyType] = p.money[moneyType] - delta -- release the reservation
        elseif delta > 0 and res.ok then
            p.money[moneyType] = p.money[moneyType] + delta
        end
        if res.ok then emitChange(p, moneyType, math.abs(delta), delta > 0 and 'add' or 'remove', reason) end
    end
    return res
end

function Money.CreditOnce(citizenid, moneyType, amount, reason, opId, actor)
    return durable(citizenid, moneyType, tonumber(amount) or 0, reason, opId, actor)
end

function Money.DebitOnce(citizenid, moneyType, amount, reason, opId, actor)
    return durable(citizenid, moneyType, -(tonumber(amount) or 0), reason, opId, actor)
end

--- Atomic transfer between two character accounts (or between one character's own accounts).
--- Ledger legs: opId (debit) and opId..'#in' (credit).
function Money.Transfer(fromCid, fromType, toCid, toType, amount, reason, opId, actor)
    amount = tonumber(amount)
    if type(fromCid) ~= 'string' or type(toCid) ~= 'string' or not Money.IsType(fromType) or not Money.IsType(toType)
        or not validAmount(amount) or not validReason(reason) or not validOp(opId) then
        return Veyl.Err('INVALID_INPUT', 'Invalid transfer')
    end
    if fromCid == toCid and fromType == toType then return Veyl.Err('INVALID_INPUT', 'Same account') end
    local fromSrc, toSrc = Core.ByCitizen[fromCid], Core.ByCitizen[toCid]
    local fromP, toP = fromSrc and Core.Players[fromSrc], toSrc and Core.Players[toSrc]
    if fromP then
        if fromP.money[fromType] < amount then
            return Veyl.Err('INSUFFICIENT_FUNDS', 'Insufficient funds', { balance = fromP.money[fromType] })
        end
        fromP.money[fromType] = fromP.money[fromType] - amount
    end
    local res = Citizen.Await(CoreEnqueue(fromCid, function()
        if MySQL.scalar.await('SELECT 1 FROM veyl_money_ledger WHERE op_id = ?', { opId }) then
            return Veyl.Err('DUPLICATE_OPERATION', 'Operation already processed')
        end
        local inOp = opId .. '#in'
        local ok = MySQL.transaction.await({
            { query = [[UPDATE veyl_money SET balance = balance - ?, last_op = ? WHERE citizenid = ? AND type = ? AND balance >= ?]],
              values = { amount, opId, fromCid, fromType, amount } },
            { query = [[INSERT INTO veyl_money_ledger (op_id, citizenid, type, delta, balance_after, reason, actor)
                SELECT ?, citizenid, type, ?, balance, ?, ? FROM veyl_money WHERE citizenid = ? AND type = ? AND last_op = ?]],
              values = { opId, -amount, reason, actor, fromCid, fromType, opId } },
            { query = [[UPDATE veyl_money SET balance = balance + ?, last_op = ? WHERE citizenid = ? AND type = ?
                AND (SELECT COUNT(*) FROM veyl_money_ledger WHERE op_id = ?) = 1]],
              values = { amount, inOp, toCid, toType, opId } },
            { query = [[INSERT INTO veyl_money_ledger (op_id, citizenid, type, delta, balance_after, reason, actor)
                SELECT ?, citizenid, type, ?, balance, ?, ? FROM veyl_money WHERE citizenid = ? AND type = ? AND last_op = ?]],
              values = { inOp, amount, reason, actor, toCid, toType, inOp } },
        })
        if not ok then return Veyl.Err('DATABASE_ERROR', 'Transfer failed; no money was moved') end
        local legs = MySQL.scalar.await('SELECT COUNT(*) FROM veyl_money_ledger WHERE op_id IN (?, ?)', { opId, inOp })
        if legs == 2 then return Veyl.Ok({}) end
        if legs == 0 then return Veyl.Err('INSUFFICIENT_FUNDS', 'Insufficient funds') end
        -- One leg only means the receiving account row is missing: report loudly, never silently.
        print(('^1[veyl_core] CRITICAL: transfer %s recorded %d leg(s)^7'):format(opId, legs))
        return Veyl.Err('INTERNAL', 'Transfer incomplete; staff have been alerted')
    end))
    if fromP and Core.Players[fromP.source] == fromP then
        if res.ok then
            emitChange(fromP, fromType, amount, 'remove', reason)
        else
            fromP.money[fromType] = fromP.money[fromType] + amount
        end
    end
    if res.ok then
        toSrc = Core.ByCitizen[toCid]
        toP = toSrc and Core.Players[toSrc]
        if toP then
            toP.money[toType] = toP.money[toType] + amount
            emitChange(toP, toType, amount, 'add', reason)
        end
    end
    return res
end

function Money.GetOperation(opId)
    return MySQL.single.await('SELECT op_id, citizenid, type, delta, balance_after, reason, actor, created_at FROM veyl_money_ledger WHERE op_id = ?',
        { opId })
end

function Money.History(citizenid, limit)
    return MySQL.query.await([[SELECT type, delta, balance_after, reason, DATE_FORMAT(created_at, '%m-%d %H:%i') AS at
        FROM veyl_money_ledger WHERE citizenid = ? ORDER BY id DESC LIMIT ?]], { citizenid, math.min(tonumber(limit) or 15, 100) }) or {}
end

--- Loads balances for login. Runs through the citizen queue so it observes every pending write.
function Money.Load(citizenid)
    return Citizen.Await(CoreEnqueue(citizenid, function()
        for t, start in pairs(VeylServerConfig.StartingMoney) do
            if Money.IsType(t) then
                MySQL.insert.await('INSERT IGNORE INTO veyl_money (citizenid, type, balance) VALUES (?, ?, ?)', { citizenid, t, 0 })
            end
        end
        local rows = MySQL.query.await('SELECT type, balance FROM veyl_money WHERE citizenid = ?', { citizenid }) or {}
        local money = {}
        for _, t in ipairs(VeylConfig.MoneyTypes) do money[t] = 0 end
        for _, r in ipairs(rows) do if Money.IsType(r.type) then money[r.type] = r.balance end end
        return money
    end))
end
