-- Inventory screen: focus via veyl_lib's broker (vlib.createScreen), every action is a server request.

local screen = vlib.createScreen({
    name = 'inventory',
    onClose = function()
        InvState.secondary = nil
        CreateThread(function() vlib.callback.await('veyl_inventory:close', { timeoutMs = 5000 }) end)
    end,
})

function UI_Forward(kind, data)
    if screen:isOpen() then screen:send('inventory:' .. kind, data) end
end

local opening = false

--- Opens the player inventory, optionally with a stash beside it.
function OpenInventory(stashId)
    if opening or screen:isOpen() or not LocalPlayer.state.isLoggedIn then return end
    if IsEntityDead(PlayerPedId()) or IsPauseMenuActive() then return end
    opening = true
    local res = vlib.callback.await('veyl_inventory:open', { timeoutMs = 10000 }, stashId)
    if type(res) ~= 'table' or not res.ok then
        opening = false
        return vlib.notify({ message = (res and res.message) or 'Could not open inventory', type = 'error' })
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
    local ok, reason = screen:open('inventory:open', {
        primary = res.data.primary, secondary = res.data.secondary, items = res.data.items,
        imagePath = res.data.imagePath, hotbarSlots = InventoryConfig.HotbarSlots,
    })
    opening = false
    if not ok then
        CreateThread(function() vlib.callback.await('veyl_inventory:close', { timeoutMs = 5000 }) end)
        vlib.notify({ message = reason == 'busy' and 'Close the open menu first.' or 'Inventory UI unavailable.', type = 'warning' })
    end
end

exports('openInventory', function(kind, id) CreateThread(function() OpenInventory(kind == 'stash' and id or nil) end) end)
exports('closeInventory', function() screen:close('export') end)
exports('IsOpen', function() return screen:isOpen() end)

---------------------------------------------------------------------------
-- NUI callbacks (always resolved, including validation errors)
---------------------------------------------------------------------------
local function ref(v) return (v == 'primary' or v == 'secondary') and v or nil end

RegisterNUICallback('move', function(data, cb)
    if not screen:isOpen() or type(data) ~= 'table' or type(data.from) ~= 'table' or type(data.to) ~= 'table' then
        return cb({ ok = false, code = 'INVALID_INPUT' })
    end
    local res = vlib.callback.await('veyl_inventory:move', { timeoutMs = 10000 }, {
        opId = tostring(data.opId or ''),
        from = { ref = ref(data.from.ref), slot = tonumber(data.from.slot) },
        to = { ref = ref(data.to.ref), slot = tonumber(data.to.slot) },
        count = tonumber(data.count),
        revisions = type(data.revisions) == 'table' and { primary = tonumber(data.revisions.primary), secondary = tonumber(data.revisions.secondary) } or nil,
    })
    if type(res) ~= 'table' then res = { ok = false, code = 'TIMEOUT', message = 'No response from server' } end
    cb({ ok = res.ok, code = res.code, message = res.message })
end)

RegisterNUICallback('use', function(data, cb)
    cb({ ok = true })
    local slot = tonumber(data and data.slot)
    screen:close('use')
    if slot then CreateThread(function() UseSlot(slot) end) end
end)

RegisterNUICallback('nearby', function(_, cb)
    local res = vlib.callback.await('veyl_inventory:nearby', { timeoutMs = 5000 })
    if type(res) ~= 'table' then res = { ok = false, code = 'TIMEOUT', message = 'No response from server' } end
    cb(res)
end)

RegisterNUICallback('give', function(data, cb)
    if not screen:isOpen() or type(data) ~= 'table' then return cb({ ok = false, code = 'INVALID_INPUT' }) end
    local res = vlib.callback.await('veyl_inventory:give', { timeoutMs = 10000 }, {
        opId = tostring(data.opId or ''), slot = tonumber(data.slot), count = tonumber(data.count),
        target = tonumber(data.target), revision = tonumber(data.revision),
    })
    if type(res) ~= 'table' then res = { ok = false, code = 'TIMEOUT', message = 'No response from server' } end
    cb({ ok = res.ok, code = res.code, message = res.message })
end)

---------------------------------------------------------------------------
-- Controls
---------------------------------------------------------------------------
vlib.addKeybind({
    name = 'veyl_inventory', description = 'Open inventory', defaultKey = InventoryConfig.OpenKey,
    onPressed = function() if screen:isOpen() then screen:close('key') else CreateThread(function() OpenInventory(nil) end) end end,
})

-- Hotbar: slots 1..N reference inventory slots (no duplicated storage).
for i = 1, InventoryConfig.HotbarSlots do
    vlib.addKeybind({
        name = ('veyl_hotbar_%d'):format(i), description = ('Use hotbar slot %d'):format(i), defaultKey = tostring(i),
        onPressed = function()
            if screen:isOpen() or not LocalPlayer.state.isLoggedIn or exports.veyl_lib:IsModalOpen() then return end
            local it = InvState.primary and InvState.primary.map and InvState.primary.map[i]
            if not it then return end
            local def = InvState.items[it.name]
            if def and def.usable then CreateThread(function() UseSlot(i) end) end
        end,
    })
end

RegisterNetEvent('veyl_inventory:closed', function() screen:close('server') end)
RegisterNetEvent('veyl_inventory:unavailable', function() vlib.notify({ message = 'Your inventory could not be loaded.', type = 'error' }) end)
