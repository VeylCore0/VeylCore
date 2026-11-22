-- veyl_dispatch client: call cards and blips, the dispatch panel, responding, panic, unit blips.

local C = DispatchConfig
local screen = vlib.createScreen({ name = 'dispatch', keepInput = true })
local state = nil          -- last sync from the server (nil = not on duty for a service)
local callBlips = {}       -- [callId] = { blip, radius }
local unitBlips = {}       -- [serverId] = blip
local newest = nil

local function onDutyUnit()
    local job = (Veyl.PlayerData or {}).job
    if not job or not job.onduty then return false end
    for _, s in pairs(C.Services) do for _, j in ipairs(s.jobs) do if j == job.name then return true end end end
    return false
end

---------------------------------------------------------------------------
-- Call blips
---------------------------------------------------------------------------
local function removeCallBlip(id)
    local b = callBlips[id]
    if not b then return end
    if DoesBlipExist(b.blip) then RemoveBlip(b.blip) end
    if b.radius and DoesBlipExist(b.radius) then RemoveBlip(b.radius) end
    callBlips[id] = nil
end

local function addCallBlip(call, seconds)
    removeCallBlip(call.id)
    local bl = call.blip or {}
    local blip = AddBlipForCoord(call.x, call.y, call.z)
    SetBlipSprite(blip, bl.sprite or (call.panic and 161 or 526))
    SetBlipColour(blip, bl.colour or (call.priority == 1 and 1 or call.priority == 2 and 47 or 5))
    SetBlipScale(blip, bl.scale or 1.0)
    SetBlipFlashes(blip, call.priority == 1)
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(('#%d %s'):format(call.id, call.title))
    EndTextCommandSetBlipName(blip)
    local radius = AddBlipForRadius(call.x, call.y, call.z, 60.0)
    SetBlipColour(radius, bl.colour or 1)
    SetBlipAlpha(radius, 70)
    callBlips[call.id] = { blip = blip, radius = radius }
    local id = call.id
    SetTimeout((seconds or C.BlipSeconds) * 1000, function() removeCallBlip(id) end)
end

