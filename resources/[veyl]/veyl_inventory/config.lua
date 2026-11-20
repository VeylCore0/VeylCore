InventoryConfig = {
    -- Only 'builtin' ships in this release. A future provider (e.g. an ox_inventory bridge) must implement
    -- the same functions as server/provider_builtin.lua. Never run two providers at once.
    Provider = 'builtin',

    MaxWeight = 30000,       -- grams carried by a character
    GiveDistance = 3.0,
    MaxStackPerAction = 50,

    Stashes = {
        {
            id = 'legion_lockers', label = 'Public lockers', personal = true, maxWeight = 100000,
            coords = vector3(236.41, -1001.06, 29.29), radius = 1.8,
        },
    },
}
