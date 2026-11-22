-- veyl_customs configuration (shared: nothing secret lives here). Prices are whole dollars and are always computed on
-- the server from this file; the client only ever sends which options it wants.

CustomsConfig = {
    Debug = false,                     -- enables /customsdebug (staff only); keep false in production

    QuoteMinutes = 5,                  -- a self-service quote is valid this long
    SentQuoteHours = 24,               -- a mechanic quote that was sent expires after this long
    SessionMinutes = 20,               -- a customisation session is closed after this long without activity
    PaymentTiming = 'on_approval',     -- mechanic orders: the customer pays when approving (see docs for the refund policy)
    PaymentMethods = { 'bank', 'cash' },

    -- Performance level caps (the game may offer fewer levels for a model; the menu only shows what exists).
    Performance = { [11] = 3, [12] = 2, [13] = 2, [15] = 3, [16] = 4 },

    -- Prices --------------------------------------------------------------------------------------------------
    Prices = {
        -- performance mods: price per level (index 0 = level 1)
        perf = {
            [11] = { 2500, 5500, 9500, 14000 },        -- engine
            [12] = { 1200, 2600, 4200 },               -- brakes
            [13] = { 1800, 3600, 5800 },               -- transmission
            [15] = { 900, 1800, 2900, 4200 },          -- suspension
            [16] = { 2500, 5000, 8000, 11000, 15000 }, -- armour
        },
        turbo = 12000,
        cosmetic = { base = 450, perIndex = 120, max = 4500 }, -- indexed cosmetic mods: base + index * perIndex (capped)
        slotBase = { [0] = 900, [1] = 650, [2] = 650, [3] = 600, [4] = 700, [7] = 800, [10] = 700, [23] = 1100, [24] = 900, [14] = 300, [48] = 1500 },
        wheelType = 0, customTyres = 650, wheelColor = 400, tyreSmokeToggle = 800, tyreSmoke = 300,
        paintPrimary = 1200, paintSecondary = 800, paintCustomExtra = 400, pearl = 650,
        xenon = 1500, xenonColor = 450, neon = 2000, neonColor = 400,
        windowTint = 500, plateIndex = 300, livery = 1500, extra = 250, interiorColor = 600, dashboardColor = 400,
        stock = 0,                                   -- going back to the stock part is free
    },

    -- Parts used by mechanic-operated shops with stock (one per installed line of that kind). cost = reorder price.
    Parts = {
        perf_engine = { label = 'Engine kit', cost = 1800, deliveryMinutes = 20 },
        perf_brakes = { label = 'Brake kit', cost = 700, deliveryMinutes = 10 },
        perf_transmission = { label = 'Transmission kit', cost = 1100, deliveryMinutes = 15 },
        perf_suspension = { label = 'Suspension kit', cost = 600, deliveryMinutes = 10 },
        perf_turbo = { label = 'Turbo kit', cost = 4500, deliveryMinutes = 30 },
        body_kit = { label = 'Body panel kit', cost = 250, deliveryMinutes = 10 },
        wheel_set = { label = 'Wheel set', cost = 400, deliveryMinutes = 10 },
        paint_can = { label = 'Paint supplies', cost = 150, deliveryMinutes = 5 },
        light_kit = { label = 'Lighting kit', cost = 300, deliveryMinutes = 10 },
    },

    -- Work interactions (mechanic installs one line at a time near the vehicle).
    InstallSeconds = { performance = 9, bodywork = 7, wheels = 6, paint = 10, lighting = 5, details = 4 },

    -- Shops ---------------------------------------------------------------------------------------------------
    -- mode: 'self' (customers buy directly), 'mechanic' (staff quote, customer approves), or 'both'.
    -- selfFallback: in a 'mechanic' shop, customers may self-serve while no staff member is on duty.
    -- preview: where the local preview copy of the vehicle is placed (needs open floor; the real car is untouched).
    -- business: veyl_business id whose account receives the money (nil = the money is not credited anywhere).
    -- stock: true = mechanic installs use the shop's part stock (Parts above).
    Shops = {
        {
            id = 'lsc_burton', label = 'LS Customs', sub = 'Burton Workshop', mode = 'both', job = 'mechanic', manageGrade = 2,
            coords = vector3(-337.39, -136.92, 39.01), radius = 25.0,
            entry = vector3(-337.4, -136.9, 39.0),        -- self-service entrance (drive in, press E)
            desk = vector3(-347.29, -133.27, 39.01),       -- dashboard / requests
            preview = vector4(-337.4, -136.9, 38.6, 90.0),
            bays = {
                { id = '01', coords = vector3(-326.1, -144.0, 39.0) },
                { id = '02', coords = vector3(-321.7, -132.5, 39.0) },
                { id = '03', coords = vector3(-333.4, -151.2, 39.0) },
            },
            selfFallback = true, laborRate = 0.10, taxRate = 0.0, priceMultiplier = 1.0, stock = true,
            business = nil,
            categories = { performance = true, bodywork = true, wheels = true, paint = true, lighting = true, details = true },
            blip = { sprite = 72, colour = 2 },
        },
        {
            id = 'tuner', label = 'Tuner Shop', sub = 'Strawberry', mode = 'mechanic', job = 'tunershop', manageGrade = 1,
            coords = vector3(-205.9, -1312.7, 31.3), radius = 25.0,
            entry = vector3(-212.7, -1324.0, 30.9),
            desk = vector3(-196.6, -1318.3, 31.1),
            preview = vector4(-212.7, -1324.0, 30.5, 0.0),
            bays = { { id = '01', coords = vector3(-212.7, -1324.0, 30.9) }, { id = '02', coords = vector3(-222.4, -1329.4, 30.9) } },
            selfFallback = false, laborRate = 0.12, taxRate = 0.0, priceMultiplier = 1.15, stock = true,
            business = 'tunershop',
            categories = { performance = true, bodywork = true, wheels = true, paint = true, lighting = true, details = true },
            blip = { sprite = 446, colour = 5 },
        },
        {
            id = 'bennys_self', label = "Benny's Self-Service", sub = 'Strawberry', mode = 'self',
            coords = vector3(-1155.0, -2007.0, 13.2), radius = 15.0,
            entry = vector3(-1155.0, -2007.0, 13.2),
            preview = vector4(-1155.0, -2007.0, 12.8, 315.0),
            bays = {}, laborRate = 0.0, taxRate = 0.05, priceMultiplier = 1.25, stock = false,
            categories = { performance = false, bodywork = true, wheels = true, paint = true, lighting = true, details = true },
            blip = { sprite = 72, colour = 3 },
        },
    },

    -- Named paired colour presets in the Paint Studio (primary / secondary as hex).
    PaintPresets = {
        { name = 'Mint & pearl', primary = '#A5F3D0', secondary = '#F7FAFC' },
        { name = 'Dusty rose', primary = '#F3A6C8', secondary = '#202326' },
        { name = 'Midnight', primary = '#151719', secondary = '#3A3F44' },
        { name = 'Sand', primary = '#E9DFC9', secondary = '#8C7B62' },
        { name = 'Deep teal', primary = '#1F6F78', secondary = '#0E2A2E' },
    },
    MaxSwatches = 12,
    MaxBuilds = 20,

    -- Lighting previews (client-local through veyl_world; the server's time/weather never changes).
    Lighting = {
        studio = { hour = 12, minute = 0, weather = 'EXTRASUNNY' },
        daylight = { hour = 14, minute = 0, weather = 'CLEAR' },
        sunset = { hour = 19, minute = 30, weather = 'CLEAR' },
        night = { hour = 23, minute = 0, weather = 'CLEAR' },
    },
}
