-- veyl_mechanic client: vehicle repair options (on-duty mechanics in a workshop), the mechanic menu and /invoices.
-- What is shown here is presentation only; the server re-checks duty, location, parts and timing.

local function job() return (Veyl.PlayerData or {}).job or {} end
local function onDuty() local j = job() return j.name == MechanicConfig.Job and j.onduty == true end

local function shopAt(pos)
    for _, s in ipairs(MechanicConfig.Shops) do
        if #(pos - s.coords) <= s.radius then return s end
    end
end

local function hasPart(item) return (exports.veyl_inventory:GetItemCount(item) or 0) > 0 end

--- Whether a repair would actually change something on this vehicle (keeps the option list short).
local function needs(entity, id)
    if id == 'engine' then return GetVehicleEngineHealth(entity) < 990.0 end
    if id == 'body' then return GetVehicleBodyHealth(entity) < 990.0 end
    if id == 'tyres' then
        for i = 0, 7 do if IsVehicleTyreBurst(entity, i, false) then return true end end
        return false
    end
    if id == 'clean' then return GetVehicleDirtLevel(entity) > 1.0 end
    return true
end

local busy = false

local function doRepair(entity, r)
    if busy then return end
    busy = true
    local start = Veyl.Callback('veyl_mechanic', 'startRepair', VehToNet(entity), r.id)
    if not start.ok then busy = false return Veyl.NotifyResult(start) end
    local ped = PlayerPedId()
    TaskTurnPedToFaceEntity(ped, entity, 800)
    Wait(800)
    local done = vlib.progress({
        label = start.data.label, duration = start.data.durationMs, canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = r.id == 'clean' and { dict = 'timetable@floyd@clean_kitchen@base', clip = 'base', flag = 1 }
            or { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 1 },
    })
    if done then
        Veyl.NotifyResult(Veyl.Callback('veyl_mechanic', 'completeRepair', start.data.token))
    else
        Veyl.Callback('veyl_mechanic', 'cancelRepair', start.data.token)
        Veyl.Notify('Repair cancelled', 'info')
    end
    ClearPedTasks(ped)
    busy = false
end

--- Applied by the client that owns the vehicle entity (sent by the server after a completed, paid-for-in-parts repair).
RegisterNetEvent('veyl_mechanic:apply', function(netId, id)
    if not NetworkDoesNetworkIdExist(netId) then return end
    local veh = NetToVeh(netId)
    if veh == 0 then return end
    if id == 'engine' then
        SetVehicleEngineHealth(veh, 1000.0)
        SetVehiclePetrolTankHealth(veh, 1000.0)
        SetVehicleUndriveable(veh, false)
    elseif id == 'body' then
        local engine = GetVehicleEngineHealth(veh)
        SetVehicleFixed(veh)
        SetVehicleDeformationFixed(veh)
        SetVehicleEngineHealth(veh, engine) -- bodywork does not repair the engine
        SetVehicleBodyHealth(veh, 1000.0)
    elseif id == 'tyres' then
        for i = 0, 7 do SetVehicleTyreFixed(veh, i) end
    elseif id == 'clean' then
        SetVehicleDirtLevel(veh, 0.0)
        WashDecalsFromVehicle(veh, 1.0)
    end
end)

---------------------------------------------------------------------------
-- Mechanic menu (duty + invoices) at the workshop desk, or /mechanic inside a workshop
---------------------------------------------------------------------------
local function sendInvoice()
    local res = Veyl.Callback('veyl_mechanic', 'nearbyCustomers')
    if not res.ok then return Veyl.NotifyResult(res) end
    if #res.data == 0 then return Veyl.Notify('Nobody is close enough to invoice', 'info') end
    local options = {}
    for i, p in ipairs(res.data) do options[i] = { value = tostring(p.id), label = ('%s (%.1f m)'):format(p.name, p.distance) } end
    local values = vlib.inputDialog('Send invoice', {
        { name = 'customer', label = 'Customer', type = 'select', required = true, options = options, default = options[1].value },
        { name = 'amount', label = 'Amount ($)', type = 'number', required = true, min = 1, max = MechanicConfig.Invoice.Max },
        { name = 'reason', label = 'Work done', type = 'text', required = true, maxLength = 100, placeholder = 'e.g. Engine repair and wash' },
    }, { submitLabel = 'Send invoice' })
    if not values then return end
    Veyl.NotifyResult(Veyl.Callback('veyl_mechanic', 'sendInvoice', tonumber(values.customer), math.floor(tonumber(values.amount) or 0), values.reason))
end

local function openMenu()
    if job().name ~= MechanicConfig.Job then return Veyl.Notify('You do not work here', 'error') end
    local duty = onDuty()
    vlib.registerMenu({
        id = 'veyl_mechanic:menu', title = 'Mechanic', subtitle = duty and 'On duty' or 'Off duty',
        options = {
            { id = 'duty', label = duty and 'Go off duty' or 'Go on duty', icon = 'clock' },
            { id = 'invoice', label = 'Send invoice', description = 'Bill a nearby customer', icon = 'money',
              disabled = not duty, disabledReason = 'Go on duty first' },
            { id = 'parts', label = 'Parts', description = 'Buy engine parts, panels, tyre and cleaning kits at the parts counter', icon = 'box', disabled = true,
              disabledReason = 'Use the parts counter in the workshop' },
        },
    }, function(optionId)
        if optionId == 'duty' then
            CreateThread(function() Veyl.NotifyResult(Veyl.Callback('veyl_mechanic', 'toggleDuty')) end)
        elseif optionId == 'invoice' then
            CreateThread(sendInvoice)
        end
    end)
    vlib.showMenu('veyl_mechanic:menu')
