-- Messages: direct and group conversations between numbers. Everything is stored; online members get a live push.
-- Read state = each member's last_read_id (read receipts in direct chats). Messages from a number you blocked are
-- never shown to you (and never pushed), in direct and group chats alike.

Messages = {}
local L = PhoneConfig.Limits

local function directKey(a, b) if a > b then a, b = b, a end return a .. '-' .. b end
local function inClause(n) return string.rep('?,', n):sub(1, -2) end

--- Contact names for a viewer: { [number] = name }
local function contactMap(cid)
    local m = {}
    for _, r in ipairs(MySQL.query.await('SELECT number, name FROM veyl_ph_contacts WHERE owner_cid = ?', { cid }) or {}) do m[r.number] = r.name end
    return m
end

local function membership(convId, number)
    return MySQL.single.await('SELECT * FROM veyl_ph_members WHERE conversation_id = ? AND number = ? AND left_at IS NULL', { convId, number })
end

local function activeMembers(convId)
    local out = {}
    for _, r in ipairs(MySQL.query.await('SELECT number, role, muted, last_read_id FROM veyl_ph_members WHERE conversation_id = ? AND left_at IS NULL',
        { convId }) or {}) do out[#out + 1] = r end
    return out
end

local function messageView(m, viewerNumber, names)
    return {
        id = m.id, conversationId = m.conversation_id, sender = m.sender, kind = m.kind, body = m.body,
        payload = m.payload and Phone.Decode(m.payload, nil) or nil, time = m.ts, mine = m.sender == viewerNumber,
        senderDisplay = names and (names[m.sender] or PhoneUtil.Format(m.sender)) or nil,
    }
end

local MSG_COLS = 'id, conversation_id, sender, kind, body, payload, UNIX_TIMESTAMP(created_at) AS ts'

--- Conversation summary as `viewer` sees it.
local function summary(conv, viewer, names)
    local me = membership(conv.id, viewer.number)
    local members = activeMembers(conv.id)
    local title, peer
    if conv.kind == 'direct' then
        for _, m in ipairs(MySQL.query.await('SELECT number FROM veyl_ph_members WHERE conversation_id = ?', { conv.id }) or {}) do
            if m.number ~= viewer.number then peer = m.number end
        end
        title = peer and (names[peer] or PhoneUtil.Format(peer)) or 'Unknown'
    else
        title = conv.name or 'Group'
    end
    local last = MySQL.single.await(([[SELECT %s FROM veyl_ph_messages WHERE conversation_id = ?
        AND sender NOT IN (SELECT number FROM veyl_ph_blocks WHERE owner_cid = ?) ORDER BY id DESC LIMIT 1]]):format(MSG_COLS), { conv.id, viewer.cid })
    local unread = MySQL.scalar.await([[SELECT COUNT(*) FROM veyl_ph_messages WHERE conversation_id = ? AND id > ? AND sender <> ?
        AND sender NOT IN (SELECT number FROM veyl_ph_blocks WHERE owner_cid = ?)]], { conv.id, me and me.last_read_id or 0, viewer.number, viewer.cid }) or 0
    local memberList, peerRead = {}, nil
    for _, m in ipairs(members) do
        memberList[#memberList + 1] = { number = m.number, display = names[m.number] or PhoneUtil.Format(m.number), admin = m.role == 'admin' }
        if m.number == peer then peerRead = m.last_read_id end
    end
    return {
        id = conv.id, kind = conv.kind, title = title, peer = peer, members = memberList,
        muted = me and (me.muted == 1 or me.muted == true) or false, admin = me and me.role == 'admin' or false,
        unread = unread, last = last and messageView(last, viewer.number, names) or nil,
        peerReadId = conv.kind == 'direct' and peerRead or nil, -- read receipt: the peer has read up to this message id
    }
end

function Messages.UnreadTotal(number)
    local cid = Phone.CidByNumber(number)
    return MySQL.scalar.await([[SELECT COUNT(*) FROM veyl_ph_messages msg JOIN veyl_ph_members mem ON mem.conversation_id = msg.conversation_id
        AND mem.number = ? AND mem.left_at IS NULL WHERE msg.id > mem.last_read_id AND msg.sender <> ?
        AND msg.sender NOT IN (SELECT number FROM veyl_ph_blocks WHERE owner_cid = ?)]], { number, number, cid or '' }) or 0
end

local function session(src)
    local s = Phone.Session(src)
    if not s then return nil, Veyl.Err('NO_SESSION', 'Open your phone first') end
    return s
end

---------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------
Veyl.RegisterCallback('conversations', function(src)
    local s, err = session(src)
    if not s then return err end
    local names = contactMap(s.cid)
    local out = {}
    for _, conv in ipairs(MySQL.query.await([[SELECT c.* FROM veyl_ph_conversations c JOIN veyl_ph_members m ON m.conversation_id = c.id
        WHERE m.number = ? AND m.left_at IS NULL AND c.last_message_id IS NOT NULL ORDER BY c.last_message_id DESC LIMIT 100]], { s.number }) or {}) do
        out[#out + 1] = summary(conv, s, names)
    end
    return Veyl.Ok(out)
end)

--- thread(conversationId, beforeId?) -> { conversation, messages (oldest first), more }
Veyl.RegisterCallback('thread', function(src, _, convId, beforeId)
    local s, err = session(src)
    if not s then return err end
    convId = tonumber(convId) or 0
    if not membership(convId, s.number) then return Veyl.Err('NOT_FOUND', 'Conversation not found') end
    beforeId = tonumber(beforeId) or 0
    local rows = MySQL.query.await(([[SELECT %s FROM veyl_ph_messages WHERE conversation_id = ? AND (? = 0 OR id < ?)
        AND sender NOT IN (SELECT number FROM veyl_ph_blocks WHERE owner_cid = ?) ORDER BY id DESC LIMIT ?]]):format(MSG_COLS),
        { convId, beforeId, beforeId, s.cid, L.PageSize + 1 }) or {}
    local names = contactMap(s.cid)
    local list = {}
    for i = math.min(#rows, L.PageSize), 1, -1 do list[#list + 1] = messageView(rows[i], s.number, names) end
    local conv = MySQL.single.await('SELECT * FROM veyl_ph_conversations WHERE id = ?', { convId })
    return Veyl.Ok({ conversation = summary(conv, s, names), messages = list, more = #rows > L.PageSize })
end)

--- read(conversationId): marks everything in it as read; the other members get a `read` push (receipts).
Veyl.RegisterCallback('read', function(src, _, convId)
    local s, err = session(src)
    if not s then return err end
    convId = tonumber(convId) or 0
    local conv = MySQL.single.await('SELECT * FROM veyl_ph_conversations WHERE id = ?', { convId })
    if not conv or not membership(convId, s.number) then return Veyl.Err('NOT_FOUND', 'Conversation not found') end
    local upTo = conv.last_message_id or 0
    MySQL.update.await('UPDATE veyl_ph_members SET last_read_id = GREATEST(last_read_id, ?) WHERE conversation_id = ? AND number = ?', { upTo, convId, s.number })
    for _, m in ipairs(activeMembers(convId)) do
        if m.number ~= s.number then
            local other = Phone.byNumber[m.number]
            if other then Phone.Push(other.src, 'read', { conversationId = convId, number = s.number, lastReadId = upTo }) end
        end
    end
    return Veyl.Ok({ unread = Messages.UnreadTotal(s.number) })
end)

---------------------------------------------------------------------------
-- Sending
---------------------------------------------------------------------------
local function directConversation(a, b)
    local key = directKey(a, b)
    MySQL.query.await("INSERT IGNORE INTO veyl_ph_conversations (kind, direct_key, created_by) VALUES ('direct', ?, ?)", { key, a })
    local conv = MySQL.single.await('SELECT * FROM veyl_ph_conversations WHERE direct_key = ?', { key })
    -- (Re)join both: a hidden direct chat comes back when either side writes.
    for _, n in ipairs({ a, b }) do
        MySQL.query.await([[INSERT INTO veyl_ph_members (conversation_id, number) VALUES (?, ?)
            ON DUPLICATE KEY UPDATE left_at = NULL]], { conv.id, n })
    end
    return conv
end

--- Stores a message and pushes it to every online member who has not blocked the sender. Returns the message row.
function Messages.Post(conv, senderNumber, kind, body, payload, clientOp)
    local id = MySQL.insert.await([[INSERT INTO veyl_ph_messages (conversation_id, sender, kind, body, payload, client_op)
        VALUES (?, ?, ?, ?, ?, ?)]], { conv.id, senderNumber, kind, body, payload and json.encode(payload) or nil, clientOp })
    MySQL.update.await('UPDATE veyl_ph_conversations SET last_message_id = ? WHERE id = ?', { id, conv.id })
    if kind ~= 'system' then
        MySQL.update.await('UPDATE veyl_ph_members SET last_read_id = ? WHERE conversation_id = ? AND number = ?', { id, conv.id, senderNumber })
    end
    local msg = MySQL.single.await(('SELECT %s FROM veyl_ph_messages WHERE id = ?'):format(MSG_COLS), { id })
    for _, m in ipairs(activeMembers(conv.id)) do
        local s = Phone.byNumber[m.number]
        if s and Phone.Session(s.src) and (m.number == senderNumber or not Contacts.IsBlocked(s.cid, senderNumber)) then
            local names = contactMap(s.cid)
            Phone.Push(s.src, 'message', {
                conversation = summary(MySQL.single.await('SELECT * FROM veyl_ph_conversations WHERE id = ?', { conv.id }), s, names),
                message = messageView(msg, s.number, names),
                silent = m.muted == 1 or m.muted == true or s.settings.dnd or s.settings.silent,
            })
        end
    end
    return msg
end

--- send({ conversationId? | to?, body, kind?, clientOp }) -> { conversation, message }
--- kind: 'text' (default), 'location' (the server reads your position; body = optional label) or 'contact'
--- (payload = { number, name }). clientOp (8-64 chars, unique per send) makes retries safe: the same op never posts twice.
Veyl.RegisterCallback('send', function(src, _, input)
    local s, err = session(src)
    if not s then return err end
    if type(input) ~= 'table' then return Veyl.Err('INVALID_INPUT', 'Invalid message') end
    if s.settings.airplane then return Veyl.Err('UNAVAILABLE', 'Turn off airplane mode first') end
    local op = type(input.clientOp) == 'string' and #input.clientOp >= 8 and #input.clientOp <= 64 and input.clientOp or nil
    if not op then return Veyl.Err('INVALID_INPUT', 'Missing clientOp') end
    local names = contactMap(s.cid)
    local dup = MySQL.single.await(('SELECT %s FROM veyl_ph_messages WHERE sender = ? AND client_op = ?'):format(MSG_COLS), { s.number, op })
    if dup then
        local conv = MySQL.single.await('SELECT * FROM veyl_ph_conversations WHERE id = ?', { dup.conversation_id })
        return Veyl.Ok({ conversation = summary(conv, s, names), message = messageView(dup, s.number, names) })
    end
    if not Phone.Rate(src, 'send', 700) then return Veyl.Err('RATE_LIMITED', 'Slow down') end

    local kind = input.kind == 'location' and 'location' or input.kind == 'contact' and 'contact' or 'text'
    local body, payload
    if kind == 'text' then
        body = PhoneUtil.CleanBody(input.body, L.MessageLength)
        if not body then return Veyl.Err('INVALID_INPUT', 'Type a message') end
    elseif kind == 'location' then
        local c = Veyl.GetPlayerCoords(src)
        if not c then return Veyl.Err('UNAVAILABLE', 'Location unavailable') end
        payload = { x = math.floor(c.x * 10) / 10, y = math.floor(c.y * 10) / 10 }
        body = PhoneUtil.Clean(input.body, 80) or 'Shared location'
    else
        local p = type(input.payload) == 'table' and input.payload or {}
        local n = PhoneUtil.Normalize(p.number)
        if not n then return Veyl.Err('INVALID_INPUT', 'Invalid contact') end
        payload = { number = n, name = PhoneUtil.Clean(p.name, L.NameLength) or PhoneUtil.Format(n) }
        body = payload.name
    end

    local conv
    if input.conversationId then
        conv = MySQL.single.await('SELECT * FROM veyl_ph_conversations WHERE id = ?', { tonumber(input.conversationId) or 0 })
        if not conv or not membership(conv.id, s.number) then return Veyl.Err('NOT_FOUND', 'Conversation not found') end
        if conv.kind == 'direct' then
            -- Bring a hidden direct chat back for the other side too.
            local peer = MySQL.scalar.await('SELECT number FROM veyl_ph_members WHERE conversation_id = ? AND number <> ?', { conv.id, s.number })
            if peer then conv = directConversation(s.number, peer) end
        end
    else
        local to = PhoneUtil.Normalize(input.to)
        if not to or to == s.number then return Veyl.Err('INVALID_INPUT', 'Enter a valid number') end
        if not Phone.CidByNumber(to) then return Veyl.Err('NOT_FOUND', 'That number is not in service') end
        conv = directConversation(s.number, to)
    end
    local msg = Messages.Post(conv, s.number, kind, body, payload, op)
    conv = MySQL.single.await('SELECT * FROM veyl_ph_conversations WHERE id = ?', { conv.id })
    return Veyl.Ok({ conversation = summary(conv, s, names), message = messageView(msg, s.number, names) })
end, { cooldown = 200 })

---------------------------------------------------------------------------
-- Groups and conversation settings
---------------------------------------------------------------------------
local function system(conv, actor, text) Messages.Post(conv, actor, 'system', text, nil, nil) end

local function pushConversation(convId, extraNumbers)
    local conv = MySQL.single.await('SELECT * FROM veyl_ph_conversations WHERE id = ?', { convId })
    local targets = {}
    for _, m in ipairs(activeMembers(convId)) do targets[m.number] = true end
    for _, n in ipairs(extraNumbers or {}) do targets[n] = true end
    for n in pairs(targets) do
        local s = Phone.byNumber[n]
        if s then
            local inside = membership(convId, n) ~= nil
            Phone.Push(s.src, 'conversation', inside and { conversation = summary(conv, s, contactMap(s.cid)) } or { removed = convId })
        end
    end
end

--- groupCreate({ name, numbers }) -> conversation
Veyl.RegisterCallback('groupCreate', function(src, _, input)
    local s, err = session(src)
    if not s then return err end
    if type(input) ~= 'table' or type(input.numbers) ~= 'table' then return Veyl.Err('INVALID_INPUT', 'Pick people to add') end
    local name = PhoneUtil.Clean(input.name, L.GroupName)
    if not name then return Veyl.Err('INVALID_INPUT', 'Give the group a name') end
    local numbers, seen = {}, { [s.number] = true }
    for _, n in ipairs(input.numbers) do
        n = PhoneUtil.Normalize(n)
        if n and not seen[n] and Phone.CidByNumber(n) then seen[n] = true numbers[#numbers + 1] = n end
    end
    if #numbers < 1 then return Veyl.Err('INVALID_INPUT', 'Add at least one valid number') end
    if #numbers + 1 > L.GroupMembers then return Veyl.Err('LIMIT_REACHED', ('Groups have up to %d members'):format(L.GroupMembers)) end
    if not Phone.Rate(src, 'group', 5000) then return Veyl.Err('RATE_LIMITED', 'Wait a moment') end
    local id = MySQL.insert.await("INSERT INTO veyl_ph_conversations (kind, name, created_by) VALUES ('group', ?, ?)", { name, s.number })
    MySQL.insert.await("INSERT INTO veyl_ph_members (conversation_id, number, role) VALUES (?, ?, 'admin')", { id, s.number })
    for _, n in ipairs(numbers) do MySQL.insert.await('INSERT INTO veyl_ph_members (conversation_id, number) VALUES (?, ?)', { id, n }) end
    local conv = MySQL.single.await('SELECT * FROM veyl_ph_conversations WHERE id = ?', { id })
    system(conv, s.number, ('%s created the group'):format(PhoneUtil.Format(s.number)))
    pushConversation(id)
    return Veyl.Ok(summary(MySQL.single.await('SELECT * FROM veyl_ph_conversations WHERE id = ?', { id }), s, contactMap(s.cid)), 'Group created')
end)

local function groupAdmin(s, convId)
    local conv = MySQL.single.await("SELECT * FROM veyl_ph_conversations WHERE id = ? AND kind = 'group'", { tonumber(convId) or 0 })
    if not conv then return nil, Veyl.Err('NOT_FOUND', 'Group not found') end
    local me = membership(conv.id, s.number)
    if not me then return nil, Veyl.Err('NOT_FOUND', 'Group not found') end
    if me.role ~= 'admin' then return nil, Veyl.Err('NO_PERMISSION', 'Only group admins can do that') end
    return conv
end

Veyl.RegisterCallback('groupRename', function(src, _, convId, name)
    local s, err = session(src)
    if not s then return err end
    local conv, e = groupAdmin(s, convId)
    if not conv then return e end
    name = PhoneUtil.Clean(name, L.GroupName)
    if not name then return Veyl.Err('INVALID_INPUT', 'Enter a name') end
    MySQL.update.await('UPDATE veyl_ph_conversations SET name = ? WHERE id = ?', { name, conv.id })
    system(conv, s.number, ('Group renamed to "%s"'):format(name))
    pushConversation(conv.id)
    return Veyl.Ok({ name = name }, 'Renamed')
end, { cooldown = 1000 })

Veyl.RegisterCallback('groupAdd', function(src, _, convId, number)
    local s, err = session(src)
    if not s then return err end
    local conv, e = groupAdmin(s, convId)
    if not conv then return e end
    number = PhoneUtil.Normalize(number)
    if not number or not Phone.CidByNumber(number) then return Veyl.Err('NOT_FOUND', 'That number is not in service') end
    if membership(conv.id, number) then return Veyl.Err('ALREADY_EXISTS', 'Already in the group') end
    if #activeMembers(conv.id) >= L.GroupMembers then return Veyl.Err('LIMIT_REACHED', 'The group is full') end
    MySQL.query.await([[INSERT INTO veyl_ph_members (conversation_id, number, last_read_id) VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE left_at = NULL, role = 'member', last_read_id = VALUES(last_read_id)]], { conv.id, number, conv.last_message_id or 0 })
    system(conv, s.number, ('%s was added'):format(PhoneUtil.Format(number)))
    pushConversation(conv.id)
    return Veyl.Ok(nil, 'Added')
end, { cooldown = 500 })

Veyl.RegisterCallback('groupRemove', function(src, _, convId, number)
    local s, err = session(src)
    if not s then return err end
    local conv, e = groupAdmin(s, convId)
    if not conv then return e end
    number = PhoneUtil.Normalize(number)
    if not number or number == s.number or not membership(conv.id, number) then return Veyl.Err('NOT_FOUND', 'Not in the group') end
    MySQL.update.await('UPDATE veyl_ph_members SET left_at = NOW() WHERE conversation_id = ? AND number = ?', { conv.id, number })
    system(conv, s.number, ('%s was removed'):format(PhoneUtil.Format(number)))
    pushConversation(conv.id, { number })
    return Veyl.Ok(nil, 'Removed')
end, { cooldown = 500 })

--- leave(conversationId): leave a group, or hide a direct chat (it comes back when a new message arrives).
Veyl.RegisterCallback('leave', function(src, _, convId)
    local s, err = session(src)
    if not s then return err end
    local conv = MySQL.single.await('SELECT * FROM veyl_ph_conversations WHERE id = ?', { tonumber(convId) or 0 })
    if not conv or not membership(conv.id, s.number) then return Veyl.Err('NOT_FOUND', 'Conversation not found') end
    MySQL.update.await('UPDATE veyl_ph_members SET left_at = NOW(), role = \'member\' WHERE conversation_id = ? AND number = ?', { conv.id, s.number })
    if conv.kind == 'group' then
        local rest = activeMembers(conv.id)
        -- A group is never left without an admin.
        local hasAdmin = false
        for _, m in ipairs(rest) do if m.role == 'admin' then hasAdmin = true end end
        if not hasAdmin and rest[1] then
            MySQL.update.await("UPDATE veyl_ph_members SET role = 'admin' WHERE conversation_id = ? AND number = ?", { conv.id, rest[1].number })
        end
        if #rest > 0 then system(conv, s.number, ('%s left'):format(PhoneUtil.Format(s.number))) end
        pushConversation(conv.id, { s.number })
    end
    return Veyl.Ok(nil, conv.kind == 'group' and 'You left the group' or 'Conversation removed')
end, { cooldown = 500 })

Veyl.RegisterCallback('mute', function(src, _, convId, on)
    local s, err = session(src)
    if not s then return err end
    local n = MySQL.update.await('UPDATE veyl_ph_members SET muted = ? WHERE conversation_id = ? AND number = ? AND left_at IS NULL',
        { on == true and 1 or 0, tonumber(convId) or 0, s.number })
    if n == 0 and not membership(tonumber(convId) or 0, s.number) then return Veyl.Err('NOT_FOUND', 'Conversation not found') end
    return Veyl.Ok({ muted = on == true })
end)

Messages.InClause = inClause
