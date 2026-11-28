-- Supplier operations branch: take supply runs from a supplier, pick up an abstract crate and deliver it, then use the contents at a
-- portable supplier station or in a laboratory. A fictional hazard can build up around a working station. Everything here is invented game
-- logic: crates hold abstract "supply kits", the station turns them into abstract "compound" in timed stages, and there are no real
-- ingredients, steps or quantities anywhere.

ProductionConfig = ProductionConfig or {}

ProductionConfig.Supplier = {
    -- Where supplier gear is sold (protective gear and the portable station).
    Shop = {
        Id = 'supply_dealer', Branch = 'supplier', Label = 'Supply Dealer',
        Ped = { model = 'a_m_m_business_01', coords = vector4(-1175.6, -2845.8, 13.95, 240.0), scenario = 'WORLD_HUMAN_STAND_IMPATIENT', radius = 2.2, label = 'Supply Dealer' },
        RestockMinutes = 30,
        Items = {
            { item = 'prod_respirator',       price = 450,  stock = 10, restock = 2, level = 1 },
            { item = 'prod_supplier_station', price = 3200, stock = 4,  restock = 1, level = 2 },
        },
    },

    -- Suppliers hand out runs. `Hours` is the window they work (server clock, hour numbers; a window can cross midnight). The fee is a trade
    -- you pay to start. MaxRunsPerDay counts per player per UTC day.
    Suppliers = {
        {
            id = 'harbour_contact', label = 'Harbour contact', level = 1, fee = 250, MaxRunsPerDay = 6, Hours = { 0, 24 },
            Ped = { model = 'a_m_y_stbla_01', coords = vector4(1197.3, -3113.5, 5.54, 90.0), scenario = 'WORLD_HUMAN_SMOKING', radius = 2.2, label = 'Harbour contact' },
            TimeLimitMinutes = 20, KitsPerRun = { 2, 4 },
        },
        {
            id = 'night_contact', label = 'Night contact', level = 2, fee = 600, MaxRunsPerDay = 4, Hours = { 20, 6 },
            Ped = { model = 'a_m_y_stbla_02', coords = vector4(-1158.8, -2030.0, 13.16, 45.0), scenario = 'WORLD_HUMAN_STAND_MOBILE', radius = 2.2, label = 'Night contact' },
            TimeLimitMinutes = 18, KitsPerRun = { 4, 7 },
        },
    },

    -- Run variations: a pickup and a drop are chosen at random.
    Pickups = {
        { label = 'Container yard', coords = vector3(1205.6, -3117.9, 5.54) }, { label = 'Back lot', coords = vector3(-431.5, -2176.6, 10.32) },
        { label = 'Roadside shed', coords = vector3(2667.4, 1436.9, 24.5) }, { label = 'Quiet alley', coords = vector3(-1158.8, -2024.4, 13.16) },
    },
    Drops = {
        { label = 'Auto yard', coords = vector3(1017.8, -2528.4, 28.3) }, { label = 'Car park', coords = vector3(-1072.3, -1659.4, 4.39) },
        { label = 'Side street', coords = vector3(212.4, -808.8, 30.73) }, { label = 'Hill track', coords = vector3(1147.6, -470.3, 66.37) },
    },
    -- The crate goes on the bed of a pickup truck instead of in your arms. Back a truck up to the crate, load it, drive to the drop and unload.
    -- The server checks the truck's model, that it is next to the crate when you load and at the drop when you unload.
    --   Required = false  brings back carrying the crate on foot.
    --   Models: open-bed vehicles only. The crate sits at the back of the bed; BedY/BedZ fine-tune it per model (offsets from the vehicle centre).
    Truck = {
        Required = true,
        LoadRadius = 12.0, DropVehicleRadius = 10.0,
        Models = { 'bison', 'bison2', 'bison3', 'bobcatxl', 'sadler', 'sadler2', 'sandking', 'sandking2', 'rebel', 'rebel2', 'guardian', 'yosemite', 'contender', 'dloader', 'bodhi2', 'flatbed' },
        BedFromRear = 1.2,     -- metres in from the tail of the vehicle (default for any model)
        BedHeight = 0.5,       -- fraction of the vehicle's height where the bed floor is (default)
        Offsets = {},          -- per model, e.g. bison = vector3(0.0, -1.6, 0.35) (x, y, z from the vehicle's centre) when the default sits wrong
    },
    CrateModel = 'prop_box_wood02a',
    PickupRadius = 6.0, DropRadius = 6.0,
    FastBonus = { within = 0.55, mult = 1.25 },     -- finish within this share of the time limit for extra kits
    MaxSpeed = 70.0,                                 -- metres per second: a delivery faster than this over the distance is refused
    Cooldown = { Cancel = 120 },                     -- seconds before you can start again after cancelling a run
    -- What a run gives: abstract supply kits (amount comes from the supplier above).
    RewardItem = 'prod_supply_kit',

    -- Skill check at the station: the player does `Rounds` short checks (veyl_minigames when it is running) and the score moves the quality of the
    -- batch. Zero correct gives a reduced yield. The server times it (a check cannot be done faster than MinRoundSeconds) but the score itself comes
    -- from the client, so it can only change quality inside the swing below, never create items.
    Skill = { MinRoundSeconds = 2.0, QualitySwing = 12, ZeroYield = 0.6, Difficulty = 'medium' },

    -- The hazard (a game mechanic, nothing real): standing near a station that is working a hazardous recipe builds exposure. Protective gear
    -- cuts it. At the threshold you take damage until you step away.
    Hazard = {
        Enabled = true,
        Radius = 7.0, TickSeconds = 2, GainPerTick = 6, DecayPerTick = 4, Threshold = 70, Damage = 4,
        ProtectionItem = 'prod_respirator', ProtectionPercent = 0.8,
        WarnAt = 40,
    },

    -- What the buyer pays for supplier goods.
    Buyer = { prod_veylx = 420, prod_lsd = 210, prod_ecstasy = 160, prod_batch_pack = 240, prod_compound = 95 },
}
