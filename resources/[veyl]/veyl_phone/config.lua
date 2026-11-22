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
        { id = 'maps', label = 'Maps', enabled = true, preinstalled = true, category = 'Navigation',
          description = 'Saved places, businesses and services, GPS, and sharing your live location.' },
        { id = 'services', label = 'Services', enabled = true, preinstalled = true, category = 'Utilities',
          description = 'Call police, EMS, mechanics, taxis and businesses. On duty? See the queue.' },
        { id = 'mail', label = 'Mail', enabled = true, preinstalled = true, category = 'Utilities',
          description = 'Receipts, bills, job offers and messages from businesses and the city.' },
        { id = 'voicemail', label = 'Voicemail', enabled = true, preinstalled = true, category = 'Utilities',
          description = 'Messages people left when you could not answer, and leaving your own.' },
        { id = 'camera', label = 'Camera', enabled = true, preinstalled = true, category = 'Photo',
          description = 'Take photos (needs screenshot-basic) and keep them in your gallery.' },
        { id = 'jobs', label = 'Jobs', enabled = true, preinstalled = true, category = 'Work',
          description = 'Your jobs, clock in and out, the city job board and applications.' },
        { id = 'bills', label = 'Bills', enabled = true, preinstalled = true, category = 'Finance',
          description = 'Pay invoices and citations, set up standing orders, see your credit score.' },
        { id = 'music', label = 'Music', enabled = true, preinstalled = false, category = 'Entertainment',
          description = 'Radio stations in your ears, or out loud for everyone nearby.' },
        { id = 'news', label = 'News', enabled = true, preinstalled = true, category = 'News',
          description = 'Weazel News stories and breaking alerts.' },
        { id = 'racing', label = 'Racing', enabled = true, preinstalled = false, category = 'Vehicles',
          description = 'Record tracks, host and join races, and the leaderboards.' },
    },

    Flock = { PostLength = 280, PageSize = 20, PostCooldownMs = 5000, MaxMentions = 5 },
    Bank = { MaxTransfer = 250000 },
    Market = {
        TitleLength = 48, BodyLength = 300, MaxPrice = 10000000, ListingDays = 7, MaxActive = 5, PageSize = 25,
        Categories = { 'vehicles', 'items', 'services', 'property', 'other' },
    },
    Notes = { Max = 100, TitleLength = 48, BodyLength = 2000 },

    -- Phone cases: the colour of the in-hand sd-phone prop (sd_phone_<colour>).
    Cases = { 'black', 'blue', 'green', 'orange', 'pink', 'purple', 'red', 'yellow' },

    -- Services app. dispatch = goes to veyl_dispatch as a call; otherwise on-duty members of the jobs get the request.
    Services = {
        { id = 'police', label = 'Police', jobs = { 'police' }, dispatch = 'police', icon = 'shield' },
        { id = 'ems', label = 'EMS', jobs = { 'ambulance' }, dispatch = 'ems', icon = 'heart' },
        { id = 'mechanic', label = 'Mechanic', jobs = { 'mechanic' }, icon = 'wrench' },
        { id = 'taxi', label = 'Taxi', jobs = { 'taxi' }, icon = 'car' },
        { id = 'beanmachine', label = 'Bean Machine', jobs = { 'beanmachine' }, icon = 'burger' },
        { id = 'burgershot', label = 'Burger Shot', jobs = { 'burgershot' }, icon = 'burger' },
    },
    ServiceCooldownSeconds = 60,

    -- Maps app: places everyone sees (label, category, coords). Saved places are per character.
    MapPlaces = {
        { label = 'City Hall', category = 'City', x = -265.0, y = -963.6 },
        { label = 'Pillbox Hill Medical Center', category = 'Services', x = 308.2, y = -595.4 },
        { label = 'Mission Row Police', category = 'Services', x = 441.8, y = -982.0 },
        { label = 'LS Customs', category = 'Services', x = -347.3, y = -133.3 },
        { label = 'Impound Lot', category = 'Services', x = 400.5, y = -1630.9 },
        { label = 'Bean Machine', category = 'Food', x = -631.2, y = 233.5 },
        { label = 'Burger Shot', category = 'Food', x = -1194.9, y = -893.9 },
        { label = 'Premium Deluxe Motorsport', category = 'Vehicles', x = -56.5, y = -1096.6 },
        { label = 'Starlite Motel', category = 'Housing', x = 319.0, y = -195.0 },
        { label = 'Fish market', category = 'Jobs', x = -1612.5, y = -1028.8 },
    },
    ShareMinutes = { 15, 30, 60 },

    Mail = { Max = 200 },
    Voicemail = { Max = 50, Length = 500 },

    -- Phase 2 apps
    Camera = { Max = 60, Quality = 0.55 },          -- photos per player; JPEG quality (lower = smaller rows)
    Valet = { Fee = 250 },                           -- bank charge to have a garaged vehicle brought to you
    Standing = { Max = 5, MaxAmount = 50000 },       -- standing orders per player and per payment
    Music = {
        SpeakerRange = 30.0,                         -- metres other players hear a phone playing out loud
        -- Built-in stations are generated in the phone (no stream needed). Add internet radio with
        -- { id = 'myradio', label = 'My Radio', url = 'https://...' } (the URL must allow cross-origin audio).
        Stations = {
            { id = 'veyl', label = 'Veyl Radio', style = 'synth' },
            { id = 'lofi', label = 'Lo-Fi Beach', style = 'lofi' },
            { id = 'night', label = 'Night Drive', style = 'night' },
        },
    },
    News = { Jobs = { 'weazel' } },                  -- jobs allowed to publish (on duty)
    Racing = { JoinRadius = 60.0 },                  -- metres from the start line to join a race
    Tablet = { Mdt = 'mdt', Dispatch = 'dispatch' }, -- commands opened from the tablet menu

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
