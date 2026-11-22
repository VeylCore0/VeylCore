-- veyl_medical server: downed / unconscious state, revives, treatment, hospital respawn and check-in.
--
-- The core metadata is the source of truth (inlaststand = downed, isdead = unconscious), so a staff revive (/vrevive)
-- or a reconnect is picked up automatically. This file keeps only timers in memory and mirrors the state into the
-- replicated player state bag 'medical' ('down' | 'dead' | nil) so other clients can show the right target options.

local C = MedicalConfig
local states = {}  -- [src] = { state = 'down'|'dead', at = os.time(), respawnAt, lastCall, id }
local actions = {} -- [src] = { kind, target, token, at, seconds }
local seq = 0
local receptionPos = vector3(C.Hospital.reception.x, C.Hospital.reception.y, C.Hospital.reception.z)

local function core(name, ...) return Veyl.Await('veyl_core', name, 15000, ...) end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function isEMS(src)
    local pd = Veyl.GetPlayerData(src)
    if not pd or not pd.job.onduty then return false end
    for _, j in ipairs(C.EMSJobs) do if pd.job.name == j then return true end end
    return false
end

local function emsOnDuty()
    local list = {}
    for _, s in ipairs(GetPlayers()) do
        s = tonumber(s)
        if isEMS(s) then list[#list + 1] = s end
    end
    return list
end

local writing = {} -- [src] = true while this file updates the metadata itself (ignored by the change handler)

local function setFlags(src, down, dead)
    writing[src] = true
    exports.veyl_core:SetMetadataMany(src, { inlaststand = down, isdead = dead })
    writing[src] = nil
end

local function publish(src, st)
    states[src] = st
    Player(src).state:set('medical', st and st.state or nil, true)
end

local function enter(src, state)
    seq = seq + 1
    local st = { state = state, at = os.time(), id = seq, lastCall = states[src] and states[src].lastCall or 0 }
    if state == 'dead' then st.respawnAt = st.at + (#emsOnDuty() > 0 and C.RespawnSeconds or C.RespawnSecondsNoEMS) end
    publish(src, st)
    setFlags(src, state == 'down', state == 'dead')
    return st
end

--- What the client needs to show its timers.
local function snapshot(st)
    if not st then return { state = nil } end
    local now = os.time()
    return {
        state = st.state,
        bleedOutIn = st.state == 'down' and math.max(0, st.at + C.BleedOutSeconds - now) or nil,
        respawnIn = st.state == 'dead' and math.max(0, st.respawnAt - now) or nil,
        fee = C.RespawnFee,
    }
end

local function clear(src, health)
    if not states[src] then return end
    publish(src, nil)
    setFlags(src, false, false)
    TriggerClientEvent('veyl_medical:revived', src, health or 200)
end

local function near(a, b, dist)
    local pa, pb = Veyl.GetPlayerCoords(a), Veyl.GetPlayerCoords(b)
    return pa ~= nil and pb ~= nil and #(pa - pb) <= (dist or C.ActionDistance) + 1.0
end

local function alertEMS(src, street)
    local pc = Veyl.GetPlayerCoords(src)
    if not pc then return 0 end
    local list = emsOnDuty()
    for _, s in ipairs(list) do
        if s ~= src then
            TriggerClientEvent('veyl_medical:alert', s, { x = pc.x, y = pc.y, z = pc.z, street = type(street) == 'string' and street:sub(1, 64) or nil,
                seconds = C.AlertBlipSeconds })
        end
    end
    return #list
end

Veyl.Startup({ 'veyl_core' }, function()
    -- Resource restart: rebuild from metadata (timers restart from now).
    for _, s in ipairs(GetPlayers()) do
        s = tonumber(s)
        local pd = Veyl.GetPlayerData(s)
        if pd and (pd.metadata.isdead or pd.metadata.inlaststand) then
            local st = enter(s, pd.metadata.isdead and 'dead' or 'down')
            TriggerClientEvent('veyl_medical:restore', s, snapshot(st))
        end
    end
    return true
end)

---------------------------------------------------------------------------
-- Going down / bleeding out / respawning (reported by the player's own client)
---------------------------------------------------------------------------
Veyl.RegisterCallback('reportDown', function(src, _, street)
    local st = states[src]
    if not st then
        st = enter(src, 'down')
        st.lastCall = os.time()
        local n = alertEMS(src, street)
        local snap = snapshot(st)
        snap.emsAlerted = n
        return Veyl.Ok(snap)
    end
    -- Killed again while downed (e.g. a second fall): unconscious straight away.
    if st.state == 'down' then st = enter(src, 'dead') end
    return Veyl.Ok(snapshot(st))
end, { cooldown = 500 })

Veyl.RegisterCallback('bleedOut', function(src)
    local st = states[src]
    if not st or st.state ~= 'down' then return Veyl.Ok(snapshot(st)) end
    if os.time() < st.at + C.BleedOutSeconds - 2 then return Veyl.Err('TOO_FAST', 'Still conscious', snapshot(st)) end
    return Veyl.Ok(snapshot(enter(src, 'dead')))
end, { cooldown = 1000 })

Veyl.RegisterCallback('state', function(src) return Veyl.Ok(snapshot(states[src])) end, { cooldown = 500 })

Veyl.RegisterCallback('callHelp', function(src, _, street)
    local st = states[src]
    if not st or st.state ~= 'down' then return Veyl.Err('INVALID_STATE', 'You can only call for help while downed') end
    local wait = st.lastCall + C.CallCooldownSeconds - os.time()
    if wait > 0 then return Veyl.Err('RATE_LIMITED', ('You can call again in %ds'):format(wait)) end
    st.lastCall = os.time()
    local n = alertEMS(src, street)
    return Veyl.Ok({ emsAlerted = n }, n > 0 and 'EMS have been alerted' or 'No EMS are on duty right now')
end, { cooldown = 1000 })

Veyl.RegisterCallback('respawn', function(src, citizenid)
    local st = states[src]
    if not st or st.state ~= 'dead' then return Veyl.Err('INVALID_STATE', 'You are not unconscious') end
    if os.time() < st.respawnAt - 1 then return Veyl.Err('TOO_FAST', 'Not yet', snapshot(st)) end
    local fee, paidWith = math.floor(C.RespawnFee or 0), nil
    if fee > 0 then
        local op = ('medical:respawn:%s:%d'):format(citizenid, st.id)
        for _, m in ipairs({ 'bank', 'cash' }) do
            local r = core('DebitOnce', citizenid, m, fee, 'Pillbox Hill Medical Center: treatment', op)
            if r.ok or r.code == 'DUPLICATE_OPERATION' then paidWith = m break end
        end
    end
    publish(src, nil)
    setFlags(src, false, false)
    TriggerEvent('veyl:playerRespawned', src, citizenid) -- veyl_needs restores hunger/thirst minimums
    Veyl.Audit(src, 'medical_respawn', { fee = paidWith and fee or 0, method = paidWith })
    local h = C.Hospital.respawn
    local msg = paidWith and ('You were treated at %s. The bill was %s.'):format(C.Hospital.label, ('$' .. fee))
        or ('You were treated at %s. The bill was waived.'):format(C.Hospital.label)
    return Veyl.Ok({ x = h.x, y = h.y, z = h.z, heading = h.w, health = C.HealthAfterRespawn }, msg)
end, { cooldown = 2000 })

---------------------------------------------------------------------------
-- Revive / help up / treat (timed: start returns a token, finish checks the time and repeats every check)
---------------------------------------------------------------------------
local function check(src, kind, target)
    if states[src] then return Veyl.Err('INVALID_STATE', 'You are hurt yourself') end
    if not target or target == src or not Veyl.GetCitizenId(target) then return Veyl.Err('NOT_FOUND', 'Nobody there') end
    if not near(src, target) then return Veyl.Err('TOO_FAR', 'Move closer') end
    local st = states[target]
    local ems = isEMS(src)
    if kind == 'revive' then
        if not st then return Veyl.Err('INVALID_STATE', 'They do not need reviving') end
        if not ems then return Veyl.Err('NO_PERMISSION', 'Only on-duty EMS can revive') end
        return nil, C.ReviveSeconds
    elseif kind == 'helpup' then
        if not C.CiviliansCanHelpUp then return Veyl.Err('NO_PERMISSION', 'Only EMS can help them') end
        if not st then return Veyl.Err('INVALID_STATE', 'They do not need help') end
        if st.state ~= 'down' then return Veyl.Err('INVALID_STATE', 'They are unconscious and need EMS') end
        if (exports.veyl_inventory:GetItemCount(src, C.FirstAidItem) or 0) < 1 then return Veyl.Err('NO_ITEM', 'You need a first aid kit') end
        return nil, C.HelpUpSeconds
    elseif kind == 'treat' then
        if not ems then return Veyl.Err('NO_PERMISSION', 'Only on-duty EMS can treat injuries') end
        if st then return Veyl.Err('INVALID_STATE', 'Revive them first') end
        local ped = GetPlayerPed(target)
        if ped ~= 0 and GetEntityHealth(ped) >= 200 then return Veyl.Err('INVALID_STATE', 'They are not hurt') end
        return nil, C.TreatSeconds
    end
    return Veyl.Err('INVALID_INPUT', 'Unknown action')
end

Veyl.RegisterCallback('actionStart', function(src, _, kind, target)
    target = tonumber(target)
    local err, seconds = check(src, kind, target)
    if err then return err end
    local token = Veyl.NewId()
    actions[src] = { kind = kind, target = target, token = token, at = GetGameTimer(), seconds = seconds }
    if kind ~= 'treat' then TriggerClientEvent('veyl_medical:beingHelped', target, seconds) end
    return Veyl.Ok({ token = token, seconds = seconds })
end, { cooldown = 1000 })

Veyl.RegisterCallback('actionFinish', function(src, citizenid, token)
    local a = actions[src]
    actions[src] = nil
    if not a or a.token ~= token then return Veyl.Err('INVALID_STATE', 'Start again') end
    if GetGameTimer() - a.at < a.seconds * 1000 - 600 then return Veyl.Err('TOO_FAST', 'You stopped too early') end
    local err = check(src, a.kind, a.target)
    if err then return err end
    local tcid = Veyl.GetCitizenId(a.target)
    if a.kind == 'helpup' then
        local ok = exports.veyl_inventory:RemoveItem(src, C.FirstAidItem, 1)
        if not ok then return Veyl.Err('NO_ITEM', 'You need a first aid kit') end
        clear(a.target, C.HealthAfterHelpUp)
    elseif a.kind == 'revive' then
        clear(a.target, 200)
    else
        TriggerClientEvent('veyl_medical:heal', a.target, 200)
    end
    Veyl.Notify(a.target, a.kind == 'treat' and 'Your injuries were treated.' or 'You were helped back on your feet.', 'success')
    Veyl.Audit(src, 'medical_' .. a.kind, { target = tcid })
    return Veyl.Ok(nil, a.kind == 'treat' and 'Treated' or 'They are back on their feet')
end, { cooldown = 500 })

Veyl.RegisterCallback('actionCancel', function(src)
    local a = actions[src]
    actions[src] = nil
    if a and a.kind ~= 'treat' then TriggerClientEvent('veyl_medical:beingHelped', a.target, 0) end
    return Veyl.Ok()
end, { cooldown = 200 })

---------------------------------------------------------------------------
-- Hospital check-in (staff treat you when EMS are not around)
---------------------------------------------------------------------------
local checkins = {} -- [src] = { token, at }

local function checkInAllowed(src)
    if states[src] then return Veyl.Err('INVALID_STATE', 'You need EMS') end
    local pc = Veyl.GetPlayerCoords(src)
    if not pc or #(pc - receptionPos) > 4.0 then return Veyl.Err('TOO_FAR', 'Stand at the reception desk') end
    if #emsOnDuty() >= C.CheckInMaxEMS then return Veyl.Err('UNAVAILABLE', 'EMS are on duty. Ask them for treatment.') end
    local ped = GetPlayerPed(src)
    if ped ~= 0 and GetEntityHealth(ped) >= 200 then return Veyl.Err('INVALID_STATE', 'You are not hurt') end
    return nil
end

Veyl.RegisterCallback('checkInStart', function(src)
    local err = checkInAllowed(src)
    if err then return err end
    local token = Veyl.NewId()
    checkins[src] = { token = token, at = GetGameTimer() }
    return Veyl.Ok({ token = token, seconds = C.CheckInSeconds, fee = C.CheckInFee })
end, { cooldown = 1000 })

Veyl.RegisterCallback('checkInFinish', function(src, citizenid, token, method)
    local c = checkins[src]
    checkins[src] = nil
    if not c or c.token ~= token then return Veyl.Err('INVALID_STATE', 'Start again') end
    if GetGameTimer() - c.at < C.CheckInSeconds * 1000 - 600 then return Veyl.Err('TOO_FAST', 'You left too early') end
    local err = checkInAllowed(src)
    if err then return err end
    local fee = math.floor(C.CheckInFee or 0)
    if fee > 0 then
        method = method == 'cash' and 'cash' or 'bank'
        local r = core('DebitOnce', citizenid, method, fee, C.Hospital.label .. ': check-in', 'medical:checkin:' .. token)
        if not r.ok and r.code ~= 'DUPLICATE_OPERATION' then
            return Veyl.Err(r.code or 'INSUFFICIENT_FUNDS', r.code == 'INSUFFICIENT_FUNDS' and ('You cannot pay the $%d fee'):format(fee) or (r.message or 'Payment failed'))
        end
    end
    TriggerClientEvent('veyl_medical:heal', src, 200)
    Veyl.Audit(src, 'medical_checkin', { fee = fee, method = method })
    return Veyl.Ok(nil, 'You were treated by hospital staff')
end, { cooldown = 1000 })

---------------------------------------------------------------------------
-- Keeping in sync with the core
---------------------------------------------------------------------------
-- A staff revive (/vrevive) or any resource clearing the flags ends the state here too.
AddEventHandler('VeylCore:Server:OnMetadataChange', function(src, key, value)
    if writing[src] then return end
    if (key == 'isdead' or key == 'inlaststand') and value == false and states[src] then
        local pd = Veyl.GetPlayerData(src)
        if pd and not pd.metadata.isdead and not pd.metadata.inlaststand then
            publish(src, nil)
            TriggerClientEvent('veyl_medical:revived', src, 200)
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    states[src], actions[src], checkins[src] = nil, nil, nil
end)

AddEventHandler('VeylCore:Server:OnPlayerUnload', function(src) states[src], actions[src], checkins[src] = nil, nil, nil end)

exports('IsDown', function(src) return states[tonumber(src)] ~= nil end)
exports('GetState', function(src) local st = states[tonumber(src)] return st and st.state or nil end)
exports('Revive', function(src, health) clear(tonumber(src), health) return true end)
