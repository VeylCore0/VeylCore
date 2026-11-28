-- The fictional hazard, as the player sees it: the server works out the exposure and sends the number; this shows a meter on the page and
-- a screen tint that grows with it. Nothing here decides damage.

local H = ProductionConfig.Supplier and ProductionConfig.Supplier.Hazard
local tinted = false
local exposure = 0

-- Breathing fumes saps your stamina: no sprinting or jumping while the exposure is high, and you tire faster before that.
CreateThread(function()
    while true do
        if H and H.StaminaAt and exposure >= H.StaminaAt then
            Wait(0)
            DisableControlAction(0, 21, true)
            DisableControlAction(0, 22, true)
            if exposure >= H.WarnAt and math.random() < 0.01 then RestorePlayerStamina(PlayerId(), -0.2) end
        else
            Wait(500)
        end
    end
end)

RegisterNetEvent('veyl_production:hazard', function(level)
    level = tonumber(level) or 0
    exposure = level
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
