-- NOTE: coordinates are starting values. Verify them in-game with /vcoords (veyl_admin) and adjust.
DeliveryConfig = {
    Job = 'delivery',

    Depot = {
        ped = { model = 's_m_m_postal_01', coords = vector4(78.83, 111.95, 81.17, 159.5) },
        vanSpawn = vector4(66.85, 120.79, 79.09, 160.0),
        radius = 3.0,
        returnRadius = 35.0,   -- van must be this close to the depot for the completion bonus
    },

    VanModel = 'boxville2',
    StopsPerRun = 5,
    PayPerStop = 85,
    CompletionBonus = 150,
    MinSecondsBetweenStops = 15, -- server-side plausibility check
    StopRadius = 4.0,             -- 2D distance to the door when delivering
    PackageFromVanDistance = 6.0,

    Stops = {
        vector3(1060.52, -378.30, 68.23),
        vector3(1029.40, -408.40, 65.95),
        vector3(1010.47, -423.40, 65.35),
        vector3(987.50, -433.07, 63.89),
        vector3(967.10, -451.60, 62.40),
        vector3(943.40, -463.30, 61.40),
        vector3(1204.90, -557.70, 69.62),
        vector3(1241.55, -566.40, 69.66),
        vector3(1251.10, -621.50, 69.41),
        vector3(1265.80, -648.30, 67.92),
        vector3(1100.60, -411.40, 67.56),
        vector3(1114.30, -391.20, 68.95),
    },
}
