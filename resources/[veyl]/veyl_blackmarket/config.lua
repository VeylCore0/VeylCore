-- veyl_blackmarket: every illegal item in one place. Prices, stock and who may buy are decided here and enforced by the server.
-- `item` must be a veyl_inventory item. `stock` is how many the dealer holds (it restocks `restock` per `RestockMinutes`, default 1/5 of stock).
-- `level` is the street reputation needed (veyl_production progression); 0 = anyone. Delete a line to stop selling that item.

BlackmarketConfig = {
    Payment = 'cash',            -- money type charged
    Distance = 4.0,              -- how close you must stand to the dealer (server checked)
    PurchaseCooldown = 1,        -- seconds between purchases
    MaxPerLine = 50,             -- most of one item in a single purchase
    RestockMinutes = 30,
    Access = { Item = nil },     -- e.g. 'usb_darkweb' to only serve people carrying that item. nil = anyone who finds a dealer
    Police = { Enabled = false, Chance = 0.25, Resource = 'veyl_dispatch', Export = 'Alert', Code = '10-31', Message = 'Suspicious meeting reported' },

    Dealers = {
        { id = 'docks', label = 'Dock Fixer', ped = { model = 's_m_y_dockwork_01', coords = vector4(1244.6, -3295.5, 5.5, 270.0), scenario = 'WORLD_HUMAN_SMOKING' },
          blip = { show = false, sprite = 110, colour = 1, label = 'Dealer' } },
        { id = 'junkyard', label = 'Scrapyard Dealer', ped = { model = 'a_m_m_hillbilly_01', coords = vector4(2340.8, 3126.4, 48.2, 350.0), scenario = 'WORLD_HUMAN_STAND_IMPATIENT' },
          blip = { show = false, sprite = 110, colour = 1, label = 'Dealer' } },
    },

    Categories = {
        { id = 'pistols', label = 'Pistols', icon = 'gun' },
        { id = 'smgs', label = 'SMGs', icon = 'gun' },
        { id = 'long', label = 'Shotguns & Rifles', icon = 'gun' },
        { id = 'melee', label = 'Melee', icon = 'blade' },
        { id = 'ammo', label = 'Ammo & Mods', icon = 'box' },
        { id = 'drugs', label = 'Drugs', icon = 'pill' },
        { id = 'lab', label = 'Lab Supplies', icon = 'flask' },
        { id = 'tools', label = 'Break-in Tools', icon = 'key' },
        { id = 'hacking', label = 'Hacking & Fraud', icon = 'chip' },
    },

    Catalog = {
        -- Pistols
        { item = 'weapon_appistol', price = 9500, category = 'pistols', stock = 6, level = 0 },
        { item = 'weapon_pistol50', price = 8800, category = 'pistols', stock = 6, level = 0 },
        { item = 'weapon_heavypistol', price = 7200, category = 'pistols', stock = 8, level = 0 },
        { item = 'weapon_ceramicpistol', price = 8000, category = 'pistols', stock = 6, level = 0 },
        { item = 'weapon_machinepistol', price = 12500, category = 'pistols', stock = 4, level = 2 },
        { item = 'weapon_revolver', price = 10500, category = 'pistols', stock = 4, level = 1 },
        -- SMGs
        { item = 'weapon_microsmg', price = 14500, category = 'smgs', stock = 4, level = 1 },
        { item = 'weapon_smg', price = 19500, category = 'smgs', stock = 3, level = 2 },
        { item = 'weapon_assaultsmg', price = 24000, category = 'smgs', stock = 2, level = 3 },
        { item = 'weapon_combatpdw', price = 26000, category = 'smgs', stock = 2, level = 3 },
        { item = 'weapon_minismg', price = 13500, category = 'smgs', stock = 3, level = 1 },
        { item = 'weapon_gusenberg', price = 42000, category = 'smgs', stock = 1, level = 5 },
        -- Shotguns and rifles
        { item = 'weapon_sawnoffshotgun', price = 11000, category = 'long', stock = 4, level = 1 },
        { item = 'weapon_assaultshotgun', price = 32000, category = 'long', stock = 2, level = 4 },
        { item = 'weapon_bullpupshotgun', price = 28000, category = 'long', stock = 2, level = 3 },
        { item = 'weapon_heavyshotgun', price = 36000, category = 'long', stock = 1, level = 5 },
        { item = 'weapon_assaultrifle', price = 38000, category = 'long', stock = 2, level = 4 },
        { item = 'weapon_carbinerifle', price = 41000, category = 'long', stock = 2, level = 4 },
        { item = 'weapon_advancedrifle', price = 46000, category = 'long', stock = 1, level = 5 },
        { item = 'weapon_specialcarbine', price = 48000, category = 'long', stock = 1, level = 5 },
        { item = 'weapon_bullpuprifle', price = 40000, category = 'long', stock = 2, level = 4 },
        { item = 'weapon_compactrifle', price = 34000, category = 'long', stock = 2, level = 4 },
        { item = 'weapon_marksmanrifle', price = 62000, category = 'long', stock = 1, level = 6 },
        { item = 'weapon_sniperrifle', price = 70000, category = 'long', stock = 1, level = 6 },
        { item = 'weapon_heavysniper', price = 95000, category = 'long', stock = 1, level = 7 },
        -- Melee
        { item = 'weapon_knuckle', price = 600, category = 'melee', stock = 10, level = 0 },
        { item = 'weapon_switchblade', price = 800, category = 'melee', stock = 10, level = 0 },
        { item = 'weapon_dagger', price = 2500, category = 'melee', stock = 3, level = 0 },
        { item = 'weapon_battleaxe', price = 1800, category = 'melee', stock = 3, level = 0 },
        -- Ammo and attachments
        { item = 'ammo_pistol', price = 9, category = 'ammo', stock = 400, restock = 60, level = 0 },
        { item = 'ammo_smg', price = 11, category = 'ammo', stock = 300, restock = 50, level = 1 },
        { item = 'ammo_shotgun', price = 16, category = 'ammo', stock = 200, restock = 30, level = 1 },
        { item = 'ammo_rifle', price = 18, category = 'ammo', stock = 300, restock = 40, level = 3 },
        { item = 'ammo_sniper', price = 45, category = 'ammo', stock = 60, restock = 10, level = 5 },
        { item = 'att_suppressor', price = 4500, category = 'ammo', stock = 5, level = 2 },
        { item = 'att_extmag', price = 2500, category = 'ammo', stock = 8, level = 1 },
        { item = 'att_scope', price = 3200, category = 'ammo', stock = 5, level = 2 },
        { item = 'att_grip', price = 1800, category = 'ammo', stock = 5, level = 1 },
        { item = 'att_flashlight', price = 900, category = 'ammo', stock = 8, level = 0 },
        -- Drugs (finished product; growing and cooking them yourself is cheaper)
        { item = 'weed_baggie', price = 140, category = 'drugs', stock = 40, restock = 10, level = 0 },
        { item = 'joint', price = 25, category = 'drugs', stock = 80, restock = 20, level = 0 },
        { item = 'coke_baggie', price = 420, category = 'drugs', stock = 25, restock = 5, level = 1 },
        { item = 'meth_baggie', price = 380, category = 'drugs', stock = 25, restock = 5, level = 1 },
        { item = 'ecstasy_pill', price = 85, category = 'drugs', stock = 60, restock = 10, level = 1 },
        { item = 'lsd_tab', price = 110, category = 'drugs', stock = 40, restock = 8, level = 2 },
        { item = 'veylx_vial', price = 1500, category = 'drugs', stock = 8, restock = 1, level = 4 },
        -- Lab supplies
        { item = 'chem_precursor', price = 260, category = 'lab', stock = 30, restock = 5, level = 1 },
        { item = 'chem_solvent', price = 180, category = 'lab', stock = 30, restock = 5, level = 1 },
        { item = 'lab_glassware', price = 650, category = 'lab', stock = 10, restock = 2, level = 1 },
        -- Break-in tools
        { item = 'lockpick', price = 220, category = 'tools', stock = 20, restock = 4, level = 0 },
        { item = 'door_ram', price = 3500, category = 'tools', stock = 4, level = 2 },
        { item = 'drill', price = 2800, category = 'tools', stock = 4, level = 2 },
        { item = 'thermite', price = 4200, category = 'tools', stock = 5, restock = 1, level = 3 },
        { item = 'spray_paint', price = 150, category = 'tools', stock = 20, restock = 4, level = 0 },
        { item = 'fake_plate', price = 1800, category = 'tools', stock = 6, restock = 1, level = 1 },
        -- Hacking and fraud
        { item = 'hacking_device', price = 6500, category = 'hacking', stock = 3, restock = 1, level = 3 },
        { item = 'usb_darkweb', price = 3000, category = 'hacking', stock = 4, restock = 1, level = 2 },
        { item = 'radio', price = 450, category = 'hacking', stock = 10, level = 0 },
    },
}
