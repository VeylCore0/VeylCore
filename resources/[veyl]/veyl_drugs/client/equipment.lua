-- Equipment on the client: props for tables near you, their target options and the table screen.
-- The server owns jobs, timing, inputs and outputs; the screen only shows what the server reports.

DrugsEquipClient = { known = {} }
local known = DrugsEquipClient.known
local spawned = {} -- [id] = entity
local OPTION_NAMES = { 'veyl_drugs_eq_use', 'veyl_drugs_eq_tray', 'veyl_drugs_eq_pack' }
local currentId, currentToken = nil, nil

local function despawn(id)
    local ent = spawned[id]
    if not ent then return end
    if GetResourceState('veyl_target') == 'started' then exports.veyl_target:removeLocalEntity(ent, OPTION_NAMES) end
    if DoesEntityExist(ent) then DeleteEntity(ent) end
    spawned[id] = nil
end

local function openEquipment(id)
    if DrugsUI.IsOpen() then return end
    local res = Veyl.Callback('veyl_drugs', 'equipmentOpen', id)
    if not res.ok then return Veyl.NotifyResult(res) end
    currentId = id
    local ok, reason = DrugsUI.Open('drugs:equipment', res.data)
    if not ok then currentId = nil Veyl.Notify(reason == 'busy' and 'Close the open menu first.' or 'Unavailable right now.', 'warning') end
end

local function collect(id)
    Veyl.NotifyResult(Veyl.Callback('veyl_drugs', 'collectTray', id))
end

local function pack(id)
    if vlib.alertDialog({ title = 'Pack up this table?', message = 'It goes back into your inventory.', confirmLabel = 'Pack up' }) ~= 'confirm' then return end
    local start = Veyl.Callback('veyl_drugs', 'packStart', id)
    if not start.ok then return Veyl.NotifyResult(start) end
    local done = vlib.progress({ label = 'Packing up', duration = start.data.durationMs, canCancel = true,
        disable = { move = true, car = true, combat = true }, anim = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 1 } })
    ClearPedTasks(PlayerPedId())
    if done then Veyl.NotifyResult(Veyl.Callback('veyl_drugs', 'packComplete', start.data.token))
    else Veyl.Callback('veyl_drugs', 'packCancel') end
end

local function options(id)
    local function k() return known[id] end
    return {
        { name = 'veyl_drugs_eq_use', label = 'Use table', icon = 'box', distance = DrugsEquipment.UseDistance,
          canInteract = function() return k() and k().own end,
          onSelect = function() CreateThread(function() openEquipment(id) end) end },
        { name = 'veyl_drugs_eq_tray', label = 'Collect from table', icon = 'hand', distance = DrugsEquipment.UseDistance,
          canInteract = function() return k() and k().own and (k().tray or 0) > 0 end,
          onSelect = function() CreateThread(function() collect(id) end) end },
        { name = 'veyl_drugs_eq_pack', label = 'Pack up', icon = 'close', distance = DrugsEquipment.UseDistance,
          canInteract = function() return k() and k().own and not k().busy and (k().tray or 0) == 0 end,
          onSelect = function() CreateThread(function() pack(id) end) end },
    }
end

local function spawn(e)
    local def = DrugsEquipment.types[e.kind]
    if not def then return end
    local hash = joaat(def.prop)
    if not IsModelInCdimage(hash) then hash = joaat(DrugsFallbackProp) end
    RequestModel(hash)
    local deadline = GetGameTimer() + 3000
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(10) end
    if not HasModelLoaded(hash) then return end
    local ent = CreateObject(hash, e.x, e.y, e.z, false, false, false)
    SetEntityHeading(ent, e.h or 0.0)
    FreezeEntityPosition(ent, true)
    SetModelAsNoLongerNeeded(hash)
    spawned[e.id] = ent
    if GetResourceState('veyl_target') == 'started' then exports.veyl_target:addLocalEntity(ent, options(e.id)) end
end

