-- veyl_medical client: going down, the downed / unconscious loop, revive and treat options on other players,
-- the hospital reception and EMS alerts. The server decides every state change; this file shows it.

local C = MedicalConfig
local state = nil          -- nil | 'down' | 'dead'
local bleedOutAt, respawnAt = 0, 0
local reporting = false
local helpedUntil, helpedTotal = 0, 0
local fee = C.RespawnFee
-- Shown on the death screen
local bleedTotal, respawnTotal = C.BleedOutSeconds * 1000, C.RespawnSeconds * 1000
local emsOnDuty, emsAlerted, callReadyAt = 0, 0, 0
local respawning = false

local ANIMS = {
    down = { dict = 'combat@damage@writhe', clip = 'writhe_loop' },
    dead = { dict = 'dead', clip = 'dead_a' },
    car = { dict = 'veh@low@front_ps@idle_duck', clip = 'sit' },
}

local function loadDict(dict)
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    local t = GetGameTimer() + 2000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < t do Wait(10) end
    return HasAnimDictLoaded(dict)
end

local function streetHere()
    local c = GetEntityCoords(PlayerPedId())
    local s1, s2 = GetStreetNameAtCoord(c.x, c.y, c.z)
    local a, b = GetStreetNameFromHashKey(s1), s2 ~= 0 and GetStreetNameFromHashKey(s2) or nil
    return b and b ~= '' and ('%s / %s'):format(a, b) or a
end

local function applySnapshot(s)
    state = s and s.state or nil
    local now = GetGameTimer()
    if s and s.bleedOutIn then bleedOutAt = now + s.bleedOutIn * 1000 end
    if s and s.respawnIn then respawnAt = now + s.respawnIn * 1000 end
    if s and s.fee then fee = s.fee end
    if s and s.bleedTotal then bleedTotal = s.bleedTotal * 1000 end
    if s and s.respawnTotal then respawnTotal = s.respawnTotal * 1000 end
    if s and s.ems then emsOnDuty = s.ems end
    if s and s.emsAlerted then emsAlerted = s.emsAlerted end
    if s and s.callCooldown then callReadyAt = now + s.callCooldown * 1000 end
end

--- Brings the ped back to life where it lies (keeps the vehicle seat) so it can play the downed animation.
local function resurrect()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    local seat
    if veh ~= 0 then
        for i = -1, GetVehicleMaxNumberOfPassengers(veh) - 1 do
            if GetPedInVehicleSeat(veh, i) == ped then seat = i break end
        end
    end
    local c, h = GetEntityCoords(ped), GetEntityHeading(ped)
    NetworkResurrectLocalPlayer(c.x, c.y, c.z, h, true, false)
    ped = PlayerPedId()
    SetEntityHealth(ped, 101)
    SetEntityInvincible(ped, true)
    SetPedCanRagdoll(ped, false)
    ClearPedTasksImmediately(ped)
    if veh ~= 0 and DoesEntityExist(veh) and seat then SetPedIntoVehicle(ped, veh, seat) end
end

local function standUp(health)
    local ped = PlayerPedId()
    state = nil
    SetEntityInvincible(ped, false)
    SetPedCanRagdoll(ped, true)
    if IsEntityDead(ped) then
        local c = GetEntityCoords(ped)
        NetworkResurrectLocalPlayer(c.x, c.y, c.z, GetEntityHeading(ped), true, false)
        ped = PlayerPedId()
    end
    if not IsPedInAnyVehicle(ped, false) then ClearPedTasks(ped) end
    SetEntityHealth(ped, math.min(GetEntityMaxHealth(ped), tonumber(health) or 200))
    ClearPedBloodDamage(ped)
end

---------------------------------------------------------------------------
-- Going down
---------------------------------------------------------------------------
local function onDeath()
    reporting = true
    local ped = PlayerPedId()
    -- Let the body settle (ragdoll, falling) before playing the downed animation.
    local t = GetGameTimer() + 4000
    while GetEntitySpeed(ped) > 0.4 and GetGameTimer() < t do Wait(100) end
    local res
    for _ = 1, 10 do
        res = Veyl.CallbackTimeout('veyl_medical', 'reportDown', 8000, streetHere())
        if res.ok then break end
        Wait(1000)
    end
    reporting = false
    if not res or not res.ok then return end
    applySnapshot(res.data)
    resurrect()
end

