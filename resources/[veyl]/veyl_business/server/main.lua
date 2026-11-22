-- veyl_business server: ownership, the business account, ingredient orders, workstations and register sales.
-- Staff and ranks are the business's job (veyl_core); hiring and firing use the boss menus (veyl_management).
-- The business account is a row in veyl_businesses; every change to it is a guarded UPDATE and is audited.

local C = BusinessConfig
local seq = 0
local function opId(kind, id) seq = seq + 1 return ('biz:%s:%s:%d:%d'):format(kind, id, os.time(), seq) end
local function core(name, ...) return Veyl.Await('veyl_core', name, 15000, ...) end

Veyl.Startup({ 'veyl_core', 'veyl_inventory' }, function()
    local ok = Veyl.Migrate({
        { id = '001_businesses', sql = {
            [[CREATE TABLE IF NOT EXISTS veyl_businesses (
                id VARCHAR(32) NOT NULL,
                owner_cid VARCHAR(16) NULL,
                balance BIGINT NOT NULL DEFAULT 0,
                purchased_at TIMESTAMP NULL,
                PRIMARY KEY (id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS veyl_business_ledger (
                id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                business VARCHAR(32) NOT NULL,
                delta BIGINT NOT NULL,
                reason VARCHAR(120) NOT NULL,
                actor VARCHAR(64) NOT NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (id),
                KEY idx_biz (business, id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        } },
    })
    if not ok then return false end
    for id, b in pairs(C.Businesses) do
        MySQL.insert.await('INSERT IGNORE INTO veyl_businesses (id) VALUES (?)', { id })
        exports.veyl_inventory:RegisterStash({ id = 'biz_' .. id, label = b.label .. ' stockroom', slots = 80, maxWeight = 400000,
            groups = { [b.job] = 0 }, coords = b.stash, radius = 2.5 })
    end
    return true
end)

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function charName(pd) return pd and ('%s %s'):format(pd.charinfo.firstname or '', pd.charinfo.lastname or '') or 'Unknown' end
local function near(src, pos, d) local pc = Veyl.GetPlayerCoords(src) return pc ~= nil and #(pc - pos) <= d end
local function row(id) return MySQL.single.await('SELECT id, owner_cid, balance FROM veyl_businesses WHERE id = ?', { id }) end
local function topGrade(job)
    local def = exports.veyl_core:GetJob(job)
    local top = 0
    for g in pairs(def and def.grades or {}) do top = math.max(top, tonumber(g)) end
    return top
end

--- grade of src in the business's job, or nil; and whether that grade is a boss grade
local function staff(src, b)
    local pd = Veyl.GetPlayerData(src)
    local g = pd and pd.jobs[b.job]
    if g == nil then return nil, false, pd end
    return g, exports.veyl_core:IsGradeBoss(b.job, g), pd
end

local function credit(id, amount, reason, actor)
    MySQL.update.await('UPDATE veyl_businesses SET balance = balance + ? WHERE id = ?', { amount, id })
    MySQL.insert.await('INSERT INTO veyl_business_ledger (business, delta, reason, actor) VALUES (?, ?, ?, ?)', { id, amount, reason, actor })
end

local function debit(id, amount, reason, actor)
    local n = MySQL.update.await('UPDATE veyl_businesses SET balance = balance - ? WHERE id = ? AND balance >= ?', { amount, id, amount })
    if n ~= 1 then return false end
    MySQL.insert.await('INSERT INTO veyl_business_ledger (business, delta, reason, actor) VALUES (?, ?, ?, ?)', { id, -amount, reason, actor })
    return true
end

local function biz(id)
    local b = type(id) == 'string' and C.Businesses[id]
    return b or nil
end

---------------------------------------------------------------------------
-- Office: info, buy, sell, deposit, withdraw, order
---------------------------------------------------------------------------
local function officeView(src, id)
    local b = biz(id)
    local r = row(id)
    local grade, boss, pd = staff(src, b)
    local owner
    if r.owner_cid then
        local o = MySQL.single.await('SELECT charinfo FROM veyl_players WHERE citizenid = ?', { r.owner_cid })
        local ok, ci = pcall(json.decode, o and o.charinfo or '{}')
        ci = ok and type(ci) == 'table' and ci or {}
        owner = ('%s %s'):format(ci.firstname or '?', ci.lastname or '')
    end
    local ledger = (boss or r.owner_cid == pd.citizenid) and MySQL.query.await([[SELECT delta, reason, actor, UNIX_TIMESTAMP(created_at) AS at
        FROM veyl_business_ledger WHERE business = ? ORDER BY id DESC LIMIT 10]], { id }) or nil
    return {
        id = id, label = b.label, price = b.price, owned = r.owner_cid ~= nil, owner = owner, isOwner = r.owner_cid == pd.citizenid,
        staff = grade ~= nil, boss = boss, grade = grade, balance = (grade ~= nil) and r.balance or nil, ledger = ledger,
        canOrder = grade ~= nil and grade >= C.OrderGrade and #(b.supplies or {}) > 0, supplies = b.supplies, sellBack = math.floor(b.price * C.SellBackShare),
    }
end

Veyl.RegisterCallback('office', function(src, _, id)
    local b = biz(id)
    if not b then return Veyl.Err('NOT_FOUND', 'Unknown business') end
    if not near(src, b.office, 3.5) then return Veyl.Err('TOO_FAR', 'Use the office') end
    return Veyl.Ok(officeView(src, id))
end, { cooldown = 400 })

Veyl.RegisterCallback('buy', function(src, citizenid, id)
    local b = biz(id)
    if not b or not near(src, b.office, 3.5) then return Veyl.Err('TOO_FAR', 'Use the office') end
    local lic = exports.veyl_core:GetMetadata(src, 'licences')
    if C.LicenceRequired and not (type(lic) == 'table' and lic[C.LicenceRequired]) then return Veyl.Err('NO_PERMISSION', 'You need a business licence (City Hall)') end
    if MySQL.scalar.await('SELECT 1 FROM veyl_businesses WHERE owner_cid = ?', { citizenid }) then return Veyl.Err('INVALID_STATE', 'You already own a business') end
    -- Claim first (only one buyer can win), then charge; undo the claim if the payment fails.
    local claimed = MySQL.update.await('UPDATE veyl_businesses SET owner_cid = ?, purchased_at = NOW() WHERE id = ? AND owner_cid IS NULL', { citizenid, id })
    if claimed ~= 1 then return Veyl.Err('INVALID_STATE', 'This business already has an owner') end
    local r = core('DebitOnce', citizenid, 'bank', b.price, ('Bought %s'):format(b.label), opId('buy', id))
    if not r.ok then
        MySQL.update.await('UPDATE veyl_businesses SET owner_cid = NULL, purchased_at = NULL WHERE id = ? AND owner_cid = ?', { id, citizenid })
        return Veyl.Err(r.code or 'INSUFFICIENT_FUNDS', r.code == 'INSUFFICIENT_FUNDS' and ('You need $%d in the bank'):format(b.price) or (r.message or 'Payment failed'))
    end
    exports.veyl_core:AddPlayerToJob(citizenid, b.job, topGrade(b.job))
    exports.veyl_core:SetPlayerPrimaryJob(citizenid, b.job)
    Veyl.Audit(src, 'business_buy', { business = id, price = b.price })
    return Veyl.Ok(officeView(src, id), ('You now own %s'):format(b.label))
end, { cooldown = 3000 })

Veyl.RegisterCallback('sell', function(src, citizenid, id)
    local b = biz(id)
    if not b or not near(src, b.office, 3.5) then return Veyl.Err('TOO_FAR', 'Use the office') end
    local n = MySQL.update.await('UPDATE veyl_businesses SET owner_cid = NULL, purchased_at = NULL WHERE id = ? AND owner_cid = ?', { id, citizenid })
    if n ~= 1 then return Veyl.Err('NO_PERMISSION', 'You do not own this business') end
    local refund = math.floor(b.price * C.SellBackShare)
    core('CreditOnce', citizenid, 'bank', refund, ('Sold %s'):format(b.label), opId('sell', id))
    exports.veyl_core:RemovePlayerFromJob(citizenid, b.job)
    Veyl.Audit(src, 'business_sell', { business = id, refund = refund })
    return Veyl.Ok(officeView(src, id), ('Sold for $%d. The business account stays with the business.'):format(refund))
end, { cooldown = 3000 })

Veyl.RegisterCallback('deposit', function(src, citizenid, id, amount, method)
    local b = biz(id)
    if not b or not near(src, b.office, 3.5) then return Veyl.Err('TOO_FAR', 'Use the office') end
    local _, boss, pd = staff(src, b)
    if not boss then return Veyl.Err('NO_PERMISSION', 'Only managers can use the business account') end
    amount = math.floor(tonumber(amount) or 0)
    if amount < 1 or amount > 10000000 then return Veyl.Err('INVALID_INPUT', 'Invalid amount') end
    method = method == 'cash' and 'cash' or 'bank'
    local r = core('DebitOnce', citizenid, method, amount, ('Deposit to %s'):format(b.label), opId('dep', id))
    if not r.ok then return Veyl.Err(r.code or 'INSUFFICIENT_FUNDS', 'Not enough money') end
    credit(id, amount, 'Deposit', charName(pd))
    Veyl.Audit(src, 'business_deposit', { business = id, amount = amount })
    return Veyl.Ok(officeView(src, id), ('Deposited $%d'):format(amount))
end, { cooldown = 1500 })

Veyl.RegisterCallback('withdraw', function(src, citizenid, id, amount)
    local b = biz(id)
    if not b or not near(src, b.office, 3.5) then return Veyl.Err('TOO_FAR', 'Use the office') end
    local _, boss, pd = staff(src, b)
    if not boss then return Veyl.Err('NO_PERMISSION', 'Only managers can use the business account') end
    amount = math.floor(tonumber(amount) or 0)
    if amount < 1 then return Veyl.Err('INVALID_INPUT', 'Invalid amount') end
    if not debit(id, amount, 'Withdrawal', charName(pd)) then return Veyl.Err('INSUFFICIENT_FUNDS', 'The business account is short') end
    local r = core('CreditOnce', citizenid, 'bank', amount, ('Withdrawal from %s'):format(b.label), opId('wd', id))
    if not r.ok then credit(id, amount, 'Withdrawal reversed', 'system') return Veyl.Err('INTERNAL', 'Could not pay out') end
    Veyl.Audit(src, 'business_withdraw', { business = id, amount = amount })
    return Veyl.Ok(officeView(src, id), ('Withdrew $%d to your bank'):format(amount))
end, { cooldown = 1500 })

Veyl.RegisterCallback('order', function(src, citizenid, id, index, count)
    local b = biz(id)
    if not b or not near(src, b.office, 3.5) then return Veyl.Err('TOO_FAR', 'Use the office') end
    local grade, _, pd = staff(src, b)
    if not grade or grade < C.OrderGrade then return Veyl.Err('NO_PERMISSION', 'Your rank cannot order stock') end
    local s = b.supplies[tonumber(index) or 0]
    count = math.floor(tonumber(count) or 0)
    if not s or count < 1 or count > 50 then return Veyl.Err('INVALID_INPUT', 'Order 1 - 50') end
    local fit = Veyl.Await('veyl_inventory', 'CanCarry', 15000, citizenid, s.item, count)
    if not fit.ok then return Veyl.Err('INVENTORY_FULL', 'Make room in your pockets first') end
    local cost = s.price * count
    if not debit(id, cost, ('Order: %dx %s'):format(count, s.label), charName(pd)) then return Veyl.Err('INSUFFICIENT_FUNDS', 'The business account is short') end
    local r = Veyl.Await('veyl_inventory', 'GiveItem', 15000, citizenid, s.item, count, nil, opId('order', id))
    if not r.ok then credit(id, cost, 'Order refund', 'system') return Veyl.Err('INVENTORY_FULL', 'The order could not be delivered. Refunded.') end
    Veyl.Audit(src, 'business_order', { business = id, item = s.item, count = count, cost = cost })
    return Veyl.Ok(officeView(src, id), ('Delivered %dx %s for $%d. Put it in the stockroom.'):format(count, s.label, cost))
end, { cooldown = 1500 })

---------------------------------------------------------------------------
-- Workstations
---------------------------------------------------------------------------
local crafting = {} -- [src] = { id, station, recipe, at, token }

local function recipeCheck(src, b, si, ri)
    local st = b.stations[tonumber(si) or 0]
    local rc = st and st.recipes[tonumber(ri) or 0]
    if not rc then return nil, Veyl.Err('NOT_FOUND', 'Unknown recipe') end
    local grade, _, pd = staff(src, b)
    if grade == nil or pd.job.name ~= b.job or not pd.job.onduty then return nil, Veyl.Err('NO_PERMISSION', 'Clock in to work here') end
    if not near(src, st.coords, 3.0) then return nil, Veyl.Err('TOO_FAR', 'Move closer') end
    for item, n in pairs(rc.inputs) do
        if (exports.veyl_inventory:GetItemCount(src, item) or 0) < n then return nil, Veyl.Err('NO_ITEM', ('You need %dx %s'):format(n, item)) end
    end
    return rc
end

Veyl.RegisterCallback('craftStart', function(src, _, id, si, ri)
    local b = biz(id)
    if not b then return Veyl.Err('NOT_FOUND', 'Unknown business') end
    local rc, err = recipeCheck(src, b, si, ri)
    if not rc then return err end
    local token = Veyl.NewId()
    crafting[src] = { id = id, si = si, ri = ri, at = GetGameTimer(), token = token }
    return Veyl.Ok({ token = token, seconds = rc.seconds })
end, { cooldown = 800 })

Veyl.RegisterCallback('craftFinish', function(src, citizenid, token)
    local c = crafting[src]
    crafting[src] = nil
    if not c or c.token ~= token then return Veyl.Err('INVALID_STATE', 'Start again') end
    local b = biz(c.id)
    local rc, err = recipeCheck(src, b, c.si, c.ri)
    if not rc then return err end
    if GetGameTimer() - c.at < rc.seconds * 1000 - 600 then return Veyl.Err('TOO_FAST', 'You stopped too early') end
    for item, n in pairs(rc.inputs) do
        if not exports.veyl_inventory:RemoveItem(src, item, n) then return Veyl.Err('NO_ITEM', 'Missing ingredients') end
    end
    local r = Veyl.Await('veyl_inventory', 'GiveItem', 15000, citizenid, rc.output, rc.count or 1, nil, 'biz:craft:' .. token)
    if not r.ok then return Veyl.Err('INVENTORY_FULL', 'No room for it') end
    return Veyl.Ok(nil, ('Made %dx %s'):format(rc.count or 1, rc.output))
end, { cooldown = 300 })

---------------------------------------------------------------------------
-- Register: an employee charges a customer, who accepts
---------------------------------------------------------------------------
local bills = {} -- [token] = { id, from, to, amount, note, expires }

Veyl.RegisterCallback('charge', function(src, _, id, target, amount, note)
    local b = biz(id)
    if not b then return Veyl.Err('NOT_FOUND', 'Unknown business') end
    local grade, _, pd = staff(src, b)
    if grade == nil or pd.job.name ~= b.job or not pd.job.onduty then return Veyl.Err('NO_PERMISSION', 'Clock in to use the register') end
    if not near(src, b.register, 3.0) then return Veyl.Err('TOO_FAR', 'Stand at the register') end
    target = tonumber(target)
    if not target or target == src or not Veyl.GetCitizenId(target) or not near(target, b.register, 5.0) then return Veyl.Err('NOT_FOUND', 'The customer must be at the counter') end
    amount = math.floor(tonumber(amount) or 0)
    if amount < 1 or amount > C.RegisterMax then return Veyl.Err('INVALID_INPUT', ('Amount must be $1 - $%d'):format(C.RegisterMax)) end
    note = type(note) == 'string' and note:gsub('[%c]', ''):sub(1, 80) or ''
    local token = Veyl.NewId()
    bills[token] = { id = id, from = src, to = target, amount = amount, note = note, expires = os.time() + 30 }
    TriggerClientEvent('veyl_business:bill', target, token, { label = b.label, amount = amount, note = note })
    return Veyl.Ok(nil, 'Sent to the customer')
end, { cooldown = 1500 })

Veyl.RegisterCallback('payBill', function(src, citizenid, token, method)
    local bl = type(token) == 'string' and bills[token]
    if not bl or bl.to ~= src then return Veyl.Err('NOT_FOUND', 'This bill is no longer valid') end
    bills[token] = nil
    if os.time() > bl.expires then return Veyl.Err('EXPIRED', 'This bill expired') end
    local b = biz(bl.id)
    if method ~= 'cash' and method ~= 'bank' then
        if GetPlayerName(bl.from) then Veyl.Notify(bl.from, 'The customer declined.', 'info') end
        return Veyl.Ok(nil, 'Declined')
    end
    local r = core('DebitOnce', citizenid, method, bl.amount, ('%s: %s'):format(b.label, bl.note ~= '' and bl.note or 'purchase'), 'biz:sale:' .. token)
    if not r.ok and r.code ~= 'DUPLICATE_OPERATION' then
        if GetPlayerName(bl.from) then Veyl.Notify(bl.from, 'The customer could not pay.', 'error') end
        return Veyl.Err(r.code or 'INSUFFICIENT_FUNDS', 'Not enough money')
    end
    local cut = math.floor(bl.amount * C.RegisterCommission)
    local seller = GetPlayerName(bl.from) and Veyl.GetCitizenId(bl.from)
    credit(bl.id, bl.amount - (seller and cut or 0), 'Sale' .. (bl.note ~= '' and (': ' .. bl.note) or ''), seller and charName(Veyl.GetPlayerData(bl.from)) or 'register')
    if seller and cut > 0 then
        core('CreditOnce', seller, 'bank', cut, ('%s commission'):format(b.label), 'biz:sale:' .. token .. ':cut')
        Veyl.Notify(bl.from, ('Paid: $%d (your commission $%d)'):format(bl.amount, cut), 'success')
    end
    return Veyl.Ok(nil, ('Paid $%d to %s'):format(bl.amount, b.label))
end, { cooldown = 800 })

---------------------------------------------------------------------------
-- Services: car wash bays, nightclub cover, pawn counter, tuning bay (config: services = { { kind, ... } })
---------------------------------------------------------------------------
local function owned(id) local r = row(id) return r and r.owner_cid ~= nil end

Veyl.RegisterCallback('service', function(src, citizenid, id, index, a1, a2)
    local b = biz(id)
    local sv = b and b.services and b.services[tonumber(index) or 0]
    if not sv then return Veyl.Err('NOT_FOUND', 'Unknown service') end
    if not near(src, sv.coords, (sv.radius or 2.5) + 2.0) then return Veyl.Err('TOO_FAR', 'Move closer') end
    local pd = Veyl.GetPlayerData(src)

    if sv.kind == 'wash' or sv.kind == 'cover' then
        local veh = GetVehiclePedIsIn(GetPlayerPed(src), false)
        if sv.kind == 'wash' and (veh == 0 or GetPedInVehicleSeat(veh, -1) ~= GetPlayerPed(src)) then return Veyl.Err('INVALID_STATE', 'Drive your vehicle into the bay') end
        local method = a1 == 'cash' and 'cash' or 'bank'
        local token = Veyl.NewId()
        local r = core('DebitOnce', citizenid, method, sv.price, ('%s: %s'):format(b.label, sv.kind == 'wash' and 'car wash' or 'entry'), 'biz:svc:' .. token)
        if not r.ok then return Veyl.Err(r.code or 'INSUFFICIENT_FUNDS', ('It costs $%d'):format(sv.price)) end
        if owned(id) then credit(id, sv.price, sv.kind == 'wash' and 'Car wash' or 'Cover charge', charName(pd)) end
        if sv.kind == 'wash' then
            TriggerClientEvent('veyl_business:washed', src, NetworkGetNetworkIdFromEntity(veh))
            return Veyl.Ok(nil, ('Washed for $%d'):format(sv.price))
        end
        return Veyl.Ok(nil, 'Enjoy your night')
    end

    if sv.kind == 'pawn' then
        local item, count = a1, math.floor(tonumber(a2) or 0)
        local price = type(item) == 'string' and sv.prices[item]
        if not price or count < 1 or count > 50 then return Veyl.Err('INVALID_INPUT', 'They do not buy that') end
        if (exports.veyl_inventory:GetItemCount(src, item) or 0) < count then return Veyl.Err('NO_ITEM', 'You do not have that many') end
        local isOwned = owned(id)
        local total = isOwned and price * count or math.floor(price * count * (sv.cityRate or 0.5))
        if isOwned and not debit(id, total, ('Bought %dx %s'):format(count, item), charName(pd)) then
            return Veyl.Err('INSUFFICIENT_FUNDS', 'The shop cannot afford that right now')
        end
        if not exports.veyl_inventory:RemoveItem(src, item, count) then
            if isOwned then credit(id, total, 'Purchase cancelled', 'system') end
            return Veyl.Err('NO_ITEM', 'Could not hand it over')
        end
        local token = Veyl.NewId()
        core('CreditOnce', citizenid, 'cash', total, ('%s: sold %dx %s'):format(b.label, count, item), 'biz:pawn:' .. token)
        if isOwned then Veyl.Await('veyl_inventory', 'GiveToStash', 15000, 'biz_' .. id, item, count, nil, 'biz:pawn:' .. token .. ':stock') end
        Veyl.Audit(src, 'pawn_sell', { business = id, item = item, count = count, total = total })
        return Veyl.Ok(nil, ('Sold %dx %s for $%d cash'):format(count, item:gsub('_', ' '), total))
    end

    if sv.kind == 'tune' then
        local grade = staff(src, b)
        if grade == nil or pd.job.name ~= b.job or not pd.job.onduty then return Veyl.Err('NO_PERMISSION', 'Clock in to use the bay') end
        local kit = type(a1) == 'string' and sv.kits[a1]
        if not kit then return Veyl.Err('INVALID_INPUT', 'Unknown kit') end
        local veh = NetworkGetEntityFromNetworkId(tonumber(a2) or 0)
        if not veh or veh == 0 or not DoesEntityExist(veh) or GetEntityType(veh) ~= 2 then return Veyl.Err('NOT_FOUND', 'No vehicle') end
        if #(GetEntityCoords(veh) - sv.coords) > sv.radius or not near(src, GetEntityCoords(veh), 5.0) then return Veyl.Err('TOO_FAR', 'The vehicle must be in the bay') end
        if not exports.veyl_inventory:RemoveItem(src, a1, 1) then return Veyl.Err('NO_ITEM', 'You do not have that kit') end
        local owner = NetworkGetEntityOwner(veh)
        TriggerClientEvent('veyl_business:tuned', owner and owner > 0 and owner or src, a2, kit)
        Veyl.Audit(src, 'tune_install', { business = id, kit = a1 })
        return Veyl.Ok(nil, 'Installed. Charge the customer at the register. It saves when they park it in a garage.')
    end
    return Veyl.Err('INVALID_INPUT', 'Unknown service')
end, { cooldown = 1500 })

AddEventHandler('playerDropped', function() crafting[source] = nil end)

---------------------------------------------------------------------------
-- Integration exports (used by veyl_customs). Async: call with Veyl.Await('veyl_business', name, timeout, ...).
---------------------------------------------------------------------------
--- CreditAccount(id, amount, reason, actor) -> Ok()
Veyl.AsyncExport('CreditAccount', function(id, amount, reason, actor)
    amount = math.floor(tonumber(amount) or 0)
    if not biz(id) or amount < 1 then return Veyl.Err('INVALID_INPUT', 'Invalid business or amount') end
    credit(id, amount, tostring(reason or 'Income'):sub(1, 120), tostring(actor or GetInvokingResource() or 'system'):sub(1, 64))
    return Veyl.Ok()
end)

--- DebitAccount(id, amount, reason, actor) -> Ok() | Err('INSUFFICIENT_FUNDS')
Veyl.AsyncExport('DebitAccount', function(id, amount, reason, actor)
    amount = math.floor(tonumber(amount) or 0)
    if not biz(id) or amount < 1 then return Veyl.Err('INVALID_INPUT', 'Invalid business or amount') end
    if not debit(id, amount, tostring(reason or 'Expense'):sub(1, 120), tostring(actor or GetInvokingResource() or 'system'):sub(1, 64)) then
        return Veyl.Err('INSUFFICIENT_FUNDS', 'The business account is short')
    end
    return Veyl.Ok()
end)

--- GetAccount(id) -> Ok({ owner, balance, label, job })
Veyl.AsyncExport('GetAccount', function(id)
    local b = biz(id)
    if not b then return Veyl.Err('NOT_FOUND', 'Unknown business') end
    local r = row(id)
    return Veyl.Ok({ owner = r and r.owner_cid, balance = r and r.balance or 0, label = b.label, job = b.job })
end)
