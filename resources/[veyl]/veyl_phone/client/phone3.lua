-- Phone 2.0, phase 2 (client): camera capture, valet road spot, speaker volume by distance, race runner, tablet menu.

local C = PhoneConfig

---------------------------------------------------------------------------
-- Camera: screenshot-basic captures the game view (no NUI) as a small JPEG data URL
---------------------------------------------------------------------------
RegisterNUICallback('cameraShot', function(_, cb)
    if GetResourceState('screenshot-basic') ~= 'started' then
        return cb({ ok = false, code = 'UNAVAILABLE', message = 'The server needs the screenshot-basic resource for photos' })
    end
    local done = false
    exports['screenshot-basic']:requestScreenshot({ encoding = 'jpg', quality = C.Camera.Quality }, function(data)
        if done then return end
        done = true
        cb({ ok = type(data) == 'string', data = { image = data } })
    end)
    SetTimeout(8000, function() if not done then done = true cb({ ok = false, message = 'Camera timed out' }) end end)
end)

---------------------------------------------------------------------------
-- Valet: the nearest drivable road node next to the player
---------------------------------------------------------------------------
RegisterNUICallback('valetSpot', function(_, cb)
    local c = GetEntityCoords(PlayerPedId())
    local found, pos, heading = GetClosestVehicleNodeWithHeading(c.x, c.y, c.z, 1, 3.0, 0)
    if not found or #(pos - c) > 60.0 then return cb({ ok = false, message = 'No road nearby' }) end
    cb({ ok = true, data = { x = pos.x, y = pos.y, z = pos.z, h = heading } })
end)

---------------------------------------------------------------------------
-- Speakers: phones playing out loud; the page plays each one at a volume set by distance
---------------------------------------------------------------------------
local speakers = {} -- [serverId] = station
RegisterNetEvent('veyl_phone:speaker', function(src, station) speakers[src] = station end)

CreateThread(function()
    local lastSent = ''
    while true do
        local list, me = {}, GetEntityCoords(PlayerPedId())
        local myId = GetPlayerServerId(PlayerId())
        for src, station in pairs(speakers) do
            if src ~= myId then
                local pl = GetPlayerFromServerId(src)
                if pl ~= -1 then
                    local d = #(GetEntityCoords(GetPlayerPed(pl)) - me)
                    if d < C.Music.SpeakerRange then
                        list[#list + 1] = { id = src, station = station, volume = math.floor((1.0 - d / C.Music.SpeakerRange) * 100) / 100 }
                    end
                end
            end
        end
        local enc = json.encode(list)
        if enc ~= lastSent then
            lastSent = enc
            SendNUIMessage({ action = 'phone:speakers', data = list })
        end
        Wait(next(speakers) and 500 or 2000)
    end
end)

---------------------------------------------------------------------------
-- Racing: record checkpoints, run a race (markers, blips, server-validated passes)
---------------------------------------------------------------------------
RegisterNUICallback('musicStations', function(_, cb) cb({ ok = true, data = C.Music.Stations }) end)

RegisterNUICallback('raceMark', function(_, cb)
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    local c = GetEntityCoords(veh ~= 0 and veh or ped)
    cb({ ok = true, data = { x = math.floor(c.x * 10) / 10, y = math.floor(c.y * 10) / 10, z = math.floor(c.z * 10) / 10 } })
end)

local race = nil
RegisterNetEvent('veyl_phone:race', function(r)
    if race then return end
    race = r
    CreateThread(function()
        for i = r.countdown, 1, -1 do
            BeginTextCommandPrint('STRING') AddTextComponentSubstringPlayerName(('~y~%d'):format(i)) EndTextCommandPrint(1000, true)
            PlaySoundFrontend(-1, '3_2_1', 'HUD_MINI_GAME_SOUNDSET', true)
            Wait(1000)
        end
        BeginTextCommandPrint('STRING') AddTextComponentSubstringPlayerName('~g~GO!') EndTextCommandPrint(1500, true)
        PlaySoundFrontend(-1, 'GO', 'HUD_MINI_GAME_SOUNDSET', true)
        local index, started = 1, GetGameTimer()
        local blip, cp
        local function setTarget()
            if blip then RemoveBlip(blip) end
            if cp then DeleteCheckpoint(cp) end
            local p = r.checkpoints[index]
            if not p then return end
            local n = r.checkpoints[index + 1]
            local last = index == #r.checkpoints
            blip = AddBlipForCoord(p.x, p.y, p.z)
            SetBlipColour(blip, 5)
            SetBlipRoute(blip, true)
            ShowNumberOnBlip(blip, index)
            cp = CreateCheckpoint(last and 4 or 2, p.x, p.y, p.z, n and n.x or p.x, n and n.y or p.y, n and n.z or p.z, 8.0, 255, 210, 80, 140, 0)
            SetCheckpointCylinderHeight(cp, 6.0, 6.0, 8.0)
        end
        setTarget()
        while race and index <= #r.checkpoints do
            local p = r.checkpoints[index]
            local c = GetEntityCoords(PlayerPedId())
            if #(c - vector3(p.x, p.y, p.z)) < 12.0 then
                local res = Veyl.CallbackTimeout('veyl_phone', 'raceCheckpoint', 10000, r.id, index)
                if res.ok then
                    PlaySoundFrontend(-1, 'CHECKPOINT_NORMAL', 'HUD_MINI_GAME_SOUNDSET', true)
                    index = index + 1
                    if res.data and res.data.finished then
                        Veyl.Notify(res.message or 'Finished', 'success')
                        break
                    end
                    setTarget()
                else
                    Wait(500)
                end
            end
            local t = (GetGameTimer() - started) / 1000
            BeginTextCommandPrint('STRING')
            AddTextComponentSubstringPlayerName(('%s  ~y~%d/%d~s~  %d:%05.2f'):format(r.name, index, #r.checkpoints, math.floor(t / 60), t % 60))
            EndTextCommandPrint(100, true)
            Wait(0)
        end
        if blip then RemoveBlip(blip) end
        if cp then DeleteCheckpoint(cp) end
        race = nil
    end)
end)

RegisterCommand('quitrace', function() if race then race = nil Veyl.Notify('You left the race', 'warning') end end, false)

---------------------------------------------------------------------------
-- Tablet item
---------------------------------------------------------------------------
RegisterNetEvent('veyl_phone:tablet', function()
    local options = {}
    local job = Veyl.PlayerData and Veyl.PlayerData.job or {}
    if GetResourceState('veyl_mdt') == 'started' and (job.type == 'leo' or job.type == 'ems' or job.type == 'doj') then
        options[#options + 1] = { id = 'mdt', label = 'MDT', icon = 'shield' }
    end
    if GetResourceState('veyl_dispatch') == 'started' and (job.type == 'leo' or job.type == 'ems') then
        options[#options + 1] = { id = 'dispatch', label = 'Dispatch', icon = 'radio' }
    end
    if GetResourceState('veyl_apartments') == 'started' then options[#options + 1] = { id = 'home', label = 'My home', icon = 'home' } end
    options[#options + 1] = { id = 'phone', label = 'Phone apps', icon = 'phone' }
    vlib.registerMenu({ id = 'veyl_tablet', title = 'Tablet', options = options }, function(id)
        if id == 'mdt' then ExecuteCommand(C.Tablet.Mdt)
        elseif id == 'dispatch' then ExecuteCommand(C.Tablet.Dispatch)
        elseif id == 'home' then TriggerEvent('veyl_apartments:openPanel')
        else exports.veyl_phone:Open() end
    end)
    vlib.showMenu('veyl_tablet')
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and race then race = nil end
end)
