-- veyl_banking server: migrations, exports for other resources, and player-facing bank actions.

Veyl.Startup({ 'veyl_core' }, function()
    return Veyl.Migrate({
        {
            id = '001_accounts_ledger',
            sql = {
                [[CREATE TABLE IF NOT EXISTS veyl_bank_accounts (
                    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                    owner_type ENUM('character','business') NOT NULL,
                    owner_id INT UNSIGNED NOT NULL,
                    kind VARCHAR(16) NOT NULL,
                    balance BIGINT NOT NULL DEFAULT 0,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (id),
                    UNIQUE KEY uq_owner_kind (owner_type, owner_id, kind),
                    CONSTRAINT chk_balance_nonneg CHECK (balance >= 0)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
                [[CREATE TABLE IF NOT EXISTS veyl_bank_ledger (
                    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                    op_id VARCHAR(100) NOT NULL,
                    account_id INT UNSIGNED NOT NULL,
                    delta BIGINT NOT NULL,
                    balance_after BIGINT NOT NULL,
                    reason VARCHAR(128) NOT NULL,
                    actor VARCHAR(64) NULL,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (id),
                    UNIQUE KEY uq_op (op_id),
                    KEY idx_account (account_id, id)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            },
        },
    })
end)

---------------------------------------------------------------------------
-- Display sync (read-only for clients: state bags set by the server)
---------------------------------------------------------------------------
local function pushBalances(charId)
    local src = Veyl.GetSourceByCharacter(charId)
    if not src then return end
    local cash = Ledger.GetBalance(Ledger.GetAccountId(charId, 'cash'))
    local bank = Ledger.GetBalance(Ledger.GetAccountId(charId, 'bank'))
    local state = Player(src).state
    state:set('veylCash', cash, true)
    state:set('veylBank', bank, true)
end

local function afterChange(charId, res)
    if res and res.ok then pushBalances(charId) end
    return res
end

AddEventHandler('veyl:characterLoaded', function(src, charId)
    CreateThread(function()
        local ok, err = pcall(Ledger.EnsureCharacterAccounts, charId)
        if not ok then
            print(('^1[veyl_banking] could not prepare accounts for %s: %s^7'):format(charId, tostring(err)))
            Veyl.Notify(src, 'Banking is unavailable right now.', 'error')
            return
        end
        pushBalances(charId)
    end)
end)

AddEventHandler('veyl:characterUnloading', function(src)
    if GetPlayerName(src) then
        Player(src).state:set('veylCash', nil, true)
        Player(src).state:set('veylBank', nil, true)
    end
end)

---------------------------------------------------------------------------
-- Server exports (async: call with Veyl.Await('veyl_banking', name, timeout, ...))
---------------------------------------------------------------------------
local function invoker() return GetInvokingResource() or 'veyl_banking' end

Veyl.AsyncExport('GetBalances', function(charId)
    if not Veyl.IsReady() then return Veyl.Err('NOT_READY', 'Banking not ready') end
    return Veyl.Ok({
        cash = Ledger.GetBalance(Ledger.GetAccountId(charId, 'cash')),
        bank = Ledger.GetBalance(Ledger.GetAccountId(charId, 'bank')),
    })
end)

--- TryDebit(characterId, 'cash'|'bank', amount, reason, operationId)
Veyl.AsyncExport('TryDebit', function(charId, kind, amount, reason, opId)
    if not Veyl.IsReady() then return Veyl.Err('NOT_READY', 'Banking not ready') end
    return afterChange(charId, Ledger.Debit(charId, kind, amount, reason, opId, invoker()))
end)

--- Credit(characterId, 'cash'|'bank', amount, reason, operationId)
Veyl.AsyncExport('Credit', function(charId, kind, amount, reason, opId)
    if not Veyl.IsReady() then return Veyl.Err('NOT_READY', 'Banking not ready') end
    return afterChange(charId, Ledger.Credit(charId, kind, amount, reason, opId, invoker()))
end)

--- Transfer({ fromCharacter, fromKind, toCharacter, toKind }, amount, reason, operationId)
Veyl.AsyncExport('Transfer', function(route, amount, reason, opId)
    if not Veyl.IsReady() then return Veyl.Err('NOT_READY', 'Banking not ready') end
    if type(route) ~= 'table' or not Ledger.IsKind(route.fromKind) or not Ledger.IsKind(route.toKind) then
        return Veyl.Err('INVALID_INPUT', 'Invalid transfer route')
    end
    local res = Ledger.Transfer(Ledger.GetAccountId(route.fromCharacter, route.fromKind),
        Ledger.GetAccountId(route.toCharacter, route.toKind), amount, reason, opId, invoker())
    if res.ok then
        pushBalances(route.fromCharacter)
        if route.toCharacter ~= route.fromCharacter then pushBalances(route.toCharacter) end
    end
    return res
end)

--- GetOperation(operationId) -> Ok(row|nil). Used for reconciliation after interruptions.
Veyl.AsyncExport('GetOperation', function(opId)
    return Veyl.Ok(Ledger.GetOperation(opId))
end)

---------------------------------------------------------------------------
-- Player-facing bank actions (validated server-side, server generates operation ids)
---------------------------------------------------------------------------
local function nearBank(src)
    local c = Veyl.GetPlayerCoords(src)
    if not c then return false end
    for _, b in ipairs(BankingConfig.Banks) do
        if #(c - b) <= BankingConfig.BankUseDistance + 1.5 then return true end
    end
    return false
end

Veyl.RegisterCallback('overview', function(src, charId)
    if not nearBank(src) then return Veyl.Err('TOO_FAR', 'You need to be at a bank') end
    local history = Ledger.History(charId, 12)
    return Veyl.Ok({
        cash = Ledger.GetBalance(Ledger.GetAccountId(charId, 'cash')),
        bank = Ledger.GetBalance(Ledger.GetAccountId(charId, 'bank')),
        history = history,
    })
end, { cooldown = 750 })

local function moveOwn(src, charId, fromKind, toKind, amount, label)
    if not nearBank(src) then return Veyl.Err('TOO_FAR', 'You need to be at a bank') end
    if not Veyl.Validate.int(amount, 1, BankingConfig.MaxSingleTransaction) then
        return Veyl.Err('INVALID_INPUT', 'Enter a whole amount between 1 and ' .. BankingConfig.MaxSingleTransaction)
    end
    local res = Ledger.Transfer(Ledger.GetAccountId(charId, fromKind), Ledger.GetAccountId(charId, toKind),
        amount, label, Veyl.NewId('bank:' .. label:lower()), 'player')
    if res.ok then
        pushBalances(charId)
        res.message = ('%s $%d'):format(label, amount)
    end
    return res
end

Veyl.RegisterCallback('deposit', function(src, charId, amount)
    return moveOwn(src, charId, 'cash', 'bank', amount, 'Deposit')
end, { cooldown = 1000 })

Veyl.RegisterCallback('withdraw', function(src, charId, amount)
    return moveOwn(src, charId, 'bank', 'cash', amount, 'Withdrawal')
end, { cooldown = 1000 })

Veyl.RegisterCallback('transfer', function(src, charId, targetSrc, amount)
    if not nearBank(src) then return Veyl.Err('TOO_FAR', 'You need to be at a bank') end
    if not Veyl.Validate.int(targetSrc, 1, 65535) or not Veyl.Validate.int(amount, 1, BankingConfig.MaxSingleTransaction) then
        return Veyl.Err('INVALID_INPUT', 'Enter a valid player ID and amount')
    end
    local targetChar = Veyl.GetCharacterId(targetSrc)
    if not targetChar then return Veyl.Err('NOT_FOUND', 'That player is not online with a character') end
    if targetChar == charId then return Veyl.Err('INVALID_INPUT', 'Use deposit/withdraw for your own accounts') end
    local res = Ledger.Transfer(Ledger.GetAccountId(charId, 'bank'), Ledger.GetAccountId(targetChar, 'bank'),
        amount, 'Bank transfer', Veyl.NewId('bank:transfer'), 'player')
    if res.ok then
        pushBalances(charId)
        pushBalances(targetChar)
        Veyl.Notify(targetSrc, ('You received a bank transfer of $%d'):format(amount), 'success')
        Veyl.Audit(src, 'bank_transfer', { to = targetChar, amount = amount })
        res.message = ('Sent $%d'):format(amount)
    end
    return res
end, { cooldown = 2000 })

-- /givecash <id> <amount> : hand cash to a nearby player
Veyl.RegisterCallback('giveCash', function(src, charId, targetSrc, amount)
    if not Veyl.Validate.int(targetSrc, 1, 65535) or not Veyl.Validate.int(amount, 1, BankingConfig.MaxSingleTransaction) then
        return Veyl.Err('INVALID_INPUT', 'Usage: /givecash [id] [amount]')
    end
    local targetChar = Veyl.GetCharacterId(targetSrc)
    if not targetChar or targetChar == charId then return Veyl.Err('NOT_FOUND', 'Player not found') end
    local a, b = Veyl.GetPlayerCoords(src), Veyl.GetPlayerCoords(targetSrc)
    if not a or not b or #(a - b) > BankingConfig.GiveCashDistance then return Veyl.Err('TOO_FAR', 'Get closer to them') end
    local res = Ledger.Transfer(Ledger.GetAccountId(charId, 'cash'), Ledger.GetAccountId(targetChar, 'cash'),
        amount, 'Cash handed over', Veyl.NewId('cash:give'), 'player')
    if res.ok then
        pushBalances(charId)
        pushBalances(targetChar)
        Veyl.Notify(targetSrc, ('You were handed $%d'):format(amount), 'success')
        res.message = ('Gave $%d'):format(amount)
    end
    return res
end, { cooldown = 2000 })
