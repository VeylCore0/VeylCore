-- veyl_robbery configuration: store robberies. Money in whole dollars, times in seconds.
-- Every shop marked `robbable = true` in veyl_shops/config.lua (all 24/7, LTD Gasoline and Rob's Liquor) can be
-- robbed at its register: hold the target key (ALT) and aim at the counter or the clerk.

RobberyConfig = {
    PoliceJobs = { 'police' },
    MinPolice = 2,                 -- on-duty officers needed before a store can be robbed
    StoreCooldownMinutes = 30,     -- per store and target (register / safe), after a robbery starts
    PlayerCooldownMinutes = 10,    -- per robber

    -- Register: threaten the clerk (weapon in hand) or pick the till (lockpick + mini game).
    -- requireWeapon = true: a weapon must be in hand to threaten the clerk.
    Register = { seconds = 25, reward = { 400, 900 }, requireWeapon = false, item = 'lockpick', pickSeconds = 12, difficulty = 'medium', pickBreakChance = 0.35 },
    Safe = { seconds = 60, reward = { 1500, 3500 }, item = 'lockpick', breakChance = 0.25, difficulty = 'hard', pickBreakChance = 0.5 },

    AlarmDelaySeconds = 0,         -- dispatch goes out when the robbery starts (silent alarm)

    -- Back-room safes by shop id (veyl_shops). Stores without an entry have a register only. Check these against
    -- your map: they assume the base-game store interiors.
    Safes = {
        ['247_innocence']  = vector3(28.21, -1339.14, 29.49),
        ['247_clinton']    = vector3(378.15, 333.38, 103.57),
        ['247_ineseno']    = vector3(-3047.88, 585.61, 7.90),
        ['247_barbareno']  = vector3(-3250.02, 1004.43, 12.83),
        ['247_paleto']     = vector3(1734.78, 6420.84, 35.03),
        ['247_sandy']      = vector3(1959.27, 3748.92, 32.34),
        ['247_route68']    = vector3(546.41, 2662.80, 42.15),
        ['247_senora']     = vector3(2672.69, 3286.63, 55.24),
        ['247_palomino']   = vector3(2549.19, 384.86, 108.62),
        ['ltd_grove']      = vector3(-43.43, -1748.30, 29.42),
        ['ltd_littleseoul'] = vector3(-709.74, -904.15, 19.21),
        ['ltd_richman']    = vector3(-1829.27, 798.76, 138.19),
        ['ltd_mirrorpark'] = vector3(1159.46, -314.05, 69.20),
        ['ltd_grapeseed']  = vector3(1707.93, 4920.47, 42.06),
        ['robs_vespucci']  = vector3(-1220.85, -916.05, 11.32),
        ['robs_morningwood'] = vector3(-1478.94, -375.50, 39.16),
        ['robs_banham']    = vector3(-2959.64, 387.08, 14.04),
        ['robs_harmony']   = vector3(1169.31, 2717.79, 37.15),
        ['robs_elrancho']  = vector3(1126.77, -980.10, 45.41),
    },
}
