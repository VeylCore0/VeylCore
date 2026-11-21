-- Plants: server-owned state, spatial index, streaming, placement, care, harvest and recovery.
--
-- Placement : row inserted as 'pending' (op_id) -> seed (+ pot/tub) taken with op ids -> 'growing'.
--             Startup reconcile finishes or undoes any 'pending' row using the inventory's operation records.
-- Harvest   : conditional claim growing -> harvesting (only one player can win) -> GiveItem(claim op) -> 'harvested'.
--             Inventory full -> claim released, nothing lost. Unclear outcome -> reconciled from the operation record.
-- Growth    : advanced from timestamps every TickMinutes in memory; dirty plants flushed every FlushMinutes and on
--             every action. No per-plant timers.

Plants = { all = {}, grid = {}, byOwner = {} }
local CELL = 64.0
local P = DrugsConfig.Placement

local function cellKey(bucket, x, y) return ('%d:%d:%d'):format(bucket, math.floor(x / CELL), math.floor(y / CELL)) end

local function indexAdd(p)
    local k = cellKey(p.bucket, p.x, p.y)
    Plants.grid[k] = Plants.grid[k] or {}
    Plants.grid[k][p.id] = true
    Plants.byOwner[p.owner] = Plants.byOwner[p.owner] or {}
    Plants.byOwner[p.owner][p.id] = true
end

local function indexRemove(p)
    local k = cellKey(p.bucket, p.x, p.y)
    if Plants.grid[k] then Plants.grid[k][p.id] = nil end
    if Plants.byOwner[p.owner] then Plants.byOwner[p.owner][p.id] = nil end
end

