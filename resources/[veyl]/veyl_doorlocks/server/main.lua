-- veyl_doorlocks server: registered doors, access rules, synchronised lock state, managers, keys, breaching and the
-- in-game editor. The server owns every decision; clients only show doors and ask.

Doors = { list = {}, ready = false }
local C = DoorConfig
local autoTimers = {}   -- [doorId] = token
local lastToggle = {}   -- [src] = time
local breaches = {}     -- [src] = { doorId, method, at, token }

local function decode(s, d) if not s or s == '' then return d end local ok, v = pcall(json.decode, s) return ok and v ~= nil and v or d end
local function isAdmin(src) return Veyl.HasPermission(src, C.AdminPermission) or Veyl.HasPermission(src, 'admin') end
local function log(doorId, citizenid, action, detail)
    MySQL.insert('INSERT INTO veyl_door_log (door_id, citizenid, action, detail) VALUES (?, ?, ?, ?)',
        { doorId, citizenid or 'system', action, detail and tostring(detail):sub(1, 120) or nil })
end

---------------------------------------------------------------------------
-- Storage
---------------------------------------------------------------------------
Veyl.Startup({ 'veyl_core', 'veyl_inventory' }, function()
    local ok = Veyl.Migrate({
        {
            id = '001_doorlocks',
            sql = {
                [[CREATE TABLE IF NOT EXISTS veyl_doors (
                    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                    name VARCHAR(48) NOT NULL,
                    entities LONGTEXT NOT NULL,
                    settings LONGTEXT NOT NULL,
                    locked TINYINT(1) NOT NULL DEFAULT 1,
                    key_rev INT UNSIGNED NOT NULL DEFAULT 1,
                    created_by VARCHAR(64) NULL,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                    PRIMARY KEY (id)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
                [[CREATE TABLE IF NOT EXISTS veyl_door_grants (
                    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                    door_id INT UNSIGNED NOT NULL,
                    citizenid VARCHAR(16) NOT NULL,
                    granted_by VARCHAR(16) NOT NULL,
                    expires_at DATETIME NOT NULL,
                    revoked_at DATETIME NULL,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (id),
                    KEY idx_door (door_id, citizenid, expires_at)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
                [[CREATE TABLE IF NOT EXISTS veyl_door_keys (
                    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                    door_id INT UNSIGNED NOT NULL,
                    key_rev INT UNSIGNED NOT NULL,
                    issued_by VARCHAR(16) NOT NULL,
                    issued_to VARCHAR(16) NOT NULL,
                    op_id VARCHAR(64) NOT NULL,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (id),
                    UNIQUE KEY uq_op (op_id),
                    KEY idx_door (door_id, key_rev)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
                [[CREATE TABLE IF NOT EXISTS veyl_door_log (
                    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                    door_id INT UNSIGNED NOT NULL,
                    citizenid VARCHAR(64) NOT NULL,
                    action VARCHAR(24) NOT NULL,
                    detail VARCHAR(120) NULL,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (id),
                    KEY idx_door (door_id, id)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            },
        },
    })
    if not ok then return false end
    MySQL.update.await('DELETE FROM veyl_door_log WHERE created_at < DATE_SUB(NOW(), INTERVAL ? DAY)', { C.LogKeepDays })
    for _, r in ipairs(MySQL.query.await('SELECT * FROM veyl_doors') or {}) do
        local d = { id = r.id, name = r.name, entities = decode(r.entities, {}), settings = Doors.CleanSettings(decode(r.settings, {})), keyRev = r.key_rev }
        d.locked = C.StateOnRestart == 'last' and (r.locked == 1 or r.locked == true) or d.settings.locked
        Doors.list[d.id] = d
    end
    Doors.ready = true
    TriggerClientEvent('veyl_doorlocks:all', -1, Doors.PublicList())
    return true
end)

---------------------------------------------------------------------------
-- Validation (shared by the editor; nothing from the client is trusted)
---------------------------------------------------------------------------
local function num(v, lo, hi, d) v = tonumber(v) if not v or v ~= v then return d end return math.max(lo, math.min(hi, v)) end
local function str(v, max) if type(v) ~= 'string' then return nil end v = v:gsub('[%c<>]', ''):gsub('^%s+', ''):gsub('%s+$', '') return #v > 0 and v:sub(1, max) or nil end

local function gradeMap(t, kind)
    local out = {}
    if type(t) ~= 'table' then return out end
    local defs = kind == 'job' and exports.veyl_core:GetJobs() or exports.veyl_core:GetGangs()
    for name, grade in pairs(t) do
        if type(name) == 'string' and defs[name] then out[name] = math.floor(num(grade, 0, 50, 0)) end
    end
    return out
end

function Doors.CleanSettings(s)
    s = type(s) == 'table' and s or {}
    local a, b = type(s.access) == 'table' and s.access or {}, type(s.breach) == 'table' and s.breach or {}
    local citizens, items = {}, {}
    for _, c in ipairs(type(a.citizens) == 'table' and a.citizens or {}) do
        if type(c) == 'table' and type(c.citizenid) == 'string' and c.citizenid:match('^[%w]+$') and #citizens < 50 then
            citizens[#citizens + 1] = { citizenid = c.citizenid:sub(1, 16), name = str(c.name, 48) or c.citizenid }
        end
    end
    local defs = exports.veyl_inventory:Items() or {}
    for _, i in ipairs(type(a.items) == 'table' and a.items or {}) do
        if type(i) == 'string' and defs[i] and i ~= C.Items.key and #items < 10 then items[#items + 1] = i end
    end
    return {
        locked = s.locked ~= false,
        autoLock = math.floor(num(s.autoLock, 0, C.AutoLockMax, 0)),
        distance = num(s.distance, C.DistanceRange[1], C.DistanceRange[2], 2.0),
        hidePrompt = s.hidePrompt == true,
        access = {
            jobs = gradeMap(a.jobs, 'job'), gangs = gradeMap(a.gangs, 'gang'), requireDuty = a.requireDuty == true,
            citizens = citizens, items = items, keys = a.keys ~= false, managers = gradeMap(a.managers, 'job'),
        },
        breach = {
            lockpick = b.lockpick == true, lockpickChance = num(b.lockpickChance, 0.05, 0.95, 0.35),
            ram = b.ram == true, ramJobs = gradeMap(b.ramJobs, 'job'),
            relock = math.floor(num(b.relock, 0, C.AutoLockMax, C.Breach.DefaultRelockSeconds)),
        },
    }
end

local function cleanEntities(list)
    if type(list) ~= 'table' or #list == 0 or #list > C.MaxEntities then return nil end
    local out = {}
    for _, e in ipairs(list) do
        local x, y, z, m = tonumber(e.x), tonumber(e.y), tonumber(e.z), tonumber(e.model)
        if not (x and y and z and m) or math.abs(x) > 10000 or math.abs(y) > 10000 or z < -200 or z > 3000 or m % 1 ~= 0 then return nil end
        out[#out + 1] = { model = math.floor(m), x = x, y = y, z = z, heading = num(e.heading, -360, 360, 0) }
    end
    return out
end

local function center(d)
    local sx, sy, sz = 0, 0, 0
    for _, e in ipairs(d.entities) do sx, sy, sz = sx + e.x, sy + e.y, sz + e.z end
    local n = #d.entities
    return vector3(sx / n, sy / n, sz / n)
end
Doors.Center = center

--- What clients need to show and run a door (no access lists other than presentation hints).
function Doors.Public(d)
    local mj = {}
    for j in pairs(d.settings.access.managers) do mj[#mj + 1] = j end
    return { id = d.id, name = d.name, entities = d.entities, locked = d.locked, distance = d.settings.distance, hidePrompt = d.settings.hidePrompt,
        lockpick = d.settings.breach.lockpick, ram = d.settings.breach.ram, managerJobs = mj, businessOpen = d.businessOpen == true }
end
function Doors.PublicList() local out = {} for _, d in pairs(Doors.list) do out[#out + 1] = Doors.Public(d) end return out end

---------------------------------------------------------------------------
-- Access
---------------------------------------------------------------------------
local function grantActive(doorId, cid)
    return MySQL.scalar.await('SELECT 1 FROM veyl_door_grants WHERE door_id = ? AND citizenid = ? AND revoked_at IS NULL AND expires_at > NOW()', { doorId, cid }) ~= nil
end

local function hasKey(src, d)
    if not d.settings.access.keys then return false end
    for _, s in ipairs(exports.veyl_inventory:GetSlotsWithItem(src, C.Items.key) or {}) do
        local m = s.metadata or {}
        if m.door == d.id and m.rev == d.keyRev then return true end
    end
    return false
end

local function onDuty(src, job)
    local pd = Veyl.GetPlayerData(src)
    return pd and pd.job and pd.job.name == job and pd.job.onduty == true
end

--- Why a player may use a door ('admin'|'job'|'gang'|'citizen'|'grant'|'item'|'key') or nil.
function Doors.Access(src, d)
    local a = d.settings.access
    local cid = Veyl.GetCitizenId(src)
    if not cid then return nil end
    for _, c in ipairs(a.citizens) do if c.citizenid == cid then return 'citizen' end end
    if next(a.jobs) then
        local job = exports.veyl_core:HasGroup(src, a.jobs)
        if job and (not a.requireDuty or onDuty(src, job)) then return 'job' end
    end
    if next(a.gangs) and exports.veyl_core:HasGroup(src, a.gangs) then return 'gang' end
    for _, item in ipairs(a.items) do if (exports.veyl_inventory:GetItemCount(src, item) or 0) > 0 then return 'item' end end
    if hasKey(src, d) then return 'key' end
    if grantActive(d.id, cid) then return 'grant' end
    if C.AdminBypass and isAdmin(src) then return 'admin' end
    return nil
end

function Doors.IsManager(src, d)
    if isAdmin(src) then return true end
    local m = d.settings.access.managers
    return next(m) ~= nil and exports.veyl_core:HasGroup(src, m) ~= nil
end

local function near(src, d, extra)
    local pc = Veyl.GetPlayerCoords(src)
    return pc ~= nil and #(pc - center(d)) <= d.settings.distance + (extra or 2.0)
end

---------------------------------------------------------------------------
-- Lock state
---------------------------------------------------------------------------
function Doors.SetLocked(d, locked, by, reason, relockIn)
    d.locked = locked == true
    if d.locked then d.businessOpen = nil end
    MySQL.update('UPDATE veyl_doors SET locked = ? WHERE id = ?', { d.locked and 1 or 0, d.id })
    TriggerClientEvent('veyl_doorlocks:state', -1, d.id, d.locked, d.businessOpen == true)
    TriggerEvent('veyl_doorlocks:changed', d.id, d.locked, by, reason)
    local token = {}
    autoTimers[d.id] = token
    local secs = relockIn or (not d.locked and not d.businessOpen and d.settings.autoLock) or 0
    if not d.locked and secs > 0 then
        SetTimeout(secs * 1000, function()
            if autoTimers[d.id] == token and Doors.list[d.id] == d and not d.locked and not d.businessOpen then
                Doors.SetLocked(d, true, 'system', 'auto')
                log(d.id, 'system', 'auto_lock')
            end
        end)
    end
end

Veyl.RegisterCallback('all', function() return Veyl.Ok(Doors.PublicList()) end, { cooldown = 1000 })

--- toggle(id, locked) — lock or unlock a door you can use, standing next to it.
Veyl.RegisterCallback('toggle', function(src, citizenid, id, locked)
    local d = Doors.list[tonumber(id) or -1]
    if not d then return Veyl.Err('NOT_FOUND', 'Unknown door') end
    local now = GetGameTimer()
    if (lastToggle[src] or 0) > now then return Veyl.Err('RATE_LIMITED', 'Slow down') end
    lastToggle[src] = now + C.ToggleCooldownMs
    if not near(src, d) then return Veyl.Err('TOO_FAR', 'Move closer to the door') end
    local why = Doors.Access(src, d)
    if not why then return Veyl.Err('NO_ACCESS', 'You do not have a key for this door') end
    locked = locked == true
    if d.locked == locked then return Veyl.Ok({ locked = d.locked }) end
    Doors.SetLocked(d, locked, citizenid, why)
    log(d.id, citizenid, locked and 'lock' or 'unlock', why)
    if why == 'admin' then Veyl.Audit(src, 'door_admin_use', { door = d.id, locked = locked }) end
    return Veyl.Ok({ locked = d.locked }, locked and 'Locked' or 'Unlocked')
end)

---------------------------------------------------------------------------
-- Managers (business controls): keep open, temporary access, physical keys, change the locks
---------------------------------------------------------------------------
local function managed(src, id)
    local d = Doors.list[tonumber(id) or -1]
    if not d then return nil, Veyl.Err('NOT_FOUND', 'Unknown door') end
    if not Doors.IsManager(src, d) then return nil, Veyl.Err('NO_PERMISSION', 'You do not manage this door') end
    return d
end

local function resolveTarget(src, target)
    if type(target) ~= 'table' then return nil end
    if target.serverId then
        local t = tonumber(target.serverId)
        local a, b = t and Veyl.GetPlayerCoords(src), t and Veyl.GetPlayerCoords(t)
        if not a or not b or t == src or #(a - b) > 6.0 then return nil end
        return Veyl.GetCitizenId(t), t
    end
    if target.number and GetResourceState('veyl_phone') == 'started' then
        local ok, cid = pcall(function() return exports.veyl_phone:GetCitizenByNumber(tostring(target.number)) end)
        if ok and cid then return cid, Veyl.GetSourceByCitizenId(cid) end
    end
    return nil
end

local function charName(cid)
    local s = Veyl.GetSourceByCitizenId(cid)
    local pd = s and Veyl.GetPlayerData(s)
    local ci = pd and pd.charinfo
    if not ci then
        local row = MySQL.single.await('SELECT charinfo FROM veyl_players WHERE citizenid = ?', { cid })
        ci = row and decode(row.charinfo, nil)
    end
    return ci and (('%s %s'):format(ci.firstname or '', ci.lastname or '')) or cid
end

Veyl.RegisterCallback('manage', function(src, _, id)
    local d, err = managed(src, id)
    if not d then return err end
    local grants = {}
    for _, g in ipairs(MySQL.query.await([[SELECT id, citizenid, UNIX_TIMESTAMP(expires_at) AS expires FROM veyl_door_grants
        WHERE door_id = ? AND revoked_at IS NULL AND expires_at > NOW() ORDER BY expires_at]], { d.id }) or {}) do
        grants[#grants + 1] = { id = g.id, name = charName(g.citizenid), expires = g.expires }
    end
    local keys = MySQL.scalar.await('SELECT COUNT(*) FROM veyl_door_keys WHERE door_id = ? AND key_rev = ?', { d.id, d.keyRev }) or 0
    return Veyl.Ok({ id = d.id, name = d.name, locked = d.locked, businessOpen = d.businessOpen == true, grants = grants, keys = keys,
        maxKeys = C.Keys.MaxPerDoor, maxHours = C.Grants.MaxHours, keysEnabled = d.settings.access.keys, serverTime = os.time(),
        phone = GetResourceState('veyl_phone') == 'started' })
end, { cooldown = 300 })

--- Keep the door unlocked (no auto-lock) until someone locks it: opening hours for a business.
Veyl.RegisterCallback('businessOpen', function(src, citizenid, id, on)
    local d, err = managed(src, id)
    if not d then return err end
    if on then
        d.businessOpen = true
        Doors.SetLocked(d, false, citizenid, 'business')
    else
        Doors.SetLocked(d, true, citizenid, 'business')
    end
    log(d.id, citizenid, on and 'open_business' or 'close_business')
    return Veyl.Ok({ businessOpen = d.businessOpen == true, locked = d.locked }, on and 'Open: the door stays unlocked' or 'Closed and locked')
end, { cooldown = 800 })

Veyl.RegisterCallback('grant', function(src, citizenid, id, target, hours)
    local d, err = managed(src, id)
    if not d then return err end
    local cid = resolveTarget(src, target)
    if not cid then return Veyl.Err('NOT_FOUND', 'Person not found. Stand next to them or use their phone number.') end
    hours = math.floor(num(hours, 1, C.Grants.MaxHours, 8))
    local n = MySQL.scalar.await('SELECT COUNT(*) FROM veyl_door_grants WHERE door_id = ? AND revoked_at IS NULL AND expires_at > NOW()', { d.id }) or 0
    if n >= C.Grants.MaxPerDoor then return Veyl.Err('LIMIT', 'Too many active grants on this door') end
    MySQL.insert.await('INSERT INTO veyl_door_grants (door_id, citizenid, granted_by, expires_at) VALUES (?, ?, ?, DATE_ADD(NOW(), INTERVAL ? HOUR))',
        { d.id, cid, citizenid, hours })
    log(d.id, citizenid, 'grant', ('%s for %dh'):format(cid, hours))
    local t = Veyl.GetSourceByCitizenId(cid)
    if t then Veyl.Notify(t, ('You can use %s for %d hour%s.'):format(d.name, hours, hours == 1 and '' or 's'), 'success') end
    return Veyl.Ok(nil, ('Access given to %s'):format(charName(cid)))
end, { cooldown = 800 })

Veyl.RegisterCallback('revoke', function(src, citizenid, grantId)
    local g = MySQL.single.await('SELECT * FROM veyl_door_grants WHERE id = ? AND revoked_at IS NULL', { tonumber(grantId) or -1 })
    if not g then return Veyl.Err('NOT_FOUND', 'Already removed') end
    local d, err = managed(src, g.door_id)
    if not d then return err end
    MySQL.update.await('UPDATE veyl_door_grants SET revoked_at = NOW() WHERE id = ?', { g.id })
    log(d.id, citizenid, 'revoke', g.citizenid)
    return Veyl.Ok(nil, 'Access removed')
end, { cooldown = 500 })

--- Cut a physical key (to yourself). Keys stop working when the locks are changed.
Veyl.RegisterCallback('makeKey', function(src, citizenid, id, opId)
    local d, err = managed(src, id)
    if not d then return err end
    if not d.settings.access.keys then return Veyl.Err('UNAVAILABLE', 'This door does not use keys') end
    if type(opId) ~= 'string' or not opId:match('^[%w%-]+$') or #opId > 48 then return Veyl.Err('INVALID_INPUT', 'Invalid request') end
    local op = ('door_key:%d:%s:%s'):format(d.id, citizenid, opId)
    if not MySQL.scalar.await('SELECT 1 FROM veyl_door_keys WHERE op_id = ?', { op }) then
        local n = MySQL.scalar.await('SELECT COUNT(*) FROM veyl_door_keys WHERE door_id = ? AND key_rev = ?', { d.id, d.keyRev }) or 0
        if n >= C.Keys.MaxPerDoor then return Veyl.Err('LIMIT', 'Too many keys for this door. Change the locks to start again.') end
    end
    local meta = { door = d.id, label = d.name, rev = d.keyRev }
    local can = Veyl.Await('veyl_inventory', 'CanCarry', 10000, citizenid, C.Items.key, 1, meta)
    if not can.ok then return Veyl.Err('INVENTORY_FULL', 'Make room in your pockets first') end
    local res = Veyl.Await('veyl_inventory', 'GiveItem', 15000, citizenid, C.Items.key, 1, meta, op)
    if not res.ok and res.code ~= 'DUPLICATE_OPERATION' then return Veyl.Err(res.code or 'FAILED', res.message or 'Could not cut the key') end
    MySQL.insert.await('INSERT IGNORE INTO veyl_door_keys (door_id, key_rev, issued_by, issued_to, op_id) VALUES (?, ?, ?, ?, ?)', { d.id, d.keyRev, citizenid, citizenid, op })
    log(d.id, citizenid, 'key_cut')
    return Veyl.Ok(nil, ('Cut a key for %s'):format(d.name))
end, { cooldown = 1500 })

Veyl.RegisterCallback('changeLocks', function(src, citizenid, id)
    local d, err = managed(src, id)
    if not d then return err end
    d.keyRev = d.keyRev + 1
    MySQL.update.await('UPDATE veyl_doors SET key_rev = ? WHERE id = ?', { d.keyRev, d.id })
    log(d.id, citizenid, 'change_locks', 'rev ' .. d.keyRev)
    return Veyl.Ok(nil, 'Locks changed. Old keys no longer work.')
end, { cooldown = 3000 })

---------------------------------------------------------------------------
-- Breaching: lockpick (anyone, if enabled) and police ram. Start -> timed action on the client -> finish.
---------------------------------------------------------------------------
local function count(src, item) return exports.veyl_inventory:GetItemCount(src, item) or 0 end

Veyl.RegisterCallback('breachStart', function(src, citizenid, id, method)
    local d = Doors.list[tonumber(id) or -1]
    if not d then return Veyl.Err('NOT_FOUND', 'Unknown door') end
    if not d.locked then return Veyl.Err('INVALID_STATE', 'It is already open') end
    if not near(src, d) then return Veyl.Err('TOO_FAR', 'Move closer to the door') end
    local b = d.settings.breach
    if method == 'lockpick' then
        if not b.lockpick then return Veyl.Err('UNAVAILABLE', 'This lock cannot be picked') end
        if count(src, C.Items.lockpick) < 1 then return Veyl.Err('NO_ITEM', 'You need a lockpick') end
    elseif method == 'ram' then
        if not b.ram then return Veyl.Err('UNAVAILABLE', 'This door cannot be breached') end
        if count(src, C.Items.ram) < 1 then return Veyl.Err('NO_ITEM', 'You need a door ram') end
        if next(b.ramJobs) then
            local job = exports.veyl_core:HasGroup(src, b.ramJobs)
            if not job or not onDuty(src, job) then return Veyl.Err('NO_PERMISSION', 'Only on-duty officers can breach this door') end
        end
    else
        return Veyl.Err('INVALID_INPUT', 'Unknown method')
    end
    local token = tostring(math.random(100000, 999999)) .. tostring(GetGameTimer())
    breaches[src] = { doorId = d.id, method = method, at = GetGameTimer(), token = token }
    TriggerEvent('veyl_doorlocks:breachStarted', src, d.id, method, center(d))
    return Veyl.Ok({ token = token, seconds = method == 'ram' and C.Breach.RamSeconds or C.Breach.LockpickSeconds })
end, { cooldown = 1000 })

Veyl.RegisterCallback('breachFinish', function(src, citizenid, token, picked)
    local b = breaches[src]
    breaches[src] = nil
    if not b or b.token ~= token then return Veyl.Err('INVALID_STATE', 'Start again') end
    local d = Doors.list[b.doorId]
    if not d or not d.locked then return Veyl.Err('INVALID_STATE', 'It is already open') end
    if b.method == 'lockpick' and picked == false then
        -- Failed the mini game: no wait, but the pick may snap.
        if count(src, C.Items.lockpick) > 0 and math.random() < C.Breach.LockpickBreakChance then
            exports.veyl_inventory:RemoveItem(src, C.Items.lockpick, 1)
            log(d.id, citizenid, 'lockpick_fail', 'broke')
            return Veyl.Err('FAILED', 'The lockpick snapped')
        end
        log(d.id, citizenid, 'lockpick_fail')
        return Veyl.Err('FAILED', 'You could not pick the lock')
    end
    local need = (b.method == 'ram' and C.Breach.RamSeconds or C.Breach.LockpickSeconds) * 1000 - 500
    if GetGameTimer() - b.at < need then return Veyl.Err('TOO_FAST', 'You stopped too early') end
    if not near(src, d) then return Veyl.Err('TOO_FAR', 'Move closer to the door') end
    if b.method == 'lockpick' then
        if count(src, C.Items.lockpick) < 1 then return Veyl.Err('NO_ITEM', 'You need a lockpick') end
        -- With the mini game (veyl_minigames) the player's skill decides; without it, the configured chance does.
        local failed
        if picked == true then failed = false elseif picked == false then failed = true else failed = math.random() > d.settings.breach.lockpickChance end
        if failed then
            if math.random() < C.Breach.LockpickBreakChance then
                exports.veyl_inventory:RemoveItem(src, C.Items.lockpick, 1)
                log(d.id, citizenid, 'lockpick_fail', 'broke')
                return Veyl.Err('FAILED', 'The lockpick snapped')
            end
            log(d.id, citizenid, 'lockpick_fail')
            return Veyl.Err('FAILED', 'You could not pick the lock')
        end
    elseif count(src, C.Items.ram) < 1 then
        return Veyl.Err('NO_ITEM', 'You need a door ram')
    end
    Doors.SetLocked(d, false, citizenid, b.method, d.settings.breach.relock)
    log(d.id, citizenid, b.method == 'ram' and 'breached' or 'lockpicked')
    TriggerEvent('veyl_doorlocks:breached', src, d.id, b.method, center(d))
    return Veyl.Ok(nil, b.method == 'ram' and 'Door breached' or 'Lock picked')
end)

AddEventHandler('playerDropped', function() breaches[source] = nil lastToggle[source] = nil end)

---------------------------------------------------------------------------
-- Editor (admins)
---------------------------------------------------------------------------
local function adminOnly(src) if not isAdmin(src) then return Veyl.Err('NO_PERMISSION', 'Staff only') end end

Veyl.RegisterCallback('adminData', function(src)
    local e = adminOnly(src) if e then return e end
    local jobs, gangs, items = {}, {}, {}
    local function grades(def)
        local list = {}
        for g, info in pairs(def.grades or {}) do list[#list + 1] = { grade = tonumber(g), name = info.name } end
        table.sort(list, function(a, b) return a.grade < b.grade end)
        return list
    end
    for name, def in pairs(exports.veyl_core:GetJobs() or {}) do jobs[#jobs + 1] = { name = name, label = def.label, grades = grades(def) } end
    for name, def in pairs(exports.veyl_core:GetGangs() or {}) do gangs[#gangs + 1] = { name = name, label = def.label, grades = grades(def) } end
    for name, def in pairs(exports.veyl_inventory:Items() or {}) do if name ~= C.Items.key then items[#items + 1] = { name = name, label = def.label } end end
    table.sort(jobs, function(a, b) return a.label < b.label end)
    table.sort(gangs, function(a, b) return a.label < b.label end)
    table.sort(items, function(a, b) return a.label < b.label end)
    local list = {}
    for _, d in pairs(Doors.list) do
        local c = center(d)
        list[#list + 1] = { id = d.id, name = d.name, entities = d.entities, settings = d.settings, locked = d.locked, x = c.x, y = c.y, z = c.z }
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return Veyl.Ok({ doors = list, jobs = jobs, gangs = gangs, items = items, limits = { distance = C.DistanceRange, autoLock = C.AutoLockMax, maxEntities = C.MaxEntities } })
end, { cooldown = 300 })

Veyl.RegisterCallback('adminSave', function(src, citizenid, input)
    local e = adminOnly(src) if e then return e end
    if type(input) ~= 'table' then return Veyl.Err('INVALID_INPUT', 'Invalid door') end
    local name = str(input.name, 48)
    if not name then return Veyl.Err('INVALID_INPUT', 'Give the door a name') end
    local entities = cleanEntities(input.entities)
    if not entities then return Veyl.Err('INVALID_INPUT', ('Pick 1 to %d doors'):format(C.MaxEntities)) end
    local settings = Doors.CleanSettings(input.settings)
    local who = ('%s (%s)'):format(GetPlayerName(src) or 'console', citizenid or '-')
    local d
    if input.id then
        d = Doors.list[tonumber(input.id) or -1]
        if not d then return Veyl.Err('NOT_FOUND', 'That door was deleted') end
        MySQL.update.await('UPDATE veyl_doors SET name = ?, entities = ?, settings = ? WHERE id = ?', { name, json.encode(entities), json.encode(settings), d.id })
        TriggerClientEvent('veyl_doorlocks:removed', -1, d.id)
        d.name, d.entities, d.settings = name, entities, settings
    else
        local id = MySQL.insert.await('INSERT INTO veyl_doors (name, entities, settings, locked, created_by) VALUES (?, ?, ?, ?, ?)',
            { name, json.encode(entities), json.encode(settings), settings.locked and 1 or 0, who })
        d = { id = id, name = name, entities = entities, settings = settings, locked = settings.locked, keyRev = 1 }
        Doors.list[id] = d
    end
    TriggerClientEvent('veyl_doorlocks:upsert', -1, Doors.Public(d))
    Veyl.Audit(src, input.id and 'door_edited' or 'door_created', { door = d.id, name = name })
    log(d.id, who, input.id and 'edited' or 'created')
    return Veyl.Ok({ id = d.id }, input.id and 'Door saved' or ('Door #%d created'):format(d.id))
end, { cooldown = 800 })

Veyl.RegisterCallback('adminDelete', function(src, _, id)
    local e = adminOnly(src) if e then return e end
    local d = Doors.list[tonumber(id) or -1]
    if not d then return Veyl.Err('NOT_FOUND', 'Already deleted') end
    MySQL.update.await('DELETE FROM veyl_doors WHERE id = ?', { d.id })
    MySQL.update.await('UPDATE veyl_door_grants SET revoked_at = NOW() WHERE door_id = ? AND revoked_at IS NULL', { d.id })
    Doors.list[d.id] = nil
    autoTimers[d.id] = nil
    TriggerClientEvent('veyl_doorlocks:removed', -1, d.id)
    Veyl.Audit(src, 'door_deleted', { door = d.id, name = d.name })
    return Veyl.Ok(nil, ('Deleted %s'):format(d.name))
end, { cooldown = 800 })

Veyl.RegisterCallback('adminToggle', function(src, citizenid, id)
    local e = adminOnly(src) if e then return e end
    local d = Doors.list[tonumber(id) or -1]
    if not d then return Veyl.Err('NOT_FOUND', 'Unknown door') end
    Doors.SetLocked(d, not d.locked, citizenid, 'admin')
    log(d.id, citizenid, d.locked and 'lock' or 'unlock', 'admin (editor)')
    return Veyl.Ok({ locked = d.locked }, d.locked and 'Locked' or 'Unlocked')
end, { cooldown = 400 })

Veyl.RegisterCallback('adminLog', function(src, _, id)
    local e = adminOnly(src) if e then return e end
    local rows = MySQL.query.await([[SELECT citizenid, action, detail, UNIX_TIMESTAMP(created_at) AS at FROM veyl_door_log WHERE door_id = ?
        ORDER BY id DESC LIMIT 50]], { tonumber(id) or -1 }) or {}
    return Veyl.Ok(rows)
end, { cooldown = 300 })

Veyl.RegisterCallback('canEdit', function(src) return Veyl.Ok(isAdmin(src)) end, { cooldown = 500 })

---------------------------------------------------------------------------
-- Exports for other resources
---------------------------------------------------------------------------
exports('IsLocked', function(id) local d = Doors.list[tonumber(id) or -1] return d and d.locked or nil end)
exports('SetLocked', function(id, locked, reason)
    local d = Doors.list[tonumber(id) or -1]
    if not d then return false end
    Doors.SetLocked(d, locked == true, GetInvokingResource() or 'resource', reason or 'script')
    log(d.id, GetInvokingResource() or 'resource', locked and 'lock' or 'unlock', reason)
    return true
end)
exports('HasAccess', function(src, id) local d = Doors.list[tonumber(id) or -1] return d ~= nil and Doors.Access(src, d) ~= nil end)
exports('GetDoorByName', function(name) for _, d in pairs(Doors.list) do if d.name == name then return d.id end end end)
--- Breach(id, relockSeconds?, reason?) — for heist/police scripts that run their own minigame and checks.
exports('Breach', function(id, relock, reason)
    local d = Doors.list[tonumber(id) or -1]
    if not d then return false end
    Doors.SetLocked(d, false, GetInvokingResource() or 'resource', reason or 'breach', relock or d.settings.breach.relock)
    log(d.id, GetInvokingResource() or 'resource', 'breached', reason)
    return true
end)

--- Editor helper: the character id and name of an online player (by server id) for the "specific people" list.
Veyl.RegisterCallback('adminLookup', function(src, _, serverId)
    local e = adminOnly(src) if e then return e end
    local t = tonumber(serverId)
    local cid = t and GetPlayerName(t) and Veyl.GetCitizenId(t)
    if not cid then return Veyl.Err('NOT_FOUND', 'No character with that server id is online') end
    return Veyl.Ok({ citizenid = cid, name = charName(cid) })
end, { cooldown = 300 })
