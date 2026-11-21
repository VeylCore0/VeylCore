-- veyl_doorlocks configuration. Doors themselves are created in game with /doorlock (stored in the database).

DoorConfig = {
    -- Who can open the in-game editor: ACE veyl.doorlocks.admin (or veyl.admin).
    AdminPermission = 'doorlocks.admin',
    -- Staff with the admin permission can lock/unlock any door (every use is logged).
    AdminBypass = true,
    Command = 'doorlock',

    -- Limits for doors created in the editor.
    MaxEntities = 4,                -- doors per entry (double doors, gate pairs...)
    DistanceRange = { 1.0, 10.0 },
    AutoLockMax = 3600,             -- seconds
    ToggleCooldownMs = 600,

    -- Lock state after a server restart: 'default' (each door's "locked by default" setting) or 'last' (as it was).
    StateOnRestart = 'default',

    Items = { key = 'door_key', lockpick = 'lockpick', ram = 'door_ram' },
    Breach = {
        LockpickSeconds = 6,
        LockpickBreakChance = 0.35,  -- chance the lockpick breaks on a failed attempt
        RamSeconds = 4,
        DefaultRelockSeconds = 300,  -- a breached door relocks itself after this (0 = stays open)
    },
    Grants = { MaxHours = 168, MaxPerDoor = 25 },
    Keys = { MaxPerDoor = 20 },     -- physical keys a manager may cut per door
    LogKeepDays = 30,
}
