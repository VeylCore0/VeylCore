-- veyl_shops server: basket checkout with durable settlement.
--
-- A checkout is a recorded operation keyed 'shop:<citizenid>:<client op id>':
--   pending -> paid (one core DebitOnce for the server-computed total)
--           -> settled (each line granted with op '<checkout>:<n>'; a line whose grant provably failed is refunded
--              once with '<line>:refund')
--   pending -> failed (debit refused)
-- Grants are atomic with their inventory operation record, so reconciliation can tell delivered from not delivered.
-- A repeated request with the same op id returns the stored result; it never charges or grants twice.

local shops = {}
for _, s in ipairs(ShopsConfig.Shops) do shops[s.id] = s end

local function core(name, ...) return Veyl.Await('veyl_core', name, 15000, ...) end
local function inv(name, ...) return Veyl.Await('veyl_inventory', name, 15000, ...) end

Veyl.Startup({ 'veyl_core', 'veyl_inventory' }, function()
    local ok = Veyl.Migrate({
        {
            id = '002_checkouts',
            sql = {
                [[CREATE TABLE IF NOT EXISTS veyl_shop_checkouts (
                    op_id VARCHAR(100) NOT NULL,
                    citizenid VARCHAR(16) NOT NULL,
                    shop VARCHAR(64) NOT NULL,
                    method VARCHAR(8) NOT NULL,
                    total INT UNSIGNED NOT NULL,
                    items_json LONGTEXT NOT NULL,
                    status ENUM('pending','paid','settled','failed') NOT NULL DEFAULT 'pending',
                    result LONGTEXT NULL,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                    PRIMARY KEY (op_id),
                    KEY idx_status (status)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            },
        },
    })
    if not ok then return false end
    Reconcile(false)
    return true
end)

---------------------------------------------------------------------------
-- Catalog
---------------------------------------------------------------------------
local function catalogFor(shop, src)
    local defs = exports.veyl_inventory:Items()
    local products = {}
    for i, entry in ipairs(shop.catalog) do
        local def = defs[entry.item]
        if def then
            products[#products + 1] = {
                index = i, item = entry.item, label = entry.label or def.label, price = entry.price,
                category = entry.category or 'all', image = def.image, stock = nil, -- finite stock is not enabled yet
            }
        end
    end
    local pd = src and Veyl.GetPlayerData(src)
    return {
        shopId = shop.id, title = shop.label, subtitle = shop.subtitle or '', categories = shop.categories or {},
        products = products, methods = shop.methods or { 'cash', 'bank' },
        balances = { cash = pd and pd.money.cash or 0, bank = pd and pd.money.bank or 0 },
        imagePath = 'nui://veyl_inventory/web/images', maxPerLine = ShopsConfig.MaxPerLine,
    }
end

local function nearShop(src, shop)
    local pc, sc = Veyl.GetPlayerCoords(src), shop.ped.coords
    return pc ~= nil and #(pc - vector3(sc.x, sc.y, sc.z)) <= ShopsConfig.UseDistance + 2.0
end

Veyl.RegisterCallback('catalog', function(src, _, shopId)
    local shop = shops[shopId]
    if not shop then return Veyl.Err('NOT_FOUND', 'Unknown shop') end
    if not nearShop(src, shop) then return Veyl.Err('TOO_FAR', 'You need to be at the counter') end
    if shop.groups and not exports.veyl_core:HasGroup(src, shop.groups) then return Veyl.Err('NO_PERMISSION', 'This store is not open to you') end
    return Veyl.Ok(catalogFor(shop, src))
end, { cooldown = 500 })

---------------------------------------------------------------------------
-- Settlement
---------------------------------------------------------------------------
local function setStatus(opId, status, result)
    MySQL.update.await('UPDATE veyl_shop_checkouts SET status = ?, result = COALESCE(?, result) WHERE op_id = ?',
        { status, result and json.encode(result) or nil, opId })
end

--- Grants every line (idempotent per line op id) and refunds lines that provably were not delivered.
local function settle(row, lines)
    local delivered, refunded = {}, 0
    for n, line in ipairs(lines) do
        local lineOp = ('%s:%d'):format(row.op_id, n)
        local grant = inv('GiveItem', row.citizenid, line.item, line.count, nil, lineOp)
        if grant.ok or grant.code == 'DUPLICATE_OPERATION' then
            delivered[#delivered + 1] = { item = line.item, count = line.count }
        elseif grant.code == 'TIMEOUT' then
            return nil -- unknown outcome: leave 'paid' for reconciliation, never refund blindly
        else
            local r = core('CreditOnce', row.citizenid, row.method, line.price * line.count, 'Refund: undelivered shop item', lineOp .. ':refund')
            if not r.ok and r.code ~= 'DUPLICATE_OPERATION' then return nil end
            refunded = refunded + line.price * line.count
        end
    end
    local result = { total = row.total - refunded, delivered = delivered, refunded = refunded }
    setStatus(row.op_id, 'settled', result)
    return result
end

function Reconcile(staleOnly)
    local sql = "SELECT * FROM veyl_shop_checkouts WHERE status IN ('pending','paid')"
    if staleOnly then sql = sql .. ' AND updated_at < NOW() - INTERVAL 2 MINUTE' end
    local rows = MySQL.query.await(sql) or {}
    for _, row in ipairs(rows) do
        local debit = core('GetMoneyOperation', row.op_id)
        if not debit.ok then
            print(('^3[veyl_shops] reconcile skipped %s (core unavailable)^7'):format(row.op_id))
        elseif not debit.data then
            setStatus(row.op_id, 'failed', { reason = 'not_charged' })
        else
            if row.status == 'pending' then setStatus(row.op_id, 'paid') end
            local okLines, lines = pcall(json.decode, row.items_json)
            if okLines and type(lines) == 'table' then settle(row, lines) end
        end
    end
    if #rows > 0 then print(('^5[veyl_shops] reconciled %d interrupted checkout(s)^7'):format(#rows)) end
end

CreateThread(function()
    while true do
        Wait(10 * 60000)
        if Veyl.IsReady() then
            local ok, e = pcall(Reconcile, true)
            if not ok then print(('^1[veyl_shops] reconcile error: %s^7'):format(tostring(e))) end
        end
    end
end)

local function balancesOf(src)
    local pd = Veyl.GetPlayerData(src)
    return { cash = pd and pd.money.cash or 0, bank = pd and pd.money.bank or 0 }
end

local function storedResult(src, row)
    if row.status == 'settled' then
        local ok, r = pcall(json.decode, row.result or '{}')
        r = ok and r or {}
        r.balances = balancesOf(src)
        return Veyl.Ok(r, 'Already paid')
    elseif row.status == 'failed' then
        return Veyl.Err('INSUFFICIENT_FUNDS', 'That payment did not go through')
    end
    return Veyl.Err('PENDING', 'Payment is still being verified')
end

--- checkout({ opId, shopId, method, lines = { { index, count } }, expectedTotal })
Veyl.RegisterCallback('checkout', function(src, citizenid, req)
    if type(req) ~= 'table' or not Veyl.Validate.str(req.opId, 6, 64, '^[%w%-]+$') then return Veyl.Err('INVALID_INPUT', 'Invalid request') end
    local shop = shops[req.shopId]
    if not shop then return Veyl.Err('NOT_FOUND', 'Unknown shop') end
    local opId = ('shop:%s:%s'):format(citizenid, req.opId)

    local existing = MySQL.single.await('SELECT * FROM veyl_shop_checkouts WHERE op_id = ?', { opId })
    if existing then return storedResult(src, existing) end

    if not nearShop(src, shop) then return Veyl.Err('TOO_FAR', 'You need to be at the counter') end
    if shop.groups and not exports.veyl_core:HasGroup(src, shop.groups) then return Veyl.Err('NO_PERMISSION', 'This store is not open to you') end
    local methodOk = false
    for _, m in ipairs(shop.methods or { 'cash', 'bank' }) do if m == req.method then methodOk = true end end
    if not methodOk then return Veyl.Err('INVALID_INPUT', 'Payment method not accepted here') end
    if type(req.lines) ~= 'table' or #req.lines == 0 or #req.lines > ShopsConfig.MaxLines then return Veyl.Err('INVALID_INPUT', 'Your basket is empty') end

    -- Server-side prices and validation; the client only names catalog indexes and counts.
    local lines, total, seen = {}, 0, {}
    for _, l in ipairs(req.lines) do
        if type(l) ~= 'table' or not Veyl.Validate.int(l.index, 1, #shop.catalog) or not Veyl.Validate.int(l.count, 1, ShopsConfig.MaxPerLine)
            or seen[l.index] then
            return Veyl.Err('INVALID_INPUT', 'Invalid basket')
        end
        seen[l.index] = true
        local entry = shop.catalog[l.index]
        lines[#lines + 1] = { item = entry.item, count = l.count, price = entry.price }
        total = total + entry.price * l.count
    end
    if tonumber(req.expectedTotal) ~= total then
        return Veyl.Err('PRICE_CHANGED', 'Prices changed. Please review your basket.', { catalog = catalogFor(shop, src) })
    end
    for _, line in ipairs(lines) do
        local carry = inv('CanCarry', citizenid, line.item, line.count)
        if not carry.ok then return Veyl.Err(carry.code, carry.message or 'Not enough space') end
    end

    local ok = pcall(MySQL.insert.await, 'INSERT INTO veyl_shop_checkouts (op_id, citizenid, shop, method, total, items_json) VALUES (?, ?, ?, ?, ?, ?)',
        { opId, citizenid, shop.id, req.method, total, json.encode(lines) })
    if not ok then
        local row = MySQL.single.await('SELECT * FROM veyl_shop_checkouts WHERE op_id = ?', { opId })
        if row then return storedResult(src, row) end
        return Veyl.Err('DATABASE_ERROR', 'Could not start checkout')
    end

    local pay = core('DebitOnce', citizenid, req.method, total, ('%s purchase'):format(shop.label), opId)
    if not pay.ok and pay.code ~= 'DUPLICATE_OPERATION' then
        if pay.code == 'TIMEOUT' then return Veyl.Err('PENDING', 'Payment is being verified') end
        setStatus(opId, 'failed', { reason = pay.code })
        return pay
    end
    setStatus(opId, 'paid')

    local result = settle({ op_id = opId, citizenid = citizenid, method = req.method, total = total }, lines)
    if not result then return Veyl.Err('PENDING', 'Delivery is being verified; it will be completed or refunded') end
    result.balances = balancesOf(src)
    Veyl.Audit(src, 'shop_checkout', { shop = shop.id, total = result.total, refunded = result.refunded })
    local msg = result.refunded > 0 and ('Paid $%d (refunded $%d for items that did not fit)'):format(result.total, result.refunded)
        or ('Paid $%d'):format(result.total)
    return Veyl.Ok(result, msg)
end, { cooldown = 1000 })

--- status(clientOpId) -> stored outcome, for reconciling a timed-out checkout without resubmitting it.
Veyl.RegisterCallback('status', function(src, citizenid, clientOpId)
    if not Veyl.Validate.str(clientOpId, 6, 64, '^[%w%-]+$') then return Veyl.Err('INVALID_INPUT', 'Invalid request') end
    local row = MySQL.single.await('SELECT * FROM veyl_shop_checkouts WHERE op_id = ?', { ('shop:%s:%s'):format(citizenid, clientOpId) })
    if not row then return Veyl.Err('NOT_FOUND', 'No such payment') end
    return storedResult(src, row)
end, { cooldown = 500 })
