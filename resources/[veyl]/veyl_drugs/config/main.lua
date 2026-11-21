-- veyl_drugs: general configuration. All production in this resource is fictional game mechanics.
DrugsConfig = {
    Debug = false,

    -- Placement (weed / coca / mushroom tubs). Everything here is re-checked on the server.
    Placement = {
        MaxDistance = 4.0,          -- how far in front of you the preview can be
        MaxSlopeDegrees = 22.0,     -- steeper ground is refused
        MinSpacing = 1.1,           -- metres between any two plants
        RotateStep = 5.0,           -- degrees per R press / scroll notch
        AllowInteriors = false,     -- interiors are refused unless a property adapter approves (no property system yet)
        RequirePotIndoors = true,   -- inside an approved interior you must use a pot or tub
        MaxPerPlayer = 30,          -- plants (incl. tubs) one character may own
        MaxNearby = 24,             -- plants of anyone within CrowdRadius of the new spot
        CrowdRadius = 20.0,
    },

    -- No planting inside these spheres (police stations, hospitals, busy public squares...).
    RestrictedZones = {
        { label = 'Mission Row PD', coords = vector3(441.0, -982.0, 30.7), radius = 90.0 },
        { label = 'Pillbox Medical', coords = vector3(300.0, -585.0, 43.3), radius = 90.0 },
        { label = 'Legion Square', coords = vector3(195.0, -934.0, 30.7), radius = 75.0 },
        { label = 'City Hall', coords = vector3(-545.0, -204.0, 38.2), radius = 70.0 },
        { label = 'Sandy Shores Sheriff', coords = vector3(1853.0, 3686.0, 34.3), radius = 55.0 },
        { label = 'Paleto Bay Sheriff', coords = vector3(-448.0, 6012.0, 31.7), radius = 55.0 },
    },

    -- Streaming: clients receive plants within this radius; props spawn within SpawnRadius.
    Stream = { Radius = 120.0, SpawnRadius = 90.0, MaxSent = 250, RefreshMs = 4000, MoveThreshold = 15.0 },

    -- Growth simulation (server). Hours are real hours. Offline = no owner (or crew member) online.
    Growth = {
        TickMinutes = 5,            -- in-memory advance interval
        FlushMinutes = 10,          -- changed plants are written to the database this often (and on every action)
        DryThreshold = 15,          -- water/care at or below this counts as neglected
        NeglectGrowthFactor = 0.35, -- growth speed while neglected
        HealthLossPerHour = 6.0,    -- while water or care is empty
        HealthGainPerHour = 3.0,    -- while cared for
        Offline = {
            DecayMultiplier = 0.25, -- water/care drain 4x slower while nobody responsible is online
            HealthFloor = 40,       -- a plant never drops below this health while its owner is offline (never dies offline)
        },
        ReadyWindowHours = 48,      -- a ready plant stays at full value this long; after that it slowly wilts
        OverripeHealthPerHour = 1.0,
        OverripeHealthFloor = 25,
    },

    -- Quality grades from the care score (0-100), capped by the variety's maximum.
    Grades = {
        { id = 'exotic', label = 'Exotic', min = 85 },
        { id = 'premium', label = 'Premium', min = 60 },
        { id = 'standard', label = 'Standard', min = 0 },
    },

    -- Water / care items (players use them on a plant through the target menu).
    CareItems = { water = 'water_bottle', care = 'plant_food' },
    ActionMs = { water = 3500, care = 4500, harvest = 6000, destroy = 4000, place = 1800 },
    InteractDistance = 2.6,

    -- Supplier NPC (seeds, pots, tubs, nutrients, journal). Stock is limited and restocks over time.
    Supplier = {
        label = 'Garden Supplier', model = 'a_m_m_hillbilly_01',
        coords = vector4(2196.24, 5598.83, 53.74, 340.0),   -- Grapeseed fields; move it in config if your map differs
        methods = { 'cash' },
        restockMinutes = 30,
        stock = {
            { item = 'weed_seed', variety = 'violet_haze', price = 60, max = 40, restock = 6 },
            { item = 'weed_seed', variety = 'silverleaf', price = 45, max = 40, restock = 6 },
            { item = 'weed_seed', variety = 'nightbloom', price = 110, max = 15, restock = 2 },
            { item = 'weed_seed', variety = 'sunburst', price = 75, max = 30, restock = 5 },
            { item = 'coca_seed', variety = 'andes_mist', price = 90, max = 25, restock = 4 },
            { item = 'coca_seed', variety = 'red_ridge', price = 70, max = 25, restock = 4 },
            { item = 'mushroom_spores', variety = 'mooncap', price = 120, max = 12, restock = 2 },
            { item = 'mushroom_spores', variety = 'forest_cap', price = 80, max = 20, restock = 3 },
            { item = 'plant_pot', price = 40, max = 20, restock = 4 },
            { item = 'grow_tub', price = 150, max = 8, restock = 2 },
            { item = 'plant_food', price = 25, max = 60, restock = 10 },
            { item = 'grow_journal', price = 300, max = 10, restock = 2 },
        },
    },

    -- Adapters (see docs/DRUGS.md). Only integrations that really exist on this server are enabled.
    Adapters = {
        Property = 'none',          -- no property/housing resource yet: interiors follow Placement.AllowInteriors
        Phone = 'standalone',       -- messages appear in the Grow Journal tablet
        Police = { jobs = { 'police' }, requireDuty = true },
    },

    Journal = { RequireItem = 'grow_journal', Command = 'growjournal' },
}
