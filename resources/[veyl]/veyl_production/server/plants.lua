-- Plants: the shared plant engine (placement rules, lifecycle simulation) and the botanical branch's plant actions.
-- A plant stores its meters as of `updated_at`; its current state is computed from the elapsed server time, so nothing needs a
-- running loop and a restart changes nothing. Harvest is claimed once, atomically, with an idempotent inventory operation.

Prod = Prod or {}
Prod.Plants = { rows = {} }
Prod.Place = {}
local Plants, Place = Prod.Plants, Prod.Place
local C = ProductionConfig
local B = C.Botanical
local Care = B.Care

---------------------------------------------------------------------------
-- Shared placement rules (plants and workstations)
---------------------------------------------------------------------------
--- Checks a spot the server can check: distance to the player, restricted zones, spacing and (inside a lab) the lab's interior.
--- `others` is a list of objects with x, y, z. Returns nil or a reason.
function Place.problem(src, cid, pos, propertyId, others)
    if not Prod.Sec.near(src, pos, C.Distance.Place) then return 'Too far from where you stand' end
    if propertyId then
        local ok, reason = Prod.Props.canPlaceInside(src, cid, propertyId, pos)
        if not ok then return reason end
    else
        if Prod.Props.insideOf(src) then return 'Use the laboratory placement from inside it' end
        for _, z in ipairs(C.Placement.RestrictedZones) do
            if ProdUtil.distance(pos, z.coords) <= z.radius then return 'Too close to ' .. z.label end
        end
    end
    for _, o in pairs(others) do
        if ProdUtil.distance(pos, o) < C.Placement.MinSpacing and (o.property_id or false) == (propertyId or false) then return 'Too close to something else' end
    end
    return nil
end

--- A position table from request fields, or nil if malformed.
function Place.position(d)
    if type(d) ~= 'table' then return nil end
    local x, y, z, h = tonumber(d.x), tonumber(d.y), tonumber(d.z), tonumber(d.heading) or 0.0
    if not (x and y and z) or math.abs(x) > 10000 or math.abs(y) > 10000 or math.abs(z) > 2000 then return nil end
    return { x = x + 0.0, y = y + 0.0, z = z + 0.0 }, (h % 360) + 0.0
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
local function varietyOf(row) return B.Varieties[row.variety] end

--- Advances a plant row to `now` and returns it (the row table is updated in place).
function Plants.simulate(row, now)
    now = now or os.time()
    local v = varietyOf(row)
    if not v then return row end
    if row.state ~= 'growing' then row.updated_at = now return row end
    local minutes = math.min((now - row.updated_at) / 60.0, Care.MaxOfflineMinutes)
    row.updated_at = now
    while minutes > 0 and row.state == 'growing' do
        local dt = math.min(1.0, minutes)
        minutes = minutes - dt
        row.water = math.max(0, row.water - v.waterDecay * dt)
        row.nutrient = math.max(0, row.nutrient - v.nutrientDecay * dt)
        row.total_minutes = row.total_minutes + dt
        if row.water <= 0 or row.nutrient <= 0 then
            row.health = row.health - Care.HealthLossPerMinute * dt
        elseif row.water >= Care.GoodAbove and row.nutrient >= Care.GoodAbove then
            row.health = math.min(100, row.health + Care.HealthGainPerMinute * dt)
            row.care_minutes = row.care_minutes + dt
        end
        if row.water >= Care.StallBelow and row.nutrient >= Care.StallBelow then row.growth = row.growth + dt end
        if row.health <= 0 then row.health, row.state = 0, 'dead'
        elseif row.growth >= v.growMinutes then row.growth, row.state = v.growMinutes, 'ready' end
    end
    return row
end

local function save(row)
    MySQL.update('UPDATE veyl_prod_plants SET water = ?, nutrient = ?, health = ?, growth = ?, care_minutes = ?, total_minutes = ?, state = ?, updated_at = ? WHERE id = ?',
        { row.water, row.nutrient, row.health, row.growth, row.care_minutes, row.total_minutes, row.state, row.updated_at, row.id })
end

--- The prop stage (1..n) for a plant.
function Plants.stage(row)
    local v = varietyOf(row)
    local n = v and #v.stages or 1
    if row.state == 'ready' then return n end
    return math.max(1, math.min(n - 1, 1 + math.floor((row.growth / v.growMinutes) * (n - 1))))
end

