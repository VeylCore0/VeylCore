PhoneConfig = {
    -- Device: a character needs this item to open the phone and to have an active phone session (receive deliveries
    -- and calls). The account and number belong to the CHARACTER: a replacement phone restores that character's data,
    -- and holding someone else's phone item never grants access to their account. Set to false to not require an item.
    RequireItem = 'phone',
    OpenKey = 'F1',

    -- Numbers: <prefix><4 digits>, shown as 555-1234. Unique per character, never reused.
    NumberPrefixes = { '555', '310', '323', '424' },

    -- App registry. Only apps listed here and enabled are shown; order = default home order. Apps from later
    -- milestones are not listed until they are built (no placeholders).
    Apps = {
        { id = 'phone', label = 'Phone', enabled = true, dock = true },
        { id = 'messages', label = 'Messages', enabled = true, dock = true },
        { id = 'contacts', label = 'Contacts', enabled = true, dock = true },
        { id = 'settings', label = 'Settings', enabled = true, dock = true },
    },

    Wallpapers = { 'aurora', 'dusk', 'vinewood', 'midnight', 'violet', 'mono' },
    Accents = { '#b892f4', '#7aa7ff', '#5fd3a5', '#f2c66d', '#ef8f96', '#e3e3ea' },
    Ringtones = { 'veyl', 'pulse', 'classic', 'chime' },
    NotificationSounds = { 'tap', 'bell', 'none' },

    Limits = {
        Contacts = 300,
        Blocked = 100,
        MessageLength = 500,
        GroupMembers = 12,
        GroupName = 32,
        PageSize = 30,
        Notifications = 100,          -- kept per character (oldest removed)
        PendingDeliveryBatch = 200,   -- undelivered messages pushed on login
    },

    Calls = {
        RingSeconds = 30,
        ChannelBase = 5000,           -- pma-voice call channels used: ChannelBase + call id
    },

    -- Integrations (adapters). Only what is really installed is enabled; see docs/PHONE.md.
    Voice = 'auto',                   -- 'auto' = pma-voice if started; calls are disabled otherwise
    Weather = 'veyl_world',           -- GlobalState.veylWorld (weather + in-game time)

    Animations = {
        prop = 'prop_npc_phone_02',
        text = { dict = 'cellphone@', clip = 'cellphone_text_read_base' },
        call = { dict = 'cellphone@', clip = 'cellphone_call_listen_base' },
        carText = { dict = 'anim@cellphone@in_car@ps', clip = 'cellphone_text_read_base' },
        carCall = { dict = 'anim@cellphone@in_car@ps', clip = 'cellphone_call_listen_base' },
        BlockWhenAiming = true,
        BlockWhenSwimming = true,
    },
}
