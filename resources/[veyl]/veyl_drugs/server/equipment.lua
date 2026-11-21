-- Placeable equipment (weed / coke tables) and crafting jobs.
--
-- Placement : 'pending' row (op id) -> equipment item taken (op ':item') -> 'placed'. Startup reconcile finishes/undoes it.
-- Job       : craft row 'starting' -> inputs taken with op ids (any failure refunds what was taken) -> 'running'
--             -> complete: server checks elapsed time and distance, output given with op 'craft:<token>:out'
--                inventory full -> output goes to the table's tray (never lost) ; timeout -> reconciled from the op record
--             -> cancel: inputs refunded (op ':refund<n>'), or put in the tray if they no longer fit.
--             Abandoned jobs (disconnect, crash) are finished with the "steady hands" score into the tray.
-- Pack up   : refused while a job runs or the tray holds items; the item is returned with op 'pack:<id>'.

Equip = { all = {}, grid = {} }
local CFG = DrugsEquipment
local CELL = 64.0

local function cellKey(bucket, x, y) return ('%d:%d:%d'):format(bucket, math.floor(x / CELL), math.floor(y / CELL)) end
local function indexAdd(e) local k = cellKey(e.bucket, e.x, e.y) Equip.grid[k] = Equip.grid[k] or {} Equip.grid[k][e.id] = true end
local function indexRemove(e) local k = cellKey(e.bucket, e.x, e.y) if Equip.grid[k] then Equip.grid[k][e.id] = nil end end

function Equip.Near(bucket, pos, radius)
    local out = {}
    local cx, cy, span = math.floor(pos.x / CELL), math.floor(pos.y / CELL), math.ceil(radius / CELL)
    for gx = cx - span, cx + span do
        for gy = cy - span, cy + span do
            for id in pairs(Equip.grid[('%d:%d:%d'):format(bucket, gx, gy)] or {}) do
                local e = Equip.all[id]
                if e then
                    local d = #(vector3(e.x, e.y, e.z) - pos)
                    if d <= radius then out[#out + 1] = { e = e, d = d } end
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.d < b.d end)
    return out
end

local function decode(s, default)
    if not s or s == '' then return default end
    local ok, v = pcall(json.decode, s)
    return ok and v or default
end

local function fromRow(r)
    return { id = r.id, owner = r.owner_cid, kind = r.kind, x = r.x, y = r.y, z = r.z, heading = r.heading, bucket = r.bucket,
        interior = r.interior, state = r.state, condition = r.condition, tray = decode(r.tray, {}) }
end

