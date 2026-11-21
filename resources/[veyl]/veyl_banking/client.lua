-- veyl_banking client: bank screen and cash commands. Every action is validated by the server.

local screen = vlib.createScreen({ name = 'bank' })

local function money(n) return ('$%s'):format(tostring(math.floor(n or 0)):reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')) end

local function openBank()
    if screen:isOpen() or not Veyl.IsLoaded() then return end
    local res = Veyl.Callback('veyl_banking', 'overview')
    if not res.ok then return Veyl.NotifyResult(res) end
    local ok, reason = screen:open('bank:open', res.data)
    if not ok then Veyl.Notify(reason == 'busy' and 'Close the open menu first.' or 'Banking UI unavailable.', 'warning') end
end

local function reply(cb, res) cb({ ok = res.ok, code = res.code, message = res.message, data = res.data }) end

--- Money actions: on a transport timeout, ask whether the operation was applied before reporting failure.
local function moneyAction(name, opId, ...)
    local res = Veyl.CallbackTimeout('veyl_banking', name, 15000, ...)
    if res.code == 'TIMEOUT' then
        local status = Veyl.CallbackTimeout('veyl_banking', 'status', 8000, opId)
        if status.ok then
            local ov = Veyl.Callback('veyl_banking', 'overview')
            return { ok = true, message = 'Done', data = ov.ok and ov.data or nil }
        end
    end
    return res
end

RegisterNUICallback('overview', function(_, cb) reply(cb, Veyl.Callback('veyl_banking', 'overview')) end)

RegisterNUICallback('history', function(data, cb)
    reply(cb, Veyl.Callback('veyl_banking', 'history', math.floor(tonumber(data and data.offset) or 0), tostring(data and data.filter or 'all')))
end)

RegisterNUICallback('deposit', function(data, cb)
    if type(data) ~= 'table' then return cb({ ok = false, code = 'INVALID_INPUT' }) end
    local opId = tostring(data.opId or '')
    reply(cb, moneyAction('deposit', opId, math.floor(tonumber(data.amount) or 0), opId))
end)

RegisterNUICallback('withdraw', function(data, cb)
    if type(data) ~= 'table' then return cb({ ok = false, code = 'INVALID_INPUT' }) end
    local opId = tostring(data.opId or '')
    reply(cb, moneyAction('withdraw', opId, math.floor(tonumber(data.amount) or 0), opId))
end)

RegisterNUICallback('resolveRecipient', function(data, cb)
    reply(cb, Veyl.Callback('veyl_banking', 'resolveRecipient', tostring(data and data.account or '')))
end)

RegisterNUICallback('transfer', function(data, cb)
    if type(data) ~= 'table' then return cb({ ok = false, code = 'INVALID_INPUT' }) end
    local opId = tostring(data.opId or '')
    reply(cb, moneyAction('transfer', opId, tostring(data.token or ''), math.floor(tonumber(data.amount) or 0), tostring(data.reference or ''), opId))
end)

AddEventHandler('veyl_banking:open', function() CreateThread(openBank) end)

CreateThread(function()
    while GetResourceState('veyl_interact') ~= 'started' do Wait(200) end
    for i, coords in ipairs(BankingConfig.Banks) do
        exports.veyl_interact:AddZone({
            id = 'bank_' .. i, coords = coords, radius = BankingConfig.BankUseDistance, icon = 'bank', title = 'Bank',
            label = 'Use bank', event = 'veyl_banking:open',
        })
        local blip = AddBlipForCoord(coords.x, coords.y, coords.z)
        SetBlipSprite(blip, 108)
        SetBlipColour(blip, 27)
        SetBlipScale(blip, 0.7)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName('Bank')
        EndTextCommandSetBlipName(blip)
    end
end)

RegisterCommand('givecash', function(_, args)
    local target, amount = tonumber(args[1]), tonumber(args[2])
    if not target or not amount then return Veyl.Notify('Usage: /givecash [id] [amount]', 'error') end
    Veyl.NotifyResult(Veyl.Callback('veyl_banking', 'giveCash', math.floor(target), math.floor(amount)))
end, false)

RegisterCommand('cash', function()
    local pd = Veyl.PlayerData or {}
    local m = pd.money or {}
    Veyl.Notify(('Cash %s · Bank %s'):format(money(m.cash), money(m.bank)), 'info')
end, false)
