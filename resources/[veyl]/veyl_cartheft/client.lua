-- veyl_cartheft client: locks ambient cars, runs the three ways in (a gun on the driver, a lockpick, a hotwire) and draws the peds' reactions.
-- Every attempt starts and ends with the server, which checks timing and gives the keys; nothing here grants anything.

local C = CartheftConfig
local keys = {}            -- plates the server says are mine
local seen = {}            -- vehicle handles already looked at by the locking loop
local mine = {}            -- vehicles I unlocked (kept unlocked even when the loop passes again)
local jacking = {}         -- vehicles I am currently threatening
local busy = false

RegisterNetEvent('veyl_cartheft:keys', function(list)
    keys = {}
    for _, p in ipairs(list or {}) do keys[p] = true end
end)

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function plateOf(veh) return (GetVehicleNumberPlateText(veh) or ''):gsub('[^%w]', ''):upper() end
local function managed(veh) return Entity(veh).state.veylVehicleId ~= nil end
local function theft(veh)
    return DoesEntityExist(veh) and IsEntityAVehicle(veh) and not managed(veh) and not C.Lock.ExcludeClasses[GetVehicleClass(veh)]
end
local function haveKey(veh) return keys[plateOf(veh)] == true end

local function control(e)
    if NetworkHasControlOfEntity(e) then return true end
    NetworkRequestControlOfEntity(e)
    local t = GetGameTimer() + 800
    while not NetworkHasControlOfEntity(e) and GetGameTimer() < t do Wait(20) end
    return NetworkHasControlOfEntity(e)
end

local function play(fnName, opts)
    local p = promise.new()
    exports.veyl_minigames[fnName](exports.veyl_minigames, opts, function(ok) p:resolve(ok == true) end)
    return Citizen.Await(p)
end

local function helpText(text)
    BeginTextCommandDisplayHelp('STRING')
    AddTextComponentSubstringPlayerName(text)
    EndTextCommandDisplayHelp(0, false, true, -1)
end

local function anim(dict, clip, ms)
    RequestAnimDict(dict)
    local t = GetGameTimer() + 1500
    while not HasAnimDictLoaded(dict) and GetGameTimer() < t do Wait(10) end
    if HasAnimDictLoaded(dict) then TaskPlayAnim(PlayerPedId(), dict, clip, 3.0, 3.0, ms or -1, 49, 0, false, false, false) end
end

---------------------------------------------------------------------------
-- Everything ambient is locked
---------------------------------------------------------------------------
local function lock(veh)
    if haveKey(veh) or mine[veh] then return end
    SetVehicleDoorsLocked(veh, 2)
    SetVehicleDoorsLockedForAllPlayers(veh, true)
end

