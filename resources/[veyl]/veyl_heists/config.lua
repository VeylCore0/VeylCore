-- veyl_heists configuration. Points are the security panel / vault door / store centre for each location; deposit
-- boxes and display cases are looted at that point (repeatable up to `loots`). Rewards: marked bills (dirty money).

HeistsConfig = {
    PoliceJobs = { 'police' },
    OneBankAtATime = true,

    Fleeca = {
        minPolice = 3, cooldownMinutes = 60, hackSeconds = 30, lootSeconds = 20, loots = 4,
        hackItem = 'hacking_device', hackBreakChance = 0.5, drillItem = 'drill', reward = { 1500, 3500 },
        banks = {
            { id = 'legion', label = 'Fleeca Legion Square', panel = vector3(146.92, -1046.11, 29.36) },
            { id = 'hawick', label = 'Fleeca Hawick Ave', panel = vector3(311.15, -284.49, 54.16) },
            { id = 'delperro', label = 'Fleeca Del Perro Blvd', panel = vector3(-354.29, -55.11, 49.04) },
            { id = 'rockford', label = 'Fleeca Rockford Hills', panel = vector3(-1210.77, -336.57, 37.78) },
            { id = 'oceanhwy', label = 'Fleeca Great Ocean Hwy', panel = vector3(-2956.55, 481.74, 15.69) },
            { id = 'route68', label = 'Fleeca Route 68', panel = vector3(1175.96, 2712.87, 38.09) },
        },
    },

    Paleto = {
        id = 'paleto', label = 'Blaine County Savings (Paleto)', minPolice = 5, cooldownMinutes = 120,
        door = vector3(-104.81, 6473.65, 31.62), panel = vector3(-105.61, 6472.03, 31.62),
        thermiteItem = 'thermite', thermiteSeconds = 15, hackSeconds = 40, lootSeconds = 25, loots = 6,
        hackItem = 'hacking_device', drillItem = 'drill', reward = { 3500, 7000 },
    },

    Jewelry = {
        id = 'vangelico', label = 'Vangelico Jewelry', center = vector3(-622.6, -231.0, 38.06), radius = 9.0,
        minPolice = 2, cooldownMinutes = 45, smashSeconds = 6, loots = 12,
        loot = { { item = 'rolex', min = 1, max = 2 }, { item = 'gold_chain', min = 1, max = 3 }, { item = 'diamond_ring', min = 0, max = 2 } },
    },
}
