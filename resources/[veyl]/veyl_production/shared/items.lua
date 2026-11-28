-- The items this resource uses (names, labels, what they do). The inventory itself defines them in veyl_inventory/data/items.lua
-- (that is how VeylCore registers items); keep the names here and there in step. All items are fictional.

ProdItems = {
    seed_ember = 'prod_seed_ember', seed_violet = 'prod_seed_violet', seed_azure = 'prod_seed_azure',
    planter = 'prod_planter', water = 'prod_water', nutrient = 'prod_nutrient',
    leaf = 'prod_leaf', blend = 'prod_blend', pack = 'prod_pack', wild_herb = 'prod_wild_herb',
    workstation = 'prod_workstation', access_card = 'prod_access_card',
    -- field branch
    fseed_dawn = 'prod_fseed_dawn', fseed_dusk = 'prod_fseed_dusk', field_find = 'prod_field_find', field_bloom = 'prod_field_bloom', field_extract = 'prod_field_extract',
    field_pack = 'prod_field_pack', field_station = 'prod_field_station',
    -- supplier branch
    supply_kit = 'prod_supply_kit', respirator = 'prod_respirator', supplier_station = 'prod_supplier_station', compound = 'prod_compound', batch_pack = 'prod_batch_pack',
}

ProdItemLabels = {
    prod_seed_ember = 'Emberleaf Seeds', prod_seed_violet = 'Violetbloom Seeds', prod_seed_azure = 'Azurefern Seeds',
    prod_planter = 'Planter', prod_water = 'Clean Water', prod_nutrient = 'Growth Tonic',
    prod_leaf = 'Fresh Leaves', prod_blend = 'Leaf Blend', prod_pack = 'Packed Product', prod_wild_herb = 'Wild Herbs',
    prod_workstation = 'Prep Table', prod_access_card = 'Lab Access Card',
    prod_fseed_dawn = 'Dawnroot Seeds', prod_fseed_dusk = 'Duskvine Seeds', prod_field_find = 'Field Specimens', prod_field_bloom = 'Field Blooms',
    prod_field_extract = 'Field Extract', prod_field_pack = 'Field Goods', prod_field_station = 'Field Station',
    prod_supply_kit = 'Supply Kit', prod_respirator = 'Respirator', prod_supplier_station = 'Supplier Station', prod_compound = 'Compound', prod_batch_pack = 'Packed Batch',
}

-- Items whose metadata carries the product quality (see MetadataSchemas.prod_product in veyl_inventory).
ProdQualityItems = { prod_leaf = true, prod_blend = true, prod_pack = true, prod_field_bloom = true, prod_field_extract = true, prod_field_pack = true, prod_compound = true, prod_batch_pack = true }
