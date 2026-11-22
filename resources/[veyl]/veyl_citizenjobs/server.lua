-- veyl_citizenjobs server: trucking, garbage, taxi and tow. The server owns every run: targets, positions, timing and pay.
-- Pay goes to the bank with CreditOnce and an operation id per run step, so a repeated request never pays twice.

local C = CitizenJobsConfig
local runs = {}           -- [citizenid] = run
local runByVehicle = {}   -- [vehicleId] = citizenid
local binsUsed = {}       -- ["x:y"] = os.time() when the bin has trash again

Veyl.Startup({ 'veyl_core', 'veyl_vehicles' }, function() return true end)

local function core(name, ...) return Veyl.Await('veyl_core', name, 15000, ...) end
local function v3(v) return vector3(v.x, v.y, v.z) end
local function dist2d(a, b) local dx, dy = a.x - b.x, a.y - b.y return math.sqrt(dx * dx + dy * dy) end
local function shuffle(n, count)
    local pool = {}
    for i = 1, n do pool[i] = i end
    for i = n, 2, -1 do local j = math.random(1, i) pool[i], pool[j] = pool[j], pool[i] end
    local out = {}
    for i = 1, math.min(count, n) do out[i] = pool[i] end
    return out
end

local function jobCfg(name) return type(name) == 'string' and C.Jobs[name] or nil end
local function depotPos(cfg) return v3(cfg.depot.coords) end

local function near(src, pos, d) local c = Veyl.GetPlayerCoords(src) return c ~= nil and #(c - pos) <= d end
local function vehicleOf(run)
    local v = exports.veyl_vehicles:GetVehicle(run.vehicleId)
    return v and v.exists and v or nil
end
local function vehicleNear(run, pos, d) local v = vehicleOf(run) return v ~= nil and dist2d(v.coords, pos) <= d end
local function driving(src, run)
    local v = vehicleOf(run)
    if not v then return false end
    local e = NetworkGetEntityFromNetworkId(v.netId)
    return e ~= 0 and GetPedInVehicleSeat(e, -1) == GetPlayerPed(src)
end

local function pay(run, amount, reason, step)
    if amount <= 0 then return true end
    local r = core('CreditOnce', run.citizenid, 'bank', math.floor(amount), reason, ('cjob:%s:%s'):format(run.id, step))
    if not r.ok and r.code ~= 'DUPLICATE_OPERATION' then return false end
    run.earned = run.earned + math.floor(amount)
    return true
end

--- What the client needs to draw the run.
local function view(run)
    local cfg = jobCfg(run.job)
    local v = { id = run.id, job = run.job, kind = cfg.kind, netId = run.netId, plate = run.plate, earned = run.earned, step = run.step }
    if cfg.kind == 'haul' then
        v.target = run.step == 'deliver' and C.Jobs[run.job].destinations[run.dest] or depotPos(cfg)
    elseif cfg.kind == 'bins' then
        v.bags, v.quota, v.carrying = run.bags, cfg.quota, run.carrying
        v.target = run.bags >= cfg.quota and depotPos(cfg) or nil
    elseif cfg.kind == 'fare' then
        v.target = run.step == 'pickup' and cfg.spots[run.from] or cfg.spots[run.to]
        v.ped = run.ped
        v.fares = run.fares
    elseif cfg.kind == 'tow' then
        local call = cfg.calls[run.call]
        v.target = run.step == 'hook' and vector3(call.x, call.y, call.z) or cfg.yard
        v.towNet = run.towNet
        v.tows = run.tows
    end
    return v
end

local function activeRun(src, citizenid)
    local run = runs[citizenid]
    if not run or run.src ~= src or Veyl.GetSessionGeneration(src) ~= run.generation then return nil end
    return run
end

local function deleteTow(run)
    if run.towId then
        runByVehicle[run.towId] = nil
        exports.veyl_vehicles:DeleteVehicle(run.towId)
        run.towId, run.towNet = nil, nil
    end
end

local function endRun(citizenid, reason)
    local run = runs[citizenid]
    if not run then return end
    runs[citizenid] = nil
    deleteTow(run)
    if run.vehicleId then
        runByVehicle[run.vehicleId] = nil
        exports.veyl_vehicles:DeleteVehicle(run.vehicleId)
    end
    Veyl.Audit(run.src, 'cjob_end', { job = run.job, reason = reason, earned = run.earned })
    if GetPlayerName(run.src) and Veyl.GetCitizenId(run.src) == citizenid then TriggerClientEvent('veyl_citizenjobs:ended', run.src, reason, run.earned) end
end