--- Plants within radius of a point in one routing bucket (uses the grid, never a full scan).
function Plants.Near(bucket, pos, radius)
    local out = {}
    local cx, cy, span = math.floor(pos.x / CELL), math.floor(pos.y / CELL), math.ceil(radius / CELL)
    for gx = cx - span, cx + span do
        for gy = cy - span, cy + span do
            local cell = Plants.grid[('%d:%d:%d'):format(bucket, gx, gy)]
            if cell then
                for id in pairs(cell) do
                    local p = Plants.all[id]
                    if p then
                        local d = #(vector3(p.x, p.y, p.z) - pos)
                        if d <= radius then out[#out + 1] = { p = p, d = d } end
                    end
                end
            end
        end
    end
    table.sort(out, function(a, b) return a.d < b.d end)
    return out
end

local function fromRow(r)
    return {
        id = r.id, owner = r.owner_cid, type = r.type, variety = r.variety, container = r.container,
        x = r.x, y = r.y, z = r.z, heading = r.heading, bucket = r.bucket, interior = r.interior, state = r.state,
        growth = r.growth, water = r.water, care = r.care, health = r.health, careSum = r.care_sum, careWeight = r.care_weight,
        readyAt = r.ready_at, plantedAt = r.planted_at, updatedAt = r.updated_at, opId = r.op_id,
    }
end

local function persist(p)
    return MySQL.update.await([[UPDATE veyl_drug_plants SET state = ?, growth = ?, water = ?, care = ?, health = ?, care_sum = ?,
        care_weight = ?, ready_at = ?, updated_at = ? WHERE id = ?]],
        { p.state, p.growth, p.water, p.care, p.health, p.careSum or 0, p.careWeight or 0, p.readyAt, p.updatedAt, p.id })
end

local function advance(p, now)
    Growth.advance(p, now or os.time(), Drugs.IsOnline(p.owner))
    p.dirty = true
end

---------------------------------------------------------------------------
-- Client streaming
---------------------------------------------------------------------------
local function streamView(p, cid)
    return { id = p.id, type = p.type, container = p.container, stage = Growth.stage(p), x = p.x, y = p.y, z = p.z, h = p.heading,
        ready = p.state == 'growing' and p.growth >= 100, own = cid ~= nil and p.owner == cid }
end

--- Tell players near a plant that it changed (stage, ready, removed). Never broadcast globally.
local function notifyNear(p, removed)
    for _, pid in ipairs(GetPlayers()) do
        local src = tonumber(pid)
        local pos, bucket = Drugs.PlayerPos(src)
        if pos and bucket == p.bucket and #(pos - vector3(p.x, p.y, p.z)) <= DrugsConfig.Stream.Radius then
            if removed then TriggerClientEvent('veyl_drugs:plantRemoved', src, p.id)
            else TriggerClientEvent('veyl_drugs:plantUpdated', src, streamView(p, exports.veyl_core:GetCitizenId(src))) end
        end
    end
end
Plants.NotifyNear = notifyNear

Veyl.RegisterCallback('nearby', function(src, citizenid)
    if not Drugs.ready then return Veyl.Err('NOT_READY', 'Not ready') end
    local pos, bucket = Drugs.PlayerPos(src)
    if not pos then return Veyl.Ok({}) end
    local list = {}
    for i, e in ipairs(Plants.Near(bucket, pos, DrugsConfig.Stream.Radius)) do
        if i > DrugsConfig.Stream.MaxSent then break end
        if e.p.state == 'growing' then list[#list + 1] = streamView(e.p, citizenid) end
    end
    return Veyl.Ok(list)
end, { cooldown = 1500 })

---------------------------------------------------------------------------
-- Permissions (crews arrive in milestone E; until then: owner only)
---------------------------------------------------------------------------
--- perm: 'inspect' | 'care' | 'harvest' | 'manage'
function Plants.Can(citizenid, p, perm)
    if p.owner == citizenid then return true end
    if Crews and Crews.Can then return Crews.Can(p.owner, citizenid, perm) end
    return false
end

local function within(src, p, extra)
    local pos, bucket = Drugs.PlayerPos(src)
    return pos ~= nil and bucket == p.bucket and #(pos - vector3(p.x, p.y, p.z)) <= DrugsConfig.InteractDistance + (extra or 0.8)
end

---------------------------------------------------------------------------
-- Placement
---------------------------------------------------------------------------
local function inRestrictedZone(pos)
    for _, z in ipairs(DrugsConfig.RestrictedZones) do
        if #(pos - z.coords) <= z.radius then return z end
    end
end

local function ownedCount(cid)
    local n = 0
    for id in pairs(Plants.byOwner[cid] or {}) do if Plants.all[id] then n = n + 1 end end
    return n
end

local function vehicleNear(pos, radius)
    for _, veh in ipairs(GetAllVehicles()) do
        if #(GetEntityCoords(veh) - pos) <= radius then return true end
    end
    return false
end

local function playerNear(pos, radius, except)
    for _, pid in ipairs(GetPlayers()) do
        local s = tonumber(pid)
        if s ~= except then
            local ped = GetPlayerPed(s)
            if ped ~= 0 and #(GetEntityCoords(ped) - pos) <= radius then return true end
        end
    end
    return false
end

--- place({ opId, item, variety, container, x, y, z, heading, interior })
Veyl.RegisterCallback('place', function(src, citizenid, req)
    if not Drugs.ready then return Veyl.Err('NOT_READY', 'Try again in a moment') end
    if type(req) ~= 'table' or not Drugs.ValidClientOp(req.opId) then return Veyl.Err('INVALID_INPUT', 'Invalid request') end
    local productId, product
    for id, prod in pairs(DrugsProducts) do if prod.seedItem == req.item then productId, product = id, prod end end
    if not product then return Veyl.Err('INVALID_INPUT', 'That cannot be planted') end
    local variety = product.varieties[req.variety]
    if not variety then return Veyl.Err('INVALID_INPUT', 'Unknown variety') end
    local container = req.container
    if not Veyl.Validate.oneOf(container, product.containers) then return Veyl.Err('INVALID_INPUT', 'That container is not allowed') end
    for _, k in ipairs({ 'x', 'y', 'z', 'heading' }) do
        if type(req[k]) ~= 'number' or req[k] ~= req[k] or math.abs(req[k]) > 20000 then return Veyl.Err('INVALID_INPUT', 'Invalid position') end
    end
    local pos = vector3(req.x, req.y, req.z)
    local ped = GetPlayerPed(src)
    if GetVehiclePedIsIn(ped, false) ~= 0 then return Veyl.Err('INVALID_STATE', 'Get out of the vehicle first') end
    local ppos, bucket = Drugs.PlayerPos(src)
    if not ppos or #(ppos - pos) > P.MaxDistance + 1.5 or math.abs(ppos.z - pos.z) > 3.0 then
        Drugs.Suspicious(src, citizenid, 'place_too_far', { x = req.x, y = req.y, z = req.z })
        return Veyl.Err('TOO_FAR', 'Too far away')
    end
    local interior = math.floor(tonumber(req.interior) or 0)
    if not Drugs.PropertyAllows(src, interior) then return Veyl.Err('NO_PERMISSION', 'You cannot grow inside here') end
    if interior ~= 0 and container == 'ground' and P.RequirePotIndoors then return Veyl.Err('INVALID_STATE', 'Use a pot indoors') end
    local zone = inRestrictedZone(pos)
    if zone then return Veyl.Err('RESTRICTED', ('Too close to %s'):format(zone.label)) end
    if ownedCount(citizenid) >= P.MaxPerPlayer then return Veyl.Err('LIMIT', ('You can tend at most %d plants'):format(P.MaxPerPlayer)) end
    local near = Plants.Near(bucket, pos, P.CrowdRadius)
    if #near >= P.MaxNearby then return Veyl.Err('LIMIT', 'This area is too crowded') end
    if near[1] and near[1].d < P.MinSpacing then return Veyl.Err('BLOCKED', 'Too close to another plant') end
    if vehicleNear(pos, 1.6) or playerNear(pos, 0.8, src) then return Veyl.Err('BLOCKED', 'Something is in the way') end

    -- Required items (checked before anything is taken).
    local seedMeta = { variety = req.variety, varietyLabel = variety.label }
    if Drugs.Inv.Count(src, req.item, seedMeta) < 1 then return Veyl.Err('NOT_ENOUGH_ITEMS', 'You do not have that seed') end
    local extraItem = (container == 'pot' and 'plant_pot') or (container == 'tub' and product.tubItem) or nil
    if extraItem and Drugs.Inv.Count(src, extraItem) < 1 then
        local def = exports.veyl_inventory:GetItemDefinition(extraItem)
        return Veyl.Err('NOT_ENOUGH_ITEMS', ('You need a %s'):format(def and def.label or extraItem))
    end

    -- 1) durable pending row, 2) take items with op ids, 3) activate. Any failure undoes the earlier steps.
    local op = ('plant:%s:%s'):format(citizenid, req.opId)
    local now = os.time()
    local okIns, id = pcall(MySQL.insert.await, [[INSERT INTO veyl_drug_plants (owner_cid, type, variety, container, x, y, z, heading, bucket,
        interior, state, planted_at, updated_at, op_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, 'pending', ?, ?, ?)]],
        { citizenid, productId, req.variety, container, req.x, req.y, req.z, req.heading % 360, bucket, interior, now, now, op })
    if not okIns or not id then return Veyl.Err('DUPLICATE_OPERATION', 'Already planted') end
    local take = Drugs.Inv.Take(citizenid, req.item, 1, seedMeta, op .. ':seed')
    if not take.ok then
        MySQL.update.await("DELETE FROM veyl_drug_plants WHERE id = ? AND state = 'pending'", { id })
        return Veyl.Err(take.code or 'NOT_ENOUGH_ITEMS', 'You do not have that seed')
    end
    if extraItem then
        local take2 = Drugs.Inv.Take(citizenid, extraItem, 1, nil, op .. ':container')
        if not take2.ok then
            Drugs.Inv.Give(citizenid, req.item, 1, seedMeta, op .. ':seed:refund')
            MySQL.update.await("DELETE FROM veyl_drug_plants WHERE id = ? AND state = 'pending'", { id })
            return Veyl.Err(take2.code or 'NOT_ENOUGH_ITEMS', 'Missing container')
        end
    end
    MySQL.update.await("UPDATE veyl_drug_plants SET state = 'growing' WHERE id = ? AND state = 'pending'", { id })
    local row = MySQL.single.await('SELECT * FROM veyl_drug_plants WHERE id = ?', { id })
    local p = fromRow(row)
    Plants.all[id] = p
    indexAdd(p)
    notifyNear(p)
    Drugs.Log(citizenid, 'plant', id, { type = productId, variety = req.variety, container = container, bucket = bucket })
    return Veyl.Ok({ id = id }, ('Planted %s'):format(variety.label))
