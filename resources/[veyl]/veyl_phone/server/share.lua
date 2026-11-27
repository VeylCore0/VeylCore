-- Share number: send your number to someone standing next to you. They get a prompt on their phone; accepting saves
-- you in their contacts. Checked on the server: distance, blocks, airplane mode, one request per pair at a time,
-- expiry. A decline is never reported back to the sender.

Share = { pending = {} }
local S = PhoneConfig.Share
local seq = 0
local lastSent = {} -- ["fromCid|toCid"] = game time of the last request

local function dist(a, b)
    if not a or not b then return math.huge end
    local dx, dy, dz = a.x - b.x, a.y - b.y, a.z - b.z
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--- nearby() -> { { id, name, distance } } people within range who can receive (have a phone, not blocking you, not in airplane mode)
Veyl.RegisterCallback('nearby', function(src)
    local s = Phone.Session(src)
    if not s then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    local me, out = Veyl.GetPlayerCoords(src), {}
    for _, id in ipairs(GetPlayers()) do
        id = tonumber(id)
        local t = id ~= src and Phone.Session(id)
        if t and not t.settings.airplane and not Contacts.IsBlocked(t.cid, s.number) then
            local d = dist(me, Veyl.GetPlayerCoords(id))
            if d <= S.Range then out[#out + 1] = { id = id, name = t.name, distance = math.floor(d * 10) / 10 } end
        end
    end
    table.sort(out, function(a, b) return a.distance < b.distance end)
    return Veyl.Ok(out)
end, { cooldown = 800 })

--- shareNumber(targetSource)
Veyl.RegisterCallback('shareNumber', function(src, citizenid, target)
    local s = Phone.Session(src)
    if not s then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    if s.settings.airplane then return Veyl.Err('UNAVAILABLE', 'Turn off airplane mode first') end
    target = tonumber(target)
    local t = target and target ~= src and Phone.Session(target)
    if not t then return Veyl.Err('NOT_FOUND', 'That person is not available') end
    if dist(Veyl.GetPlayerCoords(src), Veyl.GetPlayerCoords(target)) > S.Range + 1.0 then return Veyl.Err('TOO_FAR', 'Move closer to them') end
    -- Blocked and airplane-mode people look the same as anyone out of reach.
    if t.settings.airplane or Contacts.IsBlocked(t.cid, s.number) then return Veyl.Err('NOT_FOUND', 'That person is not available') end
    if not Phone.Rate(src, 'share', 1500) then return Veyl.Err('RATE_LIMITED', 'Slow down') end
    local key = citizenid .. '|' .. t.cid
    local now = GetGameTimer()
    if lastSent[key] and now - lastSent[key] < S.CooldownSeconds * 1000 then return Veyl.Err('RATE_LIMITED', 'You already sent them your number') end
    lastSent[key] = now
    seq = seq + 1
    local id = seq
    Share.pending[id] = { from = src, fromCid = citizenid, to = target, toCid = t.cid, name = s.name, number = s.number }
    Phone.Push(target, 'share', { id = id, from = { name = s.name, number = s.number, display = PhoneUtil.Format(s.number) }, expires = os.time() + S.ExpireSeconds })
    SetTimeout(S.ExpireSeconds * 1000, function() Share.pending[id] = nil end)
    return Veyl.Ok(nil, ('Number sent to %s'):format(t.name))
end)

--- shareAnswer(id, accept) -> { saved }
Veyl.RegisterCallback('shareAnswer', function(src, citizenid, id, accept)
    local me = Phone.Session(src)
    if not me then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    local p = Share.pending[tonumber(id) or -1]
    if not p or p.to ~= src or p.toCid ~= citizenid then return Veyl.Err('NOT_FOUND', 'That request expired') end
    Share.pending[tonumber(id)] = nil
    if accept ~= true then return Veyl.Ok({ saved = false }) end
    local name = PhoneUtil.Clean(p.name, PhoneConfig.Limits.NameLength) or PhoneUtil.Format(p.number)
    local have = MySQL.scalar.await('SELECT 1 FROM veyl_ph_contacts WHERE owner_cid = ? AND number = ?', { citizenid, p.number })
    if not have then
        local count = MySQL.scalar.await('SELECT COUNT(*) FROM veyl_ph_contacts WHERE owner_cid = ?', { citizenid }) or 0
        if count >= PhoneConfig.Limits.Contacts then return Veyl.Err('LIMIT_REACHED', 'Your contacts are full') end
        MySQL.query.await('INSERT IGNORE INTO veyl_ph_contacts (owner_cid, name, number) VALUES (?, ?, ?)', { citizenid, name, p.number })
    end
    Notify.Send(p.fromCid, { app = 'contacts', title = 'Number saved', body = ('%s saved your number.'):format(me.name), route = 'contacts', dedupe = ('share:%d'):format(tonumber(id)) })
    return Veyl.Ok({ saved = true }, have and 'Already in your contacts' or 'Contact saved')
end)
