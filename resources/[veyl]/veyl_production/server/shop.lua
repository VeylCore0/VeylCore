-- Shops and the buyer. There is one shop per branch (config/botanical.lua, field_operations.lua, supplier_operations.lua) and one buyer who
-- pays for goods from every branch. Prices and stock live on the server; payment is a durable debit with an operation id, so a retry never
-- charges or delivers twice. Stock restocks over time and is stored, so a restart does not reset it.

Prod = Prod or {}
Prod.Shop = { defs = {} }
local Shop = Prod.Shop
local C = ProductionConfig
local stock = {} -- [shop][item] = { stock, at }

local function build()
    Shop.defs = {}
    local list = { { def = C.Shop, branch = 'botanical' }, { def = C.Field and C.Field.Shop, branch = 'field' }, { def = C.Supplier and C.Supplier.Shop, branch = 'supplier' } }
    for _, e in ipairs(list) do
        local d = e.def
        if d and C.Branches[e.branch] and C.Branches[e.branch].enabled then
            Shop.defs[d.Id] = { id = d.Id, branch = d.Branch or e.branch, label = d.Label or d.Ped.label, ped = d.Ped, items = d.Items, restock = d.RestockMinutes, blip = d.Blip }
        end
    end
end

function Shop.load()
    build()
    for _, r in ipairs(MySQL.query.await('SELECT shop, item, stock, restocked_at FROM veyl_prod_stock') or {}) do
        stock[r.shop] = stock[r.shop] or {}
        stock[r.shop][r.item] = { stock = r.stock, at = r.restocked_at }
    end
    for id, d in pairs(Shop.defs) do
        stock[id] = stock[id] or {}
        for _, e in ipairs(d.items) do
            if not stock[id][e.item] then
                stock[id][e.item] = { stock = e.stock, at = os.time() }
                MySQL.update('INSERT IGNORE INTO veyl_prod_stock (shop, item, stock, restocked_at) VALUES (?, ?, ?, ?)', { id, e.item, e.stock, os.time() })
            end
        end
    end
end

local function entry(d, item) for _, e in ipairs(d.items) do if e.item == item then return e end end end

--- Brings stock up to date (restocks accrue per full interval since the last restock).
local function refresh(d, e)
    local s = stock[d.id][e.item]
    local intervals = math.floor((os.time() - s.at) / (d.restock * 60))
    if intervals > 0 and s.stock < e.stock then
        s.stock = math.min(e.stock, s.stock + intervals * e.restock)
        s.at = s.at + intervals * d.restock * 60
        MySQL.update('UPDATE veyl_prod_stock SET stock = ?, restocked_at = ? WHERE shop = ? AND item = ?', { s.stock, s.at, d.id, e.item })
    elseif intervals > 0 then s.at = os.time() end
end

--- The buyer's price list: every enabled branch's goods.
function Shop.prices()
    local out = {}
    for _, t in ipairs({ { 'botanical', C.Botanical.Buyer }, { 'field', C.Field and C.Field.Buyer }, { 'supplier', C.Supplier and C.Supplier.Buyer } }) do
        if C.Branches[t[1]] and C.Branches[t[1]].enabled and t[2] then for item, price in pairs(t[2]) do out[item] = price end end
    end
    return out
end

function Shop.def(id) return Shop.defs[id] end

