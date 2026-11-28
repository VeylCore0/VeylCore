-- veyl_boosting client: the tablet screen, the access puzzle screen, and the bridge between the page and the server.
-- The page can only call the names listed in ALLOWED; the server validates every request again.

local C = BoostingConfig
BoostClient = BoostClient or {}

local inMinigame = false
local screen = vlib.createScreen({ name = 'boosting', onClose = function()
    if inMinigame then
        inMinigame = false
        ClearPedTasks(PlayerPedId())
        CreateThread(function() Veyl.CallbackTimeout('veyl_boosting', 'accessAbort', 5000) end)
    end
end })
BoostClient.screen = screen

local function reply(cb, res) cb({ ok = res.ok, code = res.code, message = res.message, data = res.data }) end

--- Opens the tablet (only from the inventory item; the server refuses every request without it).
function BoostClient.open(via)
    if screen:isOpen() or not Veyl.IsLoaded() then return end
    local res = Veyl.CallbackTimeout('veyl_boosting', 'state', 10000, via)
    if not res.ok then return Veyl.NotifyResult(res) end
    local ok, reason = screen:open('boosting:open', res.data)
    if not ok then Veyl.Notify(reason == 'busy' and 'Close the open menu first.' or 'The tablet is unavailable.', 'warning') end
end

RegisterNetEvent('veyl_boosting:open', function() CreateThread(function() BoostClient.open('item') end) end)

-- Something changed on the server (crew, contract): the page asks for fresh data.
RegisterNetEvent('veyl_boosting:refresh', function()
    if screen:isOpen() and not inMinigame then screen:send('boosting:refresh') end
end)

RegisterNetEvent('veyl_boosting:invite', function(inv)
    Veyl.Notify(('%s invited you to a boosting crew. Open the tablet to answer.'):format(inv and inv.from or 'Someone'), 'info')
    if screen:isOpen() and not inMinigame then screen:send('boosting:refresh') end
end)

---------------------------------------------------------------------------
-- Page -> server
---------------------------------------------------------------------------
local ALLOWED = {
    state = true, refreshOffers = true, accept = true, startContract = true, cancelContract = true,
    crewNearby = true, crewInvite = true, crewAnswer = true, crewLeave = true, crewKick = true, crewLead = true,
    accessSubmit = true, accessAbort = true,
}

RegisterNUICallback('api', function(data, cb)
    if not screen:isOpen() or type(data) ~= 'table' or not ALLOWED[data.name] then return cb({ ok = false, code = 'INVALID_INPUT' }) end
    local args = type(data.args) == 'table' and data.args or {}
    CreateThread(function() reply(cb, Veyl.CallbackTimeout('veyl_boosting', data.name, 20000, table.unpack(args, 1, 3))) end)
end)

-- GPS: the page sends coordinates the server already gave it (area centre or handoff point).
RegisterNUICallback('waypoint', function(data, cb)
    cb({ ok = true })
    local x, y = tonumber(data and data.x), tonumber(data and data.y)
    if x and y then
        SetNewWaypoint(x + 0.0, y + 0.0)
        Veyl.Notify('GPS set', 'success')
    end
end)

---------------------------------------------------------------------------
-- The access puzzle
---------------------------------------------------------------------------
--- Asks the server to start an attempt on a contract vehicle, then shows the puzzle. The server holds the sequences and the verdict.
function BoostClient.startAccess(entity)
    if inMinigame or screen:isOpen() then return end
    local netId = NetworkGetNetworkIdFromEntity(entity)
    local res = Veyl.CallbackTimeout('veyl_boosting', 'accessBegin', 10000, netId)
    if not res.ok then return Veyl.NotifyResult(res) end
    local ped = PlayerPedId()
    TaskTurnPedToFaceEntity(ped, entity, 500)
    Wait(500)
    if Veyl.LoadAnimDict('anim@amb@clubhouse@tutorial@bkr_tut_ig3@') then
        TaskPlayAnim(ped, 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', 'machinic_loop_mechandplayer', 3.0, 3.0, -1, 1, 0, false, false, false)
    end
    inMinigame = true
    local ok, reason = screen:open('boosting:minigame', res.data)
    if not ok then
        inMinigame = false
        ClearPedTasks(ped)
        Veyl.CallbackTimeout('veyl_boosting', 'accessAbort', 5000)
        Veyl.Notify(reason == 'busy' and 'Close the open menu first.' or 'Could not start.', 'warning')
    end
end

-- The page finished (success, failure or the player backed out).
RegisterNUICallback('minigameDone', function(data, cb)
    cb({ ok = true })
    if not inMinigame then return end
    inMinigame = false
    ClearPedTasks(PlayerPedId())
    screen:close('done')
    -- Backing out leaves the attempt open on the server; drop it so nothing lingers.
    if type(data) == 'table' and data.result == 'cancel' then CreateThread(function() Veyl.CallbackTimeout('veyl_boosting', 'accessAbort', 5000) end) end
    if type(data) == 'table' and type(data.message) == 'string' and #data.message < 120 then
        Veyl.Notify(data.message, data.result == 'success' and 'success' or 'error')
    end
end)
