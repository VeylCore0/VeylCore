-- veyl_scavenge: dumpster diving. Everything you can find, how long it takes and how often is set here.
--
-- Two kinds of props, each with its own models and loot table:
--   dumpsters  every trash can, bin and dumpster prop
--   bags       garbage bag props lying around
-- To make something findable, add a line to that kind's `Loot`. The item name must exist in veyl_inventory/data/items.lua
-- (unknown names are reported in the server console at start and never given).
--
-- Loot entry:  { item = 'plastic', weight = 30, min = 1, max = 3 }
--   weight  how likely it is compared with the other entries (and with `EmptyWeight`). Bigger = more common.
--   min/max amount per find.
--   money = { min, max }  instead of `item`: cash found.     label (optional) shown in the notification for money.
-- Each search makes `Rolls` draws (a random number between min and max). Each draw picks one entry, or nothing (`EmptyWeight`).

ScavengeConfig = {
    Debug = false,

    Distance = 3.0,                   -- how close (metres) you must be to the prop; checked on the server
    MaxSearchesPerHour = 40,          -- per player, so one prop spot cannot be farmed endlessly
    MinSecondsBetween = 3,            -- between two searches by the same player

    Kinds = {
        dumpsters = {
            label = 'Search the dumpster', icon = 'trash',
            DurationMs = 7000,
            Anim = { dict = 'amb@prop_human_bum_bin@base', clip = 'base', flag = 1 },
            PlayerCooldownMinutes = 45,   -- the same bin is picked over for you for this long
            PropCooldownMinutes = 10,     -- and for everyone else for this long after anyone searched it
            Rolls = { 1, 3 }, EmptyWeight = 25,
            Hazard = { chance = 0.06, damage = 6, message = 'Something bit you in there' },   -- optional: remove or set chance = 0
            Models = {
                'prop_dumpster_01a', 'prop_dumpster_02a', 'prop_dumpster_02b', 'prop_dumpster_3a', 'prop_dumpster_4a', 'prop_dumpster_4b', 'prop_cs_dumpster_01a',
                'prop_bin_01a', 'prop_bin_02a', 'prop_bin_03a', 'prop_bin_04a', 'prop_bin_05a', 'prop_bin_06a', 'prop_bin_07a', 'prop_bin_07b', 'prop_bin_07c', 'prop_bin_07d',
                'prop_bin_08a', 'prop_bin_08open', 'prop_bin_09a', 'prop_bin_10a', 'prop_bin_10b', 'prop_bin_11a', 'prop_bin_11b', 'prop_bin_12a', 'prop_bin_13a',
                'prop_bin_14a', 'prop_bin_14b', 'prop_bin_beach_01a', 'prop_bin_beach_01d', 'prop_bin_delpiero', 'prop_bin_delpiero_b', 'zprop_bin_01a_old',
                'prop_cs_bin_01', 'prop_cs_bin_01_skinned', 'prop_cs_bin_02', 'prop_cs_bin_03',
                'prop_recyclebin_01a', 'prop_recyclebin_02_c', 'prop_recyclebin_02_d', 'prop_recyclebin_02a', 'prop_recyclebin_02b',
                'prop_recyclebin_03_a', 'prop_recyclebin_04_a', 'prop_recyclebin_04_b', 'prop_recyclebin_05_a',
            },
            Loot = {
                { item = 'plastic',      weight = 30, min = 1, max = 4 },
                { item = 'glass',        weight = 22, min = 1, max = 3 },
                { item = 'rubber',       weight = 14, min = 1, max = 2 },
                { item = 'scrap_metal',  weight = 16, min = 1, max = 3 },
                { item = 'water_bottle', weight = 8,  min = 1, max = 1 },
                { item = 'snack_bar',    weight = 6,  min = 1, max = 1 },
                { item = 'burger',       weight = 3,  min = 1, max = 1 },
                { item = 'bandage',      weight = 2,  min = 1, max = 1 },
                { money = { 2, 18 },     weight = 10, label = 'loose change' },
                { item = 'lockpick',     weight = 1.5, min = 1, max = 1 },
                { item = 'phone',        weight = 0.4, min = 1, max = 1 },
            },
        },

        bags = {
            label = 'Search the bag', icon = 'bag',
            DurationMs = 4500,
            Anim = { dict = 'pickup_object', clip = 'pickup_low', flag = 1 },
            PlayerCooldownMinutes = 60,
            PropCooldownMinutes = 15,
            Rolls = { 1, 2 }, EmptyWeight = 30,
            Hazard = { chance = 0.04, damage = 4, message = 'You cut yourself on something sharp' },
            Models = {
                'prop_rub_binbag_01', 'prop_rub_binbag_01b', 'prop_rub_binbag_03', 'prop_rub_binbag_03b', 'prop_rub_binbag_04', 'prop_rub_binbag_05',
                'prop_rub_binbag_06', 'prop_rub_binbag_08', 'prop_ld_rub_binbag_01', 'prop_cs_rub_binbag_01', 'prop_cs_bin_bag_01',
                'bkr_prop_fakeid_binbag_01', 'hei_prop_hei_garbage_bag', 'ng_proc_binbag_01a', 'ng_proc_binbag_02a', 'prop_rub_litter_03c', 'prop_rub_litter_04',
            },
            Loot = {
                { item = 'plastic',      weight = 28, min = 1, max = 3 },
                { item = 'glass',        weight = 14, min = 1, max = 2 },
                { item = 'scrap_metal',  weight = 10, min = 1, max = 2 },
                { item = 'coffee',       weight = 6,  min = 1, max = 1 },
                { item = 'sandwich',     weight = 5,  min = 1, max = 1 },
                { item = 'rolling_papers', weight = 4, min = 1, max = 1 },
                { money = { 1, 9 },      weight = 12, label = 'a few coins' },
                { item = 'flashlight',   weight = 0.8, min = 1, max = 1 },
            },
        },
    },

}
