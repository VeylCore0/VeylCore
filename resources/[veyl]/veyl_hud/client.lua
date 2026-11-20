-- veyl_hud client: collects display values and sends them to NUI only when they change.

local visible = true
local last = {}

local function changed(data)
    for k, v in pairs(data) do
        if last[k] ~= v then
            last = data
            return true
        end
    end
    for k in pairs(last) do
        if data[k] == nil then last = data return true end
    end
    return false
end

CreateThread(function()
    while true do
        local loaded = Veyl.IsLoaded()
        local show = visible and loaded and not IsPauseMenuActive() and not IsScreenFadedOut()
        local data = { show = show }
        if show then
            local ped = PlayerPedId()
            local pid = PlayerId()
            local needs = LocalPlayer.state.veylNeeds or {}
            local range = math.max(1, GetEntityMaxHealth(ped) - 100)
            data.health = math.max(0, math.min(100, math.floor((GetEntityHealth(ped) - 100) / range * 100)))
            data.armor = GetPedArmour(ped)
            data.hunger = needs.hunger
            data.thirst = needs.thirst
            data.stress = needs.stress
            data.stamina = math.floor(100 - GetPlayerSprintStaminaRemaining(pid))
            if IsPedSwimmingUnderWater(ped) then
                data.oxygen = math.floor(GetPlayerUnderwaterTimeRemaining(pid) * 10)
            end
            data.cash = LocalPlayer.state.veylCash
            data.bank = LocalPlayer.state.veylBank
            local job = LocalPlayer.state.veylJob
            if job then data.job = job.label .. (job.onDuty and '' or ' (off duty)') end

            local veh = GetVehiclePedIsIn(ped, false)
            if veh ~= 0 then
                data.speed = math.floor(GetEntitySpeed(veh) * 2.236936) -- mph
                local fuel = Entity(veh).state.veylFuel
                data.fuel = fuel and math.floor(fuel) or nil
                data.locked = GetVehicleDoorLockStatus(veh) >= 2
            end
        end
        if changed(data) then SendNUIMessage({ action = 'update', data = data }) end
        Wait(show and 200 or 500)
    end
end)

RegisterCommand('hud', function()
    visible = not visible
    Veyl.Notify(visible and 'HUD shown' or 'HUD hidden', 'info', 2000)
end, false)

-- Hide the default GTA cash/ammo HUD components we replace.
CreateThread(function()
    while true do
        if Veyl.IsLoaded() then
            HideHudComponentThisFrame(3)  -- cash
            HideHudComponentThisFrame(4)  -- MP cash
            HideHudComponentThisFrame(13) -- cash change
            Wait(0)
        else
            Wait(500)
        end
    end
end)
