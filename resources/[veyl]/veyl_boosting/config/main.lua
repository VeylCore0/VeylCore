-- veyl_boosting: general settings. Everything tunable lives in config/*.lua; nothing about balance is hardcoded in the scripts.
-- This is a fictional contract game: players take "recovery contracts" for vehicles in the game world.

BoostingConfig = BoostingConfig or {}
local C = BoostingConfig

C.Debug = false                       -- verbose server console output
C.LogAuditToDatabase = true           -- write contract and security events to veyl_boost_audit

-- The tablet is an inventory item and the only way in: use it from your pockets or backpack. There is no command and no phone app, and
-- every request is refused without the item. The underground contact sells it.
C.Tablet = {
    Item = 'boosting_tablet',         -- registered in veyl_inventory/data/items.lua
    Price = 2500,                     -- what the contact charges for a tablet (cash); one tablet per person
}

-- Contracts shown to a player are generated on the server and kept for a while.
C.Offers = {
    TTLMinutes = 20,                  -- how long a generated list stays the same
    RefreshCooldownSeconds = 20,      -- minimum time between manual refreshes
    ReserveSeconds = 600,             -- a reserved contract (waiting for the crew) expires after this
}

-- The access sequence (a fictional signal-sync puzzle). The server owns the sequences and checks every answer and its timing.
C.Minigame = {
    Glyphs = 6,                       -- different symbols
    BaseLength = 3,                   -- sequence length = BaseLength + (difficulty - 1) // 2
    StagesByDifficulty = { [1] = 1, [2] = 2, [3] = 2, [4] = 3, [5] = 3 },
    ShowMsPerGlyph = 600,             -- how long each symbol is shown before input opens
    MinInputMsPerGlyph = 140,         -- a human cannot answer faster than this per symbol
    MaxInputMs = 14000,               -- time to answer one stage
    Strikes = 3,                      -- wrong answers allowed before the attempt fails
    FailCooldownSeconds = 45,         -- per player, after a failed attempt
    AttemptTimeoutSeconds = 120,      -- an unfinished attempt is dropped after this
    Distance = 4.5,                   -- metres from the vehicle
    RequiredItem = nil,               -- e.g. 'lockpick': optional item needed to start (not consumed)
    ConsumeItemOnFail = false,
}

-- Handoff.
C.Delivery = {
    Radius = 9.0,                     -- vehicle must be this close to the handoff point
    PlayerRadius = 30.0,              -- and the player within this
    RequireOnFoot = true,             -- the player must be out of the vehicle to hand it over
    MinCondition = 0.25,              -- below this (engine or body, 0-1) the buyer refuses the vehicle
    MinPayFraction = 0.4,             -- pay at the minimum acceptable condition (scales up to 100% at the vehicle's "full pay" condition)
}

-- Cleanup and restart behaviour.
C.Cleanup = {
    TickMs = 2000,                    -- contract supervisor loop
    DeleteDelaySeconds = 25,          -- after completion, how long the delivered vehicle stays before it is removed
    DisconnectGraceSeconds = 300,     -- a contract with every member offline fails after this
    RestartPolicy = 'expire',         -- active contracts found after a restart: 'expire' (no penalty). Paid-but-unrecorded rewards are always recovered.
}

-- A tracker on high-risk vehicles pings the dispatch adapter until it is disabled.
C.Tracker = {
    Item = 'hacking_device',          -- needed to disable it (nil = no item needed)
    DisableSeconds = 20,
    ConsumeChance = 0.5,
    PingSeconds = 25,
}

C.Blips = {
    Area = { colour = 5, alpha = 110, radius = 160.0 },
    Drop = { sprite = 524, colour = 5, label = 'Boosting handoff' },
}

C.Admin = { Permission = 'boosting.admin' }   -- checked with Veyl.HasPermission

-- Theme sent to the tablet. The page also falls back to these if a value is missing.
C.UI = {
    Brand = 'VEYL BOOSTING',
    Tagline = 'Become the ultimate operator',
    Accent = '#8b5fd6',
    Accent2 = '#3f8bff',
    Currency = '$',
}
