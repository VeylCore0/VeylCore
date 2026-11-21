-- Supplier NPCs (Garden Supplier, Smoke on the Water weed store). Stock is limited on the server; the menu shows prices
-- and what's left. Suppliers with a `blip` show on the map.

local function buyFlow(sid, entry, methods)
    if entry.stock < 1 then return Veyl.Notify('Out of stock. Come back later.', 'info') end
    local fields = {
        { name = 'count', label = ('Quantity (max %d)'):format(math.min(20, entry.stock)), type = 'number', required = true,
          min = 1, max = math.min(20, entry.stock), default = 1 },
    }
    if #methods > 1 then
        local opts = {}
        for i, m in ipairs(methods) do opts[i] = { value = m, label = m == 'bank' and 'Bank' or 'Cash' } end
        fields[2] = { name = 'method', label = 'Pay with', type = 'select', required = true, options = opts, default = methods[1] }
    end
    local values = vlib.inputDialog(entry.label, fields, { submitLabel = ('Buy · $%d each'):format(entry.price) })
    if not values then return end
    local count = math.floor(tonumber(values.count) or 0)
    if count < 1 then return end
    local op = ('%08x%06x%06x'):format(GetGameTimer() % 0xffffffff, math.random(0, 0xffffff), math.random(0, 0xffffff))
    Veyl.NotifyResult(Veyl.CallbackTimeout('veyl_drugs', 'supplierBuy', 20000, sid, entry.index, count, values.method or methods[1], op))
end

local function openSupplier(sid)
    local res = Veyl.Callback('veyl_drugs', 'supplierList', sid)
    if not res.ok then return Veyl.NotifyResult(res) end
    local d = res.data
    local options = {}
    for i, e in ipairs(d.items) do
        options[i] = {
            id = tostring(e.index), label = e.label, right = ('$%d'):format(e.price), icon = 'basket', args = e,
            description = e.stock > 0 and ('%d in stock'):format(e.stock) or ('Sold out · restocks every %d min'):format(d.restockMinutes),
            disabled = e.stock < 1, disabledReason = 'Sold out',
        }
    end
    vlib.registerMenu({ id = 'veyl_drugs:supplier:' .. sid, title = d.label, subtitle = d.subtitle, options = options },
        function(_, entry) CreateThread(function() buyFlow(sid, entry, d.methods) end) end)
    vlib.showMenu('veyl_drugs:supplier:' .. sid)
end

AddEventHandler('veyl_drugs:supplier', function(args) if args and args.id then CreateThread(function() openSupplier(args.id) end) end end)

CreateThread(function()
    for sid, s in pairs(DrugsConfig.Suppliers) do
        if s.blip then
            local blip = AddBlipForCoord(s.coords.x, s.coords.y, s.coords.z)
            SetBlipSprite(blip, s.blip.sprite)
            SetBlipColour(blip, s.blip.colour)
            SetBlipScale(blip, s.blip.scale or 0.75)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(s.label)
            EndTextCommandSetBlipName(blip)
        end
    end
    while GetResourceState('veyl_interact') ~= 'started' do Wait(200) end
    for sid, s in pairs(DrugsConfig.Suppliers) do
        exports.veyl_interact:AddPed({
            id = 'veyl_drugs_supplier_' .. sid, model = s.model, coords = s.coords, radius = 2.5, icon = 'basket', title = s.label,
            label = 'Browse supplies', event = 'veyl_drugs:supplier', args = { id = sid },
        })
    end
end)
