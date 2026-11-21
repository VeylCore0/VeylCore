-- VeylCore item definitions (server authority). weight: integer grams.
-- use.handler names a server handler registered with exports.veyl_inventory:RegisterUseHandler(name, fn).
-- use.effects is server data read by that handler; the NUI can never submit handlers, effects or metadata.
return {
    water_bottle = {
        label = 'Water Bottle', description = 'A bottle of drinking water.', image = 'water_bottle.png',
        weight = 500, stack = true, maxStack = 10,
        use = { handler = 'consume', durationMs = 2500, consumeCount = 1, effects = { thirst = 35 },
                anim = { dict = 'mp_player_intdrink', clip = 'loop_bottle', flag = 49 },
                prop = { model = 'prop_ld_flow_bottle', bone = 60309, pos = vec3(0.0, 0.0, 0.05), rot = vec3(0.0, 0.0, 0.0) } },
    },
    sprunk = {
        label = 'Sprunk', description = 'Fizzy and very green.', image = 'sprunk.png', weight = 350, stack = true, maxStack = 10,
        use = { handler = 'consume', durationMs = 2500, consumeCount = 1, effects = { thirst = 25, stress = -5 },
                anim = { dict = 'mp_player_intdrink', clip = 'loop_bottle', flag = 49 } },
    },
    coffee = {
        label = 'Bean Machine Coffee', image = 'coffee.png', weight = 300, stack = true, maxStack = 10,
        use = { handler = 'consume', durationMs = 2500, consumeCount = 1, effects = { thirst = 15, stress = -10 },
                anim = { dict = 'mp_player_intdrink', clip = 'loop_bottle', flag = 49 } },
    },
    sandwich = {
        label = 'Sandwich', image = 'sandwich.png', weight = 300, stack = true, maxStack = 10,
        use = { handler = 'consume', durationMs = 3000, consumeCount = 1, effects = { hunger = 35 },
                anim = { dict = 'mp_player_inteat@burger', clip = 'mp_player_int_eat_burger', flag = 49 } },
    },
    burger = {
        label = 'Burger', image = 'burger.png', weight = 400, stack = true, maxStack = 10,
        use = { handler = 'consume', durationMs = 3500, consumeCount = 1, effects = { hunger = 50 },
                anim = { dict = 'mp_player_inteat@burger', clip = 'mp_player_int_eat_burger', flag = 49 } },
    },
    bandage = {
        label = 'Bandage', image = 'bandage.png', weight = 100, stack = true, maxStack = 10,
        use = { handler = 'consume', durationMs = 4000, consumeCount = 1, effects = { heal = 25 },
                anim = { dict = 'missheistdockssetup1clipboard@idle_a', clip = 'idle_a', flag = 49 } },
    },
    snack_bar = {
        label = 'Snack Bar', description = 'A quick bite.', image = 'snack_bar.png', weight = 80, stack = true, maxStack = 20,
        use = { handler = 'consume', durationMs = 2000, consumeCount = 1, effects = { hunger = 15 },
                anim = { dict = 'mp_player_inteat@burger', clip = 'mp_player_int_eat_burger', flag = 49 } },
    },
    flashlight = { label = 'Flashlight', description = 'Lights up the dark.', image = 'flashlight.png', weight = 600, stack = false },
    radio = { label = 'Radio', description = 'Short-range radio.', image = 'radio.png', weight = 400, stack = false },
    repair_kit = { label = 'Repair Kit', description = 'Fixes minor vehicle damage.', image = 'repair_kit.png', weight = 2500, stack = true, maxStack = 5 },
    phone = { label = 'Phone', image = 'phone.png', weight = 200, stack = false },
    identity_card = {
        label = 'Identity Card', description = 'Government-issued ID.', image = 'identity_card.png',
        weight = 10, stack = false, metadataSchema = 'identity_card',
    },
    scrap_metal = { label = 'Scrap Metal', description = 'A stackable crafting material.', image = 'scrap_metal.png', weight = 80, stack = true, maxStack = 100 },
    qbexample_token = {
        label = 'QB Example Token', description = 'Demonstrates QB CreateUseableItem on VeylCore.', image = 'token.png',
        weight = 10, stack = true, maxStack = 50, usable = true, -- no use.handler: dispatched to the legacy usable-item registry
    },
}
