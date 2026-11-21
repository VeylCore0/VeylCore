-- Bank app: balance, activity and transfers through the core ledger (veyl_core). Every transfer is a durable
-- TransferMoney with an operation id built from the character and the phone's request id, so a retry can never pay
-- twice. Recipients are resolved on the server first and confirmed with a short-lived token.

local function core(name, ...) return Veyl.Await('veyl_core', name, 15000, ...) end
local pending = {} -- [src] = { token, citizenid, name, label, expires }
AddEventHandler('playerDropped', function() pending[source] = nil end)

local function mask(account) return type(account) == 'string' and #account >= 4 and ('•••• %s'):format(account:sub(-4)) or '••••' end
local function validOp(id) return Veyl.Validate.str(id, 6, 64, '^[%w%-]+$') end

local function activity(rows)
    local out = {}
    for i, r in ipairs(rows or {}) do
        out[i] = { id = tostring(r.id), type = r.type, delta = r.delta, balance = r.balance_after, reason = r.reason, at = r.at }
    end
    return out
end

local function overview(src, citizenid)
    local pd = Veyl.GetPlayerData(src)
    if not pd then return nil end
    local recent = core('GetMoneyHistoryPage', citizenid, 5, 0, 'all')
    return {
        name = ('%s %s'):format(pd.charinfo.firstname or '', pd.charinfo.lastname or ''),
        bank = pd.money.bank or 0, cash = pd.money.cash or 0,
        account = pd.charinfo.account or '', accountMasked = mask(pd.charinfo.account),
        recent = recent.ok and activity(recent.data.rows) or {}, max = PhoneConfig.Bank.MaxTransfer,
    }
end

Veyl.RegisterCallback('bankOverview', function(src, citizenid)
    if not Phone.Session(src) then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    local o = overview(src, citizenid)
    if not o then return Veyl.Err('NOT_READY', 'Banking is unavailable right now') end
    return Veyl.Ok(o)
end, { cooldown = 400 })

Veyl.RegisterCallback('bankHistory', function(src, citizenid, offset)
    if not Phone.Session(src) then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    if not Veyl.Validate.int(offset, 0, 100000) then offset = 0 end
    local res = core('GetMoneyHistoryPage', citizenid, 15, offset, 'all')
    if not res.ok then return res end
    return Veyl.Ok({ rows = activity(res.data.rows), nextOffset = res.data.nextOffset })
end, { cooldown = 300 })

--- bankResolve(target): a 7-digit phone number or a bank account number -> { token, name, label }
Veyl.RegisterCallback('bankResolve', function(src, citizenid, target)
    local s = Phone.Session(src)
    if not s then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    if type(target) ~= 'string' or #target > 24 then return Veyl.Err('INVALID_INPUT', 'Enter a phone number or account number') end
    local cid, name, label
    local number = Phone.NormalizeNumber(target)
    if number then
        cid = Phone.CidByNumber(number)
        if not cid then return Veyl.Err('NOT_FOUND', 'That number is not in service') end
        name = MySQL.scalar.await('SELECT display_name FROM veyl_phone_accounts WHERE citizenid = ?', { cid }) or 'Resident'
        label = Phone.FormatNumber(number)
    else
        local account = target:gsub('%s', ''):upper()
        if not account:match('^[%w]+$') or #account < 6 then return Veyl.Err('INVALID_INPUT', 'Enter a phone number or account number') end
        local res = core('ResolveBankAccount', account)
        if not res.ok then return Veyl.Err('NOT_FOUND', 'No account with that number') end
        cid, name, label = res.data.citizenid, res.data.name, mask(account)
    end
    if cid == citizenid then return Veyl.Err('INVALID_INPUT', 'You cannot send money to yourself') end
    local token = Veyl.NewId('pbank')
    pending[src] = { token = token, citizenid = cid, name = name, label = label, expires = os.time() + 90 }
    return Veyl.Ok({ token = token, name = name, label = label })
end, { cooldown = 600 })

--- bankSend(token, amount, reference, clientOp) -> Ok(overview)
Veyl.RegisterCallback('bankSend', function(src, citizenid, token, amount, reference, clientOp)
    if not Phone.Session(src) then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    local r = pending[src]
    if not r or r.token ~= token or os.time() > r.expires then return Veyl.Err('INVALID_STATE', 'Please confirm the recipient again') end
    if not Veyl.Validate.int(amount, 1, PhoneConfig.Bank.MaxTransfer) then
        return Veyl.Err('INVALID_INPUT', ('Enter a whole amount from $1 to $%d'):format(PhoneConfig.Bank.MaxTransfer))
    end
    if not validOp(clientOp) then return Veyl.Err('INVALID_INPUT', 'Invalid request') end
    reference = type(reference) == 'string' and reference:gsub('[^%w %-%.,#/]', ''):sub(1, 40) or ''
    local reason = reference ~= '' and ('Phone transfer: %s'):format(reference) or 'Phone transfer'
    local res = core('TransferMoney', citizenid, 'bank', r.citizenid, 'bank', amount, reason, ('phone:%s:%s'):format(citizenid, clientOp))
    if res.code == 'DUPLICATE_OPERATION' then res = Veyl.Ok(nil) end -- an earlier attempt already went through
    if not res.ok then
        if res.code == 'TIMEOUT' then return Veyl.Err('PENDING', 'The transfer is being verified. Check again in a moment.') end
        return res
    end
    pending[src] = nil
    local senderName = Phone.sessions[src] and Phone.sessions[src].name or 'Someone'
    Notify.Send(r.citizenid, { app = 'bank', title = 'Money received', body = ('%s sent you $%d'):format(senderName, amount), route = 'bank', dedupe = ('bank:%s:%s'):format(citizenid, clientOp) })
    Veyl.Audit(src, 'phone_bank_transfer', { to = r.citizenid, amount = amount })
    return Veyl.Ok(overview(src, citizenid), ('Sent $%d to %s'):format(amount, r.name))
end, { cooldown = 1500 })

--- bankStatus(clientOp) -> whether a transfer that timed out was applied.
Veyl.RegisterCallback('bankStatus', function(src, citizenid, clientOp)
    if not Phone.Session(src) then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    if not validOp(clientOp) then return Veyl.Err('INVALID_INPUT', 'Invalid request') end
    local res = core('GetMoneyOperation', ('phone:%s:%s'):format(citizenid, clientOp))
    if not res.ok then return res end
    return Veyl.Ok({ applied = res.data ~= nil })
end, { cooldown = 300 })
