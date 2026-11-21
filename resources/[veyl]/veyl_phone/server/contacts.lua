-- Contacts and blocked numbers (per character).

local L = PhoneConfig.Limits

local function session(src) return Phone.Session(src) end

Veyl.RegisterCallback('contacts', function(src, citizenid)
    if not session(src) then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    local rows = MySQL.query.await('SELECT id, name, number, note, color, favorite FROM veyl_phone_contacts WHERE owner_cid = ? ORDER BY name',
        { citizenid }) or {}
    for _, r in ipairs(rows) do r.favorite = r.favorite == 1 or r.favorite == true r.display = Phone.FormatNumber(r.number) end
    return Veyl.Ok(rows)
end, { cooldown = 300 })

--- contactSave({ id?, name, number, note?, color?, favorite? })
Veyl.RegisterCallback('contactSave', function(src, citizenid, c)
    local s = session(src)
    if not s then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    if type(c) ~= 'table' then return Veyl.Err('INVALID_INPUT', 'Invalid contact') end
    local name = Phone.Clean(c.name, 40)
    local number = Phone.NormalizeNumber(c.number)
    if not name then return Veyl.Err('INVALID_INPUT', 'Give the contact a name') end
    if not number then return Veyl.Err('INVALID_INPUT', 'Numbers have 7 digits, like 555-1234') end
    if number == s.number then return Veyl.Err('INVALID_INPUT', 'That is your own number') end
    local note = Phone.Clean(c.note, 80)
    local color = Veyl.Validate.int(c.color, 0, 7) and c.color or 0
    local fav = c.favorite == true and 1 or 0
    if Veyl.Validate.int(c.id, 1) then
        local okU, n = pcall(MySQL.update.await, 'UPDATE veyl_phone_contacts SET name = ?, number = ?, note = ?, color = ?, favorite = ? WHERE id = ? AND owner_cid = ?',
            { name, number, note, color, fav, c.id, citizenid })
        if not okU then return Veyl.Err('DUPLICATE', 'You already have a contact with that number') end
        if n ~= 1 then return Veyl.Err('NOT_FOUND', 'Contact not found') end
        return Veyl.Ok({ id = c.id }, 'Contact saved')
    end
    local count = MySQL.scalar.await('SELECT COUNT(*) FROM veyl_phone_contacts WHERE owner_cid = ?', { citizenid }) or 0
    if count >= L.Contacts then return Veyl.Err('LIMIT', ('You can keep %d contacts'):format(L.Contacts)) end
    local ok, id = pcall(MySQL.insert.await, 'INSERT INTO veyl_phone_contacts (owner_cid, name, number, note, color, favorite) VALUES (?, ?, ?, ?, ?, ?)',
        { citizenid, name, number, note, color, fav })
    if not ok then return Veyl.Err('DUPLICATE', 'You already have a contact with that number') end
    return Veyl.Ok({ id = id }, 'Contact added')
end, { cooldown = 400 })

Veyl.RegisterCallback('contactDelete', function(src, citizenid, id)
    if not session(src) then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    if not Veyl.Validate.int(id, 1) then return Veyl.Err('INVALID_INPUT', 'Invalid contact') end
    local n = MySQL.update.await('DELETE FROM veyl_phone_contacts WHERE id = ? AND owner_cid = ?', { id, citizenid })
    if n ~= 1 then return Veyl.Err('NOT_FOUND', 'Contact not found') end
    return Veyl.Ok(nil, 'Contact deleted')
end, { cooldown = 400 })

---------------------------------------------------------------------------
-- Blocking: blocks new direct messages and calls from that number. In shared groups, messages from a number you
-- blocked are hidden from you (and don't count as unread); they still reach the rest of the group.
---------------------------------------------------------------------------
Blocks = {}

function Blocks.IsBlocked(ownerCid, number)
    return MySQL.scalar.await('SELECT 1 FROM veyl_phone_blocks WHERE owner_cid = ? AND number = ?', { ownerCid, number }) ~= nil
end

Veyl.RegisterCallback('blocked', function(src, citizenid)
    if not session(src) then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    local rows = MySQL.query.await([[SELECT b.number, c.name FROM veyl_phone_blocks b
        LEFT JOIN veyl_phone_contacts c ON c.owner_cid = b.owner_cid AND c.number = b.number WHERE b.owner_cid = ? ORDER BY b.created_at DESC]],
        { citizenid }) or {}
    for _, r in ipairs(rows) do r.display = Phone.FormatNumber(r.number) end
    return Veyl.Ok(rows)
end, { cooldown = 300 })

Veyl.RegisterCallback('block', function(src, citizenid, number, on)
    local s = session(src)
    if not s then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    number = Phone.NormalizeNumber(number)
    if not number or number == s.number then return Veyl.Err('INVALID_INPUT', 'Invalid number') end
    if on then
        local count = MySQL.scalar.await('SELECT COUNT(*) FROM veyl_phone_blocks WHERE owner_cid = ?', { citizenid }) or 0
        if count >= L.Blocked then return Veyl.Err('LIMIT', 'Your block list is full') end
        MySQL.insert.await('INSERT IGNORE INTO veyl_phone_blocks (owner_cid, number) VALUES (?, ?)', { citizenid, number })
        return Veyl.Ok(nil, ('%s blocked'):format(Phone.FormatNumber(number)))
    end
    MySQL.update.await('DELETE FROM veyl_phone_blocks WHERE owner_cid = ? AND number = ?', { citizenid, number })
    return Veyl.Ok(nil, ('%s unblocked'):format(Phone.FormatNumber(number)))
end, { cooldown = 500 })
