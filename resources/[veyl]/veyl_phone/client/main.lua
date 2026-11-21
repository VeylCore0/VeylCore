-- veyl_phone client: opening/closing, prop + animations, NUI bridge (whitelisted server calls), live pushes,
-- delivery acknowledgements and the developer app API. The server authorises everything.

local A = PhoneConfig.Animations
local screen = vlib.createScreen({ name = 'phone', keepInput = true, onClose = function() OnPhoneClosed() end })
local session = nil        -- data from the server's hello
local prop, animState = nil, nil
local externalApps = {}    -- [id] = { id, label, icon, color, event, resource }
local inCall = false

---------------------------------------------------------------------------
-- Prop & animation (upper body only; never in conflict with vehicles/weapons)
---------------------------------------------------------------------------
local function loadDict(dict)
    RequestAnimDict(dict)
    local deadline = GetGameTimer() + 2000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < deadline do Wait(10) end
    return HasAnimDictLoaded(dict)
end

local function attachProp(ped)
    if prop and DoesEntityExist(prop) then return end
    local hash = joaat(A.prop)
    RequestModel(hash)
    local deadline = GetGameTimer() + 2000
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(10) end
    if not HasModelLoaded(hash) then return end
    prop = CreateObject(hash, 0.0, 0.0, 0.0, true, true, false)
    AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, 28422), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(hash)
end

local function clearPhoneAnim()
    local ped = PlayerPedId()
    if animState then StopAnimTask(ped, animState.dict, animState.clip, 2.0) end
    animState = nil
    if prop and DoesEntityExist(prop) then DeleteEntity(prop) end
    prop = nil
end

--- kind: 'text' | 'call' | nil (nil = put the phone away)
local function playPhoneAnim(kind)
    local ped = PlayerPedId()
    if not kind then return clearPhoneAnim() end
    if IsEntityDead(ped) or IsPedRagdoll(ped) or (A.BlockWhenSwimming and IsPedSwimming(ped)) then return clearPhoneAnim() end
    local inCar = IsPedInAnyVehicle(ped, false)
    local a = inCar and (kind == 'call' and A.carCall or A.carText) or (kind == 'call' and A.call or A.text)
    if animState and animState.dict == a.dict and animState.clip == a.clip then return end
    if not loadDict(a.dict) then return end
    if animState then StopAnimTask(ped, animState.dict, animState.clip, 2.0) end
    TaskPlayAnim(ped, a.dict, a.clip, 3.0, 3.0, -1, 50, 0, false, false, false) -- 50 = loop + upper body + controllable
    animState = { dict = a.dict, clip = a.clip }
    attachProp(ped)
end

-- Keep the animation sane: re-apply after entering/leaving vehicles, drop it when dead or swimming.
CreateThread(function()
    while true do
        if animState then
            local ped = PlayerPedId()
            if IsEntityDead(ped) or IsPedRagdoll(ped) or (A.BlockWhenSwimming and IsPedSwimming(ped)) then
                clearPhoneAnim()
                if screen:isOpen() then screen:close('blocked') end
            elseif not IsEntityPlayingAnim(ped, animState.dict, animState.clip, 3) then
                local kind = inCall and 'call' or 'text'
                animState = nil
                playPhoneAnim(kind)
            end
            Wait(500)
        else
            Wait(1000)
        end
    end
end)

---------------------------------------------------------------------------
-- Open / close
---------------------------------------------------------------------------
local function worldState()
    local w = GlobalState.veylWorld
    return w and { hour = w.hour, minute = w.minute, weather = w.weather } or nil
end

local function bankState()
    local pd = Veyl.PlayerData
    return pd and pd.money and { bank = pd.money.bank } or nil
end

local function hello()
    local res = Veyl.Callback('veyl_phone', 'hello')
    if not res.ok then return nil, res end
    session = res.data
    return session
end

function OnPhoneClosed()
    SendNUIMessage({ action = 'phone:hidden' })
    if not inCall then clearPhoneAnim() else playPhoneAnim('call') end
end

