-- veyl_shops configuration. Prices are authoritative here (server). Items must exist in veyl_inventory
-- (data/items.lua or data/weapons.lua); unknown items are hidden from the catalog.
-- Each store type shares one catalog below; the store list underneath only places clerks.

local MARKET_CATEGORIES = { { id = 'food', label = 'Food' }, { id = 'drinks', label = 'Drinks' }, { id = 'tools', label = 'Tools' } }

local MARKET = {
    { item = 'water_bottle', price = 5, category = 'drinks' },
    { item = 'sprunk', price = 6, category = 'drinks', label = 'Soda' },
    { item = 'coffee', price = 8, category = 'drinks' },
    { item = 'sandwich', price = 12, category = 'food' },
    { item = 'snack_bar', price = 4, category = 'food' },
    { item = 'burger', price = 15, category = 'food' },
    { item = 'bandage', price = 15, category = 'tools' },
    { item = 'first_aid_kit', price = 250, category = 'tools' },
    { item = 'gauze', price = 40, category = 'tools' },
    { item = 'painkillers', price = 60, category = 'tools' },
    { item = 'medkit', price = 450, category = 'tools' },
    { item = 'flashlight', price = 80, category = 'tools' },
    { item = 'radio', price = 250, category = 'tools' },
    { item = 'phone', price = 400, category = 'tools' },
    { item = 'sim_card', price = 50, category = 'tools' },
    { item = 'repair_kit', price = 450, category = 'tools' },
    { item = 'fishing_rod', price = 150, category = 'tools' },
    { item = 'fishing_bait', price = 3, category = 'tools' },
    { item = 'qbexample_token', price = 1, category = 'tools' },
}

-- Rob's Liquor: drinks and snacks only.
local LIQUOR = {
    { item = 'water_bottle', price = 6, category = 'drinks' },
    { item = 'sprunk', price = 7, category = 'drinks', label = 'Soda' },
    { item = 'coffee', price = 9, category = 'drinks' },
    { item = 'snack_bar', price = 5, category = 'food' },
    { item = 'sandwich', price = 14, category = 'food' },
}

local AMMU_CATEGORIES = { { id = 'pistols', label = 'Pistols' }, { id = 'long', label = 'Long guns' }, { id = 'melee', label = 'Melee' }, { id = 'ammo', label = 'Ammo' } }

-- Ammu-Nation sells legal civilian weapons. A weapon licence (City Hall / police) is required.
local AMMUNATION = {
    { item = 'weapon_pistol', price = 2500, category = 'pistols' },
    { item = 'weapon_snspistol', price = 1800, category = 'pistols' },
    { item = 'weapon_combatpistol', price = 3200, category = 'pistols' },
    { item = 'weapon_heavypistol', price = 4000, category = 'pistols' },
    { item = 'weapon_vintagepistol', price = 3500, category = 'pistols' },
    { item = 'weapon_pistol50', price = 5500, category = 'pistols' },
    { item = 'weapon_revolver', price = 6000, category = 'pistols' },
    { item = 'weapon_pumpshotgun', price = 7500, category = 'long' },
    { item = 'weapon_dbshotgun', price = 6000, category = 'long' },
    { item = 'weapon_musket', price = 5000, category = 'long' },
    { item = 'weapon_knife', price = 250, category = 'melee' },
    { item = 'weapon_bat', price = 150, category = 'melee' },
    { item = 'weapon_hatchet', price = 400, category = 'melee' },
    { item = 'weapon_machete', price = 450, category = 'melee' },
    { item = 'weapon_knuckle', price = 300, category = 'melee' },
    { item = 'weapon_switchblade', price = 350, category = 'melee' },
    { item = 'ammo_pistol', price = 3, category = 'ammo' },
    { item = 'ammo_shotgun', price = 6, category = 'ammo' },
}

