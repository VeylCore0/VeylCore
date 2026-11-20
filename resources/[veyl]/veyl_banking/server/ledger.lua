-- veyl_banking ledger: the ONLY code that changes balances.
-- Guarantees:
--   * every change is one DB transaction: balance update + ledger row with a UNIQUE op_id
--   * per-account locks serialise changes, so balances can never go negative from races
--   * the same op_id can never apply twice (returns DUPLICATE_OPERATION with the original result)

Ledger = {}

local KINDS = { cash = true, bank = true }
local accountCache = {} -- ['character:12:cash'] = accountId

local function cacheKey(ownerType, ownerId, kind) return ownerType .. ':' .. ownerId .. ':' .. kind end

function Ledger.IsKind(kind) return KINDS[kind] == true end

--- Creates the character's cash and bank accounts if missing (idempotent).
function Ledger.EnsureCharacterAccounts(charId)
    for kind, start in pairs({ cash = BankingConfig.StartingCash, bank = BankingConfig.StartingBank }) do
        local key = cacheKey('character', charId, kind)
        if not accountCache[key] then
            local id = MySQL.scalar.await('SELECT id FROM veyl_bank_accounts WHERE owner_type = ? AND owner_id = ? AND kind = ?',
                { 'character', charId, kind })
            if not id then
                local ok = MySQL.transaction.await({
                    { query = 'INSERT INTO veyl_bank_accounts (owner_type, owner_id, kind, balance) VALUES (?, ?, ?, ?)',
                      values = { 'character', charId, kind, start } },
                    { query = [[INSERT INTO veyl_bank_ledger (op_id, account_id, delta, balance_after, reason)
                        SELECT CONCAT('open:', id), id, balance, balance, 'Account opened' FROM veyl_bank_accounts
                        WHERE owner_type = ? AND owner_id = ? AND kind = ?]],
                      values = { 'character', charId, kind } },
                })
                id = MySQL.scalar.await('SELECT id FROM veyl_bank_accounts WHERE owner_type = ? AND owner_id = ? AND kind = ?',
                    { 'character', charId, kind })
                if not ok and not id then error('could not create ' .. kind .. ' account for character ' .. charId) end
            end
            accountCache[key] = id
        end
    end
end

function Ledger.GetAccountId(charId, kind)
    local key = cacheKey('character', charId, kind)
    if not accountCache[key] then Ledger.EnsureCharacterAccounts(charId) end
    return accountCache[key]
end

function Ledger.GetBalance(accountId)
    return MySQL.scalar.await('SELECT balance FROM veyl_bank_accounts WHERE id = ?', { accountId })
end

function Ledger.GetOperation(opId)
    return MySQL.single.await('SELECT op_id, account_id, delta, balance_after, reason, created_at FROM veyl_bank_ledger WHERE op_id = ?',
        { opId })
end

local function validAmount(amount)
    return Veyl.Validate.int(amount, 1, BankingConfig.MaxSingleTransaction)
end

local function validOp(opId, reason)
    return Veyl.Validate.str(opId, 3, 90) and Veyl.Validate.str(reason, 1, 128)
end

--- Applies a signed delta to one account. Returns Veyl.Ok({ balance }) or Veyl.Err(...)
function Ledger.Apply(accountId, delta, reason, opId, actor)
    return Veyl.WithLock('acct:' .. accountId, function()
        local existing = Ledger.GetOperation(opId)
        if existing then
            return Veyl.Err('DUPLICATE_OPERATION', 'Operation already processed', { balance = existing.balance_after })
        end
        local balance = Ledger.GetBalance(accountId)
        if balance == nil then return Veyl.Err('NOT_FOUND', 'Account not found') end
        local newBalance = balance + delta
        if newBalance < 0 then return Veyl.Err('INSUFFICIENT_FUNDS', 'Insufficient funds', { balance = balance }) end
        local ok = MySQL.transaction.await({
            { query = 'UPDATE veyl_bank_accounts SET balance = balance + ? WHERE id = ?', values = { delta, accountId } },
            { query = 'INSERT INTO veyl_bank_ledger (op_id, account_id, delta, balance_after, reason, actor) VALUES (?, ?, ?, ?, ?, ?)',
              values = { opId, accountId, delta, newBalance, reason, actor } },
        })
        if not ok then
            return Veyl.Err('DATABASE_ERROR', 'Transaction failed; no money was moved')
        end
        return Veyl.Ok({ balance = newBalance })
    end)
