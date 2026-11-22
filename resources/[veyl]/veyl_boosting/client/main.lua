-- veyl_boosting client: /boosting menu (and phone app), contract blips, hotwire / tracker options on the car.

local C = BoostingConfig
local areaBlip, dropBlip

local function clearBlips()
    if areaBlip and DoesBlipExist(areaBlip) then RemoveBlip(areaBlip) end
    if dropBlip and DoesBlipExist(dropBlip) then RemoveBlip(dropBlip) end
    areaBlip, dropBlip = nil, nil
end

local function showArea(x, y)
    clearBlips()
    areaBlip = AddBlipForRadius(x + math.random(-60, 60), y + math.random(-60, 60), 0.0, 150.0)
    SetBlipColour(areaBlip, 5)
    SetBlipAlpha(areaBlip, 110)
end

local function showDrop(x, y)
    clearBlips()
    dropBlip = AddBlipForCoord(x, y, 0.0)
    SetBlipSprite(dropBlip, 524)
    SetBlipColour(dropBlip, 5)
    SetBlipRoute(dropBlip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('Boost drop-off')
    EndTextCommandSetBlipName(dropBlip)
end

local function menu()
    local res = Veyl.Callback('veyl_boosting', 'status')
    if not res.ok then return Veyl.NotifyResult(res) end
    local d = res.data
    local items = { { label = ('Reputation %d · Class %s'):format(d.rep, d.class), disabled = true } }
    if d.active then
        items[#items + 1] = { label = ('Active: class %s %s'):format(d.active.class, d.active.model), description = ('%d min left'):format(d.active.minutesLeft), disabled = true }
        items[#items + 1] = { label = d.active.hotwired and 'GPS to the drop-off' or 'Show the search area', value = 'gps' }
        if d.active.hotwired then items[#items + 1] = { label = 'Deliver (park at the drop-off, get out)', value = 'deliver' } end
        items[#items + 1] = { label = 'Drop the contract', value = 'cancel' }
    else
        items[#items + 1] = { label = 'Take a contract', value = 'take' }
    end
    local choice = Veyl.UI.Menu({ title = 'Boosting', subtitle = 'Steal to order', items = items })
    if choice == 'take' then
        local r = Veyl.Callback('veyl_boosting', 'take')
        Veyl.NotifyResult(r)
        if r.ok then showArea(r.data.x, r.data.y) end
    elseif choice == 'gps' then
        if d.active.hotwired then showDrop(d.active.drop.x, d.active.drop.y) else showArea(d.active.area.x, d.active.area.y) end
    elseif choice == 'deliver' then
        local r = Veyl.Callback('veyl_boosting', 'deliver')
        Veyl.NotifyResult(r)
        if r.ok then clearBlips() end
    elseif choice == 'cancel' then
        Veyl.NotifyResult(Veyl.Callback('veyl_boosting', 'cancelContract'))
        clearBlips()
    end
end

RegisterCommand('boosting', function() CreateThread(menu) end, false)
AddEventHandler('veyl_boosting:menu', function() CreateThread(menu) end)
CreateThread(function()
    while GetResourceState('veyl_phone') ~= 'started' do Wait(1000) end
    pcall(function() exports.veyl_phone:RegisterApp({ id = 'boosting', label = 'Boosting', icon = 'car', color = '#3b1f4f', event = 'veyl_boosting:menu' }) end)
end)

local state = {} -- [netId] = { unlocked, hotwired } (display only; the server decides)
local busy = false

local function minigame()
    if GetResourceState('veyl_minigames') ~= 'started' then return true end
    local p = promise.new()
    exports.veyl_minigames:Lockpick({ difficulty = BoostingConfig.LockpickDifficulty or 'medium', title = 'Pick the door lock' }, function(ok) p:resolve(ok) end)
    return Citizen.Await(p) == true
end

local function act(kind, entity)
    if busy then return end
    busy = true
    local netId = NetworkGetNetworkIdFromEntity(entity)
    if kind == 'lockpick' then
        -- Check first (right car, lockpick in pockets), then the mini game, then the short timed pick.
        if (exports.veyl_inventory:GetItemCount(BoostingConfig.HotwireItem) or 0) < 1 then busy = false return Veyl.Notify('You need a lockpick', 'error') end
        TaskTurnPedToFaceEntity(PlayerPedId(), entity, 600)
        Wait(600)
        if Veyl.LoadAnimDict('mp_arresting') then TaskPlayAnim(PlayerPedId(), 'mp_arresting', 'a_uncuff', 3.0, 3.0, -1, 49, 0, false, false, false) end
        local ok = minigame()
        ClearPedTasks(PlayerPedId())
        if not ok then
            Veyl.NotifyResult(Veyl.Callback('veyl_boosting', 'pickFailed', netId))
            busy = false
            return
        end
    end
    local start = Veyl.CallbackTimeout('veyl_boosting', 'actStart', 10000, kind, netId)
    if not start.ok then busy = false return Veyl.NotifyResult(start) end
    local labels = { hotwire = 'Hotwiring', lockpick = 'Opening the door', tracker = 'Disabling the tracker' }
    local anim = kind == 'hotwire' and { dict = 'veh@std@ds@base', clip = 'hotwire', flag = 1 }
        or kind == 'lockpick' and { dict = 'mp_arresting', clip = 'a_uncuff', flag = 49 }
        or { dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', clip = 'machinic_loop_mechandplayer', flag = 1 }
    local done = vlib.progress({ label = labels[kind], duration = start.data.seconds * 1000, canCancel = true,
        disable = { move = true, car = kind == 'hotwire', combat = true }, anim = anim })
    ClearPedTasks(PlayerPedId())
    busy = false
    if not done then return Veyl.Notify('Stopped', 'info') end
    local r = Veyl.CallbackTimeout('veyl_boosting', 'actFinish', 10000, start.data.token)
    Veyl.NotifyResult(r)
    if r.ok then
        state[netId] = state[netId] or {}
        if kind == 'lockpick' then state[netId].unlocked = true end
        if kind == 'hotwire' then state[netId].hotwired, state[netId].unlocked = true, true end
    end
    if r.ok and r.data and r.data.drop then showDrop(r.data.drop.x, r.data.drop.y) end
end

CreateThread(function()
    while GetResourceState('veyl_target') ~= 'started' do Wait(250) end
    local function isContract(entity) return (GetVehicleNumberPlateText(entity) or ''):find('BST', 1, true) ~= nil end
    exports.veyl_target:addGlobalVehicle({
        { name = 'veyl_boost_lockpick', label = 'Lockpick door', icon = 'lock', distance = 2.5, priority = 3,
          canInteract = function(e)
              local st = state[NetworkGetNetworkIdFromEntity(e)]
              return isContract(e) and not busy and GetVehiclePedIsIn(PlayerPedId(), false) == 0 and not (st and st.unlocked) and GetVehicleDoorLockStatus(e) >= 2
          end,
          onSelect = function(d) CreateThread(function() act('lockpick', d.entity) end) end },
        { name = 'veyl_boost_tracker', label = 'Disable tracker', icon = 'gear', distance = 2.5, priority = 2,
          canInteract = function(e) return isContract(e) end, onSelect = function(d) CreateThread(function() act('tracker', d.entity) end) end },
    })
end)

-- Hotwire from the driver seat of the contract car (you cannot target the car you sit in): press H.
CreateThread(function()
    local shown = false
    while true do
        local sleep = 800
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        local want = false
        if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped and (GetVehicleNumberPlateText(veh) or ''):find('BST', 1, true) then
            local st = state[NetworkGetNetworkIdFromEntity(veh)]
            if not (st and st.hotwired) and not busy then
                want, sleep = true, 0
                if IsControlJustReleased(0, 74) then CreateThread(function() act('hotwire', veh) end) end
            end
        end
        if want ~= shown then
            if want then vlib.showTextUI('Hotwire', 'H') else vlib.hideTextUI() end
            shown = want
        end
        Wait(sleep)
    end
end)