function DrugsEquipClient.Sync(list)
    local seen = {}
    for _, e in ipairs(list) do seen[e.id] = true known[e.id] = e end
    for id in pairs(known) do if not seen[id] then known[id] = nil despawn(id) end end
end

RegisterNetEvent('veyl_drugs:equipmentUpdated', function(e) known[e.id] = e end)
RegisterNetEvent('veyl_drugs:equipmentRemoved', function(id)
    known[id] = nil
    despawn(id)
    if currentId == id then DrugsUI.Close() end
end)

CreateThread(function()
    while true do
        if Veyl.IsLoaded() then
            local pos = GetEntityCoords(PlayerPedId())
            for id, e in pairs(known) do
                local near = #(pos - vector3(e.x, e.y, e.z)) <= DrugsConfig.Stream.SpawnRadius
                if near and not spawned[id] then spawn(e) elseif not near and spawned[id] then despawn(id) end
            end
        end
        Wait(1000)
    end
end)

RegisterNetEvent('VeylCore:Client:OnPlayerUnload', function()
    for id in pairs(spawned) do despawn(id) end
    for id in pairs(known) do known[id] = nil end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(spawned) do despawn(id) end
    ClearPedTasks(PlayerPedId())
end)

---------------------------------------------------------------------------
-- Table screen NUI callbacks
---------------------------------------------------------------------------
local WORK_ANIM = { dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', clip = 'machinic_loop_mechandplayer' }

local function playWork(on)
    local ped = PlayerPedId()
    if not on then ClearPedTasks(ped) return end
    RequestAnimDict(WORK_ANIM.dict)
    local deadline = GetGameTimer() + 2000
    while not HasAnimDictLoaded(WORK_ANIM.dict) and GetGameTimer() < deadline do Wait(10) end
    if HasAnimDictLoaded(WORK_ANIM.dict) then TaskPlayAnim(ped, WORK_ANIM.dict, WORK_ANIM.clip, 3.0, -3.0, -1, 1, 0, false, false, false) end
end

local function reply(cb, res) cb({ ok = res.ok, code = res.code, message = res.message, data = res.data }) end

RegisterNUICallback('craftStart', function(data, cb)
    if not currentId or type(data) ~= 'table' then return cb({ ok = false, code = 'INVALID_INPUT' }) end
    local res = Veyl.Callback('veyl_drugs', 'craftStart', currentId, tostring(data.recipe or ''), math.floor(tonumber(data.units) or 0), data.batch)
    if res.ok then
        currentToken = res.data.token
        local e = known[currentId]
        if e then TaskTurnPedToFaceCoord(PlayerPedId(), e.x, e.y, e.z, 500) end
        CreateThread(function() Wait(500) playWork(true) end)
    end
    reply(cb, res)
end)

RegisterNUICallback('craftComplete', function(data, cb)
    if not currentToken then return cb({ ok = false, code = 'INVALID_STATE' }) end
    local res = Veyl.Callback('veyl_drugs', 'craftComplete', currentToken, tonumber(data and data.score))
    if res.ok or res.code ~= 'PENDING' then currentToken = nil playWork(false) end
    reply(cb, res)
end)

RegisterNUICallback('craftCancel', function(_, cb)
    local token = currentToken
    currentToken = nil
    playWork(false)
    if not token then return cb({ ok = true }) end
    reply(cb, Veyl.Callback('veyl_drugs', 'craftCancel', token))
end)

RegisterNUICallback('collectTray', function(_, cb)
    if not currentId then return cb({ ok = false }) end
    reply(cb, Veyl.Callback('veyl_drugs', 'collectTray', currentId))
end)

-- Closing the screen (Esc, death, logout) cancels a running job: its supplies are refunded by the server.
AddEventHandler('veyl_drugs:screenClosed', function()
    if currentToken then
        local token = currentToken
        currentToken = nil
        playWork(false)
        CreateThread(function() Veyl.Callback('veyl_drugs', 'craftCancel', token) end)
    end
    currentId = nil
end)
