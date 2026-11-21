-- Products and varieties (fictional). Growth hours are real hours; yields are item counts.
-- waterUse / careUse: meter points lost per hour while someone responsible is online.
-- maxQuality caps the quality a variety can reach (0-100); demand is used by buyers (milestone D).
DrugsProducts = {
    weed = {
        label = 'Cannabis', seedItem = 'weed_seed', harvestItem = 'weed_bud', containers = { 'ground', 'pot' },
        -- props per stage (1 = seedling ... 4 = ready). Missing models fall back to Fallback with a console warning.
        props = {
            ground = { 'bkr_prop_weed_01_small_01b', 'bkr_prop_weed_med_01a', 'bkr_prop_weed_lrg_01a', 'bkr_prop_weed_lrg_01b' },
            pot = { 'bkr_prop_weed_01_small_01a', 'bkr_prop_weed_01_small_01c', 'bkr_prop_weed_med_01b', 'bkr_prop_weed_lrg_01b' },
        },
        potProp = 'bkr_prop_weed_bucket_01a',
        varieties = {
            violet_haze = { label = 'Violet Haze', growHours = 3.0, waterUse = 14, careUse = 9, yield = 6, maxQuality = 92, demand = 1.0,
                trait = 'Balanced all-rounder' },
            silverleaf = { label = 'Silverleaf', growHours = 4.5, waterUse = 7, careUse = 5, yield = 7, maxQuality = 74, demand = 0.9,
                trait = 'Low maintenance, slower, lower quality ceiling' },
            nightbloom = { label = 'Nightbloom', growHours = 3.5, waterUse = 18, careUse = 14, yield = 4, maxQuality = 100, demand = 1.25,
                trait = 'Small yield, demanding care, prized by buyers' },
        },
    },
    coca = {
        label = 'Coca', seedItem = 'coca_seed', harvestItem = 'coca_leaf', containers = { 'ground', 'pot' },
        props = {
            ground = { 'prop_plant_01a', 'prop_plant_01b', 'prop_bush_med_03', 'prop_bush_lrg_01' },
            pot = { 'prop_plant_int_02a', 'prop_plant_int_02b', 'prop_plant_int_03a', 'prop_plant_int_04a' },
        },
        potProp = 'prop_pot_plant_05a',
        varieties = {
            andes_mist = { label = 'Andes Mist', growHours = 4.0, waterUse = 12, careUse = 10, yield = 5, maxQuality = 90, demand = 1.1,
                trait = 'High ceiling, average yield' },
            red_ridge = { label = 'Red Ridge', growHours = 4.0, waterUse = 10, careUse = 8, yield = 7, maxQuality = 70, demand = 0.95,
                trait = 'Large yield, lower quality ceiling' },
        },
    },
    mushroom = {
        label = 'Mushrooms', seedItem = 'mushroom_spores', harvestItem = 'mushroom_cap', containers = { 'tub' },
        tubItem = 'grow_tub',
        props = {
            tub = { 'prop_weed_tub_01', 'prop_weed_tub_01b', 'prop_weed_tub_01b', 'prop_weed_tub_01b' },
        },
        -- Mushrooms show their stage with a small cluster prop on top of the tub (stages 2-4).
        stageProps = { nil, 'prop_veg_crop_03_cab', 'prop_veg_crop_03_cab', 'prop_veg_crop_03_cab' },
        varieties = {
            mooncap = { label = 'Mooncap', growHours = 3.0, waterUse = 16, careUse = 6, yield = 4, maxQuality = 98, demand = 1.2,
                trait = 'Rare, thirsty, high ceiling' },
            forest_cap = { label = 'Forest Cap', growHours = 2.5, waterUse = 10, careUse = 5, yield = 6, maxQuality = 72, demand = 0.9,
                trait = 'Quick and forgiving' },
        },
    },
}

-- Fallback model when a configured prop does not exist in this game build (documented in docs/DRUGS.md).
DrugsFallbackProp = 'prop_plant_01a'
