PhoneConfig = {
    -- Device: a character needs this item to open the phone and to have an active phone session (receive deliveries
    -- and calls). The account and number belong to the CHARACTER: a replacement phone restores that character's data,
    -- and holding someone else's phone item never grants access to their account. Set to false to not require an item.
    RequireItem = 'phone',
    OpenKey = 'F1',

    -- Numbers: <prefix><4 digits>, shown as 555-1234. Unique per character, never reused.
    NumberPrefixes = { '555', '310', '323', '424' },

    -- App registry. Only apps listed here and enabled exist on the phone; order = default home order.
    -- core = always installed (cannot be removed). Other apps are installed from the App Store, per character;
    -- preinstalled = installed on a new phone. Apps that are not built yet are simply not listed (no placeholders).
    Apps = {
        { id = 'phone', label = 'Phone', enabled = true, dock = true, core = true },
        { id = 'messages', label = 'Messages', enabled = true, dock = true, core = true },
        { id = 'contacts', label = 'Contacts', enabled = true, dock = true, core = true },
        { id = 'settings', label = 'Settings', enabled = true, dock = true, core = true },
        { id = 'store', label = 'App Store', enabled = true, core = true, category = 'Utilities',
          description = 'Find and install apps for your phone.' },
        { id = 'flock', label = 'Flock', enabled = true, preinstalled = true, category = 'Social',
          description = 'Short posts from around the city. Follow people, reply, like and mention with @handle.' },
        { id = 'bank', label = 'Bank', enabled = true, preinstalled = true, category = 'Finance',
          description = 'Check your balance and activity, and send money to a phone number or account.' },
        { id = 'garage', label = 'Garage', enabled = true, preinstalled = true, category = 'Vehicles',
          description = 'See every vehicle you own, where it is, and set a waypoint to it.' },
        { id = 'market', label = 'Marketplace', enabled = true, preinstalled = false, category = 'Shopping',
          description = 'Buy and sell with other residents. Post a listing and get messages or calls.' },
        { id = 'notes', label = 'Notes', enabled = true, preinstalled = false, category = 'Utilities',
          description = 'Private notes saved to your phone.' },
        { id = 'calculator', label = 'Calculator', enabled = true, preinstalled = true, category = 'Utilities',
          description = 'A simple calculator.' },
    },

    Flock = { PostLength = 280, PageSize = 20, PostCooldownMs = 5000, MaxMentions = 5 },
    Bank = { MaxTransfer = 250000 },
    Market = {
        TitleLength = 48, BodyLength = 300, MaxPrice = 10000000, ListingDays = 7, MaxActive = 5, PageSize = 25,
        Categories = { 'vehicles', 'items', 'services', 'property', 'other' },
    },
    Notes = { Max = 100, TitleLength = 48, BodyLength = 2000 },

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
        -- In-hand prop. sd_phone_black comes from the sd-phone prop pack (ensure sd-phone before veyl_phone); if that
        -- model is not streamed, the base-game phone is used instead.
        prop = 'sd_phone_black',
        fallbackProp = 'prop_npc_phone_02',
        text = { dict = 'cellphone@', clip = 'cellphone_text_read_base' },
        call = { dict = 'cellphone@', clip = 'cellphone_call_listen_base' },
        carText = { dict = 'anim@cellphone@in_car@ps', clip = 'cellphone_text_read_base' },
        carCall = { dict = 'anim@cellphone@in_car@ps', clip = 'cellphone_call_listen_base' },
        BlockWhenAiming = true,
        BlockWhenSwimming = true,
    },
}
