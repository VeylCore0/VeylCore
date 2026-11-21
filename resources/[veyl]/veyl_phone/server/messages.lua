-- Messages: direct and group conversations with honest states.
--   Sent      : the server accepted and stored it (the send callback returned).
--   Delivered : the recipient's live phone session acknowledged it (ack). Offline recipients stay "sent" until they
--               come back with a phone; pending messages are pushed and acknowledged then.
--   Read      : the recipient opened the conversation AND has read receipts enabled.
-- Every read and write checks active membership. Blocking: a recipient who blocked you cannot get new direct
-- messages from you; in groups, a member who blocked you doesn't see your messages (they aren't counted as delivered to
-- them either).

Messages = {}
local L = PhoneConfig.Limits

local function isMember(convId, number)
    return MySQL.single.await('SELECT role, muted, last_read_id FROM veyl_phone_members WHERE conversation_id = ? AND number = ? AND left_at IS NULL',
        { convId, number })
end

local function activeMembers(convId)
    return MySQL.query.await('SELECT number, role FROM veyl_phone_members WHERE conversation_id = ? AND left_at IS NULL ORDER BY joined_at', { convId }) or {}
end

local function blockedSet(cid)
    local set = {}
    for _, r in ipairs(MySQL.query.await('SELECT number FROM veyl_phone_blocks WHERE owner_cid = ?', { cid }) or {}) do set[r.number] = true end
    return set
end

local function contactNames(cid)
    local map = {}
    for _, r in ipairs(MySQL.query.await('SELECT number, name FROM veyl_phone_contacts WHERE owner_cid = ?', { cid }) or {}) do map[r.number] = r.name end
    return map
end

local function messageOut(r)
    return { id = r.id, convId = r.conversation_id, sender = r.sender, kind = r.kind, body = r.body,
        payload = Phone.Decode(r.payload, nil), at = r.at or os.time() }
end