CreateThread(function()
    while not Veyl.IsLoaded() do Wait(1000) end
    local res = Veyl.CallbackTimeout('veyl_cartheft', 'keys', 10000)
    if res.ok and type(res.data) == 'table' then for _, p in ipairs(res.data) do keys[p] = true end end
    local sweep = 0
    while true do
        Wait(1500)
        if C.Lock.Enabled then
            local ped = PlayerPedId()
            local pc = GetEntityCoords(ped)
            local mineNow = GetVehiclePedIsIn(ped, false)
            for _, veh in ipairs(GetGamePool('CVehicle')) do
                if veh ~= mineNow and theft(veh) and #(pc - GetEntityCoords(veh)) <= C.Lock.Radius then
                    -- Look once at every car that comes into range; keep a car locked while it is near unless I own its door.
                    if not seen[veh] or (GetVehicleDoorLockStatus(veh) < 2 and not mine[veh] and not haveKey(veh) and #(pc - GetEntityCoords(veh)) < 30.0) then
                        local occupied = false
                        for seat = -1, GetVehicleMaxNumberOfPassengers(veh) - 1 do
                            local who = GetPedInVehicleSeat(veh, seat)
                            if who ~= 0 and IsPedAPlayer(who) then occupied = true break end
                        end
                        if not occupied then lock(veh) end
                        seen[veh] = true
                    end
                end
            end
            sweep = sweep + 1
            if sweep % 20 == 0 then
                for h in pairs(seen) do if not DoesEntityExist(h) then seen[h] = nil mine[h] = nil jacking[h] = nil end end
            end
        end
    end
end)

---------------------------------------------------------------------------
-- A lockpick on a parked car
---------------------------------------------------------------------------
local function lockpick(veh)
    if busy then return end
    busy = true
    local res = Veyl.CallbackTimeout('veyl_cartheft', 'lockpickStart', 10000, VehToNet(veh))
    if not res.ok then busy = false return Veyl.NotifyResult(res) end
    TaskTurnPedToFaceEntity(PlayerPedId(), veh, 600)
    Wait(600)
    anim('mini@repair', 'fixing_a_ped')
    local ok = play('CarLockpick', { difficulty = res.data.difficulty, title = 'Slip the lock', subtitle = 'Feel for the tumblers' })
    ClearPedTasks(PlayerPedId())
    local fin = Veyl.CallbackTimeout('veyl_cartheft', 'lockpickFinish', 10000, res.data.token, ok)
    busy = false
    if fin.ok then
        mine[veh] = true
        SetVehicleDoorsLockedForAllPlayers(veh, false)
        SetVehicleDoorsLocked(veh, 1)
    end
    local alarm = (fin.data and fin.data.alarm) == true
    if alarm and DoesEntityExist(veh) then StartVehicleAlarm(veh) SetVehicleAlarmTimeLeft(veh, 12000) end
    Veyl.NotifyResult(fin)
end

CreateThread(function()
    while GetResourceState('veyl_target') ~= 'started' do Wait(500) end
    exports.veyl_target:addGlobalVehicle({
        { name = 'veyl_cartheft_lockpick', label = 'Lockpick the door', icon = 'key', distance = C.Lockpick.Distance, priority = 1,
          canInteract = function(e)
              if busy or mine[e] or not theft(e) or GetVehicleDoorLockStatus(e) < 2 or haveKey(e) then return false end
              local driver = GetPedInVehicleSeat(e, -1)
              if driver ~= 0 and not IsPedDeadOrDying(driver, true) then return false end
              return (exports.veyl_inventory:GetItemCount(C.Lockpick.Item) or 0) > 0
          end,
          onSelect = function(d) CreateThread(function() lockpick(d.entity) end) end },
    })
end)

---------------------------------------------------------------------------
-- No keys, no engine: hotwire from the driver's seat
---------------------------------------------------------------------------
local function hotwire(veh)
    if busy then return end
    busy = true
    local res = Veyl.CallbackTimeout('veyl_cartheft', 'hotwireStart', 10000, VehToNet(veh))
    if not res.ok then busy = false return Veyl.NotifyResult(res) end
    anim('mini@repair', 'fixing_a_ped')
    local ok = play('Hotwire', { difficulty = res.data.difficulty, title = 'Hotwire', subtitle = 'Match every wire to its terminal' })
    ClearPedTasks(PlayerPedId())
    local fin = Veyl.CallbackTimeout('veyl_cartheft', 'hotwireFinish', 10000, res.data.token, ok)
    busy = false
    Veyl.NotifyResult(fin)
    if fin.ok and DoesEntityExist(veh) then SetVehicleEngineOn(veh, true, false, false) end
end

CreateThread(function()
    while true do
        local sleep = 400
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped and theft(veh) and not haveKey(veh) then
            sleep = 0
            SetVehicleEngineOn(veh, false, true, true)
            DisableControlAction(0, 71, true)
            if not busy then
                helpText('This car has no keys. Press ~INPUT_VEH_HEADLIGHT~ to hotwire it')
                if IsDisabledControlJustPressed(0, 74) or IsControlJustPressed(0, 74) then CreateThread(function() hotwire(veh) end) end
            end
        end
        Wait(sleep)
    end
end)

---------------------------------------------------------------------------
-- A gun on the driver
---------------------------------------------------------------------------
local function carjack(veh, driver)
    jacking[veh] = true
    local ped = PlayerPedId()
    local res = Veyl.CallbackTimeout('veyl_cartheft', 'carjackStart', 10000, VehToNet(veh))
    if not res.ok then
        SetTimeout(8000, function() jacking[veh] = nil end)
        return Veyl.NotifyResult(res)
    end
    control(driver) control(veh)
    ClearPedTasks(driver)
    SetBlockingOfNonTemporaryEvents(driver, true)
    TaskVehicleTempAction(driver, veh, 6, res.data.holdMs + 1500)
    TaskHandsUp(driver, res.data.holdMs + 1500, ped, -1, true)
    local t0, held = GetGameTimer(), true
    while GetGameTimer() - t0 < res.data.holdMs do
        Wait(100)
        if not IsPlayerFreeAiming(PlayerId()) or IsPedDeadOrDying(ped, true) or IsPedDeadOrDying(driver, true) or #(GetEntityCoords(ped) - GetEntityCoords(veh)) > C.Carjack.Range + 6.0 then held = false break end
    end
    if not held then
        -- You lowered the gun: they get their nerve back and drive off.
        if DoesEntityExist(driver) then ClearPedTasks(driver) SetBlockingOfNonTemporaryEvents(driver, false) TaskVehicleDriveWander(driver, veh, 30.0, 786603) end
        SetTimeout(8000, function() jacking[veh] = nil end)
        return Veyl.Notify('You lost your nerve', 'warning')
    end
    local fin = Veyl.CallbackTimeout('veyl_cartheft', 'carjackFinish', 10000, res.data.token)
    if not DoesEntityExist(driver) or not DoesEntityExist(veh) then jacking[veh] = nil return end
    if fin.ok and fin.data and fin.data.gave then
        mine[veh] = true
        SetVehicleDoorsLockedForAllPlayers(veh, false)
        SetVehicleDoorsLocked(veh, 1)
        TaskLeaveVehicle(driver, veh, 256)
        Wait(900)
        SetBlockingOfNonTemporaryEvents(driver, false)
        TaskSmartFleePed(driver, ped, 80.0, -1, false, false)
        Veyl.NotifyResult(fin)
    else
        ClearPedTasks(driver)
        SetBlockingOfNonTemporaryEvents(driver, false)
        TaskVehicleDriveWander(driver, veh, 45.0, 786603)
        Veyl.Notify('They floor it!', 'warning')
    end
    SetTimeout(8000, function() jacking[veh] = nil end)
end

CreateThread(function()
    while not Veyl.IsLoaded() do Wait(1000) end
    while true do
        local sleep = 500
        local ped = PlayerPedId()
        if C.Carjack.Enabled and IsPedArmed(ped, 4) and IsPlayerFreeAiming(PlayerId()) then
            sleep = 100
            local has, ent = GetEntityPlayerIsFreeAimingAt(PlayerId())
            if has and ent ~= 0 and IsEntityAPed(ent) and not IsPedAPlayer(ent) and IsPedInAnyVehicle(ent, false) then
                local veh = GetVehiclePedIsIn(ent, false)
                if GetPedInVehicleSeat(veh, -1) == ent and theft(veh) and not haveKey(veh) and not mine[veh] and not jacking[veh]
                    and #(GetEntityCoords(ped) - GetEntityCoords(veh)) <= C.Carjack.Range then
                    CreateThread(function() carjack(veh, ent) end)
                end
            end
        end
        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    pcall(function() exports.veyl_target:removeGlobalVehicle({ 'veyl_cartheft_lockpick' }) end)
end)
