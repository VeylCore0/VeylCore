-- veyl_banking server: bank screen actions. Personal balances belong to veyl_core; every movement is a durable core
-- transfer with an operation id derived from the character and the client's request id (safe to retry).

Veyl.Startup({ 'veyl_core' }, function() return true end)

local function core(name, ...) return Veyl.Await('veyl_core', name, 15000, ...) end
local recipients = {} -- [src] = { token, citizenid, name, accountMasked, expires }

local function nearBank(src)
    local c = Veyl.GetPlayerCoords(src)
    if not c then return false end
    for _, b in ipairs(BankingConfig.Banks) do
        if #(c - b) <= BankingConfig.BankUseDistance + 1.5 then return true end
    end
    return false
end

local function validAmount(a) return Veyl.Validate.int(a, 1, BankingConfig.MaxSingleTransaction) end
local function validOp(id) return Veyl.Validate.str(id, 6, 64, '^[%w%-]+$') end
local function mask(account) return type(account) == 'string' and #account >= 4 and ('VC •••• %s'):format(account:sub(-4)) or 'VC ••••' end

local ICONS = { paycheck = 'briefcase', purchase = 'cart', refund = 'cart', fuel = 'car', transfer = 'transfer', deposit = 'money', withdrawal = 'money' }
local function iconFor(reason)
    local r = tostring(reason):lower()
    for key, icon in pairs(ICONS) do if r:find(key, 1, true) then return icon end end
    return nil
end

local function toActivity(rows)
    local out = {}
    for i, r in ipairs(rows or {}) do
        out[i] = { id = tostring(r.id), type = r.type, delta = r.delta, balance = r.balance_after, reason = r.reason, at = r.at, icon = iconFor(r.reason) }
    end
    return out
end

local function overview(src, citizenid)
    local pd = Veyl.GetPlayerData(src)
    local recent = core('GetMoneyHistoryPage', citizenid, 3, 0, 'all')
    local world = GlobalState.veylWorld
    return {
        name = ('%s %s'):format(pd.charinfo.firstname or '', pd.charinfo.lastname or ''),
        hour = world and world.hour or tonumber(os.date('%H')),
        bank = pd.money.bank, cash = pd.money.cash,
        account = pd.charinfo.account or '', accountMasked = mask(pd.charinfo.account),
        recent = recent.ok and toActivity(recent.data.rows) or {},
    }
end

Veyl.RegisterCallback('overview', function(src, citizenid)
    if not nearBank(src) then return Veyl.Err('TOO_FAR', 'You need to be at a bank') end
    return Veyl.Ok(overview(src, citizenid))
end, { cooldown = 500 })

Veyl.RegisterCallback('history', function(src, citizenid, offset, filter)
    if not nearBank(src) then return Veyl.Err('TOO_FAR', 'You need to be at a bank') end
    if not Veyl.Validate.int(offset, 0, 100000) then offset = 0 end
    if filter ~= 'in' and filter ~= 'out' then filter = 'all' end
    local res = core('GetMoneyHistoryPage', citizenid, 10, offset, filter)
    if not res.ok then return res end
    return Veyl.Ok({ rows = toActivity(res.data.rows), nextOffset = res.data.nextOffset })
end, { cooldown = 300 })

--- Deposit/withdraw between the character's own cash and bank.
local function moveOwn(src, citizenid, fromType, toType, amount, clientOp, label)
    if not nearBank(src) then return Veyl.Err('TOO_FAR', 'You need to be at a bank') end
    if not validAmount(amount) then return Veyl.Err('INVALID_INPUT', ('Enter a whole amount from $1 to $%d'):format(BankingConfig.MaxSingleTransaction)) end
    if not validOp(clientOp) then return Veyl.Err('INVALID_INPUT', 'Invalid request') end
    local opId = ('bank:%s:%s'):format(citizenid, clientOp)
    local res = core('TransferMoney', citizenid, fromType, citizenid, toType, amount, label, opId)
    if res.code == 'DUPLICATE_OPERATION' then res = Veyl.Ok(nil) end -- already applied by an earlier attempt
    if not res.ok then return res end
    return Veyl.Ok(overview(src, citizenid), ('%s $%d'):format(label, amount))
end

Veyl.RegisterCallback('deposit', function(src, citizenid, amount, clientOp)
    return moveOwn(src, citizenid, 'cash', 'bank', amount, clientOp, 'Deposit')
end, { cooldown = 750 })

Veyl.RegisterCallback('withdraw', function(src, citizenid, amount, clientOp)
    return moveOwn(src, citizenid, 'bank', 'cash', amount, clientOp, 'Withdrawal')
end, { cooldown = 750 })

