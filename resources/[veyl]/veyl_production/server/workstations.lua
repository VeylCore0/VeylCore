-- Workstations: placeable benches with a queue of timed batches (the shared workstation engine). A batch's times are absolute server
-- timestamps, so progress is the same after a restart; output is claimed once (atomic state change + idempotent inventory operation).

Prod = Prod or {}
Prod.Ws = { rows = {} }
local Ws = Prod.Ws
local C = ProductionConfig
local W = C.Workstations

function Ws.load()
    Ws.rows = {}
    for _, r in ipairs(MySQL.query.await('SELECT * FROM veyl_prod_workstations') or {}) do Ws.rows[r.id] = r end
end

local function typeOf(row) return W.Types[row.type] end

--- May this player use this bench? Owners always; lab members with the `bench` permission for benches in their lab.
local function canUse(cid, row)
    if row.owner_cid == cid then return true end
    if row.property_id == nil and Prod.Crews and Prod.Crews.shares(row.owner_cid, cid) then return true end
    return row.property_id ~= nil and Prod.Props.can(cid, row.property_id, 'bench')
end

local function activeBatches(wsId)
    return MySQL.query.await("SELECT * FROM veyl_prod_batches WHERE workstation_id = ? AND state = 'active' ORDER BY id", { wsId }) or {}
end

local function batchView(b, now)
    local r = W.Recipes[b.recipe]
    local stages = json.decode(b.stages) or {}
    local state = now >= b.ends_at and 'done' or now >= b.starts_at and 'running' or 'queued'
    local out = { id = b.id, recipe = b.recipe, label = r and r.label or b.recipe, state = state, startsAt = b.starts_at, endsAt = b.ends_at,
        quality = math.floor(b.quality), tier = r and r.noQuality and nil or ProdUtil.tier(b.quality).label, output = r and r.output, stage = nil, progress = 0 }
    if state == 'running' then
        out.progress = (now - b.starts_at) / math.max(1, b.ends_at - b.starts_at)
        local t = b.starts_at
        for _, s in ipairs(stages) do
            if now < t + s.seconds then out.stage = s.label break end
            t = t + s.seconds
        end
    elseif state == 'done' then out.progress = 1 end
    return out
end

