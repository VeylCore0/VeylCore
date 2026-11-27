-- Calls: a server-side state machine plus a voice adapter.
--   ringing -> connected -> ended         (or ringing -> ended)
-- End reasons: cancelled, declined, timeout, hangup, busy, unavailable, dropped, voice_failed.
-- A call is only "connected" after the voice resource has put both players in the same call channel. Without a
-- supported voice resource calls are disabled and `hello` says why (voice.available = false).

Calls = { live = {}, bySrc = {} }
local C = PhoneConfig.Calls

---------------------------------------------------------------------------
-- Voice adapter: pma-voice (server export setPlayerCall(source, channel); 0 leaves the call)
---------------------------------------------------------------------------
local function voiceName()
    if (PhoneConfig.Voice == 'auto' or PhoneConfig.Voice == 'pma-voice') and GetResourceState('pma-voice') == 'started' then return 'pma-voice' end
    return nil
end

function Calls.Availability()
    if voiceName() then return { available = true, provider = voiceName() } end
    return { available = false, reason = 'Calls need a voice resource (start pma-voice).' }
end

local function voiceJoin(src, channel)
    local ok, err = pcall(function() exports['pma-voice']:setPlayerCall(src, channel) end)
    if not ok then print(('^1[veyl_phone] voice join failed for %s: %s^7'):format(src, tostring(err))) end
    return ok
end

local function voiceLeave(src)
    if GetPlayerName(src) then pcall(function() exports['pma-voice']:setPlayerCall(src, 0) end) end
end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
--- The call as one party sees it (sent to the UI in `call` pushes and in `hello`).
local function view(call, side)
    local me, other = call[side], call[side == 'caller' and 'callee' or 'caller']
    local state = call.state
    if state == 'ringing' then state = side == 'caller' and 'outgoing' or 'incoming' end
    return {
        id = call.id, state = state, reason = call.reason,
        peer = { number = other.number, display = Phone.DisplayFor(me.cid, other.number) },
        startedAt = call.startedAt, answeredAt = call.answeredAt,
    }
end

local function sideOf(call, src)
    if call.caller.src == src then return 'caller' end
    if call.callee.src == src then return 'callee' end
    return nil
end

function Calls.StateFor(src)
    local call = Calls.live[Calls.bySrc[src] or -1]
    return call and view(call, sideOf(call, src)) or nil
end

local function missed(call)
    Notify.Send(call.callee.cid, { app = 'phone', title = 'Missed call', body = Phone.DisplayFor(call.callee.cid, call.caller.number),
        route = 'phone/recents', dedupe = 'missed:' .. call.id })
end

local function finish(call, reason)
    if not Calls.live[call.id] then return end
    Calls.live[call.id] = nil
    local wasConnected = call.state == 'connected'
    call.state, call.reason = 'ended', reason
    for _, side in ipairs({ 'caller', 'callee' }) do
        local p = call[side]
        if p.src and Calls.bySrc[p.src] == call.id then Calls.bySrc[p.src] = nil end
        if p.src then
            if wasConnected then voiceLeave(p.src) end
            TriggerClientEvent('veyl_phone:push', p.src, 'call', view(call, side))
        end
    end
    MySQL.update('UPDATE veyl_ph_calls SET ended_at = NOW(), end_reason = ? WHERE id = ?', { reason, call.id })
    if not wasConnected and (reason == 'timeout' or reason == 'cancelled') then missed(call) end
end

function Calls.EndFor(src, reason)
    local call = Calls.live[Calls.bySrc[src] or -1]
    if call then finish(call, reason or 'hangup') end
end

AddEventHandler('veyl_phone:sessionEnded', function(src) Calls.EndFor(src, 'dropped') end)
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, call in pairs(Calls.live) do
        if call.state == 'connected' then voiceLeave(call.caller.src) voiceLeave(call.callee.src) end
    end
end)

--- Logs a call that never rang (and leaves a missed-call notification when that makes sense).
local function failed(caller, number, calleeCid, reason, notifyCallee)
    local id = MySQL.insert.await('INSERT INTO veyl_ph_calls (caller, callee, ended_at, end_reason) VALUES (?, ?, NOW(), ?)', { caller.number, number, reason })
    if notifyCallee and calleeCid then
        missed({ id = id, caller = caller, callee = { cid = calleeCid, number = number } })
    end
end

