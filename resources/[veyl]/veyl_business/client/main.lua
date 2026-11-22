-- veyl_business client: office menu, stockroom, workstations, register and the customer's bill prompt.

local C = BusinessConfig

local function money(n) return ('$%s'):format(tostring(math.floor(n or 0)):reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')) end

local function office(id)
    local res = Veyl.Callback('veyl_business', 'office', id)
    if not res.ok then return Veyl.NotifyResult(res) end
    local o = res.data
    local items = {}
    if not o.owned then
        items[#items + 1] = { label = ('Buy %s'):format(o.label), description = ('%s · needs a business licence'):format(money(o.price)), value = 'buy' }
    else
        items[#items + 1] = { label = ('Owner: %s'):format(o.owner or '?'), disabled = true }
    end
    if o.staff then
        items[#items + 1] = { label = 'Business account', right = money(o.balance), disabled = true }
        if o.boss then
            items[#items + 1] = { label = 'Deposit', value = 'deposit' }
            items[#items + 1] = { label = 'Withdraw', value = 'withdraw' }
            items[#items + 1] = { label = 'Recent transactions', value = 'ledger' }
        end
        if o.canOrder then items[#items + 1] = { label = 'Order ingredients', description = 'Paid from the business account', value = 'order' } end
    end
    if o.isOwner then items[#items + 1] = { label = 'Sell the business', description = ('You get %s back'):format(money(o.sellBack)), value = 'sell' } end
    local choice = Veyl.UI.Menu({ title = o.label, subtitle = o.staff and 'Office' or 'Business office', items = items })
    if not choice then return end
    if choice == 'buy' then
        if Veyl.UI.Confirm({ title = 'Buy ' .. o.label, message = ('Pay %s from your bank and become the owner?'):format(money(o.price)) }) then
            Veyl.NotifyResult(Veyl.CallbackTimeout('veyl_business', 'buy', 20000, id))
        end
    elseif choice == 'sell' then
        if Veyl.UI.Confirm({ title = 'Sell ' .. o.label, message = ('Sell it for %s? Your staff keep their jobs; the account stays with the business.'):format(money(o.sellBack)) }) then
            Veyl.NotifyResult(Veyl.CallbackTimeout('veyl_business', 'sell', 20000, id))
        end
    elseif choice == 'deposit' then
        local v = vlib.inputDialog('Deposit', {
            { name = 'amount', label = 'Amount ($)', type = 'number', required = true, min = 1 },
            { name = 'method', label = 'From', type = 'select', required = true, default = 'bank', options = { { value = 'bank', label = 'Bank' }, { value = 'cash', label = 'Cash' } } },
        }, { submitLabel = 'Deposit' })
        if v then Veyl.NotifyResult(Veyl.CallbackTimeout('veyl_business', 'deposit', 15000, id, tonumber(v.amount), v.method)) end
    elseif choice == 'withdraw' then
        local v = vlib.inputDialog('Withdraw to your bank', { { name = 'amount', label = 'Amount ($)', type = 'number', required = true, min = 1 } }, { submitLabel = 'Withdraw' })
        if v then Veyl.NotifyResult(Veyl.CallbackTimeout('veyl_business', 'withdraw', 15000, id, tonumber(v.amount))) end
    elseif choice == 'ledger' then
        local rows = {}
        for i, l in ipairs(o.ledger or {}) do rows[i] = { label = l.reason, description = l.actor, right = (l.delta >= 0 and '+' or '-') .. money(math.abs(l.delta)), disabled = true } end
        if #rows == 0 then rows[1] = { label = 'No transactions yet', disabled = true } end
        Veyl.UI.Menu({ title = 'Recent transactions', items = rows })
    elseif choice == 'order' then
        local opts = {}
        for i, s in ipairs(o.supplies) do opts[i] = { value = tostring(i), label = ('%s (%s each)'):format(s.label, money(s.price)) } end
        local v = vlib.inputDialog('Order ingredients', {
            { name = 'item', label = 'Ingredient', type = 'select', required = true, options = opts, default = opts[1].value },
            { name = 'count', label = 'How many', type = 'number', required = true, min = 1, max = 50, default = 10 },
        }, { submitLabel = 'Order' })
        if v then Veyl.NotifyResult(Veyl.CallbackTimeout('veyl_business', 'order', 15000, id, tonumber(v.item), tonumber(v.count))) end
    end
end

local function craft(id, si, ri)
    local b = C.Businesses[id]
    local st = b.stations[si]
    local start = Veyl.CallbackTimeout('veyl_business', 'craftStart', 10000, id, si, ri)
    if not start.ok then return Veyl.NotifyResult(start) end
    if st.scenario then TaskStartScenarioInPlace(PlayerPedId(), st.scenario, 0, true) end
    local done = vlib.progress({ label = st.label, duration = start.data.seconds * 1000, canCancel = true, disable = { move = true, car = true, combat = true } })
    ClearPedTasks(PlayerPedId())
    if not done then return Veyl.Notify('Stopped', 'info') end
    Veyl.NotifyResult(Veyl.CallbackTimeout('veyl_business', 'craftFinish', 10000, start.data.token))
end

local function charge(id)
    local me, pc = PlayerId(), GetEntityCoords(PlayerPedId())
    local opts = {}
    for _, pid in ipairs(GetActivePlayers()) do
        if pid ~= me and #(GetEntityCoords(GetPlayerPed(pid)) - pc) < 5.0 then
            local sid = GetPlayerServerId(pid)
            opts[#opts + 1] = { value = tostring(sid), label = ('Customer #%d'):format(sid) }
        end
    end
    if #opts == 0 then return Veyl.Notify('No customer at the counter', 'error') end
    local v = vlib.inputDialog('Charge a customer', {
        { name = 'target', label = 'Customer', type = 'select', required = true, options = opts, default = opts[1].value },
        { name = 'amount', label = 'Amount ($)', type = 'number', required = true, min = 1, max = C.RegisterMax },
        { name = 'note', label = 'For', type = 'text', maxLength = 80, placeholder = 'e.g. 2 coffees and a sandwich' },
    }, { submitLabel = 'Send' })
    if v then Veyl.NotifyResult(Veyl.CallbackTimeout('veyl_business', 'charge', 15000, id, tonumber(v.target), tonumber(v.amount), v.note)) end
end

RegisterNetEvent('veyl_business:bill', function(token, info)
    if type(info) ~= 'table' then return end
    CreateThread(function()
        local choice = Veyl.UI.Menu({ title = info.label, subtitle = ('%s%s'):format(money(info.amount), info.note ~= '' and (' · ' .. info.note) or ''),
            items = { { label = 'Pay by card', value = 'bank' }, { label = 'Pay in cash', value = 'cash' }, { label = 'Decline', value = 'decline' } } })
        local res = Veyl.Callback('veyl_business', 'payBill', token, choice or 'decline')
        Veyl.NotifyResult(res)
    end)
end)

-- Services ----------------------------------------------------------------
local function service(id, index)
    local b = C.Businesses[id]
    local sv = b.services[index]
    if sv.kind == 'wash' or sv.kind == 'cover' then
        local choice = Veyl.UI.Menu({ title = sv.label, subtitle = money(sv.price), items = { { label = 'Pay by card', value = 'bank' }, { label = 'Pay in cash', value = 'cash' } } })
        if choice then Veyl.NotifyResult(Veyl.CallbackTimeout('veyl_business', 'service', 15000, id, index, choice)) end
    elseif sv.kind == 'pawn' then
        local defs = exports.veyl_inventory:Items() or {}
        local items = {}
        for item, price in pairs(sv.prices) do
            local n = exports.veyl_inventory:GetItemCount(item) or 0
            if n > 0 then items[#items + 1] = { label = ('%s × %d'):format(defs[item] and defs[item].label or item, n), right = money(price) .. ' each', value = item } end
        end
        if #items == 0 then return Veyl.Notify('You have nothing they buy', 'info') end
        local pick = Veyl.UI.Menu({ title = sv.label, subtitle = 'Paid in cash (the city pays less when the shop has no owner)', items = items })
        if not pick then return end
        local have = exports.veyl_inventory:GetItemCount(pick) or 1
        local v = vlib.inputDialog('How many?', { { name = 'n', label = 'Amount', type = 'number', required = true, min = 1, max = have, default = have } }, { submitLabel = 'Sell' })
        if v then Veyl.NotifyResult(Veyl.CallbackTimeout('veyl_business', 'service', 15000, id, index, pick, tonumber(v.n))) end
    elseif sv.kind == 'tune' then
        local veh, best = nil, 6.0
        local pc = GetEntityCoords(PlayerPedId())
        for _, v in ipairs(GetGamePool('CVehicle')) do
            local d = #(GetEntityCoords(v) - pc)
            if d < best then veh, best = v, d end
        end
        if not veh then return Veyl.Notify('Bring the vehicle into the bay', 'error') end
        local defs = exports.veyl_inventory:Items() or {}
        local items = {}
        for kit in pairs(sv.kits) do
            local n = exports.veyl_inventory:GetItemCount(kit) or 0
            items[#items + 1] = { label = defs[kit] and defs[kit].label or kit, value = kit, disabled = n == 0, right = n > 0 and ('%d in pockets'):format(n) or 'None' }
        end
        local pick = Veyl.UI.Menu({ title = 'Install a kit', subtitle = GetDisplayNameFromVehicleModel(GetEntityModel(veh)), items = items })
        if not pick then return end
        TaskStartScenarioInPlace(PlayerPedId(), 'PROP_HUMAN_BUM_BIN', 0, true)
        local ok = vlib.progress({ label = 'Installing', duration = 10000, canCancel = true, disable = { move = true, car = true, combat = true } })
        ClearPedTasks(PlayerPedId())
        if ok then Veyl.NotifyResult(Veyl.CallbackTimeout('veyl_business', 'service', 15000, id, index, pick, NetworkGetNetworkIdFromEntity(veh))) end
    end
end

RegisterNetEvent('veyl_business:washed', function(netId)
    local veh = NetworkDoesEntityExistWithNetworkId(netId) and NetToVeh(netId) or 0
    if veh == 0 then return end
    SetVehicleDirtLevel(veh, 0.0)
    WashDecalsFromVehicle(veh, 1.0)
end)

RegisterNetEvent('veyl_business:tuned', function(netId, kit)
    local veh = NetworkDoesEntityExistWithNetworkId(netId) and NetToVeh(netId) or 0
    if veh == 0 or type(kit) ~= 'table' then return end
    SetVehicleModKit(veh, 0)
    if kit.toggle then ToggleVehicleMod(veh, kit.toggle, true)
    elseif kit.mod then SetVehicleMod(veh, kit.mod, GetNumVehicleMods(veh, kit.mod) - 1, false) end
end)

AddEventHandler('veyl_business:service', function(a) CreateThread(function() service(a.id, a.i) end) end)
AddEventHandler('veyl_business:office', function(a) CreateThread(function() office(a.id) end) end)
AddEventHandler('veyl_business:craft', function(a) CreateThread(function() craft(a.id, a.si, a.ri) end) end)
AddEventHandler('veyl_business:charge', function(a) CreateThread(function() charge(a.id) end) end)
AddEventHandler('veyl_business:stash', function(a) exports.veyl_inventory:openInventory('stash', 'biz_' .. a.id) end)

CreateThread(function()
    while GetResourceState('veyl_interact') ~= 'started' do Wait(250) end
    local defs = exports.veyl_inventory:Items() or {}
    for id, b in pairs(C.Businesses) do
        exports.veyl_interact:AddZone({ id = 'veyl_biz_office_' .. id, coords = b.office, radius = 1.5, title = b.label,
            options = { { label = 'Business office', icon = 'briefcase', event = 'veyl_business:office', args = { id = id } } } })
        exports.veyl_interact:AddZone({ id = 'veyl_biz_stash_' .. id, coords = b.stash, radius = 1.5, title = 'Stockroom',
            options = { { label = 'Open stockroom', icon = 'box', event = 'veyl_business:stash', args = { id = id }, groups = { [b.job] = 0 } } } })
        exports.veyl_interact:AddZone({ id = 'veyl_biz_register_' .. id, coords = b.register, radius = 1.5, title = 'Register',
            options = { { label = 'Charge a customer', icon = 'money', event = 'veyl_business:charge', args = { id = id }, groups = { [b.job] = 0 } } } })
        for i, sv in ipairs(b.services or {}) do
            exports.veyl_interact:AddZone({ id = ('veyl_biz_service_%s_%d'):format(id, i), coords = sv.coords, radius = sv.radius or 2.0, title = sv.label,
                options = { { label = ({ wash = ('Wash vehicle (%s)'):format(money(sv.price or 0)), cover = ('Pay entry (%s)'):format(money(sv.price or 0)),
                    pawn = 'Sell valuables', tune = 'Install a performance kit' })[sv.kind], icon = sv.kind == 'pawn' and 'money' or 'car',
                    event = 'veyl_business:service', args = { id = id, i = i }, groups = sv.kind == 'tune' and { [b.job] = 0 } or nil } } })
        end
        for si, st in ipairs(b.stations) do
            local opts = {}
            for ri, rc in ipairs(st.recipes) do
                local d = defs[rc.output]
                opts[#opts + 1] = { label = ('Make %s'):format(d and d.label or rc.output), icon = 'burger', event = 'veyl_business:craft',
                    args = { id = id, si = si, ri = ri }, groups = { [b.job] = 0 } }
            end
            exports.veyl_interact:AddZone({ id = ('veyl_biz_station_%s_%d'):format(id, si), coords = st.coords, radius = 1.3, title = st.label, options = opts })
        end
        if b.blip then
            local blip = AddBlipForCoord(b.office.x, b.office.y, b.office.z)
            SetBlipSprite(blip, b.blip.sprite)
            SetBlipColour(blip, b.blip.colour)
            SetBlipScale(blip, 0.75)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(b.label)
            EndTextCommandSetBlipName(blip)
        end
    end
end)
