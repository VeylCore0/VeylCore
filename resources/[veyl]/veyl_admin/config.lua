-- veyl_admin menu settings. Who may use the menu: anyone with the `veyl.admin` permission (add_ace group.admin veyl.admin allow).
-- A few actions can be limited further to `veyl.admin.super` (add_ace group.owner veyl.admin.super allow): acting on other admins.

AdminConfig = {
    Command = 'admin',
    Key = '',                    -- default key to open the menu (blank = none; players can bind one in settings). e.g. 'F10'

    -- Weather the menu offers (the world resource must allow them).
    Weather = { 'EXTRASUNNY', 'CLEAR', 'CLOUDS', 'OVERCAST', 'CLEARING', 'SMOG', 'FOGGY', 'RAIN', 'THUNDER', 'SNOW', 'BLIZZARD', 'XMAS' },

    -- Resource start / stop / restart from the Server tab. true: every admin may; false: only veyl.admin.super.
    AnyAdminMayRestart = true,
    ShowAllResources = false,    -- false lists only veyl_* resources
    -- Resources that can never be stopped or restarted from the menu (starting is fine).
    ProtectedResources = { veyl_core = true, veyl_lib = true, veyl_admin = true, oxmysql = true, veyl_ui = true },

    -- Noclip speeds (multiplier steps) and the vehicles quick list in the Vehicles tab.
    NoclipSpeeds = { 0.25, 0.5, 1.0, 2.0, 4.0, 8.0 },
    QuickVehicles = { 'adder', 'zentorno', 'sultan', 'kuruma', 'buzzard2', 'frogger', 'dinghy', 'bmx', 'faggio', 'sanchez', 'police', 'ambulance' },
}

AdminConfig.WeatherSet = {}
for _, w in ipairs(AdminConfig.Weather) do AdminConfig.WeatherSet[w] = true end
