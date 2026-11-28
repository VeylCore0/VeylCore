-- Field operations branch: explore field zones, search the collectibles in them, grow field plants and process on portable field stations.
-- Fictional names and abstract items only. It uses the same engines as the botanical branch (plants, workstations, properties,
-- progression); this file only holds what is different about it.

ProductionConfig = ProductionConfig or {}

ProductionConfig.Field = {
    -- Field plant varieties (separate from the botanical ones: own seeds, own harvest item, own levels). See config/botanical.lua for the fields.
    Varieties = {
        dawn = {
            label = 'Dawnroot', branch = 'field', seed = 'prod_fseed_dawn', harvestItem = 'prod_field_bloom', level = 1, rarity = 'Common', growMinutes = 55,
            yield = { 2, 4 }, seedReturn = 0.3, baseQuality = 38, waterDecay = 0.9, nutrientDecay = 0.6,
            stages = { 'prop_plant_int_04a', 'prop_plant_int_02a', 'prop_plant_int_03a', 'prop_plant_int_05a' },
        },
        dusk = {
            label = 'Duskvine', branch = 'field', seed = 'prod_fseed_dusk', harvestItem = 'prod_field_bloom', level = 3, rarity = 'Rare', growMinutes = 90,
            yield = { 3, 6 }, seedReturn = 0.18, baseQuality = 58, waterDecay = 1.3, nutrientDecay = 1.0,
            stages = { 'prop_plant_int_04a', 'prop_plant_int_02b', 'prop_plant_int_03b', 'prop_plant_int_06a' },
        },
    },

    -- The field outfitter: field seeds and the portable field station.
    Shop = {
        Id = 'field_outfitter', Branch = 'field', Label = 'Field Outfitter',
        Ped = { model = 's_m_m_gardener_01', coords = vector4(2748.3, 3472.8, 55.7, 244.0), scenario = 'WORLD_HUMAN_CLIPBOARD', radius = 2.2, label = 'Field Outfitter' },
        RestockMinutes = 30,
        Items = {
            { item = 'prod_fseed_dawn',    price = 55,   stock = 30, restock = 5, level = 1 },
            { item = 'prod_fseed_dusk',    price = 150,  stock = 10, restock = 2, level = 3 },
            { item = 'prod_planter',       price = 60,   stock = 20, restock = 4, level = 1 },
            { item = 'prod_water',         price = 12,   stock = 40, restock = 8, level = 1 },
            { item = 'prod_nutrient',      price = 25,   stock = 30, restock = 6, level = 1 },
            { item = 'prod_field_station', price = 2800, stock = 4,  restock = 1, level = 2 },
        },
    },

    -- Field zones. Each zone has several `points` (spots in the world): a point shows a prop you can search, then is picked over for you
    -- (PlayerCooldown) and for everyone (RespawnMinutes). Z is only a guide: distance to a point is checked on the ground plane.
    Zones = {
        {
            id = 'alamo_shore', label = 'Alamo shoreline', branch = 'field', level = 1, prop = 'prop_plant_fern_01', RespawnMinutes = 12, PlayerCooldownMinutes = 40,
            points = { vector3(1971.0, 3827.0, 31.9), vector3(1990.0, 3842.0, 31.9), vector3(2008.0, 3818.0, 32.0), vector3(1950.0, 3809.0, 32.0), vector3(1930.0, 3835.0, 32.0) },
        },
        {
            id = 'canyon_floor', label = 'Canyon floor', branch = 'field', level = 2, prop = 'prop_plant_fern_01', RespawnMinutes = 18, PlayerCooldownMinutes = 60,
            points = { vector3(-1580.0, 4437.0, 14.0), vector3(-1562.0, 4452.0, 14.0), vector3(-1601.0, 4465.0, 14.0), vector3(-1545.0, 4421.0, 14.0) },
        },
    },
    SearchMs = 5000,
    -- Rewards roll once per search: { item, chance, min, max, level? }. The first always pays.
    Rewards = {
        { item = 'prod_field_find',  chance = 1.0,  min = 1, max = 3 },
        { item = 'prod_water',       chance = 0.2,  min = 1, max = 1 },
        { item = 'prod_fseed_dawn',  chance = 0.08, min = 1, max = 1 },       -- rare seed
        { item = 'prod_fseed_dusk',  chance = 0.02, min = 1, max = 1, level = 3 },
    },
    Blip = { sprite = 469, colour = 3, show = false },

    -- What the buyer pays for field goods (base; quality multiplies it).
    Buyer = { prod_field_pack = 200, prod_field_extract = 80, prod_field_bloom = 32, prod_field_find = 14 },
}
