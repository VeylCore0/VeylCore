-- Camera and gallery: photos are taken on the client with screenshot-basic and stored as small JPEG data URLs.

local C = PhoneConfig
local function session(src)
    local s = Phone.Session(src)
    if not s then return nil, Veyl.Err('NO_SESSION', 'Open your phone first') end
    return s
end
local function core(name, ...) return Veyl.Await('veyl_core', name, 15000, ...) end
local function cidByNumber(number) return Phone.CidByNumber(number) end
local function charName(pd) return pd and ('%s %s'):format(pd.charinfo.firstname or '', pd.charinfo.lastname or '') or 'Unknown' end
local seq = 0
local function op(kind, cid) seq = seq + 1 return ('phone:%s:%s:%d:%d'):format(kind, cid, os.time(), seq) end

---------------------------------------------------------------------------
-- Camera / Gallery (photos are taken on the client with screenshot-basic and stored as small JPEG data URLs)
---------------------------------------------------------------------------
Veyl.RegisterCallback('photoSave', function(src, citizenid, image)
    local _, err = session(src)
    if err then return err end
    if type(image) ~= 'string' or not image:match('^data:image/jpe?g;base64,') or #image > 600000 then return Veyl.Err('INVALID_INPUT', 'Photo too large or not a photo') end
    if (MySQL.scalar.await('SELECT COUNT(*) FROM veyl_phone_photos WHERE citizenid = ?', { citizenid }) or 0) >= C.Camera.Max then
        return Veyl.Err('LIMIT', ('Your gallery is full (%d photos)'):format(C.Camera.Max))
    end
    local id = MySQL.insert.await('INSERT INTO veyl_phone_photos (citizenid, image) VALUES (?, ?)', { citizenid, image })
    return Veyl.Ok({ id = id }, 'Saved to Gallery')
end, { cooldown = 1500 })

Veyl.RegisterCallback('photoList', function(src, citizenid)
    local _, err = session(src)
    if err then return err end
    return Veyl.Ok(MySQL.query.await('SELECT id, UNIX_TIMESTAMP(created_at) AS at FROM veyl_phone_photos WHERE citizenid = ? ORDER BY id DESC', { citizenid }) or {})
end, { cooldown = 300 })

Veyl.RegisterCallback('photoGet', function(src, citizenid, id)
    local _, err = session(src)
    if err then return err end
    local img = MySQL.scalar.await('SELECT image FROM veyl_phone_photos WHERE id = ? AND citizenid = ?', { tonumber(id) or 0, citizenid })
    return img and Veyl.Ok({ image = img }) or Veyl.Err('NOT_FOUND', 'Photo not found')
end, { cooldown = 50 })

Veyl.RegisterCallback('photoDelete', function(src, citizenid, id)
    local _, err = session(src)
    if err then return err end
    MySQL.update.await('DELETE FROM veyl_phone_photos WHERE id = ? AND citizenid = ?', { tonumber(id) or 0, citizenid })
    return Veyl.Ok()
end, { cooldown = 200 })
