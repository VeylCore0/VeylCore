-- veyl_prison configuration (Bolingbroke Penitentiary).

PrisonConfig = {
    PoliceJobs = { 'police' },        -- on-duty members can sentence (/jail) and release (/release)
    SecondsPerMonth = 60,             -- one sentenced "month" passes every minute you are online
    MaxMonths = 300,
    JailDistance = 10.0,              -- /jail: how close the officer must be

    -- Where prisoners are placed, where they leave, and the grounds they cannot leave.
    Inside = vector4(1691.6, 2565.6, 45.56, 180.0),
    Release = vector4(1848.13, 2586.05, 45.67, 269.5),
    Grounds = { center = vector3(1690.0, 2580.0, 45.0), radius = 150.0 },

    -- Yard work: each finished job takes time off the sentence.
    Work = {
        MonthsOff = 1,
        Seconds = 15,
        CooldownSeconds = 45,
        Spots = {
            { coords = vector3(1700.6, 2533.9, 45.56), label = 'Sweep the yard', scenario = 'WORLD_HUMAN_JANITOR' },
            { coords = vector3(1653.4, 2546.8, 45.56), label = 'Pick up litter', scenario = 'WORLD_HUMAN_GARDENER_PLANT' },
            { coords = vector3(1718.4, 2566.2, 45.56), label = 'Fix the fence', scenario = 'WORLD_HUMAN_WELDING' },
        },
    },
}
