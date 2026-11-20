-- Inventory NUI: focus comes from the veyl_lib broker; this resource applies it to its own page.

local isOpen = false
local focusToken = nil
local uiReady = false

function UI_Forward(kind, data)
    if isOpen then SendNUIMessage({ action = 'inventory:' .. kind, data = data }) end
end

local function releaseFocus()
    SetNuiFocus(false, false)
    if focusToken then
        exports.veyl_lib:ReleaseFocus(focusToken)
        focusToken = nil
    end
end

local function closeInventory(notifyServer)
    if not isOpen then return end
    isOpen = false
    SendNUIMessage({ action = 'inventory:close' })
    releaseFocus()
    InvState.secondary = nil
    if notifyServer ~= false then CreateThread(function() vlib.callback.await('veyl_inventory:close', { timeoutMs = 5000 }) end) end
end

--- Opens the player inventory, optionally with a stash beside it.
function OpenInventory(stashId)
    if isOpen or not LocalPlayer.state.isLoggedIn then return end
    if IsEntityDead(PlayerPedId()) or IsPauseMenuActive() then return end
    local token, reason = exports.veyl_lib:RequestFocus('inventory')
    if not token then
        return vlib.notify({ message = reason == 'busy' and 'Close the open menu first.' or 'Inventory unavailable.', type = 'warning' })
    end
    focusToken = token
    local res = vlib.callback.await('veyl_inventory:open', { timeoutMs = 10000 }, stashId)
    if type(res) ~= 'table' or not res.ok then
        releaseFocus()
        return vlib.notify({ message = (res and res.message) or 'Could not open inventory', type = 'error' })
    end
    -- Bounded wait for the page: a failed asset load must never leave an invisible focused page.
    local deadline = GetGameTimer() + 5000
    while not uiReady and GetGameTimer() < deadline do Wait(50) end
    if not uiReady then
        releaseFocus()
        return vlib.notify({ message = 'Inventory UI failed to load (web/dist missing?)', type = 'error' })
    end
    InvState.primary = res.data.primary
    InvState.secondary = res.data.secondary
    InvState.items = res.data.items
    for _, view in ipairs({ InvState.primary, InvState.secondary }) do
        if view then
            view.map = {}
            for _, it in ipairs(view.items or {}) do view.map[it.slot] = it end
        end
    end
    isOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'inventory:open', data = {
        primary = res.data.primary, secondary = res.data.secondary, items = res.data.items, imagePath = res.data.imagePath,
    } })
end

exports('openInventory', function(kind, id)
    if kind == 'stash' then OpenInventory(id) else OpenInventory(nil) end
end)
exports('closeInventory', function() closeInventory(true) end)
exports('IsOpen', function() return isOpen end)

---------------------------------------------------------------------------
-- NUI callbacks: always resolved, including validation errors.
---------------------------------------------------------------------------
RegisterNUICallback('ui:ready', function(_, cb)
    uiReady = true
    cb({ ok = true })
end)

RegisterNUICallback('close', function(_, cb)
    cb({ ok = true })
    closeInventory(true)
end)

RegisterNUICallback('move', function(data, cb)
    if not isOpen or type(data) ~= 'table' then return cb({ ok = false, code = 'CLOSED' }) end
    local res = vlib.callback.await('veyl_inventory:move', { timeoutMs = 10000 }, {
        opId = tostring(data.opId or ''),
        from = { ref = data.from and data.from.ref, slot = tonumber(data.from and data.from.slot) },
        to = { ref = data.to and data.to.ref, slot = tonumber(data.to and data.to.slot) },
        count = tonumber(data.count),
        revisions = type(data.revisions) == 'table' and data.revisions or nil,
    })
    if type(res) ~= 'table' then res = { ok = false, code = 'TIMEOUT', message = 'No response from server' } end
    cb({ ok = res.ok, code = res.code, message = res.message })
end)

RegisterNUICallback('use', function(data, cb)
    cb({ ok = true })
    local slot = tonumber(data and data.slot)
    closeInventory(true)
    if slot then CreateThread(function() UseSlot(slot) end) end
end)

---------------------------------------------------------------------------
-- Controls & cleanup
---------------------------------------------------------------------------
vlib.addKeybind({
    name = 'veyl_inventory', description = 'Open inventory', defaultKey = InventoryConfig.OpenKey,
    onPressed = function() if isOpen then closeInventory(true) else CreateThread(function() OpenInventory(nil) end) end end,
})

RegisterNetEvent('veyl_inventory:closed', function() closeInventory(false) end)
RegisterNetEvent('veyl_inventory:unavailable', function() vlib.notify({ message = 'Your inventory could not be loaded.', type = 'error' }) end)
RegisterNetEvent('VeylCore:Client:OnPlayerUnload', function() closeInventory(false) end)

AddEventHandler('veyl_lib:focusRevoked', function(token) if token == focusToken then focusToken = nil closeInventory(true) end end)
AddEventHandler('veyl_lib:brokerReset', function() focusToken = nil closeInventory(true) end)

CreateThread(function()
    while true do
        if isOpen and IsEntityDead(PlayerPedId()) then closeInventory(true) end
        Wait(500)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and isOpen then releaseFocus() end
end)
