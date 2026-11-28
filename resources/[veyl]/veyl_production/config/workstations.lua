-- Workstations: placeable benches that turn items into other items over timed stages. A recipe is just a fictional token swap:
-- inputs -> staged timers -> outputs, with a quality roll. Nothing models a real process.
--   levels: `branch` level needed; stages: { label, seconds }; quality: how input quality and skill carry over.

ProductionConfig = ProductionConfig or {}

ProductionConfig.Workstations = {
    -- What a refund gives back when a batch is cancelled while running (a batch that has not started refunds in full).
    RunningRefund = 0.5,
    -- Types. `item` is the inventory item that places one; `model` is the prop. `slots` = queue length. `speed` multiplies stage time
    -- (lower is faster). `qualityBonus` adds points to every roll. Laboratory benches get their capacity from the property's upgrades.
    Types = {
        prep_table = {
            label = 'Portable Prep Table', item = 'prod_workstation', model = 'prop_tool_bench02', branch = 'botanical',
            slots = 3, speed = 1.0, qualityBonus = 0, portable = true,
        },
        lab_bench = {
            label = 'Laboratory Bench', item = 'prod_workstation', model = 'prop_tool_bench02', branch = 'botanical',
            slots = 4, speed = 0.85, qualityBonus = 4, portable = false,
        },
    },
    Recipes = {
        blend = {
            label = 'Blend Leaves', branch = 'botanical', level = 1, xp = 15, types = { 'prep_table', 'lab_bench' },
            inputs = { { item = 'prod_leaf', count = 4 } },
            stages = { { label = 'Sorting', seconds = 20 }, { label = 'Blending', seconds = 30 } },
            output = { item = 'prod_blend', count = 2 },
        },
        pack = {
            label = 'Pack Product', branch = 'botanical', level = 2, xp = 20, types = { 'prep_table', 'lab_bench' },
            inputs = { { item = 'prod_blend', count = 2 } },
            stages = { { label = 'Weighing', seconds = 15 }, { label = 'Sealing', seconds = 20 } },
            output = { item = 'prod_pack', count = 3 },
        },
        tonic = {
            label = 'Mix Growth Tonic', branch = 'botanical', level = 1, xp = 8, types = { 'prep_table', 'lab_bench' },
            inputs = { { item = 'prod_wild_herb', count = 3 } },
            stages = { { label = 'Steeping', seconds = 25 } },
            output = { item = 'prod_nutrient', count = 2 }, noQuality = true,
        },
    },
}
