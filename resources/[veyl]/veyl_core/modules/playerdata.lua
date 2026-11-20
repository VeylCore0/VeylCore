-- Optional import for client scripts:  client_script '@veyl_core/modules/playerdata.lua'
-- Keeps Veyl.PlayerData current (late-starting resources read the cache instead of waiting for events).
Veyl = Veyl or {}
Veyl.PlayerData = exports.veyl_core:GetPlayerData() or {}

RegisterNetEvent('VeylCore:Player:SetPlayerData', function(data)
    Veyl.PlayerData = type(data) == 'table' and data or {}
end)

RegisterNetEvent('VeylCore:Client:OnPlayerUnload', function()
    Veyl.PlayerData = {}
end)
