-- veyl_boosting configuration: car theft contracts with classes, reputation, trackers and drop-offs.

BoostingConfig = {
    ContractCooldownMinutes = 15,
    TimeLimitMinutes = 30,
    MinPolice = { D = 0, C = 1, B = 2, A = 2, S = 3 },
    HotwireSeconds = 15, HotwireItem = 'lockpick',
    LockpickSeconds = 4, LockpickDifficulty = 'medium', LockpickBreakChance = 0.35, -- door: mini game, then this many seconds
    TrackerItem = 'hacking_device', TrackerSeconds = 20, TrackerPingSeconds = 20,

    -- Reputation needed for each class, and what a delivery pays (cash) and earns (rep).
    Classes = {
        { id = 'D', rep = 0,   pay = { 800, 1500 },   gain = 5,  tracker = false, models = { 'blista', 'panto', 'issi2', 'asea', 'prairie' } },
        { id = 'C', rep = 40,  pay = { 1500, 3000 },  gain = 8,  tracker = false, models = { 'sultan', 'buffalo', 'felon', 'oracle', 'fugitive' } },
        { id = 'B', rep = 120, pay = { 3000, 6000 },  gain = 12, tracker = true,  models = { 'comet2', 'schafter3', 'banshee', 'feltzer2', 'carbonizzare' } },
        { id = 'A', rep = 300, pay = { 6000, 11000 }, gain = 18, tracker = true,  models = { 'jester', 'elegy2', 'massacro', 'specter', 'neon' } },
        { id = 'S', rep = 600, pay = { 12000, 20000 }, gain = 25, tracker = true, models = { 'zentorno', 't20', 'adder', 'osiris', 'turismor' } },
    },

    -- Where contract cars are parked (heading included) and where they are delivered.
    Spawns = {
        vector4(-1072.3, -1659.4, 4.39, 307.0), vector4(-341.2, -767.0, 33.97, 270.0), vector4(212.4, -808.8, 30.73, 157.0),
        vector4(1147.6, -470.3, 66.37, 76.0), vector4(-1530.3, -326.9, 47.07, 45.0), vector4(-664.6, -1206.4, 10.65, 34.0),
        vector4(1366.8, 3600.8, 34.89, 199.0), vector4(-2028.4, -467.6, 11.42, 140.0),
    },
    Dropoffs = { vector3(1205.6, -3117.9, 5.54), vector3(-1158.8, -2024.4, 13.16), vector3(2667.4, 1436.9, 24.5), vector3(-431.5, -2176.6, 10.32) },
    DropRadius = 8.0,
}
