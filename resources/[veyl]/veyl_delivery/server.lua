-- veyl_delivery server: the server owns the route, the package state and the reward.
-- A run's payout operation id is 'delivery:<runId>', so repeated finish requests can never pay twice.

local runs = {}         -- [charId] = run
local runByVehicle = {} -- [vehicleId] = charId

local cfg = DeliveryConfig
local depotPos = vector3(cfg.Depot.ped.coords.x, cfg.Depot.ped.coords.y, cfg.Depot.ped.coords.z)

Veyl.Startup({ 'veyl_core', 'veyl_banking', 'veyl_jobs', 'veyl_vehicles' }, function()
    local ok = Veyl.Migrate({
        {
            id = '001_runs',
            sql = {
                [[CREATE TABLE IF NOT EXISTS veyl_delivery_runs (
                    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                    character_id INT UNSIGNED NOT NULL,
                    status ENUM('active','completed','cancelled','abandoned') NOT NULL DEFAULT 'active',
                    stops LONGTEXT NOT NULL,
                    stops_total TINYINT UNSIGNED NOT NULL,
                    delivered TINYINT UNSIGNED NOT NULL DEFAULT 0,
                    payout INT UNSIGNED NOT NULL DEFAULT 0,
                    end_reason VARCHAR(64) NULL,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    ended_at TIMESTAMP NULL DEFAULT NULL,
                    PRIMARY KEY (id),
                    KEY idx_char_status (character_id, status)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            },
        },
    })
    if not ok then return false end
    -- Runs that were active when the server stopped can never become payable later.
    local n = MySQL.update.await([[UPDATE veyl_delivery_runs SET status = 'abandoned', end_reason = 'server_restart',
        ended_at = CURRENT_TIMESTAMP WHERE status = 'active']])
    if n and n > 0 then print(('^5[veyl_delivery] closed %d run(s) left active by a restart^7'):format(n)) end
    return true
end)

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function dist2d(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end

local function pickStops(n)
    local pool = {}
    for i = 1, #cfg.Stops do pool[i] = i end
    for i = #pool, 2, -1 do
        local j = math.random(1, i)
        pool[i], pool[j] = pool[j], pool[i]
    end
    local out = {}
    for i = 1, math.min(n, #pool) do out[i] = pool[i] end
    return out
end

local function publicRun(run)
    local coords = {}
    for i, idx in ipairs(run.stops) do coords[i] = cfg.Stops[idx] end
    return {
        id = run.id, stops = coords, current = run.current, delivered = run.delivered, carrying = run.carrying,
        netId = run.netId, plate = run.plate, total = #run.stops,
    }
end

local function endRun(charId, status, reason, payout)
    local run = runs[charId]
    if not run then return end
    runs[charId] = nil
    if run.vehicleId then
        runByVehicle[run.vehicleId] = nil
        exports.veyl_vehicles:DeleteVehicle(run.vehicleId) -- also revokes the temporary key
    end
    MySQL.update([[UPDATE veyl_delivery_runs SET status = ?, end_reason = ?, delivered = ?, payout = ?, ended_at = CURRENT_TIMESTAMP
        WHERE id = ? AND status = 'active']], { status, reason, run.delivered, payout or 0, run.id })
    if run.src and GetPlayerName(run.src) and Veyl.GetCharacterId(run.src) == charId then
        TriggerClientEvent('veyl_delivery:ended', run.src, status, reason)
    end
end

local function nearDepot(src, radius)
    local c = Veyl.GetPlayerCoords(src)
    return c ~= nil and #(c - depotPos) <= radius
end

local function spawnBlocked()
    local s = cfg.Depot.vanSpawn
    local spawnPos = vector3(s.x, s.y, s.z)
    for _, veh in ipairs(GetAllVehicles()) do
        if #(GetEntityCoords(veh) - spawnPos) < 4.0 then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Callbacks
---------------------------------------------------------------------------
Veyl.RegisterCallback('status', function(_, charId)
    local run = runs[charId]
    return Veyl.Ok(run and publicRun(run) or nil)
end, { cooldown = 500 })

Veyl.RegisterCallback('start', function(src, charId)
    if runs[charId] then return Veyl.Err('INVALID_STATE', 'You already have an active route') end
    if not nearDepot(src, cfg.Depot.radius + 2.0) then return Veyl.Err('TOO_FAR', 'Talk to the depot manager') end

    local job = exports.veyl_jobs:GetJob(charId)
    if not job then return Veyl.Err('NOT_READY', 'Job data not loaded yet') end
    if job.name ~= cfg.Job then
        if job.name ~= 'unemployed' then
            return Veyl.Err('INVALID_STATE', ('You already work for %s. Use /quitjob first.'):format(job.label))
        end
        local hired = Veyl.Await('veyl_jobs', 'SetJob', 10000, charId, cfg.Job, 0, 'Signed on at delivery depot')
        if not hired.ok then return hired end
        Veyl.Notify(src, 'You are now employed by GoPostal.', 'success')
    elseif not exports.veyl_jobs:IsOnDuty(charId, cfg.Job) then
        return Veyl.Err('INVALID_STATE', 'Go on duty first (/duty)')
    end

    if spawnBlocked() then return Veyl.Err('BUSY', 'The loading bay is blocked. Move the vehicle out of the way.') end

    local stops = pickStops(cfg.StopsPerRun)
    local runId = MySQL.insert.await('INSERT INTO veyl_delivery_runs (character_id, stops, stops_total) VALUES (?, ?, ?)',
        { charId, json.encode(stops), #stops })
    if not runId then return Veyl.Err('DATABASE_ERROR', 'Could not create route') end

    local van = Veyl.Await('veyl_vehicles', 'SpawnAuthorizedVehicle', 10000, {
        model = cfg.VanModel, coords = cfg.Depot.vanSpawn, characterId = charId, temporary = true, platePrefix = 'POST',
    })
    if not van.ok then
        MySQL.update('UPDATE veyl_delivery_runs SET status = ?, end_reason = ?, ended_at = CURRENT_TIMESTAMP WHERE id = ?',
            { 'cancelled', 'van_spawn_failed', runId })
        return Veyl.Err(van.code, 'Could not prepare a van: ' .. tostring(van.message))
    end

    local run = {
        id = runId, src = src, charId = charId, stops = stops, current = 1, delivered = 0, carrying = false,
        vehicleId = van.data.vehicleId, netId = van.data.netId, plate = van.data.plate,
        lastActionAt = os.time(), paying = false,
    }
    runs[charId] = run
    runByVehicle[run.vehicleId] = charId
    Veyl.Audit(src, 'delivery_started', { runId = runId, stops = #stops })
    return Veyl.Ok(publicRun(run), ('Route assigned: %d stops. Your van is %s.'):format(#stops, run.plate))
end, { cooldown = 3000 })

Veyl.RegisterCallback('takePackage', function(src, charId)
    local run = runs[charId]
    if not run or run.paying then return Veyl.Err('INVALID_STATE', 'No active route') end
    if run.carrying then return Veyl.Err('INVALID_STATE', 'You are already carrying a package') end
    if run.current > #run.stops then return Veyl.Err('INVALID_STATE', 'All packages delivered - return to the depot') end
    local van = exports.veyl_vehicles:GetVehicle(run.vehicleId)
    local pc = Veyl.GetPlayerCoords(src)
    if not van or not van.exists or not pc or #(pc - van.coords) > cfg.PackageFromVanDistance then
        return Veyl.Err('TOO_FAR', 'Go to the back of your van')
    end
    run.carrying = true
    return Veyl.Ok(publicRun(run), 'Package collected')
end, { cooldown = 1000 })

Veyl.RegisterCallback('deliver', function(src, charId)
    local run = runs[charId]
    if not run or run.paying then return Veyl.Err('INVALID_STATE', 'No active route') end
    if not run.carrying then return Veyl.Err('INVALID_STATE', 'Grab the package from your van first') end
    local stop = cfg.Stops[run.stops[run.current]]
    local pc = Veyl.GetPlayerCoords(src)
    if not pc or dist2d(pc, stop) > cfg.StopRadius or math.abs(pc.z - stop.z) > 6.0 then
        return Veyl.Err('TOO_FAR', 'This is not the delivery address')
    end
    if os.time() - run.lastActionAt < cfg.MinSecondsBetweenStops then
        Veyl.Audit(src, 'delivery_too_fast', { runId = run.id, seconds = os.time() - run.lastActionAt })
        return Veyl.Err('INVALID_STATE', 'Slow down - the customer is still coming to the door')
    end
    run.carrying = false
    run.delivered = run.delivered + 1
    run.current = run.current + 1
    run.lastActionAt = os.time()
    MySQL.update('UPDATE veyl_delivery_runs SET delivered = ? WHERE id = ?', { run.delivered, run.id })
    local done = run.current > #run.stops
    return Veyl.Ok(publicRun(run), done and 'All packages delivered! Return the van to the depot.'
        or ('Delivered (%d/%d)'):format(run.delivered, #run.stops))
end, { cooldown = 1000 })

Veyl.RegisterCallback('finish', function(src, charId)
    local run = runs[charId]
    if not run then return Veyl.Err('INVALID_STATE', 'No active route') end
    if run.paying then return Veyl.Err('BUSY', 'Payment already in progress') end
    if not nearDepot(src, cfg.Depot.radius + 2.0) then return Veyl.Err('TOO_FAR', 'Talk to the depot manager') end

    local van = exports.veyl_vehicles:GetVehicle(run.vehicleId)
    local vanReturned = van and van.exists and #(van.coords - depotPos) <= cfg.Depot.returnRadius
    local complete = run.delivered >= #run.stops
    local payout = run.delivered * cfg.PayPerStop + ((complete and vanReturned) and cfg.CompletionBonus or 0)

    run.paying = true
    if payout > 0 then
        local res = Veyl.Await('veyl_banking', 'Credit', 15000, charId, 'bank', payout,
            ('GoPostal route #%d (%d stops)'):format(run.id, run.delivered), ('delivery:%d'):format(run.id))
        if not res.ok and res.code ~= 'DUPLICATE_OPERATION' then
            run.paying = false -- safe to retry: the op id prevents a second payout
            return Veyl.Err(res.code, 'Payment failed, please try again in a moment')
        end
    end
    endRun(charId, 'completed', complete and 'completed' or 'ended_early', payout)
    Veyl.Audit(src, 'delivery_completed', { runId = run.id, delivered = run.delivered, payout = payout })
    local msg = payout > 0 and ('Shift complete! $%d paid to your bank.'):format(payout) or 'Shift ended with no deliveries.'
    if complete and not vanReturned then msg = msg .. ' (No bonus: the van was not returned.)' end
    return Veyl.Ok({ payout = payout }, msg)
end, { cooldown = 2000 })

Veyl.RegisterCallback('cancel', function(src, charId)
    if not runs[charId] then return Veyl.Err('INVALID_STATE', 'No active route') end
    if runs[charId].paying then return Veyl.Err('BUSY', 'Payment in progress') end
    endRun(charId, 'cancelled', 'player_cancelled', 0)
    return Veyl.Ok(nil, 'Route cancelled. Unpaid packages were returned to the depot.')
end, { cooldown = 2000 })

---------------------------------------------------------------------------
-- Interruptions
---------------------------------------------------------------------------
AddEventHandler('veyl:characterUnloading', function(_, charId)
    if runs[charId] and not runs[charId].paying then endRun(charId, 'abandoned', 'player_left', 0) end
end)

AddEventHandler('veyl_vehicles:destroyed', function(vehicleId)
    local charId = runByVehicle[vehicleId]
    if charId and runs[charId] and not runs[charId].paying then endRun(charId, 'cancelled', 'van_destroyed', 0) end
end)

AddEventHandler('veyl_vehicles:removed', function(vehicleId, reason)
    local charId = runByVehicle[vehicleId]
    if charId and reason == 'missing' and runs[charId] and not runs[charId].paying then
        endRun(charId, 'cancelled', 'van_missing', 0)
    end
end)

AddEventHandler('veyl_jobs:updated', function(_, charId, job)
    if runs[charId] and (job.name ~= cfg.Job or not job.onDuty) and not runs[charId].paying then
        endRun(charId, 'cancelled', 'left_job_or_duty', 0)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for charId in pairs(runs) do endRun(charId, 'abandoned', 'resource_stop', 0) end
end)