local function openPhone(appId, route)
    if screen:isOpen() or not Veyl.IsLoaded() then return end
    local ped = PlayerPedId()
    if IsEntityDead(ped) then return end
    if A.BlockWhenAiming and IsPlayerFreeAiming(PlayerId()) then return end
    if A.BlockWhenSwimming and IsPedSwimming(ped) then return Veyl.Notify('Not while swimming', 'error') end
    local data, err = hello()
    if not data then return Veyl.NotifyResult(err) end
    data.external = {}
    for _, a in pairs(externalApps) do data.external[#data.external + 1] = { id = a.id, label = a.label, icon = a.icon, color = a.color } end
    data.world, data.money = worldState(), bankState()
    data.open = { app = appId, route = route }
    local ok, reason = screen:open('phone:open', data)
    if not ok then return Veyl.Notify(reason == 'busy' and 'Close the open menu first.' or 'Phone unavailable.', 'warning') end
    playPhoneAnim(inCall and 'call' or 'text')
end

vlib.addKeybind({
    name = 'veyl_phone', description = 'Open phone', defaultKey = PhoneConfig.OpenKey,
    onPressed = function()
        if screen:isOpen() then screen:close('key') else CreateThread(function() openPhone() end) end
    end,
})

RegisterNetEvent('veyl_phone:openApp', function(appId, route) CreateThread(function() openPhone(appId, route) end) end)

-- Start a (closed) phone session when the character loads, so messages are delivered and calls can ring.
local function startSession()
    if not Veyl.IsLoaded() then return end
    local data = hello()
    if data then SendNUIMessage({ action = 'phone:session', data = { settings = data.settings, number = data.number } }) end
end
RegisterNetEvent('VeylCore:Client:OnPlayerLoaded', function() SetTimeout(2000, function() CreateThread(startSession) end) end)
CreateThread(function() while not Veyl.IsLoaded() do Wait(1000) end Wait(2000) startSession() end)
RegisterNetEvent('VeylCore:Client:OnPlayerUnload', function()
    session = nil
    inCall = false
    clearPhoneAnim()
    SendNUIMessage({ action = 'phone:reset' })
end)

-- Keep the shell's clock, weather and balance current while open (cheap: once a second, only while open).
CreateThread(function()
    while true do
        if screen:isOpen() then
            screen:send('phone:tick', { world = worldState(), money = bankState() })
            Wait(1000)
        else
            Wait(1500)
        end
    end
end)

---------------------------------------------------------------------------
-- NUI bridge: only these server callbacks may be called from the page
---------------------------------------------------------------------------
local ALLOWED = {
    saveSettings = true, setProfile = true, contacts = true, contactSave = true, contactDelete = true, blocked = true, block = true,
    notifications = true, notificationsRead = true, notificationsClear = true, conversations = true, thread = true, send = true, read = true,
    groupCreate = true, groupRename = true, groupAdd = true, groupRemove = true, groupLeave = true, mute = true,
    callStart = true, callAnswer = true, callDecline = true, callEnd = true, callMute = true, recents = true,
}

RegisterNUICallback('api', function(data, cb)
    if type(data) ~= 'table' or not ALLOWED[data.name] then return cb({ ok = false, code = 'INVALID_INPUT' }) end
    local args = type(data.args) == 'table' and data.args or {}
    local res = Veyl.CallbackTimeout('veyl_phone', data.name, 15000, table.unpack(args, 1, 4))
    if data.name == 'callStart' and res.ok then inCall = true playPhoneAnim('call') end
    if data.name == 'callAnswer' and res.ok then inCall = true playPhoneAnim('call') end
    cb({ ok = res.ok, code = res.code, message = res.message, data = res.data })
end)

RegisterNUICallback('waypoint', function(data, cb)
    local x, y = tonumber(data and data.x), tonumber(data and data.y)
    if not x or not y then return cb({ ok = false }) end
    SetNewWaypoint(x, y)
    cb({ ok = true, message = 'Waypoint set' })
end)

--- Street/area name of the player's current position (label for "share location"; the coordinates come from the server).
RegisterNUICallback('locationLabel', function(_, cb)
    local c = GetEntityCoords(PlayerPedId())
    local street = GetStreetNameFromHashKey(GetStreetNameAtCoord(c.x, c.y, c.z))
    local area = GetLabelText(GetNameOfZone(c.x, c.y, c.z))
    cb({ ok = true, data = { label = (street ~= '' and (street .. ', ') or '') .. area } })
end)

RegisterNUICallback('openExternal', function(data, cb)
    local a = externalApps[data and data.id or '']
    cb({ ok = a ~= nil })
    if a then
        screen:close('external')
        SetTimeout(150, function() TriggerEvent(a.event) end)
    end
end)

---------------------------------------------------------------------------
-- Pushes from the server
---------------------------------------------------------------------------
RegisterNetEvent('veyl_phone:push', function(event, data)
    if event == 'message' then
        -- Delivered = this live phone session received it.
        CreateThread(function() Veyl.CallbackTimeout('veyl_phone', 'ack', 10000, { data.message.id }) end)
    elseif event == 'pending' then
        CreateThread(function() Veyl.CallbackTimeout('veyl_phone', 'ack', 15000, data.ids) end)
    elseif event == 'call' then
        if data.state == 'connected' then inCall = true playPhoneAnim('call')
        elseif data.state == 'ended' then
            inCall = false
            if screen:isOpen() then playPhoneAnim('text') else clearPhoneAnim() end
            -- Make sure a mute we applied for this call is lifted.
            if GetResourceState('pma-voice') == 'started' then
                for other in pairs(MutedBy or {}) do pcall(function() exports['pma-voice']:toggleMutePlayer(other) end) end
                MutedBy = {}
            end
        end
    end
    SendNUIMessage({ action = 'phone:push', data = { event = event, data = data } })
end)

MutedBy = {}
RegisterNetEvent('veyl_phone:muteFrom', function(otherSrc, on)
    if GetResourceState('pma-voice') ~= 'started' then return end
    local isMuted = MutedBy[otherSrc] == true
    if on ~= isMuted then
        pcall(function() exports['pma-voice']:toggleMutePlayer(otherSrc) end)
        MutedBy[otherSrc] = on or nil
    end
end)

---------------------------------------------------------------------------
-- Developer API (client exports)
---------------------------------------------------------------------------
--- exports.veyl_phone:RegisterApp({ id, label, icon?, color?, event }) — a home-screen shortcut owned by your resource.
--- Tapping it closes the phone and triggers `event` locally in the client. No remote/untrusted code is ever run.
exports('RegisterApp', function(def)
    if type(def) ~= 'table' or type(def.id) ~= 'string' or not def.id:match('^[%w_]+$') or type(def.event) ~= 'string' then return false end
    local owner = GetInvokingResource() or 'unknown'
    externalApps[def.id] = { id = def.id, label = tostring(def.label or def.id):sub(1, 16), icon = tostring(def.icon or 'box'):sub(1, 20),
        color = type(def.color) == 'string' and def.color:match('^#%x%x%x%x%x%x$') and def.color or '#3a3346', event = def.event, resource = owner }
    return true
end)
exports('IsOpen', function() return screen:isOpen() end)
exports('Open', function(appId, route) CreateThread(function() openPhone(appId, route) end) end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then clearPhoneAnim() return end
    for id, a in pairs(externalApps) do if a.resource == res then externalApps[id] = nil end end
end)
