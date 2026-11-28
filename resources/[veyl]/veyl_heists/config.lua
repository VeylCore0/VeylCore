-- veyl_heists configuration. Points are the security panel / vault door / store centre for each location; deposit
-- boxes and display cases are looted at that point (repeatable up to `loots`). Rewards: marked bills (dirty money).

HeistsConfig = {
    PoliceJobs = { 'police' },
    OneBankAtATime = true,

    Fleeca = {
        minPolice = 3, cooldownMinutes = 60, hackSeconds = 30, lootSeconds = 20, loots = 8,
        hackItem = 'hacking_device', hackBreakChance = 0.5, drillItem = 'drill', reward = { 750, 1750 },   -- per lockbox; there are 8 in each vault
        -- Each bank: the vault door object near the panel, its heading closed / open, and the lockboxes inside the vault (one drill each).
        banks = {
            { id = 'legion', label = 'Fleeca Legion Square', panel = vector3(146.92, -1046.11, 29.36),
              door = { model = 'v_ilev_gb_vauldr', closed = 250, open = 160 },
              boxes = { vector3(149.84, -1044.9, 29.34), vector3(151.16, -1046.64, 29.34), vector3(147.16, -1047.72, 29.34), vector3(146.54, -1049.28, 29.34), vector3(146.88, -1050.33, 29.34), vector3(150.0, -1050.67, 29.34), vector3(149.47, -1051.28, 29.34), vector3(150.58, -1049.09, 29.34) } },
            { id = 'hawick', label = 'Fleeca Hawick Ave', panel = vector3(311.15, -284.49, 54.16),
              door = { model = 'v_ilev_gb_vauldr', closed = 250, open = 160 },
              boxes = { vector3(311.16, -287.71, 54.14), vector3(311.86, -286.21, 54.14), vector3(313.39, -289.15, 54.14), vector3(311.7, -288.45, 54.14), vector3(314.23, -288.77, 54.14), vector3(314.83, -287.33, 54.14), vector3(315.24, -284.85, 54.14), vector3(314.08, -283.38, 54.14) } },
            { id = 'delperro', label = 'Fleeca Del Perro Blvd', panel = vector3(-354.29, -55.11, 49.04),
              door = { model = 'v_ilev_gb_vauldr', closed = 250, open = 160 },
              boxes = { vector3(-350.99, -54.13, 49.01), vector3(-349.53, -55.77, 49.01), vector3(-353.54, -56.94, 49.01), vector3(-354.09, -58.55, 49.01), vector3(-353.81, -59.48, 49.01), vector3(-349.8, -58.3, 49.01), vector3(-351.14, -60.37, 49.01), vector3(-350.4, -59.92, 49.01) } },
            { id = 'rockford', label = 'Fleeca Rockford Hills', panel = vector3(-1210.77, -336.57, 37.78),
              door = { model = 'v_ilev_gb_vauldr', closed = 296.863, open = 206.863 },
              boxes = { vector3(-1209.68, -333.65, 37.75), vector3(-1207.46, -333.77, 37.75), vector3(-1209.45, -337.47, 37.75), vector3(-1208.65, -339.06, 37.75), vector3(-1207.75, -339.42, 37.75), vector3(-1205.28, -338.14, 37.75), vector3(-1205.08, -337.28, 37.75), vector3(-1205.92, -335.75, 37.75) } },
            { id = 'oceanhwy', label = 'Fleeca Great Ocean Hwy', panel = vector3(-2956.55, 481.74, 15.69),
              door = { model = 'hei_prop_heist_sec_door', closed = 357.542, open = 267.542 },
              boxes = { vector3(-2958.54, 484.1, 15.67), vector3(-2957.3, 485.95, 15.67), vector3(-2955.09, 482.43, 15.67), vector3(-2953.26, 482.42, 15.67), vector3(-2952.63, 483.09, 15.67), vector3(-2952.45, 485.66, 15.67), vector3(-2953.13, 486.26, 15.67), vector3(-2954.98, 486.37, 15.67) } },
            { id = 'route68', label = 'Fleeca Route 68', panel = vector3(1175.96, 2712.87, 38.09),
              door = { model = 'v_ilev_gb_vauldr', closed = -270.542, open = -370.542 },
              boxes = { vector3(1173.69, 2710.76, 38.07), vector3(1171.78, 2711.94, 38.07), vector3(1175.25, 2714.51, 38.07), vector3(1175.26, 2715.97, 38.07), vector3(1174.27, 2716.83, 38.07), vector3(1172.32, 2716.82, 38.07), vector3(1171.25, 2716.08, 38.07), vector3(1171.23, 2714.44, 38.07) } },
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
