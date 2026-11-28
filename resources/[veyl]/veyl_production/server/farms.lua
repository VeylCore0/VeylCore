-- Admin farms: weed farms, coke farms and the like that staff place in game with /drugadmin. A farm is a set of points; players search them
-- through the same gathering engine as field zones (server/gathering.lua reads Prod.Farms.spots()), so every rule there applies. Farms are
-- saved in veyl_prod_farms, loaded at start and pushed to every client when they change.

Prod = Prod or {}
Prod.Farms = { rows = {} }
local F = Prod.Farms
local C = ProductionConfig

local function cfg() return C.Farms end

-- Staff: the production.admin permission, or the general veyl.admin one that group.admin already has (full admins need no extra line).
function F.isAdmin(src)
    if src == nil then return false end
    return Veyl.HasPermission(src, cfg().Permission) or Veyl.HasPermission(src, 'admin')
end

local function denied(src, cid, what)
    Prod.Log.suspicious(src, cid, 'admin_denied', { action = what })
    return Veyl.Err('NO_PERMISSION', 'Staff only')
end

local function id_(n) return 'farm_' .. n end

function F.load()
    F.rows = {}
    for _, r in ipairs(MySQL.query.await('SELECT * FROM veyl_prod_farms') or {}) do
        local ok1, rewards = pcall(json.decode, r.rewards or '[]')
        local ok2, points = pcall(json.decode, r.points or '[]')
        if ok1 and ok2 and type(rewards) == 'table' and type(points) == 'table' then
            F.rows[r.id] = { id = r.id, label = r.label, kind = r.kind, branch = r.branch, level = r.level, prop = r.prop, respawn = r.respawn_min,
                cooldown = r.cooldown_min, rewards = rewards, points = points }
        end
    end
end

--- What the gathering engine needs (same shape as a field zone).
function F.spots()
    local out = {}
    for _, f in pairs(F.rows) do
        if C.Branches[f.branch] and C.Branches[f.branch].enabled and #f.points > 0 and #f.rewards > 0 then
            local pts = {}
            for i, p in ipairs(f.points) do pts[i] = vector3(p.x, p.y, p.z) end
            out[#out + 1] = { id = id_(f.id), label = f.label, branch = f.branch, level = f.level, points = pts, radius = 3.0, cooldown = f.cooldown * 60, respawn = f.respawn * 60,
                rewards = f.rewards, durationMs = (C.Field and C.Field.SearchMs) or 5000, xp = 'search', alert = 'field_search', flat = true, prop = f.prop }
        end
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

