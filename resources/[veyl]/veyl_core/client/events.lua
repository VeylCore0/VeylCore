-- Session handshake: announce the client until the server confirms, with an observable failure state.

local session = nil
local failed = nil

local function announce()
    local attempts = 0
    while not session and attempts < VeylClientConfig.ClientReadyMaxAttempts do
        attempts = attempts + 1
        TriggerServerEvent('veyl_core:clientReady')
        local deadline = GetGameTimer() + VeylClientConfig.ClientReadyRetryMs
        while not session and GetGameTimer() < deadline do Wait(100) end
    end
    if not session then
        failed = failed or { code = 'TIMEOUT', stage = 'session' }
        TriggerEvent('veyl:sessionFailed', failed)
    end
end

CreateThread(function()
    while not NetworkIsSessionStarted() do Wait(100) end
    announce()
end)

RegisterNetEvent('veyl_core:sessionReady', function(data)
    session = data
    failed = nil
    TriggerEvent('veyl:sessionReady', data)
end)

RegisterNetEvent('veyl_core:sessionFailed', function(info)
    failed = info
    TriggerEvent('veyl:sessionFailed', info)
end)

function GetSession() return session end
function GetSessionFailure() return failed end
function RetrySession()
    if session then return end
    failed = nil
    CreateThread(announce)
end
