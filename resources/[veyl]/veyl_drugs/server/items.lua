-- Item use hooks (veyl_inventory use pipeline) and the Garden Supplier.

---------------------------------------------------------------------------
-- Use handlers: seeds start placement mode (nothing is consumed until placement succeeds); the journal opens the tablet.
---------------------------------------------------------------------------
local function registerUse()
    if GetResourceState('veyl_inventory') ~= 'started' then return end
    exports.veyl_inventory:RegisterUseHandler('drug_place', function(ctx)
        local meta = ctx.metadata or {}
        for productId, prod in pairs(DrugsProducts) do
            if prod.seedItem == ctx.item then
                if not prod.varieties[meta.variety] then
                    return Veyl.Notify(ctx.source, 'This seed has no known variety', 'error')
                end
                TriggerClientEvent('veyl_drugs:beginPlacement', ctx.source, { item = ctx.item, product = productId, variety = meta.variety })
                return
            end
        end
    end)
    exports.veyl_inventory:RegisterUseHandler('drug_journal', function(ctx)
        TriggerClientEvent('veyl_drugs:openJournal', ctx.source)
    end)
end

CreateThread(registerUse)
AddEventHandler('onResourceStart', function(res) if res == 'veyl_inventory' then SetTimeout(1000, registerUse) end end)

Veyl.RegisterCallback('hasJournal', function(src)
    local item = DrugsConfig.Journal.RequireItem
    return Veyl.Ok({ ok = not item or Drugs.Inv.Count(src, item) > 0 })
end, { cooldown = 500 })

---------------------------------------------------------------------------
-- Garden Supplier: limited stock, restocks over time, paid with DebitOnce, delivered with GiveItem (same operation id).
---------------------------------------------------------------------------
local S = DrugsConfig.Supplier
local stock = {} -- [key] = { stock, restockedAt }

local function keyOf(e) return e.variety and (e.item .. ':' .. e.variety) or e.item end

local function labelOf(e)
    local def = exports.veyl_inventory:GetItemDefinition(e.item)
    local label = def and def.label or e.item
    if e.variety then
        for _, prod in pairs(DrugsProducts) do
            if prod.seedItem == e.item and prod.varieties[e.variety] then return ('%s (%s)'):format(label, prod.varieties[e.variety].label) end
        end
    end
    return label
end

local function restock(now)
    for _, e in ipairs(S.stock) do
        local s = stock[keyOf(e)]
        if s then
            local periods = math.floor((now - s.restockedAt) / (S.restockMinutes * 60))
            if periods > 0 then
                s.stock = math.min(e.max, s.stock + periods * e.restock)
                s.restockedAt = s.restockedAt + periods * S.restockMinutes * 60
                s.dirty = true
            end
        end
    end
end

local function save()
    for k, s in pairs(stock) do
        if s.dirty then
            s.dirty = false
            MySQL.update('INSERT INTO veyl_drug_supplier_stock (k, stock, restocked_at) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE stock = VALUES(stock), restocked_at = VALUES(restocked_at)',
                { k, s.stock, s.restockedAt })
        end
    end
end

AddEventHandler('veyl_drugs:ready', function()
    local rows = MySQL.query.await('SELECT k, stock, restocked_at FROM veyl_drug_supplier_stock') or {}
    local saved = {}
    for _, r in ipairs(rows) do saved[r.k] = r end
    local now = os.time()
    for _, e in ipairs(S.stock) do
        local r = saved[keyOf(e)]
        stock[keyOf(e)] = { stock = r and math.min(r.stock, e.max) or e.max, restockedAt = r and r.restocked_at or now, dirty = r == nil }
    end
    restock(now)
    save()
end)

local function nearSupplier(src)
    local pos = Drugs.PlayerPos(src)
    local c = S.coords
    return pos ~= nil and #(pos - vector3(c.x, c.y, c.z)) <= 4.0
end

Veyl.RegisterCallback('supplierList', function(src)
    if not nearSupplier(src) then return Veyl.Err('TOO_FAR', 'Talk to the supplier') end
    restock(os.time())
    local list = {}
    for i, e in ipairs(S.stock) do
        local s = stock[keyOf(e)]
        list[#list + 1] = { index = i, label = labelOf(e), price = e.price, stock = s and s.stock or 0, max = e.max }
    end
    return Veyl.Ok({ items = list, restockMinutes = S.restockMinutes })
end, { cooldown = 500 })

--- buy(index, count, opId)
Veyl.RegisterCallback('supplierBuy', function(src, citizenid, index, count, clientOp)
    if not nearSupplier(src) then return Veyl.Err('TOO_FAR', 'Talk to the supplier') end
    local e = Veyl.Validate.int(index, 1, #S.stock) and S.stock[index]
    if not e then return Veyl.Err('INVALID_INPUT', 'Unknown item') end
    if not Veyl.Validate.int(count, 1, 20) then return Veyl.Err('INVALID_INPUT', 'Choose 1 to 20') end
    if not Drugs.ValidClientOp(clientOp) then return Veyl.Err('INVALID_INPUT', 'Invalid request') end
    restock(os.time())
    local s = stock[keyOf(e)]
    if not s or s.stock < count then return Veyl.Err('OUT_OF_STOCK', ('Only %d left'):format(s and s.stock or 0)) end
    local meta = nil
    if e.variety then
        for _, prod in pairs(DrugsProducts) do
            if prod.seedItem == e.item then meta = { variety = e.variety, varietyLabel = prod.varieties[e.variety].label } end
        end
    end
    local fits = Drugs.Inv.CanCarry(citizenid, e.item, count, meta)
    if not fits.ok then return Veyl.Err('INVENTORY_FULL', 'You cannot carry that much') end
    local total = e.price * count
    local op = ('supply:%s:%s'):format(citizenid, clientOp)
    s.stock = s.stock - count -- reserve before paying; released on any failure
    s.dirty = true
    local pay = Drugs.Money.Debit(citizenid, S.methods[1], total, 'Garden supplies', op)
    if not pay.ok and pay.code ~= 'DUPLICATE_OPERATION' then
        s.stock = s.stock + count
        return pay
    end
    local give = Drugs.Inv.Give(citizenid, e.item, count, meta, op)
    if not give.ok and give.code ~= 'DUPLICATE_OPERATION' then
        if give.code ~= 'TIMEOUT' then
            Drugs.Money.Credit(citizenid, S.methods[1], total, 'Refund: garden supplies', op .. ':refund')
            s.stock = s.stock + count
        end
        save()
        return Veyl.Err(give.code or 'INVENTORY_FULL', 'Could not hand over the items; you were refunded')
    end
    save()
    Drugs.Log(citizenid, 'supplier_buy', nil, { item = keyOf(e), count = count, total = total })
    return Veyl.Ok(nil, ('Bought %dx %s for $%d'):format(count, labelOf(e), total))
end, { cooldown = 1000 })
