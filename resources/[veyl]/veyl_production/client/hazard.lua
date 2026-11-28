-- The fictional hazard, as the player sees it: the server works out the exposure and sends the number; this shows a meter on the page and
-- a screen tint that grows with it. Nothing here decides damage.

local H = ProductionConfig.Supplier and ProductionConfig.Supplier.Hazard
local tinted = false

RegisterNetEvent('veyl_production:hazard', function(level)
    level = tonumber(level) or 0
    SendNUIMessage({ action = 'production:hazard', data = { level = level, warn = H and H.WarnAt or 40 } })
    if H and level >= H.WarnAt then
        if not tinted then SetTimecycleModifier('spectator5') tinted = true end
        SetTimecycleModifierStrength(math.min(1.0, level / 100.0))
    elseif tinted then
        ClearTimecycleModifier()
        tinted = false
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and tinted then ClearTimecycleModifier() end
end)
