-- Calls: authoritative state machine (server) + voice adapter.
--   Idle -> Ringing -> Connected -> Ended
-- Ended reasons: cancelled (caller hung up while ringing), declined, timeout, hangup, busy, unavailable, dropped,
-- character_changed, voice_failed, server_restart.
-- A call is only ever "connected" once the voice adapter has put both parties in the same call channel. Without a
-- supported voice resource, calls are disabled and the phone says so.

Calls = { live = {}, bySrc = {} }
local C = PhoneConfig.Calls

---------------------------------------------------------------------------
-- Voice adapter (pma-voice, verified against its README/docs: server export setPlayerCall(source, channel), 0 = leave;
-- client export toggleMutePlayer(serverId)). No speakerphone: pma-voice documents no proximity behaviour for calls.
---------------------------------------------------------------------------
Voice = {}

function Voice.Name()
    if PhoneConfig.Voice == 'auto' or PhoneConfig.Voice == 'pma-voice' then
        if GetResourceState('pma-voice') == 'started' then return 'pma-voice' end
    end
    return nil
end

function Calls.Availability()
    if Voice.Name() then return { available = true, provider = Voice.Name() } end
    return { available = false, reason = 'Calls need a voice resource. Install and start pma-voice to enable calling.' }
end

function Voice.Join(src, channel)
    local ok, err = pcall(function() exports['pma-voice']:setPlayerCall(src, channel) end)
    if not ok then print(('^1[veyl_phone] voice join failed for %s: %s^7'):format(src, tostring(err))) end
    return ok
end

function Voice.Leave(src)
    if not GetPlayerName(src) then return end
    pcall(function() exports['pma-voice']:setPlayerCall(src, 0) end)
end

---------------------------------------------------------------------------
-- State machine
---------------------------------------------------------------------------
local function party(src)
    local s = Phone.Session(src)
    return s and { src = src, cid = s.cid, number = s.number, name = s.name } or nil
end

local function displayFor(viewerCid, number)
    local name = viewerCid and MySQL.scalar.await('SELECT name FROM veyl_phone_contacts WHERE owner_cid = ? AND number = ?', { viewerCid, number })
    return name or Phone.FormatNumber(number)
end

local function finish(call, reason, by)
    if not Calls.live[call.id] then return end
    Calls.live[call.id] = nil
    for _, p in ipairs({ call.caller, call.callee }) do
        if Calls.bySrc[p.src] == call.id then Calls.bySrc[p.src] = nil end
        if call.state == 'connected' then Voice.Leave(p.src) end
        Phone.Push(p.src, 'call', { id = call.id, state = 'ended', reason = reason })
    end
    MySQL.update('UPDATE veyl_phone_calls SET ended_at = CURRENT_TIMESTAMP, end_reason = ? WHERE id = ?', { reason, call.id })
    -- Missed call notification for the callee when it never connected.
    if not call.answeredAt and (reason == 'timeout' or reason == 'cancelled' or reason == 'dnd') then
        Notify.Send(call.callee.cid, { app = 'phone', title = 'Missed call', body = displayFor(call.callee.cid, call.caller.number),
            route = 'phone/recents', dedupe = 'missed:' .. call.id })
    end
end
Calls.Finish = finish

--- callStart(number)
Veyl.RegisterCallback('callStart', function(src, citizenid, number)
    local caller = party(src)
    if not caller then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    if not Voice.Name() then return Veyl.Err('VOICE_UNAVAILABLE', Calls.Availability().reason) end
    if not Phone.Rate(src, 'call', 3000) then return Veyl.Err('RATE_LIMITED', 'Wait a moment') end
    number = Phone.NormalizeNumber(number)
    if not number or number == caller.number then return Veyl.Err('INVALID_INPUT', 'Enter a valid number') end
    if Calls.bySrc[src] then return Veyl.Err('BUSY', 'You are already in a call') end
    local calleeCid = Phone.CidByNumber(number)
    local id = MySQL.insert.await('INSERT INTO veyl_phone_calls (caller, callee) VALUES (?, ?)', { caller.number, number })
    local function ended(reason, msg)
        MySQL.update('UPDATE veyl_phone_calls SET ended_at = CURRENT_TIMESTAMP, end_reason = ? WHERE id = ?', { reason, id })
        return Veyl.Err(reason:upper(), msg)
    end
    if not calleeCid then return ended('unavailable', 'That number is not in service') end
    -- Blocked callers hear the same "unavailable" as an offline number (no information leak).
    if Blocks.IsBlocked(calleeCid, caller.number) then return ended('unavailable', 'The number you called is unavailable') end
    local rs = Phone.SessionByNumber(number)
    if not rs then return ended('unavailable', 'The number you called is unavailable') end
    local callee = party(rs.src)
    if Calls.bySrc[rs.src] then return ended('busy', 'The line is busy') end
    local call = { id = id, caller = caller, callee = callee, state = 'ringing', startedAt = GetGameTimer() }
    if rs.settings.dnd then
        Calls.live[id] = call
        finish(call, 'dnd')
        return Veyl.Err('UNAVAILABLE', 'The number you called is unavailable')
    end
    Calls.live[id] = call
    Calls.bySrc[src] = id
    Calls.bySrc[rs.src] = id
    Phone.Push(rs.src, 'call', { id = id, state = 'incoming', number = caller.number, display = displayFor(callee.cid, caller.number),
        quiet = rs.settings.silent })
    SetTimeout(C.RingSeconds * 1000, function()
        local c = Calls.live[id]
        if c and c.state == 'ringing' then finish(c, 'timeout') end
    end)
    return Veyl.Ok({ id = id, state = 'ringing', number = number, display = displayFor(citizenid, number) })
end)