end

RegisterCommand('mechanic', function()
    if not Veyl.IsLoaded() then return end
    if not shopAt(GetEntityCoords(PlayerPedId())) then return Veyl.Notify('Use this inside the workshop', 'info') end
    openMenu()
end, false)

AddEventHandler('veyl_mechanic:menu', function() CreateThread(openMenu) end)

---------------------------------------------------------------------------
-- Customers: invoices
---------------------------------------------------------------------------
RegisterNetEvent('veyl_mechanic:invoiceReceived', function(inv)
    Veyl.Notify(('Invoice #%d from %s: $%d for %s. Type /invoices to pay.'):format(inv.id, inv.from, inv.amount, inv.reason), 'info', 9000)
end)

local function payFlow(inv)
    local values = vlib.inputDialog(('Invoice #%d: $%d'):format(inv.id, inv.amount), {
        { name = 'method', label = 'Pay with', type = 'select', required = true, default = 'bank',
          options = { { value = 'bank', label = 'Bank' }, { value = 'cash', label = 'Cash' } } },
    }, { submitLabel = ('Pay $%d'):format(inv.amount) })
    if not values then return end
    Veyl.NotifyResult(Veyl.Callback('veyl_mechanic', 'payInvoice', inv.id, values.method))
end

RegisterCommand('invoices', function()
    if not Veyl.IsLoaded() then return end
    CreateThread(function()
        local res = Veyl.Callback('veyl_mechanic', 'myInvoices')
        if not res.ok then return Veyl.NotifyResult(res) end
        if #res.data == 0 then return Veyl.Notify('You have no unpaid invoices', 'info') end
        local options = {}
        for i, inv in ipairs(res.data) do
            options[i] = { id = tostring(inv.id), label = ('#%d  %s'):format(inv.id, inv.reason), right = ('$%d'):format(inv.amount),
                description = ('From %s, %s'):format(inv.sender_name, inv.at), args = inv }
        end
        vlib.registerMenu({ id = 'veyl_mechanic:invoices', title = 'Unpaid invoices', options = options }, function(_, inv)
            CreateThread(function()
                vlib.registerMenu({
                    id = 'veyl_mechanic:invoice', title = ('Invoice #%d'):format(inv.id), subtitle = ('$%d · %s'):format(inv.amount, inv.reason),
                    options = { { id = 'pay', label = 'Pay', icon = 'money' }, { id = 'decline', label = 'Decline', icon = 'close' } },
                }, function(choice)
                    CreateThread(function()
                        if choice == 'pay' then payFlow(inv)
                        elseif choice == 'decline' and vlib.alertDialog({ title = 'Decline invoice?', message = ('Decline invoice #%d for $%d?'):format(inv.id, inv.amount),
                            confirmLabel = 'Decline', destructive = true }) == 'confirm' then
                            Veyl.NotifyResult(Veyl.Callback('veyl_mechanic', 'declineInvoice', inv.id))
                        end
                    end)
                end)
                vlib.showMenu('veyl_mechanic:invoice')
            end)
        end)
        vlib.showMenu('veyl_mechanic:invoices')
    end)
end, false)

---------------------------------------------------------------------------
-- Registration: blip, desk zone, vehicle options
---------------------------------------------------------------------------
CreateThread(function()
    for _, s in ipairs(MechanicConfig.Shops) do
        local blip = AddBlipForCoord(s.coords.x, s.coords.y, s.coords.z)
        SetBlipSprite(blip, MechanicConfig.Blip.sprite)
        SetBlipColour(blip, MechanicConfig.Blip.colour)
        SetBlipScale(blip, MechanicConfig.Blip.scale)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(MechanicConfig.Blip.name)
        EndTextCommandSetBlipName(blip)
    end
    while GetResourceState('veyl_interact') ~= 'started' do Wait(200) end
    for _, s in ipairs(MechanicConfig.Shops) do
        exports.veyl_interact:AddZone({
            id = 'mechanic_desk_' .. s.id, coords = s.desk, radius = 1.6, icon = 'wrench', title = s.label,
            label = 'Mechanic menu', event = 'veyl_mechanic:menu', groups = { [MechanicConfig.Job] = 0 },
        })
    end
    while GetResourceState('veyl_target') ~= 'started' do Wait(500) end
    local options = {}
    for i, r in ipairs(MechanicConfig.Repairs) do
        options[i] = {
            name = 'veyl_mechanic_' .. r.id, label = r.label, icon = r.icon, distance = 3.0, priority = 1,
            canInteract = function(entity)
                return onDuty() and shopAt(GetEntityCoords(entity)) ~= nil and needs(entity, r.id) and hasPart(r.item)
            end,
            onSelect = function(data) if data and data.entity then CreateThread(function() doRepair(data.entity, r) end) end end,
        }
    end
    exports.veyl_target:addGlobalVehicle(options)
end)
