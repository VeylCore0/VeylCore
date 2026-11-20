-- qb-core shim (server): object entry points + QBCore-namespace notifications translated from VeylCore events.
-- Each VeylCore transition produces exactly one QBCore notification; nothing is forwarded back.

exports('GetCoreObject', function(filter) return exports.veyl_core:GetCoreObject(filter) end)

-- A few direct exports some QB resources call.
exports('GetPlayer', function(src)
    return exports.veyl_core:GetCoreObject({ 'Functions' }).Functions.GetPlayer(src)
end)
exports('GetPlayerByCitizenId', function(citizenid)
    return exports.veyl_core:GetCoreObject({ 'Functions' }).Functions.GetPlayerByCitizenId(citizenid)
end)
exports('GetSharedJobs', function() return exports.veyl_core:GetJobs() end)
exports('GetSharedGangs', function() return exports.veyl_core:GetGangs() end)
exports('GetSharedVehicles', function() return exports.veyl_core:GetVehicles() end)

AddEventHandler('VeylCore:Server:PlayerLoaded', function(src)
    TriggerEvent('QBCore:Server:PlayerLoaded', exports.veyl_core:GetPlayer(src))
end)

AddEventHandler('VeylCore:Server:OnPlayerUnload', function(src)
    TriggerEvent('QBCore:Server:OnPlayerUnload', src)
end)

AddEventHandler('VeylCore:Server:OnMoneyChange', function(src, _, moneyType, amount, action, reason)
    TriggerEvent('QBCore:Server:OnMoneyChange', src, moneyType, amount, action, reason)
end)

AddEventHandler('VeylCore:Server:OnJobUpdate', function(src, job)
    TriggerEvent('QBCore:Server:OnJobUpdate', src, job)
end)

AddEventHandler('VeylCore:Server:OnGangUpdate', function(src, gang)
    TriggerEvent('QBCore:Server:OnGangUpdate', src, gang)
end)

AddEventHandler('VeylCore:Server:SetDuty', function(src, onDuty)
    TriggerEvent('QBCore:Server:SetDuty', src, onDuty)
end)

-- Legacy duty toggle sent by many QB job resources (validated: only changes the caller's own duty).
RegisterNetEvent('QBCore:ToggleDuty', function()
    local src = source
    local pd = exports.veyl_core:GetPlayerData(src)
    if pd then exports.veyl_core:SetJobDuty(src, not pd.job.onduty) end
end)

print('^5[qb-core] VeylCore compatibility shim active (subset; see docs/COMPATIBILITY.md)^7')
