-- veyl_production server entry: start-up (migrations, loading what was saved), item use handlers, admin diagnostics.

Prod = Prod or {}
local C = ProductionConfig

Veyl.Startup({ 'veyl_core', 'veyl_inventory' }, function()
    local ok = Prod.DB.Migrate()
    if ok == false then return false end
    Prod.Shop.load()
    Prod.Plants.load()
    Prod.Ws.load()
    Prod.Props.load()
    Prod.Supplier.reconcile()
    Prod.Farms.load()
    Prod.ready = true
    print(('[veyl_production] ready: %d plants, %d benches'):format((function() local n = 0 for _ in pairs(Prod.Plants.rows) do n = n + 1 end return n end)(), (function() local n = 0 for _ in pairs(Prod.Ws.rows) do n = n + 1 end return n end)()))
    return true
end)

-- Seeds and benches are placed from the inventory. The handler only tells the player's client to start the placement preview;
-- nothing is consumed until the server accepts the placement.
local function registerUse()
    exports.veyl_inventory:RegisterUseHandler('prod_seed', function(ctx)
        for _, key in ipairs(ProdUtil.varieties()) do
            if ProdUtil.variety(key).seed == ctx.item then TriggerClientEvent('veyl_production:beginPlacement', ctx.source, { kind = 'plant', variety = key, property = Prod.Props.insideOf(ctx.source) }) return end
        end
    end)
    -- Benches: the item picks the bench type; inside a laboratory it is the lab version.
    exports.veyl_inventory:RegisterUseHandler('prod_bench', function(ctx)
        local inside = Prod.Props.insideOf(ctx.source)
        for key, t in pairs(C.Workstations.Types) do
            if t.item == ctx.item and (inside ~= nil) == (not t.portable) then
                TriggerClientEvent('veyl_production:beginPlacement', ctx.source, { kind = 'workstation', type = key, property = inside })
                return
            end
        end
        Veyl.Notify(ctx.source, inside and 'That bench does not belong in a laboratory.' or 'That bench belongs in a laboratory.', 'error')
    end)
end

CreateThread(function()
    while GetResourceState('veyl_inventory') ~= 'started' do Wait(1000) end
    Wait(1000)
    registerUse()
end)
AddEventHandler('onResourceStart', function(res)
    if res == 'veyl_inventory' then CreateThread(function() Wait(2000) registerUse() if Prod.ready then Prod.Props.registerStashes() end end) end
end)

AddEventHandler('playerDropped', function()
    local cid = Veyl.GetCitizenId(source)
    if cid then Prod.Prog.forget(cid) end
end)

---------------------------------------------------------------------------
-- /prodadmin: diag | fix
---------------------------------------------------------------------------
RegisterCommand('prodadmin', function(src, args)
    if src ~= 0 and not Veyl.HasPermission(src, 'production.admin') then return end
    local function say(t) if src == 0 then print('[veyl_production] ' .. t) else Veyl.Notify(src, t, 'info') end end
    if args[1] == 'diag' or args[1] == 'fix' then
        local d = Prod.Ws.diagnose()
        local orphanPlants = Prod.Plants.orphans()
        say(('stuck batches: %d | orphaned batches: %d | orphaned plants: %d'):format(#d.stuck, #d.orphaned, #orphanPlants))
        if args[1] == 'fix' then
            for _, id in ipairs(d.orphaned) do MySQL.update("UPDATE veyl_prod_batches SET state = 'cancelled' WHERE id = ?", { id }) end
            for _, id in ipairs(orphanPlants) do MySQL.update('DELETE FROM veyl_prod_plants WHERE id = ?', { id }) Prod.Plants.rows[id] = nil end
            say('Orphaned batches cancelled and orphaned plants removed. Stuck batches were left for their owners to collect.')
            Prod.Log.event('property', 'system', 'admin fix', { by = src })
        end
    else
        say('Usage: prodadmin diag | prodadmin fix')
    end
end, false)
