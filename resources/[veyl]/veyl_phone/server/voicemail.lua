-- Voicemail: messages people left when you could not answer.

local C = PhoneConfig
local function session(src)
    local s = Phone.Session(src)
    if not s then return nil, Veyl.Err('NO_SESSION', 'Open your phone first') end
    return s
end
local function core(name, ...) return Veyl.Await('veyl_core', name, 15000, ...) end
local function cidByNumber(number) return Phone.CidByNumber(number) end
local function clean(s, max) return PhoneUtil.Clean(s, max) end
local function charName(pd) return pd and ('%s %s'):format(pd.charinfo.firstname or '', pd.charinfo.lastname or '') or 'Unknown' end
local seq = 0
local function op(kind, cid) seq = seq + 1 return ('phone:%s:%s:%d:%d'):format(kind, cid, os.time(), seq) end

---------------------------------------------------------------------------
-- Voicemail
---------------------------------------------------------------------------
Veyl.RegisterCallback('voicemailList', function(src, citizenid)
    local _, err = session(src)
    if err then return err end
    return Veyl.Ok(MySQL.query.await([[SELECT id, from_number, from_name, body, is_read, (audio IS NOT NULL) AS recorded, seconds, UNIX_TIMESTAMP(created_at) AS at FROM veyl_phone_voicemail
        WHERE citizenid = ? ORDER BY id DESC LIMIT ?]], { citizenid, C.Voicemail.Max }) or {})
end, { cooldown = 300 })

--- A recording is a data URL from the phone's recorder (webm/ogg/mp4 audio). Returns the clean string or nil + why.
local function cleanAudio(audio)
    if type(audio) ~= 'string' or #audio > C.Voicemail.AudioChars or not audio:match('^data:audio/[%w%-%.]+[%w;=%-%._,]*;base64,[%w+/=]+$') then return nil end
    return audio
end

--- voicemailLeave(number, body, audio?, seconds?): a typed message, or a recording (then body is optional).
Veyl.RegisterCallback('voicemailLeave', function(src, citizenid, number, body, audio, seconds)
    local s, err = session(src)
    if err then return err end
    local to = cidByNumber(number)
    if not to then return Veyl.Err('NOT_FOUND', 'No phone with that number') end
    local rec
    if audio ~= nil and audio ~= false then
        rec = cleanAudio(audio)
        seconds = tonumber(seconds)
        if not rec or not seconds or seconds < 1 or seconds > C.Voicemail.AudioSeconds + 2 then return Veyl.Err('INVALID_INPUT', 'That recording is not allowed') end
        seconds = math.floor(seconds)
        body = clean(body, C.Voicemail.Length) or 'Voice message'
    else
        body = clean(body, C.Voicemail.Length)
        if not body or #body < 2 then return Veyl.Err('INVALID_INPUT', 'Say something') end
    end
    local blocked = MySQL.scalar.await('SELECT 1 FROM veyl_ph_blocks WHERE owner_cid = ? AND number = ?', { to, s.number })
    if blocked then return Veyl.Ok(nil, 'Voicemail left') end -- silently dropped for blocked callers
    MySQL.insert.await('INSERT INTO veyl_phone_voicemail (citizenid, from_number, from_name, body, audio, seconds) VALUES (?, ?, ?, ?, ?, ?)', { to, s.number, s.name, body, rec, rec and seconds or nil })
    Notify.Send(to, { app = 'voicemail', title = 'New voicemail', body = ('From %s'):format(s.name or s.number), route = 'voicemail' })
    return Veyl.Ok(nil, 'Voicemail left')
end, { cooldown = 3000 })

--- voicemailAudio(id): the recording of one of your voicemails.
Veyl.RegisterCallback('voicemailAudio', function(src, citizenid, id)
    local _, err = session(src)
    if err then return err end
    local a = MySQL.scalar.await('SELECT audio FROM veyl_phone_voicemail WHERE id = ? AND citizenid = ? AND audio IS NOT NULL', { tonumber(id) or 0, citizenid })
    return a and Veyl.Ok({ audio = a }) or Veyl.Err('NOT_FOUND', 'No recording')
end, { cooldown = 200 })

Veyl.RegisterCallback('voicemailRead', function(src, citizenid, id)
    local _, err = session(src)
    if err then return err end
    MySQL.update.await('UPDATE veyl_phone_voicemail SET is_read = 1 WHERE id = ? AND citizenid = ?', { tonumber(id) or 0, citizenid })
    return Veyl.Ok()
end, { cooldown = 100 })

Veyl.RegisterCallback('voicemailDelete', function(src, citizenid, id)
    local _, err = session(src)
    if err then return err end
    MySQL.update.await('DELETE FROM veyl_phone_voicemail WHERE id = ? AND citizenid = ?', { tonumber(id) or 0, citizenid })
    return Veyl.Ok()
end, { cooldown = 200 })