--- The shop page. With no id: the buyer's page.
function Shop.view(cid, id)
    local out = { id = id, items = {}, quality = C.Quality.Tiers, unlimited = C.UnlimitedStock == true }
    local d = id and Shop.defs[id]
    if d then
        out.label = d.label
        out.restockMinutes = d.restock
        local level = Prod.Prog.level(cid, d.branch)
        for _, e in ipairs(d.items) do
            refresh(d, e)
            out.items[#out.items + 1] = { item = e.item, label = ProdItemLabels[e.item] or e.item, price = e.price, stock = stock[d.id][e.item].stock, max = e.stock, level = e.level, locked = level < e.level, branch = d.branch }
        end
    end
    local sell = {}
    local bonus = Prod.Crews.sellBonus(cid)
    for item, price in pairs(Shop.prices()) do
        local info = Prod.Market.info(item)
        sell[#sell + 1] = { item = item, label = ProdItemLabels[item] or item, base = price, price = math.floor(price * Prod.Market.mult(item) * bonus), trend = info.trend }
    end
    table.sort(sell, function(a, b) return a.base > b.base end)
    out.sell = sell
    return out
end

function Shop.buy(src, cid, shopId, item, qty)
    local d = Prod.Sec.str(shopId, 32, '^[%w_]+$') and Shop.defs[shopId]
    local e = d and Prod.Sec.str(item, 48, '^[%w_]+$') and entry(d, item)
    qty = Prod.Sec.int(qty, 100)
    if not e or not qty or qty < 1 then Prod.Sec.invalid(src, cid, 'shop_bad_request', { shop = shopId, item = item }) return Veyl.Err('INVALID_INPUT', 'Bad request') end
    if not Prod.Sec.near(src, d.ped.coords, C.Distance.Shop) then return Veyl.Err('TOO_FAR', 'Go to the shop') end
    if Prod.Prog.level(cid, d.branch) < e.level then return Veyl.Err('LEVEL_REQUIRED', ('Needs %s level %d'):format(d.branch, e.level)) end
    if not Prod.Sec.try(cid, 'purchase', C.Cooldowns.Purchase) then return Veyl.Err('RATE_LIMITED', 'Slow down') end
    refresh(d, e)
    local s = stock[d.id][e.item]
    if not C.UnlimitedStock and s.stock < qty then return Veyl.Err('OUT_OF_STOCK', ('Only %d left'):format(s.stock)) end
    if not Prod.Inv.canCarry(cid, e.item, qty) then return Veyl.Err('INVENTORY_FULL', 'You cannot carry that') end
    local total = e.price * qty
    -- Reserve the stock first (in memory, no yielding between check and take), then charge, then deliver; any failure puts it back.
    if not C.UnlimitedStock then s.stock = s.stock - qty end
    local tag = ('prodbuy:%s:%s'):format(cid, Veyl.NewId())
    local pay = Prod.Inv.debit(cid, total, ('%s: %dx %s'):format(d.label, qty, e.item), tag)
    if not (pay and pay.ok) then
        if not C.UnlimitedStock then s.stock = s.stock + qty end
        return Veyl.Err(pay and pay.code or 'INSUFFICIENT_FUNDS', 'You cannot afford that')
    end
    local give = Prod.Inv.give(cid, e.item, qty, nil, tag)
    if not (give and give.ok) then
        if not C.UnlimitedStock then s.stock = s.stock + qty end
        Prod.Inv.credit(cid, total, 'Shop refund', tag .. ':refund')
        return Veyl.Err('FAILED', 'Could not deliver it. You were refunded.')
    end
    if not C.UnlimitedStock then MySQL.update('UPDATE veyl_prod_stock SET stock = ? WHERE shop = ? AND item = ?', { s.stock, d.id, e.item }) end
    Prod.Prog.stat(cid, 'purchases')
    Prod.Prog.stat(cid, 'money_spent', total)
    Prod.Log.event('purchase', cid, ('bought %dx %s for $%d'):format(qty, e.item, total))
    return Veyl.Ok({ stock = s.stock }, ('Bought %dx %s for $%d'):format(qty, ProdItemLabels[e.item] or e.item, total))
end

--- Sell a stack of finished goods to the buyer. The price comes from the item's server-held quality, not from anything the client says.
function Shop.sell(src, cid, item, qty)
    local base = Prod.Sec.str(item, 48, '^[%w_]+$') and Shop.prices()[item]
    qty = Prod.Sec.int(qty, 500)
    if not base or not qty or qty < 1 then Prod.Sec.invalid(src, cid, 'sell_bad_request', { item = item }) return Veyl.Err('INVALID_INPUT', 'Bad request') end
    if not Prod.Sec.near(src, C.Buyer.Ped.coords, C.Distance.Shop) then return Veyl.Err('TOO_FAR', 'Go to the buyer') end
    if not Prod.Sec.try(cid, 'purchase', C.Cooldowns.Purchase) then return Veyl.Err('RATE_LIMITED', 'Slow down') end
    local remaining, total, sold = qty, 0, 0
    local unit = Prod.Market.mult(item) * Prod.Crews.sellBonus(cid)
    local tag = ('prodsell:%s:%s'):format(cid, Veyl.NewId())
    for _, st in ipairs(Prod.Inv.stacks(src, item)) do
        if remaining <= 0 then break end
        local n = math.min(remaining, st.count)
        local meta = next(st.metadata) and st.metadata or nil
        local q = st.metadata.quality
        local mult = q and ProdUtil.tier(q).mult or 1.0
        local r = Prod.Inv.take(cid, item, n, meta, ('%s:%d'):format(tag, sold + 1))
        if r and r.ok then
            total = total + math.floor(base * mult * unit * n)
            remaining = remaining - n
            sold = sold + 1
        end
    end
    if total <= 0 then return Veyl.Err('NO_ITEM', ('You have no %s to sell'):format(ProdItemLabels[item] or item)) end
    Prod.Inv.credit(cid, total, ('Sold %s'):format(item), tag)
    Prod.Market.record(item, qty - remaining)
    Prod.Prog.award(cid, ProdItemBranch(item), 'sell')
    Prod.Prog.stat(cid, 'sales')
    Prod.Prog.stat(cid, 'money_earned', total)
    Prod.Log.event('sale', cid, ('sold %dx %s for $%d'):format(qty - remaining, item, total))
    return Veyl.Ok({ total = total, sold = qty - remaining }, ('Sold %d for $%d'):format(qty - remaining, total))
end

--- Which branch an item belongs to (for the XP of selling it).
function ProdItemBranch(item)
    if item:find('^prod_field') or item:find('^prod_fseed') then return 'field' end
    if item == 'prod_compound' or item == 'prod_batch_pack' or item == 'prod_supply_kit' then return 'supplier' end
    return 'botanical'
end