---------------------------------------------------------------------------
-- Next targets per kind
---------------------------------------------------------------------------
local function newFare(run, cfg)
    local here = Veyl.GetPlayerCoords(run.src) or depotPos(cfg)
    local best, tries = nil, 0
    repeat
        tries = tries + 1
        best = math.random(1, #cfg.spots)
    until #(v3(cfg.spots[best]) - here) > 250.0 or tries > 20
    local to
    tries = 0
    repeat
        tries = tries + 1
        to = math.random(1, #cfg.spots)
    until (to ~= best and #(v3(cfg.spots[to]) - v3(cfg.spots[best])) > cfg.minFareKm * 1000) or tries > 30
    run.from, run.to, run.step = best, to, 'pickup'
    run.ped = cfg.peds[math.random(1, #cfg.peds)]
end

local function newTow(run, cfg)
    run.call = math.random(1, #cfg.calls)
    run.step = 'hook'
    local c = cfg.calls[run.call]
    local res = Veyl.Await('veyl_vehicles', 'SpawnAuthorizedVehicle', 10000, { model = cfg.models[math.random(1, #cfg.models)], coords = c, temporary = true, platePrefix = 'WRK', fuel = 5 })
    if not res.ok then return false end
    run.towId, run.towNet = res.data.vehicleId, res.data.netId
    runByVehicle[run.towId] = run.citizenid
    return true
end

---------------------------------------------------------------------------
-- Start / finish / cancel
---------------------------------------------------------------------------
Veyl.RegisterCallback('status', function(src, citizenid)
    local run = activeRun(src, citizenid)
    return Veyl.Ok(run and view(run) or nil)
end, { cooldown = 500 })

Veyl.RegisterCallback('start', function(src, citizenid, job)
    local cfg = jobCfg(job)
    if not cfg then return Veyl.Err('NOT_FOUND', 'Unknown job') end
    if runs[citizenid] then return Veyl.Err('INVALID_STATE', 'Finish your current shift first') end
    if not near(src, depotPos(cfg), 5.0) then return Veyl.Err('TOO_FAR', 'Talk to the depot') end
    local pd = Veyl.GetPlayerData(src)
    if pd.job.name ~= job then
        if pd.jobs[job] ~= nil then
            exports.veyl_core:SetPlayerPrimaryJob(citizenid, job)
        elseif pd.job.name == 'unemployed' then
            if not exports.veyl_core:SetJob(src, job, 0) then return Veyl.Err('INTERNAL', 'Could not sign you on') end
            Veyl.Notify(src, ('You now work for %s.'):format(cfg.label), 'success')
        else
            return Veyl.Err('INVALID_STATE', ('You work for %s. Switch jobs with /jobs or the phone first.'):format(pd.job.label))
        end
        pd = Veyl.GetPlayerData(src)
    end
    if not pd.job.onduty then exports.veyl_core:SetJobDuty(src, true) end
    for _, veh in ipairs(GetAllVehicles()) do
        if #(GetEntityCoords(veh) - v3(cfg.spawn)) < 4.0 then return Veyl.Err('BUSY', 'The bay is blocked. Move the vehicle away.') end
    end
    local veh = Veyl.Await('veyl_vehicles', 'SpawnAuthorizedVehicle', 10000, { model = cfg.vehicle, coords = cfg.spawn, citizenid = citizenid, temporary = true, platePrefix = cfg.platePrefix, fuel = 100 })
    if not veh.ok then return Veyl.Err(veh.code or 'INTERNAL', 'No vehicle available right now') end
    local run = { id = Veyl.NewId(), job = job, src = src, generation = Veyl.GetSessionGeneration(src), citizenid = citizenid,
        vehicleId = veh.data.vehicleId, netId = veh.data.netId, plate = veh.data.plate, earned = 0, last = os.time(), n = 0 }
    if cfg.kind == 'haul' then
        run.dest, run.step = math.random(1, #cfg.destinations), 'deliver'
    elseif cfg.kind == 'bins' then
        run.bags, run.carrying, run.step = 0, false, 'collect'
    elseif cfg.kind == 'fare' then
        run.fares = 0
        newFare(run, cfg)
    elseif cfg.kind == 'tow' then
        run.tows = 0
        if not newTow(run, cfg) then exports.veyl_vehicles:DeleteVehicle(run.vehicleId) return Veyl.Err('INTERNAL', 'No calls right now') end
    end
    runs[citizenid] = run
    runByVehicle[run.vehicleId] = citizenid
    Veyl.Audit(src, 'cjob_start', { job = job })
    return Veyl.Ok(view(run), ('Shift started. Your %s is %s.'):format(cfg.kind == 'fare' and 'cab' or 'vehicle', run.plate))
end, { cooldown = 3000 })

Veyl.RegisterCallback('finish', function(src, citizenid)
    local run = activeRun(src, citizenid)
    if not run then return Veyl.Err('INVALID_STATE', 'No active shift') end
    local cfg = jobCfg(run.job)
    if not near(src, depotPos(cfg), 6.0) then return Veyl.Err('TOO_FAR', 'Finish at the depot') end
    local back = vehicleNear(run, depotPos(cfg), 40.0)
    if cfg.kind == 'haul' and run.step == 'return' and back then pay(run, cfg.returnBonus, 'Trucking: truck returned', 'return') end
    if cfg.kind == 'bins' then
        local pay1 = run.bags * cfg.payPerBag + ((run.bags >= cfg.quota and back) and cfg.completionBonus or 0)
        if not pay(run, pay1, ('Sanitation route (%d bags)'):format(run.bags), 'route') then return Veyl.Err('INTERNAL', 'Payment failed, try again') end
    end
    local earned = run.earned
    endRun(citizenid, 'finished')
    return Veyl.Ok({ earned = earned }, earned > 0 and ('Shift over. You earned $%d.'):format(earned) or 'Shift over.')
end, { cooldown = 2000 })

Veyl.RegisterCallback('cancel', function(src, citizenid)
    local run = activeRun(src, citizenid)
    if not run then return Veyl.Err('INVALID_STATE', 'No active shift') end
    endRun(citizenid, 'cancelled')
    return Veyl.Ok(nil, 'Shift cancelled. Unfinished work is not paid.')
end, { cooldown = 2000 })

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
local function tooFast(run) return os.time() - run.last < C.MinSecondsPerStop end

Veyl.RegisterCallback('act', function(src, citizenid, action, arg)
    local run = activeRun(src, citizenid)
    if not run then return Veyl.Err('INVALID_STATE', 'No active shift') end
    local cfg = jobCfg(run.job)

    if cfg.kind == 'haul' and action == 'unload' then
        if run.step ~= 'deliver' then return Veyl.Err('INVALID_STATE', 'Already unloaded. Head back to the depot.') end
        local dest = cfg.destinations[run.dest]
        if not near(src, dest, 10.0) or not vehicleNear(run, dest, 25.0) then return Veyl.Err('TOO_FAR', 'Bring the truck to the drop-off') end
        local km = dist2d(depotPos(cfg), dest) / 1000
        if os.time() - run.last < km * 25 then return Veyl.Err('TOO_FAST', 'That was suspiciously quick') end
        run.n = run.n + 1
        if not pay(run, cfg.base + km * cfg.perKm, ('Trucking: load delivered (%.1f km)'):format(km), 'load' .. run.n) then return Veyl.Err('INTERNAL', 'Payment failed, try again') end
        run.step, run.last = 'return', os.time()
        return Veyl.Ok(view(run), ('Delivered. Paid $%d. Return the truck to the depot for a bonus, or finish there.'):format(math.floor(cfg.base + km * cfg.perKm)))
    end

    if cfg.kind == 'bins' then
        if action == 'bag' then
            if run.carrying then return Veyl.Err('INVALID_STATE', 'Throw this bag in the truck first') end
            local p = type(arg) == 'table' and tonumber(arg.x) and tonumber(arg.y) and tonumber(arg.z) and vector3(arg.x + 0.0, arg.y + 0.0, arg.z + 0.0)
            if not p or not near(src, p, 3.0) then return Veyl.Err('TOO_FAR', 'Stand at a trash can') end
            local v = vehicleOf(run)
            if not v or #(v.coords - p) > cfg.truckRange then return Veyl.Err('TOO_FAR', 'Bring your garbage truck closer') end
            local key = ('%d:%d'):format(math.floor(p.x), math.floor(p.y))
            if (binsUsed[key] or 0) > os.time() then return Veyl.Err('EMPTY', 'This one is empty. Try another bin.') end
            if os.time() - (run.lastBag or 0) < 3 then return Veyl.Err('TOO_FAST', 'Slow down') end
            binsUsed[key], run.lastBag, run.carrying = os.time() + cfg.binCooldownMinutes * 60, os.time(), true
            return Veyl.Ok(view(run))
        elseif action == 'throw' then
            if not run.carrying then return Veyl.Err('INVALID_STATE', 'Grab a bag first') end
            local v = vehicleOf(run)
            if not v or not near(src, v.coords, 7.0) then return Veyl.Err('TOO_FAR', 'Throw it in the back of the truck') end
            run.carrying, run.bags = false, run.bags + 1
            local r = cfg.recyclables
            if r and math.random() < r.chance then
                local total, pick = 0, nil
                for _, w in pairs(r.items) do total = total + w end
                local roll = math.random() * total
                for item, w in pairs(r.items) do roll = roll - w if roll <= 0 then pick = item break end end
                if pick then
                    local g = Veyl.Await('veyl_inventory', 'GiveItem', 10000, citizenid, pick, 1, nil, ('cjob:%s:rec:%d'):format(run.id, run.bags))
                    if g.ok then Veyl.Notify(src, ('Found something useful: %s'):format(pick:gsub('_', ' ')), 'success') end
                end
            end
            local msg = run.bags == cfg.quota and ('Quota done (%d bags)! Take the truck back to the depot for your bonus, or keep collecting.'):format(run.bags)
                or ('%d / %d bags'):format(run.bags, cfg.quota)
            return Veyl.Ok(view(run), msg)
        end
    end

    if cfg.kind == 'fare' then
        if action == 'pickup' then
            if run.step ~= 'pickup' then return Veyl.Err('INVALID_STATE', 'You already have a passenger') end
            if not driving(src, run) or not vehicleNear(run, cfg.spots[run.from], 15.0) then return Veyl.Err('TOO_FAR', 'Pull up at the pickup in your cab') end
            run.step, run.pickedAt = 'ride', os.time()
            return Veyl.Ok(view(run), 'Passenger on board. Drive to the destination.')
        elseif action == 'dropoff' then
            if run.step ~= 'ride' then return Veyl.Err('INVALID_STATE', 'No passenger') end
            local to = cfg.spots[run.to]
            if not driving(src, run) or not vehicleNear(run, to, 15.0) then return Veyl.Err('TOO_FAR', 'This is not the destination') end
            local km = dist2d(cfg.spots[run.from], to) / 1000
            if os.time() - run.pickedAt < km * 30 then return Veyl.Err('TOO_FAST', 'That was suspiciously quick') end
            run.fares = run.fares + 1
            local fare = math.floor(cfg.base + km * cfg.perKm + math.random(0, 25))
            if not pay(run, fare, ('Taxi fare (%.1f km)'):format(km), 'fare' .. run.fares) then return Veyl.Err('INTERNAL', 'Payment failed, try again') end
            newFare(run, cfg)
            return Veyl.Ok(view(run), ('Fare paid: $%d (with tip). Next pickup marked.'):format(fare))
        end
    end

    if cfg.kind == 'tow' then
        local tow = run.towId and exports.veyl_vehicles:GetVehicle(run.towId)
        if action == 'hook' then
            if run.step ~= 'hook' or not tow or not tow.exists then return Veyl.Err('INVALID_STATE', 'Nothing to hook') end
            local v = vehicleOf(run)
            if not v or #(v.coords - tow.coords) > 14.0 or not near(src, tow.coords, 7.0) then return Veyl.Err('TOO_FAR', 'Back the flatbed up to the vehicle') end
            run.step, run.last = 'deliver', os.time()
            return Veyl.Ok(view(run), 'Hooked. Take it to the yard.')
        elseif action == 'drop' then
            if run.step ~= 'deliver' or not tow then return Veyl.Err('INVALID_STATE', 'Nothing on the flatbed') end
            if not vehicleNear(run, cfg.yard, cfg.yardRadius) then return Veyl.Err('TOO_FAR', 'Bring it to the yard') end
            if tooFast(run) then return Veyl.Err('TOO_FAST', 'Slow down') end
            run.tows = run.tows + 1
            if not pay(run, cfg.payPerTow, 'Tow job', 'tow' .. run.tows) then return Veyl.Err('INTERNAL', 'Payment failed, try again') end
            deleteTow(run)
            if not newTow(run, cfg) then endRun(citizenid, 'no_calls') return Veyl.Ok(nil, ('Paid $%d. No more calls today.'):format(cfg.payPerTow)) end
            return Veyl.Ok(view(run), ('Paid $%d. Next call marked.'):format(cfg.payPerTow))
        end
    end
    return Veyl.Err('INVALID_INPUT', 'Unknown action')
end, { cooldown = 700 })

---------------------------------------------------------------------------
-- Interruptions
---------------------------------------------------------------------------
AddEventHandler('VeylCore:Server:OnPlayerUnload', function(_, citizenid) if runs[citizenid] then endRun(citizenid, 'left') end end)
AddEventHandler('veyl_vehicles:destroyed', function(vehicleId)
    local cid = runByVehicle[vehicleId]
    if cid and runs[cid] and runs[cid].vehicleId == vehicleId then endRun(cid, 'vehicle_destroyed') end
end)
AddEventHandler('veyl_vehicles:removed', function(vehicleId, reason)
    local cid = runByVehicle[vehicleId]
    if cid and reason == 'missing' and runs[cid] and runs[cid].vehicleId == vehicleId then endRun(cid, 'vehicle_missing') end
end)
AddEventHandler('VeylCore:Server:OnJobUpdate', function(src, job)
    local cid = Veyl.GetCitizenId(src)
    if cid and runs[cid] and job.name ~= runs[cid].job then endRun(cid, 'left_job') end
end)
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for cid in pairs(runs) do endRun(cid, 'resource_stop') end
end)
