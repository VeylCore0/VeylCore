-- veyl_phone client: open/close, prop + animation, the NUI bridge (whitelisted server calls), live pushes and the
-- app API for other resources. The server authorises everything; this file never decides what a player may do.
-- Every NUI message and callback is listed in docs/PHONE.md.

local A = PhoneConfig.Animations
local screen = vlib.createScreen({ name = 'phone', keepInput = PhoneConfig.WalkWhileOpen, onClose = function(reason) OnPhoneClosed(reason) end })
local session = nil          -- last `hello` data
local prop, animState = nil, nil
local externalApps = {}      -- [id] = { id, label, icon, color, event, resource }
local inCall = false

---------------------------------------------------------------------------
-- Prop & animation (upper body only, so walking and driving keep working)
---------------------------------------------------------------------------
local function loadDict(dict)
    RequestAnimDict(dict)
    local deadline = GetGameTimer() + 2000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < deadline do Wait(10) end
    return HasAnimDictLoaded(dict)
end

local function attachProp(ped)
    if prop and DoesEntityExist(prop) then return end
    local case = LocalPlayer.state.phoneCase
    local hash = joaat(case and ('sd_phone_%s'):format(case) or A.prop)
    if not IsModelInCdimage(hash) then hash = joaat(A.fallbackProp) end
    RequestModel(hash)
    local deadline = GetGameTimer() + 2000
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(10) end
    if not HasModelLoaded(hash) then return end
    prop = CreateObject(hash, 0.0, 0.0, 0.0, true, true, false)
    AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, 28422), 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(hash)
end

local function clearAnim()
    if animState then StopAnimTask(PlayerPedId(), animState.dict, animState.clip, 2.0) end
    animState = nil
    if prop and DoesEntityExist(prop) then DeleteEntity(prop) end
    prop = nil
end

--- kind: 'text' | 'call' | nil (nil puts the phone away)
local function playAnim(kind)
    local ped = PlayerPedId()
    if not kind then return clearAnim() end
    if IsEntityDead(ped) or IsPedRagdoll(ped) or (A.BlockWhenSwimming and IsPedSwimming(ped)) then return clearAnim() end
    local inCar = IsPedInAnyVehicle(ped, false)
    local a = inCar and (kind == 'call' and A.carCall or A.carText) or (kind == 'call' and A.call or A.text)
    if animState and animState.dict == a.dict and animState.clip == a.clip then return end
    if not loadDict(a.dict) then return end
    if animState then StopAnimTask(ped, animState.dict, animState.clip, 2.0) end
    TaskPlayAnim(ped, a.dict, a.clip, 3.0, 3.0, -1, 50, 0, false, false, false) -- 50 = loop, upper body, controllable
    animState = { dict = a.dict, clip = a.clip }
    attachProp(ped)
end

local function refreshAnim()
    if inCall then playAnim('call') elseif screen:isOpen() then playAnim('text') else clearAnim() end
end

