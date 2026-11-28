-- Maps: saved places, the places everyone sees, and shared (live) locations.

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
-- Maps
---------------------------------------------------------------------------
Veyl.RegisterCallback('mapsData', function(src, citizenid)
    local _, err = session(src)
    if err then return err end
    local saved = MySQL.query.await('SELECT id, label, x, y FROM veyl_phone_places WHERE citizenid = ? ORDER BY label', { citizenid }) or {}
    local shared = MySQL.query.await([[SELECT id, from_name, x, y, live, UNIX_TIMESTAMP(expires_at) AS expires FROM veyl_phone_shared_locations
        WHERE to_cid = ? AND expires_at > NOW() ORDER BY id DESC LIMIT 20]], { citizenid }) or {}
    -- Live shares follow the sender while they are online.
    for _, sh in ipairs(shared) do
        if sh.live == 1 then
            local fromCid = MySQL.scalar.await('SELECT from_cid FROM veyl_phone_shared_locations WHERE id = ?', { sh.id })
            local fsrc = fromCid and exports.veyl_core:GetSourceByCitizenId(fromCid)
            local pc = fsrc and Veyl.GetPlayerCoords(fsrc)
            if pc then sh.x, sh.y = pc.x, pc.y end
        end
    end
    return Veyl.Ok({ saved = saved, shared = shared, places = C.MapPlaces or {}, shareMinutes = C.ShareMinutes })
end, { cooldown = 500 })

Veyl.RegisterCallback('placeSave', function(src, citizenid, label)
    local _, err = session(src)
    if err then return err end
    label = clean(label, 40)
    if not label or #label < 1 then return Veyl.Err('INVALID_INPUT', 'Name the place') end
    if (MySQL.scalar.await('SELECT COUNT(*) FROM veyl_phone_places WHERE citizenid = ?', { citizenid }) or 0) >= 50 then
        return Veyl.Err('LIMIT', 'You can save 50 places')
    end
    local pc = Veyl.GetPlayerCoords(src)
    if not pc then return Veyl.Err('INTERNAL', 'No position') end
    MySQL.insert.await('INSERT INTO veyl_phone_places (citizenid, label, x, y, z) VALUES (?, ?, ?, ?, ?)', { citizenid, label, pc.x, pc.y, pc.z })
    return Veyl.Ok(nil, 'Place saved')
end, { cooldown = 1000 })

Veyl.RegisterCallback('placeDelete', function(src, citizenid, id)
    local _, err = session(src)
    if err then return err end
    MySQL.update.await('DELETE FROM veyl_phone_places WHERE id = ? AND citizenid = ?', { tonumber(id) or 0, citizenid })
    return Veyl.Ok()
end, { cooldown = 300 })

--- shareLocation(number, minutes, live)
Veyl.RegisterCallback('shareLocation', function(src, citizenid, number, minutes, live)
    local s, err = session(src)
    if err then return err end
    local ok = false
    for _, m in ipairs(C.ShareMinutes) do if tonumber(minutes) == m then ok = true end end
    if not ok then return Veyl.Err('INVALID_INPUT', 'Choose how long') end
    local to = cidByNumber(number)
    if not to then return Veyl.Err('NOT_FOUND', 'No phone with that number') end
    if to == citizenid then return Veyl.Err('INVALID_INPUT', 'That is your own number') end
    local pc = Veyl.GetPlayerCoords(src)
    MySQL.insert.await([[INSERT INTO veyl_phone_shared_locations (from_cid, from_name, to_cid, x, y, live, expires_at)
        VALUES (?, ?, ?, ?, ?, ?, NOW() + INTERVAL ? MINUTE)]], { citizenid, s.name or s.number, to, pc.x, pc.y, live == true and 1 or 0, tonumber(minutes) })
    Notify.Send(to, { app = 'maps', title = 'Location shared', body = ('%s shared %s location with you'):format(s.name or s.number, live == true and 'their live' or 'a'), route = 'maps' })
    return Veyl.Ok(nil, ('Shared for %d min'):format(minutes))
end, { cooldown = 3000 })
