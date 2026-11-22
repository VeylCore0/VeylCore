-- veyl_emotes server: shared emotes. Solo emotes are client-side only; a shared emote needs the other person to accept,
-- and the server places them in front of you so both halves line up.

local C = EmotesConfig
local requests = {} -- [token] = { from, to, id, expires }

Veyl.Startup({ 'veyl_core' }, function() return true end)

local function blocked(src)
    local st = Player(src).state
    return st.medical ~= nil
end

local function near(a, b)
    local pa, pb = Veyl.GetPlayerCoords(a), Veyl.GetPlayerCoords(b)
    return pa ~= nil and pb ~= nil and #(pa - pb) <= C.SharedDistance + 1.0
end

Veyl.RegisterCallback('sharedRequest', function(src, _, id, target)
    local e = type(id) == 'string' and EmoteById[id]
    target = tonumber(target)
    if not e or not e.partner then return Veyl.Err('INVALID_INPUT', 'Unknown emote') end
    if not target or target == src or not Veyl.GetCitizenId(target) then return Veyl.Err('NOT_FOUND', 'Nobody there') end
    if not near(src, target) then return Veyl.Err('TOO_FAR', 'Stand closer') end
    if blocked(src) or blocked(target) then return Veyl.Err('INVALID_STATE', 'Not right now') end
    for t, r in pairs(requests) do if r.from == src or r.to == target then requests[t] = nil end end
    local token = Veyl.NewId()
    requests[token] = { from = src, to = target, id = id, expires = os.time() + C.RequestSeconds }
    TriggerClientEvent('veyl_emotes:request', target, token, { label = e.label, from = src, seconds = C.RequestSeconds })
    return Veyl.Ok(nil, ('Asked them: %s'):format(e.label:lower()))
end, { cooldown = 2000 })

Veyl.RegisterCallback('sharedAnswer', function(src, _, token, accept)
    local r = type(token) == 'string' and requests[token]
    if not r or r.to ~= src then return Veyl.Err('NOT_FOUND', 'This request is no longer valid') end
    requests[token] = nil
    if os.time() > r.expires then return Veyl.Err('EXPIRED', 'This request has expired') end
    if accept ~= true then
        if GetPlayerName(r.from) then Veyl.Notify(r.from, 'They said no.', 'info') end
        return Veyl.Ok()
    end
    if not GetPlayerName(r.from) or not near(r.from, src) then return Veyl.Err('TOO_FAR', 'They are no longer next to you') end
    if blocked(r.from) or blocked(src) then return Veyl.Err('INVALID_STATE', 'Not right now') end
    local e = EmoteById[r.id]
    local ped = GetPlayerPed(r.from)
    local c, h = GetEntityCoords(ped), GetEntityHeading(ped)
    local rad = math.rad(h)
    local d = e.partner.distance or 1.0
    local spot = { x = c.x - math.sin(rad) * d, y = c.y + math.cos(rad) * d, z = c.z, heading = (h + 180.0) % 360.0 }
    TriggerClientEvent('veyl_emotes:playShared', r.from, r.id, 'a', nil)
    TriggerClientEvent('veyl_emotes:playShared', src, r.id, 'b', spot)
    return Veyl.Ok()
end, { cooldown = 500 })

AddEventHandler('playerDropped', function()
    local src = source
    for t, r in pairs(requests) do if r.from == src or r.to == src then requests[t] = nil end end
end)
