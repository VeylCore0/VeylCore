-- Bills: pay mechanic invoices and police citations, standing orders, credit score.

local C = PhoneConfig
local function session(src)
    local s = Phone.Session(src)
    if not s then return nil, Veyl.Err('NO_SESSION', 'Open your phone first') end
    return s
end
local function core(name, ...) return Veyl.Await('veyl_core', name, 15000, ...) end
local function cidByNumber(number) return Phone.CidByNumber(number) end
local function charName(pd) return pd and ('%s %s'):format(pd.charinfo.firstname or '', pd.charinfo.lastname or '') or 'Unknown' end
local seq = 0
local function op(kind, cid) seq = seq + 1 return ('phone:%s:%s:%d:%d'):format(kind, cid, os.time(), seq) end

---------------------------------------------------------------------------
-- Bank 2.0: bills (mechanic invoices, citations), standing orders, credit score
---------------------------------------------------------------------------
local function tableExists(name)
    return MySQL.scalar.await('SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ?', { name }) > 0
end

local function bills(citizenid)
    local out = {}
    if tableExists('veyl_invoices') then
        for _, r in ipairs(MySQL.query.await([[SELECT id, amount, reason, UNIX_TIMESTAMP(created_at) AS at FROM veyl_invoices
            WHERE recipient_cid = ? AND status = 'pending' ORDER BY id]], { citizenid }) or {}) do
            out[#out + 1] = { kind = 'invoice', id = r.id, amount = r.amount, label = ('Invoice #%d · %s'):format(r.id, r.reason), at = r.at }
        end
    end
    if tableExists('veyl_police_citations') then
        for _, r in ipairs(MySQL.query.await([[SELECT id, amount, reason, UNIX_TIMESTAMP(created_at) AS at FROM veyl_police_citations
            WHERE citizenid = ? AND status = 'unpaid' ORDER BY id]], { citizenid }) or {}) do
            out[#out + 1] = { kind = 'citation', id = r.id, amount = r.amount, label = ('Citation #%d · %s'):format(r.id, r.reason), at = r.at }
        end
    end
    return out
end

local function creditScore(citizenid, unpaid)
    local paid = 0
    if tableExists('veyl_invoices') then paid = paid + (MySQL.scalar.await("SELECT COUNT(*) FROM veyl_invoices WHERE recipient_cid = ? AND status = 'paid'", { citizenid }) or 0) end
    if tableExists('veyl_police_citations') then paid = paid + (MySQL.scalar.await("SELECT COUNT(*) FROM veyl_police_citations WHERE citizenid = ? AND status = 'paid'", { citizenid }) or 0) end
    local failures = MySQL.scalar.await('SELECT COALESCE(SUM(failures), 0) FROM veyl_phone_standing WHERE citizenid = ?', { citizenid }) or 0
    local bank = MySQL.scalar.await("SELECT balance FROM veyl_money WHERE citizenid = ? AND type = 'bank'", { citizenid }) or 0
    local score = 600 + math.min(150, paid * 5) - unpaid * 40 - failures * 20 + (bank >= 100000 and 60 or bank >= 25000 and 35 or bank >= 5000 and 15 or 0)
    return math.max(300, math.min(850, score))
end

Veyl.RegisterCallback('billsData', function(src, citizenid)
    local _, err = session(src)
    if err then return err end
    local list = bills(citizenid)
    local standing = MySQL.query.await([[SELECT id, to_label, amount, every_days, note, UNIX_TIMESTAMP(next_at) AS next_at, failures FROM veyl_phone_standing
        WHERE citizenid = ? AND active = 1 ORDER BY id]], { citizenid }) or {}
    return Veyl.Ok({ bills = list, standing = standing, score = creditScore(citizenid, #list) })
end, { cooldown = 500 })

Veyl.RegisterCallback('billPay', function(src, citizenid, kind, id, method)
    local _, err = session(src)
    if err then return err end
    id = tonumber(id)
    method = method == 'cash' and 'cash' or 'bank'
    if kind == 'invoice' then
        local row = id and MySQL.single.await("SELECT sender_cid, amount, reason FROM veyl_invoices WHERE id = ? AND recipient_cid = ? AND status = 'pending'", { id, citizenid })
        if not row then return Veyl.Err('NOT_FOUND', 'Already paid or not yours') end
        -- Same operation id as the mechanic's own pay flow, so the two can never both charge.
        local pay = core('TransferMoney', citizenid, method, row.sender_cid, 'bank', row.amount, ('Invoice #%d: %s'):format(id, row.reason), 'invoice:' .. id)
        if not pay.ok and pay.code ~= 'DUPLICATE_OPERATION' then return Veyl.Err(pay.code or 'INSUFFICIENT_FUNDS', 'Payment failed') end
        MySQL.update.await("UPDATE veyl_invoices SET status = 'paid', settled_at = NOW() WHERE id = ? AND status = 'pending'", { id })
    elseif kind == 'citation' then
        local row = id and MySQL.single.await("SELECT amount, reason FROM veyl_police_citations WHERE id = ? AND citizenid = ? AND status = 'unpaid'", { id, citizenid })
        if not row then return Veyl.Err('NOT_FOUND', 'Already paid or not yours') end
        local pay = core('DebitOnce', citizenid, method, row.amount, ('Citation #%d: %s'):format(id, row.reason), 'citation:' .. id)
        if not pay.ok and pay.code ~= 'DUPLICATE_OPERATION' then return Veyl.Err(pay.code or 'INSUFFICIENT_FUNDS', 'Payment failed') end
        MySQL.update.await("UPDATE veyl_police_citations SET status = 'paid', paid_at = NOW() WHERE id = ?", { id })
    else
        return Veyl.Err('INVALID_INPUT', 'Unknown bill')
    end
    return Veyl.Ok(nil, 'Paid')
end, { cooldown = 1500 })

Veyl.RegisterCallback('standingCreate', function(src, citizenid, number, amount, days, note)
    local _, err = session(src)
    if err then return err end
    local to = cidByNumber(number)
    if not to or to == citizenid then return Veyl.Err('NOT_FOUND', 'No phone with that number') end
    amount, days = math.floor(tonumber(amount) or 0), math.floor(tonumber(days) or 0)
    if amount < 1 or amount > C.Standing.MaxAmount then return Veyl.Err('INVALID_INPUT', ('Amount $1 - $%d'):format(C.Standing.MaxAmount)) end
    if days < 1 or days > 30 then return Veyl.Err('INVALID_INPUT', 'Every 1 to 30 days') end
    if (MySQL.scalar.await('SELECT COUNT(*) FROM veyl_phone_standing WHERE citizenid = ? AND active = 1', { citizenid }) or 0) >= C.Standing.Max then
        return Veyl.Err('LIMIT', ('Up to %d standing orders'):format(C.Standing.Max))
    end
    local label = MySQL.scalar.await('SELECT display_name FROM veyl_ph_accounts WHERE citizenid = ?', { to }) or number
    MySQL.insert.await([[INSERT INTO veyl_phone_standing (citizenid, to_cid, to_label, amount, every_days, note, next_at)
        VALUES (?, ?, ?, ?, ?, ?, NOW() + INTERVAL ? DAY)]], { citizenid, to, label, amount, days, PhoneUtil.Clean(note, 80), days })
    return Veyl.Ok(nil, ('$%d to %s every %d day%s'):format(amount, label, days, days == 1 and '' or 's'))
end, { cooldown = 2000 })

Veyl.RegisterCallback('standingCancel', function(src, citizenid, id)
    local _, err = session(src)
    if err then return err end
    MySQL.update.await('UPDATE veyl_phone_standing SET active = 0 WHERE id = ? AND citizenid = ?', { tonumber(id) or 0, citizenid })
    return Veyl.Ok(nil, 'Standing order cancelled')
end, { cooldown = 500 })

-- Due standing orders are paid every few minutes (each run has its own operation id: never paid twice).
CreateThread(function()
    while true do
        Wait(5 * 60 * 1000)
        for _, r in ipairs(MySQL.query.await('SELECT *, UNIX_TIMESTAMP(next_at) AS due FROM veyl_phone_standing WHERE active = 1 AND next_at <= NOW() LIMIT 50') or {}) do
            local res = core('TransferMoney', r.citizenid, 'bank', r.to_cid, 'bank', r.amount, ('Standing order: %s'):format(r.note or r.to_label), ('standing:%d:%d'):format(r.id, r.due))
            if res.ok or res.code == 'DUPLICATE_OPERATION' then
                MySQL.update.await('UPDATE veyl_phone_standing SET next_at = next_at + INTERVAL every_days DAY, failures = 0 WHERE id = ?', { r.id })
            else
                local fails = r.failures + 1
                MySQL.update.await('UPDATE veyl_phone_standing SET failures = ?, active = ?, next_at = NOW() + INTERVAL 1 DAY WHERE id = ?', { fails, fails >= 3 and 0 or 1, r.id })
                Notify.Send(r.citizenid, { app = 'bills', title = 'Standing order failed', body = ('$%d to %s%s'):format(r.amount, r.to_label, fails >= 3 and ' (cancelled after 3 tries)' or ''), route = 'bills' })
            end
        end
    end
end)