local function market(id, label, name, coords, sprite, colour, catalog)
    return {
        id = id, label = label, subtitle = 'Daily essentials.',
        ped = { model = 'mp_m_shopkeep_01', coords = coords },
        blip = { sprite = sprite, colour = colour, name = name },
        methods = { 'cash', 'bank' }, categories = MARKET_CATEGORIES, catalog = catalog or MARKET,
        robbable = true, -- veyl_robbery: the register (and the safe in RobberyConfig.Safes) can be robbed
    }
end

local function ammunation(id, area, coords)
    return {
        id = 'ammu_' .. id, label = 'Ammu-Nation', subtitle = area,
        ped = { model = 's_m_y_ammucity_01', coords = coords },
        blip = { sprite = 110, colour = 1, name = 'Ammu-Nation' },
        methods = { 'cash', 'bank' }, categories = AMMU_CATEGORIES, catalog = AMMUNATION,
        licence = 'weapon', licenceMessage = 'You need a weapon licence to buy here (City Hall or the police).',
    }
end

ShopsConfig = {
    MaxPerLine = 20,
    MaxLines = 12,
    UseDistance = 3.0,

    Shops = {
        -- 24/7 Supermarkets
        market('247_innocence', 'General Store', '24/7 Supermarket', vector4(24.47, -1346.62, 29.5, 271.66), 52, 2),
        market('247_clinton', 'General Store', '24/7 Supermarket', vector4(372.66, 326.98, 103.57, 253.73), 52, 2),
        market('247_ineseno', 'General Store', '24/7 Supermarket', vector4(-3039.54, 584.38, 7.91, 17.27), 52, 2),
        market('247_barbareno', 'General Store', '24/7 Supermarket', vector4(-3242.97, 1000.01, 12.83, 357.57), 52, 2),
        market('247_paleto', 'General Store', '24/7 Supermarket', vector4(1728.07, 6416.63, 35.04, 247.45), 52, 2),
        market('247_sandy', 'General Store', '24/7 Supermarket', vector4(1959.82, 3740.48, 32.34, 301.57), 52, 2),
        market('247_route68', 'General Store', '24/7 Supermarket', vector4(549.13, 2670.85, 42.16, 99.39), 52, 2),
        market('247_senora', 'General Store', '24/7 Supermarket', vector4(2677.47, 3279.76, 55.24, 335.08), 52, 2),
        market('247_palomino', 'General Store', '24/7 Supermarket', vector4(2556.66, 380.84, 108.62, 356.67), 52, 2),

        -- LTD Gasoline
        market('ltd_grove', 'LTD Gasoline', 'LTD Gasoline', vector4(-47.02, -1758.23, 29.42, 45.05), 52, 5),
        market('ltd_littleseoul', 'LTD Gasoline', 'LTD Gasoline', vector4(-706.06, -913.97, 19.22, 88.04), 52, 5),
        market('ltd_richman', 'LTD Gasoline', 'LTD Gasoline', vector4(-1820.02, 794.03, 138.09, 135.45), 52, 5),
        market('ltd_mirrorpark', 'LTD Gasoline', 'LTD Gasoline', vector4(1164.71, -322.94, 69.21, 101.72), 52, 5),
        market('ltd_grapeseed', 'LTD Gasoline', 'LTD Gasoline', vector4(1697.87, 4922.96, 42.06, 324.71), 52, 5),

        -- Rob's Liquor
        market('robs_vespucci', "Rob's Liquor", "Rob's Liquor", vector4(-1221.58, -908.15, 12.33, 35.49), 93, 0, LIQUOR),
        market('robs_morningwood', "Rob's Liquor", "Rob's Liquor", vector4(-1486.59, -377.68, 40.16, 139.51), 93, 0, LIQUOR),
        market('robs_banham', "Rob's Liquor", "Rob's Liquor", vector4(-2966.39, 391.42, 15.04, 87.48), 93, 0, LIQUOR),
        market('robs_harmony', "Rob's Liquor", "Rob's Liquor", vector4(1165.17, 2710.88, 38.16, 179.43), 93, 0, LIQUOR),
        market('robs_elrancho', "Rob's Liquor", "Rob's Liquor", vector4(1134.2, -982.91, 46.42, 277.24), 93, 0, LIQUOR),

        -- Ammu-Nation
        ammunation('littleseoul', 'Little Seoul', vector4(-661.96, -933.53, 21.83, 177.05)),
        ammunation('cypress', 'Cypress Flats', vector4(809.68, -2159.13, 29.62, 1.43)),
        ammunation('sandy', 'Sandy Shores', vector4(1692.67, 3761.38, 34.71, 227.65)),
        ammunation('paleto', 'Paleto Bay', vector4(-331.23, 6085.37, 31.45, 228.02)),
        ammunation('hawick', 'Hawick', vector4(253.63, -51.02, 69.94, 72.91)),
        ammunation('pillbox', 'Pillbox Hill (range)', vector4(23.0, -1105.67, 29.8, 162.91)),
        ammunation('tataviam', 'Tataviam Mountains', vector4(2567.48, 292.59, 108.73, 349.68)),
        ammunation('route68', 'Route 68', vector4(-1118.59, 2700.05, 18.55, 221.89)),
        ammunation('lamesa', 'La Mesa', vector4(841.92, -1035.32, 28.19, 1.56)),
        ammunation('morningwood', 'Morningwood', vector4(-1304.19, -395.12, 36.7, 75.03)),
        ammunation('chumash', 'Chumash', vector4(-3173.31, 1088.85, 20.84, 244.18)),

        {
            -- Hunting supplies (Paleto). Rifles need a hunting licence from City Hall.
            id = 'hunting_store', label = 'Hunting Supplies', subtitle = 'Rifles need a hunting licence.',
            ped = { model = 's_m_m_ammucountry', coords = vector4(-679.4, 5838.9, 17.3, 225.0) },
            blip = { sprite = 141, colour = 25, name = 'Hunting Supplies' },
            licence = 'hunting', licenceMessage = 'You need a hunting licence (City Hall).',
            methods = { 'cash', 'bank' },
            categories = { { id = 'gear', label = 'Gear' } },
            catalog = {
                { item = 'weapon_musket', price = 3500, category = 'gear' },
                { item = 'ammo_shotgun', price = 6, category = 'gear' },
                { item = 'weapon_knife', price = 200, category = 'gear' },
            },
        },
        {
            -- Hardware: tools for the new jobs and crafting.
            id = 'hardware', label = 'YouTool', subtitle = 'Tools and supplies.',
            ped = { model = 's_m_m_lathandy_01', coords = vector4(2748.5, 3468.9, 55.7, 250.0) },
            blip = { sprite = 566, colour = 5, name = 'YouTool' },
            methods = { 'cash', 'bank' },
            categories = { { id = 'tools', label = 'Tools' } },
            catalog = {
                { item = 'pickaxe', price = 350, category = 'tools' },
                { item = 'weapon_knife', price = 250, category = 'tools' },
                { item = 'flashlight', price = 60, category = 'tools' },
                { item = 'plant_pot', price = 25, category = 'tools' },
            },
        },
        {
            -- Mechanic parts counter at LS Customs (Burton). Only members of the mechanic job can buy here.
            id = 'mechanic_parts', label = 'Parts Counter', subtitle = 'Mechanics only.',
            ped = { model = 's_m_m_autoshop_01', coords = vector4(-345.17, -128.75, 39.01, 162.0) },
            groups = { mechanic = 0 },
            methods = { 'cash', 'bank' },
            categories = { { id = 'parts', label = 'Parts' } },
            catalog = {
                { item = 'engine_parts', price = 120, category = 'parts' },
                { item = 'body_panels', price = 90, category = 'parts' },
                { item = 'tyre_kit', price = 60, category = 'parts' },
                { item = 'cleaning_kit', price = 15, category = 'parts' },
            },
        },
    },
}
