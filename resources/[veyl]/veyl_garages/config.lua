GaragesConfig = {
    UseRadius = 3.0,     -- how close to the garage sign/counter you must be to open it
    ParkRadius = 35.0,   -- the "Park in garage" option shows on your vehicles within this distance of a garage
    PaymentMethods = { 'cash', 'bank' },

    -- Public garages. spawns are tried in order; the first clear one is used.
    -- Coordinates are the standard GTA parking lots used by common garage scripts; adjust if a spot is blocked.
    Garages = {
        { id = 'legion', label = 'Legion Square Parking', coords = vector3(215.95, -809.70, 30.73),
          spawns = { vector4(222.02, -804.19, 30.26, 248.43), vector4(223.93, -799.20, 30.26, 248.43), vector4(226.27, -794.24, 30.26, 248.43) } },
        { id = 'pinkcage', label = 'Pink Cage Parking', coords = vector3(273.00, -343.85, 44.91),
          spawns = { vector4(270.75, -340.51, 44.92, 342.03), vector4(267.39, -339.38, 44.92, 342.03) } },
        { id = 'sandy', label = 'Sandy Shores Parking', coords = vector3(1737.60, 3710.20, 34.14),
          spawns = { vector4(1737.84, 3719.28, 33.04, 21.22) } },
        { id = 'paleto', label = 'Paleto Bay Parking', coords = vector3(107.32, 6611.77, 31.98),
          spawns = { vector4(110.84, 6607.82, 31.86, 265.28) } },
    },

    -- Impounded vehicles (abandoned, wrecked or impounded by staff) are released here for their fee.
    Impound = { id = 'impound', label = 'Impound Lot', coords = vector3(400.45, -1630.87, 29.29),
        spawns = { vector4(407.20, -1645.58, 29.31, 228.28), vector4(404.02, -1649.27, 29.31, 228.28) } },

    Blips = {
        garage = { sprite = 357, colour = 27, scale = 0.65 },
        impound = { sprite = 68, colour = 27, scale = 0.7 },
    },
}