--- What the tablet and the bench menu show for one workstation.
function Ws.view(row, cid)
    local now = os.time()
    local t = typeOf(row)
    local batches = {}
    for _, b in ipairs(activeBatches(row.id)) do batches[#batches + 1] = batchView(b, now) end
    local recipes = {}
    for id, r in pairs(W.Recipes) do
        for _, ty in ipairs(r.types) do
            if ty == row.type then
                recipes[#recipes + 1] = { id = id, label = r.label, level = r.level, branch = r.branch, locked = Prod.Prog.level(cid, r.branch) < r.level, inputs = r.inputs, output = r.output,
                    skill = r.skill and r.skill.rounds or nil, hazard = r.hazard == true, noQuality = r.noQuality == true,
                    seconds = (function() local s = 0 for _, st in ipairs(r.stages) do s = s + st.seconds end return math.floor(s * (t.speed * Prod.Props.benchSpeed(row.property_id))) end)(),
                    stages = r.stages }
            end
        end
    end
    table.sort(recipes, function(a, b) return a.level < b.level or (a.level == b.level and a.id < b.id) end)
    return { id = row.id, type = row.type, label = t and t.label or row.type, property = row.property_id, mine = row.owner_cid == cid, x = row.x, y = row.y,
        slots = t and t.slots or 0, batches = batches, recipes = recipes, serverTime = now }
end

function Ws.list(cid)
    local out = {}
    for _, r in pairs(Ws.rows) do
        local t = typeOf(r)
        out[#out + 1] = { id = r.id, type = r.type, model = t and t.model, x = r.x, y = r.y, z = r.z, heading = r.heading, property = r.property_id, mine = r.owner_cid == cid, use = canUse(cid, r) }
    end
    return out
end

function Ws.mine(cid)
    local out = {}
    for _, r in pairs(Ws.rows) do if canUse(cid, r) then out[#out + 1] = Ws.view(r, cid) end end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

local function count(cid, propertyId)
    local n = 0
    for _, r in pairs(Ws.rows) do
        if (propertyId and r.property_id == propertyId) or (not propertyId and r.owner_cid == cid and not r.property_id) then n = n + 1 end
    end
    return n
end

function Ws.countIn(propertyId) return count(nil, propertyId) end

---------------------------------------------------------------------------
-- Placement
---------------------------------------------------------------------------
function Ws.place(src, cid, d)
    local tkey = Prod.Sec.str(d.type, 24, '^[%w_]+$')
    local t = tkey and W.Types[tkey]
    if not t then Prod.Sec.invalid(src, cid, 'ws_bad_type') return Veyl.Err('INVALID_INPUT', 'Unknown workstation') end
    local pos, heading = Prod.Place.position(d)
    if not pos then Prod.Sec.invalid(src, cid, 'ws_bad_position') return Veyl.Err('INVALID_INPUT', 'Bad position') end
    local propertyId = d.property and Prod.Sec.str(d.property, 32, '^[%w_]+$') or nil
    if t.portable and propertyId then return Veyl.Err('INVALID_INPUT', 'That bench is for outdoors') end
    if not t.portable and not propertyId then return Veyl.Err('INVALID_INPUT', 'That bench belongs in a laboratory') end
    if propertyId then
        if not Prod.Props.can(cid, propertyId, 'bench') then return Veyl.Err('NO_PERMISSION', 'You cannot set up benches here') end
        local pd = Prod.Props.def(propertyId)
        if pd and pd.branch ~= t.branch then return Veyl.Err('INVALID_INPUT', ('That bench belongs in a %s laboratory'):format(t.branch)) end
        if count(nil, propertyId) >= Prod.Props.benchSlots(propertyId) then return Veyl.Err('LIMIT', 'No free bench slots in this laboratory. Upgrade it for more.') end
    elseif count(cid, nil) >= C.Placement.MaxWorkstationsPerPlayer then
        return Veyl.Err('LIMIT', ('You can keep %d portable benches'):format(C.Placement.MaxWorkstationsPerPlayer))
    end
    local others = {}
    for _, r in pairs(Prod.Plants.rows) do others[#others + 1] = r end
    for _, w in pairs(Ws.rows) do others[#others + 1] = w end
    local why = Prod.Place.problem(src, cid, pos, propertyId, others)
    if why then return Veyl.Err('INVALID_PLACEMENT', why) end
    if not Prod.Sec.try(cid, 'place', C.Cooldowns.Place) then return Veyl.Err('RATE_LIMITED', 'Slow down') end
    local taken = Prod.Inv.take(cid, t.item, 1, nil, ('prodws:%s:%s'):format(cid, Veyl.NewId()))
    if not (taken and taken.ok) then return Veyl.Err('NO_ITEM', ('You need a %s'):format(ProdItemLabels[t.item])) end
    local now = os.time()
    local id = MySQL.insert.await('INSERT INTO veyl_prod_workstations (owner_cid, type, x, y, z, heading, property_id, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        { cid, tkey, pos.x, pos.y, pos.z, heading, propertyId, now })
    if not id then
        Prod.Inv.give(cid, t.item, 1, nil, ('prodws:undo:%s'):format(Veyl.NewId()))
        return Veyl.Err('DATABASE_ERROR', 'Could not set it up')
    end
    Ws.rows[id] = { id = id, owner_cid = cid, type = tkey, x = pos.x, y = pos.y, z = pos.z, heading = heading, property_id = propertyId, created_at = now }
    Prod.Log.event('craft', cid, ('set up %s #%d'):format(tkey, id))
    TriggerClientEvent('veyl_production:refresh', -1, 'workstations')
    return Veyl.Ok({ id = id }, ('%s set up'):format(t.label))
end

local function target(src, cid, id)
    id = Prod.Sec.int(id, 2147483647)
    local row = id and Ws.rows[id]
    if not row then return nil, Veyl.Err('NOT_FOUND', 'That bench is gone') end
    if not Prod.Sec.near(src, row, C.Distance.Workstation) then return nil, Veyl.Err('TOO_FAR', 'Get closer') end
    if not canUse(cid, row) then Prod.Sec.invalid(src, cid, 'ws_not_yours', { id = id }) return nil, Veyl.Err('NO_PERMISSION', 'You cannot use that') end
    return row
end

function Ws.open(src, cid, id)
    local row, err = target(src, cid, id)
    if not row then return err end
    return Veyl.Ok(Ws.view(row, cid))
end

--- Pack a bench up and get the item back. Not while it still holds work.
function Ws.packup(src, cid, id)
    local row, err = target(src, cid, id)
    if not row then return err end
    if row.owner_cid ~= cid and not (row.property_id and Prod.Props.can(cid, row.property_id, 'manage')) then return Veyl.Err('NO_PERMISSION', 'Only the owner can pack it up') end
    if #activeBatches(row.id) > 0 then return Veyl.Err('INVALID_STATE', 'Finish or cancel its batches first') end
    local t = typeOf(row)
    local removed = MySQL.update.await('DELETE FROM veyl_prod_workstations WHERE id = ?', { row.id })
    if (removed or 0) < 1 then return Veyl.Err('NOT_FOUND', 'That bench is gone') end
    Ws.rows[row.id] = nil
    Prod.Inv.give(cid, t.item, 1, nil, ('prodws:pack:%d'):format(row.id))
    Prod.Log.event('craft', cid, ('packed up bench #%d'):format(row.id))
    TriggerClientEvent('veyl_production:refresh', -1, 'workstations')
    return Veyl.Ok(nil, 'Packed up')
end

---------------------------------------------------------------------------
-- Batches
---------------------------------------------------------------------------
--- Quality of a finished batch: average input quality, skill, bench and equipment bonuses and a random variation.
local function rollQuality(inputAvg, level, bonus)
    local q = inputAvg + C.Quality.PerLevel * (level - 1) * 0.5 + bonus + math.random(-C.Quality.Variance, C.Quality.Variance)
    return ProdUtil.clamp(ProdUtil.round(q), 1, 100)
end

local challenges = {} -- [src] = { token, ws, recipe, at }
local S = ProductionConfig.Supplier

--- Starts a skill check for a recipe that has one. The server notes when it began; the page runs the rounds and reports a score.
function Ws.challenge(src, cid, id, recipeId)
    local row, err = target(src, cid, id)
    if not row then return err end
    recipeId = Prod.Sec.str(recipeId, 24, '^[%w_]+$')
    local r = recipeId and W.Recipes[recipeId]
    if not r or not r.skill then return Veyl.Err('INVALID_INPUT', 'That recipe has no skill check') end
    if Prod.Prog.level(cid, r.branch) < r.level then return Veyl.Err('LEVEL_REQUIRED', ('Needs %s level %d'):format(r.branch, r.level)) end
    local token = Veyl.NewId()
    challenges[src] = { token = token, ws = row.id, recipe = recipeId, at = GetGameTimer(), cid = cid }
    return Veyl.Ok({ token = token, rounds = r.skill.rounds, difficulty = S and S.Skill.Difficulty or 'medium' })
end
AddEventHandler('playerDropped', function() challenges[source] = nil end)

function Ws.start(src, cid, id, recipeId, token, score)
    local row, err = target(src, cid, id)
    if not row then return err end
    recipeId = Prod.Sec.str(recipeId, 24, '^[%w_]+$')
    local r = recipeId and W.Recipes[recipeId]
    local t = typeOf(row)
    local allowed = false
    if r then for _, ty in ipairs(r.types) do if ty == row.type then allowed = true end end end
    if not allowed then Prod.Sec.invalid(src, cid, 'ws_bad_recipe', { recipe = recipeId }) return Veyl.Err('INVALID_INPUT', 'That bench cannot do that') end
    local level = Prod.Prog.level(cid, r.branch)
    if level < r.level then return Veyl.Err('LEVEL_REQUIRED', ('Needs %s level %d'):format(r.branch, r.level)) end
    -- A recipe with a skill check needs a finished check: right player, bench and recipe, long enough since it began, a score within the rounds.
    local swing, yieldPct = 0, 1.0
    if r.skill then
        local ch = challenges[src]
        challenges[src] = nil
        if not ch or ch.token ~= token or ch.cid ~= cid or ch.ws ~= row.id or ch.recipe ~= recipeId then Prod.Sec.invalid(src, cid, 'ws_bad_challenge') return Veyl.Err('SKILL_REQUIRED', 'Do the check first') end
        score = Prod.Sec.int(score, r.skill.rounds)
        if not score then Prod.Sec.invalid(src, cid, 'ws_bad_score') return Veyl.Err('INVALID_INPUT', 'Bad score') end
        if GetGameTimer() - ch.at < r.skill.rounds * S.Skill.MinRoundSeconds * 1000 - 500 then Prod.Sec.invalid(src, cid, 'ws_skill_too_fast') return Veyl.Err('TOO_FAST', 'You rushed the check') end
        swing = (score / r.skill.rounds - 0.5) * 2 * S.Skill.QualitySwing
        if score == 0 then yieldPct = S.Skill.ZeroYield end
    end
    local active = activeBatches(row.id)
    if #active >= t.slots then return Veyl.Err('LIMIT', 'The queue is full') end

    local batchTag = ('prodin:%s:%s'):format(cid, Veyl.NewId())
    local taken, qsum, qn, variety = {}, 0, 0, nil
    for i, input in ipairs(r.inputs) do
        local res = Prod.Inv.takeBest(src, cid, input.item, input.count, ('%s:%d'):format(batchTag, i))
        if not res.ok then
            for j, g in ipairs(taken) do Prod.Inv.refund(cid, g.groups, g.item, ('%s:undo:%d'):format(batchTag, j), 1.0) end
            return Veyl.Err(res.code or 'NO_ITEM', ('You need %d x %s'):format(input.count, ProdItemLabels[input.item] or input.item))
        end
        taken[#taken + 1] = { item = input.item, groups = res.groups }
        if ProdQualityItems[input.item] then qsum = qsum + res.avg qn = qn + 1 end
        variety = variety or res.variety
    end
    local speed = t.speed * Prod.Props.benchSpeed(row.property_id)
    local stages, total = {}, 0
    for _, s in ipairs(r.stages) do
        local secs = math.max(1, math.floor(s.seconds * speed + 0.5))
        stages[#stages + 1] = { label = s.label, seconds = secs }
        total = total + secs
    end
    local now = os.time()
    local startsAt = now
    for _, b in ipairs(active) do if b.ends_at > startsAt then startsAt = b.ends_at end end
    local quality = r.noQuality and 0 or rollQuality(qn > 0 and qsum / qn or 40, level, (t.qualityBonus or 0) + Prod.Props.benchBonus(row.property_id) + swing)
    local batchId = MySQL.insert.await([[INSERT INTO veyl_prod_batches (workstation_id, owner_cid, recipe, state, input_quality, variety, quality, starts_at, ends_at, stages, refund, created_at, yield_pct)
        VALUES (?, ?, ?, 'active', ?, ?, ?, ?, ?, ?, ?, ?, ?)]], { row.id, cid, recipeId, qn > 0 and qsum / qn or 0, variety, quality, startsAt, startsAt + total, json.encode(stages), json.encode(taken), now, yieldPct })
    if not batchId then
        for j, g in ipairs(taken) do Prod.Inv.refund(cid, g.groups, g.item, ('%s:undo:%d'):format(batchTag, j), 1.0) end
        return Veyl.Err('DATABASE_ERROR', 'Could not start the batch')
    end
    Prod.Log.event('craft', cid, ('started %s on bench #%d'):format(recipeId, row.id), { batch = batchId })
    Prod.Police.maybeAlert(cid, 'workstation', row)
    return Veyl.Ok(Ws.view(row, cid), ('%s queued'):format(r.label))
end

--- Collects everything finished on this bench that is yours. Each batch is claimed once.
function Ws.claim(src, cid, id)
    local row, err = target(src, cid, id)
    if not row then return err end
    local now = os.time()
    local got, lines, any = 0, {}, false
    for _, b in ipairs(activeBatches(row.id)) do
        if b.ends_at <= now and (b.owner_cid == cid or row.owner_cid == cid) then
            any = true
            local r = W.Recipes[b.recipe]
            local meta = r.noQuality and nil or Prod.Inv.productMeta(b.variety, b.quality, ('B%d'):format(b.id), r.branch)
            local n = math.max(1, math.floor(r.output.count * (b.yield_pct or 1) + 0.0001))
            if not Prod.Inv.canCarry(cid, r.output.item, n, meta) then
                lines[#lines + 1] = 'Not enough room for ' .. r.label
                break
            end
            -- Only the caller that flips active -> claimed gets the output; the operation id makes a retry after a crash safe.
            local flipped = MySQL.update.await("UPDATE veyl_prod_batches SET state = 'claimed', claimed_at = ? WHERE id = ? AND state = 'active' AND ends_at <= ?", { now, b.id, now })
            if (flipped or 0) > 0 then
                local g = Prod.Inv.give(cid, r.output.item, n, meta, ('prodbatch:%d'):format(b.id))
                if g and g.ok then
                    got = got + n
                    Prod.Prog.award(cid, r.branch, 'craft')
                    Prod.Prog.stat(cid, 'batches_completed')
                    Prod.Log.event('craft', cid, ('collected %s (bench #%d)'):format(r.label, row.id), { batch = b.id })
                    lines[#lines + 1] = ('%d x %s'):format(n, ProdItemLabels[r.output.item] or r.output.item)
                else
                    MySQL.update("UPDATE veyl_prod_batches SET state = 'active', claimed_at = NULL WHERE id = ? AND state = 'claimed'", { b.id })
                    lines[#lines + 1] = 'Could not collect ' .. r.label
                end
            end
        end
    end
    if not any then return Veyl.Err('NOTHING_READY', 'Nothing is ready yet') end
    return Veyl.Ok(Ws.view(row, cid), #lines > 0 and ('Collected: ' .. table.concat(lines, ', ')) or 'Nothing collected')
end

--- Cancels a queued or running batch. Queued: full refund. Running: the configured share. Later batches move up.
function Ws.cancel(src, cid, id, batchId)
    local row, err = target(src, cid, id)
    if not row then return err end
    batchId = Prod.Sec.int(batchId, 2147483647)
    local b = batchId and MySQL.single.await("SELECT * FROM veyl_prod_batches WHERE id = ? AND workstation_id = ? AND state = 'active'", { batchId, row.id })
    if not b then return Veyl.Err('NOT_FOUND', 'That batch is not active') end
    if b.owner_cid ~= cid and row.owner_cid ~= cid then return Veyl.Err('NO_PERMISSION', 'Not your batch') end
    local now = os.time()
    if b.ends_at <= now then return Veyl.Err('INVALID_STATE', 'It already finished: collect it instead') end
    local flipped = MySQL.update.await("UPDATE veyl_prod_batches SET state = 'cancelled' WHERE id = ? AND state = 'active' AND ends_at > ?", { b.id, now })
    if (flipped or 0) < 1 then return Veyl.Err('INVALID_STATE', 'It just finished') end
    local fraction = now < b.starts_at and 1.0 or W.RunningRefund
    for i, g in ipairs(json.decode(b.refund) or {}) do Prod.Inv.refund(b.owner_cid, g.groups, g.item, ('prodrefund:%d:%d'):format(b.id, i), fraction) end
    local delta = b.ends_at - math.max(now, b.starts_at)
    MySQL.update("UPDATE veyl_prod_batches SET starts_at = starts_at - ?, ends_at = ends_at - ? WHERE workstation_id = ? AND state = 'active' AND id > ?", { delta, delta, row.id, b.id })
    Prod.Log.event('craft', cid, ('cancelled batch #%d'):format(b.id))
    return Veyl.Ok(Ws.view(row, cid), fraction >= 1.0 and 'Cancelled: everything returned' or 'Cancelled: part of the materials came back')
end

--- Cancels every active batch of a bench without refund (used by raids).
function Ws.wipe(wsId)
    MySQL.update("UPDATE veyl_prod_batches SET state = 'cancelled' WHERE workstation_id = ? AND state = 'active'", { wsId })
end

--- Admin diagnostics: batches long finished and never collected, batches on benches that no longer exist.
function Ws.diagnose()
    local out = { stuck = {}, orphaned = {} }
    local now = os.time()
    for _, b in ipairs(MySQL.query.await("SELECT id, workstation_id, owner_cid, ends_at FROM veyl_prod_batches WHERE state = 'active'") or {}) do
        if not Ws.rows[b.workstation_id] then out.orphaned[#out.orphaned + 1] = b.id
        elseif b.ends_at < now - 86400 then out.stuck[#out.stuck + 1] = b.id end
    end
    return out
end

--- Benches that are working a hazardous recipe right now (for the hazard system). Returns { { id, x, y, z } }.
function Ws.hazardous()
    local out = {}
    local now = os.time()
    local seen = {}
    for _, b in ipairs(MySQL.query.await("SELECT workstation_id, recipe FROM veyl_prod_batches WHERE state = 'active' AND starts_at <= ? AND ends_at > ?", { now, now }) or {}) do
        local r = W.Recipes[b.recipe]
        local ws = Ws.rows[b.workstation_id]
        if r and r.hazard and ws and not seen[ws.id] then seen[ws.id] = true out[#out + 1] = { id = ws.id, x = ws.x, y = ws.y, z = ws.z, owner = ws.owner_cid } end
    end
    return out
end
