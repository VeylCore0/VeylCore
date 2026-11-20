-- veyl_banking client: bank counters and cash commands.

local function money(n) return ('$%s'):format(tostring(n or 0):reverse():gsub('(%d%d%d)', '%1,'):reverse():gsub('^,', '')) end

local function askAmount(title)
    local values = Veyl.UI.Input({
        title = title,
        fields = { { name = 'amount', label = 'Amount ($)', type = 'number', min = 1, max = BankingConfig.MaxSingleTransaction, required = true } },
    })
    return values and tonumber(values.amount) or nil
end

local function openBank()
    while true do
        local res = Veyl.Callback('veyl_banking', 'overview')
        if not res.ok then return Veyl.NotifyResult(res) end
        local d = res.data
        local items = {
            { label = 'Deposit cash', value = 'deposit', right = money(d.cash) },
            { label = 'Withdraw cash', value = 'withdraw', right = money(d.bank) },
            { label = 'Transfer to player', description = 'Send money to another online player by server ID', value = 'transfer' },
            { label = 'Recent transactions', value = 'history' },
        }
        local choice = Veyl.UI.Menu({ title = 'Fleeca Bank', subtitle = ('Bank %s  ·  Cash %s'):format(money(d.bank), money(d.cash)), items = items })
        if not choice then return end

        if choice == 'deposit' or choice == 'withdraw' then
            local amount = askAmount(choice == 'deposit' and 'Deposit cash' or 'Withdraw cash')
            if amount then Veyl.NotifyResult(Veyl.Callback('veyl_banking', choice, math.floor(amount))) end
        elseif choice == 'transfer' then
            local v = Veyl.UI.Input({
                title = 'Bank transfer',
                fields = {
                    { name = 'target', label = 'Player server ID', type = 'number', min = 1, required = true },
                    { name = 'amount', label = 'Amount ($)', type = 'number', min = 1, max = BankingConfig.MaxSingleTransaction, required = true },
                },
            })
            if v then
                local ok = Veyl.UI.Confirm({ title = 'Confirm transfer', message = ('Send %s to player %d?'):format(money(v.amount), v.target) })
                if ok then Veyl.NotifyResult(Veyl.Callback('veyl_banking', 'transfer', math.floor(v.target), math.floor(v.amount))) end
            end
        elseif choice == 'history' then
            local rows = {}
            for _, h in ipairs(d.history or {}) do
                rows[#rows + 1] = {
                    label = h.reason, description = ('%s · %s · balance %s'):format(h.at, h.type, money(h.balance_after)),
                    right = (h.delta >= 0 and '+' or '-') .. money(math.abs(h.delta)), value = 'noop',
                }
            end
            Veyl.UI.Menu({ title = 'Recent transactions', items = rows, emptyText = 'No transactions yet.' })
        end
    end
end

CreateThread(function()
    while GetResourceState('veyl_interact') ~= 'started' do Wait(200) end
    for i, coords in ipairs(BankingConfig.Banks) do
        exports.veyl_interact:AddZone({
            id = 'bank_' .. i, coords = coords, radius = BankingConfig.BankUseDistance,
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

AddEventHandler('veyl_banking:open', function()
    if Veyl.IsLoaded() then openBank() end
end)

RegisterCommand('givecash', function(_, args)
    local target, amount = tonumber(args[1]), tonumber(args[2])
    if not target or not amount then return Veyl.Notify('Usage: /givecash [id] [amount]', 'error') end
    Veyl.NotifyResult(Veyl.Callback('veyl_banking', 'giveCash', math.floor(target), math.floor(amount)))
end, false)

RegisterCommand('cash', function()
    Veyl.Notify(('Cash %s · Bank %s'):format(money(Veyl.PlayerData.money and Veyl.PlayerData.money.cash), money(Veyl.PlayerData.money and Veyl.PlayerData.money.bank)), 'info')
end, false)
