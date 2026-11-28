-- veyl_phone (base). Everything the phone does is checked on the server; the UI only displays and asks.
-- The UI contract (every call, push and message) is documented in docs/PHONE.md.

PhoneConfig = {
    -- A character needs this item to open the phone and to be reachable (messages pushed live, calls ring).
    -- The number belongs to the CHARACTER: a new phone item gives back the same number and data. false = no item needed.
    RequireItem = 'phone',
    OpenKey = 'F1',
    WalkWhileOpen = true,             -- the player can keep walking with the phone open (camera/combat stay blocked)

    -- Numbers are <prefix><4 digits> (7 digits), shown as 555-1234. One per character, never reused.
    NumberPrefixes = { '555', '310', '323', '424' },

    -- Built-in apps the UI provides. core = always installed (cannot be removed); preinstalled = on a new phone.
    -- The UI must only show apps that are listed here (plus apps other resources register with RegisterApp).
    Apps = {
        { id = 'phone', label = 'Phone', core = true, dock = true },
        { id = 'messages', label = 'Messages', core = true, dock = true },
        { id = 'contacts', label = 'Contacts', core = true, dock = true },
        { id = 'settings', label = 'Settings', core = true, dock = true },
        { id = 'mail', label = 'Mail', core = true },
        { id = 'store', label = 'App Store', core = true },
        { id = 'calculator', label = 'Calculator', preinstalled = true, description = 'A simple calculator.' },
        { id = 'clock', label = 'Clock', preinstalled = true, description = 'Time, stopwatch and timer.' },
        { id = 'bank', label = 'Bank', preinstalled = true, description = 'Your balance and activity, and send money to a phone number or account.' },
        { id = 'garage', label = 'Garage', preinstalled = true, description = 'Every vehicle you own, where it is, and a waypoint to it. Valet brings it to you.' },
        { id = 'maps', label = 'Maps', preinstalled = true, description = 'Places, businesses and services, GPS, and sharing your live location.' },
        { id = 'services', label = 'Services', preinstalled = true, description = 'Call police, EMS, mechanics and taxis. On duty? See the queue.' },
        { id = 'camera', label = 'Camera', preinstalled = true, description = 'Take photos (needs screenshot-basic) and keep them in your gallery.' },
        { id = 'jobs', label = 'Jobs', preinstalled = true, description = 'Your jobs, clock in and out, the city job board and applications.' },
        { id = 'bills', label = 'Bills', preinstalled = true, description = 'Pay invoices and citations, standing orders, your credit score.' },
        { id = 'voicemail', label = 'Voicemail', preinstalled = true, description = 'Messages people left when you could not answer.' },
        { id = 'news', label = 'News', preinstalled = true, description = 'Weazel News stories and breaking alerts.' },
        { id = 'flock', label = 'Flock', preinstalled = true, description = 'Short posts from around the city. Follow people, reply, like and mention with @handle.' },
        { id = 'market', label = 'Marketplace', description = 'Buy and sell with other residents. Post a listing and get messages or calls.' },
        { id = 'notes', label = 'Notes', description = 'Private notes saved to your phone.' },
        { id = 'music', label = 'Music', description = 'Radio stations in your ears, or out loud for everyone nearby.' },
        { id = 'racing', label = 'Racing', description = 'Record tracks, host and join races, and the leaderboards.' },
    },

    -- Settings the UI may save (anything else is dropped by the server). First value = default for a new phone.
    Presets = {
        wallpapers = { 'default', 'sunset', 'aurora', 'midnight', 'mono' },
        accents = { '#8b63d6', '#4f8cff', '#2fbf8a', '#f2b443', '#ef6f7c', '#e3e3ea' },
        ringtones = { 'default', 'pulse', 'classic', 'chime' },
        notifySounds = { 'default', 'tap', 'none' },
        themes = { 'dark', 'light' },
        cases = { 'black', 'blue', 'green', 'orange', 'pink', 'purple', 'red', 'yellow' },
    },

    Limits = {
        Contacts = 300,
        Blocked = 100,
        NameLength = 40,
        ContactPhoto = 30000,           -- a contact picture is a small JPEG, at most this many characters
        MessageLength = 500,
        GroupMembers = 12,
        GroupName = 32,
        PageSize = 30,                -- messages / notifications / mail per page
        Notifications = 100,          -- kept per character (oldest removed)
        Mail = 200,                   -- kept per character (oldest removed)
    },

    Calls = {
        RingSeconds = 30,
        ChannelBase = 5000,           -- pma-voice call channel = ChannelBase + call id
    },
    -- ---- App settings ----
    Flock = { PostLength = 280, PageSize = 20, PostCooldownMs = 5000, MaxMentions = 5 },
    Bank = { MaxTransfer = 250000 },
    Market = {
        TitleLength = 48, BodyLength = 300, MaxPrice = 10000000, ListingDays = 7, MaxActive = 5, PageSize = 25,
        Categories = { 'vehicles', 'items', 'services', 'property', 'other' },
    },
    Notes = { Max = 100, TitleLength = 48, BodyLength = 2000 },

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

    Voicemail = { Max = 50, Length = 500, AudioSeconds = 30, AudioChars = 400000 },   -- a recording: at most this long and this big (base64 characters)

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

    -- Account (email + password, like an Apple ID) and PIN lock.
    Account = { Domain = 'veylid.com', UsernameMin = 3, UsernameMax = 24, PasswordMin = 6 },
    Lock = { GraceSeconds = 10, MaxAttempts = 5, LockoutSeconds = 300 },   -- reopen within the grace period without the PIN; 5 wrong tries lock it for 5 minutes

    -- SIM card: without one the phone has no service (no calls, texts, Flock, bank transfers, ...). Offline tools still work.
    -- Buy a `sim_card` item (shops) and drag it into the SIM slot on the body panel of your inventory. Existing characters keep service.
    Sim = { Required = true, Item = 'sim_card' },

    Share = { Range = 4.0, ExpireSeconds = 60, CooldownSeconds = 30 },   -- "Share my number": metres, how long the prompt lasts, per-pair cooldown
    Voice = 'auto',                   -- 'auto' = pma-voice when it is started; calls are disabled without a voice resource

    -- The tablet item (use handler `phone_tablet`): commands its menu runs.
    Tablet = { Mdt = 'mdt', Dispatch = 'dispatch' },

    Animations = {
        -- In-hand prop: sd_phone_<case> from the sd-phone prop pack when it is streamed, else the base-game phone.
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
