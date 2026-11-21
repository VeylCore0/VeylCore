-- Placeable equipment and its recipes (fictional, abstract game mechanics only).
--
-- Recipe inputs: { item, count, batch = true } — batch inputs must all come from ONE stack (same variety/grade/batch);
-- the output keeps that batch's metadata. Counts are per unit; players pick 1..MaxUnits units.
-- challenge: 'timing' (stop the marker in the zone) or 'calibration' (hold the needle in the band).
-- The challenge only nudges quality (±ChallengeQuality); it never changes quantities.

DrugsEquipment = {
    MaxUnits = 5,                 -- units per job (small batches)
    ChallengeQuality = 5,         -- quality points a perfect / failed challenge adds / removes
    SteadyScore = 0.6,            -- score used when a player chooses "steady hands" (no challenge)
    WearPerJob = 2,               -- condition lost per job (cosmetic + up to -5 quality at 0 condition)
    MaxPerPlayer = 4,
    UseDistance = 2.5,
    PackMs = 5000,

    types = {
        weed_table = {
            label = 'Weed Table', item = 'weed_table', prop = 'bkr_prop_weed_table_01a',
            recipes = {
                {
                    id = 'roll_joints', label = 'Roll joints', icon = 'leaf', challenge = 'timing', msPerUnit = 2500,
                    inputs = { { item = 'weed_bud', count = 1, batch = true }, { item = 'rolling_papers', count = 1 } },
                    output = { item = 'joint', count = 2, product = 'weed' },
                },
                {
                    id = 'bag_weed', label = 'Bag weed', icon = 'bag', challenge = 'timing', msPerUnit = 3000,
                    inputs = { { item = 'weed_bud', count = 5, batch = true }, { item = 'empty_baggie', count = 1 } },
                    output = { item = 'weed_baggie', count = 1, product = 'weed' },
                },
            },
        },
        coke_table = {
            label = 'Coke Table', item = 'coke_table', prop = 'bkr_prop_coke_table01a',
            recipes = {
                {
                    id = 'process_coca', label = 'Process leaves', icon = 'sparkle', challenge = 'calibration', msPerUnit = 6000,
                    inputs = { { item = 'coca_leaf', count = 4, batch = true }, { item = 'lab_supplies', count = 1 } },
                    output = { item = 'coke_powder', count = 2, product = 'coke' },
                },
                {
                    id = 'bag_coke', label = 'Bag coke', icon = 'bag', challenge = 'timing', msPerUnit = 3000,
                    inputs = { { item = 'coke_powder', count = 2, batch = true }, { item = 'empty_baggie', count = 1 } },
                    output = { item = 'coke_baggie', count = 1, product = 'coke' },
                },
            },
        },
    },
}

-- Item -> equipment type
DrugsEquipmentByItem = {}
for id, t in pairs(DrugsEquipment.types) do
    t.id = id
    DrugsEquipmentByItem[t.item] = id
    for _, r in ipairs(t.recipes) do t.recipesById = t.recipesById or {} t.recipesById[r.id] = r end
end