--- What gets shown for a plant (to its owner or someone tending it).
function Plants.status(row)
    local v = varietyOf(row)
    return { id = row.id, variety = row.variety, label = v and v.label or row.variety, state = row.state, x = row.x, y = row.y, property = row.property_id, growth = row.growth / (v and v.growMinutes or 1),
        water = math.floor(row.water), nutrient = math.floor(row.nutrient), health = math.floor(row.health), stage = Plants.stage(row),
        minutesLeft = v and row.state == 'growing' and math.max(0, math.ceil(v.growMinutes - row.growth)) or 0,
        careRatio = row.total_minutes > 0 and row.care_minutes / row.total_minutes or 1 }
end

--- Quality for a harvest: variety base, steady care, health, skill, equipment and a random variation.
function Plants.quality(row, level, bonus)
    local v = varietyOf(row)
    local careRatio = row.total_minutes > 0 and row.care_minutes / row.total_minutes or 1
    local q = v.baseQuality + Care.CareQualityWeight * careRatio + Care.HealthQualityWeight * (row.health / 100) + C.Quality.PerLevel * (level - 1) + (bonus or 0)
        + math.random(-C.Quality.Variance, C.Quality.Variance)
    return ProdUtil.clamp(ProdUtil.round(q), 1, 100)
end

---------------------------------------------------------------------------
-- Loading, access
---------------------------------------------------------------------------
function Plants.load()
    Plants.rows = {}
    for _, r in ipairs(MySQL.query.await('SELECT * FROM veyl_prod_plants') or {}) do Plants.rows[r.id] = r end
end

local function count(cid) local n = 0 for _, r in pairs(Plants.rows) do if r.owner_cid == cid then n = n + 1 end end return n end

--- May this player tend this plant? Owners always; lab members with the `plants` permission when the plant is in their lab.
local function canTend(cid, row)
    if row.owner_cid == cid then return true end
    return row.property_id ~= nil and Prod.Props.can(cid, row.property_id, 'plants')
end

--- All plants, for the client to draw. Positions are public; care details are not.
function Plants.list(cid)
    local out = {}
    local now = os.time()
    for _, r in pairs(Plants.rows) do
        Plants.simulate(r, now)
        out[#out + 1] = { id = r.id, variety = r.variety, x = r.x, y = r.y, z = r.z, heading = r.heading, property = r.property_id,
            stage = Plants.stage(r), state = r.state, mine = r.owner_cid == cid, tend = canTend(cid, r) }
    end
    return out
end