--- Aggregated receipt state for messages a number sent. Returns map id -> { state, delivered, read, total }.
local function receiptStates(ids, isDirect)
    local out = {}
    if #ids == 0 then return out end
    local placeholders = ('?,'):rep(#ids):sub(1, -2)
    local rows = MySQL.query.await(([[SELECT message_id, COUNT(*) AS total, SUM(delivered_at IS NOT NULL) AS delivered, SUM(read_at IS NOT NULL) AS readc
        FROM veyl_phone_receipts WHERE message_id IN (%s) GROUP BY message_id]]):format(placeholders), ids) or {}
    for _, r in ipairs(rows) do
        local total, delivered, readc = tonumber(r.total) or 0, tonumber(r.delivered) or 0, tonumber(r.readc) or 0
        local state = 'sent'
        if total > 0 and readc == total and isDirect then state = 'read'
        elseif total > 0 and delivered == total then state = 'delivered' end
        out[r.message_id] = { state = state, delivered = delivered, read = readc, total = total }
    end
    return out
end

local function pushReceipt(messageId)
    local m = MySQL.single.await('SELECT m.id, m.conversation_id, m.sender, c.kind FROM veyl_phone_messages m JOIN veyl_phone_conversations c ON c.id = m.conversation_id WHERE m.id = ?',
        { messageId })
    if not m then return end
    local s = Phone.SessionByNumber(m.sender)
    if not s then return end
    local st = receiptStates({ m.id }, m.kind == 'direct')[m.id]
    if st then Phone.Push(s.src, 'receipt', { convId = m.conversation_id, id = m.id, state = st.state, delivered = st.delivered, read = st.read, total = st.total }) end
end

function Messages.UnreadTotal(number)
    local cid = Phone.CidByNumber(number)
    if not cid then return 0 end
    local n = MySQL.scalar.await([[SELECT COUNT(*) FROM veyl_phone_members mb JOIN veyl_phone_messages m ON m.conversation_id = mb.conversation_id
        WHERE mb.number = ? AND mb.left_at IS NULL AND m.id > mb.last_read_id AND m.sender <> ? AND m.kind <> 'system'
        AND m.sender NOT IN (SELECT number FROM veyl_phone_blocks WHERE owner_cid = ?)]], { number, number, cid })
    return tonumber(n) or 0
end

---------------------------------------------------------------------------
-- Conversation list (paginated)
---------------------------------------------------------------------------
Veyl.RegisterCallback('conversations', function(src, citizenid, offset)
    local s = Phone.Session(src)
    if not s then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    offset = Veyl.Validate.int(offset, 0, 10000) and offset or 0
    local rows = MySQL.query.await([[SELECT c.id, c.kind, c.name, c.last_message_id, mb.muted, mb.last_read_id, mb.role
        FROM veyl_phone_members mb JOIN veyl_phone_conversations c ON c.id = mb.conversation_id
        WHERE mb.number = ? AND mb.left_at IS NULL AND c.last_message_id IS NOT NULL
        ORDER BY c.last_message_id DESC LIMIT ? OFFSET ?]], { s.number, L.PageSize, offset }) or {}
    local names, blocked = contactNames(citizenid), blockedSet(citizenid)
    local out = {}
    for _, c in ipairs(rows) do
        local last = MySQL.single.await('SELECT id, conversation_id, sender, kind, body, payload, UNIX_TIMESTAMP(created_at) AS at FROM veyl_phone_messages WHERE id = ?',
            { c.last_message_id })
        local unread = MySQL.scalar.await([[SELECT COUNT(*) FROM veyl_phone_messages WHERE conversation_id = ? AND id > ? AND sender <> ? AND kind <> 'system'
            AND sender NOT IN (SELECT number FROM veyl_phone_blocks WHERE owner_cid = ?)]], { c.id, c.last_read_id, s.number, citizenid }) or 0
        local item = { id = c.id, kind = c.kind, muted = c.muted == 1 or c.muted == true, unread = tonumber(unread) or 0,
            last = last and messageOut(last) or nil, role = c.role }
        if c.kind == 'direct' then
            local other = MySQL.scalar.await('SELECT number FROM veyl_phone_members WHERE conversation_id = ? AND number <> ? LIMIT 1', { c.id, s.number })
            item.number = other
            item.title = names[other] or Phone.FormatNumber(other)
            item.blocked = blocked[other] == true
        else
            item.title = c.name or 'Group'
            if last and blocked[last.sender] then item.last = { kind = 'system', body = 'Message hidden (blocked sender)', at = last.at } end
        end
        out[#out + 1] = item
    end
    return Veyl.Ok({ items = out, nextOffset = #rows == L.PageSize and offset + L.PageSize or nil, unreadTotal = Messages.UnreadTotal(s.number) })
end, { cooldown = 300 })

---------------------------------------------------------------------------
-- Thread (paginated, newest first)
---------------------------------------------------------------------------
Veyl.RegisterCallback('thread', function(src, citizenid, convId, beforeId)
    local s = Phone.Session(src)
    if not s then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    if not Veyl.Validate.int(convId, 1) then return Veyl.Err('INVALID_INPUT', 'Invalid conversation') end
    local me = isMember(convId, s.number)
    if not me then return Veyl.Err('NO_PERMISSION', 'You are not in this conversation') end
    local conv = MySQL.single.await('SELECT id, kind, name FROM veyl_phone_conversations WHERE id = ?', { convId })
    local rows = MySQL.query.await([[SELECT id, conversation_id, sender, kind, body, payload, UNIX_TIMESTAMP(created_at) AS at FROM veyl_phone_messages
        WHERE conversation_id = ? AND id < ? ORDER BY id DESC LIMIT ?]], { convId, tonumber(beforeId) or 9e15, L.PageSize }) or {}
    local blocked = conv.kind == 'group' and blockedSet(citizenid) or {}
    local items, mine = {}, {}
    for _, r in ipairs(rows) do
        if not blocked[r.sender] then
            items[#items + 1] = messageOut(r)
            if r.sender == s.number then mine[#mine + 1] = r.id end
        end
    end
    local states = receiptStates(mine, conv.kind == 'direct')
    for _, m in ipairs(items) do
        if m.sender == s.number then
            local st = states[m.id]
            m.state = st and st.state or 'sent'
            if conv.kind == 'group' and st then m.deliveredCount, m.total = st.delivered, st.total end
        end
    end
    local names = contactNames(citizenid)
    local members = {}
    for _, mb in ipairs(activeMembers(convId)) do
        members[#members + 1] = { number = mb.number, display = Phone.FormatNumber(mb.number), name = names[mb.number], role = mb.role, me = mb.number == s.number }
    end
    local title = conv.name
    if conv.kind == 'direct' then
        for _, mb in ipairs(members) do if not mb.me then title = mb.name or mb.display end end
    end
    return Veyl.Ok({ conv = { id = conv.id, kind = conv.kind, title = title or 'Group', muted = me.muted == 1 or me.muted == true, role = me.role },
        members = members, items = items, nextBefore = #rows == L.PageSize and rows[#rows].id or nil })
end, { cooldown = 200 })

---------------------------------------------------------------------------
-- Send
---------------------------------------------------------------------------
local function directConversation(a, b)
    local key = a < b and (a .. ':' .. b) or (b .. ':' .. a)
    local id = MySQL.scalar.await('SELECT id FROM veyl_phone_conversations WHERE direct_key = ?', { key })
    if id then return id end
    local ok, newId = pcall(MySQL.insert.await, "INSERT INTO veyl_phone_conversations (kind, direct_key, created_by) VALUES ('direct', ?, ?)", { key, a })
    if not ok then return MySQL.scalar.await('SELECT id FROM veyl_phone_conversations WHERE direct_key = ?', { key }) end
    MySQL.insert.await('INSERT IGNORE INTO veyl_phone_members (conversation_id, number) VALUES (?, ?), (?, ?)', { newId, a, newId, b })
    return newId
end

--- Stores a message and fans it out. Returns the stored message (or an error).
local function store(s, convId, kind, body, payload, clientOp)
    local okIns, id = pcall(MySQL.insert.await, [[INSERT INTO veyl_phone_messages (conversation_id, sender, kind, body, payload, client_op)
        VALUES (?, ?, ?, ?, ?, ?)]], { convId, s.number, kind, body, payload and json.encode(payload) or nil, clientOp })
    if not okIns or not id then
        -- Same client operation id: the first attempt was stored; return it (no duplicate message).
        local existing = clientOp and MySQL.single.await([[SELECT id, conversation_id, sender, kind, body, payload, UNIX_TIMESTAMP(created_at) AS at
            FROM veyl_phone_messages WHERE sender = ? AND client_op = ?]], { s.number, clientOp })
        if existing then local m = messageOut(existing) m.state = 'sent' return m end
        return nil
    end
    MySQL.update.await('UPDATE veyl_phone_conversations SET last_message_id = ? WHERE id = ?', { id, convId })
    MySQL.update.await('UPDATE veyl_phone_members SET last_read_id = ? WHERE conversation_id = ? AND number = ?', { id, convId, s.number })
    local conv = MySQL.single.await('SELECT kind, name FROM veyl_phone_conversations WHERE id = ?', { convId })
    local msg = { id = id, convId = convId, sender = s.number, kind = kind, body = body, payload = payload, at = os.time(), state = 'sent' }
    if kind == 'system' then msg.state = nil end
    for _, mb in ipairs(activeMembers(convId)) do
        if mb.number ~= s.number then
            local cid = Phone.CidByNumber(mb.number)
            if cid and not Blocks.IsBlocked(cid, s.number) then
                if kind ~= 'system' then MySQL.insert.await('INSERT IGNORE INTO veyl_phone_receipts (message_id, number) VALUES (?, ?)', { id, mb.number }) end
                local rs = Phone.SessionByNumber(mb.number)
                if rs then
                    local names = contactNames(cid)
                    local title = conv.kind == 'direct' and (names[s.number] or Phone.FormatNumber(s.number)) or (conv.name or 'Group')
                    local muted = MySQL.scalar.await('SELECT muted FROM veyl_phone_members WHERE conversation_id = ? AND number = ?', { convId, mb.number })
                    Phone.Push(rs.src, 'message', { message = msg, title = title, senderName = names[s.number] or Phone.FormatNumber(s.number),
                        kind = conv.kind, muted = muted == 1 or muted == true })
                end
            end
        end
    end
    return msg
end
Messages.Store = store

--- send({ convId? | to?, kind = 'text'|'contact'|'location', body?, contact? = { name, number }, label?, clientOp })
Veyl.RegisterCallback('send', function(src, citizenid, req)
    local s = Phone.Session(src)
    if not s then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    if type(req) ~= 'table' or not Veyl.Validate.str(req.clientOp, 8, 64, '^[%w%-]+$') then return Veyl.Err('INVALID_INPUT', 'Invalid message') end
    if not Phone.Rate(src, 'send', 600) then return Veyl.Err('RATE_LIMITED', 'You are sending too fast') end
    local convId
    if req.to then
        local to = Phone.NormalizeNumber(req.to)
        if not to or to == s.number then return Veyl.Err('INVALID_INPUT', 'Enter a valid number') end
        local cid = Phone.CidByNumber(to)
        if not cid then return Veyl.Err('NOT_FOUND', 'That number is not in service') end
        if Blocks.IsBlocked(cid, s.number) then return Veyl.Err('UNDELIVERABLE', 'Your message could not be delivered to this number') end
        convId = directConversation(s.number, to)
    else
        convId = Veyl.Validate.int(req.convId, 1) and req.convId or nil
        if not convId or not isMember(convId, s.number) then return Veyl.Err('NO_PERMISSION', 'You are not in this conversation') end
        local conv = MySQL.single.await('SELECT kind FROM veyl_phone_conversations WHERE id = ?', { convId })
        if conv.kind == 'direct' then
            local other = MySQL.scalar.await('SELECT number FROM veyl_phone_members WHERE conversation_id = ? AND number <> ? LIMIT 1', { convId, s.number })
            local ocid = other and Phone.CidByNumber(other)
            if not ocid then return Veyl.Err('NOT_FOUND', 'That number is not in service') end
            if Blocks.IsBlocked(ocid, s.number) then return Veyl.Err('UNDELIVERABLE', 'Your message could not be delivered to this number') end
        end
    end

    local kind, body, payload = req.kind, nil, nil
    if kind == 'text' then
        body = Phone.Clean(req.body, L.MessageLength)
        if not body then return Veyl.Err('INVALID_INPUT', 'Message is empty') end
    elseif kind == 'contact' then
        local c = type(req.contact) == 'table' and req.contact or {}
        local name, number = Phone.Clean(c.name, 40), Phone.NormalizeNumber(c.number)
        if not name or not number then return Veyl.Err('INVALID_INPUT', 'Invalid contact card') end
        body, payload = name, { name = name, number = number }
    elseif kind == 'location' then
        -- The position is the sender's own, read on the server (never client-supplied coordinates).
        local ped = GetPlayerPed(src)
        if ped == 0 then return Veyl.Err('INVALID_STATE', 'Location unavailable') end
        local c = GetEntityCoords(ped)
        local label = Phone.Clean(req.label, 60) or 'Shared location'
        body, payload = label, { x = math.floor(c.x * 10) / 10, y = math.floor(c.y * 10) / 10, label = label }
    else
        return Veyl.Err('INVALID_INPUT', 'Unsupported message type')
    end
    local msg = store(s, convId, kind, body, payload, req.clientOp)
    if not msg then return Veyl.Err('DATABASE_ERROR', 'Message not sent') end
    return Veyl.Ok(msg)
end)

---------------------------------------------------------------------------
-- Delivery and read receipts
---------------------------------------------------------------------------
--- ack(ids): the recipient's live session confirms delivery.
Veyl.RegisterCallback('ack', function(src, _, ids)
    local s = Phone.Session(src)
    if not s or type(ids) ~= 'table' then return Veyl.Ok() end
    for i, id in ipairs(ids) do
        if i > L.PendingDeliveryBatch then break end
        if Veyl.Validate.int(id, 1) then
            local n = MySQL.update.await('UPDATE veyl_phone_receipts SET delivered_at = CURRENT_TIMESTAMP WHERE message_id = ? AND number = ? AND delivered_at IS NULL',
                { id, s.number })
            if n == 1 then pushReceipt(id) end
        end
    end
    return Veyl.Ok()
end)

--- read(convId, uptoId): marks the conversation read; read receipts only if this reader allows them.
Veyl.RegisterCallback('read', function(src, citizenid, convId, uptoId)
    local s = Phone.Session(src)
    if not s then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    if not Veyl.Validate.int(convId, 1) or not Veyl.Validate.int(uptoId, 1) then return Veyl.Err('INVALID_INPUT', 'Invalid') end
    if not isMember(convId, s.number) then return Veyl.Err('NO_PERMISSION', 'You are not in this conversation') end
    MySQL.update.await('UPDATE veyl_phone_members SET last_read_id = GREATEST(last_read_id, ?) WHERE conversation_id = ? AND number = ?', { uptoId, convId, s.number })
    if s.settings.readReceipts then
        local ids = MySQL.query.await([[SELECT r.message_id FROM veyl_phone_receipts r JOIN veyl_phone_messages m ON m.id = r.message_id
            WHERE m.conversation_id = ? AND r.number = ? AND r.read_at IS NULL AND m.id <= ? LIMIT 200]], { convId, s.number, uptoId }) or {}
        for _, r in ipairs(ids) do
            MySQL.update.await('UPDATE veyl_phone_receipts SET read_at = CURRENT_TIMESTAMP, delivered_at = COALESCE(delivered_at, CURRENT_TIMESTAMP) WHERE message_id = ? AND number = ?',
                { r.message_id, s.number })
            pushReceipt(r.message_id)
        end
    end
    return Veyl.Ok({ unreadTotal = Messages.UnreadTotal(s.number) })
end, { cooldown = 200 })

--- When a phone session starts, push undelivered messages (ids) so the client acknowledges them.
AddEventHandler('veyl_phone:sessionStarted', function(src, s)
    CreateThread(function()
        local rows = MySQL.query.await([[SELECT r.message_id FROM veyl_phone_receipts r WHERE r.number = ? AND r.delivered_at IS NULL
            ORDER BY r.message_id LIMIT ?]], { s.number, L.PendingDeliveryBatch }) or {}
        if #rows == 0 then return end
        local ids = {}
        for i, r in ipairs(rows) do ids[i] = r.message_id end
        Phone.Push(src, 'pending', { ids = ids })
    end)
end)

---------------------------------------------------------------------------
-- Groups
---------------------------------------------------------------------------
local function admin(convId, number)
    local m = isMember(convId, number)
    return m and m.role == 'admin'
end

Veyl.RegisterCallback('groupCreate', function(src, citizenid, name, numbers)
    local s = Phone.Session(src)
    if not s then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    if not Phone.Rate(src, 'groupCreate', 8000) then return Veyl.Err('RATE_LIMITED', 'Wait a moment before creating another group') end
    name = Phone.Clean(name, L.GroupName)
    if not name then return Veyl.Err('INVALID_INPUT', 'Name the group') end
    if type(numbers) ~= 'table' then return Veyl.Err('INVALID_INPUT', 'Add members') end
    local list, seen = {}, { [s.number] = true }
    for _, n in ipairs(numbers) do
        local nn = Phone.NormalizeNumber(n)
        if nn and not seen[nn] then
            seen[nn] = true
            if not Phone.CidByNumber(nn) then return Veyl.Err('NOT_FOUND', ('%s is not in service'):format(Phone.FormatNumber(nn))) end
            list[#list + 1] = nn
        end
    end
    if #list < 1 then return Veyl.Err('INVALID_INPUT', 'Add at least one member') end
    if #list + 1 > L.GroupMembers then return Veyl.Err('LIMIT', ('Groups have at most %d members'):format(L.GroupMembers)) end
    local id = MySQL.insert.await("INSERT INTO veyl_phone_conversations (kind, name, created_by) VALUES ('group', ?, ?)", { name, s.number })
    MySQL.insert.await("INSERT INTO veyl_phone_members (conversation_id, number, role) VALUES (?, ?, 'admin')", { id, s.number })
    for _, n in ipairs(list) do MySQL.insert.await('INSERT IGNORE INTO veyl_phone_members (conversation_id, number) VALUES (?, ?)', { id, n }) end
    store(s, id, 'system', ('%s created "%s"'):format(s.name, name), nil, nil)
    return Veyl.Ok({ id = id }, 'Group created')
end)

Veyl.RegisterCallback('groupRename', function(src, _, convId, name)
    local s = Phone.Session(src)
    if not s then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    if not Veyl.Validate.int(convId, 1) or not admin(convId, s.number) then return Veyl.Err('NO_PERMISSION', 'Only the group admin can do that') end
    name = Phone.Clean(name, L.GroupName)
    if not name then return Veyl.Err('INVALID_INPUT', 'Name the group') end
    MySQL.update.await("UPDATE veyl_phone_conversations SET name = ? WHERE id = ? AND kind = 'group'", { name, convId })
    store(s, convId, 'system', ('%s renamed the group to "%s"'):format(s.name, name), nil, nil)
    return Veyl.Ok(nil, 'Group renamed')
end, { cooldown = 2000 })

Veyl.RegisterCallback('groupAdd', function(src, _, convId, number)
    local s = Phone.Session(src)
    if not s then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    if not Veyl.Validate.int(convId, 1) or not admin(convId, s.number) then return Veyl.Err('NO_PERMISSION', 'Only the group admin can do that') end
    number = Phone.NormalizeNumber(number)
    if not number or not Phone.CidByNumber(number) then return Veyl.Err('NOT_FOUND', 'That number is not in service') end
    local count = MySQL.scalar.await('SELECT COUNT(*) FROM veyl_phone_members WHERE conversation_id = ? AND left_at IS NULL', { convId }) or 0
    if count >= L.GroupMembers then return Veyl.Err('LIMIT', 'The group is full') end
    MySQL.insert.await([[INSERT INTO veyl_phone_members (conversation_id, number) VALUES (?, ?)
        ON DUPLICATE KEY UPDATE left_at = NULL, joined_at = CURRENT_TIMESTAMP, role = 'member']], { convId, number })
    -- New members only see messages from now on.
    local last = MySQL.scalar.await('SELECT last_message_id FROM veyl_phone_conversations WHERE id = ?', { convId }) or 0
    MySQL.update.await('UPDATE veyl_phone_members SET last_read_id = ? WHERE conversation_id = ? AND number = ?', { last, convId, number })
    store(s, convId, 'system', ('%s added %s'):format(s.name, Phone.FormatNumber(number)), nil, nil)
    return Veyl.Ok(nil, 'Member added')
end, { cooldown = 1000 })

local function promoteIfNeeded(convId)
    if MySQL.scalar.await("SELECT 1 FROM veyl_phone_members WHERE conversation_id = ? AND role = 'admin' AND left_at IS NULL", { convId }) then return end
    local nextAdmin = MySQL.scalar.await('SELECT number FROM veyl_phone_members WHERE conversation_id = ? AND left_at IS NULL ORDER BY joined_at LIMIT 1', { convId })
    if nextAdmin then MySQL.update.await("UPDATE veyl_phone_members SET role = 'admin' WHERE conversation_id = ? AND number = ?", { convId, nextAdmin }) end
end

Veyl.RegisterCallback('groupRemove', function(src, _, convId, number)
    local s = Phone.Session(src)
    if not s then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    if not Veyl.Validate.int(convId, 1) or not admin(convId, s.number) then return Veyl.Err('NO_PERMISSION', 'Only the group admin can do that') end
    number = Phone.NormalizeNumber(number)
    if not number or number == s.number then return Veyl.Err('INVALID_INPUT', 'Use Leave group to leave') end
    local n = MySQL.update.await('UPDATE veyl_phone_members SET left_at = CURRENT_TIMESTAMP WHERE conversation_id = ? AND number = ? AND left_at IS NULL', { convId, number })
    if n ~= 1 then return Veyl.Err('NOT_FOUND', 'Not a member') end
    store(s, convId, 'system', ('%s removed %s'):format(s.name, Phone.FormatNumber(number)), nil, nil)
    local rs = Phone.SessionByNumber(number)
    if rs then Phone.Push(rs.src, 'removed', { convId = convId }) end
    return Veyl.Ok(nil, 'Member removed')
end, { cooldown = 1000 })

Veyl.RegisterCallback('groupLeave', function(src, _, convId)
    local s = Phone.Session(src)
    if not s then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    if not Veyl.Validate.int(convId, 1) then return Veyl.Err('INVALID_INPUT', 'Invalid conversation') end
    local conv = MySQL.single.await('SELECT kind FROM veyl_phone_conversations WHERE id = ?', { convId })
    if not conv or conv.kind ~= 'group' or not isMember(convId, s.number) then return Veyl.Err('NO_PERMISSION', 'You are not in this group') end
    store(s, convId, 'system', ('%s left'):format(s.name), nil, nil)
    MySQL.update.await('UPDATE veyl_phone_members SET left_at = CURRENT_TIMESTAMP WHERE conversation_id = ? AND number = ?', { convId, s.number })
    promoteIfNeeded(convId)
    return Veyl.Ok(nil, 'You left the group')
end, { cooldown = 1000 })

Veyl.RegisterCallback('mute', function(src, _, convId, on)
    local s = Phone.Session(src)
    if not s then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    if not Veyl.Validate.int(convId, 1) or not isMember(convId, s.number) then return Veyl.Err('NO_PERMISSION', 'You are not in this conversation') end
    MySQL.update.await('UPDATE veyl_phone_members SET muted = ? WHERE conversation_id = ? AND number = ?', { on and 1 or 0, convId, s.number })
    return Veyl.Ok({ muted = on == true }, on and 'Conversation muted' or 'Conversation unmuted')
end, { cooldown = 300 })
