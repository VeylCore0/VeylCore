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

    -- Backpack: a second personal container shown under your pockets. Slots and weight apply to new characters; for existing ones the
    -- slot count only grows. Set Enabled = false to hide it.
    Backpack = { Enabled = true, Slots = 15, MaxWeight = 15000, Label = 'Backpack' },   -- the container exists only while a backpack item is worn (equip = 'backpack')

    -- Equipment slots (the body panel). An item goes in a slot only if its definition says equip = '<slot id>' (server-checked on every move).
    -- Order is the slot number. side/row place them on the body panel; only the order matters to the server.
    Equipment = {
        { id = 'ears',    label = 'Headset',  icon = 'headset', side = 'left' },
        { id = 'mask',    label = 'Mask',     icon = 'mask',    side = 'left' },
        { id = 'glasses', label = 'Glasses',  icon = 'glasses', side = 'left' },
        { id = 'armor',   label = 'Armour',   icon = 'shield',  side = 'left' },
        { id = 'hat',     label = 'Hat',      icon = 'hat',     side = 'left' },
        { id = 'backpack', label = 'Backpack', icon = 'backpack', side = 'left' },
        { id = 'id',      label = 'ID card',  icon = 'id',      side = 'right' },
        { id = 'phone',   label = 'Phone',    icon = 'phone',   side = 'right' },
        { id = 'tablet',  label = 'Tablet',   icon = 'tablet',  side = 'right' },
        { id = 'key',     label = 'Key',      icon = 'key',     side = 'right' },
    },

    -- Item categories for the filter chips. An item definition can set category = '<id>'; otherwise it is worked out from what the item does.
    Categories = {
        { id = 'all', label = 'All' }, { id = 'weapons', label = 'Weapons' }, { id = 'consumables', label = 'Consumables' },
        { id = 'equipment', label = 'Equipment' }, { id = 'goods', label = 'Goods' }, { id = 'misc', label = 'Other' },
    },

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
