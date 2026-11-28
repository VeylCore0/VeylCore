-- Inventory screen: focus via veyl_lib's broker (vlib.createScreen), every action is a server request.

local shopCtx -- set while a shop is open in the inventory screen: { shopId }

local screen = vlib.createScreen({
    name = 'inventory',
    keepInput = true, -- you can keep walking with the inventory open
    onClose = function()
        shopCtx = nil
        InvState.secondary = nil
        CreateThread(function() vlib.callback.await('veyl_inventory:close', { timeoutMs = 5000 }) end)
    end,
})

function UI_Forward(kind, data)
    if screen:isOpen() then screen:send('inventory:' .. kind, data) end
end

local opening = false

--- Opens the player inventory, optionally with a stash beside it.
function OpenInventory(stashId, shop)
    if opening or screen:isOpen() or not LocalPlayer.state.isLoggedIn then return end
    if IsEntityDead(PlayerPedId()) or LocalPlayer.state.medical or LocalPlayer.state.cuffed or IsPauseMenuActive() then return end
    opening = true
    local res = vlib.callback.await('veyl_inventory:open', { timeoutMs = 10000 }, stashId)
    if type(res) ~= 'table' or not res.ok then
        opening = false
        return vlib.notify({ message = (res and res.message) or 'Could not open inventory', type = 'error' })
    end
    InvState.primary = res.data.primary
    InvState.secondary = res.data.secondary
    InvState.equip = res.data.equip
    InvState.backpack = res.data.backpack
    InvState.equipSlots = res.data.equipSlots or InvState.equipSlots
    InvState.items = res.data.items
    for _, view in ipairs({ InvState.primary, InvState.secondary, InvState.equip or false, InvState.backpack or false }) do
        if view then
            view.map = {}
            for _, it in ipairs(view.items or {}) do view.map[it.slot] = it end
        end
    end
    local ok, reason = screen:open('inventory:open', {
        primary = res.data.primary, secondary = (not shop) and res.data.secondary or nil, equip = res.data.equip, backpack = res.data.backpack, equipSlots = res.data.equipSlots,
        categories = res.data.categories, profile = res.data.profile, items = res.data.items,
        shop = shop and shop.catalog or nil,
        imagePath = res.data.imagePath, hotbarSlots = InventoryConfig.HotbarSlots,
    })
    opening = false
    if not ok then
        shopCtx = nil
        CreateThread(function() vlib.callback.await('veyl_inventory:close', { timeoutMs = 5000 }) end)
        vlib.notify({ message = reason == 'busy' and 'Close the open menu first.' or 'Inventory UI unavailable.', type = 'warning' })
    end
end

--- Opens the inventory with a shop's catalog in the right-hand column (called by veyl_shops).
exports('openShop', function(catalog, shopId)
    if GetInvokingResource() ~= 'veyl_shops' or type(catalog) ~= 'table' or type(shopId) ~= 'string' then return end
    shopCtx = { shopId = shopId }
    CreateThread(function() OpenInventory(nil, { catalog = catalog }) end)
end)

exports('openInventory', function(kind, id) CreateThread(function() OpenInventory(kind == 'stash' and id or nil) end) end)
exports('closeInventory', function() screen:close('export') end)
exports('IsOpen', function() return screen:isOpen() end)

---------------------------------------------------------------------------
-- NUI callbacks (always resolved, including validation errors)
---------------------------------------------------------------------------
local REFS = { primary = true, secondary = true, equip = true, backpack = true }
local function ref(v) return REFS[v] and v or nil end
local function personal(v) return v == 'backpack' and 'backpack' or 'primary' end

RegisterNUICallback('move', function(data, cb)
    if not screen:isOpen() or type(data) ~= 'table' or type(data.from) ~= 'table' or type(data.to) ~= 'table' then
        return cb({ ok = false, code = 'INVALID_INPUT' })
    end
    local res = vlib.callback.await('veyl_inventory:move', { timeoutMs = 10000 }, {
        opId = tostring(data.opId or ''),
        from = { ref = ref(data.from.ref), slot = tonumber(data.from.slot) },
        to = { ref = ref(data.to.ref), slot = tonumber(data.to.slot) },
        count = tonumber(data.count),
        revisions = type(data.revisions) == 'table' and { primary = tonumber(data.revisions.primary), secondary = tonumber(data.revisions.secondary),
            equip = tonumber(data.revisions.equip), backpack = tonumber(data.revisions.backpack) } or nil,
    })
    if type(res) ~= 'table' then res = { ok = false, code = 'TIMEOUT', message = 'No response from server' } end
    cb({ ok = res.ok, code = res.code, message = res.message })
end)