local function streamView(e, cid)
    return { id = e.id, kind = e.kind, x = e.x, y = e.y, z = e.z, h = e.heading, own = cid ~= nil and e.owner == cid,
        busy = e.job ~= nil, tray = #e.tray }
end
Equip.StreamView = streamView

local function notifyNear(e, removed)
    for _, pid in ipairs(GetPlayers()) do
        local src = tonumber(pid)
        local pos, bucket = Drugs.PlayerPos(src)
        if pos and bucket == e.bucket and #(pos - vector3(e.x, e.y, e.z)) <= DrugsConfig.Stream.Radius then
            if removed then TriggerClientEvent('veyl_drugs:equipmentRemoved', src, e.id)
            else TriggerClientEvent('veyl_drugs:equipmentUpdated', src, streamView(e, exports.veyl_core:GetCitizenId(src))) end
        end
    end
end

local function saveTray(e)
    MySQL.update.await('UPDATE veyl_drug_equipment SET tray = ?, `condition` = ?, updated_at = ? WHERE id = ?',
        { #e.tray > 0 and json.encode(e.tray) or nil, e.condition, os.time(), e.id })
end

function Equip.Can(cid, e, perm)
    if e.owner == cid then return true end
    if Crews and Crews.Can then return Crews.Can(e.owner, cid, perm) end
    return false
end

local function near(src, e, extra)
    local pos, bucket = Drugs.PlayerPos(src)
    return pos ~= nil and bucket == e.bucket and #(pos - vector3(e.x, e.y, e.z)) <= CFG.UseDistance + (extra or 1.0)
end

---------------------------------------------------------------------------
-- Placement
---------------------------------------------------------------------------
local function ownedCount(cid)
    local n = 0
    for _, e in pairs(Equip.all) do if e.owner == cid then n = n + 1 end end
    return n
end

Veyl.RegisterCallback('placeEquipment', function(src, citizenid, req)
    if not Drugs.ready then return Veyl.Err('NOT_READY', 'Try again in a moment') end
    if type(req) ~= 'table' or not Drugs.ValidClientOp(req.opId) then return Veyl.Err('INVALID_INPUT', 'Invalid request') end
    local kind = DrugsEquipmentByItem[req.item]
    local def = kind and CFG.types[kind]
    if not def then return Veyl.Err('INVALID_INPUT', 'That cannot be placed') end
    for _, k in ipairs({ 'x', 'y', 'z', 'heading' }) do
        if type(req[k]) ~= 'number' or req[k] ~= req[k] or math.abs(req[k]) > 20000 then return Veyl.Err('INVALID_INPUT', 'Invalid position') end
    end
    local pos = vector3(req.x, req.y, req.z)
    if GetVehiclePedIsIn(GetPlayerPed(src), false) ~= 0 then return Veyl.Err('INVALID_STATE', 'Get out of the vehicle first') end
    local ppos, bucket = Drugs.PlayerPos(src)
    if not ppos or #(ppos - pos) > DrugsConfig.Placement.MaxDistance + 1.5 or math.abs(ppos.z - pos.z) > 3.0 then
        Drugs.Suspicious(src, citizenid, 'equip_place_too_far', { x = req.x, y = req.y, z = req.z })
        return Veyl.Err('TOO_FAR', 'Too far away')
    end
    local interior = math.floor(tonumber(req.interior) or 0)
    if not Drugs.PropertyAllows(src, interior) then return Veyl.Err('NO_PERMISSION', 'You cannot set up inside here') end
    for _, z in ipairs(DrugsConfig.RestrictedZones) do
        if #(pos - z.coords) <= z.radius then return Veyl.Err('RESTRICTED', ('Too close to %s'):format(z.label)) end
    end
    if ownedCount(citizenid) >= CFG.MaxPerPlayer then return Veyl.Err('LIMIT', ('You can set up at most %d tables'):format(CFG.MaxPerPlayer)) end
    local ne = Equip.Near(bucket, pos, 2.0)
    if ne[1] then return Veyl.Err('BLOCKED', 'Too close to other equipment') end
    local np = Plants.Near(bucket, pos, 1.2)
    if np[1] then return Veyl.Err('BLOCKED', 'Too close to a plant') end
    if Drugs.Inv.Count(src, req.item) < 1 then return Veyl.Err('NOT_ENOUGH_ITEMS', ('You need a %s'):format(def.label)) end

    local op = ('equip:%s:%s'):format(citizenid, req.opId)
    local now = os.time()
    local okIns, id = pcall(MySQL.insert.await, [[INSERT INTO veyl_drug_equipment (owner_cid, kind, x, y, z, heading, bucket, interior,
        state, created_at, updated_at, op_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?, ?)]],
        { citizenid, kind, req.x, req.y, req.z, req.heading % 360, bucket, interior, now, now, op })
    if not okIns or not id then return Veyl.Err('DUPLICATE_OPERATION', 'Already set up') end
    local take = Drugs.Inv.Take(citizenid, req.item, 1, nil, op .. ':item')
    if not take.ok then
        MySQL.update.await("DELETE FROM veyl_drug_equipment WHERE id = ? AND state = 'pending'", { id })
        return Veyl.Err(take.code or 'NOT_ENOUGH_ITEMS', ('You need a %s'):format(def.label))
    end
    MySQL.update.await("UPDATE veyl_drug_equipment SET state = 'placed' WHERE id = ? AND state = 'pending'", { id })
    local e = fromRow(MySQL.single.await('SELECT * FROM veyl_drug_equipment WHERE id = ?', { id }))
    Equip.all[id] = e
    indexAdd(e)
    notifyNear(e)
    Drugs.Log(citizenid, 'equip_place', nil, { equipment = id, kind = kind })
    return Veyl.Ok({ id = id }, ('%s set up'):format(def.label))
end, { cooldown = 1500 })

---------------------------------------------------------------------------
-- Screen data: recipes with what you have, and which batches can be used
---------------------------------------------------------------------------
local BATCH_KEYS = { 'product', 'variety', 'varietyLabel', 'grade', 'quality', 'batch' }

local function cleanBatch(m)
    if type(m) ~= 'table' then return nil end
    local out = {}
    for _, k in ipairs(BATCH_KEYS) do
        local v = m[k]
        if k == 'quality' then if type(v) ~= 'number' then return nil end out[k] = v
        elseif type(v) ~= 'string' or #v > 40 then return nil else out[k] = v end
    end
    return out
end

local function itemLabel(name)
    local d = exports.veyl_inventory:GetItemDefinition(name)
    return d and d.label or name
end

--- Stacks in the player's inventory that can feed a batch input, grouped by identical metadata.
local function batchesFor(src, item)
    local groups, order = {}, {}
    for _, it in pairs(exports.veyl_inventory:GetInventoryItems(src) or {}) do
        if it.name == item then
            local meta = cleanBatch(it.metadata)
            if meta then
                local key = meta.batch .. '|' .. meta.grade .. '|' .. meta.quality
                if not groups[key] then groups[key] = { metadata = meta, count = 0 } order[#order + 1] = key end
                groups[key].count = groups[key].count + it.count
            end
        end
    end
    local out = {}
    for _, k in ipairs(order) do out[#out + 1] = groups[k] end
    return out
end

local function equipmentView(src, cid, e)
    local def = CFG.types[e.kind]
    local recipes = {}
    for _, r in ipairs(def.recipes) do
        local inputs = {}
        local batchItem
        for _, i in ipairs(r.inputs) do
            inputs[#inputs + 1] = { item = i.item, label = itemLabel(i.item), count = i.count, batch = i.batch == true,
                have = i.batch and 0 or Drugs.Inv.Count(src, i.item) }
            if i.batch then batchItem = i.item end
        end
        recipes[#recipes + 1] = {
            id = r.id, label = r.label, icon = r.icon, challenge = r.challenge, msPerUnit = r.msPerUnit,
            inputs = inputs, output = { item = r.output.item, label = itemLabel(r.output.item), count = r.output.count },
            batches = batchItem and batchesFor(src, batchItem) or {},
        }
    end
    local tray = {}
    for i, t in ipairs(e.tray) do tray[i] = { item = t.item, label = itemLabel(t.item), count = t.count, grade = t.metadata and t.metadata.grade } end
    return {
        id = e.id, kind = e.kind, label = def.label, condition = math.floor(e.condition), maxUnits = CFG.MaxUnits,
        challengeQuality = CFG.ChallengeQuality, recipes = recipes, tray = tray, busy = e.job ~= nil,
    }
end

Veyl.RegisterCallback('equipmentOpen', function(src, citizenid, id)
    local e = Equip.all[tonumber(id) or -1]
    if not e then return Veyl.Err('NOT_FOUND', 'That is gone') end
    if not Equip.Can(citizenid, e, 'equipment') then return Veyl.Err('NO_PERMISSION', 'This is not yours') end
    if not near(src, e) then return Veyl.Err('TOO_FAR', 'Walk up to the table') end
    return Veyl.Ok(equipmentView(src, citizenid, e))
end, { cooldown = 500 })

---------------------------------------------------------------------------
-- Jobs
---------------------------------------------------------------------------
local jobsBySrc = {}   -- [src] = token
local jobs = {}        -- [token] = { token, src, cid, e, recipe, units, batch, taken = { {item,count,metadata} }, startedAt, duration }

local function newToken() return ('%x%04x%04x'):format(os.time(), math.random(0, 0xffff), math.random(0, 0xffff)) end

local function refundTaken(job, reasonPrefix)
    local trayed = false
    for i, t in ipairs(job.taken) do
        local r = Drugs.Inv.Give(job.cid, t.item, t.count, t.metadata, ('craft:%s:%s%d'):format(job.token, reasonPrefix, i))
        if not r.ok and r.code ~= 'DUPLICATE_OPERATION' then
            job.e.tray[#job.e.tray + 1] = { id = newToken(), item = t.item, count = t.count, metadata = t.metadata }
            trayed = true
        end
    end
    if trayed then saveTray(job.e) end
    return trayed
end

--- craftStart(equipmentId, recipeId, units, batchMetadata, clientOp)
Veyl.RegisterCallback('craftStart', function(src, citizenid, id, recipeId, units, batchMeta)
    local e = Equip.all[tonumber(id) or -1]
    if not e then return Veyl.Err('NOT_FOUND', 'That is gone') end
    if not Equip.Can(citizenid, e, 'equipment') then return Veyl.Err('NO_PERMISSION', 'This is not yours') end
    if not near(src, e) then Drugs.Suspicious(src, citizenid, 'remote_craft', { equipment = e.id }) return Veyl.Err('TOO_FAR', 'Walk up to the table') end
    if e.job then return Veyl.Err('BUSY', 'The table is in use') end
    if jobsBySrc[src] then return Veyl.Err('BUSY', 'You are already working') end
    local r = CFG.types[e.kind].recipesById[recipeId]
    if not r then return Veyl.Err('INVALID_INPUT', 'Unknown recipe') end
    if not Veyl.Validate.int(units, 1, CFG.MaxUnits) then return Veyl.Err('INVALID_INPUT', ('Choose 1 to %d'):format(CFG.MaxUnits)) end
    local batch = nil
    for _, i in ipairs(r.inputs) do if i.batch then batch = cleanBatch(batchMeta) if not batch then return Veyl.Err('INVALID_INPUT', 'Choose a batch') end end end

    -- Check everything first.
    for _, i in ipairs(r.inputs) do
        local need = i.count * units
        if Drugs.Inv.Count(src, i.item, i.batch and batch or nil) < need then
            return Veyl.Err('NOT_ENOUGH_ITEMS', ('You need %d %s'):format(need, itemLabel(i.item)))
        end
    end

    local token = newToken()
    local duration = r.msPerUnit * units
    MySQL.insert.await([[INSERT INTO veyl_drug_crafts (token, equipment_id, citizenid, recipe, units, inputs, batch, state, started_at, duration_ms)
        VALUES (?, ?, ?, ?, ?, '[]', ?, 'starting', ?, ?)]], { token, e.id, citizenid, r.id, units, batch and json.encode(batch) or nil, os.time(), duration })
    local job = { token = token, src = src, cid = citizenid, e = e, recipe = r, units = units, batch = batch, taken = {},
        startedAt = GetGameTimer(), duration = duration }
    e.job = token
    for n, i in ipairs(r.inputs) do
        local meta = i.batch and batch or nil
        local take = Drugs.Inv.Take(citizenid, i.item, i.count * units, meta, ('craft:%s:in%d'):format(token, n))
        if not take.ok then
            refundTaken(job, 'refund')
            e.job = nil
            MySQL.update.await("UPDATE veyl_drug_crafts SET state = 'cancelled' WHERE token = ?", { token })
            return Veyl.Err(take.code or 'NOT_ENOUGH_ITEMS', 'Your supplies changed. Nothing was used.')
        end
        job.taken[#job.taken + 1] = { item = i.item, count = i.count * units, metadata = meta }
    end
    MySQL.update.await("UPDATE veyl_drug_crafts SET state = 'running', inputs = ? WHERE token = ?", { json.encode(job.taken), token })
    jobs[token] = job
    jobsBySrc[src] = token
    job.startedAt = GetGameTimer()
    notifyNear(e)
    return Veyl.Ok({ token = token, durationMs = duration, challenge = r.challenge })
end, { cooldown = 800 })

local function outputFor(job, score)
    local r = job.recipe
    local meta = nil
    if job.batch then
        local q = job.batch.quality
        q = q + math.floor((math.max(0, math.min(1, score)) - 0.5) * 2 * CFG.ChallengeQuality + 0.5)
        q = q - math.floor((1 - job.e.condition / 100) * 5 + 0.5)
        q = math.max(0, math.min(100, q))
        local grade = DrugsConfig.Grades[#DrugsConfig.Grades]
        for _, g in ipairs(DrugsConfig.Grades) do if q >= g.min then grade = g break end end
        meta = { product = r.output.product, variety = job.batch.variety, varietyLabel = job.batch.varietyLabel,
            grade = grade.label, quality = q, batch = job.batch.batch }
    end
    return { item = r.output.item, count = r.output.count * job.units, metadata = meta }
end

--- Finishes a job: output to the player, or to the tray if it doesn't fit. Returns 'delivered' | 'tray' | 'pending'.
local function finish(job, score)
    local out = outputFor(job, score)
    local give = Drugs.Inv.Give(job.cid, out.item, out.count, out.metadata, ('craft:%s:out'):format(job.token))
    local state
    if give.ok or give.code == 'DUPLICATE_OPERATION' then
        state = 'delivered'
    elseif give.code == 'TIMEOUT' then
        return 'pending', out
    else
        job.e.tray[#job.e.tray + 1] = { id = job.token, item = out.item, count = out.count, metadata = out.metadata }
        state = 'tray'
    end
    job.e.condition = math.max(0, job.e.condition - CFG.WearPerJob)
    saveTray(job.e)
    MySQL.update.await('UPDATE veyl_drug_crafts SET state = ?, score = ? WHERE token = ?', { state, score, job.token })
    jobs[job.token] = nil
    if jobsBySrc[job.src] == job.token then jobsBySrc[job.src] = nil end
    job.e.job = nil
    notifyNear(job.e)
    Drugs.Log(job.cid, 'craft', nil, { equipment = job.e.id, recipe = job.recipe.id, units = job.units, output = out.item, count = out.count,
        quality = out.metadata and out.metadata.quality, state = state })
    return state, out
end

Veyl.RegisterCallback('craftComplete', function(src, citizenid, token, score)
    local job = jobs[token]
    if not job or job.src ~= src or job.cid ~= citizenid then
        Drugs.Suspicious(src, citizenid, 'replayed_craft', { token = token })
        return Veyl.Err('INVALID_STATE', 'Nothing in progress')
    end
    if GetGameTimer() - job.startedAt < job.duration - 500 then
        Drugs.Suspicious(src, citizenid, 'craft_too_fast', { recipe = job.recipe.id })
        return Veyl.Err('INVALID_STATE', 'Not finished yet')
    end
    if not near(src, job.e, 2.5) then return Veyl.Err('TOO_FAR', 'Stay at the table') end
    score = tonumber(score) or CFG.SteadyScore
    if score ~= score then score = CFG.SteadyScore end
    local state, out = finish(job, score)
    if state == 'pending' then return Veyl.Err('PENDING', 'Checking your pockets… try again in a moment') end
    local msg = state == 'tray' and ('Pockets full: %dx %s left on the table'):format(out.count, itemLabel(out.item))
        or ('Made %dx %s%s'):format(out.count, itemLabel(out.item), out.metadata and (' (%s)'):format(out.metadata.grade) or '')
    return Veyl.Ok({ state = state, view = equipmentView(src, citizenid, job.e) }, msg)
end)

Veyl.RegisterCallback('craftCancel', function(src, citizenid, token)
    local job = jobs[token]
    if not job or job.src ~= src then return Veyl.Ok() end
    local trayed = refundTaken(job, 'refund')
    MySQL.update.await("UPDATE veyl_drug_crafts SET state = 'cancelled' WHERE token = ?", { token })
    jobs[token] = nil
    jobsBySrc[src] = nil
    job.e.job = nil
    notifyNear(job.e)
    return Veyl.Ok({ view = equipmentView(src, citizenid, job.e) }, trayed and 'Cancelled. Some supplies were left on the table.' or 'Cancelled. Supplies returned.')
end)

Veyl.RegisterCallback('collectTray', function(src, citizenid, id)
    local e = Equip.all[tonumber(id) or -1]
    if not e then return Veyl.Err('NOT_FOUND', 'That is gone') end
    if not Equip.Can(citizenid, e, 'storage') then return Veyl.Err('NO_PERMISSION', 'This is not yours') end
    if not near(src, e) then return Veyl.Err('TOO_FAR', 'Walk up to the table') end
    if #e.tray == 0 then return Veyl.Err('INVALID_STATE', 'Nothing to collect') end
    local kept, got = {}, 0
    for _, t in ipairs(e.tray) do
        local r = Drugs.Inv.Give(citizenid, t.item, t.count, t.metadata, ('tray:%d:%s'):format(e.id, t.id or newToken()))
        if r.ok or r.code == 'DUPLICATE_OPERATION' then got = got + 1 else kept[#kept + 1] = t end
    end
    e.tray = kept
    saveTray(e)
    notifyNear(e)
    if #kept > 0 then return Veyl.Ok({ view = equipmentView(src, citizenid, e) }, 'Some items did not fit and are still on the table') end
    return Veyl.Ok({ view = equipmentView(src, citizenid, e) }, 'Collected everything')
end, { cooldown = 1000 })

---------------------------------------------------------------------------
-- Pack up (owner only; never while a job runs or items wait in the tray)
---------------------------------------------------------------------------
local packing = {} -- [src] = { id, token, startedAt }

Veyl.RegisterCallback('packStart', function(src, citizenid, id)
    local e = Equip.all[tonumber(id) or -1]
    if not e then return Veyl.Err('NOT_FOUND', 'That is gone') end
    if e.owner ~= citizenid then return Veyl.Err('NO_PERMISSION', 'Only the owner can pack this up') end
    if not near(src, e) then return Veyl.Err('TOO_FAR', 'Walk up to the table') end
    if e.job then return Veyl.Err('BUSY', 'Wait for the current job to finish') end
    if #e.tray > 0 then return Veyl.Err('INVALID_STATE', 'Collect what is on the table first') end
    local token = newToken()
    packing[src] = { id = e.id, token = token, startedAt = GetGameTimer() }
    e.packing = true
    return Veyl.Ok({ token = token, durationMs = CFG.PackMs })
end, { cooldown = 800 })

Veyl.RegisterCallback('packCancel', function(src)
    local p = packing[src]
    if p then local e = Equip.all[p.id] if e then e.packing = nil end packing[src] = nil end
    return Veyl.Ok()
end)

Veyl.RegisterCallback('packComplete', function(src, citizenid, token)
    local p = packing[src]
    if not p or p.token ~= token then return Veyl.Err('INVALID_STATE', 'Nothing in progress') end
    packing[src] = nil
    local e = Equip.all[p.id]
    if not e then return Veyl.Err('NOT_FOUND', 'That is gone') end
    e.packing = nil
    if GetGameTimer() - p.startedAt < CFG.PackMs - 400 then return Veyl.Err('INVALID_STATE', 'Too fast') end
    if e.job or #e.tray > 0 then return Veyl.Err('BUSY', 'The table is in use') end
    if not near(src, e, 1.5) then return Veyl.Err('TOO_FAR', 'You moved away') end
    local item = CFG.types[e.kind].item
    local give = Drugs.Inv.Give(citizenid, item, 1, nil, 'pack:' .. e.id)
    if not give.ok and give.code ~= 'DUPLICATE_OPERATION' then return Veyl.Err(give.code or 'INVENTORY_FULL', 'Make room to carry it') end
    MySQL.update.await("UPDATE veyl_drug_equipment SET state = 'packed', updated_at = ? WHERE id = ?", { os.time(), e.id })
    Equip.all[e.id] = nil
    indexRemove(e)
    notifyNear(e, true)
    Drugs.Log(citizenid, 'equip_pack', nil, { equipment = e.id })
    return Veyl.Ok(nil, ('%s packed up'):format(CFG.types[e.kind].label))
end)

AddEventHandler('playerDropped', function()
    local src = source
    packing[src] = nil
    -- A running job is left alone: the reconcile below finishes it into the tray, so nothing is lost or duplicated.
    jobsBySrc[src] = nil
end)

---------------------------------------------------------------------------
-- Load and reconcile
---------------------------------------------------------------------------
--- Jobs whose time is well past: finish them with the steady-hands score (output lands in the player's pockets or tray).
local function reconcileJobs(all)
    local now = GetGameTimer()
    for token, job in pairs(jobs) do
        if all or now - job.startedAt > job.duration + 60000 then finish(job, CFG.SteadyScore) end
    end
end

local function reconcileStartup()
    -- Equipment placements interrupted between the row and the item take.
    for _, r in ipairs(MySQL.query.await("SELECT id, op_id FROM veyl_drug_equipment WHERE state = 'pending' AND updated_at < ?", { os.time() - 60 }) or {}) do
        if Drugs.Inv.Done(r.op_id .. ':item') then
            MySQL.update.await("UPDATE veyl_drug_equipment SET state = 'placed' WHERE id = ?", { r.id })
        else
            MySQL.update.await("DELETE FROM veyl_drug_equipment WHERE id = ? AND state = 'pending'", { r.id })
        end
    end
end

--- Jobs that were running when the server stopped: deliver the output once (or into the tray), never twice.
local function reconcileCraftRows()
    for _, c in ipairs(MySQL.query.await("SELECT * FROM veyl_drug_crafts WHERE state IN ('starting','running')") or {}) do
        local e = Equip.all[c.equipment_id]
        local taken = decode(c.inputs, {})
        if c.state == 'starting' then
            -- Inputs may have been partly taken before the stop: give back exactly what the inventory recorded.
            local def = e and DrugsEquipment.types[e.kind]
            local r = def and def.recipesById[c.recipe]
            if r then
                local batch = decode(c.batch, nil)
                for n, i in ipairs(r.inputs) do
                    if Drugs.Inv.Done(('craft:%s:in%d'):format(c.token, n)) then
                        Drugs.Inv.Give(c.citizenid, i.item, i.count * c.units, i.batch and batch or nil, ('craft:%s:refund%d'):format(c.token, n))
                    end
                end
            end
            MySQL.update.await("UPDATE veyl_drug_crafts SET state = 'cancelled' WHERE token = ?", { c.token })
        elseif e then
            local def = DrugsEquipment.types[e.kind]
            local job = { token = c.token, src = -1, cid = c.citizenid, e = e, recipe = def.recipesById[c.recipe], units = c.units,
                batch = decode(c.batch, nil), taken = taken, startedAt = 0, duration = c.duration_ms }
            if job.recipe then jobs[c.token] = job end
        end
    end
end

AddEventHandler('veyl_drugs:ready', function()
    CreateThread(function()
        reconcileStartup()
        local rows = MySQL.query.await("SELECT * FROM veyl_drug_equipment WHERE state = 'placed'") or {}
        for _, r in ipairs(rows) do
            local e = fromRow(r)
            Equip.all[e.id] = e
            indexAdd(e)
        end
        reconcileCraftRows()
        reconcileJobs(true)
        print(('^5[veyl_drugs] %d pieces of equipment loaded^7'):format(#rows))
        while true do
            Wait(60000)
            reconcileJobs(false)
        end
    end)
end)
