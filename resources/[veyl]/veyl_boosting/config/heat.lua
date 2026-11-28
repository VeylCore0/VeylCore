-- Heat (attention) and the optional police alert adapter. Both are fictional game systems.

BoostingConfig = BoostingConfig or {}

BoostingConfig.Heat = {
    Max = 100,
    DecayPerMinute = 3.0,            -- heat cools over elapsed real time (also while offline)
    -- Levels, by upper bound. Influence multiplies the pay of new contract offers while the level is active.
    Levels = {
        { id = 'LOW',     max = 25,  label = 'Low',     color = '#34d27b', rewardMult = 1.00 },
        { id = 'MEDIUM',  max = 50,  label = 'Medium',  color = '#f2b443', rewardMult = 1.05 },
        { id = 'HIGH',    max = 75,  label = 'High',    color = '#ef7a3a', rewardMult = 1.12 },
        { id = 'EXTREME', max = 100, label = 'Extreme', color = '#e0576a', rewardMult = 1.20 },
    },
    -- At or above this level, templates below `minDifficulty` are hidden (hot players are not offered the easy jobs).
    HideEasyAt = 'HIGH', MinDifficulty = 3,
    AlertCooldownSeconds = 90,       -- per player, between police alerts
    FailGainMultiplier = 1.0,        -- scales a template's heat.onFail
}

-- The dispatch adapter (integrations/dispatch_adapter.lua). It stays off unless the named resource is running.
BoostingConfig.Police = {
    Enabled = true,                  -- false = never alert, and police count is ignored
    Resource = 'veyl_dispatch',      -- the dispatch resource that provides the `Alert` export
    Jobs = { 'police' },             -- jobs counted for minPolice
    Code = '10-16',
    Priority = 2,
    Title = 'Stolen vehicle',
    Radius = 250.0,                  -- the alert shows an area of this radius, not the exact spot
    Blip = { sprite = 225, colour = 1 },
    InvestigationZone = false,       -- true: blur the reported position inside the radius
}
