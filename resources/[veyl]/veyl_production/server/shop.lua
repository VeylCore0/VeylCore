-- The supply shop and the buyer. Prices and stock live on the server; payment is a durable debit with an operation id, so a retry never
-- charges or delivers twice. Stock restocks over time and is stored, so a restart does not reset it.

Prod = Prod or {}
Prod.Shop = {}
local Shop = Prod.Shop
local C = ProductionConfig
local S = C.Shop
local stock = {} -- [item] = { stock, at }

function Shop.load()
    for _, r in ipairs(MySQL.query.await('SELECT item, stock, restocked_at FROM veyl_prod_stock WHERE shop = ?', { S.Id }) or {}) do stock[r.item] = { stock = r.stock, at = r.restocked_at } end
    for _, e in ipairs(S.Items) do
        if not stock[e.item] then
            stock[e.item] = { stock = e.stock, at = os.time() }
            MySQL.update('INSERT IGNORE INTO veyl_prod_stock (shop, item, stock, restocked_at) VALUES (?, ?, ?, ?)', { S.Id, e.item, e.stock, os.time() })
        end
    end
end

local function entry(item) for _, e in ipairs(S.Items) do if e.item == item then return e end end end

--- Brings stock up to date (restocks accrue per full interval since the last restock).
local function refresh(e)
    local s = stock[e.item]
    local intervals = math.floor((os.time() - s.at) / (S.RestockMinutes * 60))
    if intervals > 0 and s.stock < e.stock then
        s.stock = math.min(e.stock, s.stock + intervals * e.restock)
        s.at = s.at + intervals * S.RestockMinutes * 60
        MySQL.update('UPDATE veyl_prod_stock SET stock = ?, restocked_at = ? WHERE shop = ? AND item = ?', { s.stock, s.at, S.Id, e.item })
    elseif intervals > 0 then s.at = os.time() end
end

function Shop.view(cid)
    local level = Prod.Prog.level(cid, 'botanical')
    local out = {}
    for _, e in ipairs(S.Items) do
        refresh(e)
        out[#out + 1] = { item = e.item, label = ProdItemLabels[e.item] or e.item, price = e.price, stock = stock[e.item].stock, max = e.stock, level = e.level, locked = level < e.level }
    end
    local sell = {}
    for item, price in pairs(C.Botanical.Buyer) do sell[#sell + 1] = { item = item, label = ProdItemLabels[item] or item, base = price } end
    table.sort(sell, function(a, b) return a.base > b.base end)
    return { items = out, sell = sell, quality = C.Quality.Tiers, restockMinutes = S.RestockMinutes }
end

function Shop.buy(src, cid, item, qty)
    local e = Prod.Sec.str(item, 48, '^[%w_]+$') and entry(item)
    qty = Prod.Sec.int(qty, 100)
    if not e or not qty or qty < 1 then Prod.Sec.invalid(src, cid, 'shop_bad_request', { item = item }) return Veyl.Err('INVALID_INPUT', 'Bad request') end
    if not Prod.Sec.near(src, S.Ped.coords, C.Distance.Shop) then return Veyl.Err('TOO_FAR', 'Go to the supplier') end
    if Prod.Prog.level(cid, 'botanical') < e.level then return Veyl.Err('LEVEL_REQUIRED', ('Needs botanical level %d'):format(e.level)) end
    if not Prod.Sec.try(cid, 'purchase', C.Cooldowns.Purchase) then return Veyl.Err('RATE_LIMITED', 'Slow down') end
    refresh(e)
    local s = stock[e.item]
    if s.stock < qty then return Veyl.Err('OUT_OF_STOCK', ('Only %d left'):format(s.stock)) end
    if not Prod.Inv.canCarry(cid, e.item, qty) then return Veyl.Err('INVENTORY_FULL', 'You cannot carry that') end
    local total = e.price * qty
    -- Reserve the stock first (in memory, no yielding between check and take), then charge, then deliver; any failure puts it back.
    s.stock = s.stock - qty
    local tag = ('prodbuy:%s:%s'):format(cid, Veyl.NewId())
    local pay = Prod.Inv.debit(cid, total, ('Supply shop: %dx %s'):format(qty, e.item), tag)
    if not (pay and pay.ok) then
        s.stock = s.stock + qty
        return Veyl.Err(pay and pay.code or 'INSUFFICIENT_FUNDS', 'You cannot afford that')
    end
    local give = Prod.Inv.give(cid, e.item, qty, nil, tag)
    if not (give and give.ok) then
        s.stock = s.stock + qty
        Prod.Inv.credit(cid, total, 'Supply shop refund', tag .. ':refund')
        return Veyl.Err('FAILED', 'Could not deliver it. You were refunded.')
    end
    MySQL.update('UPDATE veyl_prod_stock SET stock = ? WHERE shop = ? AND item = ?', { s.stock, S.Id, e.item })
    Prod.Prog.stat(cid, 'purchases')
    Prod.Prog.stat(cid, 'money_spent', total)
    Prod.Log.event('purchase', cid, ('bought %dx %s for $%d'):format(qty, e.item, total))
    return Veyl.Ok({ stock = s.stock }, ('Bought %dx %s for $%d'):format(qty, ProdItemLabels[e.item] or e.item, total))
end

--- Sell a stack of finished goods to the buyer. The price comes from the item's server-held quality, not from anything the client says.
function Shop.sell(src, cid, item, qty)
    local base = Prod.Sec.str(item, 48, '^[%w_]+$') and C.Botanical.Buyer[item]
    qty = Prod.Sec.int(qty, 500)
    if not base or not qty or qty < 1 then Prod.Sec.invalid(src, cid, 'sell_bad_request', { item = item }) return Veyl.Err('INVALID_INPUT', 'Bad request') end
    if not Prod.Sec.near(src, C.Buyer.Ped.coords, C.Distance.Shop) then return Veyl.Err('TOO_FAR', 'Go to the buyer') end
    if not Prod.Sec.try(cid, 'purchase', C.Cooldowns.Purchase) then return Veyl.Err('RATE_LIMITED', 'Slow down') end
    local remaining, total, sold = qty, 0, 0
    local tag = ('prodsell:%s:%s'):format(cid, Veyl.NewId())
    for _, st in ipairs(Prod.Inv.stacks(src, item)) do
        if remaining <= 0 then break end
        local n = math.min(remaining, st.count)
        local meta = next(st.metadata) and st.metadata or nil
        local q = st.metadata.quality
        local mult = q and ProdUtil.tier(q).mult or 1.0
        local r = Prod.Inv.take(cid, item, n, meta, ('%s:%d'):format(tag, sold + 1))
        if r and r.ok then
            total = total + math.floor(base * mult * n)
            remaining = remaining - n
            sold = sold + 1
        end
    end
    if total <= 0 then return Veyl.Err('NO_ITEM', ('You have no %s to sell'):format(ProdItemLabels[item] or item)) end
    Prod.Inv.credit(cid, total, ('Sold %s'):format(item), tag)
    Prod.Prog.award(cid, 'botanical', 'sell')
    Prod.Prog.stat(cid, 'sales')
    Prod.Prog.stat(cid, 'money_earned', total)
    Prod.Log.event('sale', cid, ('sold %dx %s for $%d'):format(qty - remaining, item, total))
    return Veyl.Ok({ total = total, sold = qty - remaining }, ('Sold %d for $%d'):format(qty - remaining, total))
end