CreateThread(function()
    while true do
        local sleep = 300
        if Veyl.IsLoaded() and not reporting then
            local ped = PlayerPedId()
            if IsEntityDead(ped) then
                if state == 'dead' then resurrect() -- already unconscious: just lie back down
                else CreateThread(onDeath) sleep = 1000 end
            end
        end
        Wait(sleep)
    end
end)

---------------------------------------------------------------------------
-- Death screen (passive NUI: never takes focus) and screen effect
---------------------------------------------------------------------------
local function pushScreen()
    local now = GetGameTimer()
    if not state then
        SendNUIMessage({ action = 'medical:state', data = { visible = false } })
        return
    end
    SendNUIMessage({ action = 'medical:state', data = {
        visible = true, state = state,
        remainingMs = math.max(0, (state == 'down' and bleedOutAt or respawnAt) - now),
        totalMs = state == 'down' and bleedTotal or respawnTotal,
        callMs = math.max(0, callReadyAt - now),
        helpedMs = math.max(0, helpedUntil - now), helpedTotalMs = helpedTotal,
        ems = emsOnDuty, alerted = emsAlerted, fee = fee, respawning = respawning,
        firstAid = C.CiviliansCanHelpUp, hospital = C.Hospital.label,
    } })
end

CreateThread(function()
    local fx = nil
    while true do
        pushScreen()
        -- Unconscious: the world drains to grey. Downed: the page's red vignette does the work.
        local want = state == 'dead' and 'DeathFailMPIn' or nil
        if want ~= fx then
            if fx then AnimpostfxStop(fx) end
            if want then AnimpostfxPlay(want, 0, true) end
            fx = want
        end
        Wait(state and 500 or 1000)
    end
end)

-- Voice: downed players whisper, unconscious players cannot be heard (pma-voice; restored when the state ends).
CreateThread(function()
    local applied = nil
    while true do
        Wait(500)
        if GetResourceState('pma-voice') == 'started' and applied ~= state then
            local range = state == 'down' and C.VoiceRangeDowned or state == 'dead' and C.VoiceRangeUnconscious or nil
            local ok = pcall(function()
                if range then exports['pma-voice']:overrideProximityRange(range + 0.0, true)
                elseif applied then exports['pma-voice']:clearProximityOverride() end
            end)
            if ok then applied = state end
        end
    end
end)

-- While downed / unconscious: animation, blocked controls, help text, timers.
local transitioning = false
CreateThread(function()
    while true do
        if not state then
            Wait(250)
        else
            local ped = PlayerPedId()
            local now = GetGameTimer()
            local inCar = IsPedInAnyVehicle(ped, false)
            local a = inCar and ANIMS.car or ANIMS[state]
            if not IsEntityDead(ped) and not IsEntityPlayingAnim(ped, a.dict, a.clip, 3) and loadDict(a.dict) then
                TaskPlayAnim(ped, a.dict, a.clip, 2.0, 2.0, -1, 1, 0, false, false, false)
            end
            DisableAllControlActions(0)
            for _, k in ipairs({ 1, 2, 245, 249, 199, 200, 46, 47, 38 }) do EnableControlAction(0, k, true) end -- look, chat, push-to-talk, pause, G, E
            if now < helpedUntil then
                -- shown on the death screen
            elseif state == 'down' then
                if now >= bleedOutAt and not transitioning then
                    transitioning = true
                    CreateThread(function()
                        local r = Veyl.Callback('veyl_medical', 'bleedOut')
                        if type(r.data) == 'table' then applySnapshot(r.data) else Wait(1000) end
                        transitioning = false
                    end)
                end
                if IsControlJustPressed(0, 47) and now >= callReadyAt then
                    callReadyAt = now + C.CallCooldownSeconds * 1000
                    CreateThread(function()
                        local r = Veyl.Callback('veyl_medical', 'callHelp', streetHere())
                        if r.ok and r.data then
                            emsAlerted = r.data.emsAlerted or 0
                            emsOnDuty = math.max(emsOnDuty, emsAlerted)
                        end
                        Veyl.NotifyResult(r)
                        pushScreen()
                    end)
                end
            elseif state == 'dead' then
                if now >= respawnAt then
                    if IsControlJustPressed(0, 38) and not transitioning then
                        transitioning = true
                        respawning = true
                        pushScreen()
                        CreateThread(function()
                            local r = Veyl.CallbackTimeout('veyl_medical', 'respawn', 15000)
                            if not r.ok then
                                Veyl.NotifyResult(r)
                                if r.data then applySnapshot(r.data) end
                                transitioning = false
                                respawning = false
                                return
                            end
                            DoScreenFadeOut(500)
                            Wait(550)
                            local p = r.data
                            standUp(p.health)
                            local me = PlayerPedId()
                            if IsPedInAnyVehicle(me, false) then TaskLeaveVehicle(me, GetVehiclePedIsIn(me, false), 16) Wait(300) end
                            RequestCollisionAtCoord(p.x, p.y, p.z)
                            SetEntityCoordsNoOffset(me, p.x, p.y, p.z, false, false, false)
                            SetEntityHeading(me, p.heading or 0.0)
                            local t = GetGameTimer() + 5000
                            while not HasCollisionLoadedAroundEntity(me) and GetGameTimer() < t do Wait(25) end
                            DoScreenFadeIn(600)
                            Veyl.Notify(r.message, 'info', 7000)
                            transitioning = false
                            respawning = false
                        end)
                    end
                end
            end
            Wait(0)
        end
    end
end)

