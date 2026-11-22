-- veyl_emotes client: playing and stopping emotes, props, favourites, the emote menu and shared emote requests.

local C = EmotesConfig
local screen = vlib.createScreen({ name = 'emotes', keepInput = true })
local current = nil   -- { id, emote, props = { entity }, token }
local playSeq = 0

---------------------------------------------------------------------------
-- Favourites (per character, stored on this computer)
---------------------------------------------------------------------------
local function favKey()
    local cid = Veyl.PlayerData and Veyl.PlayerData.citizenid
    return cid and ('fav:%s'):format(cid) or nil
end

local function loadFavs()
    local key = favKey()
    local raw = key and GetResourceKvpString(key)
    local ok, list = pcall(json.decode, raw or '[]')
    local out = {}
    for _, id in ipairs(ok and type(list) == 'table' and list or {}) do if EmoteById[id] then out[#out + 1] = id end end
    return out
end

local function saveFavs(list)
    local key = favKey()
    if key then SetResourceKvp(key, json.encode(list)) end
end

---------------------------------------------------------------------------
-- Playing
---------------------------------------------------------------------------
local function loadDict(dict)
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    local t = GetGameTimer() + 3000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < t do Wait(10) end
    return HasAnimDictLoaded(dict)
end

local function loadModel(model)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local t = GetGameTimer() + 3000
    while not HasModelLoaded(hash) and GetGameTimer() < t do Wait(10) end
    return HasModelLoaded(hash) and hash or nil
end

local function removeProps(c)
    for _, e in ipairs(c and c.props or {}) do
        if DoesEntityExist(e) then DetachEntity(e, true, false) DeleteEntity(e) end
    end
    if c then c.props = {} end
end

local function whyBlocked()
    local ped = PlayerPedId()
    if not Veyl.IsLoaded() then return 'Not loaded yet' end
    if IsEntityDead(ped) or LocalPlayer.state.medical then return 'Not while you are hurt' end
    if IsPedInAnyVehicle(ped, true) then return 'Not in a vehicle' end
    if IsPedSwimming(ped) or IsPedFalling(ped) or IsPedRagdoll(ped) or IsPedClimbing(ped) then return 'Not right now' end
    if Veyl.PlayerData and Veyl.PlayerData.metadata and Veyl.PlayerData.metadata.ishandcuffed then return 'Not while restrained' end
    return nil
end

--- Stops the current emote. instant = true snaps out (no exit animation).
local function stop(instant)
    if not current then return end
    local c = current
    current = nil
    removeProps(c)
    local ped = PlayerPedId()
    if instant then ClearPedTasksImmediately(ped) else ClearPedTasks(ped) end -- scenarios play their exit animation
end

local function play(e, clipOverride)
    local why = whyBlocked()
    if why then Veyl.Notify(why, 'error') return false end
    stop(true)
    local ped = PlayerPedId()
    playSeq = playSeq + 1
    local c = { id = e.id, emote = e, props = {}, seq = playSeq, started = GetGameTimer() }
    if e.scenario then
        ClearPedTasks(ped)
        TaskStartScenarioInPlace(ped, e.scenario, 0, true)
    else
        local a = e.anim
        if not loadDict(a.dict) then Veyl.Notify('That emote could not be loaded', 'error') return false end
        local flag = a.loop and (a.upper and 49 or 1) or (a.upper and 48 or 0)
        TaskPlayAnim(ped, a.dict, clipOverride or a.clip, 3.0, 3.0, a.loop and -1 or (a.ms or -1), flag, 0, false, false, false)
    end
    if e.prop then
        local hash = loadModel(e.prop.model)
        if hash then
            local pc = GetEntityCoords(ped)
            local obj = CreateObject(hash, pc.x, pc.y, pc.z + 0.2, true, true, true)
            local p, r = e.prop.pos, e.prop.rot
            AttachEntityToEntity(obj, ped, GetPedBoneIndex(ped, e.prop.bone), p[1], p[2], p[3], r[1], r[2], r[3], true, true, false, true, 1, true)
            SetModelAsNoLongerNeeded(hash)
            c.props[#c.props + 1] = obj
        end
    end
    current = c
    -- One-shot animations end by themselves; tidy up afterwards.
    if not e.scenario and not e.anim.loop then
        SetTimeout((e.anim.ms or 3000) + 200, function()
            if current and current.seq == c.seq then removeProps(current) current = nil end
        end)
    end
    return true
end

-- Ends the emote if something interrupts it (ragdoll, getting in a car, going down, the animation stopping).
CreateThread(function()
    while true do
        Wait(400)
        if current and GetGameTimer() - current.started > 1500 then
            local ped = PlayerPedId()
            local e = current.emote
            local interrupted = IsPedRagdoll(ped) or IsPedInAnyVehicle(ped, true) or IsEntityDead(ped) or LocalPlayer.state.medical
            if not interrupted and e.anim and e.anim.loop and not IsEntityPlayingAnim(ped, e.anim.dict, e.anim.clip, 3) then interrupted = true end
            if not interrupted and e.scenario and not IsPedUsingAnyScenario(ped) then interrupted = true end
            if interrupted then removeProps(current) current = nil end
        end
    end
end)

---------------------------------------------------------------------------
-- Shared emotes
---------------------------------------------------------------------------
local function closestPlayer()
    local me = PlayerPedId()
    local pc = GetEntityCoords(me)
    local best, bestD = nil, C.SharedDistance
    for _, pid in ipairs(GetActivePlayers()) do
        if pid ~= PlayerId() then
            local ped = GetPlayerPed(pid)
            local d = #(GetEntityCoords(ped) - pc)
            if d <= bestD then best, bestD = GetPlayerServerId(pid), d end
        end
    end
    return best
end

local function requestShared(e)
    local why = whyBlocked()
    if why then return Veyl.Notify(why, 'error') end
    local target = closestPlayer()
    if not target then return Veyl.Notify('Stand next to someone first', 'error') end
    Veyl.NotifyResult(Veyl.Callback('veyl_emotes', 'sharedRequest', e.id, target))
end

RegisterNetEvent('veyl_emotes:request', function(token, info)
    if type(info) ~= 'table' then return end
    CreateThread(function()
        local yes = Veyl.UI.Confirm({ title = info.label, message = ('Person #%d wants to %s with you.'):format(info.from or 0, (info.label or ''):lower()),
            confirmLabel = 'Accept', cancelLabel = 'Decline' })
        local res = Veyl.Callback('veyl_emotes', 'sharedAnswer', token, yes == true)
        if not res.ok then Veyl.NotifyResult(res) end
    end)
end)

RegisterNetEvent('veyl_emotes:playShared', function(id, role, spot)
    local e = EmoteById[id]
    if not e or not e.partner then return end
    local ped = PlayerPedId()
    if role == 'b' and type(spot) == 'table' then
        SetEntityCoordsNoOffset(ped, spot.x, spot.y, spot.z, false, false, false)
        SetEntityHeading(ped, spot.heading)
    end
    play(e, role == 'b' and e.partner.clip or nil)
end)

---------------------------------------------------------------------------
-- Entry points: menu, /e, cancel key
---------------------------------------------------------------------------
local function run(id)
    local e = EmoteById[id]
    if not e then return Veyl.Notify(('No emote called "%s". Open the menu with /%s.'):format(tostring(id), C.Command), 'error') end
    if e.partner then return requestShared(e) end
    play(e)
end

local CATEGORIES = {
    { id = 'gestures', label = 'Gestures' }, { id = 'dances', label = 'Dances' }, { id = 'actions', label = 'Actions' },
    { id = 'poses', label = 'Poses' }, { id = 'props', label = 'Props' }, { id = 'shared', label = 'Shared' },
}

local function openMenu()
    if screen:isOpen() then return screen:close('toggle') end
    if not Veyl.IsLoaded() then return end
    local list = {}
    for i, e in ipairs(EmoteList) do
        list[i] = { id = e.id, label = e.label, cat = e.cat, prop = e.prop ~= nil, shared = e.partner ~= nil, loop = e.scenario ~= nil or (e.anim and e.anim.loop) == true }
    end
    local ok, reason = screen:open('emotes:open', {
        emotes = list, categories = CATEGORIES, favourites = loadFavs(), current = current and current.id or nil,
        command = C.Command, maxFavourites = C.MaxFavourites,
    })
    if not ok and reason == 'busy' then Veyl.Notify('Close the open menu first.', 'warning') end
end

RegisterNUICallback('play', function(data, cb)
    cb({ ok = true })
    local id = type(data) == 'table' and data.id
    if type(id) == 'string' then CreateThread(function()
        run(id)
        screen:send('emotes:current', { current = current and current.id or nil })
    end) end
end)

RegisterNUICallback('stop', function(_, cb)
    cb({ ok = true })
    stop(false)
    screen:send('emotes:current', { current = nil })
end)

RegisterNUICallback('favourite', function(data, cb)
    local id, on = type(data) == 'table' and data.id, type(data) == 'table' and data.on == true
    if type(id) ~= 'string' or not EmoteById[id] then return cb({ ok = false }) end
    local list, out = loadFavs(), {}
    for _, f in ipairs(list) do if f ~= id then out[#out + 1] = f end end
    if on then
        if #out >= C.MaxFavourites then return cb({ ok = false, message = ('You can keep up to %d favourites'):format(C.MaxFavourites) }) end
        out[#out + 1] = id
    end
    saveFavs(out)
    cb({ ok = true, data = out })
end)

RegisterCommand(C.Command, function(_, args)
    if not args[1] then return openMenu() end
    CreateThread(function() run(args[1]:lower()) end)
end, false)
RegisterCommand('emotes', function() openMenu() end, false)
RegisterCommand('emotecancel', function() stop(false) end, false)

vlib.addKeybind({ name = 'veyl_emotes_menu', description = 'Open emote menu', defaultKey = C.MenuKey, onPressed = function() openMenu() end })
vlib.addKeybind({ name = 'veyl_emotes_cancel', description = 'Stop emote', defaultKey = C.CancelKey, onPressed = function()
    if current and not screen:isOpen() then stop(false) end
end })

RegisterNetEvent('VeylCore:Client:OnPlayerUnload', function() stop(true) end)
AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and current then removeProps(current) ClearPedTasks(PlayerPedId()) end
end)

exports('Play', function(id) local e = EmoteById[id] return e ~= nil and not e.partner and play(e) end)
exports('Stop', function() stop(false) end)
exports('IsPlaying', function() return current ~= nil end)
