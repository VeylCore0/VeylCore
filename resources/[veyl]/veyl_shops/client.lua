-- veyl_shops client: catalog menu. Prices shown here are for display; the server decides the charge.

local shops = {}
for _, s in ipairs(ShopsConfig.Shops) do shops[s.id] = s end

local function openShop(shopId)
    local shop = shops[shopId]
    if not shop or not Veyl.IsLoaded() then return end
    while true do
        local items = {}
        for i, entry in ipairs(shop.catalog) do
            local def = exports.ox_inventory:Items(entry.item)
            items[i] = { label = def and def.label or entry.item, right = '$' .. entry.price, value = i }
        end
        local index = Veyl.UI.Menu({ title = shop.label, subtitle = 'Prices include tax', items = items })
        if not index then return end
        local entry = shop.catalog[index]
        local v = Veyl.UI.Input({
            title = items[index].label .. ' - $' .. entry.price .. ' each',
            submitLabel = 'Buy',
            fields = {
                { name = 'count', label = 'Quantity', type = 'number', min = 1, max = ShopsConfig.MaxPerPurchase, default = 1, required = true },
                { name = 'method', label = 'Pay with', type = 'select', default = 'cash',
                  options = { { value = 'cash', label = 'Cash' }, { value = 'bank', label = 'Bank card' } } },
            },
        })
        if v and v.count then
            Veyl.NotifyResult(Veyl.Callback('veyl_shops', 'buy', shopId, index, math.floor(v.count), v.method))
        end
    end
end

AddEventHandler('veyl_shops:open', function(args) if args then openShop(args.id) end end)

CreateThread(function()
    while GetResourceState('veyl_interact') ~= 'started' do Wait(200) end
    for _, s in ipairs(ShopsConfig.Shops) do
        exports.veyl_interact:AddPed({ icon = 'fa-solid fa-basket-shopping',
            id = 'shop_' .. s.id, model = s.ped.model, coords = s.ped.coords, radius = ShopsConfig.UseDistance,
            label = 'Shop at ' .. s.label, event = 'veyl_shops:open', args = { id = s.id },
        })
        if s.blip then
            local c = s.ped.coords
            local blip = AddBlipForCoord(c.x, c.y, c.z)
            SetBlipSprite(blip, s.blip.sprite)
            SetBlipColour(blip, s.blip.colour)
            SetBlipScale(blip, 0.7)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(s.label)
            EndTextCommandSetBlipName(blip)
        end
    end
end)
