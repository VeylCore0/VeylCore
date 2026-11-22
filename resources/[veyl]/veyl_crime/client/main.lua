-- veyl_crime client: dark web app, dead drops, USB dealer, fence, laundromat, drug corners, turf, labs.

local C = CrimeConfig

local function money(n) return ('$%d'):format(math.floor(n or 0)) end

---------------------------------------------------------------------------
-- Dark web (phone app and /darkweb)
---------------------------------------------------------------------------
local function darkweb()
    if (exports.veyl_inventory:GetItemCount(C.DarkWeb.UnlockItem) or 0) < 1 then return Veyl.Notify('No signal.', 'error') end
    local res = Veyl.Callback('veyl_crime', 'darkweb')
    if not res.ok then return Veyl.NotifyResult(res) end
    local items = {}
    for _, o in ipairs(res.data.orders) do
        items[#items + 1] = { label = ('Order #%d waiting'):format(o.id), description = 'Set GPS to the drop', value = 'drop:' .. o.id, x = o.x, y = o.y }
    end
    for _, c in ipairs(res.data.catalog) do
        items[#items + 1] = { label = c.label, right = money(c.price), value = 'buy:' .. c.index }
    end
    local choice = Veyl.UI.Menu({ title = 'Silk Road LS', subtitle = 'Cash only. Pick up at the drop.', items = items })
    if not choice then return end
    if choice:sub(1, 5) == 'drop:' then
        for _, it in ipairs(items) do if it.value == choice then SetNewWaypoint(it.x, it.y) Veyl.Notify('GPS set to the drop', 'success') end end
        return
    end
    local index = tonumber(choice:sub(5))
    local v = vlib.inputDialog('Order', { { name = 'n', label = 'How many', type = 'number', required = true, min = 1, max = 250, default = 1 } }, { submitLabel = 'Pay' })
    if not v then return end
    local r = Veyl.CallbackTimeout('veyl_crime', 'order', 15000, index, tonumber(v.n))
    Veyl.NotifyResult(r)
    if r.ok then SetNewWaypoint(r.data.x, r.data.y) end
end

RegisterCommand('darkweb', function() CreateThread(darkweb) end, false)
AddEventHandler('veyl_crime:darkweb', function() CreateThread(darkweb) end)
CreateThread(function()
    while GetResourceState('veyl_phone') ~= 'started' do Wait(1000) end
    pcall(function() exports.veyl_phone:RegisterApp({ id = 'darkweb', label = 'Silk Road', icon = 'eye', color = '#1b1b1f', event = 'veyl_crime:darkweb' }) end)
end)

---------------------------------------------------------------------------
-- Points: dealer, fence, laundromat, drops, labs, gang stashes
---------------------------------------------------------------------------
local function cb(name, ...) local args = { ... } CreateThread(function() Veyl.NotifyResult(Veyl.CallbackTimeout('veyl_crime', name, 15000, table.unpack(args))) end) end

local function timed(startName, finishName, label, scenario, ...)
    local start = Veyl.CallbackTimeout('veyl_crime', startName, 10000, ...)
    if not start.ok then return Veyl.NotifyResult(start) end
    if scenario then TaskStartScenarioInPlace(PlayerPedId(), scenario, 0, true) end
    local done = vlib.progress({ label = label, duration = start.data.seconds * 1000, canCancel = true, disable = { move = true, car = true, combat = true } })
    ClearPedTasks(PlayerPedId())
    if not done then return Veyl.Notify('Stopped', 'info') end
    Veyl.NotifyResult(Veyl.CallbackTimeout('veyl_crime', finishName, 10000, start.data.token))
end

AddEventHandler('veyl_crime:usb', function() cb('buyUsb') end)
AddEventHandler('veyl_crime:fence', function() cb('fence') end)
AddEventHandler('veyl_crime:collect', function() cb('collect') end)
AddEventHandler('veyl_crime:wash', function() CreateThread(function() timed('washStart', 'washFinish', 'Washing money', 'PROP_HUMAN_BUM_BIN') end) end)
AddEventHandler('veyl_crime:cook', function(a) CreateThread(function() timed('cookStart', 'cookFinish', C.Labs[a.index].label, 'PROP_HUMAN_BBQ', a.index) end) end)
AddEventHandler('veyl_crime:gangstash', function(a) exports.veyl_inventory:openInventory('stash', 'gang_' .. a.gang) end)

CreateThread(function()
    while GetResourceState('veyl_interact') ~= 'started' do Wait(250) end
    local u, f = C.UsbDealer, C.Fence
    exports.veyl_interact:AddPed({ id = 'veyl_crime_usb', model = u.model, coords = u.coords, radius = 2.0, title = 'Shady guy',
        options = { { label = ('Buy a USB drive (%s cash)'):format(money(u.price)), icon = 'eye', event = 'veyl_crime:usb' } } })
    exports.veyl_interact:AddPed({ id = 'veyl_crime_fence', model = f.model, coords = f.coords, radius = 2.0, title = 'Fence',
        options = { { label = 'Sell jewelry', icon = 'money', event = 'veyl_crime:fence' } } })
    exports.veyl_interact:AddZone({ id = 'veyl_crime_wash', coords = C.Laundering.coords, radius = 1.5, title = 'Laundromat',
        options = { { label = 'Wash marked bills', icon = 'money', event = 'veyl_crime:wash' } } })
    for i, d in ipairs(C.DarkWeb.Drops) do
        exports.veyl_interact:AddZone({ id = 'veyl_crime_drop_' .. i, coords = d, radius = 1.5, title = 'Dumpster',
            options = { { label = 'Search', icon = 'search', event = 'veyl_crime:collect' } } })
    end
    for i, lab in ipairs(C.Labs) do
        exports.veyl_interact:AddZone({ id = 'veyl_crime_lab_' .. i, coords = lab.coords, radius = 1.5, title = lab.label,
            options = { { label = 'Cook a batch', icon = 'gear', event = 'veyl_crime:cook', args = { index = i } } } })
    end
    for gang, s in pairs(C.GangStashes) do
        exports.veyl_interact:AddZone({ id = 'veyl_crime_gang_' .. gang, coords = s.coords, radius = 1.5, title = s.label,
            options = { { label = 'Open stash', icon = 'box', event = 'veyl_crime:gangstash', args = { gang = gang }, groups = { [gang] = 0 } } } })
    end
end)

---------------------------------------------------------------------------
-- Drug corners: offer to a local
---------------------------------------------------------------------------
local asked = {}
local function hasDrugs()
    for item in pairs(C.Corners.Products) do if (exports.veyl_inventory:GetItemCount(item) or 0) > 0 then return true end end
    return false
end

CreateThread(function()
    while GetResourceState('veyl_target') ~= 'started' do Wait(250) end
    exports.veyl_target:addGlobalPed({
        { name = 'veyl_crime_sell', label = 'Offer drugs', icon = 'hand', distance = 2.0, priority = 1,
          canInteract = function(ped)
              return not IsPedAPlayer(ped) and not asked[ped] and not IsPedInAnyVehicle(ped, false) and IsPedHuman(ped)
                  and not IsPedDeadOrDying(ped, true) and not IsPedInAnyVehicle(PlayerPedId(), false) and hasDrugs()
          end,
          onSelect = function(data) CreateThread(function()
              local ped = data.entity
              asked[ped] = true
              ClearPedTasks(ped)
              TaskTurnPedToFaceEntity(ped, PlayerPedId(), 1500)
              Wait(1200)
              local res = Veyl.Callback('veyl_crime', 'sell')
              if res.ok and res.data.outcome == 'buy' then
                  RequestAnimDict('mp_common')
                  local t = GetGameTimer() + 1000
                  while not HasAnimDictLoaded('mp_common') and GetGameTimer() < t do Wait(10) end
                  TaskPlayAnim(PlayerPedId(), 'mp_common', 'givetake1_a', 8.0, -8.0, 2000, 48, 0, false, false, false)
                  TaskPlayAnim(ped, 'mp_common', 'givetake1_b', 8.0, -8.0, 2000, 48, 0, false, false, false)
              elseif res.ok and res.data.outcome == 'police' then
                  TaskSmartFleePed(ped, PlayerPedId(), 100.0, -1, false, false)
              end
              Veyl.NotifyResult(res)
              SetPedAsNoLongerNeeded(ped)
          end) end },
    })
end)

RegisterCommand('turf', function()
    CreateThread(function()
        local res = Veyl.Callback('veyl_crime', 'turf')
        if not res.ok then return Veyl.NotifyResult(res) end
        local items = {}
        for i, z in ipairs(res.data) do items[i] = { label = z.label, right = z.gang or 'Nobody', disabled = true } end
        Veyl.UI.Menu({ title = 'Turf', subtitle = 'Who controls each area', items = items })
    end)
end, false)

RegisterCommand('tag', function() cb('tag') end, false)
RegisterNetEvent('veyl_crime:tag', function() cb('tag') end)
