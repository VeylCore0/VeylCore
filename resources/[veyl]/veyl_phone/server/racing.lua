-- Racing: record tracks, host and join races, timed and checked by the server.

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
-- Racing: tracks are recorded checkpoint by checkpoint; races are hosted, joined nearby, timed on the server
---------------------------------------------------------------------------
local races, raceSeq = {}, 0 -- [id] = { id, track, host, hostName, racers = { [src] = { name, next, done } }, state, startAt }

local function trackRow(id)
    local t = MySQL.single.await('SELECT id, name, creator, checkpoints FROM veyl_phone_race_tracks WHERE id = ?', { tonumber(id) or 0 })
    if t then t.checkpoints = json.decode(t.checkpoints) or {} end
    return t
end

Veyl.RegisterCallback('raceData', function(src)
    local _, err = session(src)
    if err then return err end
    local tracks = MySQL.query.await([[SELECT t.id, t.name, t.creator, JSON_LENGTH(t.checkpoints) AS points,
        (SELECT MIN(ms) FROM veyl_phone_race_results r WHERE r.track_id = t.id) AS best FROM veyl_phone_race_tracks t ORDER BY t.id DESC LIMIT 50]]) or {}
    local open = {}
    for id, r in pairs(races) do
        if r.state == 'lobby' then
            local n = 0
            for _ in pairs(r.racers) do n = n + 1 end
            open[#open + 1] = { id = id, track = r.track.name, host = r.hostName, racers = n, mine = r.host == src, joined = r.racers[src] ~= nil }
        end
    end
    return Veyl.Ok({ tracks = tracks, open = open })
end, { cooldown = 500 })

Veyl.RegisterCallback('raceBoard', function(src, _, trackId)
    local _, err = session(src)
    if err then return err end
    return Veyl.Ok(MySQL.query.await('SELECT name, MIN(ms) AS ms FROM veyl_phone_race_results WHERE track_id = ? GROUP BY citizenid, name ORDER BY ms LIMIT 10', { tonumber(trackId) or 0 }) or {})
end, { cooldown = 500 })

Veyl.RegisterCallback('raceTrackSave', function(src, citizenid, name, points)
    local _, err = session(src)
    if err then return err end
    name = PhoneUtil.Clean(name, 40)
    if not name or #name < 3 then return Veyl.Err('INVALID_INPUT', 'Name the track') end
    if type(points) ~= 'table' or #points < 2 or #points > 40 then return Veyl.Err('INVALID_INPUT', 'A track needs 2 to 40 checkpoints') end
    local clean = {}
    for _, p in ipairs(points) do
        if not (tonumber(p.x) and tonumber(p.y) and tonumber(p.z)) then return Veyl.Err('INVALID_INPUT', 'Bad checkpoint') end
        clean[#clean + 1] = { x = tonumber(p.x), y = tonumber(p.y), z = tonumber(p.z) }
    end
    local pd = Veyl.GetPlayerData(src)
    MySQL.insert.await('INSERT INTO veyl_phone_race_tracks (name, creator_cid, creator, checkpoints) VALUES (?, ?, ?, ?)', { name, citizenid, charName(pd), json.encode(clean) })
    return Veyl.Ok(nil, 'Track saved')
end, { cooldown = 3000 })

Veyl.RegisterCallback('raceHost', function(src, _, trackId)
    local _, err = session(src)
    if err then return err end
    local t = trackRow(trackId)
    if not t then return Veyl.Err('NOT_FOUND', 'Unknown track') end
    for _, r in pairs(races) do if r.host == src and r.state ~= 'done' then return Veyl.Err('INVALID_STATE', 'You are already hosting a race') end end
    raceSeq = raceSeq + 1
    local pd = Veyl.GetPlayerData(src)
    races[raceSeq] = { id = raceSeq, track = t, host = src, hostName = charName(pd), racers = { [src] = { name = charName(pd), next = 1 } }, state = 'lobby', created = os.time() }
    return Veyl.Ok({ id = raceSeq, start = t.checkpoints[1] }, 'Race open: others near the start can join from their Racing app')
end, { cooldown = 3000 })

Veyl.RegisterCallback('raceJoin', function(src, _, id)
    local _, err = session(src)
    if err then return err end
    local r = races[tonumber(id) or 0]
    if not r or r.state ~= 'lobby' then return Veyl.Err('NOT_FOUND', 'That race is not open') end
    local p, pc = r.track.checkpoints[1], Veyl.GetPlayerCoords(src)
    if not pc or #(pc - vector3(p.x, p.y, p.z)) > C.Racing.JoinRadius then return Veyl.Err('TOO_FAR', 'Get to the start line first') end
    r.racers[src] = { name = charName(Veyl.GetPlayerData(src)), next = 1 }
    return Veyl.Ok({ start = p }, 'Joined. Wait for the host to start.')
end, { cooldown = 1000 })

Veyl.RegisterCallback('raceStart', function(src, _, id)
    local r = races[tonumber(id) or 0]
    if not r or r.host ~= src or r.state ~= 'lobby' then return Veyl.Err('NO_PERMISSION', 'Only the host can start it') end
    r.state = 'running'
    r.startAt = GetGameTimer() + 5000
    for s in pairs(r.racers) do TriggerClientEvent('veyl_phone:race', s, { id = r.id, name = r.track.name, checkpoints = r.track.checkpoints, countdown = 5 }) end
    return Veyl.Ok(nil, 'Starting')
end, { cooldown = 2000 })

Veyl.RegisterCallback('raceCheckpoint', function(src, citizenid, id, index)
    local r = races[tonumber(id) or 0]
    local me = r and r.racers[src]
    if not me or r.state ~= 'running' or me.done or tonumber(index) ~= me.next then return Veyl.Err('INVALID_STATE', 'Not in this race') end
    if GetGameTimer() < r.startAt then return Veyl.Err('TOO_FAST', 'Jumped the start') end
    local p, pc = r.track.checkpoints[me.next], Veyl.GetPlayerCoords(src)
    if not pc or #(pc - vector3(p.x, p.y, p.z)) > 25.0 then return Veyl.Err('TOO_FAR', 'Missed the checkpoint') end
    me.next = me.next + 1
    if me.next > #r.track.checkpoints then
        me.done = GetGameTimer() - r.startAt
        MySQL.insert.await('INSERT INTO veyl_phone_race_results (track_id, citizenid, name, ms) VALUES (?, ?, ?, ?)', { r.track.id, citizenid, me.name, me.done })
        local place = 0
        for _, o in pairs(r.racers) do if o.done and o.done <= me.done then place = place + 1 end end
        local allDone = true
        for _, o in pairs(r.racers) do if not o.done then allDone = false end end
        if allDone then r.state = 'done' end
        return Veyl.Ok({ finished = true, ms = me.done, place = place }, ('Finished #%d in %.2fs'):format(place, me.done / 1000))
    end
    return Veyl.Ok({ finished = false, next = me.next })
end, { cooldown = 100 })

CreateThread(function()
    while true do
        Wait(60000)
        for id, r in pairs(races) do if os.time() - r.created > 3600 then races[id] = nil end end
    end
end)