function Plants.mine(cid)
    local out = {}
    local now = os.time()
    for _, r in pairs(Plants.rows) do
        if canTend(cid, r) then Plants.simulate(r, now) out[#out + 1] = Plants.status(r) end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
function Plants.place(src, cid, d)
    local varietyKey = Prod.Sec.str(d.variety, 24, '^[%w_]+$')
    local v = varietyKey and B.Varieties[varietyKey]
    if not v then Prod.Sec.invalid(src, cid, 'plant_bad_variety') return Veyl.Err('INVALID_INPUT', 'Unknown plant') end
    local pos, heading = Place.position(d)
    if not pos then Prod.Sec.invalid(src, cid, 'plant_bad_position') return Veyl.Err('INVALID_INPUT', 'Bad position') end
    local level = Prod.Prog.level(cid, 'botanical')
    if level < v.level then return Veyl.Err('LEVEL_REQUIRED', ('Needs botanical level %d'):format(v.level)) end
    if count(cid) >= C.Placement.MaxPlantsPerPlayer then return Veyl.Err('LIMIT', ('You can keep up to %d plants'):format(C.Placement.MaxPlantsPerPlayer)) end
    local propertyId = d.property and Prod.Sec.str(d.property, 32, '^[%w_]+$') or nil
    local others = {}
    for _, r in pairs(Plants.rows) do others[#others + 1] = r end
    for _, w in pairs(Prod.Ws.rows) do others[#others + 1] = w end
    local why = Place.problem(src, cid, pos, propertyId, others)
    if why then return Veyl.Err('INVALID_PLACEMENT', why) end
    if not Prod.Sec.try(cid, 'place', C.Cooldowns.Place) then return Veyl.Err('RATE_LIMITED', 'Slow down') end
    if Prod.Inv.count(src, v.seed) < 1 then return Veyl.Err('NO_ITEM', ('You need %s'):format(ProdItemLabels[v.seed])) end
    if Prod.Inv.count(src, B.PlanterItem) < 1 then return Veyl.Err('NO_ITEM', 'You need a planter') end

    local tag = ('prodplant:%s:%s'):format(cid, Veyl.NewId())
    local t1 = Prod.Inv.take(cid, v.seed, 1, nil, tag .. ':seed')
    if not (t1 and t1.ok) then return Veyl.Err('NO_ITEM', 'Could not take the seed') end
    local t2 = Prod.Inv.take(cid, B.PlanterItem, 1, nil, tag .. ':pot')
    if not (t2 and t2.ok) then
        Prod.Inv.give(cid, v.seed, 1, nil, tag .. ':undo')
        return Veyl.Err('NO_ITEM', 'Could not take the planter')
    end
    local now = os.time()
    local id = MySQL.insert.await([[INSERT INTO veyl_prod_plants (owner_cid, variety, x, y, z, heading, property_id, water, nutrient, health, planted_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 100, ?, ?)]], { cid, varietyKey, pos.x, pos.y, pos.z, heading, propertyId, Care.StartMeter, Care.StartMeter, now, now })
    if not id then
        Prod.Inv.give(cid, v.seed, 1, nil, tag .. ':undo1')
        Prod.Inv.give(cid, B.PlanterItem, 1, nil, tag .. ':undo2')
        return Veyl.Err('DATABASE_ERROR', 'Could not plant it')
    end
    Plants.rows[id] = { id = id, owner_cid = cid, branch = 'botanical', variety = varietyKey, x = pos.x, y = pos.y, z = pos.z, heading = heading, property_id = propertyId,
        water = Care.StartMeter + 0.0, nutrient = Care.StartMeter + 0.0, health = 100.0, growth = 0.0, care_minutes = 0.0, total_minutes = 0.0, state = 'growing', planted_at = now, updated_at = now }
    Prod.Prog.award(cid, 'botanical', 'plant')
    Prod.Prog.stat(cid, 'plants_planted')
    Prod.Log.event('plant', cid, ('planted %s #%d'):format(varietyKey, id))
    Prod.Police.maybeAlert(cid, 'plant', pos)
    TriggerClientEvent('veyl_production:refresh', -1, 'plants')
    return Veyl.Ok({ id = id }, ('%s planted'):format(v.label))
end

local function target(src, cid, id)
    id = Prod.Sec.int(id, 2147483647)
    local row = id and Plants.rows[id]
    if not row then return nil, Veyl.Err('NOT_FOUND', 'That plant is gone') end
    if not Prod.Sec.near(src, row, C.Distance.Plant) then return nil, Veyl.Err('TOO_FAR', 'Get closer') end
    if not canTend(cid, row) then Prod.Sec.invalid(src, cid, 'plant_not_yours', { id = id }) return nil, Veyl.Err('NO_PERMISSION', 'That is not your plant') end
    Plants.simulate(row, os.time())
    save(row) -- the database must agree with what the player just saw (claims below depend on `state`)
    return row
end

function Plants.inspect(src, cid, id)
    local row, err = target(src, cid, id)
    if not row then return err end
    save(row)
    return Veyl.Ok(Plants.status(row))
end

--- Water or feed a plant with a configured item.
function Plants.care(src, cid, id, kind)
    local row, err = target(src, cid, id)
    if not row then return err end
    if row.state ~= 'growing' then return Veyl.Err('INVALID_STATE', row.state == 'dead' and 'It is dead' or 'It is ready to harvest') end
    local item, field = B.WaterItem, 'water'
    if kind == 'nutrient' then item, field = B.NutrientItem, 'nutrient' elseif kind ~= 'water' then return Veyl.Err('INVALID_INPUT', 'Unknown care') end
    if row[field] >= 95 then return Veyl.Err('INVALID_STATE', 'It does not need that right now') end
    if not Prod.Sec.try(cid, 'care:' .. row.id, C.Cooldowns.Water) then return Veyl.Err('RATE_LIMITED', 'Slow down') end
    local t = Prod.Inv.take(cid, item, 1, nil, ('prodcare:%s:%s'):format(cid, Veyl.NewId()))
    if not (t and t.ok) then return Veyl.Err('NO_ITEM', ('You need %s'):format(ProdItemLabels[item])) end
    row[field] = math.min(100, row[field] + (kind == 'water' and Care.WaterAdds or Care.NutrientAdds))
    save(row)
    Prod.Prog.award(cid, 'botanical', 'water')
    return Veyl.Ok(Plants.status(row), kind == 'water' and 'Watered' or 'Fed')
end

--- Harvest. The claim string stores the roll, so a retry after a crash repeats the very same grant (same operation id).
function Plants.harvest(src, cid, id)
    local row, err = target(src, cid, id)
    if not row then return err end
    if row.state ~= 'ready' then return Veyl.Err('INVALID_STATE', row.state == 'dead' and 'It is dead' or 'It is not ready yet') end
    if row.owner_cid ~= cid and not (row.property_id and Prod.Props.can(cid, row.property_id, 'plants')) then return Veyl.Err('NO_PERMISSION', 'Not yours') end
    local v = varietyOf(row)
    local level = Prod.Prog.level(cid, 'botanical')
    if not Prod.Sec.try(cid, 'harvest', C.Cooldowns.Harvest) then return Veyl.Err('RATE_LIMITED', 'Slow down') end

    local claim = row.harvest_claim
    local count_, quality, token
    if claim then
        token, count_, quality = claim:match('^(%w+):(%d+):(%d+)$')
        count_, quality = tonumber(count_), tonumber(quality)
    end
    if not count_ then
        count_ = math.random(v.yield[1], v.yield[2])
        quality = Plants.quality(row, level, Prod.Props.benchBonus(row.property_id))
        token = Veyl.NewId():gsub('%W', ''):sub(1, 12)
        if not Prod.Inv.canCarry(cid, ProdItems.leaf, count_, Prod.Inv.productMeta(row.variety, quality, '', 'botanical')) then
            return Veyl.Err('INVENTORY_FULL', 'You cannot carry the harvest')
        end
        local claimed = MySQL.update.await('UPDATE veyl_prod_plants SET harvest_claim = ? WHERE id = ? AND harvest_claim IS NULL AND state = ?',
            { ('%s:%d:%d'):format(token, count_, quality), row.id, 'ready' })
        if (claimed or 0) < 1 then return Veyl.Err('BUSY', 'Someone else is harvesting it') end
        row.harvest_claim = ('%s:%d:%d'):format(token, count_, quality)
    end
    local batch = ('H%d'):format(row.id)
    local g = Prod.Inv.give(cid, ProdItems.leaf, count_, Prod.Inv.productMeta(row.variety, quality, batch, 'botanical'), ('prodharvest:%d:%s'):format(row.id, token))
    if not (g and g.ok) then
        -- Nothing was granted (the operation is recorded only when it commits), so release the claim and let them try again.
        MySQL.update('UPDATE veyl_prod_plants SET harvest_claim = NULL WHERE id = ?', { row.id })
        row.harvest_claim = nil
        return Veyl.Err(g and g.code or 'FAILED', 'Could not collect the harvest')
    end
    local extras = {}
    if B.SeedReturnItem and math.random() < v.seedReturn then
        Prod.Inv.give(cid, v.seed, 1, nil, ('prodharvest:%d:%s:seed'):format(row.id, token))
        extras[#extras + 1] = '1 seed'
    end
    if math.random() < B.PlanterRecovery then
        Prod.Inv.give(cid, B.PlanterItem, 1, nil, ('prodharvest:%d:%s:pot'):format(row.id, token))
        extras[#extras + 1] = 'the planter'
    end
    MySQL.update('DELETE FROM veyl_prod_plants WHERE id = ?', { row.id })
    Plants.rows[row.id] = nil
    local xp = Prod.Prog.award(cid, 'botanical', 'harvest')
    Prod.Prog.stat(cid, 'plants_harvested')
    Prod.Prog.stat(cid, 'leaves_harvested', count_)
    Prod.Log.event('harvest', cid, ('harvested %s x%d (quality %d)'):format(row.variety, count_, quality), { plant = row.id })
    Prod.Police.maybeAlert(cid, 'harvest', row)
    TriggerClientEvent('veyl_production:refresh', -1, 'plants')
    return Veyl.Ok({ count = count_, quality = quality, tier = ProdUtil.tier(quality).label, xp = xp },
        ('Harvested %d (%s)%s'):format(count_, ProdUtil.tier(quality).label, #extras > 0 and (', plus ' .. table.concat(extras, ' and ')) or ''))
end

--- Removes a plant (owner only). Dead plants and unwanted ones both go; the planter may come back.
function Plants.remove(src, cid, id)
    local row, err = target(src, cid, id)
    if not row then return err end
    if row.owner_cid ~= cid and not (row.property_id and Prod.Props.can(cid, row.property_id, 'manage')) then return Veyl.Err('NO_PERMISSION', 'Only the owner can remove it') end
    local deleted = MySQL.update.await('DELETE FROM veyl_prod_plants WHERE id = ?', { row.id })
    if (deleted or 0) < 1 then return Veyl.Err('NOT_FOUND', 'That plant is gone') end
    Plants.rows[row.id] = nil
    if math.random() < B.PlanterRecovery then Prod.Inv.give(cid, B.PlanterItem, 1, nil, ('prodremove:%d'):format(row.id)) end
    Prod.Log.event('plant', cid, ('removed plant #%d'):format(row.id))
    TriggerClientEvent('veyl_production:refresh', -1, 'plants')
    return Veyl.Ok(nil, 'Plant removed')
end

--- Admin diagnostics: plants whose lab no longer exists or whose owner is missing.
function Plants.orphans()
    local out = {}
    for _, r in pairs(Plants.rows) do
        if r.property_id and not Prod.Props.exists(r.property_id) then out[#out + 1] = r.id end
    end
    return out
end
