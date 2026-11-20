-- Local PlayerData cache (allowlisted view sent by the server). Never used to authorize anything.
PlayerData = {}

RegisterNetEvent('VeylCore:Player:SetPlayerData', function(data)
    PlayerData = type(data) == 'table' and data or {}
end)

RegisterNetEvent('VeylCore:Client:OnPlayerUnload', function()
    PlayerData = {}
end)
