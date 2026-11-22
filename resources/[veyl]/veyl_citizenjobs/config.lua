-- veyl_citizenjobs configuration. Coordinates are starting values: check them in game with /vcoords (veyl_admin).
-- Pay is in whole dollars, paid to the bank by the server at the end of each run / fare / tow.

CitizenJobsConfig = {
    MinSecondsPerStop = 12,        -- plausibility: no faster than this between two stops

    Jobs = {
        -- Trucking: take a load to a destination and come back. Pay grows with distance.
        trucker = {
            label = 'Trucking', kind = 'haul', blip = { sprite = 477, colour = 21 },
            depot = { model = 's_m_m_trucker_01', coords = vector4(1197.0, -3253.6, 7.1, 90.0) },
            spawn = vector4(1186.5, -3239.6, 6.0, 90.0), vehicle = 'mule3', platePrefix = 'HAUL',
            base = 150, perKm = 95, returnBonus = 120, unloadSeconds = 8,
            destinations = {
                vector3(1702.7, 4917.8, 42.1), vector3(-75.9, 6492.4, 31.5), vector3(1983.6, 3780.5, 32.2),
                vector3(2664.4, 1607.7, 24.5), vector3(-2196.0, 4249.4, 47.6), vector3(848.5, -1993.5, 29.3),
                vector3(-438.4, -2795.0, 6.0), vector3(2555.8, 2602.9, 37.9), vector3(-1140.0, -1993.0, 13.2),
            },
        },
        -- Garbage: take trash from ANY trash can or dumpster near your truck and throw it in the back.
        -- Collect the quota for a bonus. Each bin is empty for a while after it was used. Recyclables sometimes turn up.
        garbage = {
            label = 'Sanitation', kind = 'bins', blip = { sprite = 318, colour = 25 },
            depot = { model = 's_m_y_garbage', coords = vector4(-321.7, -1545.8, 31.0, 0.0) },
            spawn = vector4(-334.9, -1562.9, 25.2, 60.0), vehicle = 'trash2', platePrefix = 'TRSH',
            quota = 20, payPerBag = 22, completionBonus = 200,
            truckRange = 50.0,             -- the truck must be this close to the bin
            binCooldownMinutes = 10,       -- a bin is empty this long after someone emptied it
            recyclables = { chance = 0.35, items = { plastic = 40, glass = 25, rubber = 20, scrap_metal = 15 } },
            binModels = {
                'prop_bin_01a', 'prop_bin_02a', 'prop_bin_03a', 'prop_bin_04a', 'prop_bin_05a', 'prop_bin_06a', 'prop_bin_07a',
                'prop_bin_07b', 'prop_bin_07c', 'prop_bin_07d', 'prop_bin_08a', 'prop_bin_08open', 'prop_bin_09a', 'prop_bin_10a',
                'prop_bin_10b', 'prop_bin_11a', 'prop_bin_11b', 'prop_bin_12a', 'prop_bin_13a', 'prop_bin_14a', 'prop_bin_14b',
                'prop_bin_beach_01a', 'prop_bin_beach_01d', 'prop_bin_delpiero', 'prop_bin_delpiero_b', 'zprop_bin_01a_old',
                'prop_cs_bin_01', 'prop_cs_bin_01_skinned', 'prop_cs_bin_02', 'prop_cs_bin_03',
                'prop_dumpster_01a', 'prop_dumpster_02a', 'prop_dumpster_02b', 'prop_dumpster_3a', 'prop_dumpster_4a', 'prop_dumpster_4b',
                'prop_recyclebin_01a', 'prop_recyclebin_02_c', 'prop_recyclebin_02_d', 'prop_recyclebin_02a', 'prop_recyclebin_02b',
                'prop_recyclebin_03_a', 'prop_recyclebin_04_a', 'prop_recyclebin_04_b', 'prop_recyclebin_05_a',
            },
        },
        -- Taxi: pick up a fare, drive them, get paid by distance. Fares keep coming until you finish.
        taxi = {
            label = 'Downtown Cab Co.', kind = 'fare', blip = { sprite = 198, colour = 5 },
            depot = { model = 'a_m_y_stlat_01', coords = vector4(895.4, -179.3, 74.7, 240.0) },
            spawn = vector4(911.1, -163.6, 74.4, 194.0), vehicle = 'taxi', platePrefix = 'CAB',
            base = 40, perKm = 110, minFareKm = 0.6,
            spots = {
                vector3(195.1, -933.8, 30.7), vector3(-1640.7, -1012.1, 13.1), vector3(300.2, 180.5, 104.0),
                vector3(-1037.3, -2737.6, 20.2), vector3(-147.2, -370.1, 33.7), vector3(-1222.7, -1494.2, 4.4),
                vector3(1110.3, -645.1, 56.8), vector3(290.1, -590.3, 43.2), vector3(430.8, -972.6, 30.7),
                vector3(-660.2, -893.2, 24.6), vector3(95.2, -1932.5, 20.8), vector3(-1556.2, 22.3, 58.5),
                vector3(-414.5, -170.0, 37.2), vector3(-1374.4, -388.4, 36.5), vector3(244.5, -36.1, 69.7),
            },
            peds = { 'a_m_y_business_01', 'a_f_y_business_02', 'a_m_m_tourist_01', 'a_f_y_hipster_01', 'a_m_y_genstreet_01', 'a_f_m_bevhills_01' },
        },
        -- Tow: hook broken-down vehicles onto the flatbed and bring them to the yard.
        tow = {
            label = 'Tow Truck', kind = 'tow', blip = { sprite = 68, colour = 47 },
            depot = { model = 's_m_m_autoshop_02', coords = vector4(409.4, -1622.8, 29.3, 230.0) },
            spawn = vector4(401.3, -1631.6, 29.3, 230.0), vehicle = 'flatbed', platePrefix = 'TOW',
            yard = vector3(401.9, -1647.4, 29.3), yardRadius = 18.0, payPerTow = 320,
            models = { 'blista', 'asea', 'emperor', 'premier', 'ingot', 'primo', 'stanier', 'tornado', 'regina', 'fugitive' },
            calls = {
                vector4(-561.3, -838.5, 27.5, 90.0), vector4(232.6, -797.6, 30.6, 160.0), vector4(-1180.1, -879.0, 13.8, 120.0),
                vector4(1153.8, -330.3, 68.9, 10.0), vector4(-332.7, -78.6, 54.4, 340.0), vector4(842.2, -1078.4, 28.2, 270.0),
                vector4(-1446.9, -539.6, 34.7, 215.0), vector4(110.5, -1590.1, 29.3, 50.0), vector4(-73.1, -1785.2, 28.4, 140.0),
            },
        },
    },
}
