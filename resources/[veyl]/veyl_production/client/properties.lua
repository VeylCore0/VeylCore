-- Laboratories on the client: street doors (through veyl_interact), moving in and out of the interior, the storage and management
-- points inside, transfer offers and police raids. The server decides who gets in and what happens; this only moves the player.

local C = ProductionConfig
local P = C.Properties
local doorIds = {}
local INSIDE_ZONE = 'veyl_prod_inside'
local busy = false

local function fade(out) if out then DoScreenFadeOut(450) while not IsScreenFadedOut() do Wait(10) end else DoScreenFadeIn(450) end end

local function teleport(x, y, z, w)
    local ped = PlayerPedId()
    RequestCollisionAtCoord(x, y, z)
    SetEntityCoordsNoOffset(ped, x + 0.0, y + 0.0, z + 0.0, false, false, false)
    if w then SetEntityHeading(ped, w + 0.0) end
    local deadline = GetGameTimer() + 3000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < deadline do Wait(10) end
end

local function removeInsideZone() pcall(function() exports.veyl_interact:Remove(INSIDE_ZONE) end) end

local function leaveTo(pos)
    fade(true)
    removeInsideZone()
    ProdClient.inside, ProdClient.interior = nil, nil
    teleport(pos.x, pos.y, pos.z, pos.w)
    TriggerEvent('veyl_production:insideChanged')
    Wait(300)
    fade(false)
end

local function enterWith(data)
    fade(true)
    if data.ipl and data.ipl ~= '' then
        RequestIpl(data.ipl)
        local deadline = GetGameTimer() + 4000
        while not IsIplActive(data.ipl) and GetGameTimer() < deadline do Wait(50) end
    end
    ProdClient.inside = data.id
    ProdClient.interior = { spawn = data.spawn, radius = data.radius, door = data.door, id = data.id }
    teleport(data.spawn.x, data.spawn.y, data.spawn.z, data.spawn.w)
    exports.veyl_interact:AddZone({
        id = INSIDE_ZONE, coords = vector3(data.door.x, data.door.y, data.door.z), radius = 1.6, title = data.label,
        options = {
            { label = 'Open storage', icon = 'box', onSelect = function() CreateThread(function()
                local r = Veyl.CallbackTimeout('veyl_production', 'propStorage', 15000, data.id)
                if not r.ok then return Veyl.NotifyResult(r) end
                exports.veyl_inventory:openInventory('stash', r.data.stash)
            end) end },
            { label = 'Laboratory management', icon = 'gear', onSelect = function() TriggerEvent('veyl_production:openTabletLocal', 'properties') end },
            { label = 'Leave', icon = 'door', onSelect = function() CreateThread(function()
                local r = Veyl.CallbackTimeout('veyl_production', 'propExit', 15000)
                if not r.ok then return Veyl.NotifyResult(r) end
                leaveTo(r.data)
            end) end },
        },
    })
    TriggerEvent('veyl_production:insideChanged')
    Wait(400)
    fade(false)
    TriggerEvent('veyl_production:refreshLocal')
end

local function tryEnter(id)
    if busy then return end
    busy = true
    local res = Veyl.CallbackTimeout('veyl_production', 'propEnter', 15000, id)
    if not res.ok and res.code == 'CODE_REQUIRED' then
        local values = vlib.inputDialog('Access code', { { name = 'code', label = 'Code', type = 'input', required = true, password = true } }, { submitLabel = 'Enter' })
        if values and values.code then res = Veyl.CallbackTimeout('veyl_production', 'propEnter', 15000, id, tostring(values.code)) else busy = false return end
    end
    if not res.ok then busy = false return Veyl.NotifyResult(res) end
    enterWith(res.data)
    busy = false
end

local function raid(id)
    if busy then return end
    busy = true
    local start = Veyl.CallbackTimeout('veyl_production', 'raidStart', 15000, id)
    if not start.ok then busy = false return Veyl.NotifyResult(start) end
    local done = vlib.progress({ label = 'Breaching the door', duration = start.data.seconds * 1000, canCancel = true,
        disable = { move = true, car = true, combat = true }, anim = { dict = 'missheistfbi3b_ig7', clip = 'lift_fibagent_loop', flag = 1 } })
    ClearPedTasks(PlayerPedId())
    if not done then busy = false return Veyl.Notify('Breach cancelled', 'info') end
    Veyl.NotifyResult(Veyl.CallbackTimeout('veyl_production', 'raidFinish', 15000, start.data.token))
    busy = false
end

local function addDoors(list)
    for _, d in ipairs(list) do
        local id = 'veyl_prod_door_' .. d.id
        exports.veyl_interact:AddZone({
            id = id, coords = vector3(d.entry.x, d.entry.y, d.entry.z), radius = 2.0, title = d.label,
            options = {
                { label = 'Enter laboratory', icon = 'door', onSelect = function() CreateThread(function() tryEnter(d.id) end) end },
                { label = 'Laboratory details', icon = 'info', onSelect = function() TriggerEvent('veyl_production:openTabletLocal', 'properties') end },
                { label = 'Breach the door', icon = 'shield', groups = C.Police.Jobs, onSelect = function() CreateThread(function() raid(d.id) end) end },
            },
        })
        doorIds[#doorIds + 1] = id
    end
end

CreateThread(function()
    while not Veyl.IsLoaded() do Wait(1000) end
    while GetResourceState('veyl_interact') ~= 'started' do Wait(500) end
    local r = Veyl.CallbackTimeout('veyl_production', 'propList', 15000)
    if r.ok then addDoors(r.data) end
    -- Left the game inside a lab? The interior is only there for people in its bucket: put them back on the street.
    local back = Veyl.CallbackTimeout('veyl_production', 'propRecover', 15000)
    if back.ok and back.data then teleport(back.data.x, back.data.y, back.data.z, back.data.w) end
end)

-- The server let us out (sold, transferred, access removed).
RegisterNetEvent('veyl_production:leave', function(pos) CreateThread(function() leaveTo(pos) end) end)

RegisterNetEvent('veyl_production:transferOffer', function(offer)
    CreateThread(function()
        local choice = vlib.alertDialog({ title = 'Laboratory offer', message = ('%s wants to give you %s.'):format(offer.from, offer.property), confirmLabel = 'Accept', cancelLabel = 'Decline' })
        Veyl.NotifyResult(Veyl.CallbackTimeout('veyl_production', 'propTransferAnswer', 15000, choice == 'confirm'))
    end)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    removeInsideZone()
    for _, id in ipairs(doorIds) do pcall(function() exports.veyl_interact:Remove(id) end) end
    if ProdClient.inside then DoScreenFadeIn(0) end
end)
