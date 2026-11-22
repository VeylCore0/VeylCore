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

local function act(kind, entity)
    local netId = NetworkGetNetworkIdFromEntity(entity)
    local start = Veyl.CallbackTimeout('veyl_boosting', 'actStart', 10000, kind, netId)
    if not start.ok then return Veyl.NotifyResult(start) end
    local done = vlib.progress({ label = kind == 'hotwire' and 'Hotwiring' or 'Disabling the tracker', duration = start.data.seconds * 1000, canCancel = true,
        disable = { move = true, car = false, combat = true }, anim = { dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', clip = 'machinic_loop_mechandplayer', flag = 1 } })
    ClearPedTasks(PlayerPedId())
    if not done then return Veyl.Notify('Stopped', 'info') end
    local r = Veyl.CallbackTimeout('veyl_boosting', 'actFinish', 10000, start.data.token)
    Veyl.NotifyResult(r)
    if r.ok and r.data and r.data.drop then showDrop(r.data.drop.x, r.data.drop.y) end
end

CreateThread(function()
    while GetResourceState('veyl_target') ~= 'started' do Wait(250) end
    local function isContract(entity) return (GetVehicleNumberPlateText(entity) or ''):find('BST', 1, true) ~= nil end
    exports.veyl_target:addGlobalVehicle({
        { name = 'veyl_boost_hotwire', label = 'Hotwire (contract)', icon = 'key', distance = 2.5, priority = 3,
          canInteract = function(e) return isContract(e) end, onSelect = function(d) CreateThread(function() act('hotwire', d.entity) end) end },
        { name = 'veyl_boost_tracker', label = 'Disable tracker', icon = 'gear', distance = 2.5, priority = 2,
          canInteract = function(e) return isContract(e) end, onSelect = function(d) CreateThread(function() act('tracker', d.entity) end) end },
    })
end)
