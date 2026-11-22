-- veyl_crafting configuration. Benches at fixed places; recipes take materials from the new jobs (garbage recyclables,
-- quarry ores, hunting hides). level = crafting level needed (metadata.skills.crafting / 100, max 10).

CraftingConfig = {
    XpPerLevel = 100,
    MaxLevel = 10,

    Benches = {
        foundry = {
            label = 'Foundry', coords = vector3(1109.9, -2008.2, 31.0), blip = { sprite = 436, colour = 47 },
            scenario = 'WORLD_HUMAN_WELDING',
            recipes = {
                { output = 'iron_ingot', count = 1, seconds = 8, xp = 3, level = 0, inputs = { iron_ore = 2, coal = 1 } },
                { output = 'copper_ingot', count = 1, seconds = 8, xp = 3, level = 0, inputs = { copper_ore = 2, coal = 1 } },
                { output = 'gold_bar', count = 1, seconds = 14, xp = 10, level = 2, inputs = { gold_ore = 3, coal = 2 } },
                { output = 'glass', count = 2, seconds = 6, xp = 2, level = 0, inputs = { stone = 3, coal = 1 } },
            },
        },
        workshop = {
            label = 'Public workshop', coords = vector3(2747.6, 3472.9, 55.7), blip = { sprite = 566, colour = 5 },
            scenario = 'PROP_HUMAN_BUM_BIN',
            recipes = {
                { output = 'lockpick', count = 2, seconds = 6, xp = 4, level = 0, inputs = { iron_ingot = 1, plastic = 1 } },
                { output = 'repair_kit', count = 1, seconds = 12, xp = 8, level = 1, inputs = { iron_ingot = 2, rubber = 1, scrap_metal = 2 } },
                { output = 'tyre_kit', count = 1, seconds = 8, xp = 5, level = 1, inputs = { rubber = 3 } },
                { output = 'pickaxe', count = 1, seconds = 10, xp = 6, level = 0, inputs = { iron_ingot = 2, scrap_metal = 1 } },
                { output = 'radio', count = 1, seconds = 12, xp = 8, level = 2, inputs = { copper_ingot = 2, plastic = 2, glass = 1 } },
                { output = 'fishing_rod', count = 1, seconds = 8, xp = 4, level = 1, inputs = { plastic = 2, copper_ingot = 1 } },
                { output = 'plant_pot', count = 2, seconds = 5, xp = 2, level = 0, inputs = { plastic = 3 } },
                { output = 'flashlight', count = 1, seconds = 8, xp = 5, level = 1, inputs = { plastic = 1, glass = 1, copper_ingot = 1 } },
            },
        },
        mechanic = {
            label = 'Parts bench', coords = vector3(-339.9, -137.1, 39.0), groups = { mechanic = 0, tunershop = 0 },
            scenario = 'WORLD_HUMAN_WELDING',
            recipes = {
                { output = 'engine_parts', count = 1, seconds = 10, xp = 6, level = 0, inputs = { iron_ingot = 2, copper_ingot = 1, scrap_metal = 2 } },
                { output = 'body_panels', count = 1, seconds = 10, xp = 6, level = 0, inputs = { iron_ingot = 2, scrap_metal = 3 } },
                { output = 'tyre_kit', count = 2, seconds = 8, xp = 5, level = 0, inputs = { rubber = 4 } },
                { output = 'perf_brakes', count = 1, seconds = 16, xp = 14, level = 2, inputs = { iron_ingot = 4, rubber = 2 } },
                { output = 'perf_suspension', count = 1, seconds = 16, xp = 14, level = 2, inputs = { iron_ingot = 4, rubber = 3 } },
                { output = 'perf_transmission', count = 1, seconds = 18, xp = 16, level = 3, inputs = { iron_ingot = 5, copper_ingot = 2 } },
                { output = 'perf_engine', count = 1, seconds = 20, xp = 20, level = 4, inputs = { iron_ingot = 6, copper_ingot = 3, engine_parts = 1 } },
                { output = 'perf_turbo', count = 1, seconds = 20, xp = 20, level = 5, inputs = { iron_ingot = 5, copper_ingot = 4, rubber = 2 } },
            },
        },
        -- No blip: you have to find it.
        backroom = {
            label = 'Backroom bench', coords = vector3(708.9, -966.4, 30.4),
            scenario = 'PROP_HUMAN_BUM_BIN',
            recipes = {
                { output = 'fake_plate', count = 1, seconds = 10, xp = 8, level = 2, inputs = { iron_ingot = 1, plastic = 2 } },
                { output = 'ammo_pistol', count = 12, seconds = 12, xp = 8, level = 3, inputs = { copper_ingot = 1, scrap_metal = 1 } },
                { output = 'armor_vest', count = 1, seconds = 20, xp = 18, level = 4, inputs = { iron_ingot = 4, rubber = 2, deer_hide = 1 } },
                { output = 'thermite', count = 1, seconds = 18, xp = 15, level = 5, inputs = { iron_ingot = 2, copper_ingot = 2, coal = 3 } },
            },
        },
    },
}
