ShopsConfig = {
    MaxPerPurchase = 20,
    UseDistance = 3.0,

    Shops = {
        {
            id = '247_innocence', label = '24/7 Supermarket',
            ped = { model = 'mp_m_shopkeep_01', coords = vector4(24.47, -1346.62, 29.5, 271.66) },
            blip = { sprite = 52, colour = 27 },
            catalog = {
                { item = 'water_bottle', price = 4 },
                { item = 'cola', price = 5 },
                { item = 'coffee', price = 6 },
                { item = 'sandwich', price = 8 },
                { item = 'burger', price = 12 },
                { item = 'bandage', price = 25 },
                { item = 'phone', price = 300 },
            },
        },
        {
            id = '247_clinton', label = '24/7 Supermarket',
            ped = { model = 'mp_m_shopkeep_01', coords = vector4(372.66, 326.98, 103.57, 253.73) },
            blip = { sprite = 52, colour = 27 },
            catalog = {
                { item = 'water_bottle', price = 4 },
                { item = 'cola', price = 5 },
                { item = 'sandwich', price = 8 },
                { item = 'burger', price = 12 },
                { item = 'bandage', price = 25 },
            },
        },
    },
}
