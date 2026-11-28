-- The contract engine. The server owns everything: which contracts a player may take, the state machine, the vehicles, the access
-- puzzle, delivery, rewards and penalties. The client only shows things and asks; it never decides an outcome.

Boost = Boost or {}
local Contracts = { byId = {}, byCid = {}, offers = {}, event = false }
Boost.Contracts = Contracts

local C = BoostingConfig
local S = BoostingShared
local K = C.Crews

local function core(name, ...) return Veyl.Await('veyl_core', name, 15000, ...) end
local function trim(s) return (tostring(s or ''):gsub('^%s+', ''):gsub('%s+$', '')) end
local function ent(v) return v.netId and NetworkGetEntityFromNetworkId(v.netId) or 0 end
local function templateOf(id) for _, t in ipairs(C.Templates) do if t.id == id then return t end end end
local function vehicleDef(model) for _, v in ipairs(C.Vehicles) do if v.model == model then return v end end end

---------------------------------------------------------------------------
-- Persistence
---------------------------------------------------------------------------
function Contracts.persist(c)
    local vs = {}
    for _, v in ipairs(c.vehicles) do vs[#vs + 1] = { model = v.model, status = v.status } end
    MySQL.update([[INSERT INTO veyl_boost_contracts (id, template, leader_cid, state, vehicles, reward, payout, rep_reward, result, created_at, started_at, expires_at, ended_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE leader_cid = VALUES(leader_cid), state = VALUES(state), vehicles = VALUES(vehicles), payout = VALUES(payout),
            result = VALUES(result), started_at = VALUES(started_at), expires_at = VALUES(expires_at), ended_at = VALUES(ended_at)]],
        { c.id, c.template.id, c.leader, c.state, json.encode(vs), c.reward, c.payout, c.repReward, c.result, c.createdAt, c.startedAt, c.expiresAt, c.endedAt })
end

--- The only way a contract changes state. Illegal moves are refused and logged.
local function transition(c, to)
    local allowed = S.Transitions[c.state]
    if not allowed or not allowed[to] then
        Boost.Log.suspicious(nil, c.leader, 'illegal_transition', { contract = c.id, from = c.state, to = to })
        return false
    end
    c.state = to
    Contracts.persist(c)
    Boost.Log.audit(c.leader, 'state', { contract = c.id, state = to })
    return true
end

---------------------------------------------------------------------------
-- Views sent to players
---------------------------------------------------------------------------
function Contracts.view(c, cid)
    if not c then return nil end
    local vs = {}
    local acquired = 0
    for i, v in ipairs(c.vehicles) do
        if v.status ~= 'waiting' then acquired = acquired + 1 end
        vs[i] = { index = i, model = v.model, label = v.label, tier = v.tier, status = v.status, netId = v.netId }
    end
    local members = {}
    for _, x in ipairs(c.order) do
        local m = c.members[x]
        if m then members[#members + 1] = { id = x, name = m.name, leader = x == c.leader, online = m.src ~= nil, me = x == cid } end
    end
    local view = {
        id = c.id, template = c.template.id, label = c.template.label, badge = c.template.badge, description = c.template.description,
        state = c.state, difficulty = c.template.difficulty, leader = c.leader == cid, vehicles = vs, acquired = acquired,
        members = members, tracked = c.tracked and not c.trackerOff, trackerOff = c.trackerOff == true,
        reward = c.reward, repReward = c.repReward, createdAt = c.createdAt, startedAt = c.startedAt, expiresAt = c.expiresAt,
        reserveUntil = c.reserveUntil, area = c.state ~= 'reserved' and c.area or nil,
        canStart = c.state == 'reserved' and c.leader == cid, canCancel = S.Live[c.state] == true,
        needsCrew = c.template.mode == 'group', timeLimit = c.template.timeLimit, serverTime = os.time(),
    }
    -- The handoff point is revealed once the first vehicle is in hand.
    if c.state == 'vehicle_acquired' or c.state == 'delivery_started' then view.drop = { label = c.drop.label, x = c.drop.coords.x, y = c.drop.coords.y, z = c.drop.coords.z, radius = C.Delivery.Radius } end
    return view
end

function Contracts.push(c)
    for cid, m in pairs(c.members) do
        if m.src then TriggerClientEvent('veyl_boosting:contract', m.src, Contracts.view(c, cid)) end
    end
end

local function pushNone(c)
    for _, m in pairs(c.members) do if m.src then TriggerClientEvent('veyl_boosting:contract', m.src, nil) end end
end

---------------------------------------------------------------------------
-- Offers
---------------------------------------------------------------------------
local function activeCount(templateId)
    local n = 0
    for _, c in pairs(Contracts.byId) do if c.template.id == templateId and S.Live[c.state] then n = n + 1 end end
    return n
end

--- Why this player cannot take the template right now (nil = they can).
function Contracts.lockReason(cid, t)
    local p = Boost.Prog.get(cid)
    local rankIdx = BoostingUtil.rankFor(p.rep)
    local ranks = C.Ranks
    if t.event and not Contracts.event then return 'No event running' end
    if rankIdx < (t.minRank or 1) then return ('Requires rank %s'):format(ranks[t.minRank].label) end
    if t.maxRank and rankIdx > t.maxRank then return 'Too experienced for this one' end
    if p.rep < (t.minRep or 0) then return ('Requires %d reputation'):format(t.minRep) end
    if t.maxRep and p.rep > t.maxRep then return 'Too experienced for this one' end
    if t.requires and (p.done[t.requires.template] or 0) < t.requires.completed then
        local req = templateOf(t.requires.template)
        return ('Complete %d x %s first'):format(t.requires.completed, req and req.label or t.requires.template)
    end
    local cd = Boost.Prog.cooldownLeft(cid, 'tpl:' .. t.id)
    if cd > 0 then return ('Available in %d min'):format(math.ceil(cd / 60)) end
    if activeCount(t.id) >= (t.maxActive or 99) then return 'Fully booked right now' end
    if (t.minPolice or 0) > 0 and Boost.Dispatch.policeOnline() < t.minPolice then return 'Too quiet in the city right now' end
    return nil
end

local function pickVehicle(cid, t, exclude)
    local p = Boost.Prog.get(cid)
    local pool = {}
    for _, v in ipairs(C.Vehicles) do
        local tierOk = false
        for _, tier in ipairs(t.tiers) do if tier == v.tier then tierOk = true end end
        local modeOk = (t.mode == 'group' and v.group) or (t.mode == 'solo' and v.solo) or (t.mode == 'both' and (v.solo or v.group))
        if tierOk and modeOk and p.rep >= v.minRep and not (exclude and exclude[v.model]) then pool[#pool + 1] = v end
    end
    return pool[#pool > 0 and math.random(#pool) or 1]
end

--- The list of contract cards for a player. A pick (vehicle, reward roll, id) is kept for OfferTTL so the page is stable.
function Contracts.offersFor(cid, force)
    local o = Contracts.offers[cid]
    local ttl = C.Offers.TTLMinutes * 60
    if force and o and os.time() - o.at < C.Offers.RefreshCooldownSeconds then force = false end
    if not o or force or os.time() - o.at > ttl then
        o = { at = os.time(), picks = {} }
        Contracts.offers[cid] = o
    end
    local out = {}
    local heatMult = Boost.Heat.rewardMult(cid)
    for _, t in ipairs(C.Templates) do
        if Boost.Heat.allows(cid, t.difficulty) then
            local pick = o.picks[t.id]
            if not pick then
                local v = pickVehicle(cid, t)
                pick = { id = Veyl.NewId(), model = v and v.model, roll = t.reward[1] + math.random() * (t.reward[2] - t.reward[1]) }
                o.picks[t.id] = pick
            end
            local v = pick.model and vehicleDef(pick.model)
            local lock = Contracts.lockReason(cid, t)
            if not v and not lock then lock = 'No vehicles unlocked yet' end
            local base = v and v.baseReward * t.vehicles or 0
            out[#out + 1] = {
                id = pick.id, template = t.id, label = t.label, badge = t.badge, description = t.description, difficulty = t.difficulty,
                model = v and v.model, vehicleLabel = v and v.label, tier = v and v.tier, mode = t.mode, crew = { min = t.minCrew, max = t.maxCrew },
                vehicles = t.vehicles, timeLimit = t.timeLimit, tracked = t.tracked, minRep = t.minRep, minRank = C.Ranks[t.minRank or 1].label,
                rewardMin = math.floor(base * t.reward[1] * heatMult), rewardMax = math.floor(base * t.reward[2] * heatMult), repReward = t.repReward,
                risk = t.heat.chance, locked = lock,
            }
        end
    end
    return out, o.at
end

---------------------------------------------------------------------------
-- Creating a contract
---------------------------------------------------------------------------
local function newContractId() return ('BC%s'):format(Veyl.NewId():gsub('%W', ''):sub(1, 10):upper()) end

local function memberOnline(m) return m.src ~= nil and Veyl.GetCitizenId(m.src) == m.cid end

function Contracts.addMember(c, cid, src)
    c.members[cid] = { cid = cid, src = src, name = Boost.Crew.nameOf(src) }
    c.order[#c.order + 1] = cid
    Contracts.byCid[cid] = c
    MySQL.update('INSERT IGNORE INTO veyl_boost_members (contract_id, citizenid, role) VALUES (?, ?, ?)', { c.id, cid, 'member' })
    Contracts.push(c)
end

function Contracts.removeMember(c, cid)
    c.members[cid] = nil
    Contracts.byCid[cid] = nil
    for i, x in ipairs(c.order) do if x == cid then table.remove(c.order, i) break end end
    MySQL.update("DELETE FROM veyl_boost_members WHERE contract_id = ? AND citizenid = ? AND role <> 'leader'", { c.id, cid })
    if not next(c.members) then
        Contracts.finish(c, 'cancelled', 'empty')
    else
        Contracts.push(c)
    end
end

--- Reserves a contract for the player (and their crew) from one of their offers.
function Contracts.accept(src, cid, offerId)
    if Contracts.byCid[cid] then return Veyl.Err('INVALID_STATE', 'Finish your current contract first') end
    local crew = Boost.Crew.of(cid)
    if crew and crew.leader ~= cid then return Veyl.Err('NO_PERMISSION', 'Only the crew leader can take contracts') end
    local o = Contracts.offers[cid]
    local t, pick
    if o and os.time() - o.at <= C.Offers.TTLMinutes * 60 then
        for _, tpl in ipairs(C.Templates) do if o.picks[tpl.id] and o.picks[tpl.id].id == offerId then t, pick = tpl, o.picks[tpl.id] end end
    end
    if not t then return Veyl.Err('NOT_FOUND', 'That contract is no longer on offer') end
    local lock = Contracts.lockReason(cid, t)
    if lock then return Veyl.Err('UNAVAILABLE', lock) end
    if not Boost.Heat.allows(cid, t.difficulty) then return Veyl.Err('UNAVAILABLE', 'Not available right now') end
    local v1 = pick.model and vehicleDef(pick.model)
    if not v1 then return Veyl.Err('UNAVAILABLE', 'No vehicle is available for this contract') end

    local roster = crew and Boost.Crew.roster(cid) or { { cid = cid, src = src, name = Boost.Crew.nameOf(src) } }
    if #roster > t.maxCrew then return Veyl.Err('LIMIT', ('This contract takes up to %d people'):format(t.maxCrew)) end
    if #roster < t.minCrew then return Veyl.Err('INVALID_STATE', ('This contract needs a crew of %d or more'):format(t.minCrew)) end
    if t.mode == 'solo' and #roster > 1 then return Veyl.Err('INVALID_STATE', 'This contract is solo only') end
    for _, m in ipairs(roster) do
        if not m.src or Veyl.GetCitizenId(m.src) ~= m.cid then return Veyl.Err('INVALID_STATE', ('%s is offline'):format(m.name)) end
        if Contracts.byCid[m.cid] then return Veyl.Err('INVALID_STATE', ('%s is on another contract'):format(m.name)) end
    end
    if #roster == 1 and not v1.solo then return Veyl.Err('INVALID_STATE', 'This one needs a crew') end

    -- Vehicles: the offered one, plus (for multi-vehicle contracts) others from the same pool.
    local vehicles, used = {}, { [v1.model] = true }
    for i = 1, t.vehicles do
        local def = i == 1 and v1 or pickVehicle(cid, t, used)
        if not def then return Veyl.Err('UNAVAILABLE', 'Not enough vehicles for this contract') end
        used[def.model] = true
        local spawn = C.Spawns[math.random(#C.Spawns)]
        vehicles[#vehicles + 1] = { model = def.model, label = def.label, tier = def.tier, difficulty = def.difficulty, base = def.baseReward,
            cond = def.condition or { full = 0.7 }, spawn = spawn, status = 'waiting' }
    end
    local baseSum = 0
    for _, v in ipairs(vehicles) do baseSum = baseSum + v.base end

    local drop = C.Dropoffs[math.random(#C.Dropoffs)]
    local sp = vehicles[1].spawn
    local aR = math.floor((C.Blips.Area.radius or 160.0) * 0.5)
    local c = {
        id = newContractId(), template = t, state = 'reserved', leader = cid, members = {}, order = {}, vehicles = vehicles,
        drop = drop, area = { x = sp.x + math.random(-aR, aR), y = sp.y + math.random(-aR, aR), r = C.Blips.Area.radius },
        baseSum = baseSum, reward = math.floor(baseSum * pick.roll * Boost.Heat.rewardMult(cid)), repReward = t.repReward,
        createdAt = os.time(), reserveUntil = os.time() + C.Offers.ReserveSeconds, tracked = t.tracked, attempts = {}, accessCd = {},
    }
    for _, m in ipairs(roster) do
        c.members[m.cid] = { cid = m.cid, src = m.src, name = m.name }
        c.order[#c.order + 1] = m.cid
        Contracts.byCid[m.cid] = c
    end
    Contracts.byId[c.id] = c
    o.picks[t.id] = nil -- a fresh vehicle and roll for next time
    Contracts.persist(c)
    for _, x in ipairs(c.order) do
        MySQL.update('INSERT INTO veyl_boost_members (contract_id, citizenid, role) VALUES (?, ?, ?)', { c.id, x, x == cid and 'leader' or 'member' })
    end
    if crew then Boost.Crew.attach(cid, c.id) end
    Boost.Log.audit(cid, 'accept', { contract = c.id, template = t.id, crew = #roster, reward = c.reward }, src)
    Boost.Prog.activity(cid, 'contract', ('Contract accepted: %s'):format(t.label), vehicles[1].label)

    -- A solo contract starts at once; a crew waits for the leader to start (members can still join until then).
    if #roster == 1 and t.mode ~= 'group' then return Contracts.start(src, cid) end
    Contracts.push(c)
    return Veyl.Ok({ id = c.id }, 'Contract reserved')
end

---------------------------------------------------------------------------
-- Starting: spawn the vehicles
---------------------------------------------------------------------------
function Contracts.start(src, cid)
    local c = Contracts.byCid[cid]
    if not c or c.leader ~= cid then return Veyl.Err('NO_PERMISSION', 'Only the leader can start the contract') end
    if c.state ~= 'reserved' or c.starting then return Veyl.Err('INVALID_STATE', 'The contract cannot be started') end
    if #c.order < c.template.minCrew then return Veyl.Err('INVALID_STATE', ('Needs a crew of %d or more'):format(c.template.minCrew)) end
    c.starting = true
    for _, v in ipairs(c.vehicles) do
        local res = Veyl.Await('veyl_vehicles', 'SpawnAuthorizedVehicle', 15000, { model = v.model, coords = v.spawn, temporary = true, platePrefix = 'BST' })
        if not (res and res.ok and res.data) then
            c.starting = nil
            Contracts.cleanupVehicles(c, true)
            for _, x in ipairs(c.vehicles) do x.vehicleId, x.netId = nil, nil end
            return Veyl.Err('INTERNAL', 'The contract fell through. Try again.')
        end
        v.vehicleId, v.netId = res.data.vehicleId, res.data.netId
        local e = NetworkGetEntityFromNetworkId(v.netId)
        if e ~= 0 then
            SetVehicleDoorsLocked(e, 2)
            v.plate = trim(GetVehicleNumberPlateText(e))
        end
    end
    c.starting = nil
    if c.state ~= 'reserved' then Contracts.cleanupVehicles(c, true) return Veyl.Err('INVALID_STATE', 'The contract was cancelled') end
    c.startedAt = os.time()
    c.expiresAt = os.time() + c.template.timeLimit * 60
    if not transition(c, 'active') then Contracts.cleanupVehicles(c, true) return Veyl.Err('INVALID_STATE', 'The contract cannot be started') end
    Boost.Crew.log(cid, ('Contract started: %s'):format(c.template.label))
    Contracts.push(c)
    Boost.Crew.refresh(Boost.Crew.of(cid) or { members = {} })
    return Veyl.Ok({ id = c.id }, ('Contract started: find the %s in the marked area.'):format(c.vehicles[1].label))
end

---------------------------------------------------------------------------
-- The access puzzle (server-owned)
---------------------------------------------------------------------------
local MG = C.Minigame

local function sequence(len)
    local s = {}
    for i = 1, len do s[i] = math.random(MG.Glyphs) end
    return s
end

local function stageInfo(a)
    local len = MG.BaseLength + math.floor((a.difficulty - 1) / 2) + (a.stage - 1)
    a.seq = sequence(len)
    a.shownAt = GetGameTimer()
    a.showMs = MG.ShowMsPerGlyph * len
    return { stage = a.stage, stages = a.stages, strikes = a.strikes, maxStrikes = MG.Strikes, seq = a.seq, showMs = a.showMs, maxInputMs = MG.MaxInputMs, glyphs = MG.Glyphs, token = a.token }
end

local function contractAndVehicle(src, cid, netId)
    local c = Contracts.byCid[cid]
    if not c or not (c.state == 'active' or c.state == 'vehicle_acquired' or c.state == 'delivery_started') then return nil end
    netId = tonumber(netId)
    for i, v in ipairs(c.vehicles) do
        if netId and v.netId == netId then
            local e = ent(v)
            if e == 0 or not DoesEntityExist(e) then return nil end
            return c, v, i, e
        end
    end
    return nil
end

function Contracts.accessBegin(src, cid, netId)
    local c, v, i, e = contractAndVehicle(src, cid, netId)
    if not c then Boost.Log.suspicious(src, cid, 'access_not_contract_vehicle', { netId = netId }) return Veyl.Err('NOT_FOUND', 'That is not one of your contract vehicles') end
    if v.status ~= 'waiting' then return Veyl.Err('INVALID_STATE', 'Already done') end
    local left = (c.accessCd[cid] or 0) - os.time()
    if left > 0 then return Veyl.Err('RATE_LIMITED', ('Wait %ds before trying again'):format(left)) end
    local pc = Veyl.GetPlayerCoords(src)
    if not pc or #(pc - GetEntityCoords(e)) > MG.Distance + 1.5 then return Veyl.Err('TOO_FAR', 'Get closer to the vehicle') end
    if GetVehiclePedIsIn(GetPlayerPed(src), false) ~= 0 then return Veyl.Err('INVALID_STATE', 'Get out of the vehicle first') end
    if MG.RequiredItem and (exports.veyl_inventory:GetItemCount(src, MG.RequiredItem) or 0) < 1 then return Veyl.Err('NO_ITEM', ('You need a %s'):format(MG.RequiredItem)) end
    local diff = math.min(5, math.max(1, math.floor((v.difficulty + c.template.difficulty) / 2 + 0.5)))
    local a = { token = Veyl.NewId(), vehicle = i, contract = c.id, stage = 1, stages = MG.StagesByDifficulty[diff] or 2, strikes = 0, difficulty = diff, at = os.time() }
    c.attempts[cid] = a
    return Veyl.Ok(stageInfo(a))
end

local function failAttempt(c, cid, src, v, e)
    c.attempts[cid] = nil
    c.accessCd[cid] = os.time() + MG.FailCooldownSeconds
    local profile = c.template.heat or {}
    Boost.Heat.add(cid, (profile.onFail or 0) * (BoostingConfig.Heat.FailGainMultiplier or 1), 'access_fail')
    if math.random() < (profile.chance or 0) and e and e ~= 0 then Boost.Heat.alert(cid, c, GetEntityCoords(e)) end
    local pen = BoostingConfig.Penalties.accessFail or 0
    if pen > 0 then Boost.Prog.addRep(cid, -pen, 'access_fail') end
    Boost.Log.audit(cid, 'access_fail', { contract = c.id, vehicle = v.model }, src)
end

local function acquire(c, cid, src, v, e)
    v.status = 'acquired'
    c.attempts[cid] = nil
    if e ~= 0 then SetVehicleDoorsLocked(e, 1) end
    if GetResourceState('veyl_vehiclekeys') == 'started' then
        for x in pairs(c.members) do pcall(function() exports.veyl_vehiclekeys:GiveKey(v.vehicleId, x) end) end
    end
    if c.state == 'active' then transition(c, 'vehicle_acquired') else Contracts.persist(c) end
    if e ~= 0 then Boost.Heat.roll(cid, c, GetEntityCoords(e), 'access') end
    Boost.Log.audit(cid, 'acquired', { contract = c.id, vehicle = v.model }, src)
    Boost.Crew.log(cid, ('%s: access complete'):format(v.label))
    Contracts.push(c)
end

--- One stage answer. Returns the next stage, a retry, success or failure. The answer and its timing are checked here.
function Contracts.accessSubmit(src, cid, token, answer)
    local c = Contracts.byCid[cid]
    local a = c and c.attempts[cid]
    if not a or a.token ~= token then Boost.Log.suspicious(src, cid, 'access_bad_token', {}) return Veyl.Err('INVALID_STATE', 'Start again') end
    local v = c.vehicles[a.vehicle]
    local e = ent(v)
    if os.time() - a.at > MG.AttemptTimeoutSeconds or e == 0 or v.status ~= 'waiting' then c.attempts[cid] = nil return Veyl.Err('INVALID_STATE', 'That attempt ended') end
    local pc = Veyl.GetPlayerCoords(src)
    if not pc or #(pc - GetEntityCoords(e)) > MG.Distance + 3.0 then c.attempts[cid] = nil return Veyl.Err('TOO_FAR', 'You moved away') end
    if type(answer) ~= 'table' or #answer ~= #a.seq then return Veyl.Err('INVALID_INPUT', 'Bad answer') end
    local elapsed = GetGameTimer() - a.shownAt
    if elapsed < a.showMs + MG.MinInputMsPerGlyph * #a.seq then
        Boost.Log.suspicious(src, cid, 'access_too_fast', { elapsed = elapsed })
        failAttempt(c, cid, src, v, e)
        return Veyl.Ok({ result = 'failed' }, 'The signal dropped')
    end
    local right = elapsed <= a.showMs + MG.MaxInputMs
    for i = 1, #a.seq do if math.tointeger(answer[i]) ~= a.seq[i] then right = false break end end
    if not right then
        a.strikes = a.strikes + 1
        if a.strikes >= MG.Strikes then
            failAttempt(c, cid, src, v, e)
            return Veyl.Ok({ result = 'failed' }, 'The signal dropped')
        end
        return Veyl.Ok({ result = 'retry', stage = stageInfo(a) })
    end
    a.stage = a.stage + 1
    if a.stage > a.stages then
        acquire(c, cid, src, v, e)
        return Veyl.Ok({ result = 'success' }, ('%s unlocked'):format(v.label))
    end
    return Veyl.Ok({ result = 'next', stage = stageInfo(a) })
end

function Contracts.accessAbort(cid)
    local c = Contracts.byCid[cid]
    if c then c.attempts[cid] = nil end
end

---------------------------------------------------------------------------
-- Tracker
---------------------------------------------------------------------------
function Contracts.trackerStart(src, cid, netId)
    local c, v = contractAndVehicle(src, cid, netId)
    if not c or not c.tracked or c.trackerOff then return Veyl.Err('INVALID_STATE', 'No tracker on this one') end
    local pc, e = Veyl.GetPlayerCoords(src), ent(v)
    if not pc or e == 0 or #(pc - GetEntityCoords(e)) > 6.0 then return Veyl.Err('TOO_FAR', 'Get closer') end
    if C.Tracker.Item and (exports.veyl_inventory:GetItemCount(src, C.Tracker.Item) or 0) < 1 then return Veyl.Err('NO_ITEM', 'You need a hacking device') end
    c.trackerJob = { token = Veyl.NewId(), at = GetGameTimer(), cid = cid, netId = v.netId }
    return Veyl.Ok({ token = c.trackerJob.token, seconds = C.Tracker.DisableSeconds })
end

function Contracts.trackerFinish(src, cid, token)
    local c = Contracts.byCid[cid]
    local job = c and c.trackerJob
    if c then c.trackerJob = nil end
    if not job or job.token ~= token or job.cid ~= cid then return Veyl.Err('INVALID_STATE', 'Start again') end
    if GetGameTimer() - job.at < C.Tracker.DisableSeconds * 1000 - 600 then Boost.Log.suspicious(src, cid, 'tracker_too_fast', {}) return Veyl.Err('TOO_FAST', 'You stopped too early') end
    if C.Tracker.Item and C.Tracker.ConsumeChance > 0 and math.random() < C.Tracker.ConsumeChance then exports.veyl_inventory:RemoveItem(src, C.Tracker.Item, 1) end
    c.trackerOff = true
    Contracts.push(c)
    return Veyl.Ok(nil, 'Tracker disabled')
end

---------------------------------------------------------------------------
-- Delivery
---------------------------------------------------------------------------
local function condition(e)
    local engine, body = GetVehicleEngineHealth(e) / 1000.0, GetVehicleBodyHealth(e) / 1000.0
    -- 0 exactly means the server has no synced reading yet (not a wreck): treat as undamaged rather than guess.
    if GetVehicleEngineHealth(e) == 0 then engine = 1.0 end
    if GetVehicleBodyHealth(e) == 0 then body = 1.0 end
    return math.min(1.0, engine, body)
end

function Contracts.deliver(src, cid)
    local c = Contracts.byCid[cid]
    if not c or c.state ~= 'delivery_started' then return Veyl.Err('INVALID_STATE', 'Nothing to hand over yet') end
    if c.finishing or c.delivering then return Veyl.Err('BUSY', 'One moment') end
    local pc = Veyl.GetPlayerCoords(src)
    local dropAt = c.drop.coords
    if not pc or #(pc - dropAt) > C.Delivery.PlayerRadius then return Veyl.Err('TOO_FAR', 'Go to the handoff point') end
    local ped = GetPlayerPed(src)
    -- The vehicle nearest the handoff that is acquired and not yet delivered.
    local best, bestIdx, bestEnt, bestD
    for i, v in ipairs(c.vehicles) do
        if v.status == 'acquired' then
            local e = ent(v)
            if e ~= 0 and DoesEntityExist(e) then
                local d = #(GetEntityCoords(e) - dropAt)
                if d <= C.Delivery.Radius and (not bestD or d < bestD) then best, bestIdx, bestEnt, bestD = v, i, e, d end
            end
        end
    end
    if not best then return Veyl.Err('TOO_FAR', 'Park the vehicle on the handoff point') end
    -- Identity: model and plate must match what the server spawned.
    if GetEntityModel(bestEnt) ~= joaat(best.model) or (best.plate and best.plate ~= '' and trim(GetVehicleNumberPlateText(bestEnt)) ~= best.plate) then
        Boost.Log.suspicious(src, cid, 'delivery_identity', { contract = c.id, model = best.model })
        return Veyl.Err('INVALID_STATE', 'That is not the contract vehicle')
    end
    if C.Delivery.RequireOnFoot and GetVehiclePedIsIn(ped, false) == bestEnt then return Veyl.Err('INVALID_STATE', 'Get out and step away from it') end
    local cond = condition(bestEnt)
    if cond < C.Delivery.MinCondition then return Veyl.Err('INVALID_STATE', 'The buyer will not take it in that state') end

    c.delivering = true
    best.status = 'delivered'
    local full = best.cond.full or 0.7
    local mod = cond >= full and 1.0 or (C.Delivery.MinPayFraction + (1 - C.Delivery.MinPayFraction) * math.max(0, (cond - C.Delivery.MinCondition) / math.max(0.01, full - C.Delivery.MinCondition)))
    best.paid = math.floor(c.reward * (best.base / c.baseSum) * mod)
    best.deliveredBy = cid
    local remaining = 0
    for _, v in ipairs(c.vehicles) do if v.status ~= 'delivered' then remaining = remaining + 1 end end
    Contracts.persist(c)
    c.delivering = nil
    if remaining > 0 then
        Contracts.push(c)
        return Veyl.Ok({ remaining = remaining }, ('%s delivered. %d more to go.'):format(best.label, remaining))
    end
    return Contracts.complete(c, src)
end

---------------------------------------------------------------------------
-- Ending a contract
---------------------------------------------------------------------------
function Contracts.cleanupVehicles(c, now)
    local list = {}
    for _, v in ipairs(c.vehicles) do if v.vehicleId then list[#list + 1] = v.vehicleId end end
    local function go() for _, id in ipairs(list) do pcall(function() exports.veyl_vehicles:DeleteVehicle(id) end) end end
    if now then go() else SetTimeout(C.Cleanup.DeleteDelaySeconds * 1000, go) end
end

local function release(c)
    Boost.Crew.detach(c.leader)
    for cid in pairs(c.members) do
        if Contracts.byCid[cid] == c then Contracts.byCid[cid] = nil end
        Boost.Prog.setCooldown(cid, 'tpl:' .. c.template.id, c.template.cooldown or 0)
    end
    Contracts.byId[c.id] = nil
end

--- Completes the contract: pays every member their share once (idempotent by operation id) and awards reputation.
function Contracts.complete(c, src)
    if c.finishing then return Veyl.Err('BUSY', 'Already finishing') end
    c.finishing = true
    if not transition(c, 'completed') then c.finishing = nil return Veyl.Err('INVALID_STATE', 'The contract cannot be completed') end
    c.endedAt = os.time()
    c.result = 'completed'
    local elapsed = c.endedAt - (c.startedAt or c.endedAt)
    local total = 0
    for _, v in ipairs(c.vehicles) do total = total + (v.paid or 0) end
    local t = c.template
    if t.fastBonus and elapsed <= t.timeLimit * 60 * t.fastBonus.within then total = math.floor(total * t.fastBonus.mult) end
    local n = #c.order
    total = math.floor(total * (1 + K.GroupPayBonus * math.max(0, n - 1)))
    c.payout = total

    -- Shares.
    local shares = {}
    if K.Split == 'leader' and n > 1 then
        local bonus = math.floor(total * K.LeaderBonus)
        local each = math.floor((total - bonus) / n)
        for _, x in ipairs(c.order) do shares[x] = each + (x == c.leader and bonus or 0) end
    else
        local each = math.floor(total / n)
        for _, x in ipairs(c.order) do shares[x] = each end
    end
    for _, x in ipairs(c.order) do
        MySQL.update.await('UPDATE veyl_boost_members SET share = ?, rep = ? WHERE contract_id = ? AND citizenid = ?', { shares[x], c.repReward, c.id, x })
    end
    Contracts.persist(c)

    local members = {}
    for _, x in ipairs(c.order) do members[#members + 1] = x end
    local msgs = {}
    for _, x in ipairs(members) do
        local share = shares[x]
        -- One credit per contract and person, whatever happens with retries or a crash in between (see reconcile at start).
        if share > 0 then
            core('CreditOnce', x, 'cash', share, ('Boosting: %s'):format(t.label), ('boost:%s:%s'):format(c.id, x))
        end
        MySQL.update('UPDATE veyl_boost_members SET paid = 1 WHERE contract_id = ? AND citizenid = ?', { c.id, x })
        local rep, rank, up = Boost.Prog.addRep(x, c.repReward, 'contract')
        Boost.Prog.record(x, true, share, elapsed, t.id)
        Boost.Prog.activity(x, 'complete', ('Contract Completed: %s'):format(t.label), ('+$%d | +%d Rep'):format(share, c.repReward))
        local done = Boost.Prog.bump(x, 'completed', 1)
        for _, d in ipairs(Boost.Prog.bump(x, 'earned', share)) do done[#done + 1] = d end
        local msrc = c.members[x] and c.members[x].src
        if msrc then
            Veyl.Notify(msrc, ('Contract complete. $%d cash and +%d reputation.%s'):format(share, c.repReward, up and (' Rank up: ' .. rank.label .. '!') or ''), 'success')
            for _, d in ipairs(done) do Veyl.Notify(msrc, ('Challenge complete: %s (+$%d)'):format(d.label, d.reward), 'success') end
        end
    end
    Boost.Log.audit(c.leader, 'complete', { contract = c.id, payout = total, members = n, seconds = elapsed }, src)
    Contracts.cleanupVehicles(c, false)
    pushNone(c)
    local ref = Boost.Crew.of(c.leader)
    release(c)
    if ref then Boost.Crew.refresh(ref) end
    return Veyl.Ok({ payout = total }, ('Delivered. $%d total.'):format(total))
end

--- Ends the contract without a payout: failed / expired / cancelled, with the configured penalties.
function Contracts.finish(c, state, reason)
    if c.finishing then return false end
    c.finishing = true
    if not transition(c, state) then c.finishing = nil return false end
    c.endedAt, c.result = os.time(), reason or state
    Contracts.persist(c)
    local P = BoostingConfig.Penalties
    local acquired = 0
    for _, v in ipairs(c.vehicles) do if v.status ~= 'waiting' then acquired = acquired + 1 end end
    local started = c.startedAt ~= nil
    local pen = state == 'failed' and P.failed or state == 'expired' and (started and P.expired or 0)
        or state == 'cancelled' and (acquired > 0 and P.cancelledAcquired or P.cancelledActive) or 0
    for cid, m in pairs(c.members) do
        if pen and pen > 0 and started then Boost.Prog.addRep(cid, -pen, state) end
        if started and (state == 'failed' or state == 'expired' or (state == 'cancelled' and acquired > 0)) then Boost.Prog.record(cid, false) end
        if state == 'failed' then Boost.Heat.add(cid, c.template.heat.onFail or 0, 'contract_failed') end
        Boost.Prog.activity(cid, 'fail', ('Contract %s: %s'):format(state, c.template.label), pen and pen > 0 and started and ('-%d Rep'):format(pen) or nil)
        if m.src then
            local text = state == 'expired' and 'Your boosting contract ran out of time.' or state == 'failed' and 'The contract failed.' or 'Contract dropped.'
            Veyl.Notify(m.src, text, state == 'cancelled' and 'info' or 'error')
        end
    end
    Boost.Log.audit(c.leader, state, { contract = c.id, reason = reason }, nil)
    Contracts.cleanupVehicles(c, true)
    pushNone(c)
    local ref = Boost.Crew.of(c.leader)
    release(c)
    if ref then Boost.Crew.refresh(ref) end
    return true
end

function Contracts.cancel(src, cid)
    local c = Contracts.byCid[cid]
    if not c then return Veyl.Err('NOT_FOUND', 'You have no contract') end
    if c.leader ~= cid then return Veyl.Err('NO_PERMISSION', 'Only the crew leader can cancel the contract') end
    if not S.Live[c.state] then return Veyl.Err('INVALID_STATE', 'It already ended') end
    Contracts.finish(c, 'cancelled', 'leader_cancel')
    return Veyl.Ok(nil, 'Contract dropped')
end

---------------------------------------------------------------------------
-- Supervision: time limits, lost vehicles, disconnects, tracker pings
---------------------------------------------------------------------------
function Contracts.tick()
    local now = os.time()
    for _, c in pairs(Contracts.byId) do
        if not c.finishing and not c.starting and S.Live[c.state] then
            if c.state == 'reserved' then
                if now > c.reserveUntil then Contracts.finish(c, 'expired', 'reserve_timeout') end
            elseif now > (c.expiresAt or now + 1) then
                Contracts.finish(c, 'expired', 'time')
            else
                -- Vehicle lost or wrecked?
                local lost
                for _, v in ipairs(c.vehicles) do
                    if v.status ~= 'delivered' then
                        local e = ent(v)
                        if e == 0 or not DoesEntityExist(e) or GetVehicleEngineHealth(e) < -100 then lost = v end
                    end
                end
                if lost then
                    Contracts.finish(c, 'failed', 'vehicle_lost')
                else
                    -- Everyone offline too long?
                    local anyOnline, oldest = false, now
                    for _, m in pairs(c.members) do
                        if m.src then anyOnline = true elseif (m.offlineAt or now) < oldest then oldest = m.offlineAt end
                    end
                    if not anyOnline and now - oldest > C.Cleanup.DisconnectGraceSeconds then
                        Contracts.finish(c, 'expired', 'disconnected')
                    elseif c.state == 'vehicle_acquired' then
                        -- Someone drives an acquired vehicle: the delivery has begun.
                        for _, v in ipairs(c.vehicles) do
                            local e = v.status == 'acquired' and ent(v) or 0
                            if e ~= 0 then
                                local driver = GetPedInVehicleSeat(e, -1)
                                for _, m in pairs(c.members) do
                                    if m.src and driver ~= 0 and driver == GetPlayerPed(m.src) and c.state == 'vehicle_acquired' then
                                        transition(c, 'delivery_started')
                                        Contracts.push(c)
                                    end
                                end
                            end
                        end
                    end
                    -- Tracker pings.
                    if c.tracked and not c.trackerOff and (c.state == 'vehicle_acquired' or c.state == 'delivery_started') and now - (c.lastPing or 0) >= C.Tracker.PingSeconds then
                        c.lastPing = now
                        for _, v in ipairs(c.vehicles) do
                            local e = v.status == 'acquired' and ent(v) or 0
                            if e ~= 0 then Boost.Dispatch.send(GetEntityCoords(e), ('Tracker ping: %s (%s)'):format(v.label, v.plate or '?'), { title = 'Stolen vehicle tracker' }) end
                        end
                    end
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Players leaving and returning
---------------------------------------------------------------------------
function Contracts.onDrop(cid)
    local c = Contracts.byCid[cid]
    if c and c.members[cid] then
        c.members[cid].src = nil
        c.members[cid].offlineAt = os.time()
        c.attempts[cid] = nil
    end
    Boost.Crew.drop(cid)
    Contracts.offers[cid] = nil
end

function Contracts.onBack(cid, src)
    local c = Contracts.byCid[cid]
    if c and c.members[cid] then
        c.members[cid].src = src
        c.members[cid].offlineAt = nil
        TriggerClientEvent('veyl_boosting:contract', src, Contracts.view(c, cid))
    end
    Boost.Crew.back(cid, src)
end

---------------------------------------------------------------------------
-- Start-up reconciliation and shutdown
---------------------------------------------------------------------------
function Contracts.reconcile()
    -- Contracts that were running when the server stopped: their vehicles are gone. They end without a penalty.
    MySQL.update.await([[UPDATE veyl_boost_contracts SET state = 'expired', result = 'server_restart', ended_at = ?
        WHERE state IN ('reserved', 'active', 'vehicle_acquired', 'delivery_started')]], { os.time() })
    -- Rewards that were decided but not recorded as paid (a crash between the two): credit them again; CreditOnce makes that safe.
    local rows = MySQL.query.await([[SELECT m.contract_id, m.citizenid, m.share FROM veyl_boost_members m
        JOIN veyl_boost_contracts c ON c.id = m.contract_id WHERE c.state = 'completed' AND m.paid = 0 AND m.share > 0]]) or {}
    for _, r in ipairs(rows) do
        core('CreditOnce', r.citizenid, 'cash', r.share, 'Boosting payout (recovered)', ('boost:%s:%s'):format(r.contract_id, r.citizenid))
        MySQL.update.await('UPDATE veyl_boost_members SET paid = 1 WHERE contract_id = ? AND citizenid = ?', { r.contract_id, r.citizenid })
        Boost.Log.audit(r.citizenid, 'payout_recovered', { contract = r.contract_id, share = r.share })
    end
end

function Contracts.shutdown()
    for _, c in pairs(Contracts.byId) do
        Contracts.cleanupVehicles(c, true)
        if S.Live[c.state] then
            c.state, c.result, c.endedAt = 'expired', 'resource_stop', os.time()
            Contracts.persist(c)
        end
    end
end
