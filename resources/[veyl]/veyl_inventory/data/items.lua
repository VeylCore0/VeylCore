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
        weight = 10, stack = false, metadataSchema = 'identity_card', use = { handler = 'cityhall_show', durationMs = 0, consumeCount = 0 },
    },
    -- veyl_cityhall: printed at the City Hall desk; using one shows it to people nearby
    driver_license = { label = "Driver's Licence", description = 'Proof you can drive.', image = 'identity_card.png', weight = 10, stack = false,
        metadataSchema = 'licence_card', use = { handler = 'cityhall_show', durationMs = 0, consumeCount = 0 } },
    weapon_license = { label = 'Weapon Licence', description = 'Proof you may carry a firearm.', image = 'identity_card.png', weight = 10, stack = false,
        metadataSchema = 'licence_card', use = { handler = 'cityhall_show', durationMs = 0, consumeCount = 0 } },
    -- veyl_doorlocks
    door_key = { label = 'Key', description = 'Opens one door.', image = 'keys.png', weight = 20, stack = false, metadataSchema = 'door_key' },
    lockpick = { label = 'Lockpick', description = 'Picks simple locks. Might break.', image = 'lockpick.png', weight = 50, stack = true, maxStack = 10 },
    door_ram = { label = 'Door Ram', description = 'Police breaching tool.', image = 'door_ram.png', weight = 6000, stack = false },
    scrap_metal = { label = 'Scrap Metal', description = 'A stackable crafting material.', image = 'scrap_metal.png', weight = 80, stack = true, maxStack = 100 },
    -- Mechanic parts (consumed by veyl_mechanic repairs; sold at the mechanic parts counter)
    engine_parts = { label = 'Engine Parts', description = 'Used by mechanics to repair an engine.', image = 'engine_parts.png', weight = 2000, stack = true, maxStack = 10 },
    body_panels = { label = 'Body Panels', description = 'Used by mechanics to repair bodywork.', image = 'body_panels.png', weight = 1500, stack = true, maxStack = 10 },
    tyre_kit = { label = 'Tyre Kit', description = 'Used by mechanics to replace burst tyres.', image = 'tyre_kit.png', weight = 1200, stack = true, maxStack = 10 },
    cleaning_kit = { label = 'Cleaning Kit', description = 'Used by mechanics to wash a vehicle.', image = 'cleaning_kit.png', weight = 300, stack = true, maxStack = 20 },
    -- veyl_drugs (fictional game items). Seeds carry their variety; harvests carry variety, quality grade and batch id
    -- in metadata, so different batches never stack together.
    weed_seed = { label = 'Cannabis Seed', description = 'Plant on suitable ground or in a pot.', image = 'weed_seed.png', weight = 5,
        stack = true, maxStack = 50, metadataSchema = 'drug_seed', use = { handler = 'drug_place', durationMs = 0, consumeCount = 0 } },
    coca_seed = { label = 'Coca Seedling', description = 'Plant on suitable ground or in a pot.', image = 'coca_seed.png', weight = 20,
        stack = true, maxStack = 25, metadataSchema = 'drug_seed', use = { handler = 'drug_place', durationMs = 0, consumeCount = 0 } },
    mushroom_spores = { label = 'Mushroom Culture', description = 'Starts a grow tub (needs an empty Grow Tub).', image = 'mushroom_spores.png',
        weight = 10, stack = true, maxStack = 25, metadataSchema = 'drug_seed', use = { handler = 'drug_place', durationMs = 0, consumeCount = 0 } },
    plant_pot = { label = 'Plant Pot', description = 'Lets you plant on hard surfaces. Used up when planted.', image = 'plant_pot.png', weight = 1500, stack = true, maxStack = 5 },
    grow_tub = { label = 'Grow Tub', description = 'A tub for mushroom cultures. Used up when started.', image = 'grow_tub.png', weight = 2500, stack = true, maxStack = 5 },
    plant_food = { label = 'Grow Nutrients', description = 'Keeps a plant cared for.', image = 'plant_food.png', weight = 400, stack = true, maxStack = 20 },
    grow_journal = { label = 'Grow Journal', description = 'A tablet that tracks your plants.', image = 'grow_journal.png', weight = 300, stack = false,
        use = { handler = 'drug_journal', durationMs = 0, consumeCount = 0 } },
    weed_bud = { label = 'Cannabis Bud', description = 'Freshly harvested.', image = 'weed_bud.png', weight = 50, stack = true, maxStack = 100, metadataSchema = 'drug_batch' },
    coca_leaf = { label = 'Coca Leaves', description = 'Freshly harvested.', image = 'coca_leaf.png', weight = 40, stack = true, maxStack = 100, metadataSchema = 'drug_batch' },
    mushroom_cap = { label = 'Mushrooms', description = 'Freshly harvested.', image = 'mushroom_cap.png', weight = 30, stack = true, maxStack = 100, metadataSchema = 'drug_batch' },
    -- veyl_drugs equipment and packaging (fictional)
    weed_table = { label = 'Weed Table', description = 'Placeable table for rolling joints and bagging weed.', image = 'weed_table.png',
        weight = 8000, stack = false, use = { handler = 'drug_place_equipment', durationMs = 0, consumeCount = 0 } },
    coke_table = { label = 'Coke Table', description = 'Placeable table for processing and bagging.', image = 'coke_table.png',
        weight = 9000, stack = false, use = { handler = 'drug_place_equipment', durationMs = 0, consumeCount = 0 } },
    rolling_papers = { label = 'Rolling Papers', image = 'rolling_papers.png', weight = 10, stack = true, maxStack = 50 },
    empty_baggie = { label = 'Empty Baggie', image = 'empty_baggie.png', weight = 5, stack = true, maxStack = 100 },
    lab_supplies = { label = 'Processing Supplies', description = 'Abstract supplies for the coke table.', image = 'lab_supplies.png',
        weight = 500, stack = true, maxStack = 20 },
    joint = { label = 'Joint', description = 'Takes the edge off.', image = 'joint.png', weight = 5, stack = true, maxStack = 50, metadataSchema = 'drug_batch',
        use = { handler = 'consume', durationMs = 4000, consumeCount = 1, effects = { stress = -15 },
                anim = { dict = 'amb@world_human_smoking@male@male_a@enter', clip = 'enter', flag = 49 },
                prop = { model = 'prop_sh_joint_01', bone = 47419, pos = vec3(0.015, -0.009, 0.003), rot = vec3(55.0, 0.0, 110.0) } } },
    weed_baggie = { label = 'Bag of Weed', description = 'Packaged for sale.', image = 'weed_baggie.png', weight = 30, stack = true, maxStack = 50, metadataSchema = 'drug_batch' },
    coke_powder = { label = 'Cocaine', description = 'Processed, not yet packaged.', image = 'coke_powder.png', weight = 50, stack = true, maxStack = 50, metadataSchema = 'drug_batch' },
    coke_baggie = { label = 'Bag of Coke', description = 'Packaged for sale.', image = 'coke_baggie.png', weight = 20, stack = true, maxStack = 50, metadataSchema = 'drug_batch' },
    qbexample_token = {
        label = 'QB Example Token', description = 'Demonstrates QB CreateUseableItem on VeylCore.', image = 'token.png',
        weight = 10, stack = true, maxStack = 50, usable = true, -- no use.handler: dispatched to the legacy usable-item registry
    },
}
