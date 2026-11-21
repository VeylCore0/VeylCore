-- VeylCore framework adapter: character lifecycle -> inventory lifecycle. Also registers the default stashes
-- and the startup sequence (migrations before any request is served).

Ready = false

AddEventHandler('VeylCore:Server:PlayerLoaded', function(src, citizenid)
    CreateThread(function()
        while not Ready do Wait(100) end
        local pd = exports.veyl_core:GetPlayerData(src)
        if not pd or pd.citizenid ~= citizenid then return end
        Inventory_OnCharacterLoaded(src, citizenid, exports.veyl_core:GetSessionGeneration(src),
            ('%s %s'):format(pd.charinfo.firstname or '', pd.charinfo.lastname or ''))
    end)
end)

AddEventHandler('VeylCore:Server:OnPlayerUnload', function(src)
    Inventory_OnCharacterUnloaded(src)
end)

CreateThread(function()
    local okDb = pcall(MySQL.ready.await)
    if not okDb then return print('^1[veyl_inventory] NOT READY: database unavailable^7') end
    local okMig, e = pcall(DB.Migrate)
    if not okMig then return print(('^1[veyl_inventory] NOT READY: migration failed: %s^7'):format(tostring(e))) end
    for _, s in ipairs(InventoryConfig.Stashes) do Stashes.Register(s, GetCurrentResourceName()) end
    pcall(Drops.ClearAll)
    Ready = true
    GlobalState['veyl:ready:veyl_inventory'] = true
    print(('^5[veyl_inventory] ready (%d item definitions)^7'):format(vlib.table.count(ItemDefs)))
    -- Resource restart while characters are online.
    for _, pd in ipairs(exports.veyl_core:GetPlayersData()) do
        Inventory_OnCharacterLoaded(pd.source, pd.citizenid, exports.veyl_core:GetSessionGeneration(pd.source),
            ('%s %s'):format(pd.charinfo.firstname or '', pd.charinfo.lastname or ''))
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then GlobalState['veyl:ready:veyl_inventory'] = false end
end)
