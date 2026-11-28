-- Laboratories (properties): bought, owned, upgraded, shared with employees, locked with codes. Each property is a private instance of an
-- interior (a routing bucket of its own), so one interior can serve many properties. The default interior is the base game's
-- Biker DLC warehouse interior, loaded through its IPL; swap `interiors` entries for any MLO.

ProductionConfig = ProductionConfig or {}

ProductionConfig.Properties = {
    BucketBase = 41000,              -- routing buckets used for lab instances (BucketBase + property index)
    SellBackPercent = 0.6,           -- selling returns this share of the price paid
    BuybackHours = 24,               -- the previous owner can buy it back for BuybackPercent of the sale price
    BuybackPercent = 1.05,
    MaxEmployees = 4, MaxGuests = 6,
    MaxOwned = 2,                    -- laboratories one player can own at once
    Code = { MinLength = 4, MaxLength = 8, MaxAttempts = 5, LockoutSeconds = 300 },
    RequireAccessCard = false,       -- true: entering also needs the prod_access_card item
    TransferSeconds = 45,            -- how long a transfer offer stays open
    BaseStorage = { slots = 40, maxWeight = 120000 },
    BaseBenchSlots = 2,              -- laboratory benches allowed (upgrades add more)

    Interiors = {
        biker_warehouse = {
            ipl = 'bkr_biker_interior_placement_interior_3_biker_dlc_int_ware02_milo',
            spawn = vector4(1066.0, -3183.4, -39.2, 90.0),   -- where you appear inside
            door = vector3(1066.3, -3183.4, -39.2),          -- the inside exit point
            radius = 40.0,                                   -- things can be placed within this distance of `spawn`
        },
        -- Other Biker DLC interiors for the field and supplier labs. These are the usual coordinates for them: check them in game.
        biker_field = {
            ipl = 'bkr_biker_interior_placement_interior_2_biker_dlc_int_ware01_milo',
            spawn = vector4(1093.6, -3196.6, -38.99, 0.0), door = vector3(1088.7, -3188.1, -38.99), radius = 40.0,
        },
        biker_supplier = {
            ipl = 'bkr_biker_interior_placement_interior_4_biker_dlc_int_ware03_milo',
            spawn = vector4(997.0, -3200.0, -36.4, 270.0), door = vector3(997.3, -3200.5, -36.4), radius = 40.0,
        },
    },

    -- A map blip on each laboratory you own or work at (and only those). Set Show = false to turn them off.
    Blip = { Show = true, Sprite = 473, Colour = 25, Scale = 0.85, Label = 'Laboratory' },

    -- Properties for sale. `entry` is the street door (a vector4). Add as many as you like.
    Catalogue = {
        { id = 'puerta_lab', label = 'La Puerta Lab', interior = 'biker_warehouse', price = 60000, level = 1, branch = 'botanical',
          entry = vector4(-1158.8, -2024.4, 13.16, 45.0), description = 'A quiet unit near the old docks. The cheapest way in.' },
        { id = 'elysian_lab', label = 'Elysian Lab', interior = 'biker_warehouse', price = 85000, level = 2, branch = 'botanical',
          entry = vector4(1205.6, -3117.9, 5.54, 90.0), description = 'Warehouse space by the container yards.' },
        { id = 'harmony_lab', label = 'Harmony Lab', interior = 'biker_warehouse', price = 110000, level = 3, branch = 'botanical',
          entry = vector4(2667.4, 1436.9, 24.5, 0.0), description = 'A big shed in the desert. Far from prying eyes.' },
        { id = 'alamo_lab', label = 'Alamo Field Lab', interior = 'biker_field', price = 70000, level = 1, branch = 'field',
          entry = vector4(1730.2, 3312.0, 41.2, 195.0), description = 'A quiet shed out by the Alamo Sea for field work.' },
        { id = 'sandy_lab', label = 'Sandy Field Lab', interior = 'biker_field', price = 105000, level = 3, branch = 'field',
          entry = vector4(1392.4, 3601.7, 34.9, 200.0), description = 'A bigger field lab with room to grow.' },
        { id = 'docks_lab', label = 'Docks Supplier Lab', interior = 'biker_supplier', price = 95000, level = 2, branch = 'supplier',
          entry = vector4(1245.0, -3150.0, 5.5, 270.0), description = 'A unit at the docks, close to your suppliers.' },
        { id = 'rail_lab', label = 'Railyard Supplier Lab', interior = 'biker_supplier', price = 130000, level = 3, branch = 'supplier',
          entry = vector4(480.0, -1980.0, 24.5, 30.0), description = 'A railside warehouse with plenty of space.' },
    },

    -- Upgrades: levels in order. `price` is for that level. Effects: storage { slots, maxWeight } extra, benches (+ slots),
    -- equipment { quality, speed } (bonus applied to every bench in the lab), security (breach seconds added; level 1 also alerts the owner).
    Upgrades = {
        storage = { label = 'Storage capacity', icon = 'box', levels = {
            { price = 15000, slots = 15, maxWeight = 60000 }, { price = 30000, slots = 30, maxWeight = 150000 }, { price = 55000, slots = 50, maxWeight = 300000 } } },
        benches = { label = 'Workstation slots', icon = 'bench', levels = {
            { price = 20000, slots = 1 }, { price = 40000, slots = 2 }, { price = 70000, slots = 3 } } },
        equipment = { label = 'Equipment', icon = 'gear', levels = {
            { price = 25000, quality = 3, speed = 0.95 }, { price = 50000, quality = 6, speed = 0.9 }, { price = 90000, quality = 10, speed = 0.8 } } },
        security = { label = 'Security', icon = 'shield', levels = {
            { price = 12000, breachSeconds = 20 }, { price = 28000, breachSeconds = 45 }, { price = 60000, breachSeconds = 90 } } },
    },
}