end, { cooldown = 1500 })

---------------------------------------------------------------------------
-- Inspect
---------------------------------------------------------------------------
Veyl.RegisterCallback('inspect', function(src, citizenid, id)
    local p = Plants.all[tonumber(id) or -1]
    if not p or p.state ~= 'growing' then return Veyl.Err('NOT_FOUND', 'Nothing to inspect') end
    if not within(src, p, 2.0) then return Veyl.Err('TOO_FAR', 'Walk closer') end
    advance(p)
    local v = Growth.view(p)
    local own = Plants.Can(citizenid, p, 'inspect')
    if not own then
        -- Strangers (and police, until milestone E) only see what is visible by looking at it.
        return Veyl.Ok({ id = p.id, typeLabel = v.typeLabel, stage = v.stage, ready = v.ready, own = false, container = p.container })
    end
    v.own = true
    v.isOwner = p.owner == citizenid
    v.can = { care = Plants.Can(citizenid, p, 'care'), harvest = Plants.Can(citizenid, p, 'harvest'), manage = Plants.Can(citizenid, p, 'manage') }
    return Veyl.Ok(v)
end, { cooldown = 400 })

---------------------------------------------------------------------------
-- Timed actions: water / care / harvest / destroy  (start -> client progress -> complete)
---------------------------------------------------------------------------
local actions = {}  -- [src] = { token, kind, id, startedAt, duration }
local seq = 0
local PERM = { water = 'care', care = 'care', harvest = 'harvest', destroy = 'manage' }

