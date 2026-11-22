-- veyl_robbery configuration: 24/7 store robberies. Money in whole dollars, times in seconds.

RobberyConfig = {
    PoliceJobs = { 'police' },
    MinPolice = 2,                 -- on-duty officers needed before a store can be robbed
    StoreCooldownMinutes = 30,     -- per store, after a robbery starts
    PlayerCooldownMinutes = 10,    -- per robber

    Register = { seconds = 25, reward = { 400, 900 } },          -- needs a weapon in hand
    Safe = { seconds = 60, reward = { 1500, 3500 }, item = 'lockpick', breakChance = 0.25 },

    -- Dispatch goes out when the robbery starts (silent alarm).
    AlarmDelaySeconds = 0,

    Stores = {
        { id = 'innocence', label = '24/7 Innocence Blvd', register = vector3(24.47, -1346.62, 29.5), safe = vector3(28.21, -1339.14, 29.49) },
        { id = 'clinton', label = '24/7 Clinton Ave', register = vector3(372.66, 326.98, 103.57) },
    },
}
