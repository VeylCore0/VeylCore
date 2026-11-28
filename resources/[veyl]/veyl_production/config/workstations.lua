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
        field_station = {
            label = 'Portable Field Station', item = 'prod_field_station', model = 'prop_tool_bench02', branch = 'field', slots = 3, speed = 1.0, qualityBonus = 0, portable = true,
        },
        field_lab_bench = {
            label = 'Field Laboratory Bench', item = 'prod_field_station', model = 'prop_tool_bench02', branch = 'field', slots = 4, speed = 0.85, qualityBonus = 4, portable = false,
        },
        supplier_station = {
            label = 'Portable Supplier Station', item = 'prod_supplier_station', model = 'prop_tool_bench02', branch = 'supplier', slots = 3, speed = 1.0, qualityBonus = 0, portable = true,
        },
        supplier_lab_bench = {
            label = 'Supplier Laboratory Bench', item = 'prod_supplier_station', model = 'prop_tool_bench02', branch = 'supplier', slots = 4, speed = 0.85, qualityBonus = 4, portable = false,
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
        extract = {
            label = 'Press Field Blooms', branch = 'field', level = 1, xp = 15, types = { 'field_station', 'field_lab_bench' },
            inputs = { { item = 'prod_field_bloom', count = 3 } },
            stages = { { label = 'Sorting', seconds = 20 }, { label = 'Pressing', seconds = 30 } },
            output = { item = 'prod_field_extract', count = 2 },
        },
        pack_field = {
            label = 'Pack Field Goods', branch = 'field', level = 3, xp = 20, types = { 'field_station', 'field_lab_bench' },
            inputs = { { item = 'prod_field_extract', count = 2 } },
            stages = { { label = 'Weighing', seconds = 15 }, { label = 'Sealing', seconds = 20 } },
            output = { item = 'prod_field_pack', count = 3 },
        },
        sift = {
            label = 'Sift Field Finds', branch = 'field', level = 2, xp = 8, types = { 'field_station', 'field_lab_bench' },
            inputs = { { item = 'prod_field_find', count = 4 } },
            stages = { { label = 'Sifting', seconds = 25 } },
            output = { item = 'prod_fseed_dawn', count = 1 }, noQuality = true,
        },
        synthesize = {
            label = 'Process Supply Kits', branch = 'supplier', level = 1, xp = 22, types = { 'supplier_station', 'supplier_lab_bench' }, hazard = true,
            skill = { rounds = 3 },
            inputs = { { item = 'prod_supply_kit', count = 2 } },
            stages = { { label = 'Calibrating', seconds = 25 }, { label = 'Reacting', seconds = 40 }, { label = 'Settling', seconds = 20 } },
            output = { item = 'prod_compound', count = 2 },
        },
        finish = {
            label = 'Finish Compound', branch = 'supplier', level = 2, xp = 22, types = { 'supplier_station', 'supplier_lab_bench' },
            skill = { rounds = 2 },
            inputs = { { item = 'prod_compound', count = 2 } },
            stages = { { label = 'Measuring', seconds = 20 }, { label = 'Sealing', seconds = 25 } },
            output = { item = 'prod_batch_pack', count = 3 },
        },
    },
}
