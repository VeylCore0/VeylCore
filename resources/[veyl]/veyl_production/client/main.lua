-- veyl_production client: the tablet screen and the bridge between the page and the server. The page can only call names in ALLOWED;
-- the server validates every request again. Nothing here decides an outcome.

local C = ProductionConfig
ProdClient = ProdClient or { inside = nil, plants = {}, benches = {}, doors = {} }

local screen = vlib.createScreen({ name = 'production' })
ProdClient.screen = screen

local function reply(cb, res) cb({ ok = res.ok, code = res.code, message = res.message, data = res.data }) end

--- Opens the page on a view: 'tablet' | 'shop' | 'buyer' | 'bench'.
function ProdClient.open(view, data)
    if screen:isOpen() or not Veyl.IsLoaded() then return end
    local ok, reason = screen:open('production:open', { view = view, data = data })
    if not ok then Veyl.Notify(reason == 'busy' and 'Close the open menu first.' or 'Not available right now.', 'warning') end
end

--- Loads the tablet's state from the server and shows it.
function ProdClient.openTablet(page)
    local res = Veyl.CallbackTimeout('veyl_production', 'state', 15000)
    if not res.ok then return Veyl.NotifyResult(res) end
    ProdClient.open('tablet', { state = res.data, page = page })
end

RegisterCommand(C.Command, function() CreateThread(function() ProdClient.openTablet() end) end, false)
RegisterNetEvent('veyl_production:openTablet', function(page) CreateThread(function() ProdClient.openTablet(page) end) end)
AddEventHandler('veyl_production:openTabletLocal', function(page) CreateThread(function() ProdClient.openTablet(page) end) end)

---------------------------------------------------------------------------
-- Page -> server
---------------------------------------------------------------------------
local ALLOWED = {
    state = true, shopView = true, buyerView = true, shopBuy = true, shopSell = true,
    wsOpen = true, wsStart = true, wsClaim = true, wsCancel = true, wsPack = true,
    propCatalogue = true, propBuy = true, propSell = true, propTransfer = true, propUpgrade = true, propLock = true, propCode = true,
    propMemberAdd = true, propMemberRemove = true, propStorage = true, nearbyPlayers = true, raidSeize = true,
}

RegisterNUICallback('api', function(data, cb)
    if not screen:isOpen() or type(data) ~= 'table' or not ALLOWED[data.name] then return cb({ ok = false, code = 'INVALID_INPUT' }) end
    local args = type(data.args) == 'table' and data.args or {}
    CreateThread(function()
        local res = Veyl.CallbackTimeout('veyl_production', data.name, 20000, table.unpack(args, 1, 4))
        reply(cb, res)
        -- The storage is a veyl_inventory stash: close the tablet and open it (the inventory asks the server again).
        if data.name == 'propStorage' and res.ok and res.data and res.data.stash then
            screen:close('storage')
            Wait(150)
            exports.veyl_inventory:openInventory('stash', res.data.stash)
        end
    end)
end)

RegisterNUICallback('waypoint', function(data, cb)
    cb({ ok = true })
    local x, y = tonumber(data and data.x), tonumber(data and data.y)
    if x and y then SetNewWaypoint(x + 0.0, y + 0.0) Veyl.Notify('GPS set', 'success') end
end)

-- The server says something changed (a plant was harvested, a bench placed): list refreshers listen for this.
RegisterNetEvent('veyl_production:refresh', function(kind)
    TriggerEvent('veyl_production:refreshLocal', kind)
    if screen:isOpen() then screen:send('production:refresh') end
end)

--- A short random id for a client request (the server also makes its own operation ids).
function ProdClient.opId() return ('%08x%06x'):format(GetGameTimer() % 0xffffffff, math.random(0, 0xffffff)) end