Veyl.RegisterCallback('actionStart', function(src, citizenid, id, kind)
    local p = Plants.all[tonumber(id) or -1]
    if not PERM[kind] then return Veyl.Err('INVALID_INPUT', 'Unknown action') end
    if not p or p.state ~= 'growing' then return Veyl.Err('NOT_FOUND', 'That plant is gone') end
    if not Plants.Can(citizenid, p, PERM[kind]) then return Veyl.Err('NO_PERMISSION', 'This is not yours to tend') end
    if not within(src, p) then Drugs.Suspicious(src, citizenid, 'remote_action', { id = p.id, kind = kind }) return Veyl.Err('TOO_FAR', 'Walk closer') end
    if actions[src] then return Veyl.Err('BUSY', 'You are already busy') end
    if p.busy then return Veyl.Err('BUSY', 'Someone is already working on this plant') end
    advance(p)
    if kind == 'harvest' and p.growth < 100 then return Veyl.Err('INVALID_STATE', 'Not ready yet') end
    if kind == 'water' or kind == 'care' then
        local item = DrugsConfig.CareItems[kind]
        if Drugs.Inv.Count(src, item) < 1 then
            local def = exports.veyl_inventory:GetItemDefinition(item)
            return Veyl.Err('NOT_ENOUGH_ITEMS', ('You need %s'):format(def and def.label or item))
        end
    end
    seq = seq + 1
    local token = ('%x%x%04x'):format(os.time(), seq, math.random(0, 0xffff))
    actions[src] = { token = token, kind = kind, id = p.id, startedAt = GetGameTimer(), duration = DrugsConfig.ActionMs[kind] }
    p.busy = src
    return Veyl.Ok({ token = token, durationMs = DrugsConfig.ActionMs[kind] })
end, { cooldown = 500 })

local function endAction(src)
    local a = actions[src]
    actions[src] = nil
    if a then local p = Plants.all[a.id] if p and p.busy == src then p.busy = nil end end
    return a
end

Veyl.RegisterCallback('actionCancel', function(src, _, token)
    if actions[src] and actions[src].token == token then endAction(src) end
    return Veyl.Ok()
end)

local function harvest(src, citizenid, p)
    local prod = DrugsProducts[p.type]
    local q, grade = Growth.quality(p)
    local count = Growth.yield(p)
    local meta = { product = p.type, variety = p.variety, varietyLabel = Growth.variety(p).label, grade = grade.label, quality = q,
        batch = ('B%05X'):format(p.id) }
    local fits = Drugs.Inv.CanCarry(citizenid, prod.harvestItem, count, meta)
    if not fits.ok then return Veyl.Err('INVENTORY_FULL', 'Make room in your pockets first') end
    local claim = 'harvest:' .. p.id
    local n = MySQL.update.await([[UPDATE veyl_drug_plants SET state = 'harvesting', claim_op = ?, claim_by = ?, claimed_at = ?
        WHERE id = ? AND state = 'growing']], { claim, citizenid, os.time(), p.id })
    if n ~= 1 then return Veyl.Err('INVALID_STATE', 'Someone else harvested it') end
    p.state = 'harvesting'
    local give = Drugs.Inv.Give(citizenid, prod.harvestItem, count, meta, claim)
    if give.ok or give.code == 'DUPLICATE_OPERATION' then
        MySQL.update.await("UPDATE veyl_drug_plants SET state = 'harvested' WHERE id = ?", { p.id })
        p.state = 'harvested'
        indexRemove(p)
        Plants.all[p.id] = nil
        notifyNear(p, true)
        Drugs.Log(citizenid, 'harvest', p.id, { item = prod.harvestItem, count = count, quality = q, owner = p.owner })
        return Veyl.Ok({ count = count, grade = grade.label }, ('Harvested %d %s (%s)'):format(count, Growth.variety(p).label, grade.label))
    end
    if give.code == 'TIMEOUT' then
        return Veyl.Err('PENDING', 'Harvest is being verified') -- reconciled from the operation record
    end
    -- Definite failure (e.g. inventory filled meanwhile): release the claim, the plant stays ready.
    MySQL.update.await("UPDATE veyl_drug_plants SET state = 'growing', claim_op = NULL, claim_by = NULL WHERE id = ? AND state = 'harvesting'", { p.id })
    p.state = 'growing'
    return Veyl.Err(give.code or 'INVENTORY_FULL', give.message or 'Could not harvest')
