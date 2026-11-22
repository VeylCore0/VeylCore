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

-- Local preview override (e.g. veyl_customs lighting modes): only this client's screen, never the server's time/weather.
local preview = nil
exports('SetLocalPreview', function(p)
    if type(p) == 'table' and tonumber(p.hour) and type(p.weather) == 'string' then
        preview = { hour = math.floor(tonumber(p.hour)) % 24, minute = math.floor(tonumber(p.minute) or 0) % 60, weather = p.weather }
    else
        preview = nil
        currentWeather = nil -- force the real weather back on the next tick
    end
end)
exports('HasLocalPreview', function() return preview ~= nil end)

CreateThread(function()
    local first = true
    while true do
        local s = preview or GlobalState.veylWorld
        if s then
            NetworkOverrideClockTime(s.hour, s.minute, 0)
            applyWeather(s.weather, first or preview ~= nil)
            first = false
        end
        Wait(preview and 250 or 1000)
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
