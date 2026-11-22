InventoryConfig = {
    PlayerSlots = 30,
    PlayerMaxWeight = 130000,         -- integer grams
    MaxMetadataBytes = 2048,
    UseTimeToleranceMs = 400,         -- completion may arrive this much earlier than the use duration
    UseReservationGraceMs = 10000,    -- reservation expires this long after the use duration
    ImagePath = 'nui://veyl_inventory/web/images',
    OpenKey = 'F2',
    HotbarSlots = 5,                  -- keys 1..5 use the item in personal slots 1..5
    GiveDistance = 3.0,

    -- Ground drops (the right-hand box when no stash is open). Cleared on restart.
    DropSlots = 30,
    DropMaxWeight = 200000,         -- grams
    DropDistance = 2.5,             -- how close you must be to use a drop
    DropLifetimeMinutes = 30,       -- untouched drops disappear after this
    DropProp = 'prop_paper_bag_small',

    -- Server-registered stashes. owner = true: every character has its own copy.
    -- groups = { police = 0 } restricts access (checked on the server for every mutation).
    Stashes = {
        { id = 'legion_lockers', label = 'Public lockers', slots = 30, maxWeight = 100000, owner = true,
          coords = vector3(236.41, -1001.06, 29.29), radius = 1.8 },
        { id = 'legion_shared', label = 'Community crate', slots = 20, maxWeight = 50000, owner = false,
          coords = vector3(239.20, -998.70, 29.29), radius = 1.8 },
    },
}
