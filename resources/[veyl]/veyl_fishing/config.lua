-- veyl_fishing configuration. Prices in whole dollars.

FishingConfig = {
    Rod = 'fishing_rod',
    Bait = 'fishing_bait',
    WaitSeconds = { 6, 16 },       -- time until a bite
    ReactSeconds = 1.6,            -- press E within this long when it bites
    MaxCarry = 50,                 -- stop fishing above this many fish

    -- Fish: item, sell price, weight in the zone tables below.
    Fish = {
        fish_mackerel = { label = 'Mackerel', price = 35 },
        fish_bass = { label = 'Sea Bass', price = 55 },
        fish_tuna = { label = 'Tuna', price = 140 },
        fish_salmon = { label = 'Salmon', price = 90 },
        fish_catfish = { label = 'Catfish', price = 45 },
        fish_trout = { label = 'Trout', price = 60 },
        fish_shark = { label = 'Small Shark', price = 400 },
    },

    Zones = {
        { label = 'Del Perro Pier', center = vector3(-1850.0, -1250.0, 8.6), radius = 70.0,
          catch = { fish_mackerel = 45, fish_bass = 30, fish_tuna = 12, fish_shark = 2, junk = 11 } },
        { label = 'Alamo Sea', center = vector3(1301.0, 4228.0, 33.9), radius = 300.0,
          catch = { fish_catfish = 45, fish_bass = 25, fish_trout = 22, junk = 8 } },
        { label = 'Paleto Cove', center = vector3(-275.0, 6640.0, 7.5), radius = 90.0,
          catch = { fish_salmon = 35, fish_mackerel = 30, fish_tuna = 15, fish_shark = 4, junk = 16 } },
    },

    -- Where fish are bought (a clerk).
    Market = { label = 'Fish market', coords = vector4(-1612.5, -1028.8, 13.15, 140.0), model = 's_m_m_linecook' },
}
