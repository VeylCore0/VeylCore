-- Botanical branch: invented plant varieties, care, harvest, the supply shop and gathering spots. All of it is abstract game
-- mechanics with fictional names. Item names live in shared/items.lua.

ProductionConfig = ProductionConfig or {}

-- veyl_weedprops (custom stream resource, must start before this one): an_weed_<colour>_<size>. Missing models fall back to FallbackProp.
local function weedStages(colour)
    local p = 'an_weed_' .. colour
    return { p .. '_01_small_01a', p .. '_01_small_01c', p .. '_med_01b', p .. '_lrg_01b' }
end

ProductionConfig.Botanical = {
    -- Plant varieties. Times are minutes of growth (care allowing). Decay is per minute. `stages` are the props shown as the plant grows
    -- (stage 1 = sprout ... last = ready); any valid model works, unknown models fall back to FallbackProp.
    FallbackProp = 'prop_plant_int_04a',
    Varieties = {
        ember = {
            label = 'Violet Haze', seed = 'prod_seed_ember', level = 1, rarity = 'Common', growMinutes = 45,
            yield = { 3, 5 }, seedReturn = 0.25, baseQuality = 40, waterDecay = 1.1, nutrientDecay = 0.7,
            stages = weedStages('purple'),
        },
        violet = {
            label = 'Silverleaf', seed = 'prod_seed_violet', level = 2, rarity = 'Uncommon', growMinutes = 70,
            yield = { 3, 6 }, seedReturn = 0.2, baseQuality = 50, waterDecay = 1.3, nutrientDecay = 0.9,
            stages = weedStages('white'),
        },
        azure = {
            label = 'Nightbloom', seed = 'prod_seed_azure', level = 4, rarity = 'Rare', growMinutes = 100,
            yield = { 4, 7 }, seedReturn = 0.15, baseQuality = 60, waterDecay = 1.5, nutrientDecay = 1.1,
            stages = weedStages('blue'),
        },
    },

    -- Care. Meters run 0-100. Growth only advances while both meters are above `StallBelow`.
    Care = {
        StartMeter = 70, StallBelow = 15, WaterAdds = 55, NutrientAdds = 55,
        HealthLossPerMinute = 0.8,      -- while a meter is empty
        HealthGainPerMinute = 0.15,     -- while both meters are healthy (above GoodAbove)
        GoodAbove = 40,
        MaxOfflineMinutes = 10080,      -- time is only simulated this far back (a week)
        CareQualityWeight = 22,         -- up to this many quality points for steady care
        HealthQualityWeight = 10,
    },
    WaterItem = 'prod_water', NutrientItem = 'prod_nutrient', PlanterItem = 'prod_planter',
    PlanterRecovery = 0.5,            -- chance to get the planter back when you remove or harvest a plant (harvest always empties it)
    SeedReturnItem = true,            -- varieties' seedReturn chance gives a seed back on harvest

    -- Selling finished products to the buyer. Price = base x quality multiplier.
    Buyer = { prod_pack = 180, prod_blend = 70, prod_leaf = 28, prod_wild_herb = 12 },
}

-- The supply shop. `stock` refills every `RestockMinutes` by `restock`. Prices are server-side only.
ProductionConfig.Shop = {
    Id = 'garden_supplier',
    Ped = { model = 's_m_m_gardener_01', coords = vector4(1960.1, 3739.9, 32.34, 300.0), scenario = 'WORLD_HUMAN_GARDENER_PLANT', radius = 2.2, label = 'Garden Supplier' },
    Blip = { sprite = 469, colour = 25, label = 'Garden Supplier', show = false },
    RestockMinutes = 30,
    Items = {
        { item = 'prod_planter',     price = 60,   stock = 30, restock = 5, level = 1 },
        { item = 'prod_water',       price = 12,   stock = 60, restock = 10, level = 1 },
        { item = 'prod_nutrient',    price = 25,   stock = 40, restock = 8, level = 1 },
        { item = 'prod_seed_ember',  price = 40,   stock = 40, restock = 6, level = 1 },
        { item = 'prod_seed_violet', price = 110,  stock = 20, restock = 4, level = 2 },
        { item = 'prod_seed_azure',  price = 260,  stock = 10, restock = 2, level = 4 },
        { item = 'prod_workstation', price = 2500, stock = 5,  restock = 1, level = 2 },
    },
}

-- Gathering: wild spots that give small fictional rewards. Each spot has a cooldown per player.
ProductionConfig.Gathering = {
    Spots = {
        { id = 'grapeseed_a', label = 'Wild patch', coords = vector3(2024.5, 4880.2, 42.2), radius = 6.0, level = 1, cooldown = 300 },
        { id = 'grapeseed_b', label = 'Wild patch', coords = vector3(1959.3, 4640.8, 40.6), radius = 6.0, level = 1, cooldown = 300 },
        { id = 'paleto_a', label = 'Overgrown ditch', coords = vector3(-216.0, 6330.5, 31.5), radius = 6.0, level = 2, cooldown = 420 },
    },
    DurationMs = 5500,
    -- Rewards roll once per gather: { item, chance, min, max }. Every entry rolls independently; the first entry always pays.
    Rewards = {
        { item = 'prod_wild_herb', chance = 1.0, min = 1, max = 3 },
        { item = 'prod_nutrient', chance = 0.35, min = 1, max = 1 },
        { item = 'prod_water', chance = 0.2, min = 1, max = 2 },
        { item = 'prod_seed_ember', chance = 0.12, min = 1, max = 2 },
        { item = 'prod_seed_violet', chance = 0.03, min = 1, max = 1, level = 2 },
    },
    Blip = { sprite = 469, colour = 2, scale = 0.6, show = false },
}

-- The buyer pays cash for finished goods. A separate NPC from the supplier.
ProductionConfig.Buyer = {
    Ped = { model = 'a_m_m_business_01', coords = vector4(1964.3, 3746.2, 32.3, 120.0), scenario = 'WORLD_HUMAN_STAND_IMPATIENT', radius = 2.2, label = 'Buyer' },
}
