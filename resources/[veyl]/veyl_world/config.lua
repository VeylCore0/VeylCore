WorldConfig = {
    StartHour = 9,
    SecondsPerGameMinute = 2,           -- 48 real minutes per in-game day
    WeatherChangeMinutes = 30,          -- real minutes between weather changes
    WeatherCycle = { 'EXTRASUNNY', 'CLEAR', 'CLOUDS', 'CLEAR', 'OVERCAST', 'CLEARING', 'CLEAR', 'SMOG', 'RAIN', 'CLEARING' },
    AllowedWeather = {
        EXTRASUNNY = true, CLEAR = true, CLOUDS = true, OVERCAST = true, CLEARING = true, SMOG = true, FOGGY = true,
        RAIN = true, THUNDER = true, NEUTRAL = true, SNOW = true, SNOWLIGHT = true, BLIZZARD = true, XMAS = true, HALLOWEEN = true,
    },

    -- Ambient population multipliers (0.0 - 1.0)
    PedDensity = 0.8,
    VehicleDensity = 0.7,
    ParkedVehicleDensity = 0.8,
    DisableDispatch = true,   -- no ambient police/EMS/fire NPC responses
    DisableWantedLevel = true,
}
