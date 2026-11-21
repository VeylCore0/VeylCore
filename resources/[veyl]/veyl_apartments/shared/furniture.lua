-- Furniture catalog. Every model below was checked against the base-game object list (ObjectList.ini) before it was
-- added. The client also checks IsModelInCdimage before placing and greys out anything missing on that game build.
-- Only listed models can ever be placed (the server rejects anything else).

AptFurnitureCategories = {
    { id = 'seating', label = 'Seating' }, { id = 'beds', label = 'Beds' }, { id = 'tables', label = 'Tables' },
    { id = 'storage', label = 'Shelves & units' }, { id = 'lighting', label = 'Lighting' }, { id = 'kitchen', label = 'Kitchen' },
    { id = 'electronics', label = 'Electronics' }, { id = 'decor', label = 'Decor' },
}

AptFurniture = {
    -- Seating
    sofa_two = { label = 'Two-seat sofa', model = 'apa_mp_h_stn_sofa2seat_02', category = 'seating', price = 900 },
    sofa_corner = { label = 'Corner sofa', model = 'apa_mp_h_stn_sofacorn_01', category = 'seating', price = 1600 },
    daybed = { label = 'Daybed', model = 'apa_mp_h_stn_sofa_daybed_01', category = 'seating', price = 1100 },
    armchair = { label = 'Armchair', model = 'apa_mp_h_stn_chairarm_01', category = 'seating', price = 450 },
    armchair_lounge = { label = 'Lounge armchair', model = 'apa_mp_h_yacht_armchair_01', category = 'seating', price = 650 },
    office_chair = { label = 'Office chair', model = 'prop_off_chair_01', category = 'seating', price = 220 },
    dining_chair = { label = 'Dining chair', model = 'apa_mp_h_din_chair_04', category = 'seating', price = 180 },
    old_couch = { label = 'Worn couch', model = 'prop_rub_couch01', category = 'seating', price = 120 },
    -- Beds
    bed_double = { label = 'Double bed', model = 'apa_mp_h_bed_double_08', category = 'beds', price = 1400 },
    bed_wide = { label = 'Wide bed', model = 'apa_mp_h_bed_wide_05', category = 'beds', price = 1800 },
    bed_tables = { label = 'Bed with side tables', model = 'apa_mp_h_bed_with_table_02', category = 'beds', price = 2200 },
    -- Tables
    dining_table = { label = 'Dining table', model = 'apa_mp_h_din_table_04', category = 'tables', price = 600 },
    coffee_table = { label = 'Coffee table', model = 'apa_mp_h_tab_coffee_07', category = 'tables', price = 350 },
    side_table = { label = 'Side table', model = 'apa_mp_h_tab_sidesml_01', category = 'tables', price = 150 },
    side_table_lg = { label = 'Large side table', model = 'apa_mp_h_tab_sidelrg_04', category = 'tables', price = 260 },
    -- Shelves & units (decorative: they do not hold items)
    sideboard = { label = 'Sideboard', model = 'apa_mp_h_str_sideboardl_06', category = 'storage', price = 700 },
    sideboard_m = { label = 'Small sideboard', model = 'apa_mp_h_str_sideboardm_02', category = 'storage', price = 480 },
    shelf_floor = { label = 'Floor shelf', model = 'apa_mp_h_str_shelffloorm_02', category = 'storage', price = 420 },
    tv_unit = { label = 'TV unit', model = 'apa_mp_h_str_avunitm_01', category = 'storage', price = 520 },
    chest_drawer = { label = 'Chest of drawers', model = 'apa_mp_h_bed_chestdrawer_02', category = 'storage', price = 540 },
    wardrobe = { label = 'Wardrobe', model = 'v_res_tre_wardrobe', category = 'storage', price = 600 },
    dressing_table = { label = 'Dressing table', model = 'v_res_d_dressingtable', category = 'storage', price = 480 },
    -- Lighting (decorative; the light itself depends on the model)
    floor_lamp = { label = 'Floor lamp', model = 'apa_mp_h_floorlamp_a', category = 'lighting', price = 240 },
    floor_lamp_b = { label = 'Arc floor lamp', model = 'apa_mp_h_floorlamp_c', category = 'lighting', price = 300 },
    table_lamp = { label = 'Table lamp', model = 'apa_mp_h_lit_lamptable_005', category = 'lighting', price = 110 },
    -- Kitchen
    fridge = { label = 'Fridge', model = 'prop_fridge_01', category = 'kitchen', price = 650 },
    cooker = { label = 'Cooker', model = 'prop_cooker_03', category = 'kitchen', price = 550 },
    microwave = { label = 'Microwave', model = 'prop_micro_01', category = 'kitchen', price = 120 },
    coffee_machine = { label = 'Coffee machine', model = 'prop_coffee_mac_02', category = 'kitchen', price = 160 },
    toaster = { label = 'Toaster', model = 'prop_toaster_01', category = 'kitchen', price = 45 },
    kettle = { label = 'Kettle', model = 'prop_kettle', category = 'kitchen', price = 35 },
    washer = { label = 'Washing machine', model = 'prop_washer_02', category = 'kitchen', price = 480 },
    -- Electronics
    tv = { label = 'Flat-screen TV', model = 'prop_tv_flat_01', category = 'electronics', price = 800 },
    tv_small = { label = 'Small TV', model = 'prop_tv_flat_03', category = 'electronics', price = 380 },
    speaker = { label = 'Speaker', model = 'prop_speaker_06', category = 'electronics', price = 200 },
    laptop = { label = 'Laptop', model = 'prop_laptop_01a', category = 'electronics', price = 900 },
    monitor = { label = 'Monitor', model = 'prop_monitor_w_large', category = 'electronics', price = 350 },
    -- Decor
    plant_tall = { label = 'Tall plant', model = 'apa_mp_h_acc_plant_tall_01', category = 'decor', price = 140 },
    plant_palm = { label = 'Palm', model = 'apa_mp_h_acc_plant_palm_01', category = 'decor', price = 160 },
    rug_medium = { label = 'Wool rug', model = 'apa_mp_h_acc_rugwoolm_03', category = 'decor', price = 220 },
    rug_large = { label = 'Large rug', model = 'apa_mp_h_acc_rugwooll_04', category = 'decor', price = 300 },
    vase_flowers = { label = 'Flowers', model = 'apa_mp_h_acc_vase_flowers_01', category = 'decor', price = 60 },
    vase = { label = 'Vase', model = 'apa_mp_h_acc_vase_05', category = 'decor', price = 70 },
    candles = { label = 'Candles', model = 'apa_mp_h_acc_candles_01', category = 'decor', price = 40 },
    fruit_bowl = { label = 'Fruit bowl', model = 'apa_mp_h_acc_fruitbowl_01', category = 'decor', price = 45 },
    art_large = { label = 'Wall art (large)', model = 'apa_mp_h_acc_artwalll_01', category = 'decor', price = 450 },
    art_medium = { label = 'Wall art', model = 'apa_mp_h_acc_artwallm_02', category = 'decor', price = 280 },
}
