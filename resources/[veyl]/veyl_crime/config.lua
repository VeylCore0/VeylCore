-- veyl_crime configuration: black market (dark web app + dead drops), fence, money laundering, drug corners,
-- turf and tags, gang stashes, drug labs and branding. Money in whole dollars.

CrimeConfig = {
    PoliceJobs = { 'police' },

    -- Dark web: a phone app that only opens with this item in your pockets. Orders are paid in cash and picked up
    -- at a random dead drop.
    DarkWeb = {
        UnlockItem = 'usb_darkweb',
        DropMinutes = 30,              -- how long an order waits at its drop
        Catalog = {
            { item = 'lockpick', price = 150 }, { item = 'thermite', price = 2500 }, { item = 'hacking_device', price = 3000 },
            { item = 'drill', price = 2000 }, { item = 'spray_paint', price = 50 },
            { item = 'chem_precursor', price = 120 }, { item = 'chem_solvent', price = 80 }, { item = 'lab_glassware', price = 600 },
            { item = 'att_suppressor', price = 3500 }, { item = 'att_extmag', price = 1500 }, { item = 'att_scope', price = 1200 },
            { item = 'att_flashlight', price = 400 }, { item = 'att_grip', price = 800 },
            -- Unregistered weapons (no serial number)
            { item = 'weapon_machinepistol', price = 9000 }, { item = 'weapon_microsmg', price = 11000 }, { item = 'weapon_smg', price = 14000 },
            { item = 'weapon_sawnoffshotgun', price = 8000 }, { item = 'weapon_assaultrifle', price = 25000 }, { item = 'weapon_carbinerifle', price = 28000 },
            { item = 'ammo_smg', price = 6 }, { item = 'ammo_rifle', price = 8 },
        },
        Drops = {
            vector3(-1185.6, -1555.4, 4.36), vector3(476.9, -1278.3, 29.54), vector3(1240.5, -3242.1, 5.9),
            vector3(-571.3, 5254.0, 70.47), vector3(2340.6, 3127.1, 48.21), vector3(-36.7, -1823.6, 26.1),
        },
    },
    -- Where to buy the USB drive (a shady contact, cash).
    UsbDealer = { coords = vector4(-1157.9, -1520.6, 4.36, 33.0), model = 'g_m_y_mexgoon_02', price = 5000 },

    -- Fence: buys jewelry for cash.
    Fence = { coords = vector4(1129.4, -989.7, 45.97, 280.0), model = 's_m_y_dealer_01', prices = { rolex = 600, gold_chain = 400, diamond_ring = 900 } },

    -- Money laundering: marked bills in, clean cash out.
    Laundering = { coords = vector3(-1190.2, -1403.1, 4.33), fee = 0.30, maxPerRun = 5000, seconds = 20, cooldownMinutes = 10 },

    -- Drug corners: offer drugs to locals. price = per unit at quality 100 (scaled by quality, minimum 40 %).
    Corners = {
        CooldownSeconds = 18,
        Chance = { buy = 0.65, refuse = 0.20, police = 0.15 },
        MaxUnits = 3,
        Products = {
            weed_baggie = 90, joint = 40, coke_baggie = 220, meth_baggie = 260, ecstasy_pill = 120, lsd_tab = 140, veylx_vial = 380,
        },
    },

    -- Turf: selling and tagging in a zone builds your gang's rep there; the gang with the most rep controls it and
    -- its members get a better price. Rep fades by DecayPercent every day.
    Turf = {
        ControlBonus = 0.20, SaleRep = 2, TagRep = 25, TagCooldownMinutes = 30, DecayPercent = 10,
        Zones = {
            { id = 'grove', label = 'Grove Street', center = vector3(103.0, -1938.0, 20.8), radius = 180.0 },
            { id = 'davis', label = 'Davis', center = vector3(237.0, -1713.0, 29.2), radius = 200.0 },
            { id = 'rancho', label = 'Rancho', center = vector3(437.0, -1858.0, 27.7), radius = 200.0 },
            { id = 'vespucci', label = 'Vespucci Beach', center = vector3(-1205.0, -1560.0, 4.4), radius = 220.0 },
            { id = 'mirrorpark', label = 'Mirror Park', center = vector3(1143.0, -510.0, 64.0), radius = 220.0 },
            { id = 'sandy', label = 'Sandy Shores', center = vector3(1880.0, 3720.0, 33.0), radius = 300.0 },
        },
    },

    -- Gang stashes (members only).
    GangStashes = {
        lostmc = { label = 'Lost MC stash', coords = vector3(983.4, -103.0, 74.85) },
    },

    -- Drug labs: chemicals in, branded product out. Quality is random within the range.
    Labs = {
        { label = 'Meth lab', coords = vector3(1391.9, 3605.9, 38.94), seconds = 25,
          recipe = { output = 'meth_baggie', count = 10, quality = { 45, 100 }, inputs = { chem_precursor = 2, chem_solvent = 1 } } },
        { label = 'Pill press', coords = vector3(-1102.4, -1640.2, 4.64), seconds = 20,
          recipe = { output = 'ecstasy_pill', count = 15, quality = { 50, 100 }, inputs = { chem_precursor = 1, chem_solvent = 1 } } },
        { label = 'Blotter lab', coords = vector3(2433.7, 4968.9, 42.35), seconds = 20,
          recipe = { output = 'lsd_tab', count = 20, quality = { 50, 100 }, inputs = { chem_precursor = 1, chem_solvent = 2 } } },
        { label = 'Veyl-X lab', coords = vector3(-1150.6, 4940.3, 222.27), seconds = 40,
          recipe = { output = 'veylx_vial', count = 6, quality = { 60, 100 }, inputs = { chem_precursor = 3, chem_solvent = 2, lab_glassware = 1 } } },
    },
    BrandMaxLength = 20,
}
