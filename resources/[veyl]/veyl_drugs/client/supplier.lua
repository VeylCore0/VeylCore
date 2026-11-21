-- Garden Supplier NPC: limited stock (server), shown in a menu with prices and remaining stock. No map blip.

local function buyFlow(entry)
    if entry.stock < 1 then return Veyl.Notify('Out of stock. Come back later.', 'info') end
    local values = vlib.inputDialog(entry.label, {
        { name = 'count', label = ('Quantity (max %d)'):format(math.min(20, entry.stock)), type = 'number', required = true,
          min = 1, max = math.min(20, entry.stock), default = 1 },
    }, { submitLabel = ('Buy · $%d each'):format(entry.price) })
    if not values then return end
    local count = math.floor(tonumber(values.count) or 0)
    if count < 1 then return end
    local op = ('%08x%06x%06x'):format(GetGameTimer() % 0xffffffff, math.random(0, 0xffffff), math.random(0, 0xffffff))
    Veyl.NotifyResult(Veyl.CallbackTimeout('veyl_drugs', 'supplierBuy', 20000, entry.index, count, op))
end

local function openSupplier()
    local res = Veyl.Callback('veyl_drugs', 'supplierList')
    if not res.ok then return Veyl.NotifyResult(res) end
    local options = {}
    for i, e in ipairs(res.data.items) do
        options[i] = {
            id = tostring(e.index), label = e.label, right = ('$%d'):format(e.price), icon = 'basket', args = e,
            description = e.stock > 0 and ('%d in stock'):format(e.stock) or ('Sold out · restocks every %d min'):format(res.data.restockMinutes),
            disabled = e.stock < 1, disabledReason = 'Sold out',
        }
    end
    vlib.registerMenu({ id = 'veyl_drugs:supplier', title = DrugsConfig.Supplier.label, subtitle = 'Cash only', options = options },
        function(_, entry) CreateThread(function() buyFlow(entry) end) end)
    vlib.showMenu('veyl_drugs:supplier')
end

AddEventHandler('veyl_drugs:supplier', function() CreateThread(openSupplier) end)

CreateThread(function()
    while GetResourceState('veyl_interact') ~= 'started' do Wait(200) end
    local s = DrugsConfig.Supplier
    exports.veyl_interact:AddPed({
        id = 'veyl_drugs_supplier', model = s.model, coords = s.coords, radius = 2.5, icon = 'basket', title = s.label,
        label = 'Browse supplies', event = 'veyl_drugs:supplier',
    })
end)
