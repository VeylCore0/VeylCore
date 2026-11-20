VehiclesConfig = {
    LockDistance = 8.0,

    -- Fuel is tracked for VeylCore-spawned vehicles only (ambient traffic is unaffected).
    FuelTickMs = 5000,
    FuelIdleUse = 0.05,      -- per tick with engine running
    FuelSpeedUse = 0.006,    -- extra per tick per m/s

    FuelPricePerUnit = 3,    -- whole dollars per 1% of tank, paid in cash
    FuelStations = {
        vector3(265.65, -1261.31, 29.29),
        vector3(-724.62, -935.16, 19.21),
        vector3(1181.38, -330.85, 69.32),
        vector3(-70.21, -1761.79, 29.53),
        vector3(819.65, -1028.85, 26.40),
    },
    FuelStationRadius = 12.0,
}