---------------------------------------------------------------------------
-- Incoming calls and sync
---------------------------------------------------------------------------
RegisterNetEvent('veyl_dispatch:call', function(call, popupSeconds, blipSeconds)
    if type(call) ~= 'table' then return end
    newest = call.id
    addCallBlip(call, blipSeconds)
    local me = GetEntityCoords(PlayerPedId())
    call.distance = math.floor(#(me - vector3(call.x, call.y, call.z)))
    screen:send('dispatch:alert', { call = call, seconds = popupSeconds, respondKey = C.RespondKey })
    if call.panic then
        PlaySoundFrontend(-1, 'TIMER_STOP', 'HUD_MINI_GAME_SOUNDSET', true)
        Wait(180)
        PlaySoundFrontend(-1, 'TIMER_STOP', 'HUD_MINI_GAME_SOUNDSET', true)
    else
        PlaySoundFrontend(-1, call.priority == 1 and 'Lose_1st' or 'Event_Message_Purple', call.priority == 1 and 'GTAO_FM_Events_Soundset' or 'GTAO_FM_Events_Soundset', true)
    end
end)

RegisterNetEvent('veyl_dispatch:sync', function(st)
    state = st
    if not st then
        for id in pairs(callBlips) do removeCallBlip(id) end
        for id, b in pairs(unitBlips) do if DoesBlipExist(b) then RemoveBlip(b) end unitBlips[id] = nil end
        if screen:isOpen() then screen:close('off_duty') end
        return
    end
    if screen:isOpen() then screen:send('dispatch:state', st) end
end)

---------------------------------------------------------------------------
-- Unit blips
---------------------------------------------------------------------------
RegisterNetEvent('veyl_dispatch:units', function(list)
    if type(list) ~= 'table' or not onDutyUnit() then return end
    local seen, me = {}, GetPlayerServerId(PlayerId())
    for _, u in ipairs(list) do
        if u.id ~= me then
            seen[u.id] = true
            local b = unitBlips[u.id]
            if not b or not DoesBlipExist(b) then
                b = AddBlipForCoord(u.x, u.y, u.z)
                SetBlipSprite(b, 1)
                SetBlipScale(b, 0.8)
                SetBlipCategory(b, 7)
                ShowHeadingIndicatorOnBlip(b, true)
                unitBlips[u.id] = b
            else
                SetBlipCoords(b, u.x, u.y, u.z)
            end
            local sv = C.Services[u.service]
            SetBlipColour(b, sv and sv.blip.colour or 0)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(u.name)
            EndTextCommandSetBlipName(b)
        end
    end
    for id, b in pairs(unitBlips) do
        if not seen[id] then if DoesBlipExist(b) then RemoveBlip(b) end unitBlips[id] = nil end
    end
end)

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
local function respond(id)
    local res = Veyl.Callback('veyl_dispatch', 'respond', id)
    if not res.ok then return Veyl.NotifyResult(res) end
    SetNewWaypoint(res.data.x, res.data.y)
    Veyl.Notify(res.message, 'success')
end

local function openPanel()
    if screen:isOpen() then return screen:close('toggle') end
    if not onDutyUnit() then return Veyl.Notify('You need to be on duty as police or EMS', 'error') end
    local res = Veyl.Callback('veyl_dispatch', 'state')
    if not res.ok then return Veyl.NotifyResult(res) end
    state = res.data
    local ok, reason = screen:open('dispatch:open', state)
    if not ok and reason == 'busy' then Veyl.Notify('Close the open menu first.', 'warning') end
end

local function panic()
    if not onDutyUnit() then return Veyl.Notify('The panic button is for on-duty police and EMS', 'error') end
    Veyl.NotifyResult(Veyl.Callback('veyl_dispatch', 'panic'))
end

vlib.addKeybind({ name = 'veyl_dispatch_menu', description = 'Dispatch panel (police / EMS)', defaultKey = C.MenuKey, onPressed = function() CreateThread(openPanel) end })
vlib.addKeybind({ name = 'veyl_dispatch_respond', description = 'Respond to the newest call', defaultKey = C.RespondKey, onPressed = function()
    if onDutyUnit() and newest and not screen:isOpen() then CreateThread(function() respond(newest) end) end
end })
vlib.addKeybind({ name = 'veyl_dispatch_panic', description = 'Panic button (police / EMS)', defaultKey = C.PanicKey, onPressed = function() CreateThread(panic) end })
RegisterCommand('dispatch', function() CreateThread(openPanel) end, false)
RegisterCommand('panic', function() CreateThread(panic) end, false)

RegisterNUICallback('respond', function(data, cb)
    cb({ ok = true })
    CreateThread(function() respond(tonumber(data and data.id)) end)
end)
RegisterNUICallback('waypoint', function(data, cb)
    cb({ ok = true })
    if type(data) == 'table' and tonumber(data.x) and tonumber(data.y) then SetNewWaypoint(data.x + 0.0, data.y + 0.0) end
end)
RegisterNUICallback('status', function(data, cb)
    local res = Veyl.Callback('veyl_dispatch', 'setStatus', type(data) == 'table' and data.status or nil)
    if res.ok then state = res.data end
    cb({ ok = res.ok, message = res.message, data = res.data })
end)

---------------------------------------------------------------------------
-- Street name for panic and public calls (the server has no street data)
---------------------------------------------------------------------------
CreateThread(function()
    local last
    while true do
        Wait(4000)
        if Veyl.IsLoaded() then
            local c = GetEntityCoords(PlayerPedId())
            local s1, s2 = GetStreetNameAtCoord(c.x, c.y, c.z)
            local a, b = GetStreetNameFromHashKey(s1), s2 ~= 0 and GetStreetNameFromHashKey(s2) or ''
            local street = b ~= '' and ('%s / %s'):format(a, b) or a
            if street ~= last then last = street TriggerServerEvent('veyl_dispatch:street', street) end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(callBlips) do removeCallBlip(id) end
    for _, b in pairs(unitBlips) do if DoesBlipExist(b) then RemoveBlip(b) end end
end)
