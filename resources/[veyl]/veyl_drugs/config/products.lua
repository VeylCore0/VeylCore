-- Products and varieties (fictional). Growth hours are real hours; yields are item counts.
-- waterUse / careUse: meter points lost per hour while someone responsible is online.
-- maxQuality caps the quality a variety can reach (0-100); demand is used by buyers (milestone D).
-- Props: a list of 4 stages (1 = seedling ... 4 = ready) per container. Each entry is a model name or
-- { model = '...', scale = 0.5 } (scaled visually; used when a product has only one plant model).
-- A variety may set its own `props` (same shape) to override the product's. Missing models fall back to
-- DrugsFallbackProp with one console warning.

--- veyl_weedprops (custom stream resource, must be started before veyl_drugs): an_weed_<colour>_<size>.
local function weedStages(colour)
    local p = 'an_weed_' .. colour
    return { p .. '_01_small_01a', p .. '_01_small_01c', p .. '_med_01b', p .. '_lrg_01b' }
end

-- Base-game coca bush from the Cayo Perico Heist update (no download needed); grown in four sizes.
local COCA = 'h4_prop_bush_cocaplant_01'
local cocaStages = { { model = COCA, scale = 0.35 }, { model = COCA, scale = 0.6 }, { model = COCA, scale = 0.85 }, { model = COCA, scale = 1.0 } }
local cocaPotStages = { { model = COCA, scale = 0.3 }, { model = COCA, scale = 0.45 }, { model = COCA, scale = 0.6 }, { model = COCA, scale = 0.72 } }

DrugsProducts = {
    weed = {
        label = 'Cannabis', seedItem = 'weed_seed', harvestItem = 'weed_bud', containers = { 'ground', 'pot' },
        -- Base-game Biker DLC weed, used only if a variety has no props of its own.
        props = {
            ground = { 'bkr_prop_weed_01_small_01b', 'bkr_prop_weed_med_01a', 'bkr_prop_weed_lrg_01a', 'bkr_prop_weed_lrg_01b' },
            pot = { 'bkr_prop_weed_01_small_01a', 'bkr_prop_weed_01_small_01c', 'bkr_prop_weed_med_01b', 'bkr_prop_weed_lrg_01b' },
        },
        potProp = 'bkr_prop_weed_bucket_01a',
        varieties = {
            violet_haze = { label = 'Violet Haze', growHours = 3.0, waterUse = 14, careUse = 9, yield = 6, maxQuality = 92, demand = 1.0,
                trait = 'Balanced all-rounder', props = { ground = weedStages('purple'), pot = weedStages('purple') } },
            silverleaf = { label = 'Silverleaf', growHours = 4.5, waterUse = 7, careUse = 5, yield = 7, maxQuality = 74, demand = 0.9,
                trait = 'Low maintenance, slower, lower quality ceiling', props = { ground = weedStages('white'), pot = weedStages('white') } },
            nightbloom = { label = 'Nightbloom', growHours = 3.5, waterUse = 18, careUse = 14, yield = 4, maxQuality = 100, demand = 1.25,
                trait = 'Small yield, demanding care, prized by buyers', props = { ground = weedStages('blue'), pot = weedStages('blue') } },
            sunburst = { label = 'Sunburst', growHours = 2.5, waterUse = 20, careUse = 8, yield = 5, maxQuality = 84, demand = 1.05,
                trait = 'Fast, but very thirsty', props = { ground = weedStages('yellow'), pot = weedStages('yellow') } },
        },
    },
    coca = {
        label = 'Coca', seedItem = 'coca_seed', harvestItem = 'coca_leaf', containers = { 'ground', 'pot' },
        props = { ground = cocaStages, pot = cocaPotStages },
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

--- Stage props for a plant: the variety's own props, else the product's. Returns a list of 4 entries.
function DrugsStageProps(productId, varietyId, container)
    local prod = DrugsProducts[productId]
    if not prod then return nil end
    local v = prod.varieties[varietyId]
    local set = (v and v.props) or prod.props
    return set[container] or set.ground or prod.props[container] or prod.props.ground
end

--- Normalises a prop entry to model, scale.
function DrugsPropEntry(entry)
    if type(entry) == 'table' then return entry.model, entry.scale or 1.0 end
    return entry, 1.0
end
