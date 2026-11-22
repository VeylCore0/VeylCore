-- veyl_boosting server: one contract at a time per character. The car is spawned locked; hotwiring gives the key;
-- tracked classes ping the police until the tracker is disabled; delivering it at the drop-off pays and adds rep.

local C = BoostingConfig
local contracts = {}   -- [citizenid] = { class, model, spawn, drop, vehicleId, netId, expires, tracked, hotwired, token }
local lastContract = {}
local acting = {}      -- [src] = { kind, token, at, seconds }

local function core(name, ...) return Veyl.Await('veyl_core', name, 15000, ...) end
local function count(src, item) return exports.veyl_inventory:GetItemCount(src, item) or 0 end

Veyl.Startup({ 'veyl_core', 'veyl_vehicles', 'veyl_inventory' }, function()
    return Veyl.Migrate({ { id = '001_rep', sql = {
        [[CREATE TABLE IF NOT EXISTS veyl_boosting_rep (citizenid VARCHAR(16) NOT NULL, rep INT UNSIGNED NOT NULL DEFAULT 0,
            completed INT UNSIGNED NOT NULL DEFAULT 0, PRIMARY KEY (citizenid)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    } } })
end)

local function repOf(cid) return MySQL.scalar.await('SELECT rep FROM veyl_boosting_rep WHERE citizenid = ?', { cid }) or 0 end
local function police()
    local n = 0
    for _, s in ipairs(GetPlayers()) do
        local pd = Veyl.GetPlayerData(tonumber(s))
        if pd and pd.job.onduty and pd.job.name == 'police' then n = n + 1 end
    end
    return n
end

local function entityOf(c) return c.netId and NetworkGetEntityFromNetworkId(c.netId) or 0 end

local function finish(cid)
    local c = contracts[cid]
    contracts[cid] = nil
    if c and c.vehicleId then exports.veyl_vehicles:DeleteVehicle(c.vehicleId) end
end

Veyl.RegisterCallback('status', function(_, citizenid)
    local rep = repOf(citizenid)
    local class
    for _, cl in ipairs(C.Classes) do if rep >= cl.rep then class = cl end end
    local c = contracts[citizenid]
    return Veyl.Ok({ rep = rep, class = class.id, active = c and { class = c.class, model = c.model, area = { x = c.spawn.x, y = c.spawn.y }, hotwired = c.hotwired,
        tracked = c.tracked, drop = c.hotwired and { x = c.drop.x, y = c.drop.y } or nil, minutesLeft = math.max(0, math.ceil((c.expires - os.time()) / 60)) } or nil })
end, { cooldown = 800 })

Veyl.RegisterCallback('take', function(src, citizenid)
    if contracts[citizenid] then return Veyl.Err('INVALID_STATE', 'Finish your current contract first') end
    local wait = (lastContract[citizenid] or 0) + C.ContractCooldownMinutes * 60 - os.time()
    if wait > 0 then return Veyl.Err('RATE_LIMITED', ('No contracts for you for %d min'):format(math.ceil(wait / 60))) end
    local rep = repOf(citizenid)
    local cl
    for _, x in ipairs(C.Classes) do if rep >= x.rep and police() >= (C.MinPolice[x.id] or 0) then cl = x end end
    if not cl then return Veyl.Err('UNAVAILABLE', 'No contracts right now') end
    local spawn = C.Spawns[math.random(#C.Spawns)]
    local model = cl.models[math.random(#cl.models)]
    local res = Veyl.Await('veyl_vehicles', 'SpawnAuthorizedVehicle', 15000, { model = model, coords = spawn, temporary = true, platePrefix = 'BST' })
    if not res.ok then return Veyl.Err('INTERNAL', 'The contract fell through. Try again.') end
    local ent = NetworkGetEntityFromNetworkId(res.data.netId)
    if ent ~= 0 then SetVehicleDoorsLocked(ent, 2) end
    lastContract[citizenid] = os.time()
    contracts[citizenid] = { class = cl.id, cfg = cl, model = model, spawn = spawn, drop = C.Dropoffs[math.random(#C.Dropoffs)],
        vehicleId = res.data.vehicleId, netId = res.data.netId, expires = os.time() + C.TimeLimitMinutes * 60, tracked = cl.tracker, hotwired = false, src = src }
    Veyl.Audit(src, 'boost_contract', { class = cl.id, model = model })
    return Veyl.Ok({ x = spawn.x, y = spawn.y, class = cl.id, model = model }, ('Class %s contract: a %s. Find it in the marked area.'):format(cl.id, model))
end, { cooldown = 2000 })

local function contractVehicle(src, cid, netId)
    local c = contracts[cid]
    if not c or tonumber(netId) ~= c.netId then return nil end
    local ent = entityOf(c)
    if ent == 0 then return nil end
    local pc = Veyl.GetPlayerCoords(src)
    if not pc or #(pc - GetEntityCoords(ent)) > 6.0 then return nil end
    return c, ent
end

Veyl.RegisterCallback('actStart', function(src, citizenid, kind, netId)
    local c = contractVehicle(src, citizenid, netId)
    if not c then return Veyl.Err('NOT_FOUND', 'That is not your contract car') end
    if kind == 'lockpick' then
        if c.unlocked or c.hotwired then return Veyl.Err('INVALID_STATE', 'The door is already open') end
        if GetVehiclePedIsIn(GetPlayerPed(src), false) ~= 0 then return Veyl.Err('INVALID_STATE', 'Get out to pick the door') end
        if count(src, C.HotwireItem) < 1 then return Veyl.Err('NO_ITEM', 'You need a lockpick') end
    elseif kind == 'hotwire' then
        if c.hotwired then return Veyl.Err('INVALID_STATE', 'Already done') end
        if not c.unlocked then return Veyl.Err('INVALID_STATE', 'Pick the door lock first') end
        local _, ent = contractVehicle(src, citizenid, netId)
        if not ent or GetPedInVehicleSeat(ent, -1) ~= GetPlayerPed(src) then return Veyl.Err('INVALID_STATE', 'Sit in the driver seat to hotwire it') end
        if count(src, C.HotwireItem) < 1 then return Veyl.Err('NO_ITEM', 'You need a lockpick') end
    elseif kind == 'tracker' then
        if not c.tracked then return Veyl.Err('INVALID_STATE', 'No tracker on this one') end
        if count(src, C.TrackerItem) < 1 then return Veyl.Err('NO_ITEM', 'You need a hacking device') end
    else
        return Veyl.Err('INVALID_INPUT', 'Unknown action')
    end
    local token = Veyl.NewId()
    acting[src] = { kind = kind, token = token, at = GetGameTimer(), netId = netId,
        seconds = kind == 'hotwire' and C.HotwireSeconds or kind == 'lockpick' and (C.LockpickSeconds or 4) or C.TrackerSeconds }
    return Veyl.Ok({ token = token, seconds = acting[src].seconds })
end, { cooldown = 1000 })

--- The lockpick mini game failed at the contract car's door: the pick may snap.
Veyl.RegisterCallback('pickFailed', function(src, citizenid, netId)
    local c = contractVehicle(src, citizenid, netId)
    if not c then return Veyl.Ok() end
    if math.random() < (C.LockpickBreakChance or 0.35) and exports.veyl_inventory:RemoveItem(src, C.HotwireItem, 1) then
        return Veyl.Ok({ broke = true }, 'Your lockpick snapped')
    end
    return Veyl.Ok({ broke = false }, 'You slipped. Try again.')
end, { cooldown = 1500 })

Veyl.RegisterCallback('actFinish', function(src, citizenid, token)
    local a = acting[src]
    acting[src] = nil
    if not a or a.token ~= token then return Veyl.Err('INVALID_STATE', 'Start again') end
    local c, ent = contractVehicle(src, citizenid, a.netId)
    if not c then return Veyl.Err('NOT_FOUND', 'You moved away') end
    if GetGameTimer() - a.at < a.seconds * 1000 - 600 then return Veyl.Err('TOO_FAST', 'You stopped too early') end
    if a.kind == 'lockpick' then
        c.unlocked = true
        SetVehicleDoorsLocked(ent, 1)
        return Veyl.Ok({ unlocked = true }, 'Unlocked. Get in and hotwire it (H).')
    end
    if a.kind == 'hotwire' then
        c.hotwired = true
        SetVehicleDoorsLocked(ent, 1)
        if GetResourceState('veyl_vehiclekeys') == 'started' then exports.veyl_vehiclekeys:GiveKey(c.vehicleId, citizenid) end
        return Veyl.Ok({ drop = { x = c.drop.x, y = c.drop.y }, tracked = c.tracked },
            c.tracked and 'Hotwired. It has a tracker: disable it or the police will follow you.' or 'Hotwired. Get it to the drop-off.')
    end
    if math.random() < 0.5 then exports.veyl_inventory:RemoveItem(src, C.TrackerItem, 1) end
    c.tracked = false
    return Veyl.Ok(nil, 'Tracker disabled')
end, { cooldown = 500 })

Veyl.RegisterCallback('deliver', function(src, citizenid)
    local c = contracts[citizenid]
    if not c or not c.hotwired then return Veyl.Err('NOT_FOUND', 'No car to deliver') end
    if c.delivering then return Veyl.Err('BUSY', 'Already being delivered') end
    local ent = entityOf(c)
    if ent == 0 or #(GetEntityCoords(ent) - c.drop) > C.DropRadius then return Veyl.Err('TOO_FAR', 'Park it at the drop-off') end
    local ped = GetPlayerPed(src)
    if GetVehiclePedIsIn(ped, false) == ent then return Veyl.Err('INVALID_STATE', 'Get out and walk away') end
    local cl = c.cfg
    local pay = math.random(cl.pay[1], cl.pay[2])
    -- 0 exactly means the server has no synced value yet (not a wreck): pay in full rather than guess.
    local health = GetVehicleBodyHealth(ent)
    if health > 0 and health < 700 then pay = math.floor(pay * math.max(0.3, health / 1000)) end
    c.delivering = true
    -- One payment per contract vehicle, whatever happens with repeated requests.
    core('CreditOnce', citizenid, 'cash', pay, ('Boosting: %s'):format(c.model), ('boost:%s:%s'):format(citizenid, c.vehicleId))
    MySQL.query.await('INSERT INTO veyl_boosting_rep (citizenid, rep, completed) VALUES (?, ?, 1) ON DUPLICATE KEY UPDATE rep = rep + VALUES(rep), completed = completed + 1',
        { citizenid, cl.gain })
    finish(citizenid)
    Veyl.Audit(src, 'boost_delivered', { class = cl.id, pay = pay })
    return Veyl.Ok(nil, ('Delivered. $%d cash and +%d rep.%s'):format(pay, cl.gain, health < 700 and ' (it was damaged)' or ''))
end, { cooldown = 2000 })

Veyl.RegisterCallback('cancelContract', function(_, citizenid)
    if not contracts[citizenid] then return Veyl.Err('NOT_FOUND', 'No contract') end
    finish(citizenid)
    return Veyl.Ok(nil, 'Contract dropped')
end, { cooldown = 2000 })

-- Trackers and time limits.
CreateThread(function()
    local lastPing = 0
    while true do
        Wait(5000)
        local ping = os.time() - lastPing >= C.TrackerPingSeconds
        if ping then lastPing = os.time() end
        for cid, c in pairs(contracts) do
            local ent = entityOf(c)
            if os.time() > c.expires or ent == 0 then
                local s = exports.veyl_core:GetSourceByCitizenId(cid)
                if s then Veyl.Notify(s, 'Your boosting contract ran out.', 'error') end
                finish(cid)
            elseif ping and c.hotwired and c.tracked and GetResourceState('veyl_dispatch') == 'started' then
                pcall(function()
                    exports.veyl_dispatch:Alert({ services = { 'police' }, code = '10-16', title = 'Stolen vehicle tracker', priority = 2,
                        coords = GetEntityCoords(ent), message = ('Tracker ping: %s (%s)'):format(c.model, GetVehicleNumberPlateText(ent)),
                        blip = { sprite = 225, colour = 1 } })
                end)
            end
        end
    end
end)

AddEventHandler('playerDropped', function() acting[source] = nil end)
