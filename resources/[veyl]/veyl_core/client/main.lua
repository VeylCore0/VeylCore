-- veyl_core client: announces the client to the server and exposes session state.

local session = nil
local failed = nil

local function announce()
    local attempts = 0
    while not session and attempts < VeylConfig.ClientReadyMaxAttempts do
        attempts = attempts + 1
        TriggerServerEvent('veyl_core:clientReady')
        local deadline = GetGameTimer() + VeylConfig.ClientReadyRetryMs
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

RegisterNetEvent('veyl_core:coreStopped', function()
    session = nil
end)

exports('GetSession', function() return session end)
exports('GetSessionFailure', function() return failed end)

--- Lets a UI offer "retry" after a failed stage.
exports('RetrySession', function()
    if session then return end
    failed = nil
    CreateThread(announce)
end)
