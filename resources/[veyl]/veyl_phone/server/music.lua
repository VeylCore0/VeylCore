-- Music: the speaker. Nearby players hear the same station, louder the closer they are.

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
-- Music speaker: nearby players hear the same station, louder the closer they are
---------------------------------------------------------------------------
local speakers = {} -- [src] = station id
Veyl.RegisterCallback('speakerPlay', function(src, _, station)
    local _, err = session(src)
    if err then return err end
    local ok = station == 'veyl'
    for _, s in ipairs(C.Music.Stations) do if s.id == station then ok = true end end
    if not ok then return Veyl.Err('NOT_FOUND', 'Unknown station') end
    speakers[src] = station
    TriggerClientEvent('veyl_phone:speaker', -1, src, station)
    return Veyl.Ok(nil, 'Playing out loud')
end, { cooldown = 2000 })

Veyl.RegisterCallback('speakerStop', function(src)
    speakers[src] = nil
    TriggerClientEvent('veyl_phone:speaker', -1, src, nil)
    return Veyl.Ok()
end, { cooldown = 500 })

AddEventHandler('playerDropped', function()
    local src = source
    if speakers[src] then speakers[src] = nil TriggerClientEvent('veyl_phone:speaker', -1, src, nil) end
end)