Veyl.RegisterCallback('callAnswer', function(src, _, id)
    local call = Calls.live[tonumber(id) or -1]
    if not call or call.callee.src ~= src or call.state ~= 'ringing' then return Veyl.Err('INVALID_STATE', 'The call ended') end
    if not Voice.Name() then finish(call, 'voice_failed') return Veyl.Err('VOICE_UNAVAILABLE', Calls.Availability().reason) end
    local channel = C.ChannelBase + call.id
    if not (Voice.Join(call.caller.src, channel) and Voice.Join(call.callee.src, channel)) then
        finish(call, 'voice_failed')
        return Veyl.Err('VOICE_FAILED', 'Could not connect the call audio')
    end
    call.state, call.channel, call.answeredAt = 'connected', channel, os.time()
    MySQL.update('UPDATE veyl_phone_calls SET answered_at = CURRENT_TIMESTAMP WHERE id = ?', { call.id })
    for _, p in ipairs({ call.caller, call.callee }) do
        Phone.Push(p.src, 'call', { id = call.id, state = 'connected', since = call.answeredAt,
            other = p == call.caller and call.callee.src or call.caller.src })
    end
    return Veyl.Ok({ id = call.id, state = 'connected', since = call.answeredAt })
end)

Veyl.RegisterCallback('callDecline', function(src, _, id)
    local call = Calls.live[tonumber(id) or -1]
    if not call or call.callee.src ~= src or call.state ~= 'ringing' then return Veyl.Ok() end
    finish(call, 'declined')
    return Veyl.Ok()
end)

Veyl.RegisterCallback('callEnd', function(src, _, id)
    local call = Calls.live[tonumber(id) or -1]
    if not call or (call.caller.src ~= src and call.callee.src ~= src) then return Veyl.Ok() end
    finish(call, call.state == 'ringing' and (call.caller.src == src and 'cancelled' or 'declined') or 'hangup')
    return Veyl.Ok()
end)

--- Mute: pma-voice has no "mute my own call microphone" export, so the OTHER party's client mutes you locally
--- (toggleMutePlayer). Muting therefore means: they can't hear you.
Veyl.RegisterCallback('callMute', function(src, _, id, on)
    local call = Calls.live[tonumber(id) or -1]
    if not call or call.state ~= 'connected' or (call.caller.src ~= src and call.callee.src ~= src) then return Veyl.Err('INVALID_STATE', 'Not in a call') end
    local other = call.caller.src == src and call.callee or call.caller
    TriggerClientEvent('veyl_phone:muteFrom', other.src, src, on == true)
    return Veyl.Ok({ muted = on == true })
end, { cooldown = 300 })

Veyl.RegisterCallback('recents', function(src, citizenid, beforeId)
    local s = Phone.Session(src)
    if not s then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    local rows = MySQL.query.await([[SELECT id, caller, callee, UNIX_TIMESTAMP(started_at) AS at, answered_at IS NOT NULL AS answered,
        TIMESTAMPDIFF(SECOND, answered_at, ended_at) AS seconds, end_reason FROM veyl_phone_calls
        WHERE (caller = ? OR callee = ?) AND id < ? ORDER BY id DESC LIMIT ?]], { s.number, s.number, tonumber(beforeId) or 9e15, PhoneConfig.Limits.PageSize }) or {}
    local names = {}
    for _, r in ipairs(MySQL.query.await('SELECT number, name FROM veyl_phone_contacts WHERE owner_cid = ?', { citizenid }) or {}) do names[r.number] = r.name end
    local out = {}
    for _, r in ipairs(rows) do
        local outgoing = r.caller == s.number
        local other = outgoing and r.callee or r.caller
        local answered = r.answered == 1 or r.answered == true
        out[#out + 1] = { id = r.id, number = other, display = names[other] or Phone.FormatNumber(other), outgoing = outgoing, answered = answered,
            missed = not outgoing and not answered, seconds = tonumber(r.seconds), at = r.at, reason = r.end_reason }
    end
    return Veyl.Ok({ items = out, voice = Calls.Availability() })
end, { cooldown = 300 })

-- Any way a party leaves ends the call and releases the voice channel.
AddEventHandler('veyl_phone:sessionEnded', function(src, _, reason)
    local id = Calls.bySrc[src]
    local call = id and Calls.live[id]
    if call then finish(call, reason == 'character_changed' and 'character_changed' or 'dropped') end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, call in pairs(Calls.live) do
        if call.state == 'connected' then Voice.Leave(call.caller.src) Voice.Leave(call.callee.src) end
    end
end)
