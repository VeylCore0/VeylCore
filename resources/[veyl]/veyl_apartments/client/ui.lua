-- NUI bridge. One modal screen (focus token, Escape, death/logout/resource-stop cleanup via vlib.createScreen) and a
-- passive layer (placement hint, tour timer, revoked notice) that never takes focus.
-- The page can only call the server callbacks listed in ALLOWED; the server re-checks every rule anyway.

AptUI = {}
local screen = vlib.createScreen({ name = 'apartments', keepInput = false, onClose = function() TriggerEvent('veyl_apartments:screenClosed') end })

function AptUI.Open(view, data)
    local ok, reason = screen:open('apt:open', { view = view, data = data })
    if not ok then Veyl.Notify(reason == 'busy' and 'Close the open menu first.' or 'Unavailable right now.', 'warning') end
    return ok
end
function AptUI.Send(action, data) screen:send(action, data) end
function AptUI.Close(reason) screen:close(reason or 'done') end
function AptUI.IsOpen() return screen:isOpen() end
function AptUI.Passive(action, data) SendNUIMessage({ action = action, data = data }) end

--- A visitor request: shown inside the open panel, or as a small "doorbell" view of the same screen.
--- (One screen per resource: vlib registers the page's close/ready callbacks once.)
function AptUI.Doorbell(req)
    if screen:isOpen() then screen:send('apt:doorbell', req) return end
    local ok = screen:open('apt:open', { view = 'doorbell', data = req })
    if not ok then Veyl.Notify(('%s is requesting access. Answer in the Apartments app.'):format(req.name), 'info', 9000) end
end


local ALLOWED = {
    catalog = true, lease = true, payRent = true, setAutopay = true, setDirectory = true, payments = true, moveOut = true,
    dashboard = true, roommateInvite = true, roommateRespond = true, roommatePerms = true, roommateRemove = true, roommateLeave = true,
    contribute = true, guestGrant = true, guestRevoke = true, respondVisit = true, unblock = true, directory = true, ringDirectory = true,
    storageList = true, recoveryList = true, wardrobe = true, parcels = true, collectParcel = true,
    notices = true, noticePost = true, noticeRemove = true, noticeReport = true,
    maintenanceCreate = true, maintenanceList = true, maintenanceCancel = true, maintenanceUpdate = true,
    furnitureCatalog = true, furnitureStore = true, furnitureSell = true, furnitureOwned = true,
}

local function reply(cb, res) cb({ ok = res.ok, code = res.code, message = res.message, data = res.data }) end

RegisterNUICallback('api', function(data, cb)
    if type(data) ~= 'table' or not ALLOWED[data.name] then return cb({ ok = false, code = 'INVALID_INPUT' }) end
    local args = type(data.args) == 'table' and data.args or {}
    CreateThread(function() reply(cb, Veyl.CallbackTimeout('veyl_apartments', data.name, 20000, table.unpack(args, 1, 6))) end)
end)

RegisterNUICallback('waypoint', function(data, cb)
    local x, y = tonumber(data and data.x), tonumber(data and data.y)
    if not x or not y then return cb({ ok = false }) end
    SetNewWaypoint(x, y)
    cb({ ok = true, message = 'Waypoint set' })
end)

RegisterNUICallback('openStash', function(data, cb)
    cb({ ok = true })
    local id = data and data.id
    if type(id) ~= 'string' then return end
    screen:close('stash')
    SetTimeout(150, function() TriggerEvent('veyl_apartments:openStash', id) end)
end)

--- Wardrobe actions go through the server; "wear" applies the returned (saved) appearance locally.
RegisterNUICallback('wardrobeAction', function(data, cb)
    CreateThread(function()
        local res = Veyl.CallbackTimeout('veyl_apartments', 'wardrobeAction', 20000, data and data.action, tonumber(data and data.id), data and data.name)
        if res.ok and data.action == 'wear' and res.data and res.data.appearance then
            Veyl.Await('veyl_appearance', 'Apply', 15000, res.data.appearance)
        end
        reply(cb, res)
    end)
end)

RegisterNUICallback('startPlacement', function(data, cb)
    cb({ ok = true })
    screen:close('placement')
    SetTimeout(200, function() TriggerEvent('veyl_apartments:beginPlacement', data) end)
end)

RegisterNUICallback('tour', function(data, cb)
    cb({ ok = true })
    screen:close('tour')
    SetTimeout(200, function() TriggerEvent('veyl_apartments:tour', tonumber(data and data.unitId)) end)
end)

RegisterNUICallback('doorbellAnswer', function(data, cb)
    CreateThread(function()
        local res = Veyl.CallbackTimeout('veyl_apartments', 'respondVisit', 10000, tonumber(data and data.id), data and data.action)
        reply(cb, res)
        if data and data.action ~= 'ignore' then Veyl.NotifyResult(res) end
    end)
end)


AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    AptUI.Passive('apt:placement', { visible = false })
    AptUI.Passive('apt:tour', nil)
end)
