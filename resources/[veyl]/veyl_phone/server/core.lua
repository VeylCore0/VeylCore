-- veyl_phone server core: tables, accounts (numbers), settings, sessions, the `hello` handshake, pushes.
--
-- A "session" exists while a character is online AND carries the phone item (PhoneConfig.RequireItem). Only a live
-- session gets pushes and rings; everything is stored, so nothing is lost while the phone is away.

Phone = { ready = false, sessions = {}, byNumber = {}, byCid = {} }
local P = PhoneConfig.Presets

-- A phone with a PIN that has not been unlocked refuses every request except these (answering a call must always work).
local WHILE_LOCKED = { hello = true, unlock = true, lock = true, pinReset = true, callAnswer = true, callDecline = true, callEnd = true }
local registerCallback = Veyl.RegisterCallback
Veyl.RegisterCallback = function(name, fn, opts)
    return registerCallback(name, function(src, citizenid, ...)
        if not WHILE_LOCKED[name] then
            local s = Phone.sessions[src]
            if s and s.locked then return Veyl.Err('LOCKED', 'Unlock your phone first') end
        end
        return fn(src, citizenid, ...)
    end, opts)
end

---------------------------------------------------------------------------
-- Tables. The base uses veyl_ph_* tables. The previous phone's veyl_phone_* tables are never changed or dropped;
-- numbers, display names and contacts are copied from them once (so characters keep their number).
---------------------------------------------------------------------------
local MIGRATIONS = {
    {
        id = 'v2_001_base',
        sql = {
            [[CREATE TABLE IF NOT EXISTS veyl_ph_accounts (
                citizenid VARCHAR(16) NOT NULL,
                number VARCHAR(7) NOT NULL,
                display_name VARCHAR(48) NOT NULL,
                settings LONGTEXT NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (citizenid),
                UNIQUE KEY uq_number (number)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS veyl_ph_contacts (
                id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                owner_cid VARCHAR(16) NOT NULL,
                name VARCHAR(40) NOT NULL,
                number VARCHAR(7) NOT NULL,
                note VARCHAR(80) NULL,
                favorite TINYINT(1) NOT NULL DEFAULT 0,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (id),
                UNIQUE KEY uq_owner_number (owner_cid, number)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS veyl_ph_blocks (
                owner_cid VARCHAR(16) NOT NULL,
                number VARCHAR(7) NOT NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (owner_cid, number)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS veyl_ph_notifications (
                id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                citizenid VARCHAR(16) NOT NULL,
                app VARCHAR(32) NOT NULL,
                title VARCHAR(80) NOT NULL,
                body VARCHAR(200) NOT NULL,
                route VARCHAR(128) NULL,
                dedupe VARCHAR(64) NULL,
                is_read TINYINT(1) NOT NULL DEFAULT 0,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (id),
                UNIQUE KEY uq_dedupe (citizenid, dedupe),
                KEY idx_cid (citizenid, id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS veyl_ph_badges (
                citizenid VARCHAR(16) NOT NULL,
                app VARCHAR(32) NOT NULL,
                count INT UNSIGNED NOT NULL DEFAULT 0,
                PRIMARY KEY (citizenid, app)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS veyl_ph_conversations (
                id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                kind ENUM('direct','group') NOT NULL,
                direct_key VARCHAR(16) NULL,
                name VARCHAR(32) NULL,
                created_by VARCHAR(7) NOT NULL,
                last_message_id BIGINT UNSIGNED NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (id),
                UNIQUE KEY uq_direct (direct_key)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS veyl_ph_members (
                conversation_id INT UNSIGNED NOT NULL,
                number VARCHAR(7) NOT NULL,
                role ENUM('member','admin') NOT NULL DEFAULT 'member',
                muted TINYINT(1) NOT NULL DEFAULT 0,
                last_read_id BIGINT UNSIGNED NOT NULL DEFAULT 0,
                joined_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                left_at DATETIME NULL,
                PRIMARY KEY (conversation_id, number),
                KEY idx_number (number, left_at)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS veyl_ph_messages (
                id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                conversation_id INT UNSIGNED NOT NULL,
                sender VARCHAR(7) NOT NULL,
                kind ENUM('text','location','contact','system') NOT NULL DEFAULT 'text',
                body VARCHAR(500) NOT NULL,
                payload VARCHAR(255) NULL,
                client_op VARCHAR(64) NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (id),
                UNIQUE KEY uq_client_op (sender, client_op),
                KEY idx_conv (conversation_id, id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS veyl_ph_calls (
                id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                caller VARCHAR(7) NOT NULL,
                callee VARCHAR(7) NOT NULL,
                started_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                answered_at DATETIME NULL,
                ended_at DATETIME NULL,
                end_reason VARCHAR(24) NULL,
                PRIMARY KEY (id),
                KEY idx_caller (caller, id),
                KEY idx_callee (callee, id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS veyl_ph_mail (
                id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                citizenid VARCHAR(16) NOT NULL,
                sender VARCHAR(64) NOT NULL,
                subject VARCHAR(120) NOT NULL,
                body TEXT NOT NULL,
                is_read TINYINT(1) NOT NULL DEFAULT 0,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (id),
                KEY idx_cid (citizenid, id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        },
    },
    {
        -- Account (email + password), PIN lock and the first-run setup flag. Times are unix seconds.
        id = 'v2_003_security',
        sql = {
            [[ALTER TABLE veyl_ph_accounts
                ADD COLUMN email VARCHAR(64) NULL,
                ADD COLUMN pass_hash VARCHAR(160) NULL,
                ADD COLUMN pin_hash VARCHAR(160) NULL,
                ADD COLUMN pin_fails TINYINT UNSIGNED NOT NULL DEFAULT 0,
                ADD COLUMN pin_locked_until INT UNSIGNED NOT NULL DEFAULT 0,
                ADD COLUMN pass_fails TINYINT UNSIGNED NOT NULL DEFAULT 0,
                ADD COLUMN pass_locked_until INT UNSIGNED NOT NULL DEFAULT 0,
                ADD COLUMN setup_done TINYINT(1) NOT NULL DEFAULT 0,
                ADD UNIQUE KEY uq_email (email)]],
        },
    },
}

local function tableExists(name)
    return MySQL.scalar.await('SELECT 1 FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ?', { name }) ~= nil
end

--- One-time copy of numbers, names and contacts from the previous phone (its tables are left as they are).
local function importPrevious()
    local done = MySQL.scalar.await("SELECT 1 FROM veyl_migrations WHERE resource = ? AND id = 'v2_002_import'", { GetCurrentResourceName() })
    if done then return end
    if tableExists('veyl_phone_accounts') then
        local n = MySQL.update.await([[INSERT IGNORE INTO veyl_ph_accounts (citizenid, number, display_name, created_at)
            SELECT citizenid, number, display_name, created_at FROM veyl_phone_accounts WHERE CHAR_LENGTH(number) = 7]])
        print(('^2[veyl_phone] kept %d existing phone numbers^7'):format(n or 0))
    end
    if tableExists('veyl_phone_contacts') then
        MySQL.update.await([[INSERT IGNORE INTO veyl_ph_contacts (owner_cid, name, number, note, favorite, created_at)
            SELECT owner_cid, LEFT(name, 40), number, note, favorite, created_at FROM veyl_phone_contacts WHERE CHAR_LENGTH(number) = 7]])
    end
    if tableExists('veyl_phone_blocks') then
        MySQL.update.await([[INSERT IGNORE INTO veyl_ph_blocks (owner_cid, number, created_at)
            SELECT owner_cid, number, created_at FROM veyl_phone_blocks WHERE CHAR_LENGTH(number) = 7]])
    end
    MySQL.insert.await("INSERT INTO veyl_migrations (resource, id) VALUES (?, 'v2_002_import')", { GetCurrentResourceName() })
end

Veyl.Startup({ 'veyl_core', 'veyl_inventory' }, function()
    if not Veyl.Migrate(MIGRATIONS) then return false end
    importPrevious()
    Phone.ready = true
    TriggerEvent('veyl_phone:ready')
end)

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
function Phone.Decode(s, default)
    if type(s) ~= 'string' or s == '' then return default end
    local ok, v = pcall(json.decode, s)
    if ok and v ~= nil then return v end
    return default
end

local rate = {}
--- Per-player, per-action limiter on top of the callback cooldown. Returns false when called again within `ms`.
function Phone.Rate(src, key, ms)
    rate[src] = rate[src] or {}
    local now = GetGameTimer()
    if rate[src][key] and now - rate[src][key] < ms then return false end
    rate[src][key] = now
    return true
end
AddEventHandler('playerDropped', function() rate[source] = nil end)

local function oneOf(v, list, default)
    for _, x in ipairs(list) do if x == v then return v end end
    return default
end

--- Settings the UI may store. Unknown keys are dropped; bad values fall back to the defaults.
function Phone.CleanSettings(s)
    s = type(s) == 'table' and s or {}
    local out = {
        wallpaper = oneOf(s.wallpaper, P.wallpapers, P.wallpapers[1]),
        accent = oneOf(s.accent, P.accents, P.accents[1]),
        ringtone = oneOf(s.ringtone, P.ringtones, P.ringtones[1]),
        notifySound = oneOf(s.notifySound, P.notifySounds, P.notifySounds[1]),
        theme = oneOf(s.theme, P.themes, P.themes[1]),
        case = oneOf(s.case, P.cases, P.cases[1]),
        volume = (type(s.volume) == 'number' and s.volume == s.volume) and math.max(0, math.min(100, math.floor(s.volume))) or 70,
        dnd = s.dnd == true,                 -- Do Not Disturb: calls go to missed, notifications are silent
        airplane = s.airplane == true,       -- not reachable: no calls; messages are kept for later
        silent = s.silent == true,           -- no sounds, vibration only
        streamer = s.streamer == true,       -- hide own number in the UI
        size = (type(s.size) == 'number' and s.size == s.size) and math.max(60, math.min(140, math.floor(s.size))) or 100, -- phone size on screen, percent
        brightness = (type(s.brightness) == 'number' and s.brightness == s.brightness) and math.max(20, math.min(100, math.floor(s.brightness))) or 100,
        installed = {},                      -- non-core apps installed from the App Store
        home = {},                           -- home-screen order (app ids)
    }
    local known = {}
    for _, a in ipairs(PhoneConfig.Apps) do known[a.id] = a end
    local seen = {}
    for _, id in ipairs(type(s.installed) == 'table' and s.installed or {}) do
        if type(id) == 'string' and known[id] and not known[id].core and not seen[id] then seen[id] = true out.installed[#out.installed + 1] = id end
    end
    seen = {}
    for _, id in ipairs(type(s.home) == 'table' and s.home or {}) do
        if type(id) == 'string' and #id <= 32 and id:match('^[%w_]+$') and not seen[id] and #out.home < 60 then seen[id] = true out.home[#out.home + 1] = id end
    end
    return out
end

local function defaultSettings()
    local s = Phone.CleanSettings({})
    for _, a in ipairs(PhoneConfig.Apps) do if a.preinstalled then s.installed[#s.installed + 1] = a.id end end
    return s
end

---------------------------------------------------------------------------
-- Accounts
---------------------------------------------------------------------------
local function newNumber()
    for _ = 1, 50 do
        local prefix = PhoneConfig.NumberPrefixes[math.random(#PhoneConfig.NumberPrefixes)]
        local n = ('%s%04d'):format(prefix, math.random(0, 9999))
        if not MySQL.scalar.await('SELECT 1 FROM veyl_ph_accounts WHERE number = ?', { n }) then return n end
    end
    return nil
end

--- The character's account, created on first use (a number is picked once and kept forever).
function Phone.Account(citizenid, displayName)
    local acc = MySQL.single.await('SELECT * FROM veyl_ph_accounts WHERE citizenid = ?', { citizenid })
    if acc then return acc end
    for _ = 1, 3 do
        local n = newNumber()
        if n then
            local ok = pcall(MySQL.insert.await, 'INSERT INTO veyl_ph_accounts (citizenid, number, display_name, settings) VALUES (?, ?, ?, ?)',
                { citizenid, n, (displayName or 'Citizen'):sub(1, 48), json.encode(defaultSettings()) })
            if ok then return MySQL.single.await('SELECT * FROM veyl_ph_accounts WHERE citizenid = ?', { citizenid }) end
        end
    end
    return nil
end

function Phone.CidByNumber(number)
    number = PhoneUtil.Normalize(number)
    return number and MySQL.scalar.await('SELECT citizenid FROM veyl_ph_accounts WHERE number = ?', { number }) or nil
end

function Phone.NumberOf(citizenid)
    local s = Phone.byCid[citizenid]
    if s then return s.number end
    return MySQL.scalar.await('SELECT number FROM veyl_ph_accounts WHERE citizenid = ?', { citizenid })
end

function Phone.SettingsOf(citizenid)
    local s = Phone.byCid[citizenid]
    if s then return s.settings end
    return Phone.CleanSettings(Phone.Decode(MySQL.scalar.await('SELECT settings FROM veyl_ph_accounts WHERE citizenid = ?', { citizenid }), {}))
end

--- How `viewerCid` sees `number`: their contact name if saved, else the formatted number.
function Phone.DisplayFor(viewerCid, number)
    local name = viewerCid and MySQL.scalar.await('SELECT name FROM veyl_ph_contacts WHERE owner_cid = ? AND number = ?', { viewerCid, number })
    return name or PhoneUtil.Format(number)
end

---------------------------------------------------------------------------
-- Sessions
---------------------------------------------------------------------------
function Phone.HasDevice(src)
    local item = PhoneConfig.RequireItem
    if not item then return true end
    local ok, n = pcall(function() return exports.veyl_inventory:GetItemCount(src, item) end)
    return ok and (n or 0) > 0
end

--- The live session for a player, or nil (no character, other character, or no phone).
function Phone.Session(src)
    local s = Phone.sessions[src]
    if not s then return nil end
    if Veyl.GetCitizenId(src) ~= s.cid then Phone.EndSession(src, 'character_changed') return nil end
    return s
end

--- The live, reachable session for a number (has the phone item right now), or nil.
function Phone.SessionByNumber(number)
    local s = Phone.byNumber[number]
    if s and Phone.Session(s.src) and Phone.HasDevice(s.src) then return s end
    return nil
end

function Phone.EndSession(src, reason)
    local s = Phone.sessions[src]
    if not s then return end
    Phone.sessions[src] = nil
    if Phone.byNumber[s.number] == s then Phone.byNumber[s.number] = nil end
    if Phone.byCid[s.cid] == s then Phone.byCid[s.cid] = nil end
    TriggerEvent('veyl_phone:sessionEnded', src, s, reason)
    if GetPlayerName(src) then TriggerClientEvent('veyl_phone:sessionEnded', src, reason) end
end

AddEventHandler('playerDropped', function() Phone.EndSession(source, 'dropped') end)
AddEventHandler('VeylCore:Server:OnPlayerUnload', function(src) Phone.EndSession(src, 'logout') end)

-- Losing the phone item ends the session (the client closes the phone, calls hang up).
CreateThread(function()
    while true do
        Wait(15000)
        for src in pairs(Phone.sessions) do
            if not Phone.HasDevice(src) then Phone.EndSession(src, 'no_device') end
        end
    end
end)

--- Push to a player's phone UI (only while the session is live). See docs/PHONE.md for every event.
function Phone.Push(src, event, data)
    if Phone.sessions[src] then TriggerClientEvent('veyl_phone:push', src, event, data) end
end

function Phone.PushCid(citizenid, event, data)
    local s = Phone.byCid[citizenid]
    if s then Phone.Push(s.src, event, data) end
end

---------------------------------------------------------------------------
-- Handshake and settings
---------------------------------------------------------------------------
--- Everything the UI needs to draw the phone. A locked phone (PIN set, not entered) gets no personal data at all.
function Phone.HelloData(s, acc)
    local L = PhoneConfig.Limits
    local locked = s.locked == true
    local data = {
        number = locked and '' or acc.number, display = locked and '' or PhoneUtil.Format(acc.number), name = locked and '' or acc.display_name,
        settings = s.settings, voice = Calls.Availability(), call = Calls.StateFor(s.src), locked = locked,
        security = { email = (not locked) and s.email or nil, hasPin = s.hasPin, setupDone = s.setupDone, grace = PhoneConfig.Lock.GraceSeconds,
            domain = PhoneConfig.Account.Domain, passwordMin = PhoneConfig.Account.PasswordMin },
        presets = P,
        limits = { message = L.MessageLength, groupMembers = L.GroupMembers, groupName = L.GroupName, name = L.NameLength, pageSize = L.PageSize },
        serverTime = os.time(),
    }
    if locked then
        data.apps, data.unread, data.badges = {}, { messages = 0, notifications = 0, mail = 0 }, {}
    else
        data.apps = Apps.ListFor(s.settings)
        data.unread = { messages = Messages.UnreadTotal(acc.number), notifications = Notify.UnreadCount(s.cid), mail = Mail.UnreadCount(s.cid) }
        data.badges = Notify.Badges(s.cid)
    end
    return data
end

function Phone.HelloFor(src)
    local s = Phone.sessions[src]
    local acc = s and MySQL.single.await('SELECT * FROM veyl_ph_accounts WHERE citizenid = ?', { s.cid })
    return s and acc and Phone.HelloData(s, acc) or nil
end

--- hello: starts (or refreshes) the session and returns what the UI needs. Requires the phone item.
Veyl.RegisterCallback('hello', function(src, citizenid)
    if not Phone.ready then return Veyl.Err('NOT_READY', 'The phone service is starting') end
    if not Phone.HasDevice(src) then return Veyl.Err('NO_DEVICE', 'You need a phone') end
    local pd = Veyl.GetPlayerData(src)
    local ci = pd and pd.charinfo or {}
    local name = PhoneUtil.Clean(('%s %s'):format(ci.firstname or '', ci.lastname or ''), 48) or 'Citizen'
    local acc = Phone.Account(citizenid, name)
    if not acc then return Veyl.Err('DATABASE_ERROR', 'Could not set up your phone') end
    local settings = Phone.CleanSettings(Phone.Decode(acc.settings, defaultSettings()))
    Player(src).state:set('phoneCase', settings.case, true)
    local old = Phone.sessions[src]
    if old and old.cid ~= citizenid then Phone.EndSession(src, 'character_changed') old = nil end
    local hasPin = type(acc.pin_hash) == 'string' and acc.pin_hash ~= ''
    local keep = old and old.unlockedUntil or nil -- still inside the grace period after putting the phone away
    local s = { src = src, cid = citizenid, number = acc.number, name = acc.display_name, settings = settings,
        hasPin = hasPin, email = acc.email, setupDone = acc.setup_done == 1 or acc.setup_done == true, unlockedUntil = keep }
    s.locked = hasPin and not (keep ~= nil and os.time() < keep)
    Phone.sessions[src] = s
    Phone.byNumber[acc.number] = s
    Phone.byCid[citizenid] = s
    TriggerEvent('veyl_phone:sessionStarted', src, s)
    return Veyl.Ok(Phone.HelloData(s, acc))
end, { cooldown = 1000 })

Veyl.RegisterCallback('settingsSave', function(src, citizenid, input)
    local s = Phone.Session(src)
    if not s then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    if not Phone.Rate(src, 'settings', 400) then return Veyl.Err('RATE_LIMITED', 'Slow down') end
    -- Partial updates: unspecified keys keep their current value.
    local merged = {}
    for k, v in pairs(s.settings) do merged[k] = v end
    if type(input) == 'table' then for k, v in pairs(input) do merged[k] = v end end
    local clean = Phone.CleanSettings(merged)
    MySQL.update.await('UPDATE veyl_ph_accounts SET settings = ? WHERE citizenid = ?', { json.encode(clean), citizenid })
    s.settings = clean
    Player(src).state:set('phoneCase', clean.case, true)
    if clean.airplane and Calls.bySrc[src] then Calls.EndFor(src, 'unavailable') end
    return Veyl.Ok(clean)
end)

Veyl.RegisterCallback('profileSave', function(src, citizenid, name)
    local s = Phone.Session(src)
    if not s then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    local clean = PhoneUtil.Clean(name, 48)
    if not clean or #clean < 2 then return Veyl.Err('INVALID_INPUT', 'Use 2 to 48 characters') end
    MySQL.update.await('UPDATE veyl_ph_accounts SET display_name = ? WHERE citizenid = ?', { clean, citizenid })
    s.name = clean
    return Veyl.Ok({ name = clean }, 'Profile updated')
end, { cooldown = 2000 })