RegisterNUICallback('use', function(data, cb)
    cb({ ok = true })
    local slot = tonumber(data and data.slot)
    local from = personal(data and data.ref)
    screen:close('use')
    if slot then CreateThread(function() UseSlot(slot, from) end) end
end)

RegisterNUICallback('itemAction', function(data, cb)
    local slot, id = tonumber(data and data.slot), data and data.id
    if not screen:isOpen() or not slot or type(id) ~= 'string' then return cb({ ok = false, code = 'INVALID_INPUT' }) end
    local arg = type(data.arg) == 'table' and { op = tostring(data.arg.op or ''), slot = tonumber(data.arg.slot) } or nil
    local res = vlib.callback.await('veyl_inventory:itemAction', { timeoutMs = 8000 }, slot, id, arg)
    if type(res) ~= 'table' then res = { ok = false, code = 'TIMEOUT', message = 'No response from server' } end
    cb({ ok = res.ok, code = res.code, message = res.message, data = res.data })
end)

RegisterNUICallback('itemTray', function(data, cb)
    local slot, id = tonumber(data and data.slot), data and data.id
    if not screen:isOpen() or not slot or type(id) ~= 'string' then return cb({ ok = false, code = 'INVALID_INPUT' }) end
    local res = vlib.callback.await('veyl_inventory:itemTray', { timeoutMs = 8000 }, slot, id)
    if type(res) ~= 'table' then res = { ok = false, code = 'TIMEOUT', message = 'No response from server' } end
    cb({ ok = res.ok, code = res.code, message = res.message, data = res.data })
end)

RegisterNUICallback('drop', function(data, cb)
    if not screen:isOpen() or type(data) ~= 'table' then return cb({ ok = false, code = 'INVALID_INPUT' }) end
    local res = vlib.callback.await('veyl_inventory:drop', { timeoutMs = 10000 }, {
        opId = tostring(data.opId or ''), slot = tonumber(data.slot), count = tonumber(data.count), revision = tonumber(data.revision), ref = personal(data.ref),
    })
    if type(res) ~= 'table' then res = { ok = false, code = 'TIMEOUT', message = 'No response from server' } end
    if res.ok then
        -- Short put-down animation; the item is already on the ground (server-confirmed).
        local ped = PlayerPedId()
        if not IsPedInAnyVehicle(ped, false) then
            CreateThread(function()
                local dict = 'pickup_object'
                RequestAnimDict(dict)
                local t = GetGameTimer() + 1000
                while not HasAnimDictLoaded(dict) and GetGameTimer() < t do Wait(10) end
                if HasAnimDictLoaded(dict) then TaskPlayAnim(ped, dict, 'putdown_low', 8.0, -8.0, 900, 48, 0, false, false, false) end
            end)
        end
    end
    cb({ ok = res.ok, code = res.code, message = res.message })
end)

RegisterNUICallback('shopBuy', function(data, cb)
    if not screen:isOpen() or not shopCtx or type(data) ~= 'table' or GetResourceState('veyl_shops') ~= 'started' then return cb({ ok = false, code = 'INVALID_STATE' }) end
    local res = exports.veyl_shops:Checkout(shopCtx.shopId, {
        opId = tostring(data.opId or ''), method = data.method == 'bank' and 'bank' or 'cash',
        lines = { { index = tonumber(data.index), count = tonumber(data.count) } }, expectedTotal = tonumber(data.expectedTotal),
    })
    if type(res) ~= 'table' then res = { ok = false, code = 'TIMEOUT', message = 'No response from the shop' } end
    -- Fresh balances for the panel (the new items arrive through the normal inventory updates).
    if res.ok then
        local cat = exports.veyl_shops:Catalog(shopCtx.shopId)
        if type(cat) == 'table' and cat.ok then screen:send('inventory:shop', cat.data) end
    end
    cb({ ok = res.ok, code = res.code, message = res.message })
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
        target = tonumber(data.target), revision = tonumber(data.revision), ref = personal(data.ref),
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
