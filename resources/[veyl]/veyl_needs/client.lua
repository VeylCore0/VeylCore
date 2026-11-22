-- veyl_needs client: effects of empty needs and high stress (display is veyl_hud's job).

CreateThread(function()
    while true do
        Wait(10000)
        local m = Veyl.IsLoaded() and (exports.veyl_core:GetPlayerData().metadata) or nil
        if m then
            local ped = PlayerPedId()
            if ((m.hunger or 100) <= 0 or (m.thirst or 100) <= 0) and not IsEntityDead(ped) then
                SetEntityHealth(ped, math.max(0, GetEntityHealth(ped) - NeedsConfig.StarvingDamage))
                Veyl.Notify((m.hunger or 100) <= 0 and 'You are starving.' or 'You are dehydrated.', 'warning', 3000)
            end

        end
    end
end)