--- Resolves an account number server-side and issues a short-lived token for the confirmed recipient.
Veyl.RegisterCallback('resolveRecipient', function(src, citizenid, account)
    if not nearBank(src) then return Veyl.Err('TOO_FAR', 'You need to be at a bank') end
    if not Veyl.Validate.str(account, 6, 24, '^[%w]+$') then return Veyl.Err('INVALID_INPUT', 'Enter a valid account number') end
    local res = core('ResolveBankAccount', account:upper())
    if not res.ok then return Veyl.Err('NOT_FOUND', 'No account with that number') end
    if res.data.citizenid == citizenid then return Veyl.Err('INVALID_INPUT', 'Use deposit/withdraw for your own account') end
    local token = Veyl.NewId('rcpt')
    recipients[src] = { token = token, citizenid = res.data.citizenid, name = res.data.name, accountMasked = mask(account:upper()), expires = os.time() + 90 }
    return Veyl.Ok({ token = token, name = res.data.name, accountMasked = mask(account:upper()) })
end, { cooldown = 750 })

Veyl.RegisterCallback('transfer', function(src, citizenid, token, amount, reference, clientOp)
    if not nearBank(src) then return Veyl.Err('TOO_FAR', 'You need to be at a bank') end
    local r = recipients[src]
    if not r or r.token ~= token or os.time() > r.expires then return Veyl.Err('INVALID_STATE', 'Please confirm the recipient again') end
    if not validAmount(amount) then return Veyl.Err('INVALID_INPUT', 'Enter a valid amount') end
    if not validOp(clientOp) then return Veyl.Err('INVALID_INPUT', 'Invalid request') end
    reference = type(reference) == 'string' and reference:gsub('[^%w %-%.,#/]', ''):sub(1, 40) or ''
    local reason = reference ~= '' and ('Transfer: %s'):format(reference) or 'Bank transfer'
    local opId = ('bank:%s:%s'):format(citizenid, clientOp)
    local res = core('TransferMoney', citizenid, 'bank', r.citizenid, 'bank', amount, reason, opId)
    if res.code == 'DUPLICATE_OPERATION' then res = Veyl.Ok(nil) end
    if not res.ok then return res end
    recipients[src] = nil
    local targetSrc = Veyl.GetSourceByCitizenId(r.citizenid)
    if targetSrc then Veyl.Notify(targetSrc, ('You received a bank transfer of $%d'):format(amount), 'success') end
    Veyl.Audit(src, 'bank_transfer', { to = r.citizenid, amount = amount })
    return Veyl.Ok(overview(src, citizenid), ('Sent $%d to %s'):format(amount, r.name))
end, { cooldown = 1500 })

--- status(clientOp) -> whether a timed-out deposit/withdraw/transfer was applied.
Veyl.RegisterCallback('status', function(_, citizenid, clientOp)
    if not validOp(clientOp) then return Veyl.Err('INVALID_INPUT', 'Invalid request') end
    local res = core('GetMoneyOperation', ('bank:%s:%s'):format(citizenid, clientOp))
    if not res.ok then return res end
    return res.data and Veyl.Ok({ applied = true }) or Veyl.Err('NOT_FOUND', 'Not applied')
end, { cooldown = 300 })

-- /givecash <id> <amount>: hand cash to a nearby player
Veyl.RegisterCallback('giveCash', function(src, citizenid, targetSrc, amount)
    if not Veyl.Validate.int(targetSrc, 1, 65535) or not validAmount(amount) then
        return Veyl.Err('INVALID_INPUT', 'Usage: /givecash [id] [amount]')
    end
    local target = Veyl.GetCitizenId(targetSrc)
    if not target or target == citizenid then return Veyl.Err('NOT_FOUND', 'Player not found') end
    local a, b = Veyl.GetPlayerCoords(src), Veyl.GetPlayerCoords(targetSrc)
    if not a or not b or #(a - b) > BankingConfig.GiveCashDistance or GetPlayerRoutingBucket(src) ~= GetPlayerRoutingBucket(targetSrc) then
        return Veyl.Err('TOO_FAR', 'Get closer to them')
    end
    local res = core('TransferMoney', citizenid, 'cash', target, 'cash', amount, 'Cash handed over', Veyl.NewId('cash:give'))
    if res.ok then
        Veyl.Notify(targetSrc, ('You were handed $%d'):format(amount), 'success')
        res.message = ('Gave $%d'):format(amount)
    end
    return res
end, { cooldown = 2000 })

AddEventHandler('playerDropped', function() recipients[source] = nil end)
