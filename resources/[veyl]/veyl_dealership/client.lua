-- veyl_dealership client: salesperson, blip and the catalog screen. Prices shown are a preview; the server charges.

local screen = vlib.createScreen({ name = 'dealer' })

local function openDealer()
    if screen:isOpen() or not Veyl.IsLoaded() then return end
    local res = Veyl.Callback('veyl_dealership', 'catalog')
    if not res.ok then return Veyl.NotifyResult(res) end
    local ok, reason = screen:open('dealer:open', res.data)
    if not ok then Veyl.Notify(reason == 'busy' and 'Close the open menu first.' or 'Dealership UI unavailable.', 'warning') end
end

RegisterNUICallback('purchase', function(data, cb)
    if not screen:isOpen() or type(data) ~= 'table' then return cb({ ok = false, code = 'INVALID_INPUT' }) end
    local d = DealershipConfig.Delivery
    local clear = not IsPositionOccupied(d.x, d.y, d.z, 3.0, false, true, true, false, false, 0, false)
    local res = Veyl.CallbackTimeout('veyl_dealership', 'purchase', 30000, {
        model = tostring(data.model or ''), method = data.method == 'bank' and 'bank' or 'cash',
        opId = tostring(data.opId or ''), expectedPrice = tonumber(data.expectedPrice), deliver = clear,
    })
    cb({ ok = res.ok, code = res.code, message = res.message, data = res.data })
    if res.ok then
        screen:close('purchased')
        Veyl.Notify(res.message, 'success', 7000)
        if res.data and res.data.delivered then SetNewWaypoint(d.x, d.y) end
    end
end)

AddEventHandler('veyl_dealership:open', function() CreateThread(openDealer) end)

CreateThread(function()
    local s = DealershipConfig.Salesperson.coords
    local blip = AddBlipForCoord(s.x, s.y, s.z)
    SetBlipSprite(blip, DealershipConfig.Blip.sprite)
    SetBlipColour(blip, DealershipConfig.Blip.colour)
    SetBlipScale(blip, DealershipConfig.Blip.scale)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Vehicle Dealership')
    EndTextCommandSetBlipName(blip)
    while GetResourceState('veyl_interact') ~= 'started' do Wait(200) end
    exports.veyl_interact:AddPed({
        id = 'dealer_pdm', model = DealershipConfig.Salesperson.model, coords = s, radius = DealershipConfig.UseRadius,
        icon = 'car', title = DealershipConfig.Label, label = 'Browse vehicles', event = 'veyl_dealership:open',
    })
end)
