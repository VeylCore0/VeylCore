-- veyl_characters client: selection screen with observable stages, retry and full focus/camera cleanup.

local open = false
local cam = nil
local busy = false

local function hidePed()
    local ped = PlayerPedId()
    SetEntityVisible(ped, false, false)
    SetEntityInvincible(ped, true)
    FreezeEntityPosition(ped, true)
    SetEntityCoordsNoOffset(ped, CharactersConfig.HoldingCoords.x, CharactersConfig.HoldingCoords.y, CharactersConfig.HoldingCoords.z, false, false, false)
end

local function startCamera()
    if cam then return end
    local c = CharactersConfig.SelectionCamera
    cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', c.coords.x, c.coords.y, c.coords.z, 0.0, 0.0, 0.0, c.fov, false, 0)
    PointCamAtCoord(cam, c.pointAt.x, c.pointAt.y, c.pointAt.z)
    SetCamActive(cam, true)
    RenderScriptCams(true, false, 0, true, true)
end

local function stopCamera()
    if not cam then return end
    RenderScriptCams(false, false, 0, true, true)
    DestroyCam(cam, false)
    cam = nil
end

local function send(action, data)
    SendNUIMessage({ action = action, data = data })
end

local function refreshList()
    send('stage', { stage = 'Loading your characters...' })
    local res = Veyl.Callback('veyl_characters', 'list')
    if res.ok then
        send('characters', res.data)
    else
        send('error', { stage = 'Character list', code = res.code, message = res.message or 'Could not load characters' })
    end
end

local function openSelector()
    if open then return end
    open = true
    DoScreenFadeOut(0)
    hidePed()
    startCamera()
    ShutdownLoadingScreen()
    ShutdownLoadingScreenNui()
    SetNuiFocus(true, true)
    send('open', { serverName = 'VeylCore' })
    DoScreenFadeIn(500)
    refreshList()
end

local function closeSelector()
    if not open then return end
    open = false
    SetNuiFocus(false, false)
    send('close')
    stopCamera()
end

-- Session lifecycle -------------------------------------------------------
AddEventHandler('veyl:sessionReady', function()
    if not Veyl.IsLoaded() then openSelector() end
end)

AddEventHandler('veyl:sessionFailed', function(info)
    if not open then
        open = true
        ShutdownLoadingScreen()
        ShutdownLoadingScreenNui()
        DoScreenFadeIn(0)
        SetNuiFocus(true, true)
        send('open', { serverName = 'VeylCore' })
    end
    send('error', { stage = 'Session (' .. tostring(info and info.stage) .. ')', code = info and info.code, message = 'Could not start your session.' })
end)

RegisterNetEvent('veyl:characterUnloaded', function()
    DoScreenFadeOut(300)
    Wait(350)
    openSelector()
end)

RegisterNetEvent('veyl:characterLoaded', function()
    closeSelector()
end)

CreateThread(function()
    -- Resource (re)started while a session already exists.
    while not NetworkIsSessionStarted() do Wait(250) end
    Wait(500)
    if exports.veyl_core:GetSession() and not Veyl.IsLoaded() then openSelector() end
end)

-- NUI actions -------------------------------------------------------------
RegisterNUICallback('select', function(data, cb)
    cb({})
    if busy then return end
    busy = true
    send('stage', { stage = 'Loading character...' })
    local res = Veyl.Callback('veyl_characters', 'select', tonumber(data and data.id))
    busy = false
    if not res.ok then
        send('error', { stage = 'Select character', code = res.code, message = res.message })
    end
    -- On success veyl:characterLoaded closes the screen and veyl_spawn takes over.
end)

RegisterNUICallback('create', function(data, cb)
    cb({})
    if busy then return end
    busy = true
    local res = Veyl.Callback('veyl_characters', 'create', {
        firstname = data.firstname, lastname = data.lastname, dob = data.dob, sex = data.sex,
    })
    busy = false
    if res.ok then
        send('characters', { characters = res.data.characters })
        send('toast', { message = 'Character created', type = 'success' })
    else
        send('formError', { message = res.message or res.code })
    end
end)

RegisterNUICallback('delete', function(data, cb)
    cb({})
    if busy then return end
    busy = true
    local res = Veyl.Callback('veyl_characters', 'delete', tonumber(data and data.id), tostring(data and data.confirmName or ''))
    busy = false
    if res.ok then
        send('characters', { characters = res.data.characters })
        send('toast', { message = 'Character deleted', type = 'success' })
    else
        send('toast', { message = res.message or res.code, type = 'error' })
    end
end)

RegisterNUICallback('retry', function(_, cb)
    cb({})
    if not exports.veyl_core:GetSession() then
        send('stage', { stage = 'Reconnecting session...' })
        exports.veyl_core:RetrySession()
    else
        refreshList()
    end
end)

RegisterNUICallback('disconnect', function(_, cb)
    cb({})
    closeSelector()
    TriggerServerEvent('veyl_characters:quit')
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
    stopCamera()
    if not Veyl.IsLoaded() then
        local ped = PlayerPedId()
        FreezeEntityPosition(ped, false)
        SetEntityVisible(ped, true, false)
    end
    DoScreenFadeIn(0)
end)
