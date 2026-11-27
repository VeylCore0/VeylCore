-- Mail: one-way messages from the city, businesses and scripts (receipts, bills, offers). Works for offline characters.

Mail = {}
local L = PhoneConfig.Limits

function Mail.UnreadCount(citizenid)
    return MySQL.scalar.await('SELECT COUNT(*) FROM veyl_ph_mail WHERE citizenid = ? AND is_read = 0', { citizenid }) or 0
end

--- Stores a mail and tells the phone. Returns the id, or nil.
function Mail.Send(citizenid, from, subject, body)
    if type(citizenid) ~= 'string' then return nil end
    from = PhoneUtil.Clean(from, 64) or 'Los Santos'
    subject = PhoneUtil.Clean(subject, 120) or '(no subject)'
    body = PhoneUtil.CleanBody(body, 4000) or ''
    local id = MySQL.insert.await('INSERT INTO veyl_ph_mail (citizenid, sender, subject, body) VALUES (?, ?, ?, ?)', { citizenid, from, subject, body })
    if not id then return nil end
    MySQL.update([[DELETE FROM veyl_ph_mail WHERE citizenid = ? AND id <= (SELECT id FROM (SELECT id FROM veyl_ph_mail
        WHERE citizenid = ? ORDER BY id DESC LIMIT 1 OFFSET ?) t)]], { citizenid, citizenid, L.Mail })
    local s = Phone.byCid[citizenid]
    if s then
        Phone.Push(s.src, 'mail', {
            mail = { id = id, from = from, subject = subject, preview = body:sub(1, 120), read = false, time = os.time() },
            unread = Mail.UnreadCount(citizenid),
            silent = s.settings.dnd or s.settings.silent,
        })
    end
    return id
end

--- mailList(beforeId?) -> { items (no bodies), unread, more }
Veyl.RegisterCallback('mailList', function(src, citizenid, beforeId)
    if not Phone.Session(src) then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    beforeId = tonumber(beforeId) or 0
    local rows = MySQL.query.await([[SELECT id, sender, subject, LEFT(body, 120) AS preview, is_read, UNIX_TIMESTAMP(created_at) AS ts
        FROM veyl_ph_mail WHERE citizenid = ? AND (? = 0 OR id < ?) ORDER BY id DESC LIMIT ?]], { citizenid, beforeId, beforeId, L.PageSize + 1 }) or {}
    local items = {}
    for i = 1, math.min(#rows, L.PageSize) do
        local r = rows[i]
        items[i] = { id = r.id, from = r.sender, subject = r.subject, preview = r.preview, read = r.is_read == 1 or r.is_read == true, time = r.ts }
    end
    return Veyl.Ok({ items = items, unread = Mail.UnreadCount(citizenid), more = #rows > L.PageSize })
end)

--- mailRead(id) -> the full mail (and marks it read)
Veyl.RegisterCallback('mailRead', function(src, citizenid, id)
    if not Phone.Session(src) then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    local r = MySQL.single.await('SELECT id, sender, subject, body, UNIX_TIMESTAMP(created_at) AS ts FROM veyl_ph_mail WHERE id = ? AND citizenid = ?',
        { tonumber(id) or 0, citizenid })
    if not r then return Veyl.Err('NOT_FOUND', 'Mail not found') end
    MySQL.update.await('UPDATE veyl_ph_mail SET is_read = 1 WHERE id = ?', { r.id })
    return Veyl.Ok({ id = r.id, from = r.sender, subject = r.subject, body = r.body, read = true, time = r.ts, unread = Mail.UnreadCount(citizenid) })
end)

Veyl.RegisterCallback('mailDelete', function(src, citizenid, id)
    if not Phone.Session(src) then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    local n = MySQL.update.await('DELETE FROM veyl_ph_mail WHERE id = ? AND citizenid = ?', { tonumber(id) or 0, citizenid })
    if n == 0 then return Veyl.Err('NOT_FOUND', 'Mail not found') end
    return Veyl.Ok({ unread = Mail.UnreadCount(citizenid) }, 'Deleted')
end)
