-- qb-core shim (client): object entry point + local QBCore-namespace notifications.
-- Uses local TriggerEvent so handlers registered with RegisterNetEvent in QB resources receive them once.

exports('GetCoreObject', function(filter) return exports.veyl_core:GetCoreObject(filter) end)

RegisterNetEvent('VeylCore:Player:SetPlayerData', function(data)
    TriggerEvent('QBCore:Player:SetPlayerData', data)
end)

RegisterNetEvent('VeylCore:Client:OnPlayerLoaded', function()
    TriggerEvent('QBCore:Client:OnPlayerLoaded')
end)

RegisterNetEvent('VeylCore:Client:OnPlayerUnload', function()
    TriggerEvent('QBCore:Client:OnPlayerUnload')
end)

RegisterNetEvent('VeylCore:Client:OnJobUpdate', function(job)
    TriggerEvent('QBCore:Client:OnJobUpdate', job)
end)

RegisterNetEvent('VeylCore:Client:OnGangUpdate', function(gang)
    TriggerEvent('QBCore:Client:OnGangUpdate', gang)
end)

RegisterNetEvent('VeylCore:Client:SetDuty', function(onDuty)
    TriggerEvent('QBCore:Client:SetDuty', onDuty)
end)

RegisterNetEvent('VeylCore:Client:OnMoneyChange', function(moneyType, amount, action, reason)
    TriggerEvent('QBCore:Client:OnMoneyChange', moneyType, amount, action, reason)
end)

-- QB's notify event, used directly by some resources.
RegisterNetEvent('QBCore:Notify', function(text, kind, length)
    if type(text) == 'table' then text = text.text or text.caption or '' end
    if kind == 'primary' then kind = 'info' end
    TriggerEvent('veyl_ui:notify', { message = tostring(text), type = kind or 'info', duration = length })
end)