--- What clients draw: id, label, prop, branch and the points (no rewards).
function F.publicList()
    local out = {}
    for _, f in pairs(F.rows) do
        out[#out + 1] = { id = id_(f.id), label = f.label, branch = f.branch, prop = f.prop, points = f.points }
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

function F.broadcast() TriggerClientEvent('veyl_production:farms', -1, F.publicList()) end

--- Items an admin may use in rewards: every production item except benches and cards.
function F.rewardItems()
    local out = {}
    for item, label in pairs(ProdItemLabels) do
        if not cfg().ExcludeItems[item] then out[#out + 1] = { item = item, label = label } end
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return out
end

local function allowedItem(item) return type(item) == 'string' and ProdItemLabels[item] ~= nil and not cfg().ExcludeItems[item] end

--- The full admin view: farms with everything editable, the presets and the item list.
function F.adminView(src, cid)
    if not F.isAdmin(src) then return denied(src, cid, 'view') end
    local farms = {}
    for _, f in pairs(F.rows) do
        farms[#farms + 1] = { id = f.id, key = id_(f.id), label = f.label, kind = f.kind, branch = f.branch, level = f.level, prop = f.prop, respawn = f.respawn,
            cooldown = f.cooldown, rewards = f.rewards, points = f.points }
    end
    table.sort(farms, function(a, b) return a.id < b.id end)
    local presets = {}
    for k, p in pairs(cfg().Presets) do presets[#presets + 1] = { kind = k, label = p.label, branch = p.branch } end
    table.sort(presets, function(a, b) return a.kind < b.kind end)
    local labels = {}
    for item, l in pairs(ProdItemLabels) do labels[item] = l end
    return Veyl.Ok({ farms = farms, presets = presets, items = F.rewardItems(), max = { farms = cfg().MaxFarms, points = cfg().MaxPoints, rewards = cfg().MaxRewards } })
end

local function persist(f)
    MySQL.update('UPDATE veyl_prod_farms SET label = ?, level = ?, prop = ?, respawn_min = ?, cooldown_min = ?, rewards = ?, points = ? WHERE id = ?',
        { f.label, f.level, f.prop, f.respawn, f.cooldown, json.encode(f.rewards), json.encode(f.points), f.id })
end

local function here(src)
    local pc = Veyl.GetPlayerCoords(src)
    if not pc then return nil end
    return { x = math.floor(pc.x * 100 + 0.5) / 100, y = math.floor(pc.y * 100 + 0.5) / 100, z = math.floor(pc.z * 100 + 0.5) / 100 }
end

local function count() local n = 0 for _ in pairs(F.rows) do n = n + 1 end return n end

function F.create(src, cid, kind, label)
    if not F.isAdmin(src) then return denied(src, cid, 'create') end
    local p = Prod.Sec.str(kind, 16, '^%a+$') and cfg().Presets[kind]
    label = type(label) == 'string' and label:gsub('^%s+', ''):gsub('%s+$', '') or ''
    if not p then return Veyl.Err('INVALID_INPUT', 'Unknown kind') end
    if #label < 1 or #label > 40 then label = p.label end
    if count() >= cfg().MaxFarms then return Veyl.Err('LIMIT', 'Too many farms') end
    local pos = here(src)
    if not pos then return Veyl.Err('FAILED', 'Could not read your position') end
    local rewards = {}
    for i, r in ipairs(p.rewards) do rewards[i] = { item = r.item, chance = r.chance, min = r.min, max = r.max, level = r.level } end
    local id = MySQL.insert.await('INSERT INTO veyl_prod_farms (label, kind, branch, level, prop, respawn_min, cooldown_min, rewards, points, created_by) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        { label, kind, p.branch, p.level, p.prop, p.respawn, p.cooldown, json.encode(rewards), json.encode({ pos }), cid })
    if not id then return Veyl.Err('FAILED', 'Could not save it') end
    F.rows[id] = { id = id, label = label, kind = kind, branch = p.branch, level = p.level, prop = p.prop, respawn = p.respawn, cooldown = p.cooldown, rewards = rewards, points = { pos } }
    Prod.Log.event('admin', cid, ('created %s farm #%d "%s"'):format(kind, id, label))
    F.broadcast()
    return Veyl.Ok({ id = id }, ('%s added with its first point here'):format(label))
end

local function farm(src, cid, id, what)
    if not F.isAdmin(src) then return nil, denied(src, cid, what) end
    id = Prod.Sec.int(id, 1e9)
    local f = id and F.rows[id]
    if not f then return nil, Veyl.Err('INVALID_INPUT', 'Unknown farm') end
    return f
end

function F.addPoint(src, cid, id)
    local f, err = farm(src, cid, id, 'addPoint')
    if not f then return err end
    if #f.points >= cfg().MaxPoints then return Veyl.Err('LIMIT', 'That farm has the most points allowed') end
    local pos = here(src)
    if not pos then return Veyl.Err('FAILED', 'Could not read your position') end
    for _, p in ipairs(f.points) do
        if ProdUtil.distance2d(p, pos) < 1.0 then return Veyl.Err('INVALID_STATE', 'There is already a point here') end
    end
    f.points[#f.points + 1] = pos
    persist(f)
    Prod.Log.event('admin', cid, ('farm #%d: point %d added'):format(f.id, #f.points))
    F.broadcast()
    return Veyl.Ok({ points = #f.points }, ('Point %d added'):format(#f.points))
end

function F.removePoint(src, cid, id, index)
    local f, err = farm(src, cid, id, 'removePoint')
    if not f then return err end
    index = Prod.Sec.int(index, 1000)
    if not index or index < 1 or not f.points[index] then return Veyl.Err('INVALID_INPUT', 'Unknown point') end
    if #f.points <= 1 then return Veyl.Err('INVALID_STATE', 'A farm needs at least one point. Delete the farm instead.') end
    table.remove(f.points, index)
    persist(f)
    -- Cooldown keys are per point index, so indexes after the removed one shift; clear this farm's global cooldowns.
    for k in pairs(Prod.Gather.global) do if k:find('^' .. id_(f.id) .. ':') then Prod.Gather.global[k] = nil end end
    Prod.Log.event('admin', cid, ('farm #%d: point %d removed'):format(f.id, index))
    F.broadcast()
    return Veyl.Ok({ points = #f.points }, 'Point removed')
end

--- Name, level, timings and prop. Only the fields sent are changed, each checked.
function F.update(src, cid, id, d)
    local f, err = farm(src, cid, id, 'update')
    if not f then return err end
    if type(d) ~= 'table' then return Veyl.Err('INVALID_INPUT', 'Bad request') end
    if d.label ~= nil then
        if type(d.label) ~= 'string' or #d.label < 1 or #d.label > 40 then return Veyl.Err('INVALID_INPUT', 'Name must be 1 to 40 characters') end
        f.label = d.label
    end
    if d.level ~= nil then
        local v = Prod.Sec.int(d.level, #C.LevelNames)
        if not v or v < 1 then return Veyl.Err('INVALID_INPUT', ('Level must be 1 to %d'):format(#C.LevelNames)) end
        f.level = v
    end
    if d.respawn ~= nil then
        local v = Prod.Sec.int(d.respawn, 1440)
        if not v or v < 1 then return Veyl.Err('INVALID_INPUT', 'Respawn must be 1 to 1440 minutes') end
        f.respawn = v
    end
    if d.cooldown ~= nil then
        local v = Prod.Sec.int(d.cooldown, 1440)
        if not v or v < 1 then return Veyl.Err('INVALID_INPUT', 'Cooldown must be 1 to 1440 minutes') end
        f.cooldown = v
    end
    if d.prop ~= nil then
        if not Prod.Sec.str(d.prop, 64, '^[%w_]+$') then return Veyl.Err('INVALID_INPUT', 'That is not a model name') end
        f.prop = d.prop
    end
    persist(f)
    Prod.Log.event('admin', cid, ('farm #%d updated'):format(f.id))
    F.broadcast()
    return Veyl.Ok(nil, 'Saved')
end

--- Replaces the reward list. At least one reward; the first always pays so its chance is forced to 1.
function F.setRewards(src, cid, id, list)
    local f, err = farm(src, cid, id, 'rewards')
    if not f then return err end
    if type(list) ~= 'table' or #list < 1 or #list > cfg().MaxRewards then return Veyl.Err('INVALID_INPUT', ('Between 1 and %d rewards'):format(cfg().MaxRewards)) end
    local clean = {}
    for i, r in ipairs(list) do
        if type(r) ~= 'table' or not allowedItem(r.item) then return Veyl.Err('INVALID_INPUT', ('Reward %d: unknown item'):format(i)) end
        local chance, mn, mx = tonumber(r.chance), Prod.Sec.int(r.min, 50), Prod.Sec.int(r.max, 50)
        if not chance or chance ~= chance or chance <= 0 or chance > 1 then return Veyl.Err('INVALID_INPUT', ('Reward %d: chance must be above 0 and at most 1'):format(i)) end
        if not mn or not mx or mn < 1 or mx < mn then return Veyl.Err('INVALID_INPUT', ('Reward %d: amounts must be 1 or more, max not under min'):format(i)) end
        local lv = r.level ~= nil and Prod.Sec.int(r.level, #C.LevelNames) or nil
        if r.level ~= nil and (not lv or lv < 1) then return Veyl.Err('INVALID_INPUT', ('Reward %d: bad level'):format(i)) end
        clean[i] = { item = r.item, chance = i == 1 and 1.0 or chance, min = mn, max = mx, level = lv }
    end
    f.rewards = clean
    persist(f)
    Prod.Log.event('admin', cid, ('farm #%d: rewards set (%d)'):format(f.id, #clean))
    return Veyl.Ok(nil, 'Rewards saved')
end

function F.delete(src, cid, id)
    local f, err = farm(src, cid, id, 'delete')
    if not f then return err end
    MySQL.update('DELETE FROM veyl_prod_farms WHERE id = ?', { f.id })
    F.rows[f.id] = nil
    for k in pairs(Prod.Gather.global) do if k:find('^' .. id_(f.id) .. ':') then Prod.Gather.global[k] = nil end end
    Prod.Log.event('admin', cid, ('farm #%d "%s" deleted'):format(f.id, f.label))
    F.broadcast()
    return Veyl.Ok(nil, 'Farm deleted')
end
