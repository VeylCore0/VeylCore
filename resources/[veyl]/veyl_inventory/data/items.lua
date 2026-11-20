-- VeylCore item definitions (server authority). weight: integer grams.
-- use.handler names a server handler registered with exports.veyl_inventory:RegisterUseHandler(name, fn).
-- use.effects is server data read by that handler; the NUI can never submit handlers, effects or metadata.
return {
    water_bottle = {
        label = 'Water Bottle', description = 'A bottle of drinking water.', image = 'water_bottle.svg',
        weight = 500, stack = true, maxStack = 10,
        use = { handler = 'consume', durationMs = 2500, consumeCount = 1, effects = { thirst = 35 },
                anim = { dict = 'mp_player_intdrink', clip = 'loop_bottle', flag = 49 },
                prop = { model = 'prop_ld_flow_bottle', bone = 60309, pos = vec3(0.0, 0.0, 0.05), rot = vec3(0.0, 0.0, 0.0) } },
    },
    sprunk = {
        label = 'Sprunk', description = 'Fizzy and very green.', image = 'sprunk.svg', weight = 350, stack = true, maxStack = 10,
        use = { handler = 'consume', durationMs = 2500, consumeCount = 1, effects = { thirst = 25, stress = -5 },
                anim = { dict = 'mp_player_intdrink', clip = 'loop_bottle', flag = 49 } },
    },
    coffee = {
        label = 'Bean Machine Coffee', image = 'coffee.svg', weight = 300, stack = true, maxStack = 10,
        use = { handler = 'consume', durationMs = 2500, consumeCount = 1, effects = { thirst = 15, stress = -10 },
                anim = { dict = 'mp_player_intdrink', clip = 'loop_bottle', flag = 49 } },
    },
    sandwich = {
        label = 'Sandwich', image = 'sandwich.svg', weight = 300, stack = true, maxStack = 10,
        use = { handler = 'consume', durationMs = 3000, consumeCount = 1, effects = { hunger = 35 },
                anim = { dict = 'mp_player_inteat@burger', clip = 'mp_player_int_eat_burger', flag = 49 } },
    },
    burger = {
        label = 'Burger', image = 'burger.svg', weight = 400, stack = true, maxStack = 10,
        use = { handler = 'consume', durationMs = 3500, consumeCount = 1, effects = { hunger = 50 },
                anim = { dict = 'mp_player_inteat@burger', clip = 'mp_player_int_eat_burger', flag = 49 } },
    },
    bandage = {
        label = 'Bandage', image = 'bandage.svg', weight = 100, stack = true, maxStack = 10,
        use = { handler = 'consume', durationMs = 4000, consumeCount = 1, effects = { heal = 25 },
                anim = { dict = 'missheistdockssetup1clipboard@idle_a', clip = 'idle_a', flag = 49 } },
    },
    phone = { label = 'Phone', image = 'phone.svg', weight = 200, stack = false },
    identity_card = {
        label = 'Identity Card', description = 'Government-issued ID.', image = 'identity_card.svg',
        weight = 10, stack = false, metadataSchema = 'identity_card',
    },
    scrap_metal = { label = 'Scrap Metal', description = 'A stackable crafting material.', image = 'scrap_metal.svg', weight = 80, stack = true, maxStack = 100 },
    qbexample_token = {
        label = 'QB Example Token', description = 'Demonstrates QB CreateUseableItem on VeylCore.', image = 'token.svg',
        weight = 10, stack = true, maxStack = 50, usable = true, -- no use.handler: dispatched to the legacy usable-item registry
    },
}
