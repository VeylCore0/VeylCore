VehiclesConfig = {
    ImpoundFee = 500,          -- release fee for owned vehicles that were abandoned or wrecked
    WreckClearMs = 120000,     -- a wrecked owned vehicle stays in the world this long before it is towed away
    MaxPropsBytes = 8000,      -- largest saved vehicle-properties payload accepted from a client

    -- Storage (veyl_inventory stashes per vehicle; owned vehicles keep their contents)
    Trunk = { slots = 30, maxWeight = 120000, distance = 4.0 },
    Glovebox = { slots = 6, maxWeight = 8000, key = '' },     -- key: optional default keybind; /glovebox always works

    -- Custom plates: drive in and stay seated. Price is charged from the bank.
    PlateShop = { coords = vector4(-31.4, -1089.0, 26.4, 340.0), radius = 6.0, price = 5000,
        blocked = { 'LSPD', 'POLICE', 'SHERIFF', 'EMS', 'ADMIN' } },

    -- Insurance: wrecked or abandoned insured vehicles go to the impound with no fee and fully repaired.
    Insurance = { coords = vector4(-1083.0, -245.8, 37.76, 210.0), model = 'a_m_y_business_02', weekly = 350, maxWeeks = 8 },
}
