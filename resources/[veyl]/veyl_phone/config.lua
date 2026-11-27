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
