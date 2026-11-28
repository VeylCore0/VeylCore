-- The items this resource uses (names, labels, what they do). The inventory itself defines them in veyl_inventory/data/items.lua
-- (that is how VeylCore registers items); keep the names here and there in step. All items are fictional.

ProdItems = {
    seed_ember = 'prod_seed_ember', seed_violet = 'prod_seed_violet', seed_azure = 'prod_seed_azure',
    planter = 'prod_planter', water = 'prod_water', nutrient = 'prod_nutrient',
    leaf = 'prod_leaf', blend = 'prod_blend', pack = 'prod_pack', wild_herb = 'prod_wild_herb',
    workstation = 'prod_workstation', access_card = 'prod_access_card',
}

ProdItemLabels = {
    prod_seed_ember = 'Emberleaf Seeds', prod_seed_violet = 'Violetbloom Seeds', prod_seed_azure = 'Azurefern Seeds',
    prod_planter = 'Planter', prod_water = 'Clean Water', prod_nutrient = 'Growth Tonic',
    prod_leaf = 'Fresh Leaves', prod_blend = 'Leaf Blend', prod_pack = 'Packed Product', prod_wild_herb = 'Wild Herbs',
    prod_workstation = 'Prep Table', prod_access_card = 'Lab Access Card',
}

-- Items whose metadata carries the product quality (see MetadataSchemas.prod_product in veyl_inventory).
ProdQualityItems = { prod_leaf = true, prod_blend = true, prod_pack = true }
