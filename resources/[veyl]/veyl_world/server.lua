-- veyl_world server: single authority for time and weather, replicated through GlobalState.

local state = { hour = WorldConfig.StartHour, minute = 0, weather = WorldConfig.WeatherCycle[1], frozen = false }
local weatherIndex = 1

local function publish() GlobalState.veylWorld = { hour = state.hour, minute = state.minute, weather = state.weather, frozen = state.frozen } end

Veyl.Startup({}, function() publish() return true end)

CreateThread(function()
    while true do
        Wait(WorldConfig.SecondsPerGameMinute * 1000)
        if not state.frozen then
            state.minute = state.minute + 1
            if state.minute >= 60 then
                state.minute = 0
                state.hour = (state.hour + 1) % 24
            end
            publish()
        end
    end
end)

CreateThread(function()
    while true do
        Wait(WorldConfig.WeatherChangeMinutes * 60000)
        if not state.frozen then
            weatherIndex = weatherIndex % #WorldConfig.WeatherCycle + 1
            state.weather = WorldConfig.WeatherCycle[weatherIndex]
            publish()
        end
    end
end)

local function staff(src)
    if Veyl.HasPermission(src, 'admin') then return true end
    Veyl.Notify(src, 'You do not have permission to use this command.', 'error')
    return false
end

RegisterCommand('vtime', function(src, args)
    if not staff(src) then return end
    local h, m = tonumber(args[1]), tonumber(args[2]) or 0
    if not h or h < 0 or h > 23 or m < 0 or m > 59 then return Veyl.Notify(src, 'Usage: /vtime [hour] [minute]', 'error') end
    state.hour, state.minute = math.floor(h), math.floor(m)
    publish()
    Veyl.Audit(src, 'world_time', { hour = state.hour, minute = state.minute })
end, false)

RegisterCommand('vweather', function(src, args)
    if not staff(src) then return end
    local w = args[1] and args[1]:upper()
    if not w or not WorldConfig.AllowedWeather[w] then return Veyl.Notify(src, 'Unknown weather type', 'error') end
    state.weather = w
    publish()
    Veyl.Audit(src, 'world_weather', { weather = w })
end, false)

RegisterCommand('vfreezetime', function(src)
    if not staff(src) then return end
    state.frozen = not state.frozen
    publish()
    Veyl.Notify(src, state.frozen and 'Time and weather frozen' or 'Time and weather resumed', 'info')
end, false)
