-- ox_inventory framework bridge for VeylCore (client). Install to ox_inventory/modules/bridge/veyl/

RegisterNetEvent('VeylCore:Client:OnPlayerUnload', function()
    client.onLogout()
end)

RegisterNetEvent('VeylCore:Client:OnGroupUpdate', function(groupName, groupGrade)
    local groups = PlayerData.groups or {}
    groups[groupName] = groupGrade or nil
    client.setPlayerData('groups', groups)
end)

-- Consumable status effects are applied server-side by veyl_needs (from the 'ox_inventory:usedItem'
-- event), so client-reported status values are intentionally ignored.
---@diagnostic disable-next-line: duplicate-set-field
function client.setPlayerStatus(_) end
