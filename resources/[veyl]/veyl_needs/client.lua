-- veyl_needs client: effects of empty needs and high stress (display is veyl_hud's job).

CreateThread(function()
    while true do
        Wait(10000)
        local needs = LocalPlayer.state.veylNeeds
        if needs and Veyl.IsLoaded() then
            local ped = PlayerPedId()
            if (needs.hunger <= 0 or needs.thirst <= 0) and not IsEntityDead(ped) then
                SetEntityHealth(ped, math.max(0, GetEntityHealth(ped) - NeedsConfig.StarvingDamage))
                Veyl.Notify(needs.hunger <= 0 and 'You are starving.' or 'You are dehydrated.', 'warning', 3000)
            end
            if needs.stress >= 80 then
                ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', 0.04)
            end
        end
    end
end)
