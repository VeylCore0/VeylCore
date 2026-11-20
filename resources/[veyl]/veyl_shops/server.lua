-- veyl_shops server. A purchase is a recorded operation:
--   pending -> paid (debit applied) -> delivered (items granted)
--                                   -> refunded (grant failed; refund credited)
--   pending -> failed (debit refused)
-- Restart reconciliation resolves anything left in pending/paid using the banking and inventory op records.

local shops = {}
for _, s in ipairs(ShopsConfig.Shops) do shops[s.id] = s end

local function setStatus(opId, status)
    MySQL.update.await('UPDATE veyl_shop_purchases SET status = ? WHERE op_id = ?', { status, opId })
end

local function refund(p)
    local res = Veyl.Await('veyl_banking', 'Credit', 15000, p.character_id, p.method, p.total,
        'Refund: shop purchase', p.op_id .. ':refund')
    if res.ok or res.code == 'DUPLICATE_OPERATION' then
        setStatus(p.op_id, 'refunded')
        return true
    end
    return false
end

--- staleOnly: skip rows touched in the last 2 minutes (they may still be in flight).
local function reconcile(staleOnly)
    local sql = "SELECT * FROM veyl_shop_purchases WHERE status IN ('pending','paid')"
    if staleOnly then sql = sql .. ' AND updated_at < NOW() - INTERVAL 2 MINUTE' end
    local rows = MySQL.query.await(sql) or {}
    for _, p in ipairs(rows) do
        local debit = Veyl.Await('veyl_banking', 'GetOperation', 15000, p.op_id)
        local grant = Veyl.Await('veyl_inventory', 'GetOperation', 15000, p.op_id)
        if not debit.ok or not grant.ok then
            print(('^3[veyl_shops] reconcile skipped %s (services unavailable)^7'):format(p.op_id))
        elseif grant.data then
            setStatus(p.op_id, 'delivered')
        elseif debit.data then
            refund(p) -- paid but never delivered
        else
            setStatus(p.op_id, 'failed') -- never charged
        end
    end
    if #rows > 0 then print(('^5[veyl_shops] reconciled %d interrupted purchase(s)^7'):format(#rows)) end
end

Veyl.Startup({ 'veyl_core', 'veyl_banking', 'veyl_inventory' }, function()
    local ok = Veyl.Migrate({
        {
            id = '001_purchases',
            sql = {
                [[CREATE TABLE IF NOT EXISTS veyl_shop_purchases (
                    op_id VARCHAR(100) NOT NULL,
                    character_id INT UNSIGNED NOT NULL,
                    shop VARCHAR(64) NOT NULL,
                    item VARCHAR(64) NOT NULL,
                    count INT UNSIGNED NOT NULL,
                    total INT UNSIGNED NOT NULL,
                    method VARCHAR(8) NOT NULL,
                    status ENUM('pending','paid','delivered','refunded','failed') NOT NULL DEFAULT 'pending',
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                    PRIMARY KEY (op_id),
                    KEY idx_status (status)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            },
        },
    })
    if not ok then return false end
    reconcile()
    return true
end)

-- Purchases interrupted by a timeout are resolved periodically, not only at restart.
CreateThread(function()
    while true do
        Wait(10 * 60000)
        if Veyl.IsReady() then
            local ok, err = pcall(reconcile, true)
            if not ok then print(('^1[veyl_shops] reconcile error: %s^7'):format(tostring(err))) end
        end
    end
end)

Veyl.RegisterCallback('buy', function(src, charId, shopId, index, count, method)
    local shop = shops[shopId]
    if not shop or not Veyl.Validate.int(index, 1, #shop.catalog) or not Veyl.Validate.int(count, 1, ShopsConfig.MaxPerPurchase)
        or (method ~= 'cash' and method ~= 'bank') then
        return Veyl.Err('INVALID_INPUT', 'Invalid purchase')
    end
    local pc = Veyl.GetPlayerCoords(src)
    local sc = shop.ped.coords
    if not pc or #(pc - vector3(sc.x, sc.y, sc.z)) > ShopsConfig.UseDistance + 2.0 then
        return Veyl.Err('TOO_FAR', 'You need to be at the counter')
    end
    local entry = shop.catalog[index]
    local total = entry.price * count -- price comes from server config only

    local carry = Veyl.Await('veyl_inventory', 'CanCarry', 10000, charId, entry.item, count)
    if not carry.ok then return carry end

    local opId = Veyl.NewId('shop')
    MySQL.insert.await('INSERT INTO veyl_shop_purchases (op_id, character_id, shop, item, count, total, method) VALUES (?, ?, ?, ?, ?, ?, ?)',
        { opId, charId, shop.id, entry.item, count, total, method })

    local pay = Veyl.Await('veyl_banking', 'TryDebit', 15000, charId, method, total,
        ('%s: %dx %s'):format(shop.label, count, entry.item), opId)
    if not pay.ok then
        if pay.code == 'TIMEOUT' then return Veyl.Err('TIMEOUT', 'Payment is being verified; check your balance shortly') end
        setStatus(opId, 'failed')
        return pay
    end
    setStatus(opId, 'paid')

    local grant = Veyl.Await('veyl_inventory', 'GiveItem', 15000, charId, entry.item, count, nil, opId)
    if grant.ok then
        setStatus(opId, 'delivered')
        return Veyl.Ok({ item = entry.item, count = count, total = total }, ('Bought %dx for $%d'):format(count, total))
    end
    if grant.code == 'TIMEOUT' then
        return Veyl.Err('TIMEOUT', 'Delivery is being verified; it will be completed or refunded')
    end
    refund({ op_id = opId, character_id = charId, method = method, total = total })
    return Veyl.Err(grant.code, (grant.message or 'Could not deliver items') .. ' - you were refunded')
end, { cooldown = 1000 })
