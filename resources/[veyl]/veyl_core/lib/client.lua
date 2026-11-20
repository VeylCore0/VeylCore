-- VeylCore client library. Import after shared.lua:  client_script '@veyl_core/lib/client.lua'
Veyl = Veyl or {}
local RES = GetCurrentResourceName()

---------------------------------------------------------------------------
-- Bounded server callbacks
---------------------------------------------------------------------------
local pending = {}

RegisterNetEvent('veyl:cbr', function(reqId, result)
    local p = pending[reqId]
    if p then
        pending[reqId] = nil
        p:resolve(result)
    end
end)

--- Calls a server callback registered by `target` with Veyl.RegisterCallback. Always returns a
--- { ok, code, message, data } table; times out after timeoutMs (default 10s) with code TIMEOUT.
function Veyl.CallbackTimeout(target, name, timeoutMs, ...)
    local reqId = Veyl.NewId(RES)
    local p = promise.new()
    pending[reqId] = p
    TriggerServerEvent(('veyl:cb:%s:%s'):format(target, name), reqId, ...)
    SetTimeout(timeoutMs or 10000, function()
        if pending[reqId] then
            pending[reqId] = nil
            p:resolve(Veyl.Err('TIMEOUT', ('%s:%s did not respond'):format(target, name)))
        end
    end)
    return Citizen.Await(p)
end

function Veyl.Callback(target, name, ...)
    return Veyl.CallbackTimeout(target, name, 10000, ...)
end

---------------------------------------------------------------------------
-- Player state
---------------------------------------------------------------------------
function Veyl.GetCitizenId()
    return LocalPlayer.state.citizenid
end

function Veyl.IsLoaded()
    return LocalPlayer.state.isLoggedIn == true
end

--- Current PlayerData view for this client (allowlisted by the server). Empty table when logged out.
function Veyl.GetPlayerData()
    return exports.veyl_core:GetPlayerData()
end

---------------------------------------------------------------------------
-- UI wrappers (veyl_ui owns NUI focus; these never leave focus stuck)
---------------------------------------------------------------------------
Veyl.UI = {}

function Veyl.Notify(message, kind, durationMs)
    TriggerEvent('veyl_ui:notify', { message = message, type = kind or 'info', duration = durationMs })
end

--- Shows a response's message (or a fallback) with a colour based on ok/err.
function Veyl.NotifyResult(res, okText)
    if res and res.ok then
        Veyl.Notify(res.message or okText or 'Done', 'success')
    else
        Veyl.Notify((res and res.message) or (res and res.code) or 'Request failed', 'error')
    end
end

function Veyl.UI.Progress(opts) return Veyl.Await('veyl_ui', 'Progress', 0, opts) end      -- -> true / false
function Veyl.UI.Confirm(opts) return Veyl.Await('veyl_ui', 'Confirm', 0, opts) end        -- -> true / false
function Veyl.UI.Input(opts) return Veyl.Await('veyl_ui', 'Input', 0, opts) end            -- -> values table / nil
function Veyl.UI.Menu(opts) return Veyl.Await('veyl_ui', 'Menu', 0, opts) end              -- -> selected value / nil

---------------------------------------------------------------------------
-- Misc helpers
---------------------------------------------------------------------------
function Veyl.LoadModel(model, timeoutMs)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local deadline = GetGameTimer() + (timeoutMs or 10000)
    while not HasModelLoaded(hash) do
        if GetGameTimer() > deadline then return nil end
        Wait(10)
    end
    return hash
end

function Veyl.LoadAnimDict(dict, timeoutMs)
    RequestAnimDict(dict)
    local deadline = GetGameTimer() + (timeoutMs or 5000)
    while not HasAnimDictLoaded(dict) do
        if GetGameTimer() > deadline then return false end
        Wait(10)
    end
    return true
end

function Veyl.HelpText(text)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, false, -1)
end
