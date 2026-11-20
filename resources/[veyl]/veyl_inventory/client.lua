-- veyl_inventory client: stash access points (ox_inventory renders the inventory UI itself).

exports('GetItemDefinition', function(item) return exports.ox_inventory:Items(item) end)

AddEventHandler('veyl_inventory:openStash', function(args)
    if not Veyl.IsLoaded() or not args or not args.id then return end
    exports.ox_inventory:openInventory('stash', args.id)
end)

CreateThread(function()
    while GetResourceState('veyl_interact') ~= 'started' do Wait(200) end
    for _, s in ipairs(InventoryConfig.Stashes) do
        exports.veyl_interact:AddZone({
            id = 'stash_' .. s.id, coords = s.coords, radius = s.radius or 2.0, icon = 'fa-solid fa-box-archive',
            label = 'Open ' .. s.label, event = 'veyl_inventory:openStash', args = { id = s.id },
        })
    end
end)