---------------------------------------------------------------------------
-- Callbacks
---------------------------------------------------------------------------
--- callStart(number) -> call (state 'outgoing')
Veyl.RegisterCallback('callStart', function(src, citizenid, number)
    local s = Phone.Session(src)
    if not s then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    if not voiceName() then return Veyl.Err('VOICE_UNAVAILABLE', Calls.Availability().reason) end
    if s.settings.airplane then return Veyl.Err('UNAVAILABLE', 'Turn off airplane mode first') end
    if Calls.bySrc[src] then return Veyl.Err('BUSY', 'You are already in a call') end
    if not Phone.Rate(src, 'call', 3000) then return Veyl.Err('RATE_LIMITED', 'Wait a moment') end
    number = PhoneUtil.Normalize(number)
    if not number or number == s.number then return Veyl.Err('INVALID_INPUT', 'Enter a valid number') end
    local caller = { src = src, cid = citizenid, number = s.number }
    local calleeCid = Phone.CidByNumber(number)
    if not calleeCid then return Veyl.Err('NOT_FOUND', 'The number you dialled is not in service') end
    local target = Phone.SessionByNumber(number)
    -- Blocked, unreachable and Do-Not-Disturb all sound the same to the caller.
    if Contacts.IsBlocked(calleeCid, s.number) then
        failed(caller, number, calleeCid, 'unavailable', false)
        return Veyl.Err('UNAVAILABLE', 'The person you are calling is not available')
    end
    if not target or target.settings.airplane or target.settings.dnd then
        failed(caller, number, calleeCid, 'unavailable', true)
        return Veyl.Err('UNAVAILABLE', 'The person you are calling is not available')
    end
    if Calls.bySrc[target.src] then
        failed(caller, number, calleeCid, 'busy', true)
        return Veyl.Err('BUSY', 'The line is busy')
    end
    local id = MySQL.insert.await('INSERT INTO veyl_ph_calls (caller, callee) VALUES (?, ?)', { s.number, number })
    local call = { id = id, state = 'ringing', caller = caller, callee = { src = target.src, cid = target.cid, number = number }, startedAt = os.time() }
    Calls.live[id] = call
    Calls.bySrc[src], Calls.bySrc[target.src] = id, id
    Phone.Push(target.src, 'call', view(call, 'callee'))
    SetTimeout(C.RingSeconds * 1000, function()
        if Calls.live[id] and Calls.live[id].state == 'ringing' then finish(call, 'timeout') end
    end)
    return Veyl.Ok(view(call, 'caller'))
end)

--- callAnswer(id)
Veyl.RegisterCallback('callAnswer', function(src, _, id)
    local call = Calls.live[tonumber(id) or -1]
    if not call or call.callee.src ~= src then return Veyl.Err('NOT_FOUND', 'No incoming call') end
    if call.state ~= 'ringing' then return Veyl.Err('INVALID_STATE', 'The call is no longer ringing') end
    if not GetPlayerName(call.caller.src) then finish(call, 'dropped') return Veyl.Err('UNAVAILABLE', 'The caller hung up') end
    local channel = C.ChannelBase + call.id
    if not (voiceJoin(call.caller.src, channel) and voiceJoin(call.callee.src, channel)) then
        call.state = 'connected' -- so finish() leaves the channel on both sides
        finish(call, 'voice_failed')
        return Veyl.Err('VOICE_UNAVAILABLE', 'Could not connect the call')
    end
    call.state, call.answeredAt = 'connected', os.time()
    MySQL.update('UPDATE veyl_ph_calls SET answered_at = NOW() WHERE id = ?', { call.id })
    TriggerClientEvent('veyl_phone:push', call.caller.src, 'call', view(call, 'caller'))
    return Veyl.Ok(view(call, 'callee'))
end)

--- callDecline(id)
Veyl.RegisterCallback('callDecline', function(src, _, id)
    local call = Calls.live[tonumber(id) or -1]
    if not call or call.callee.src ~= src or call.state ~= 'ringing' then return Veyl.Err('NOT_FOUND', 'No incoming call') end
    finish(call, 'declined')
    return Veyl.Ok(nil)
end)

--- callEnd(id?): hang up (or cancel while it is still ringing).
Veyl.RegisterCallback('callEnd', function(src, _, id)
    local call = Calls.live[tonumber(id) or Calls.bySrc[src] or -1]
    if not call or not sideOf(call, src) then return Veyl.Err('NOT_FOUND', 'No active call') end
    local reason = call.state == 'connected' and 'hangup' or (sideOf(call, src) == 'caller' and 'cancelled' or 'declined')
    finish(call, reason)
    return Veyl.Ok(nil)
end)

--- recents() -> the last 50 calls: { id, direction 'in'|'out', number, display, missed, reason, time, duration }
Veyl.RegisterCallback('recents', function(src, citizenid)
    local s = Phone.Session(src)
    if not s then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    local rows = MySQL.query.await([[SELECT id, caller, callee, end_reason, UNIX_TIMESTAMP(started_at) AS t,
        UNIX_TIMESTAMP(answered_at) AS a, UNIX_TIMESTAMP(ended_at) AS e FROM veyl_ph_calls
        WHERE caller = ? OR callee = ? ORDER BY id DESC LIMIT 50]], { s.number, s.number }) or {}
    local names = {}
    for _, r in ipairs(MySQL.query.await('SELECT number, name FROM veyl_ph_contacts WHERE owner_cid = ?', { citizenid }) or {}) do names[r.number] = r.name end
    local out = {}
    for _, r in ipairs(rows) do
        local out_ = r.caller == s.number
        local other = out_ and r.callee or r.caller
        -- Calls from numbers you blocked are not listed.
        if out_ or not Contacts.IsBlocked(citizenid, other) then
            out[#out + 1] = {
                id = r.id, direction = out_ and 'out' or 'in', number = other, display = names[other] or PhoneUtil.Format(other),
                missed = not out_ and r.a == nil, reason = r.end_reason, time = r.t,
                duration = (r.a and r.e) and math.max(0, r.e - r.a) or 0,
            }
        end
    end
    return Veyl.Ok(out)
end)
