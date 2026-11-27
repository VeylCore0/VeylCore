-- Notifications (stored per character, delivered live when the phone session is up) and app badges.

Notify = {}
local L = PhoneConfig.Limits

local function row(n)
    return { id = n.id, app = n.app, title = n.title, body = n.body, route = n.route, read = n.is_read == 1 or n.is_read == true,
        time = n.ts }
end

function Notify.UnreadCount(citizenid)
    return MySQL.scalar.await('SELECT COUNT(*) FROM veyl_ph_notifications WHERE citizenid = ? AND is_read = 0', { citizenid }) or 0
end

--- Stores and pushes a notification. n = { app, title, body?, route?, dedupe? }. Works for offline characters.
--- With `dedupe`, the same (citizenid, dedupe) is only ever stored once. Returns the id, or nil.
function Notify.Send(citizenid, n)
    if type(citizenid) ~= 'string' or type(n) ~= 'table' then return nil end
    local app = type(n.app) == 'string' and n.app:match('^[%w_]+$') and n.app:sub(1, 32) or 'system'
    local title = PhoneUtil.Clean(n.title, 80)
    if not title then return nil end
    local body = PhoneUtil.Clean(n.body, 200) or ''
    local route = type(n.route) == 'string' and n.route:match('^[%w_/:%-]+$') and n.route:sub(1, 128) or nil
    local dedupe = type(n.dedupe) == 'string' and n.dedupe:sub(1, 64) or nil
    local id = MySQL.insert.await([[INSERT IGNORE INTO veyl_ph_notifications (citizenid, app, title, body, route, dedupe)
        VALUES (?, ?, ?, ?, ?, ?)]], { citizenid, app, title, body, route, dedupe })
    if not id or id == 0 then return nil end -- duplicate
    -- Keep the newest L.Notifications per character.
    MySQL.update([[DELETE FROM veyl_ph_notifications WHERE citizenid = ? AND id <= (SELECT id FROM (SELECT id FROM veyl_ph_notifications
        WHERE citizenid = ? ORDER BY id DESC LIMIT 1 OFFSET ?) t)]], { citizenid, citizenid, L.Notifications })
    local s = Phone.byCid[citizenid]
    if s then
        Phone.Push(s.src, 'notification', {
            notification = { id = id, app = app, title = title, body = body, route = route, read = false, time = os.time() },
            unread = Notify.UnreadCount(citizenid),
            silent = s.settings.dnd or s.settings.silent,
        })
    end
    return id
end

function Notify.Badges(citizenid)
    local out = {}
    for _, r in ipairs(MySQL.query.await('SELECT app, count FROM veyl_ph_badges WHERE citizenid = ? AND count > 0', { citizenid }) or {}) do
        out[r.app] = r.count
    end
    return out
end

--- Sets the number shown on an app's icon (0 clears it). Stored, so it survives restarts and offline time.
function Notify.SetBadge(citizenid, app, count)
    if type(citizenid) ~= 'string' or type(app) ~= 'string' or not app:match('^[%w_]+$') then return false end
    count = math.max(0, math.floor(tonumber(count) or 0))
    if count == 0 then
        MySQL.update.await('DELETE FROM veyl_ph_badges WHERE citizenid = ? AND app = ?', { citizenid, app:sub(1, 32) })
    else
        MySQL.query.await('INSERT INTO veyl_ph_badges (citizenid, app, count) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE count = VALUES(count)',
            { citizenid, app:sub(1, 32), count })
    end
    Phone.PushCid(citizenid, 'badge', { app = app, count = count })
    return true
end

--- notifications(beforeId?) -> { items, unread, more }
Veyl.RegisterCallback('notifications', function(src, citizenid, beforeId)
    if not Phone.Session(src) then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    beforeId = tonumber(beforeId) or 0
    local rows = MySQL.query.await([[SELECT id, app, title, body, route, is_read, UNIX_TIMESTAMP(created_at) AS ts FROM veyl_ph_notifications
        WHERE citizenid = ? AND (? = 0 OR id < ?) ORDER BY id DESC LIMIT ?]], { citizenid, beforeId, beforeId, L.PageSize + 1 }) or {}
    local items = {}
    for i = 1, math.min(#rows, L.PageSize) do items[i] = row(rows[i]) end
    return Veyl.Ok({ items = items, unread = Notify.UnreadCount(citizenid), more = #rows > L.PageSize })
end)

local function idList(ids)
    if ids == 'all' then return 'all' end
    if type(ids) ~= 'table' then return nil end
    local out = {}
    for _, v in ipairs(ids) do
        local n = tonumber(v)
        if n and n > 0 and #out < 200 then out[#out + 1] = math.floor(n) end
    end
    return #out > 0 and out or nil
end

local function inClause(n) return string.rep('?,', n):sub(1, -2) end

--- notificationsRead(ids | 'all')
Veyl.RegisterCallback('notificationsRead', function(src, citizenid, ids)
    if not Phone.Session(src) then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    ids = idList(ids)
    if not ids then return Veyl.Err('INVALID_INPUT', 'Nothing selected') end
    if ids == 'all' then
        MySQL.update.await('UPDATE veyl_ph_notifications SET is_read = 1 WHERE citizenid = ?', { citizenid })
    else
        local p = { citizenid }
        for _, i in ipairs(ids) do p[#p + 1] = i end
        MySQL.update.await(('UPDATE veyl_ph_notifications SET is_read = 1 WHERE citizenid = ? AND id IN (%s)'):format(inClause(#ids)), p)
    end
    return Veyl.Ok({ unread = Notify.UnreadCount(citizenid) })
end)

--- notificationsClear(ids | 'all')
Veyl.RegisterCallback('notificationsClear', function(src, citizenid, ids)
    if not Phone.Session(src) then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    ids = idList(ids)
    if not ids then return Veyl.Err('INVALID_INPUT', 'Nothing selected') end
    if ids == 'all' then
        MySQL.update.await('DELETE FROM veyl_ph_notifications WHERE citizenid = ?', { citizenid })
    else
        local p = { citizenid }
        for _, i in ipairs(ids) do p[#p + 1] = i end
        MySQL.update.await(('DELETE FROM veyl_ph_notifications WHERE citizenid = ? AND id IN (%s)'):format(inClause(#ids)), p)
    end
    return Veyl.Ok({ unread = Notify.UnreadCount(citizenid) })
end)
