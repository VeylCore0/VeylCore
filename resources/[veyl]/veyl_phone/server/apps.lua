-- App Store (install/remove optional apps, per character) and Notes.

---------------------------------------------------------------------------
-- App Store
---------------------------------------------------------------------------
--- appInstall(appId, on) -> Ok({ installed = { ids } })
Veyl.RegisterCallback('appInstall', function(src, citizenid, appId, on)
    local s = Phone.Session(src)
    if not s then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    if type(appId) ~= 'string' or not Phone.OptionalApps[appId] then return Veyl.Err('NOT_FOUND', 'That app is not available') end
    if not Phone.Rate(src, 'install', 400) then return Veyl.Err('RATE_LIMITED', 'Slow down') end
    local set = Phone.InstalledSet(s.settings)
    set[appId] = on == true or nil
    local list = {}
    for _, a in ipairs(PhoneConfig.Apps) do if set[a.id] and Phone.OptionalApps[a.id] then list[#list + 1] = a.id end end
    local settings = Phone.CleanSettings(s.settings)
    settings.installed = list
    MySQL.update.await('UPDATE veyl_phone_accounts SET settings = ? WHERE citizenid = ?', { json.encode(settings), citizenid })
    s.settings = settings
    local label = appId
    for _, a in ipairs(PhoneConfig.Apps) do if a.id == appId then label = a.label end end
    return Veyl.Ok({ installed = list }, on and (label .. ' installed') or (label .. ' removed'))
end)

---------------------------------------------------------------------------
-- Notes (private to the character)
---------------------------------------------------------------------------
local N = PhoneConfig.Notes

Veyl.RegisterCallback('notes', function(src, citizenid)
    if not Phone.Session(src) then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    local rows = MySQL.query.await([[SELECT id, title, body, UNIX_TIMESTAMP(updated_at) AS at FROM veyl_phone_notes
        WHERE citizenid = ? ORDER BY updated_at DESC, id DESC LIMIT ?]], { citizenid, N.Max }) or {}
    return Veyl.Ok(rows)
end, { cooldown = 200 })

--- noteSave({ id?, title, body }) -> Ok({ id })
Veyl.RegisterCallback('noteSave', function(src, citizenid, note)
    if not Phone.Session(src) then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    if type(note) ~= 'table' then return Veyl.Err('INVALID_INPUT', 'Invalid note') end
    if not Phone.Rate(src, 'note', 400) then return Veyl.Err('RATE_LIMITED', 'Slow down') end
    local body = type(note.body) == 'string' and note.body:gsub('[\0-\8\11\12\14-\31]', ''):sub(1, N.BodyLength) or ''
    local title = Phone.Clean(note.title, N.TitleLength) or Phone.Clean(body:match('[^\n]+'), N.TitleLength)
    if not title then return Veyl.Err('INVALID_INPUT', 'Write something first') end
    if note.id ~= nil then
        if not Veyl.Validate.int(note.id, 1) then return Veyl.Err('INVALID_INPUT', 'Invalid note') end
        local n = MySQL.update.await('UPDATE veyl_phone_notes SET title = ?, body = ? WHERE id = ? AND citizenid = ?', { title, body, note.id, citizenid })
        if n ~= 1 then
            -- Unchanged content also reports 0 rows on some drivers: confirm the note exists and is ours.
            if not MySQL.scalar.await('SELECT 1 FROM veyl_phone_notes WHERE id = ? AND citizenid = ?', { note.id, citizenid }) then
                return Veyl.Err('NOT_FOUND', 'Note not found')
            end
        end
        return Veyl.Ok({ id = note.id }, 'Saved')
    end
    local count = MySQL.scalar.await('SELECT COUNT(*) FROM veyl_phone_notes WHERE citizenid = ?', { citizenid }) or 0
    if count >= N.Max then return Veyl.Err('LIMIT', ('You can keep up to %d notes'):format(N.Max)) end
    local id = MySQL.insert.await('INSERT INTO veyl_phone_notes (citizenid, title, body) VALUES (?, ?, ?)', { citizenid, title, body })
    if not id then return Veyl.Err('DATABASE_ERROR', 'Could not save the note') end
    return Veyl.Ok({ id = id }, 'Saved')
end)

Veyl.RegisterCallback('noteDelete', function(src, citizenid, id)
    if not Phone.Session(src) then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    if not Veyl.Validate.int(id, 1) then return Veyl.Err('INVALID_INPUT', 'Invalid note') end
    local n = MySQL.update.await('DELETE FROM veyl_phone_notes WHERE id = ? AND citizenid = ?', { id, citizenid })
    if n ~= 1 then return Veyl.Err('NOT_FOUND', 'Note not found') end
    return Veyl.Ok(nil, 'Note deleted')
end, { cooldown = 300 })