end

Veyl.RegisterCallback('actionComplete', function(src, citizenid, token)
    local a = actions[src]
    if not a or a.token ~= token then
        Drugs.Suspicious(src, citizenid, 'replayed_completion', { token = token })
        return Veyl.Err('INVALID_STATE', 'Nothing in progress')
    end
    endAction(src)
    if GetGameTimer() - a.startedAt < a.duration - 400 then
        Drugs.Suspicious(src, citizenid, 'completed_too_fast', { kind = a.kind })
        return Veyl.Err('INVALID_STATE', 'Too fast')
    end
    local p = Plants.all[a.id]
    if not p or p.state ~= 'growing' then return Veyl.Err('NOT_FOUND', 'That plant is gone') end
    if not Plants.Can(citizenid, p, PERM[a.kind]) then return Veyl.Err('NO_PERMISSION', 'Your access was removed') end
    if not within(src, p, 1.5) then return Veyl.Err('TOO_FAR', 'You moved away') end
    advance(p)
    if a.kind == 'water' or a.kind == 'care' then
        local take = Drugs.Inv.Take(citizenid, DrugsConfig.CareItems[a.kind], 1, nil, ('%s:%d:%s'):format(a.kind, p.id, a.token))
        if not take.ok and take.code ~= 'DUPLICATE_OPERATION' then return Veyl.Err(take.code or 'NOT_ENOUGH_ITEMS', 'You ran out') end
        if a.kind == 'water' then p.water = 100 else p.care = 100 end
        persist(p)
        p.dirty = false
        Drugs.Log(citizenid, a.kind, p.id, p.owner ~= citizenid and { owner = p.owner } or nil)
        return Veyl.Ok(Growth.view(p), a.kind == 'water' and 'Watered' or 'Nutrients added')
    elseif a.kind == 'harvest' then
        if p.growth < 100 then return Veyl.Err('INVALID_STATE', 'Not ready yet') end
        return harvest(src, citizenid, p)
    elseif a.kind == 'destroy' then
        local n = MySQL.update.await("UPDATE veyl_drug_plants SET state = 'removed' WHERE id = ? AND state = 'growing'", { p.id })
        if n ~= 1 then return Veyl.Err('INVALID_STATE', 'Already gone') end
        p.state = 'removed'
        indexRemove(p)
        Plants.all[p.id] = nil
        notifyNear(p, true)
        Drugs.Log(citizenid, 'destroy', p.id, { owner = p.owner })
        return Veyl.Ok(nil, 'Plant removed')
    end
end)

AddEventHandler('playerDropped', function() endAction(source) end)