RegisterNetEvent('veyl_medical:revived', function(health) standUp(health) end)
RegisterNetEvent('veyl_medical:restore', function(snap)
    applySnapshot(snap)
    if state then resurrect() end
end)
RegisterNetEvent('veyl_medical:heal', function(health)
    local ped = PlayerPedId()
    if state or IsEntityDead(ped) then return end
    SetEntityHealth(ped, math.min(GetEntityMaxHealth(ped), tonumber(health) or 200))
    ClearPedBloodDamage(ped)
end)
RegisterNetEvent('veyl_medical:beingHelped', function(seconds)
    seconds = tonumber(seconds) or 0
    helpedUntil = seconds > 0 and GetGameTimer() + seconds * 1000 + 1000 or 0
    helpedTotal = seconds > 0 and seconds * 1000 + 1000 or 0
    pushScreen()
end)
RegisterNetEvent('VeylCore:Client:OnPlayerUnload', function()
    if state then standUp(200) end
    state = nil
end)
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    AnimpostfxStop('DeathFailMPIn')
    if not state then return end
    local ped = PlayerPedId()
    SetEntityInvincible(ped, false)
    SetPedCanRagdoll(ped, true)
    if GetResourceState('pma-voice') == 'started' then pcall(function() exports['pma-voice']:clearProximityOverride() end) end
end)

-- Resource restart while this client was mid-state: ask the server.
CreateThread(function()
    while not Veyl.IsLoaded() do Wait(500) end
    local r = Veyl.Callback('veyl_medical', 'state')
    if r.ok and r.data and r.data.state and not state then
        applySnapshot(r.data)
        resurrect()
    end
end)

---------------------------------------------------------------------------
-- Helping others (targets on players)
---------------------------------------------------------------------------
local function serverIdOf(entity)
    local idx = NetworkGetPlayerIndexFromPed(entity)
    return idx ~= -1 and GetPlayerServerId(idx) or nil
end

local function medicalOf(entity)
    local id = serverIdOf(entity)
    return id and Player(id).state.medical or nil
end

local function isEMS()
    local job = (Veyl.PlayerData or {}).job
    if not job or not job.onduty then return false end
    for _, j in ipairs(C.EMSJobs) do if job.name == j then return true end end
    return false
end

local ACTION_LABEL = { revive = 'Reviving', helpup = 'Helping them up', treat = 'Treating injuries' }
local ACTION_ANIM = {
    revive = { dict = 'mini@cpr@char_a@cpr_str', clip = 'cpr_pumpchest', flag = 1 },
    helpup = { dict = 'amb@medic@standing@tendtodead@idle_a', clip = 'idle_a', flag = 1 },
    treat = { dict = 'amb@medic@standing@tendtodead@idle_a', clip = 'idle_a', flag = 1 },
}

local function act(kind, entity)
    if state then return end
    local id = serverIdOf(entity)
    if not id then return end
    CreateThread(function()
        local start = Veyl.CallbackTimeout('veyl_medical', 'actionStart', 10000, kind, id)
        if not start.ok then return Veyl.NotifyResult(start) end
        local done = vlib.progress({ label = ACTION_LABEL[kind], duration = start.data.seconds * 1000, canCancel = true,
            disable = { move = true, car = true, combat = true }, anim = ACTION_ANIM[kind] })
        ClearPedTasks(PlayerPedId())
        if not done then
            Veyl.Callback('veyl_medical', 'actionCancel')
            return Veyl.Notify('Stopped', 'info')
        end
        Veyl.NotifyResult(Veyl.CallbackTimeout('veyl_medical', 'actionFinish', 10000, start.data.token))
    end)
