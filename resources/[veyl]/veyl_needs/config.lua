NeedsConfig = {
    TickMs = 60000,          -- decay interval
    HungerPerTick = 1.2,     -- ~83 minutes from full to empty
    ThirstPerTick = 1.8,     -- ~55 minutes from full to empty
    StressPerTick = -0.5,    -- stress slowly recovers
    StarvingDamage = 3,      -- health lost every 10s while hunger or thirst is 0
    RespawnMinimum = 40,     -- hunger/thirst restored to at least this on hospital respawn

    -- Server-authoritative effects applied after ox_inventory confirms an item was used.
    -- (ox_inventory's client-side `status` values are ignored by the VeylCore bridge.)
    ItemEffects = {
        water = { thirst = 35 },
        sprunk = { thirst = 25, stress = -5 },
        coffee = { thirst = 15, stress = -10 },
        sandwich = { hunger = 35 },
        burger = { hunger = 50 },
        mustard = { hunger = 5, thirst = 5 },
        bandage = { heal = 25 },
    },
}