---------------------------------------------------------------------------
-- Journal (owner's plants, read-only; no remote actions)
---------------------------------------------------------------------------
Veyl.RegisterCallback('journal', function(src, citizenid)
    local list, ready, areas = {}, 0, {}
    for id in pairs(Plants.byOwner[citizenid] or {}) do
        local p = Plants.all[id]
        if p and p.state == 'growing' then
            advance(p)
            local v = Growth.view(p)
            list[#list + 1] = v
            if v.ready then ready = ready + 1 end
            areas[('%d:%d'):format(math.floor(p.x / 250), math.floor(p.y / 250))] = true
        end
    end
    table.sort(list, function(a, b) if a.ready ~= b.ready then return a.ready end return a.growth > b.growth end)
    local locations = 0
    for _ in pairs(areas) do locations = locations + 1 end
    return Veyl.Ok({ plants = list, stats = { plants = #list, ready = ready, locations = locations, limit = P.MaxPerPlayer } })
end, { cooldown = 1000 })

---------------------------------------------------------------------------
-- Load, tick, flush, reconcile
---------------------------------------------------------------------------
local function reconcile()
    -- Interrupted placements: finish them if the seed was taken, otherwise drop the row.
    for _, r in ipairs(MySQL.query.await("SELECT id, owner_cid, type, variety, container, op_id FROM veyl_drug_plants WHERE state = 'pending' AND updated_at < ?",
        { os.time() - 60 }) or {}) do
        local seedTaken = Drugs.Inv.Done(r.op_id .. ':seed')
        local needsContainer = r.container ~= 'ground'
        local containerTaken = not needsContainer or Drugs.Inv.Done(r.op_id .. ':container')
        if seedTaken and containerTaken then
            MySQL.update.await("UPDATE veyl_drug_plants SET state = 'growing' WHERE id = ?", { r.id })
        else
            if seedTaken then
                local prod = DrugsProducts[r.type]
                local v = prod and prod.varieties[r.variety]
                Drugs.Inv.Give(r.owner_cid, prod.seedItem, 1, { variety = r.variety, varietyLabel = v and v.label or r.variety }, r.op_id .. ':seed:refund')
            end
            MySQL.update.await("DELETE FROM veyl_drug_plants WHERE id = ? AND state = 'pending'", { r.id })
        end
    end
    -- Interrupted harvests: the inventory operation record decides.
    for _, r in ipairs(MySQL.query.await("SELECT id, claim_op FROM veyl_drug_plants WHERE state = 'harvesting' AND claimed_at < ?",
        { os.time() - 60 }) or {}) do
        if r.claim_op and Drugs.Inv.Done(r.claim_op) then
            MySQL.update.await("UPDATE veyl_drug_plants SET state = 'harvested' WHERE id = ?", { r.id })
            local p = Plants.all[r.id]
            if p then indexRemove(p) Plants.all[r.id] = nil notifyNear(p, true) end
        else
            MySQL.update.await("UPDATE veyl_drug_plants SET state = 'growing', claim_op = NULL, claim_by = NULL WHERE id = ? AND state = 'harvesting'", { r.id })
            local p = Plants.all[r.id]
            if p then p.state = 'growing' end
        end
    end
end

local function flush()
    local queries = {}
    for _, p in pairs(Plants.all) do
        if p.dirty and p.state == 'growing' then
            queries[#queries + 1] = { query = [[UPDATE veyl_drug_plants SET growth = ?, water = ?, care = ?, health = ?, care_sum = ?, care_weight = ?,
                ready_at = ?, updated_at = ? WHERE id = ? AND state = 'growing']],
                values = { p.growth, p.water, p.care, p.health, p.careSum or 0, p.careWeight or 0, p.readyAt, p.updatedAt, p.id } }
            p.dirty = false
        end
    end
    if #queries > 0 then MySQL.transaction.await(queries) end
end
Plants.Flush = flush

AddEventHandler('veyl_drugs:ready', function()
    CreateThread(function()
        reconcile()
        local rows = MySQL.query.await("SELECT * FROM veyl_drug_plants WHERE state IN ('growing','harvesting')") or {}
        for _, r in ipairs(rows) do
            local p = fromRow(r)
            Plants.all[p.id] = p
            indexAdd(p)
            -- Time the server was down counts as offline time (generous).
            Growth.advance(p, os.time(), false)
            p.dirty = true
        end
        print(('^5[veyl_drugs] ready: %d plants loaded^7'):format(#rows))
        local lastFlush = os.time()
        while true do
            Wait(DrugsConfig.Growth.TickMinutes * 60000)
            local now = os.time()
            for _, p in pairs(Plants.all) do
                if p.state == 'growing' then
                    local before = Growth.stage(p)
                    local wasReady = p.growth >= 100
                    advance(p, now)
                    if p.state == 'dead' then
                        persist(p)
                        indexRemove(p)
                        Plants.all[p.id] = nil
                        notifyNear(p, true)
                        Drugs.Log(p.owner, 'died', p.id, nil)
                    elseif Growth.stage(p) ~= before or (p.growth >= 100) ~= wasReady then
                        notifyNear(p)
                    end
                end
            end
            if now - lastFlush >= DrugsConfig.Growth.FlushMinutes * 60 then
                flush()
                reconcile()
                lastFlush = now
            end
        end
    end)
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() and Drugs.ready then flush() end
end)
