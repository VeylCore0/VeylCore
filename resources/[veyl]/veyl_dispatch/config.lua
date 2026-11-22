-- veyl_dispatch configuration. Keys can be rebound in Settings > Key Bindings > FiveM.

DispatchConfig = {
    -- Emergency services and the jobs whose ON-DUTY members belong to them.
    Services = {
        police = { label = 'Police', jobs = { 'police' }, blip = { colour = 38 } },
        ems    = { label = 'EMS',    jobs = { 'ambulance' }, blip = { colour = 1 } },
    },

    MenuKey = 'F6',        -- open the dispatch panel (on duty only)
    RespondKey = 'Y',      -- respond to the newest call
    PanicKey = 'F9',       -- panic button (police and EMS)

    CallLifetimeMinutes = 15,
    MaxCalls = 60,
    PopupSeconds = 9,      -- how long a new call card stays on screen
    BlipSeconds = 120,     -- how long a call blip stays on the map
    PanicCooldownSeconds = 30,

    UnitBlips = true,      -- on-duty units see each other on the map
    UnitBlipIntervalMs = 3000,

    Statuses = {
        { id = 'available', label = 'Available' },
        { id = 'enroute',   label = 'En route' },
        { id = 'onscene',   label = 'On scene' },
        { id = 'busy',      label = 'Busy' },
        { id = 'break',     label = 'On break' },
    },

    -- Commands anyone can use. services = who receives it.
    PublicCalls = {
        ['911'] = { services = { 'police', 'ems' }, code = '911', title = 'Emergency call', priority = 2 },
        ['311'] = { services = { 'police' }, code = '311', title = 'Non-emergency call', priority = 3 },
    },
    PublicCallCooldownSeconds = 30,
}
