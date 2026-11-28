-- veyl_cartheft: stealing cars. Ambient cars (parked or driven by pedestrians) are locked. You get into one by
--   * pointing a gun at the driver (they hand over the keys),
--   * or picking the lock of a parked car with a lockpick (a tumbler minigame) and then hotwiring it (a wiring minigame).
-- Cars VeylCore manages (owned, dealer, job, mission vehicles) are never touched. Loot in the trunk and glovebox is in the tables at the bottom.

CartheftConfig = {
    -- Ambient cars are locked as they come into range. Vehicle classes left alone: 13 cycles, 14 boats, 15 helicopters, 16 planes, 21 trains.
    Lock = { Enabled = true, ExcludeClasses = { [13] = true, [14] = true, [15] = true, [16] = true, [21] = true }, Radius = 150.0 },

    -- Picking the lock of a parked car. Needs the item; it can snap when you fail.
    Lockpick = {
        Item = 'lockpick', Difficulty = 'medium', Distance = 2.6,
        BreakChanceOnFail = 0.5,        -- the lockpick is used up with this chance when the minigame fails
        AlarmChance = 0.25,             -- the car alarm goes off with this chance, pass or fail
        MinMsPerRound = 500,            -- a tumbler round cannot be done faster than this (the server checks the total)
        CooldownSeconds = 4,
    },

    -- Hotwiring from the driver's seat (the engine stays dead until the keys are yours).
    Hotwire = { Difficulty = 'medium', MinMs = 3000, CooldownSeconds = 4, AlertChance = 0.3 },

    -- Pointing a gun at a driver: hold the aim for HoldMs. SuccessChance of them giving up the keys; otherwise they floor it.
    Carjack = { Enabled = true, Range = 14.0, HoldMs = 2800, SuccessChance = 0.85, CooldownSeconds = 15, AlertChance = 0.7 },

    -- How long keys to a stolen car are yours (minutes, counted on the server; also lost when the server restarts).
    KeysMinutes = 240,

    -- Police alerts. Off until you switch it on and have a dispatch resource that exports Alert (veyl_dispatch does).
    Police = {
        Enabled = false, Jobs = { 'police' }, PlayerCooldownSeconds = 60,
        Dispatch = { Enabled = false, Resource = 'veyl_dispatch', Code = '10-60', Title = 'Vehicle theft', Priority = 2, Blip = { sprite = 225, colour = 1 } },
    },

    -- Things you can find. Each search of a trunk or glovebox that belongs to no one is filled once (per plate, again after RerollHours).
    --   { item, weight, min, max }   weight = how likely compared with the others (and with EmptyWeight).
    Loot = {
        RerollHours = 24,
        Trunk = {
            Rolls = { 1, 3 }, EmptyWeight = 25,
            Items = {
                { item = 'scrap_metal',   weight = 22, min = 1, max = 4 },
                { item = 'plastic',       weight = 16, min = 1, max = 3 },
                { item = 'rubber',        weight = 12, min = 1, max = 2 },
                { item = 'tyre_kit',      weight = 8,  min = 1, max = 1 },
                { item = 'repair_kit',    weight = 7,  min = 1, max = 1 },
                { item = 'cleaning_kit',  weight = 8,  min = 1, max = 1 },
                { item = 'engine_parts',  weight = 5,  min = 1, max = 1 },
                { item = 'flashlight',    weight = 6,  min = 1, max = 1 },
                { item = 'water_bottle',  weight = 10, min = 1, max = 3 },
                { item = 'bandage',       weight = 6,  min = 1, max = 2 },
                { item = 'lockpick',      weight = 4,  min = 1, max = 2 },
                { item = 'radio',         weight = 2,  min = 1, max = 1 },
                { item = 'rolex',         weight = 0.6, min = 1, max = 1 },
            },
        },
        Glovebox = {
            Rolls = { 1, 2 }, EmptyWeight = 30,
            Items = {
                { item = 'sandwich',      weight = 10, min = 1, max = 2 },
                { item = 'snack_bar',     weight = 12, min = 1, max = 3 },
                { item = 'sprunk',        weight = 8,  min = 1, max = 2 },
                { item = 'coffee',        weight = 6,  min = 1, max = 1 },
                { item = 'bandage',       weight = 6,  min = 1, max = 2 },
                { item = 'lockpick',      weight = 5,  min = 1, max = 1 },
                { item = 'flashlight',    weight = 5,  min = 1, max = 1 },
                { item = 'radio',         weight = 3,  min = 1, max = 1 },
                { item = 'sim_card',      weight = 3,  min = 1, max = 1 },
                { item = 'usb_darkweb',   weight = 1,  min = 1, max = 1 },
                { item = 'gold_chain',    weight = 0.8, min = 1, max = 1 },
                { item = 'diamond_ring',  weight = 0.4, min = 1, max = 1 },
            },
        },
    },
}
