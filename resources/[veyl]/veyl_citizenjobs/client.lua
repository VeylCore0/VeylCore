-- veyl_citizenjobs client: depots, blips and markers, carrying bags, taxi passengers and the tow hook. The server decides.

local C = CitizenJobsConfig
local run = nil
local blip, bagProp, passenger = nil, nil, nil

local function cb(name, ...) return Veyl.CallbackTimeout('veyl_citizenjobs', name, 15000, ...) end

local function clearBlip() if blip then RemoveBlip(blip) blip = nil end end
local function setBlip(pos, label, colour)
    clearBlip()
    if not pos then return end
    blip = AddBlipForCoord(pos.x, pos.y, pos.z)
    SetBlipSprite(blip, 1)
    SetBlipColour(blip, colour or 5)
    SetBlipRoute(blip, true)
    SetBlipRouteColour(blip, colour or 5)
    BeginTextCommandSetBlipName('STRING') AddTextComponentSubstringPlayerName(label) EndTextCommandSetBlipName(blip)
end

local function dropBag()
    if bagProp then DeleteEntity(bagProp) bagProp = nil end
    StopAnimTask(PlayerPedId(), 'anim@heists@narcotics@trash', 'walk', 1.0)
end
local function carryBag()
    if bagProp then return end
    local ped = PlayerPedId()
    local hash = Veyl.LoadModel('prop_cs_rub_binbag_01', 5000)
    if not hash then return end
    bagProp = CreateObject(hash, 0.0, 0.0, 0.0, true, true, false)
    AttachEntityToEntity(bagProp, ped, GetPedBoneIndex(ped, 57005), 0.12, 0.0, -0.05, 220.0, 120.0, 0.0, true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(hash)
    if Veyl.LoadAnimDict('anim@heists@narcotics@trash') then TaskPlayAnim(ped, 'anim@heists@narcotics@trash', 'walk', 1.0, -1.0, -1, 49, 0, false, false, false) end
end

local function removePassenger(walkAway)
    if not passenger then return end
    local p = passenger
    passenger = nil
    if DoesEntityExist(p) then
        if walkAway then
            TaskLeaveVehicle(p, GetVehiclePedIsIn(p, false), 0)
            SetTimeout(2500, function() if DoesEntityExist(p) then TaskWanderStandard(p, 10.0, 10) SetPedAsNoLongerNeeded(p) end end)
        else DeleteEntity(p) end
    end
end

local function vehicle() return run and NetworkDoesEntityExistWithNetworkId(run.netId) and NetToVeh(run.netId) or 0 end

--- Taxi: a local passenger waits at the pickup and gets in when you arrive.
--- A waiting spot on the kerb next to the pickup: the nearest pavement point (GetSafeCoordForPed, pavement only),
--- otherwise the edge of the nearest road stepped 1.5 m off it. Returns the spot and a heading that faces the road.
local function curbSpot(pos)
    local _, node = GetClosestVehicleNode(pos.x, pos.y, pos.z, 1, 3.0, 0)
    local spot
    local ok, safe = GetSafeCoordForPed(pos.x, pos.y, pos.z, true, 16)
    if ok and #(safe - pos) < 14.0 then
        spot = safe
    else
        local found, side = GetPointOnRoadSide(pos.x, pos.y, pos.z, 0)
        if found and node then
            local dir = vector3(side.x - node.x, side.y - node.y, 0.0)
            local len = #dir
            spot = len > 0.1 and (side + dir / len * 1.5) or side
        end
    end
    spot = spot or pos
    local heading = node and GetHeadingFromVector_2d(node.x - spot.x, node.y - spot.y) or 0.0
    return spot, heading
end

local function spawnPassenger(pos, model)
    removePassenger(false)
    local hash = Veyl.LoadModel(model, 5000)
    if not hash then return end
    RequestCollisionAtCoord(pos.x, pos.y, pos.z)
    local spot, heading = curbSpot(vector3(pos.x, pos.y, pos.z))
    local found, z = GetGroundZFor_3dCoord(spot.x, spot.y, spot.z + 2.0, false)
    passenger = CreatePed(4, hash, spot.x, spot.y, found and z or spot.z, heading, false, true)
    SetBlockingOfNonTemporaryEvents(passenger, true)
    SetPedCanRagdoll(passenger, false)
    TaskStartScenarioInPlace(passenger, 'WORLD_HUMAN_STAND_MOBILE', 0, true)
    SetModelAsNoLongerNeeded(hash)
end

--- Tow: the broken-down vehicle sits on the flatbed while you drive.
local function attachTow(on)
    if not run or not run.towNet or not NetworkDoesEntityExistWithNetworkId(run.towNet) then return end
    local target, bed = NetToVeh(run.towNet), vehicle()
    if target == 0 or bed == 0 then return end
    NetworkRequestControlOfEntity(target)
    local deadline = GetGameTimer() + 2000
    while not NetworkHasControlOfEntity(target) and GetGameTimer() < deadline do Wait(50) NetworkRequestControlOfEntity(target) end
    if on then
        AttachEntityToEntity(target, bed, GetEntityBoneIndexByName(bed, 'bodyshell'), 0.0, -2.2, 1.05, 0.0, 0.0, 0.0, false, false, false, false, 20, true)
    else
        DetachEntity(target, true, true)
    end
end

local function refresh(data)
    run = data
    clearBlip()
    if not run then dropBag() removePassenger(false) return end
    local cfg = C.Jobs[run.job]
    if run.kind == 'haul' then
        setBlip(run.target, run.step == 'deliver' and 'Drop-off' or 'Depot', 21)
    elseif run.kind == 'bins' then
        if run.target then setBlip(run.target, 'Depot (quota done)', 25) end
        if run.carrying then carryBag() else dropBag() end
    elseif run.kind == 'fare' then
        setBlip(run.target, run.step == 'pickup' and 'Passenger' or 'Destination', 5)
        -- The passenger appears when you get close (the area has to be loaded to find the pavement).
    elseif run.kind == 'tow' then
        setBlip(run.target, run.step == 'hook' and 'Breakdown' or 'Tow yard', 47)
    end
    if cfg and run.kind ~= 'bins' then dropBag() end
end

-- Markers and prompts near the current target -----------------------------------------------
local busy = false
local function act(action, label, ms, arg)
    if busy then return end
    busy = true
    CreateThread(function()
        if ms and ms > 0 then
            local ok = vlib.progress({ label = label, duration = ms, canCancel = true, disable = { move = true, car = action ~= 'pickup' and action ~= 'dropoff', combat = true } })
            if not ok then busy = false return end
        end
        local res = cb('act', action, arg)
        Veyl.NotifyResult(res)
        if res.ok and res.data then
            if action == 'pickup' and passenger then
                local veh = vehicle()
                ClearPedTasks(passenger)
                TaskEnterVehicle(passenger, veh, 10000, 2, 1.0, 1, 0)
            elseif action == 'dropoff' then removePassenger(true)
            elseif action == 'hook' then attachTow(true)
            elseif action == 'drop' then attachTow(false)
            end
            refresh(res.data)
        elseif res.ok then refresh(nil) end
        busy = false
    end)
end

CreateThread(function()
    while true do
        local sleep = 1000
        if run and (run.target or run.kind == 'bins') then
            local ped = PlayerPedId()
            local pc = GetEntityCoords(ped)
            local t = run.target
            local d = t and #(pc - vector3(t.x, t.y, t.z)) or math.huge
            local inVeh = GetVehiclePedIsIn(ped, false)
            local myVeh = vehicle()
            if run.kind == 'fare' and run.step == 'pickup' and not passenger and d < 150.0 then spawnPassenger(t, run.ped) end
            if d < 60.0 then
                sleep = 0
                DrawMarker(1, t.x, t.y, t.z - 1.0, 0, 0, 0, 0, 0, 0, 4.0, 4.0, 1.0, 245, 200, 80, 90, false, false, 2, false, nil, nil, false)
            end
            local prompt, action, label, ms
            if run.kind == 'haul' and run.step == 'deliver' and d < 10.0 and inVeh == 0 then
                prompt, action, label, ms = 'Unload the truck', 'unload', 'Unloading', C.Jobs.trucker.unloadSeconds * 1000
            elseif run.kind == 'bins' then
                -- Taking trash is on the bins themselves (target any trash can or dumpster).
                if run.carrying and myVeh ~= 0 and #(pc - GetEntityCoords(myVeh)) < 6.0 then prompt, action, label, ms = 'Throw the bag in the truck', 'throw', 'Throwing', 1200 end
                if run.carrying then sleep = 0 end
            elseif run.kind == 'fare' and inVeh ~= 0 and inVeh == myVeh and d < 15.0 then
                if run.step == 'pickup' then prompt, action = 'Pick up the passenger', 'pickup' else prompt, action = 'Drop off the passenger', 'dropoff' end
            elseif run.kind == 'tow' then
                if run.step == 'hook' and inVeh == 0 and run.towNet and NetworkDoesEntityExistWithNetworkId(run.towNet) and #(pc - GetEntityCoords(NetToVeh(run.towNet))) < 6.0 then
                    prompt, action, label, ms = 'Hook the vehicle', 'hook', 'Winching', 5000
                    sleep = 0
                elseif run.step == 'deliver' and d < C.Jobs.tow.yardRadius then prompt, action, label, ms = 'Drop the vehicle', 'drop', 'Unhooking', 4000 end
            end
            if prompt and not busy then
                sleep = 0
                vlib.showTextUI(prompt, 'E')
                if IsControlJustReleased(0, 38) then vlib.hideTextUI() act(action, label, ms) end
            else
                vlib.hideTextUI()
            end
        end
        Wait(sleep)
    end
end)

-- Depots -----------------------------------------------------------------------------------
local function start(job)
    local cfg = C.Jobs[job]
    local text = {
        haul = ('Take a load across the state. $%d plus $%d per km, and $%d for bringing the truck back.'):format(cfg.base or 0, cfg.perKm or 0, cfg.returnBonus or 0),
        bins = ('Take trash from any trash can or dumpster (with your truck nearby) and throw it in the truck. $%d per bag, $%d bonus for %d bags. Recyclables sometimes turn up.'):format(cfg.payPerBag or 0, cfg.completionBonus or 0, cfg.quota or 0),
        fare = ('Pick up fares around the city. $%d plus $%d per km and tips.'):format(cfg.base or 0, cfg.perKm or 0),
        tow = ('Tow broken-down vehicles to the yard. $%d per tow.'):format(cfg.payPerTow or 0),
    }
    if not Veyl.UI.Confirm({ title = cfg.label, message = text[cfg.kind], confirmLabel = 'Start shift' }) then return end
    local res = cb('start', job)
    Veyl.NotifyResult(res)
    if res.ok then refresh(res.data) end
end

-- Garbage: every trash can and dumpster is a target during a sanitation shift.
CreateThread(function()
    while GetResourceState('veyl_target') ~= 'started' do Wait(500) end
    local g = C.Jobs.garbage
    if not g or not g.binModels then return end
    exports.veyl_target:addModel(g.binModels, {
        { name = 'veyl_cjob_bin', label = 'Take the trash', icon = 'hand', distance = 2.5, priority = 4,
          canInteract = function() return run ~= nil and run.kind == 'bins' and not run.carrying and not busy and GetVehiclePedIsIn(PlayerPedId(), false) == 0 end,
          onSelect = function(d)
              local c = GetEntityCoords(d.entity)
              act('bag', 'Grabbing the trash', 2500, { x = c.x, y = c.y, z = c.z })
          end },
    })
end)

AddEventHandler('veyl_citizenjobs:start', function(a) CreateThread(function() start(a.job) end) end)
AddEventHandler('veyl_citizenjobs:finish', function()
    CreateThread(function()
        local res = cb('finish')
        Veyl.NotifyResult(res)
        if res.ok then if run and run.kind == 'tow' then attachTow(false) end refresh(nil) end
    end)
end)
AddEventHandler('veyl_citizenjobs:cancel', function()
    CreateThread(function()
        if not Veyl.UI.Confirm({ title = 'Cancel shift', message = 'Cancel? Unfinished work is not paid.' }) then return end
        local res = cb('cancel')
        Veyl.NotifyResult(res)
        if res.ok then refresh(nil) end
    end)
end)

RegisterNetEvent('veyl_citizenjobs:ended', function(reason, earned)
    if run and reason ~= 'finished' then Veyl.Notify(('Your shift ended (%s). Earned $%d.'):format(reason:gsub('_', ' '), earned or 0), 'warning', 6000) end
    vlib.hideTextUI()
    refresh(nil)
end)

RegisterNetEvent('VeylCore:Client:OnPlayerLoaded', function()
    refresh(nil)
    SetTimeout(2000, function() CreateThread(function() local r = cb('status') if r.ok and r.data then refresh(r.data) end end) end)
end)
RegisterNetEvent('VeylCore:Client:OnPlayerUnload', function() refresh(nil) end)

CreateThread(function()
    while GetResourceState('veyl_interact') ~= 'started' do Wait(250) end
    for job, cfg in pairs(C.Jobs) do
        local p = cfg.depot
        exports.veyl_interact:AddPed({ id = 'veyl_cjob_' .. job, model = p.model, coords = p.coords, radius = 3.0,
            label = cfg.label, scenario = 'WORLD_HUMAN_CLIPBOARD', icon = 'briefcase',
            options = {
                { label = 'Start a shift', icon = 'briefcase', event = 'veyl_citizenjobs:start', args = { job = job }, canInteract = function() return run == nil end },
                { label = 'Finish shift and get paid', icon = 'money', event = 'veyl_citizenjobs:finish', canInteract = function() return run ~= nil and run.job == job end },
                { label = 'Cancel shift', icon = 'close', event = 'veyl_citizenjobs:cancel', canInteract = function() return run ~= nil and run.job == job end },
            } })
        local b = AddBlipForCoord(p.coords.x, p.coords.y, p.coords.z)
        SetBlipSprite(b, cfg.blip.sprite) SetBlipColour(b, cfg.blip.colour) SetBlipScale(b, 0.75) SetBlipAsShortRange(b, true)
        BeginTextCommandSetBlipName('STRING') AddTextComponentSubstringPlayerName(cfg.label .. ' (Jobs)') EndTextCommandSetBlipName(b)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then clearBlip() dropBag() removePassenger(false) vlib.hideTextUI() end
end)
