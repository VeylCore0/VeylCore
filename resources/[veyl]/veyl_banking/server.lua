-- veyl_banking server: bank counter UI actions. Personal balances belong to veyl_core; every movement here is a
-- durable core transfer with a server-generated operation id. Removing this resource never affects balances.

Veyl.Startup({ 'veyl_core' }, function() return true end)

local function core(name, ...) return Veyl.Await('veyl_core', name, 15000, ...) end

local function nearBank(src)
    local c = Veyl.GetPlayerCoords(src)
    if not c then return false end
    for _, b in ipairs(BankingConfig.Banks) do
        if #(c - b) <= BankingConfig.BankUseDistance + 1.5 then return true end
    end
    return false
end

local function validAmount(amount) return Veyl.Validate.int(amount, 1, BankingConfig.MaxSingleTransaction) end

Veyl.RegisterCallback('overview', function(src, citizenid)
    if not nearBank(src) then return Veyl.Err('TOO_FAR', 'You need to be at a bank') end
    local pd = Veyl.GetPlayerData(src)
    local history = core('GetMoneyHistory', citizenid, 12)
    return Veyl.Ok({ cash = pd.money.cash, bank = pd.money.bank, history = history.ok and history.data or {} })
end, { cooldown = 750 })

local function moveOwn(src, citizenid, fromType, toType, amount, label)
    if not nearBank(src) then return Veyl.Err('TOO_FAR', 'You need to be at a bank') end
    if not validAmount(amount) then
        return Veyl.Err('INVALID_INPUT', 'Enter a whole amount between 1 and ' .. BankingConfig.MaxSingleTransaction)
    end
    local res = core('TransferMoney', citizenid, fromType, citizenid, toType, amount, label, Veyl.NewId('bank'))
    if res.ok then res.message = ('%s $%d'):format(label, amount) end
    return res
end

Veyl.RegisterCallback('deposit', function(src, citizenid, amount)
    return moveOwn(src, citizenid, 'cash', 'bank', amount, 'Deposit')
end, { cooldown = 1000 })

Veyl.RegisterCallback('withdraw', function(src, citizenid, amount)
    return moveOwn(src, citizenid, 'bank', 'cash', amount, 'Withdrawal')
end, { cooldown = 1000 })

Veyl.RegisterCallback('transfer', function(src, citizenid, targetSrc, amount)
    if not nearBank(src) then return Veyl.Err('TOO_FAR', 'You need to be at a bank') end
    if not Veyl.Validate.int(targetSrc, 1, 65535) or not validAmount(amount) then
        return Veyl.Err('INVALID_INPUT', 'Enter a valid player ID and amount')
    end
    local target = Veyl.GetCitizenId(targetSrc)
    if not target then return Veyl.Err('NOT_FOUND', 'That player is not online with a character') end
    if target == citizenid then return Veyl.Err('INVALID_INPUT', 'Use deposit/withdraw for your own accounts') end
    local res = core('TransferMoney', citizenid, 'bank', target, 'bank', amount, 'Bank transfer', Veyl.NewId('bank:xfer'))
    if res.ok then
        Veyl.Notify(targetSrc, ('You received a bank transfer of $%d'):format(amount), 'success')
        Veyl.Audit(src, 'bank_transfer', { to = target, amount = amount })
        res.message = ('Sent $%d'):format(amount)
    end
    return res
end, { cooldown = 2000 })

Veyl.RegisterCallback('giveCash', function(src, citizenid, targetSrc, amount)
    if not Veyl.Validate.int(targetSrc, 1, 65535) or not validAmount(amount) then
        return Veyl.Err('INVALID_INPUT', 'Usage: /givecash [id] [amount]')
    end
    local target = Veyl.GetCitizenId(targetSrc)
    if not target or target == citizenid then return Veyl.Err('NOT_FOUND', 'Player not found') end
    local a, b = Veyl.GetPlayerCoords(src), Veyl.GetPlayerCoords(targetSrc)
    if not a or not b or #(a - b) > BankingConfig.GiveCashDistance then return Veyl.Err('TOO_FAR', 'Get closer to them') end
    local res = core('TransferMoney', citizenid, 'cash', target, 'cash', amount, 'Cash handed over', Veyl.NewId('cash:give'))
    if res.ok then
        Veyl.Notify(targetSrc, ('You were handed $%d'):format(amount), 'success')
        res.message = ('Gave $%d'):format(amount)
    end
    return res
end, { cooldown = 2000 })