end

function Ledger.Credit(charId, kind, amount, reason, opId, actor)
    if not Ledger.IsKind(kind) or not validAmount(amount) or not validOp(opId, reason) then
        return Veyl.Err('INVALID_INPUT', 'Invalid credit request')
    end
    return Ledger.Apply(Ledger.GetAccountId(charId, kind), amount, reason, opId, actor)
end

function Ledger.Debit(charId, kind, amount, reason, opId, actor)
    if not Ledger.IsKind(kind) or not validAmount(amount) or not validOp(opId, reason) then
        return Veyl.Err('INVALID_INPUT', 'Invalid debit request')
    end
    return Ledger.Apply(Ledger.GetAccountId(charId, kind), -amount, reason, opId, actor)
end

--- Moves money between two accounts atomically. Legs are recorded as opId and opId..'#in'.
function Ledger.Transfer(fromAccount, toAccount, amount, reason, opId, actor)
    if not validAmount(amount) or not validOp(opId, reason) then return Veyl.Err('INVALID_INPUT', 'Invalid transfer') end
    if fromAccount == toAccount then return Veyl.Err('INVALID_INPUT', 'Cannot transfer to the same account') end
    local first, second = math.min(fromAccount, toAccount), math.max(fromAccount, toAccount)
    return Veyl.WithLock('acct:' .. first, function()
        return Veyl.WithLock('acct:' .. second, function()
            if Ledger.GetOperation(opId) then return Veyl.Err('DUPLICATE_OPERATION', 'Operation already processed') end
            local fromBal, toBal = Ledger.GetBalance(fromAccount), Ledger.GetBalance(toAccount)
            if fromBal == nil or toBal == nil then return Veyl.Err('NOT_FOUND', 'Account not found') end
            if fromBal < amount then return Veyl.Err('INSUFFICIENT_FUNDS', 'Insufficient funds', { balance = fromBal }) end
            local ok = MySQL.transaction.await({
                { query = 'UPDATE veyl_bank_accounts SET balance = balance - ? WHERE id = ?', values = { amount, fromAccount } },
                { query = 'UPDATE veyl_bank_accounts SET balance = balance + ? WHERE id = ?', values = { amount, toAccount } },
                { query = 'INSERT INTO veyl_bank_ledger (op_id, account_id, delta, balance_after, reason, actor) VALUES (?, ?, ?, ?, ?, ?)',
                  values = { opId, fromAccount, -amount, fromBal - amount, reason, actor } },
                { query = 'INSERT INTO veyl_bank_ledger (op_id, account_id, delta, balance_after, reason, actor) VALUES (?, ?, ?, ?, ?, ?)',
                  values = { opId .. '#in', toAccount, amount, toBal + amount, reason, actor } },
            })
            if not ok then return Veyl.Err('DATABASE_ERROR', 'Transfer failed; no money was moved') end
            return Veyl.Ok({ fromBalance = fromBal - amount, toBalance = toBal + amount })
        end)
    end)
end

function Ledger.History(charId, limit)
    local cash, bank = Ledger.GetAccountId(charId, 'cash'), Ledger.GetAccountId(charId, 'bank')
    return MySQL.query.await([[SELECT l.delta, l.balance_after, l.reason, a.kind,
        DATE_FORMAT(l.created_at, '%m-%d %H:%i') AS at
        FROM veyl_bank_ledger l JOIN veyl_bank_accounts a ON a.id = l.account_id
        WHERE l.account_id IN (?, ?) ORDER BY l.id DESC LIMIT ?]], { cash, bank, limit or 15 }) or {}
end
