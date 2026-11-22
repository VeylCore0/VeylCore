-- Cash as an item. veyl_core stays the authority for the cash balance (ledger, operation ids); the `money` item in a
-- character's pockets mirrors it:
--   * cash changes in the core (wages, shops, robberies...) -> the item count is set to the new balance;
--   * the item leaves or enters the pockets through the inventory (drop, stash, give, pick up, AddItem...) -> the same
--     amount is debited / credited in the core with a durable operation id, so cash and item stay equal.

Cash = { item = InventoryConfig.CashItem or 'money', applying = {} }

local function count(items)
    local n = 0
    for _, it in pairs(items) do if it.name == Cash.item then n = n + it.count end end
    return n
end
Cash.Count = count

local function srcOf(citizenid)
    for src, p in pairs(Players) do if p.citizenid == citizenid then return src end end
end

--- Pockets <- core: set the item count to the character's cash.
function Cash.Sync(src)
    if not ItemDefs[Cash.item] then return end
    local p = Players[src]
    local inv = p and Store.Get(p.invId)
    if not inv then return end
    local pd = exports.veyl_core:GetPlayerData(src)
    local cash = pd and pd.money and math.floor(tonumber(pd.money.cash) or 0)
    if not cash then return end
    -- Under the inventory lock, so a move that is being committed at the same moment cannot overwrite this.
    Store.WithLocks({ inv.id }, function()
        local have = count(inv.items)
        if have == cash then return end
        local items, changed
        if cash > have then
            items, changed = Store.PlanAdd(inv, Store.CopyItems(inv), Cash.item, cash - have, {})
        else
            items, changed = Ops.PlanRemove(inv, Cash.item, have - cash)
        end
        if not items then return end -- no free slot (or cash in use): tried again on the next change
        Cash.applying[inv.id] = true
        Ops.ApplyAndPersist(inv, items, changed, { { inventory = inv.id, item = Cash.item, delta = cash - have, reason = 'cash sync' } })
        Cash.applying[inv.id] = nil
    end, 'cash')
end

--- Pockets -> core: called by Store.Apply after a player inventory changed.
function Cash.OnApplied(inv, before)
    if Cash.applying[inv.id] or inv.type ~= 'player' or not inv.owner then return end
    local delta = count(inv.items) - before
    if delta == 0 then return end
    local citizenid, opId = inv.owner, ('invcash:%s:%d'):format(inv.id, inv.revision)
    CreateThread(function()
        local fn = delta > 0 and 'CreditOnce' or 'DebitOnce'
        local reason = delta > 0 and 'Cash picked up' or 'Cash handed over / stored'
        local p, settled = promise.new(), false
        local function settle(res) if not settled then settled = true p:resolve(res) end end
        exports.veyl_core[fn](exports.veyl_core, citizenid, 'cash', math.abs(delta), reason, opId, settle)
        SetTimeout(15000, function() settle({ ok = false, code = 'TIMEOUT' }) end)
        local r = Citizen.Await(p)
        if not r.ok and r.code ~= 'DUPLICATE_OPERATION' then
            print(('^3[veyl_inventory] cash mirror %s %d for %s failed (%s); resyncing^7'):format(fn, math.abs(delta), citizenid, tostring(r.code)))
            local src = srcOf(citizenid)
            if src then Cash.Sync(src) end
        end
    end)
end

AddEventHandler('VeylCore:Server:OnMoneyChange', function(src, _, moneyType)
    if moneyType ~= 'cash' or not Players[src] then return end
    CreateThread(function() Cash.Sync(src) end)
end)
