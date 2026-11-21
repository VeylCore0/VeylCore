-- Item use hooks (veyl_inventory use pipeline) and supplier NPCs.

---------------------------------------------------------------------------
-- Use handlers: seeds and equipment start placement mode (nothing is consumed until placement succeeds);
-- the journal opens the tablet.
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
    exports.veyl_inventory:RegisterUseHandler('drug_place_equipment', function(ctx)
        local kind = DrugsEquipmentByItem[ctx.item]
        if kind then TriggerClientEvent('veyl_drugs:beginPlacement', ctx.source, { item = ctx.item, equipment = kind }) end
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
-- Suppliers: limited stock per supplier, restocks over time, paid with DebitOnce, delivered with GiveItem
-- (same operation id). Stock is reserved before paying and released on any failure.
---------------------------------------------------------------------------
local stock = {} -- ['<supplier>/<item[:variety]>'] = { stock, restockedAt, dirty }

local function keyOf(sid, e) return sid .. '/' .. (e.variety and (e.item .. ':' .. e.variety) or e.item) end

local function seedMeta(e)
    if not e.variety then return nil end
    for _, prod in pairs(DrugsProducts) do
        if prod.seedItem == e.item and prod.varieties[e.variety] then return { variety = e.variety, varietyLabel = prod.varieties[e.variety].label } end
    end
end

local function labelOf(e)
    local def = exports.veyl_inventory:GetItemDefinition(e.item)
    local label = def and def.label or e.item
    local meta = seedMeta(e)
    return meta and ('%s (%s)'):format(label, meta.varietyLabel) or label
end

local function restock(now)
    for sid, s in pairs(DrugsConfig.Suppliers) do
        for _, e in ipairs(s.stock) do
            local st = stock[keyOf(sid, e)]
            if st then
                local periods = math.floor((now - st.restockedAt) / (s.restockMinutes * 60))
                if periods > 0 then
                    st.stock = math.min(e.max, st.stock + periods * e.restock)
                    st.restockedAt = st.restockedAt + periods * s.restockMinutes * 60
                    st.dirty = true
                end
            end
        end
    end
end

local function save()
    for k, st in pairs(stock) do
        if st.dirty then
            st.dirty = false
            MySQL.update('INSERT INTO veyl_drug_supplier_stock (k, stock, restocked_at) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE stock = VALUES(stock), restocked_at = VALUES(restocked_at)',
                { k, st.stock, st.restockedAt })
        end
    end
end

AddEventHandler('veyl_drugs:ready', function()
    local rows = MySQL.query.await('SELECT k, stock, restocked_at FROM veyl_drug_supplier_stock') or {}
    local saved = {}
    for _, r in ipairs(rows) do saved[r.k] = r end
    local now = os.time()
    for sid, s in pairs(DrugsConfig.Suppliers) do
        for _, e in ipairs(s.stock) do
            local k = keyOf(sid, e)
            local r = saved[k]
            stock[k] = { stock = r and math.min(r.stock, e.max) or e.max, restockedAt = r and r.restocked_at or now, dirty = r == nil }
        end
    end
    restock(now)
    save()
end)

local function supplierFor(src, sid)
    local s = DrugsConfig.Suppliers[sid]
    if not s then return nil end
    local pos = Drugs.PlayerPos(src)
    if not pos or #(pos - vector3(s.coords.x, s.coords.y, s.coords.z)) > 4.0 then return nil end
    return s
end

Veyl.RegisterCallback('supplierList', function(src, _, sid)
    local s = supplierFor(src, sid)
    if not s then return Veyl.Err('TOO_FAR', 'Talk to the seller') end
    restock(os.time())
    local list = {}
    for i, e in ipairs(s.stock) do
        local st = stock[keyOf(sid, e)]
        list[#list + 1] = { index = i, item = e.item, label = labelOf(e), price = e.price, stock = st and st.stock or 0, max = e.max }
    end
    return Veyl.Ok({ label = s.label, subtitle = s.subtitle, items = list, restockMinutes = s.restockMinutes, methods = s.methods })
end, { cooldown = 500 })

--- supplierBuy(supplierId, index, count, method, clientOp)
Veyl.RegisterCallback('supplierBuy', function(src, citizenid, sid, index, count, method, clientOp)
    local s = supplierFor(src, sid)
    if not s then return Veyl.Err('TOO_FAR', 'Talk to the seller') end
    local e = Veyl.Validate.int(index, 1, #s.stock) and s.stock[index]
    if not e then return Veyl.Err('INVALID_INPUT', 'Unknown item') end
    if not Veyl.Validate.int(count, 1, 20) then return Veyl.Err('INVALID_INPUT', 'Choose 1 to 20') end
    if not Veyl.Validate.oneOf(method, s.methods) then return Veyl.Err('INVALID_INPUT', 'That payment method is not accepted here') end
    if not Drugs.ValidClientOp(clientOp) then return Veyl.Err('INVALID_INPUT', 'Invalid request') end
    restock(os.time())
    local st = stock[keyOf(sid, e)]
    if not st or st.stock < count then return Veyl.Err('OUT_OF_STOCK', ('Only %d left'):format(st and st.stock or 0)) end
    local meta = seedMeta(e)
    local fits = Drugs.Inv.CanCarry(citizenid, e.item, count, meta)
    if not fits.ok then return Veyl.Err('INVENTORY_FULL', 'You cannot carry that much') end
    local total = e.price * count
    local op = ('supply:%s:%s'):format(citizenid, clientOp)
    st.stock = st.stock - count
    st.dirty = true
    local pay = Drugs.Money.Debit(citizenid, method, total, s.label, op)
    if not pay.ok and pay.code ~= 'DUPLICATE_OPERATION' then
        st.stock = st.stock + count
        return pay
    end
    local give = Drugs.Inv.Give(citizenid, e.item, count, meta, op)
    if not give.ok and give.code ~= 'DUPLICATE_OPERATION' then
        if give.code ~= 'TIMEOUT' then
            Drugs.Money.Credit(citizenid, method, total, 'Refund: ' .. s.label, op .. ':refund')
            st.stock = st.stock + count
        end
        save()
        return Veyl.Err(give.code or 'INVENTORY_FULL', 'Could not hand over the items; you were refunded')
    end
    save()
    Drugs.Log(citizenid, 'supplier_buy', nil, { supplier = sid, item = keyOf(sid, e), count = count, total = total })
    return Veyl.Ok(nil, ('Bought %dx %s for $%d'):format(count, labelOf(e), total))
end, { cooldown = 1000 })
