-- Contacts and blocked numbers (per character).

Contacts = {}
local L = PhoneConfig.Limits

local function view(r)
    return { id = r.id, name = r.name, number = r.number, display = PhoneUtil.Format(r.number), note = r.note,
        favorite = r.favorite == 1 or r.favorite == true, photo = r.photo }
end

--- A contact picture: a small JPEG data URL. Returns the clean string, false when it should be cleared, or nil when it was not sent (keep what is there).
local function cleanPhoto(v)
    if v == nil then return nil end
    if v == false or v == '' then return false end
    if type(v) ~= 'string' or #v > L.ContactPhoto or not v:match('^data:image/jpe?g;base64,[%w+/=]+$') then return nil, 'That picture is not allowed' end
    return v
end

function Contacts.IsBlocked(ownerCid, number)
    return MySQL.scalar.await('SELECT 1 FROM veyl_ph_blocks WHERE owner_cid = ? AND number = ?', { ownerCid, number }) ~= nil
end

Veyl.RegisterCallback('contacts', function(src, citizenid)
    if not Phone.Session(src) then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    local out = {}
    for _, r in ipairs(MySQL.query.await('SELECT * FROM veyl_ph_contacts WHERE owner_cid = ? ORDER BY favorite DESC, name ASC', { citizenid }) or {}) do
        out[#out + 1] = view(r)
    end
    return Veyl.Ok(out)
end)

--- contactSave({ id?, name, number, note?, favorite? }) -> contact. Without id: add (or update the contact with that number).
Veyl.RegisterCallback('contactSave', function(src, citizenid, input)
    local s = Phone.Session(src)
    if not s then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    if type(input) ~= 'table' then return Veyl.Err('INVALID_INPUT', 'Invalid contact') end
    local name = PhoneUtil.Clean(input.name, L.NameLength)
    local number = PhoneUtil.Normalize(input.number)
    if not name then return Veyl.Err('INVALID_INPUT', 'Enter a name') end
    if not number then return Veyl.Err('INVALID_INPUT', 'Enter a 7-digit number') end
    if number == s.number then return Veyl.Err('INVALID_INPUT', 'That is your own number') end
    local note = PhoneUtil.Clean(input.note, 80)
    local fav = input.favorite == true and 1 or 0
    local photo, photoErr = cleanPhoto(input.photo)
    if photoErr then return Veyl.Err('INVALID_INPUT', photoErr) end
    local id = tonumber(input.id)
    if id then
        local clash = MySQL.scalar.await('SELECT id FROM veyl_ph_contacts WHERE owner_cid = ? AND number = ? AND id <> ?', { citizenid, number, id })
        if clash then return Veyl.Err('ALREADY_EXISTS', 'You already have a contact with that number') end
        local n = MySQL.update.await('UPDATE veyl_ph_contacts SET name = ?, number = ?, note = ?, favorite = ?' .. (photo ~= nil and ', photo = ?' or '') .. ' WHERE id = ? AND owner_cid = ?',
            photo ~= nil and { name, number, note, fav, photo or nil, id, citizenid } or { name, number, note, fav, id, citizenid })
        if n == 0 and not MySQL.scalar.await('SELECT 1 FROM veyl_ph_contacts WHERE id = ? AND owner_cid = ?', { id, citizenid }) then
            return Veyl.Err('NOT_FOUND', 'Contact not found')
        end
    else
        local count = MySQL.scalar.await('SELECT COUNT(*) FROM veyl_ph_contacts WHERE owner_cid = ?', { citizenid }) or 0
        local existing = MySQL.scalar.await('SELECT id FROM veyl_ph_contacts WHERE owner_cid = ? AND number = ?', { citizenid, number })
        if not existing and count >= L.Contacts then return Veyl.Err('LIMIT_REACHED', ('You can save up to %d contacts'):format(L.Contacts)) end
        MySQL.query.await([[INSERT INTO veyl_ph_contacts (owner_cid, name, number, note, favorite, photo) VALUES (?, ?, ?, ?, ?, ?)
            ON DUPLICATE KEY UPDATE name = VALUES(name), note = VALUES(note), favorite = VALUES(favorite)]] .. (photo ~= nil and ', photo = VALUES(photo)' or ''), { citizenid, name, number, note, fav, photo or nil })
    end
    local r = MySQL.single.await('SELECT * FROM veyl_ph_contacts WHERE owner_cid = ? AND number = ?', { citizenid, number })
    return Veyl.Ok(view(r), 'Contact saved')
end)

Veyl.RegisterCallback('contactDelete', function(src, citizenid, id)
    if not Phone.Session(src) then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    local n = MySQL.update.await('DELETE FROM veyl_ph_contacts WHERE id = ? AND owner_cid = ?', { tonumber(id) or 0, citizenid })
    if n == 0 then return Veyl.Err('NOT_FOUND', 'Contact not found') end
    return Veyl.Ok(nil, 'Contact deleted')
end)

Veyl.RegisterCallback('blocks', function(src, citizenid)
    if not Phone.Session(src) then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    local out = {}
    for _, r in ipairs(MySQL.query.await('SELECT number FROM veyl_ph_blocks WHERE owner_cid = ? ORDER BY created_at DESC', { citizenid }) or {}) do
        out[#out + 1] = { number = r.number, display = Phone.DisplayFor(citizenid, r.number) }
    end
    return Veyl.Ok(out)
end)

--- block(number, on): blocked numbers cannot call you, and their messages to you are not delivered.
Veyl.RegisterCallback('block', function(src, citizenid, number, on)
    local s = Phone.Session(src)
    if not s then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    number = PhoneUtil.Normalize(number)
    if not number or number == s.number then return Veyl.Err('INVALID_INPUT', 'Enter a valid number') end
    if on == false then
        MySQL.update.await('DELETE FROM veyl_ph_blocks WHERE owner_cid = ? AND number = ?', { citizenid, number })
        return Veyl.Ok({ blocked = false }, 'Unblocked')
    end
    local count = MySQL.scalar.await('SELECT COUNT(*) FROM veyl_ph_blocks WHERE owner_cid = ?', { citizenid }) or 0
    if count >= L.Blocked then return Veyl.Err('LIMIT_REACHED', 'Too many blocked numbers') end
    MySQL.query.await('INSERT IGNORE INTO veyl_ph_blocks (owner_cid, number) VALUES (?, ?)', { citizenid, number })
    return Veyl.Ok({ blocked = true }, 'Blocked')
end)