-- Re-apply after entering/leaving vehicles; drop it when dead, ragdolled or swimming.
CreateThread(function()
    while true do
        if animState then
            local ped = PlayerPedId()
            if IsEntityDead(ped) or IsPedRagdoll(ped) or (A.BlockWhenSwimming and IsPedSwimming(ped)) then
                clearAnim()
                if screen:isOpen() then screen:close('blocked') end
            elseif not IsEntityPlayingAnim(ped, animState.dict, animState.clip, 3) then
                animState = nil
                refreshAnim()
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
    return { hour = w and w.hour or GetClockHours(), minute = w and w.minute or GetClockMinutes(), weather = w and w.weather or nil }
end

local function externalList()
    local out = {}
    for _, a in pairs(externalApps) do out[#out + 1] = { id = a.id, label = a.label, icon = a.icon, color = a.color } end
    table.sort(out, function(x, y) return x.label < y.label end)
    return out
end

local function hello()
    local res = Veyl.Callback('veyl_phone', 'hello')
    if not res.ok then return nil, res end
    session = res.data
    inCall = session.call ~= nil and session.call.state == 'connected'
    return session
end

function OnPhoneClosed()
    refreshAnim()
    -- Putting the phone away locks it again when a PIN is set (the server decides, after its grace period).
    CreateThread(function() Veyl.CallbackTimeout('veyl_phone', 'lock', 5000) end)
end

--- Opens the phone, optionally straight into an app (`appId`) and a route inside it (`route`, app-defined string).
local function openPhone(appId, route)
    if screen:isOpen() then
        if appId then screen:send('phone:navigate', { app = appId, route = route }) end
        return
    end
    if not Veyl.IsLoaded() then return end
    local ped = PlayerPedId()
    if IsEntityDead(ped) or LocalPlayer.state.cuffed or LocalPlayer.state.handcuffed then return end
    if A.BlockWhenAiming and IsPlayerFreeAiming(PlayerId()) then return end
    if A.BlockWhenSwimming and IsPedSwimming(ped) then return Veyl.Notify('Not while swimming', 'error') end
    local data, err = hello()
    if not data then return Veyl.NotifyResult(err) end
    data.external = externalList()
    data.world = worldState()
    data.open = { app = appId, route = route }
    local ok, reason = screen:open('phone:open', data)
    if not ok then return Veyl.Notify(reason == 'busy' and 'Close the open menu first.' or 'The phone is unavailable.', 'warning') end
    refreshAnim()
end

vlib.addKeybind({
    name = 'veyl_phone', description = 'Open phone', defaultKey = PhoneConfig.OpenKey,
    onPressed = function()
        if screen:isOpen() then screen:close('key') else CreateThread(function() openPhone() end) end
    end,
})

-- Other resources (client or server) can open a specific app: TriggerEvent / TriggerClientEvent('veyl_phone:openApp', app, route)
RegisterNetEvent('veyl_phone:openApp', function(appId, route) CreateThread(function() openPhone(appId, route) end) end)

-- A closed phone still has a session once the character is loaded, so it rings and receives messages.
local function startSession()
    if not Veyl.IsLoaded() then return end
    local data = hello()
    if data then
        data.external = externalList()
        SendNUIMessage({ action = 'phone:session', data = data })
    end
end
RegisterNetEvent('VeylCore:Client:OnPlayerLoaded', function() SetTimeout(2000, function() CreateThread(startSession) end) end)
CreateThread(function() while not Veyl.IsLoaded() do Wait(1000) end Wait(2000) startSession() end)

RegisterNetEvent('VeylCore:Client:OnPlayerUnload', function()
    session, inCall = nil, false
    clearAnim()
    SendNUIMessage({ action = 'phone:reset' })
end)

RegisterNetEvent('veyl_phone:sessionEnded', function(reason)
    session, inCall = nil, false
    if screen:isOpen() then screen:close('session_ended') end
    clearAnim()
    SendNUIMessage({ action = 'phone:reset', data = { reason = reason } })
    if reason == 'no_device' then Veyl.Notify('You no longer have a phone.', 'info') end
end)

-- Picking up a phone starts the session right away; losing it closes the phone at once (the server ends the session
-- on its own check, and `hello` refuses without the item, so this is only for responsiveness).
local starting = false
AddEventHandler('veyl_inventory:client:counts', function(counts)
    local item = PhoneConfig.RequireItem
    if not item or type(counts) ~= 'table' then return end
    local has = (counts[item] or 0) > 0
    if has and not session and not starting and Veyl.IsLoaded() then
        starting = true
        CreateThread(function() startSession() starting = false end)
    elseif not has and screen:isOpen() then
        screen:close('no_device')
    end
end)

-- Clock and weather for the status bar, once a second while the phone is open.
CreateThread(function()
    while true do
        if screen:isOpen() then
            screen:send('phone:tick', { world = worldState() })
            Wait(1000)
        else
            Wait(1500)
        end
    end
end)

---------------------------------------------------------------------------
-- NUI bridge: the page may only call these server callbacks
---------------------------------------------------------------------------
local ALLOWED = {
    hello = true, settingsSave = true, profileSave = true, appInstall = true, homeSave = true,
    notifications = true, notificationsRead = true, notificationsClear = true,
    contacts = true, contactSave = true, contactDelete = true, blocks = true, block = true,
    conversations = true, thread = true, send = true, read = true, leave = true, mute = true,
    groupCreate = true, groupRename = true, groupAdd = true, groupRemove = true,
    callStart = true, callAnswer = true, callDecline = true, callEnd = true, recents = true,
    mailList = true, mailRead = true, mailDelete = true,
    nearby = true, shareNumber = true, shareAnswer = true,
    notes = true, noteSave = true, noteDelete = true,
    bankOverview = true, bankHistory = true, bankResolve = true, bankSend = true, bankStatus = true,
    garageList = true, garageLocate = true, garageValet = true,
    marketList = true, marketPost = true, marketDelete = true,
    flockMe = true, flockSetup = true, flockSignup = true, flockLogin = true, flockLogout = true, flockClaim = true, flockFeed = true, flockThread = true, flockUser = true, flockPost = true, flockLike = true, flockDelete = true, flockFollow = true,
    mapsData = true, placeSave = true, placeDelete = true, shareLocation = true,
    servicesData = true, serviceRequest = true, serviceTake = true, serviceClose = true,
    voicemailList = true, voicemailAudio = true, messagePhoto = true, messagePhotoSave = true, voicemailLeave = true, voicemailRead = true, voicemailDelete = true,
    photoSave = true, photoList = true, photoGet = true, photoDelete = true,
    jobsData = true, jobsDuty = true, jobsPrimary = true, jobsApply = true, jobsAppClose = true,
    billsData = true, billPay = true, standingCreate = true, standingCancel = true,
    speakerPlay = true, speakerStop = true, newsList = true, newsPost = true,
    raceData = true, raceBoard = true, raceTrackSave = true, raceHost = true, raceJoin = true, raceStart = true,
    unlock = true, accountCheck = true, accountCreate = true, passwordChange = true, pinSet = true, pinRemove = true, pinReset = true, setupFinish = true,
}

--- api { name, args: [] } -> { ok, code?, message?, data? }
RegisterNUICallback('api', function(data, cb)
    if type(data) ~= 'table' or not ALLOWED[data.name] then return cb({ ok = false, code = 'INVALID_INPUT', message = 'Unknown request' }) end
    local args = type(data.args) == 'table' and data.args or {}
    local res = Veyl.CallbackTimeout('veyl_phone', data.name, 15000, table.unpack(args, 1, 4))
    if res.ok and (data.name == 'callAnswer') then inCall = true refreshAnim() end
    cb({ ok = res.ok, code = res.code, message = res.message, data = res.data })
end)

--- waypoint { x, y }
RegisterNUICallback('waypoint', function(data, cb)
    local x, y = tonumber(data and data.x), tonumber(data and data.y)
    if not x or not y then return cb({ ok = false }) end
    SetNewWaypoint(x + 0.0, y + 0.0)
    cb({ ok = true, message = 'Waypoint set' })
end)

--- location -> { label } (street and area where the player stands, for "share location")
RegisterNUICallback('location', function(_, cb)
    local c = GetEntityCoords(PlayerPedId())
    local street = GetStreetNameFromHashKey(GetStreetNameAtCoord(c.x, c.y, c.z))
    local area = GetLabelText(GetNameOfZone(c.x, c.y, c.z))
    cb({ ok = true, data = { label = (street ~= '' and (street .. ', ') or '') .. area } })
end)

--- openExternal { id }: tapping an app registered by another resource. The phone closes and that resource takes over.
RegisterNUICallback('openExternal', function(data, cb)
    local a = externalApps[data and data.id or '']
    cb({ ok = a ~= nil })
    if a then
        screen:close('external')
        SetTimeout(150, function() TriggerEvent(a.event) end)
    end
end)

---------------------------------------------------------------------------
-- Pushes from the server (forwarded to the page as { action = 'phone:push', data = { event, data } })
---------------------------------------------------------------------------
RegisterNetEvent('veyl_phone:push', function(event, data)
    if event == 'call' and type(data) == 'table' then
        inCall = data.state == 'connected'
        refreshAnim()
        -- An incoming call while the phone is closed: say so in-game too (the page also shows its own ring UI).
        if data.state == 'incoming' and not screen:isOpen() then
            Veyl.Notify(('Incoming call from %s. Press %s to answer.'):format(data.peer and data.peer.display or 'unknown', PhoneConfig.OpenKey), 'info', 6000)
        end
    end
    SendNUIMessage({ action = 'phone:push', data = { event = event, data = data } })
end)

---------------------------------------------------------------------------
-- API for other resources (client exports)
---------------------------------------------------------------------------
--- exports.veyl_phone:RegisterApp({ id, label, icon?, color?, event }) -> boolean
--- A home-screen app owned by your resource: tapping it closes the phone and triggers `event` on this client.
--- Removed automatically when your resource stops.
exports('RegisterApp', function(def)
    if type(def) ~= 'table' or type(def.id) ~= 'string' or not def.id:match('^[%w_]+$') or #def.id > 32 or type(def.event) ~= 'string' then return false end
    externalApps[def.id] = {
        id = def.id, label = tostring(def.label or def.id):sub(1, 16), icon = tostring(def.icon or 'box'):sub(1, 24),
        color = type(def.color) == 'string' and def.color:match('^#%x%x%x%x%x%x$') and def.color or '#3a3346',
        event = def.event, resource = GetInvokingResource() or GetCurrentResourceName(),
    }
    SendNUIMessage({ action = 'phone:apps', data = { external = externalList() } })
    return true
end)

exports('UnregisterApp', function(id)
    if externalApps[id] then externalApps[id] = nil SendNUIMessage({ action = 'phone:apps', data = { external = externalList() } }) end
end)

exports('IsOpen', function() return screen:isOpen() end)
exports('IsInCall', function() return inCall end)
exports('Open', function(appId, route) CreateThread(function() openPhone(appId, route) end) end)
exports('Close', function() if screen:isOpen() then screen:close('external') end end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then clearAnim() return end
    local changed = false
    for id, a in pairs(externalApps) do if a.resource == res then externalApps[id] = nil changed = true end end
    if changed then SendNUIMessage({ action = 'phone:apps', data = { external = externalList() } }) end
end)
