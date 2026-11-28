-- Places. All coordinates are in-game world positions.

BoostingConfig = BoostingConfig or {}

-- The underground contact: a ped that opens the tablet. Add more entries for more contacts.
BoostingConfig.Contacts = {
    { id = 'ghost', label = 'Ghost', model = 's_m_y_dealer_01', coords = vector4(481.3, -1313.9, 29.2, 270.0), scenario = 'WORLD_HUMAN_SMOKING', radius = 2.2 },
}

-- Where contract vehicles can be parked (heading included). The contract only shows a search area, not the exact spot.
BoostingConfig.Spawns = {
    vector4(-1072.3, -1659.4, 4.39, 307.0), vector4(-341.2, -767.0, 33.97, 270.0), vector4(212.4, -808.8, 30.73, 157.0),
    vector4(1147.6, -470.3, 66.37, 76.0), vector4(-1530.3, -326.9, 47.07, 45.0), vector4(-664.6, -1206.4, 10.65, 34.0),
    vector4(1366.8, 3600.8, 34.89, 199.0), vector4(-2028.4, -467.6, 11.42, 140.0),
}

-- Handoff points. `label` is shown to the player.
BoostingConfig.Dropoffs = {
    { label = 'Elysian Island docks',  coords = vector3(1205.6, -3117.9, 5.54) },
    { label = 'La Puerta warehouse',   coords = vector3(-1158.8, -2024.4, 13.16) },
    { label = 'Harmony yard',          coords = vector3(2667.4, 1436.9, 24.5) },
    { label = 'Port of Los Santos',    coords = vector3(-431.5, -2176.6, 10.32) },
    { label = 'East Los Santos lot',   coords = vector3(1017.8, -2528.4, 28.3) },
}
