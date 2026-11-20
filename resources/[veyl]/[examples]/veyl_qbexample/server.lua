-- Written exactly like a QBCore resource. Demonstrates that the QB facade and native VeylCore exports
-- observe the same player and the same committed balances.

local QBCore = exports['qb-core']:GetCoreObject()
local Lang = Locale:new({ phrases = { greet = 'Hello %{name}, you work as %{job}.' }, warnOnMissing = true })

-- Boot self-check (visible in the server console).
CreateThread(function()
    local jobs = 0
    for _ in pairs(QBCore.Shared.Jobs) do jobs = jobs + 1 end
    assert(QBCore.Shared.Jobs.unemployed.grades['0'], 'QB job grade format mismatch')
    print(('^2[veyl_qbexample] QB facade OK: %d jobs, %d online players, Commands.Add=%s^7')
        :format(jobs, #QBCore.Functions.GetPlayers(), type(QBCore.Commands.Add)))
end)

QBCore.Functions.CreateCallback('veyl_qbexample:server:getSummary', function(source, cb)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return cb(nil) end
    cb({
        citizenid = Player.PlayerData.citizenid,
        job = Player.PlayerData.job.label,
        grade = Player.PlayerData.job.grade.name,
        cash = Player.Functions.GetMoney('cash'),
    })
end)

QBCore.Commands.Add('qbexample', 'Run the QB compatibility example', {}, false, function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    local pd = Player.PlayerData
    local before = exports.veyl_core:GetMoney(source, 'cash')            -- native API
    local ok = Player.Functions.AddMoney('cash', 1, 'qbexample test')      -- QB API
    local after = exports.veyl_core:GetMoney(source, 'cash')
    local name = pd.charinfo.firstname .. ' ' .. pd.charinfo.lastname
    TriggerClientEvent('QBCore:Notify', source, Lang:t('greet', { name = name, job = pd.job.label }), 'primary')
    print(('[veyl_qbexample] %s (%s) AddMoney=%s cash %d -> %d (native view)'):format(name, pd.citizenid, tostring(ok), before, after))
end)

QBCore.Functions.CreateUseableItem('qbexample_token', function(source, item)
    TriggerClientEvent('QBCore:Notify', source, 'You used a QB-registered item: ' .. tostring(item and item.name), 'success')
end)

AddEventHandler('QBCore:Server:OnJobUpdate', function(source, job)
    print(('[veyl_qbexample] job update for %s -> %s'):format(source, job.name))
end)
