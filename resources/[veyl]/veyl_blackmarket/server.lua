-- veyl_blackmarket server. The menu is only a view: the server owns the catalogue, prices, stock, who may buy (distance, street
-- reputation, an optional access item) and the payment, which is a durable debit with an operation id so a retry never charges or
-- delivers twice. Any failure after payment refunds it.

local C = BlackmarketConfig
local stock = {}      -- [item] = { n, at }
local lastBuy = {}    -- [citizenid] = os.time() of the last purchase
local byItem, byId = {}, {}
local strikes = {}

for _, e in ipairs(C.Catalog) do byItem[e.item] = e end
for _, d in ipairs(C.Dealers) do byId[d.id] = d end

Veyl.Startup({ 'veyl_core', 'veyl_inventory' }, function()
    local ok = Veyl.Migrate({
        { id = '001_stock', sql = {
            [[CREATE TABLE IF NOT EXISTS veyl_blackmarket_stock (
                item VARCHAR(48) NOT NULL PRIMARY KEY, stock INT NOT NULL, restocked_at INT UNSIGNED NOT NULL
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        } },
    })
    if not ok then return false end
    for _, r in ipairs(MySQL.query.await('SELECT item, stock, restocked_at FROM veyl_blackmarket_stock') or {}) do
        stock[r.item] = { n = r.stock, at = r.restocked_at }
    end
    for _, e in ipairs(C.Catalog) do
        if not stock[e.item] then
            stock[e.item] = { n = e.stock, at = os.time() }
            MySQL.update('INSERT IGNORE INTO veyl_blackmarket_stock (item, stock, restocked_at) VALUES (?, ?, ?)', { e.item, e.stock, os.time() })
        end
    end
    return ok
end)

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function int(v, max)
    v = tonumber(v)
    if not v or v ~= math.floor(v) or v < 1 or (max and v > max) then return nil end
    return math.floor(v)
end

local function suspicious(src, cid, reason, data)
    local s = strikes[cid]
    if not s or os.time() - s.at > 60 then s = { n = 0, at = os.time() } strikes[cid] = s end
    s.n = s.n + 1
    Veyl.Audit(src, 'blackmarket_' .. reason, data or {})
end

local function near(src, dealer)
    local pc = Veyl.GetPlayerCoords(src)
    local p = dealer.ped.coords
    return pc ~= nil and #(pc - vector3(p.x, p.y, p.z)) <= C.Distance
end

--- Street reputation level from veyl_production; without it the level gate is open.
local function level(cid)
    if GetResourceState('veyl_production') ~= 'started' then return nil end
    local ok, lv = pcall(function() return exports.veyl_production:GetReputation(cid) end)
    return ok and tonumber(lv) or nil
end

local function restock(e)
    local s = stock[e.item]
    local per = (C.RestockMinutes or 30) * 60
    local intervals = math.floor((os.time() - s.at) / per)
    if intervals > 0 and s.n < e.stock then
        s.n = math.min(e.stock, s.n + intervals * (e.restock or math.max(1, math.floor(e.stock / 5))))
        s.at = s.at + intervals * per
        MySQL.update('UPDATE veyl_blackmarket_stock SET stock = ?, restocked_at = ? WHERE item = ?', { s.n, s.at, e.item })
    elseif intervals > 0 then s.at = os.time() end
end

local function label(item)
    local ok, def = pcall(function() return exports.veyl_inventory:GetItemDefinition(item) end)
    return ok and type(def) == 'table' and def.label or item
end

local function allowed(src)
    if not C.Access.Item then return true end
    return (exports.veyl_inventory:GetItemCount(src, C.Access.Item) or 0) > 0
end

---------------------------------------------------------------------------
-- The menu
---------------------------------------------------------------------------
Veyl.RegisterCallback('view', function(src, cid, dealerId)
    local d = type(dealerId) == 'string' and byId[dealerId]
    if not d then suspicious(src, cid, 'bad_view', { dealer = dealerId }) return Veyl.Err('INVALID_INPUT', 'Unknown dealer') end
    if not near(src, d) then return Veyl.Err('TOO_FAR', 'Go to the dealer') end
    if not allowed(src) then return Veyl.Err('NOT_TRUSTED', 'He does not know you') end
    local lv = level(cid)
    local items = {}
    for _, e in ipairs(C.Catalog) do
        if not C.UnlimitedStock then restock(e) end
        local def = (function() local ok, x = pcall(function() return exports.veyl_inventory:GetItemDefinition(e.item) end) return ok and type(x) == 'table' and x or {} end)()
        items[#items + 1] = { item = e.item, label = def.label or e.item, description = def.description, image = def.image, price = e.price, category = e.category,
            stock = C.UnlimitedStock and e.stock or stock[e.item].n, max = e.stock, level = e.level or 0, locked = lv ~= nil and (e.level or 0) > lv }
    end
    return Veyl.Ok({ id = d.id, label = d.label, unlimited = C.UnlimitedStock == true, categories = C.Categories, items = items, cash = exports.veyl_core:GetMoney(src, C.Payment) or 0, level = lv, maxPerLine = C.MaxPerLine })
end)

Veyl.RegisterCallback('buy', function(src, cid, dealerId, item, qty)
    local d = type(dealerId) == 'string' and byId[dealerId]
    local e = type(item) == 'string' and byItem[item]
    qty = int(qty, C.MaxPerLine)
    if not d or not e or not qty then suspicious(src, cid, 'bad_buy', { dealer = dealerId, item = item, qty = qty }) return Veyl.Err('INVALID_INPUT', 'Bad request') end
    if not near(src, d) then return Veyl.Err('TOO_FAR', 'Go to the dealer') end
    if not allowed(src) then return Veyl.Err('NOT_TRUSTED', 'He does not know you') end
    local lv = level(cid)
    if lv ~= nil and (e.level or 0) > lv then return Veyl.Err('LEVEL_REQUIRED', ('He wants a reputation of %d first'):format(e.level)) end
    if os.time() - (lastBuy[cid] or 0) < C.PurchaseCooldown then return Veyl.Err('RATE_LIMITED', 'Slow down') end
    lastBuy[cid] = os.time()
    if not C.UnlimitedStock then restock(e) end
    local s = stock[e.item]
    if not C.UnlimitedStock and s.n < qty then return Veyl.Err('OUT_OF_STOCK', s.n > 0 and ('Only %d left'):format(s.n) or 'Sold out') end
    local can = Veyl.Await('veyl_inventory', 'CanCarry', 10000, cid, e.item, qty, nil)
    if not (can and can.ok) then return Veyl.Err('INVENTORY_FULL', 'You cannot carry that') end
    local total = e.price * qty
    if not C.UnlimitedStock then s.n = s.n - qty end   -- reserve first (no yield between the check and the take)
    local tag = ('blackmarket:%s:%s'):format(cid, Veyl.NewId())
    local pay = Veyl.Await('veyl_core', 'DebitOnce', 15000, cid, C.Payment, total, ('Black market: %dx %s'):format(qty, e.item), tag)
    if not (pay and pay.ok) then
        if not C.UnlimitedStock then s.n = s.n + qty end
        return Veyl.Err(pay and pay.code or 'INSUFFICIENT_FUNDS', 'You cannot afford that')
    end
    local give = Veyl.Await('veyl_inventory', 'GiveItem', 15000, cid, e.item, qty, nil, tag)
    if not (give and give.ok) then
        if not C.UnlimitedStock then s.n = s.n + qty end
        Veyl.Await('veyl_core', 'CreditOnce', 15000, cid, C.Payment, total, 'Black market refund', tag .. ':refund')
        return Veyl.Err('FAILED', 'The deal fell through. You were refunded.')
    end
    if not C.UnlimitedStock then MySQL.update('UPDATE veyl_blackmarket_stock SET stock = ? WHERE item = ?', { s.n, e.item }) end
    Veyl.Audit(src, 'blackmarket_buy', { dealer = d.id, item = e.item, qty = qty, total = total })
    TriggerEvent('veyl_blackmarket:purchased', src, cid, e.item, qty, total)
    if C.Police.Enabled and math.random() < C.Police.Chance and GetResourceState(C.Police.Resource) == 'started' then
        local p = d.ped.coords
        pcall(function() exports[C.Police.Resource][C.Police.Export](exports[C.Police.Resource], { code = C.Police.Code, message = C.Police.Message, coords = vector3(p.x, p.y, p.z) }) end)
    end
    return Veyl.Ok({ stock = C.UnlimitedStock and e.stock or s.n, cash = exports.veyl_core:GetMoney(src, C.Payment) or 0 }, ('Bought %dx %s for $%d'):format(qty, label(e.item), total))
end)
