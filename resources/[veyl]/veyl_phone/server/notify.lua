-- Shared notification service. Every app (and other resources, through exports) posts here.
-- Stored per character with a bounded history; deduplicated by (citizenid, dedupe); pushed to a live phone session.
-- Delivery respects per-app mute and do-not-disturb (stored either way; DND only silences the banner and sound).

Notify = {}
local L = PhoneConfig.Limits
local badges = {} -- [citizenid] = { [app] = count } (in memory; apps set them through SetBadge)

local ROUTE_OK = '^[%w_%-/:%.]*$'

--- Notify.Send(citizenid, { app, title, body, route?, dedupe? }) -> id | nil
function Notify.Send(citizenid, n)
    if type(citizenid) ~= 'string' or type(n) ~= 'table' then return nil end
    local app = Phone.Clean(n.app, 32)
    local title = Phone.Clean(n.title, 80)
    local body = Phone.Clean(n.body, 160) or ''
    if not app or not title then return nil end
    local route = type(n.route) == 'string' and #n.route <= 255 and n.route:match(ROUTE_OK) and n.route or nil
    local dedupe = Phone.Clean(n.dedupe, 64)
    local ok, id = pcall(MySQL.insert.await, [[INSERT INTO veyl_phone_notifications (citizenid, app, title, body, route, dedupe) VALUES (?, ?, ?, ?, ?, ?)]],
        { citizenid, app, title, body, route, dedupe })
    if not ok or not id then return nil end -- duplicate dedupe key: already notified
    -- Bound the history.
    MySQL.update([[DELETE FROM veyl_phone_notifications WHERE citizenid = ? AND id <= (
        SELECT id FROM (SELECT id FROM veyl_phone_notifications WHERE citizenid = ? ORDER BY id DESC LIMIT 1 OFFSET ?) t)]],
        { citizenid, citizenid, L.Notifications })
    local s = Phone.byCid[citizenid]
    if s and Phone.Session(s.src) then
        local prefs = s.settings.appPrefs[app]
        Phone.Push(s.src, 'notification', {
            id = id, app = app, title = title, body = body, route = route, at = os.time(),
            quiet = s.settings.dnd or s.settings.silent or (prefs and prefs.muted) or false,
        })
    end
    return id
end

function Notify.Badges(citizenid) return badges[citizenid] or {} end

function Notify.UnreadCount(citizenid)
    return MySQL.scalar.await('SELECT COUNT(*) FROM veyl_phone_notifications WHERE citizenid = ? AND is_read = 0', { citizenid }) or 0
end

Veyl.RegisterCallback('notifications', function(src, citizenid, beforeId)
    if not Phone.Session(src) then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    local rows = MySQL.query.await([[SELECT id, app, title, body, route, is_read, UNIX_TIMESTAMP(created_at) AS at FROM veyl_phone_notifications
        WHERE citizenid = ? AND id < ? ORDER BY id DESC LIMIT ?]], { citizenid, tonumber(beforeId) or 9e15, L.PageSize }) or {}
    return Veyl.Ok({ items = rows, badges = badges[citizenid] or {} })
end, { cooldown = 300 })

Veyl.RegisterCallback('notificationsRead', function(src, citizenid, ids)
    if not Phone.Session(src) then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    if ids == 'all' then
        MySQL.update.await('UPDATE veyl_phone_notifications SET is_read = 1 WHERE citizenid = ?', { citizenid })
    elseif type(ids) == 'table' then
        for i, id in ipairs(ids) do
            if i > 50 then break end
            if Veyl.Validate.int(id, 1) then MySQL.update.await('UPDATE veyl_phone_notifications SET is_read = 1 WHERE id = ? AND citizenid = ?', { id, citizenid }) end
        end
    end
    return Veyl.Ok({ unread = Notify.UnreadCount(citizenid) })
end, { cooldown = 200 })

Veyl.RegisterCallback('notificationsClear', function(src, citizenid)
    if not Phone.Session(src) then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    MySQL.update.await('DELETE FROM veyl_phone_notifications WHERE citizenid = ?', { citizenid })
    return Veyl.Ok()
end, { cooldown = 1000 })

---------------------------------------------------------------------------
-- Developer API (server exports)
---------------------------------------------------------------------------
--- exports.veyl_phone:Notify(citizenid, { app, title, body, route?, dedupe? }) -> id | nil
exports('Notify', function(citizenid, n) return Notify.Send(citizenid, n) end)

--- exports.veyl_phone:SetBadge(citizenid, app, count)
exports('SetBadge', function(citizenid, app, count)
    if type(citizenid) ~= 'string' or type(app) ~= 'string' then return false end
    badges[citizenid] = badges[citizenid] or {}
    badges[citizenid][app] = math.max(0, math.floor(tonumber(count) or 0))
    local s = Phone.byCid[citizenid]
    if s then Phone.Push(s.src, 'badge', { app = app, count = badges[citizenid][app] }) end
    return true
end)

exports('GetNumber', function(citizenid) return Phone.NumberOf(citizenid) end)
exports('GetCitizenByNumber', function(number) local n = Phone.NormalizeNumber(number) return n and Phone.CidByNumber(n) or nil end)

--- exports.veyl_phone:OpenApp(src, appId, route?) — opens the phone to an app on that player's client (if they have a phone).
exports('OpenApp', function(src, appId, route)
    if type(appId) ~= 'string' or not Phone.HasDevice(src) then return false end
    TriggerClientEvent('veyl_phone:openApp', src, appId, type(route) == 'string' and route:match(ROUTE_OK) and route or nil)
    return true
end)
