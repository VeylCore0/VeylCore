ShopsConfig = {
    MaxPerLine = 20,
    MaxLines = 12,
    UseDistance = 3.0,

    Shops = {
        {
            id = '247_innocence', label = 'General Store', subtitle = 'Daily essentials.',
            ped = { model = 'mp_m_shopkeep_01', coords = vector4(24.47, -1346.62, 29.5, 271.66) },
            blip = { sprite = 52, colour = 27, name = '24/7 Supermarket' },
            methods = { 'cash', 'bank' },
            categories = { { id = 'food', label = 'Food' }, { id = 'drinks', label = 'Drinks' }, { id = 'tools', label = 'Tools' } },
            -- Prices are authoritative here (server). Items must exist in veyl_inventory/data/items.lua.
            catalog = {
                { item = 'water_bottle', price = 5, category = 'drinks' },
                { item = 'sandwich', price = 12, category = 'food' },
                { item = 'sprunk', price = 6, category = 'drinks', label = 'Soda' },
                { item = 'snack_bar', price = 4, category = 'food' },
                { item = 'bandage', price = 15, category = 'tools' },
                { item = 'first_aid_kit', price = 250, category = 'tools' },
                { item = 'gauze', price = 40, category = 'tools' },
                { item = 'painkillers', price = 60, category = 'tools' },
                { item = 'medkit', price = 450, category = 'tools' },
                { item = 'flashlight', price = 80, category = 'tools' },
                { item = 'radio', price = 250, category = 'tools' },
                { item = 'phone', price = 400, category = 'tools' },
                { item = 'repair_kit', price = 450, category = 'tools' },
            },
        },
        {
            id = '247_clinton', label = 'General Store', subtitle = 'Daily essentials.',
            ped = { model = 'mp_m_shopkeep_01', coords = vector4(372.66, 326.98, 103.57, 253.73) },
            blip = { sprite = 52, colour = 27, name = '24/7 Supermarket' },
            methods = { 'cash', 'bank' },
            categories = { { id = 'food', label = 'Food' }, { id = 'drinks', label = 'Drinks' }, { id = 'tools', label = 'Tools' } },
            catalog = {
                { item = 'water_bottle', price = 5, category = 'drinks' },
                { item = 'sandwich', price = 12, category = 'food' },
                { item = 'sprunk', price = 6, category = 'drinks', label = 'Soda' },
                { item = 'snack_bar', price = 4, category = 'food' },
                { item = 'bandage', price = 15, category = 'tools' },
                { item = 'first_aid_kit', price = 250, category = 'tools' },
                { item = 'gauze', price = 40, category = 'tools' },
                { item = 'painkillers', price = 60, category = 'tools' },
                { item = 'medkit', price = 450, category = 'tools' },
                { item = 'qbexample_token', price = 1, category = 'tools' },
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
