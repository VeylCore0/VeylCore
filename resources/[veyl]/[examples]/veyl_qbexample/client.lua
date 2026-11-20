local QBCore = exports['qb-core']:GetCoreObject()

RegisterNetEvent('QBCore:Client:OnPlayerLoaded', function()
    local pd = QBCore.Functions.GetPlayerData()
    QBCore.Functions.Notify(('[QB example] Loaded %s'):format(pd.citizenid or '?'), 'success')
end)

RegisterCommand('qbexample_cb', function()
    QBCore.Functions.TriggerCallback('veyl_qbexample:server:getSummary', function(summary)
        if not summary then return QBCore.Functions.Notify('No character loaded', 'error') end
        QBCore.Functions.Notify(('%s | %s (%s) | cash $%d'):format(summary.citizenid, summary.job, summary.grade, summary.cash), 'primary', 8000)
    end)
end, false)
