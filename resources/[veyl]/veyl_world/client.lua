-- veyl_world client: applies replicated time/weather and population settings.

local currentWeather = nil

local function applyWeather(w, instant)
    if w == currentWeather then return end
    currentWeather = w
    ClearOverrideWeather()
    ClearWeatherTypePersist()
    if instant then
        SetWeatherTypeNow(w)
        SetWeatherTypePersist(w)
        SetWeatherTypeNowPersist(w)
    else
        SetWeatherTypeOvertimePersist(w, 30.0)
    end
    SetForceVehicleTrails(w == 'XMAS' or w == 'SNOW' or w == 'BLIZZARD')
    SetForcePedFootstepsTracks(w == 'XMAS' or w == 'SNOW' or w == 'BLIZZARD')
end

CreateThread(function()
    local first = true
    while true do
        local s = GlobalState.veylWorld
        if s then
            NetworkOverrideClockTime(s.hour, s.minute, 0)
            applyWeather(s.weather, first)
            first = false
        end
        Wait(1000)
    end
end)

CreateThread(function()
    if WorldConfig.DisableDispatch then
        for i = 1, 15 do EnableDispatchService(i, false) end
    end
    while true do
        SetPedDensityMultiplierThisFrame(WorldConfig.PedDensity)
        SetScenarioPedDensityMultiplierThisFrame(WorldConfig.PedDensity, WorldConfig.PedDensity)
        SetVehicleDensityMultiplierThisFrame(WorldConfig.VehicleDensity)
        SetRandomVehicleDensityMultiplierThisFrame(WorldConfig.VehicleDensity)
        SetParkedVehicleDensityMultiplierThisFrame(WorldConfig.ParkedVehicleDensity)
        if WorldConfig.DisableWantedLevel and GetPlayerWantedLevel(PlayerId()) > 0 then
            ClearPlayerWantedLevel(PlayerId())
        end
        Wait(0)
    end
end)
