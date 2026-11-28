-- Progression: six levels per branch and an overall reputation level. XP is awarded only by the server.

ProductionConfig = ProductionConfig or {}

-- XP needed to REACH each level (index = level). Level 1 starts at 0 XP.
ProductionConfig.Levels = { 0, 120, 360, 800, 1600, 3200 }
ProductionConfig.LevelNames = { 'Newcomer', 'Hand', 'Practitioner', 'Specialist', 'Expert', 'Master' }

-- XP for each activity. `Cooldown` is seconds per player between rewarded repeats of that activity (anti-farming).
ProductionConfig.XP = {
    gather = { xp = 6, cooldown = 20 },
    plant = { xp = 8, cooldown = 10 },
    water = { xp = 2, cooldown = 30 },
    harvest = { xp = 30, cooldown = 0 },
    craft = { xp = 15, cooldown = 0 },
    sell = { xp = 4, cooldown = 10 },
    search = { xp = 7, cooldown = 15 },        -- field zone searches
    run = { xp = 40, cooldown = 0 },           -- supplier runs
}

-- Overall reputation: the sum of every branch's XP, at these totals.
ProductionConfig.Reputation = { 0, 200, 600, 1400, 2800, 5200 }

-- Quality: skill (branch level) and equipment add to a product's quality, and each roll varies randomly.
ProductionConfig.Quality = {
    PerLevel = 2.0,                  -- points per branch level above 1
    Variance = 6,                    -- +/- random
    Tiers = {                        -- upper bound (inclusive), label, resale multiplier
        { max = 24, label = 'Poor', mult = 0.6 },
        { max = 49, label = 'Standard', mult = 1.0 },
        { max = 74, label = 'Good', mult = 1.3 },
        { max = 89, label = 'Excellent', mult = 1.6 },
        { max = 100, label = 'Flawless', mult = 2.0 },
    },
}
