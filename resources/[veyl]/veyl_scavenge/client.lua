-- veyl_scavenge client: every configured trash can, dumpster and garbage bag prop gets a "search" option. The server decides everything.

local C = ScavengeConfig
local busy = false
local picked = {} -- keys the server said are picked over (hides the prompt for a little while)

local function key(kind, c) return ('%s:%d:%d:%d'):format(kind, math.floor(c.x / 2), math.floor(c.y / 2), math.floor(c.z / 2)) end

local function search(kind, def, entity)
    if busy then return end
    busy = true
    local c = GetEntityCoords(entity)
    local k = key(kind, c)
    local start = Veyl.CallbackTimeout('veyl_scavenge', 'searchStart', 15000, kind, c.x, c.y, c.z)
    if not start.ok then
        busy = false
        if start.code == 'COOLDOWN' then picked[k] = GetGameTimer() + 120000 end
        return Veyl.NotifyResult(start)
    end
    TaskTurnPedToFaceEntity(PlayerPedId(), entity, 500)
    Wait(500)
    local done = vlib.progress({ label = 'Searching', duration = start.data.durationMs, canCancel = true,
        disable = { move = true, car = true, combat = true }, anim = start.data.anim })
    ClearPedTasks(PlayerPedId())
    if not done then busy = false return Veyl.Notify('You stop searching', 'info') end
    local res = Veyl.CallbackTimeout('veyl_scavenge', 'searchFinish', 15000, start.data.token)
    picked[k] = GetGameTimer() + 120000
    busy = false
    Veyl.NotifyResult(res)
end

CreateThread(function()
    while GetResourceState('veyl_target') ~= 'started' do Wait(500) end
    for kind, def in pairs(C.Kinds) do
        local models = {}
        for _, m in ipairs(def.Models) do if IsModelInCdimage(joaat(m)) then models[#models + 1] = m end end
        if C.Debug then print(('[veyl_scavenge] %s: %d of %d models available'):format(kind, #models, #def.Models)) end
        exports.veyl_target:addModel(models, {
            { name = 'veyl_scavenge_' .. kind, label = def.label, icon = def.icon, distance = 2.0, priority = 2,
              canInteract = function(e)
                  if busy or GetVehiclePedIsIn(PlayerPedId(), false) ~= 0 then return false end
                  local until_ = picked[key(kind, GetEntityCoords(e))]
                  return not until_ or until_ < GetGameTimer()
              end,
              onSelect = function(d) CreateThread(function() search(kind, def, d.entity) end) end },
        })
    end
end)

-- Hiding in the dumpster ------------------------------------------------------------------------------------------------------
local H = C.Hide or {}
local hidden = false
local forced = false
RegisterNetEvent('veyl_scavenge:forceOut', function() forced = true end)

local function hideIn(entity)
    if busy or hidden then return end
    busy = true
    local ped = PlayerPedId()
    local back = GetEntityCoords(ped)
    local c = GetEntityCoords(entity)
    local res = Veyl.CallbackTimeout('veyl_scavenge', 'hideEnter', 15000, c.x, c.y, c.z)
    if not res.ok then busy = false return Veyl.NotifyResult(res) end
    TaskTurnPedToFaceEntity(ped, entity, 500)
    Wait(500)
    local done = vlib.progress({ label = 'Climbing in', duration = H.EnterMs or 1800, canCancel = true, disable = { move = true, car = true, combat = true },
        anim = { dict = 'anim@heists@narcotics@trash', clip = 'throw_b', flag = 1 } })
    ClearPedTasks(ped)
    if not done or not DoesEntityExist(entity) then
        Veyl.CallbackTimeout('veyl_scavenge', 'hideExit', 10000)
        busy = false
        return
    end
    hidden, forced = true, false
    local maxAt = GetGameTimer() + (res.data.maxSeconds or 300) * 1000
    local health = GetEntityHealth(ped)
    SetEntityVisible(ped, false, false)
    SetEntityCollision(ped, false, false)
    FreezeEntityPosition(ped, true)
    SetEntityCoordsNoOffset(ped, c.x, c.y, c.z + 0.6, false, false, false)
    if H.NpcsIgnoreYou then SetEveryoneIgnorePlayer(PlayerId(), true) SetPoliceIgnorePlayer(PlayerId(), true) end
    Veyl.Notify('You are hiding. Press E or Backspace to climb out.', 'info')
    busy = false
    while hidden do
        Wait(0)
        DisableControlAction(0, 24, true) DisableControlAction(0, 25, true) DisableControlAction(0, 140, true) DisableControlAction(0, 141, true) DisableControlAction(0, 142, true)
        local p = PlayerPedId()
        if IsControlJustPressed(0, H.ExitKey or 38) or IsControlJustPressed(0, 177) or forced or GetGameTimer() > maxAt or IsEntityDead(p)
            or not DoesEntityExist(entity) or (H.HealthLossExits and GetEntityHealth(p) < health) then break end
        health = math.max(health, GetEntityHealth(p))
    end
    hidden = false
    ped = PlayerPedId()
    if H.NpcsIgnoreYou then SetEveryoneIgnorePlayer(PlayerId(), false) SetPoliceIgnorePlayer(PlayerId(), false) end
    FreezeEntityPosition(ped, false)
    SetEntityCollision(ped, true, true)
    SetEntityVisible(ped, true, false)
    SetEntityCoordsNoOffset(ped, back.x, back.y, back.z, false, false, false)
    Veyl.CallbackTimeout('veyl_scavenge', 'hideExit', 10000)
end

CreateThread(function()
    if not H.Enabled then return end
    while GetResourceState('veyl_target') ~= 'started' do Wait(500) end
    local models = {}
    for _, m in ipairs(H.Models) do if IsModelInCdimage(joaat(m)) then models[#models + 1] = m end end
    exports.veyl_target:addModel(models, {
        { name = 'veyl_scavenge_hide', label = H.Label, icon = H.Icon, distance = H.Distance or 2.2, priority = 1,
          canInteract = function() return not busy and not hidden and GetVehiclePedIsIn(PlayerPedId(), false) == 0 end,
          onSelect = function(d) CreateThread(function() hideIn(d.entity) end) end },
    })
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and hidden then
        local ped = PlayerPedId()
        SetEntityVisible(ped, true, false) SetEntityCollision(ped, true, true) FreezeEntityPosition(ped, false)
        SetEveryoneIgnorePlayer(PlayerId(), false) SetPoliceIgnorePlayer(PlayerId(), false)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for kind, def in pairs(C.Kinds) do pcall(function() exports.veyl_target:removeModel(def.Models, { 'veyl_scavenge_' .. kind }) end) end
end)
