MechanicConfig = {
    Job = 'mechanic',

    -- Workshops: repairs are only possible inside `radius`. `desk` is where the mechanic menu (duty, invoices) is.
    Shops = {
        { id = 'lsc_burton', label = 'LS Customs (Burton)', coords = vector3(-337.39, -136.92, 39.01), radius = 20.0,
          desk = vector3(-347.29, -133.27, 39.01) },
    },

    -- Repair actions: the part item is consumed once per completed repair (server-timed).
    Repairs = {
        { id = 'engine', label = 'Repair engine', icon = 'wrench', item = 'engine_parts', durationMs = 12000 },
        { id = 'body', label = 'Repair bodywork', icon = 'car', item = 'body_panels', durationMs = 10000 },
        { id = 'tyres', label = 'Replace tyres', icon = 'wrench', item = 'tyre_kit', durationMs = 7000 },
        { id = 'clean', label = 'Wash vehicle', icon = 'drop', item = 'cleaning_kit', durationMs = 5000 },
    },

    Invoice = {
        Max = 25000,          -- largest single invoice
        Distance = 5.0,       -- customer must be this close when the invoice is sent
        PendingLimit = 5,     -- most unpaid invoices one customer can have from mechanics
    },

    Blip = { sprite = 446, colour = 27, scale = 0.7, name = 'Mechanic' },
}
