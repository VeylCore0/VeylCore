-- veyl_gathering configuration: mining, hunting and farming. Coordinates are starting values (check with /vcoords).
-- Yields are server-side. Ores are smelted at the foundry bench in veyl_crafting.

GatheringConfig = {
    Mining = {
        label = 'Davis Quartz quarry', tool = 'pickaxe', seconds = 7, respawnSeconds = 150,
        -- A rock prop is placed on every spot (the first model that exists in your game build is used).
        -- It disappears when the rock is mined out and comes back when it refills.
        rockModels = { 'prop_rock_4_c', 'prop_rock_4_d', 'prop_rock_1_f', 'prop_rock_3_f', 'prop_rock_1_a' },
        rockDrawDistance = 120.0,
        blip = { coords = vector3(2954.0, 2788.0, 41.0), sprite = 618, colour = 5 },
        spots = {
            vector3(2943.9, 2770.4, 39.1), vector3(2959.0, 2758.3, 42.0), vector3(2975.1, 2789.9, 40.5), vector3(2935.4, 2808.6, 42.5),
            vector3(2919.5, 2789.6, 43.0), vector3(2953.6, 2820.6, 42.2), vector3(2990.4, 2765.7, 42.7), vector3(2928.3, 2760.9, 44.0),
            vector3(2968.2, 2804.4, 41.6), vector3(2946.1, 2742.5, 43.4),
        },
        -- item = { weight, min, max }
        yields = { stone = { 40, 2, 4 }, coal = { 25, 1, 3 }, iron_ore = { 18, 1, 2 }, copper_ore = { 14, 1, 2 }, gold_ore = { 3, 1, 1 } },
    },

    Hunting = {
        knife = 'weapon_knife',             -- needed (in your inventory) to skin an animal
        maxAnimals = 3,                     -- animals around each hunter at once
        zones = {
            { label = 'Paleto Forest', center = vector3(-650.0, 5650.0, 38.0), radius = 400.0 },
            { label = 'Tongva Hills', center = vector3(-1750.0, 2000.0, 120.0), radius = 350.0 },
            { label = 'Mount Chiliad foothills', center = vector3(1400.0, 5800.0, 300.0), radius = 450.0 },
        },
        animals = {
            a_c_deer = { label = 'Deer', weight = 50, items = { raw_meat = { 2, 4 }, deer_hide = { 1, 1 } }, bonus = { deer_antlers = 0.25 } },
            a_c_boar = { label = 'Boar', weight = 30, items = { raw_meat = { 2, 3 }, boar_hide = { 1, 1 } } },
            a_c_coyote = { label = 'Coyote', weight = 20, items = { raw_meat = { 1, 1 }, coyote_pelt = { 1, 1 } } },
        },
    },

    Farming = {
        label = 'Grapeseed farms', seconds = 4, respawnSeconds = 120,
        blip = { coords = vector3(2050.0, 4900.0, 41.0), sprite = 140, colour = 2 },
        -- Each point is one plant / tree / cow. kind sets the animation.
        points = {
            { coords = vector3(2032.6, 4900.4, 42.7), item = 'wheat', min = 2, max = 4, kind = 'crop', label = 'Wheat' },
            { coords = vector3(2038.1, 4894.9, 42.7), item = 'wheat', min = 2, max = 4, kind = 'crop', label = 'Wheat' },
            { coords = vector3(2043.4, 4889.7, 42.7), item = 'wheat', min = 2, max = 4, kind = 'crop', label = 'Wheat' },
            { coords = vector3(1896.3, 4816.2, 45.0), item = 'tomato', min = 2, max = 5, kind = 'crop', label = 'Tomatoes' },
            { coords = vector3(1901.8, 4811.0, 45.0), item = 'tomato', min = 2, max = 5, kind = 'crop', label = 'Tomatoes' },
            { coords = vector3(2121.4, 5101.2, 46.0), item = 'potato', min = 2, max = 5, kind = 'crop', label = 'Potatoes' },
            { coords = vector3(2126.7, 5095.9, 46.0), item = 'potato', min = 2, max = 5, kind = 'crop', label = 'Potatoes' },
            { coords = vector3(2231.0, 5170.4, 58.2), item = 'lettuce', min = 1, max = 3, kind = 'crop', label = 'Lettuce' },
            { coords = vector3(2336.1, 4768.5, 35.4), item = 'orange', min = 2, max = 4, kind = 'tree', label = 'Orange tree' },
            { coords = vector3(2343.0, 4761.2, 35.1), item = 'orange', min = 2, max = 4, kind = 'tree', label = 'Orange tree' },
            { coords = vector3(2440.6, 4760.7, 34.3), item = 'milk', min = 1, max = 2, kind = 'cow', label = 'Cow' },
            { coords = vector3(2446.2, 4755.0, 34.3), item = 'milk', min = 1, max = 2, kind = 'cow', label = 'Cow' },
        },
    },

    -- Buyers pay cash. price per item.
    Buyers = {
        { id = 'ores', label = 'Ore & metal buyer', model = 's_m_y_construct_01', coords = vector4(1086.6, -2003.6, 31.4, 140.0), blip = { 618, 5 },
          prices = { stone = 4, coal = 8, iron_ore = 16, copper_ore = 18, gold_ore = 70, iron_ingot = 42, copper_ingot = 46, gold_bar = 260, scrap_metal = 12 } },
        { id = 'butcher', label = 'Butcher', model = 's_m_m_linecook', coords = vector4(-68.9, 6254.9, 31.1, 300.0), blip = { 463, 1 },
          prices = { raw_meat = 28, deer_hide = 90, boar_hide = 75, coyote_pelt = 55, deer_antlers = 180 } },
        { id = 'farmers', label = "Farmers' market", model = 'a_m_m_farmer_01', coords = vector4(1675.4, 4882.3, 42.0, 50.0), blip = { 52, 2 },
          prices = { wheat = 6, tomato = 7, potato = 6, lettuce = 6, orange = 7, milk = 9 } },
    },

    -- Skill: xp per action; each level (every 100 xp, up to 5) adds a 6% chance of an extra item.
    Xp = { mining = 4, hunting = 10, farming = 3 },
}
