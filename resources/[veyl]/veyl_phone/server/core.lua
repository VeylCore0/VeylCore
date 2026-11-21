-- veyl_phone server core: migrations, accounts (numbers), settings, sessions.
-- All phone data is keyed by the character (citizenid) or its number. A "phone session" exists while the character
-- is online AND carries the phone item (PhoneConfig.RequireItem); only then are messages delivered and calls rung.

Phone = { ready = false, sessions = {}, byNumber = {}, byCid = {} }
local L = PhoneConfig.Limits

Veyl.Startup({ 'veyl_core', 'veyl_inventory' }, function()
    local ok = Veyl.Migrate({
        {
            id = '001_phone',
            sql = {
                [[CREATE TABLE IF NOT EXISTS veyl_phone_accounts (
                    citizenid VARCHAR(16) NOT NULL,
                    number VARCHAR(10) NOT NULL,
                    display_name VARCHAR(48) NOT NULL,
                    settings LONGTEXT NULL,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (citizenid),
                    UNIQUE KEY uq_number (number)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
                [[CREATE TABLE IF NOT EXISTS veyl_phone_contacts (
                    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                    owner_cid VARCHAR(16) NOT NULL,
                    name VARCHAR(40) NOT NULL,
                    number VARCHAR(10) NOT NULL,
                    note VARCHAR(80) NULL,
                    color TINYINT UNSIGNED NOT NULL DEFAULT 0,
                    favorite TINYINT(1) NOT NULL DEFAULT 0,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (id),
                    UNIQUE KEY uq_owner_number (owner_cid, number),
                    KEY idx_owner (owner_cid)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
                [[CREATE TABLE IF NOT EXISTS veyl_phone_blocks (
                    owner_cid VARCHAR(16) NOT NULL,
                    number VARCHAR(10) NOT NULL,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (owner_cid, number)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
                [[CREATE TABLE IF NOT EXISTS veyl_phone_notifications (
                    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                    citizenid VARCHAR(16) NOT NULL,
                    app VARCHAR(32) NOT NULL,
                    title VARCHAR(80) NOT NULL,
                    body VARCHAR(160) NOT NULL,
                    route VARCHAR(255) NULL,
                    dedupe VARCHAR(64) NULL,
                    is_read TINYINT(1) NOT NULL DEFAULT 0,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (id),
                    UNIQUE KEY uq_dedupe (citizenid, dedupe),
                    KEY idx_cid (citizenid, id)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
                [[CREATE TABLE IF NOT EXISTS veyl_phone_conversations (
                    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                    kind ENUM('direct','group') NOT NULL,
                    direct_key VARCHAR(24) NULL,
                    name VARCHAR(32) NULL,
                    created_by VARCHAR(10) NOT NULL,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    last_message_id BIGINT UNSIGNED NULL,
                    PRIMARY KEY (id),
                    UNIQUE KEY uq_direct (direct_key)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
                [[CREATE TABLE IF NOT EXISTS veyl_phone_members (
                    conversation_id INT UNSIGNED NOT NULL,
                    number VARCHAR(10) NOT NULL,
                    role ENUM('member','admin') NOT NULL DEFAULT 'member',
                    muted TINYINT(1) NOT NULL DEFAULT 0,
                    last_read_id BIGINT UNSIGNED NOT NULL DEFAULT 0,
                    joined_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    left_at TIMESTAMP NULL,
                    PRIMARY KEY (conversation_id, number),
                    KEY idx_number (number, left_at)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
                [[CREATE TABLE IF NOT EXISTS veyl_phone_messages (
                    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                    conversation_id INT UNSIGNED NOT NULL,
                    sender VARCHAR(10) NOT NULL,
                    kind ENUM('text','contact','location','system') NOT NULL,
                    body VARCHAR(500) NOT NULL,
                    payload VARCHAR(255) NULL,
                    client_op VARCHAR(64) NULL,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (id),
                    UNIQUE KEY uq_client_op (sender, client_op),
                    KEY idx_conv (conversation_id, id)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
                [[CREATE TABLE IF NOT EXISTS veyl_phone_receipts (
                    message_id BIGINT UNSIGNED NOT NULL,
                    number VARCHAR(10) NOT NULL,
                    delivered_at TIMESTAMP NULL,
                    read_at TIMESTAMP NULL,
                    PRIMARY KEY (message_id, number),
                    KEY idx_pending (number, delivered_at)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
                [[CREATE TABLE IF NOT EXISTS veyl_phone_calls (
                    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                    caller VARCHAR(10) NOT NULL,
                    callee VARCHAR(10) NOT NULL,
                    started_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    answered_at TIMESTAMP NULL,
                    ended_at TIMESTAMP NULL,
                    end_reason VARCHAR(24) NULL,
                    PRIMARY KEY (id),
                    KEY idx_caller (caller, id),
                    KEY idx_callee (callee, id)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            },
        },
    })
    if not ok then return false end
    -- Calls that were live when the server stopped have ended.
    MySQL.update.await("UPDATE veyl_phone_calls SET ended_at = CURRENT_TIMESTAMP, end_reason = 'server_restart' WHERE ended_at IS NULL")
    Phone.ready = true
    TriggerEvent('veyl_phone:ready')
    return true
end)

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
function Phone.Decode(s, default)
    if not s or s == '' then return default end
    local ok, v = pcall(json.decode, s)
    return ok and v ~= nil and v or default
end

function Phone.Clean(s, maxLen)
    if type(s) ~= 'string' then return nil end
    s = s:gsub('[%c]', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if #s == 0 then return nil end
    return s:sub(1, maxLen)
end

function Phone.NormalizeNumber(n)
    if type(n) ~= 'string' and type(n) ~= 'number' then return nil end
    local digits = tostring(n):gsub('%D', '')
    if #digits ~= 7 then return nil end
    return digits
end

function Phone.FormatNumber(n) return n and (n:sub(1, 3) .. '-' .. n:sub(4)) or nil end

local rate = {}
--- Simple per-player, per-action rate limit. Returns true when the action may proceed.
function Phone.Rate(src, key, ms)
    local now = GetGameTimer()
    rate[src] = rate[src] or {}
    if (rate[src][key] or 0) > now then return false end
    rate[src][key] = now + ms
    return true
end
AddEventHandler('playerDropped', function() rate[source] = nil end)

---------------------------------------------------------------------------
-- Settings (validated; unknown keys dropped)
---------------------------------------------------------------------------
local function oneOf(v, list, default) for _, x in ipairs(list) do if x == v then return v end end return default end
local function num(v, lo, hi, default) v = tonumber(v) if not v or v ~= v then return default end return math.max(lo, math.min(hi, v)) end
local function bool(v, default) if type(v) == 'boolean' then return v end return default end

local APP_IDS = {}
for _, a in ipairs(PhoneConfig.Apps) do APP_IDS[a.id] = true end

local function cleanLayout(layout)
    if type(layout) ~= 'table' then return nil end
    local out, seen = {}, {}
    for _, entry in ipairs(layout) do
        if #out >= 40 then break end
        if type(entry) == 'string' and not seen[entry] and #entry <= 40 then
            seen[entry] = true
            out[#out + 1] = entry
        elseif type(entry) == 'table' and type(entry.apps) == 'table' then
            local apps = {}
            for _, id in ipairs(entry.apps) do
                if type(id) == 'string' and not seen[id] and #id <= 40 and #apps < 12 then seen[id] = true apps[#apps + 1] = id end
            end
            if #apps > 0 then out[#out + 1] = { folder = Phone.Clean(entry.folder, 20) or 'Folder', apps = apps } end
        end
    end
    return out
end

function Phone.CleanSettings(s)
    s = type(s) == 'table' and s or {}
    local appPrefs = {}
    if type(s.appPrefs) == 'table' then
        for id, p in pairs(s.appPrefs) do
            if type(id) == 'string' and #id <= 40 and type(p) == 'table' then appPrefs[id] = { muted = p.muted == true } end
        end
    end
    return {
        wallpaper = oneOf(s.wallpaper, PhoneConfig.Wallpapers, PhoneConfig.Wallpapers[1]),
        accent = oneOf(s.accent, PhoneConfig.Accents, PhoneConfig.Accents[1]),
        ringtone = oneOf(s.ringtone, PhoneConfig.Ringtones, PhoneConfig.Ringtones[1]),
        notifySound = oneOf(s.notifySound, PhoneConfig.NotificationSounds, PhoneConfig.NotificationSounds[1]),
        ringVolume = num(s.ringVolume, 0, 100, 70),
        notifyVolume = num(s.notifyVolume, 0, 100, 60),
        silent = bool(s.silent, false),
        dnd = bool(s.dnd, false),
        lockPreview = oneOf(s.lockPreview, { 'full', 'sender', 'hidden' }, 'sender'),
        readReceipts = bool(s.readReceipts, true),
        showBank = bool(s.showBank, false),
        widgets = {
            clock = bool(type(s.widgets) == 'table' and s.widgets.clock, true),
            recent = bool(type(s.widgets) == 'table' and s.widgets.recent, true),
            bank = bool(type(s.widgets) == 'table' and s.widgets.bank, true),
        },
        scale = num(s.scale, 0.75, 1.3, 1.0),
        position = oneOf(s.position, { 'bottom-right', 'bottom-left', 'center-right' }, 'bottom-right'),
        reducedMotion = bool(s.reducedMotion, false),
        layout = cleanLayout(s.layout),
        appPrefs = appPrefs,
    }
end

---------------------------------------------------------------------------
-- Accounts: one per character, created on first use
---------------------------------------------------------------------------
local function newNumber()
    for _ = 1, 30 do
        local prefix = PhoneConfig.NumberPrefixes[math.random(1, #PhoneConfig.NumberPrefixes)]
        local n = ('%s%04d'):format(prefix, math.random(0, 9999))
        if not MySQL.scalar.await('SELECT 1 FROM veyl_phone_accounts WHERE number = ?', { n }) then return n end
    end
    return nil
end

function Phone.Account(citizenid, displayName)
    local row = MySQL.single.await('SELECT citizenid, number, display_name, settings FROM veyl_phone_accounts WHERE citizenid = ?', { citizenid })
    if row then return row end
    for _ = 1, 5 do
        local n = newNumber()
        if not n then break end
        local ok = pcall(MySQL.insert.await, 'INSERT INTO veyl_phone_accounts (citizenid, number, display_name) VALUES (?, ?, ?)',
            { citizenid, n, (displayName or 'Citizen'):sub(1, 48) })
        if ok then return MySQL.single.await('SELECT citizenid, number, display_name, settings FROM veyl_phone_accounts WHERE citizenid = ?', { citizenid }) end
    end
    return nil
end

--- citizenid for a number, or nil (deleted characters' numbers resolve to nil: "unavailable").
function Phone.CidByNumber(number)
    local cid = MySQL.scalar.await([[SELECT a.citizenid FROM veyl_phone_accounts a JOIN veyl_players p ON p.citizenid = a.citizenid
        WHERE a.number = ? AND p.deleted_at IS NULL]], { number })
    return cid
end

function Phone.NumberOf(citizenid)
    local s = Phone.byCid[citizenid]
    if s then return s.number end
    return MySQL.scalar.await('SELECT number FROM veyl_phone_accounts WHERE citizenid = ?', { citizenid })
end

function Phone.SettingsOf(citizenid)
    local s = Phone.byCid[citizenid]
    if s then return s.settings end
    return Phone.CleanSettings(Phone.Decode(MySQL.scalar.await('SELECT settings FROM veyl_phone_accounts WHERE citizenid = ?', { citizenid }), {}))
end

---------------------------------------------------------------------------
-- Sessions
---------------------------------------------------------------------------
function Phone.HasDevice(src)
    local item = PhoneConfig.RequireItem
    if not item then return true end
    return (exports.veyl_inventory:GetItemCount(src, item) or 0) > 0
end

--- Session for a source if the character is online with a phone; nil otherwise.
function Phone.Session(src)
    local s = Phone.sessions[src]
    if not s then return nil end
    if exports.veyl_core:GetCitizenId(src) ~= s.cid then Phone.EndSession(src, 'character_changed') return nil end
    return s
end

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
end

AddEventHandler('playerDropped', function() Phone.EndSession(source, 'dropped') end)
AddEventHandler('VeylCore:Server:OnPlayerUnload', function(src) Phone.EndSession(src, 'logout') end)

--- hello: starts (or refreshes) the phone session and returns everything the shell needs. Requires the phone item.
Veyl.RegisterCallback('hello', function(src, citizenid)
    if not Phone.ready then return Veyl.Err('NOT_READY', 'Phone service is starting') end
    if not Phone.HasDevice(src) then return Veyl.Err('NO_DEVICE', 'You need a phone') end
    local pd = Veyl.GetPlayerData(src)
    local name = pd and ('%s %s'):format(pd.charinfo.firstname or '', pd.charinfo.lastname or ''):gsub('^%s+', '') or 'Citizen'
    local acc = Phone.Account(citizenid, name)
    if not acc then return Veyl.Err('DATABASE_ERROR', 'Could not set up your phone') end
    local settings = Phone.CleanSettings(Phone.Decode(acc.settings, {}))
    local old = Phone.sessions[src]
    if old and old.cid ~= citizenid then Phone.EndSession(src, 'character_changed') end
    local s = { src = src, cid = citizenid, number = acc.number, name = acc.display_name, settings = settings }
    Phone.sessions[src] = s
    Phone.byNumber[acc.number] = s
    Phone.byCid[citizenid] = s
    TriggerEvent('veyl_phone:sessionStarted', src, s)
    local apps = {}
    for _, a in ipairs(PhoneConfig.Apps) do if a.enabled then apps[#apps + 1] = { id = a.id, label = a.label, dock = a.dock == true } end end
    return Veyl.Ok({
        number = acc.number, display = Phone.FormatNumber(acc.number), name = acc.display_name, settings = settings,
        apps = apps, voice = Calls and Calls.Availability() or { available = false, reason = 'Calls are not loaded' },
        serverTime = os.time(), unread = Messages and Messages.UnreadTotal(acc.number) or 0,
        notificationsUnread = Notify and Notify.UnreadCount(citizenid) or 0,
        badges = Notify and Notify.Badges(citizenid) or {},
        presets = { wallpapers = PhoneConfig.Wallpapers, accents = PhoneConfig.Accents, ringtones = PhoneConfig.Ringtones,
            notifySounds = PhoneConfig.NotificationSounds },
        limits = { message = L.MessageLength, groupMembers = L.GroupMembers },
    })
end, { cooldown = 1000 })

Veyl.RegisterCallback('saveSettings', function(src, citizenid, input)
    local s = Phone.Session(src)
    if not s then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    if not Phone.Rate(src, 'settings', 500) then return Veyl.Err('RATE_LIMITED', 'Slow down') end
    local clean = Phone.CleanSettings(input)
    MySQL.update.await('UPDATE veyl_phone_accounts SET settings = ? WHERE citizenid = ?', { json.encode(clean), citizenid })
    s.settings = clean
    return Veyl.Ok(clean)
end)

Veyl.RegisterCallback('setProfile', function(src, citizenid, name)
    local s = Phone.Session(src)
    if not s then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    local clean = Phone.Clean(name, 48)
    if not clean or #clean < 2 then return Veyl.Err('INVALID_INPUT', 'Use 2 to 48 characters') end
    MySQL.update.await('UPDATE veyl_phone_accounts SET display_name = ? WHERE citizenid = ?', { clean, citizenid })
    s.name = clean
    return Veyl.Ok({ name = clean }, 'Profile updated')
end, { cooldown = 2000 })

--- Push to a session's client (only if the session is live).
function Phone.Push(src, event, data)
    if Phone.sessions[src] then TriggerClientEvent('veyl_phone:push', src, event, data) end
end
