NeedsConfig = {
    TickMs = 60000,          -- decay interval
    HungerPerTick = 1.2,     -- ~83 minutes from full to empty
    ThirstPerTick = 1.8,     -- ~55 minutes from full to empty
    StressPerTick = -0.5,    -- stress slowly recovers
    StarvingDamage = 3,      -- health lost every 10s while hunger or thirst is 0
    RespawnMinimum = 40,     -- hunger/thirst restored to at least this on hospital respawn

    -- Consumable effects live in veyl_inventory/data/items.lua (use.effects) and are applied by the
    -- 'consume' handler registered in server.lua.
}