end

CreateThread(function()
    while GetResourceState('veyl_target') ~= 'started' do Wait(250) end
    exports.veyl_target:addGlobalPlayer({
        { name = 'veyl_medical_revive', label = 'Revive', icon = 'heart', distance = C.ActionDistance, priority = 5,
          canInteract = function(entity) return not state and isEMS() and medicalOf(entity) ~= nil end,
          onSelect = function(data) act('revive', data.entity) end },
        { name = 'veyl_medical_helpup', label = 'Help up (first aid kit)', icon = 'heart', distance = C.ActionDistance, priority = 4,
          canInteract = function(entity) return not state and C.CiviliansCanHelpUp and not isEMS() and medicalOf(entity) == 'down' end,
          onSelect = function(data) act('helpup', data.entity) end },
        { name = 'veyl_medical_treat', label = 'Treat injuries', icon = 'heart', distance = C.ActionDistance, priority = 3,
          canInteract = function(entity) return not state and isEMS() and medicalOf(entity) == nil and GetEntityHealth(entity) < GetEntityMaxHealth(entity) end,
          onSelect = function(data) act('treat', data.entity) end },
    })
end)

---------------------------------------------------------------------------
-- Hospital reception and blip
---------------------------------------------------------------------------
AddEventHandler('veyl_medical:checkIn', function()
    if state then return end
    CreateThread(function()
        local start = Veyl.CallbackTimeout('veyl_medical', 'checkInStart', 10000)
        if not start.ok then return Veyl.NotifyResult(start) end
        local method = 'bank'
        if start.data.fee > 0 then
            local choice = Veyl.UI.Menu({ title = 'Check in', subtitle = ('Treatment costs $%d'):format(start.data.fee), items = {
                { label = 'Pay by card', value = 'bank' }, { label = 'Pay in cash', value = 'cash' } } })
            if not choice then return end
            method = choice
        end
        local done = vlib.progress({ label = 'Being treated', duration = start.data.seconds * 1000, canCancel = true,
            disable = { move = true, car = true, combat = true }, anim = { dict = 'missheistdockssetup1clipboard@idle_a', clip = 'idle_a', flag = 49 } })
        ClearPedTasks(PlayerPedId())
        if not done then return Veyl.Notify('You left before treatment finished. Nothing was charged.', 'info') end
        Veyl.NotifyResult(Veyl.CallbackTimeout('veyl_medical', 'checkInFinish', 15000, start.data.token, method))
    end)
end)

CreateThread(function()
    while GetResourceState('veyl_interact') ~= 'started' do Wait(250) end
    local h = C.Hospital
    exports.veyl_interact:AddPed({
        id = 'veyl_medical_reception', model = h.receptionPed, coords = h.reception, radius = 2.5, scenario = 'WORLD_HUMAN_CLIPBOARD',
        title = h.label, options = { { label = ('Check in ($%d)'):format(C.CheckInFee), icon = 'heart', event = 'veyl_medical:checkIn' } },
    })
    if h.blip then
        local blip = AddBlipForCoord(h.reception.x, h.reception.y, h.reception.z)
        SetBlipSprite(blip, h.blip.sprite)
        SetBlipColour(blip, h.blip.colour)
        SetBlipScale(blip, h.blip.scale or 0.8)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(h.label)
        EndTextCommandSetBlipName(blip)
    end
end)

---------------------------------------------------------------------------
-- EMS alerts
---------------------------------------------------------------------------
RegisterNetEvent('veyl_medical:alert', function(a)
    if type(a) ~= 'table' then return end
    local blip = AddBlipForCoord(a.x, a.y, a.z)
    SetBlipSprite(blip, 153)
    SetBlipColour(blip, 1)
    SetBlipScale(blip, 1.0)
    SetBlipFlashes(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Person down')
    EndTextCommandSetBlipName(blip)
    PlaySoundFrontend(-1, 'Lose_1st', 'GTAO_FM_Events_Soundset', true)
    Veyl.Notify(('Person down%s. Marked on your map.'):format(a.street and (' near ' .. a.street) or ''), 'warning', 8000)
    SetTimeout((tonumber(a.seconds) or 90) * 1000, function() if DoesBlipExist(blip) then RemoveBlip(blip) end end)
end)

exports('IsDown', function() return state ~= nil end)
exports('GetState', function() return state end)
