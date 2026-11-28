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
    prod_seed_ember = 'Violet Haze Seeds', prod_seed_violet = 'Silverleaf Seeds', prod_seed_azure = 'Nightbloom Seeds',
    prod_planter = 'Planter', prod_water = 'Clean Water', prod_nutrient = 'Growth Tonic',
    prod_leaf = 'Weed Bud', prod_blend = 'Trimmed Bud', prod_pack = 'Bagged Weed', prod_wild_herb = 'Wild Herbs',
    prod_workstation = 'Weed Table', prod_access_card = 'Lab Access Card',
    prod_fseed_dawn = 'Red Ridge Seeds', prod_fseed_dusk = 'Andes Mist Seeds', prod_field_find = 'Wild Mushrooms', prod_field_bloom = 'Coca Leaf',
    prod_field_extract = 'Coke', prod_field_pack = 'Bagged Coke', prod_field_station = 'Coke Table',
    prod_supply_kit = 'Chemical Supplies', prod_respirator = 'Respirator', prod_supplier_station = 'Meth Station', prod_compound = 'Crystal', prod_batch_pack = 'Bagged Meth',
}

-- Items whose metadata carries the product quality (see MetadataSchemas.prod_product in veyl_inventory).
ProdQualityItems = { prod_leaf = true, prod_blend = true, prod_pack = true, prod_field_bloom = true, prod_field_extract = true, prod_field_pack = true, prod_compound = true, prod_batch_pack = true }
