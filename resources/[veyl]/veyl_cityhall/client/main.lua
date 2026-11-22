-- veyl_cityhall client: the desk clerk, the City Hall screen and cards shown by nearby players.

local C = CityHallConfig
local releaseDeskPhoto -- set below; frees the City Hall screen's photo when it closes
local screen = vlib.createScreen({ name = 'cityhall', onClose = function() if releaseDeskPhoto then releaseDeskPhoto() end end })

local function reply(cb, res) cb({ ok = res.ok, code = res.code, message = res.message, data = res.data }) end

---------------------------------------------------------------------------
-- Photos: a live headshot of a ped, shown in the page as https://nui-img/<txd>/<txd>
---------------------------------------------------------------------------
local photos = {} -- [key] = headshot handle

local function takePhoto(key, ped)
    if photos[key] then UnregisterPedheadshot(photos[key]) photos[key] = nil end
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    local h = RegisterPedheadshot(ped)
    local t = GetGameTimer() + 3000
    while not (IsPedheadshotReady(h) and IsPedheadshotValid(h)) and GetGameTimer() < t do Wait(25) end
    if not (IsPedheadshotReady(h) and IsPedheadshotValid(h)) then UnregisterPedheadshot(h) return nil end
    photos[key] = h
    local txd = GetPedheadshotTxdString(h)
    return ('https://nui-img/%s/%s'):format(txd, txd)
end

local function dropPhoto(key)
    if photos[key] then UnregisterPedheadshot(photos[key]) photos[key] = nil end
end
releaseDeskPhoto = function() dropPhoto('desk') end

local function open()
    if screen:isOpen() or not Veyl.IsLoaded() then return end
    local res = Veyl.Callback('veyl_cityhall', 'overview')
    if not res.ok then return Veyl.NotifyResult(res) end
    res.data.person.photo = takePhoto('desk', PlayerPedId())
    local ok, reason = screen:open('cityhall:open', res.data)
    if not ok then Veyl.Notify(reason == 'busy' and 'Close the open menu first.' or 'City Hall is unavailable right now.', 'warning') end
end
AddEventHandler('veyl_cityhall:open', function() CreateThread(open) end)

local ALLOWED = { overview = true, buy = true, takeJob = true }
RegisterNUICallback('api', function(data, cb)
    if not screen:isOpen() or type(data) ~= 'table' or not ALLOWED[data.name] then return cb({ ok = false, code = 'INVALID_INPUT' }) end
    local args = type(data.args) == 'table' and data.args or {}
    CreateThread(function() reply(cb, Veyl.CallbackTimeout('veyl_cityhall', data.name, 20000, table.unpack(args, 1, 2))) end)
end)

RegisterNUICallback('waypoint', function(data, cb)
    cb({ ok = true })
    CreateThread(function()
        local res = Veyl.Callback('veyl_cityhall', 'jobLocation', data and data.job)
        if not res.ok then return Veyl.NotifyResult(res) end
        SetNewWaypoint(res.data.x, res.data.y)
        Veyl.Notify(('GPS set: %s'):format(res.data.label or 'job location'), 'success')
    end)
end)

---------------------------------------------------------------------------
-- Cards shown by someone nearby (passive: never takes focus)
---------------------------------------------------------------------------
local shownSeq = 0
RegisterNetEvent('veyl_cityhall:showCard', function(card, seconds)
    if type(card) ~= 'table' then return end
    shownSeq = shownSeq + 1
    local mine = shownSeq
    CreateThread(function()
        if card.photoOf then
            local pid = not card.self and GetPlayerFromServerId(card.photoOf) or nil
            local ped = card.self and PlayerPedId() or (pid and pid ~= -1 and GetPlayerPed(pid)) or nil
            card.photo = takePhoto('card', ped)
        end
        card.photoOf = nil
        if mine ~= shownSeq then return end
        screen:send('cityhall:card', card)
        SetTimeout((tonumber(seconds) or 8) * 1000, function()
            if mine == shownSeq then
                screen:send('cityhall:card', nil)
                Wait(500) -- let the card fade before its photo is released
                if mine == shownSeq then dropPhoto('card') end
            end
        end)
    end)
end)

RegisterNetEvent('veyl_cityhall:shown', function(count)
    if count == 0 then Veyl.Notify('Nobody is close enough to see it.', 'info')
    else Veyl.Notify(('You showed it to %d %s.'):format(count, count == 1 and 'person' or 'people'), 'success') end
    local ped = PlayerPedId()
    if not IsPedInAnyVehicle(ped, false) then
        local dict = 'paper_1_rcm_alt1-9'
        RequestAnimDict(dict)
        local t = GetGameTimer() + 1000
        while not HasAnimDictLoaded(dict) and GetGameTimer() < t do Wait(10) end
        if HasAnimDictLoaded(dict) then TaskPlayAnim(ped, dict, 'player_one_dual-9', 8.0, -8.0, 2500, 49, 0, false, false, false) end
    end
end)

---------------------------------------------------------------------------
-- Desk clerk and blip
---------------------------------------------------------------------------
CreateThread(function()
    while GetResourceState('veyl_interact') ~= 'started' do Wait(250) end
    local d = C.Desk
    exports.veyl_interact:AddPed({
        id = 'veyl_cityhall_desk', model = d.model, coords = d.coords, scenario = d.scenario, radius = C.UseDistance,
        title = 'City Hall', options = { { label = 'City services', icon = 'card', event = 'veyl_cityhall:open' } },
    })
    if d.blip then
        local blip = AddBlipForCoord(d.coords.x, d.coords.y, d.coords.z)
        SetBlipSprite(blip, d.blip.sprite)
        SetBlipColour(blip, d.blip.colour)
        SetBlipScale(blip, d.blip.scale or 0.75)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(d.blip.name)
        EndTextCommandSetBlipName(blip)
    end
end)
