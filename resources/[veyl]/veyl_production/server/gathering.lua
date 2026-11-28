-- Gathering and field searching (one engine, two configs): botanical wild spots (config/botanical.lua) and field zones with several
-- searchable points each (config/field_operations.lua). The server checks the spot, the distance, the level, the per-player and per-point
-- cooldowns, times the action and rolls the reward itself; the page only asks. One start, one finish, one reward.

Prod = Prod or {}
Prod.Gather = { jobs = {}, global = {} }
local G = Prod.Gather
local C = ProductionConfig

--- Every spot as one list: { id, label, branch, level, points = { vector3 }, cooldown (player, seconds), respawn (everyone, seconds), rewards, durationMs, kind, flat }.
function G.spots()
    local out = {}
    for _, s in ipairs(C.Gathering.Spots) do
        out[#out + 1] = { id = s.id, label = s.label, branch = 'botanical', level = s.level, points = { s.coords }, radius = s.radius, cooldown = s.cooldown, respawn = 0,
            rewards = C.Gathering.Rewards, durationMs = C.Gathering.DurationMs, xp = 'gather', alert = nil, flat = false }
    end
    for _, z in ipairs((C.Field and C.Field.Zones) or {}) do
        out[#out + 1] = { id = z.id, label = z.label, branch = z.branch or 'field', level = z.level, points = z.points, radius = 3.0, cooldown = (z.PlayerCooldownMinutes or 40) * 60,
            respawn = (z.RespawnMinutes or 12) * 60, rewards = C.Field.Rewards, durationMs = C.Field.SearchMs, xp = 'search', alert = 'field_search', flat = true, prop = z.prop }
    end
    return out
end

local function spot(id) for _, s in ipairs(G.spots()) do if s.id == id then return s end end end

local function pointDistance(s, pc, p)
    if s.flat then return ProdUtil.distance2d(pc, p) end
    return ProdUtil.distance(pc, p)
end

function G.view(cid)
    local out = {}
    for _, s in ipairs(G.spots()) do
        local b = C.Branches[s.branch]
        if b and b.enabled then
            local lvl = Prod.Prog.level(cid, s.branch)
            local ready = 0
            for i = 1, #s.points do if Prod.Sec.cooldownLeft(cid, ('gather:%s:%d'):format(s.id, i)) == 0 and (G.global[('%s:%d'):format(s.id, i)] or 0) <= os.time() then ready = ready + 1 end end
            out[#out + 1] = { id = s.id, label = s.label, branch = s.branch, level = s.level, locked = lvl < s.level, points = #s.points, ready = ready,
                cooldown = ready == 0 and Prod.Sec.cooldownLeft(cid, ('gather:%s:1'):format(s.id)) or 0, x = s.points[1].x, y = s.points[1].y }
        end
    end
    return out
end

--- Starts a gather or a field search. `index` picks the point in the zone (1 for a plain spot).
function G.start(src, cid, id, index)
    local s = Prod.Sec.str(id, 32, '^[%w_]+$') and spot(id)
    if not s or not (C.Branches[s.branch] and C.Branches[s.branch].enabled) then Prod.Sec.invalid(src, cid, 'gather_bad_spot', { id = id }) return Veyl.Err('INVALID_INPUT', 'Unknown spot') end
    index = Prod.Sec.int(index or 1, #s.points)
    local p = index and index >= 1 and s.points[index]
    if not p then Prod.Sec.invalid(src, cid, 'gather_bad_point', { id = id, index = index }) return Veyl.Err('INVALID_INPUT', 'Unknown spot') end
    local pc = Veyl.GetPlayerCoords(src)
    local range = s.flat and 4.0 or (s.radius or 5.0) + 2.0
    if not pc or pointDistance(s, pc, p) > range then return Veyl.Err('TOO_FAR', 'Get to the spot') end
    if s.flat and math.abs(pc.z - p.z) > 40.0 then return Veyl.Err('TOO_FAR', 'Get to the spot') end
    if Prod.Prog.level(cid, s.branch) < s.level then return Veyl.Err('LEVEL_REQUIRED', ('Needs %s level %d'):format(s.branch, s.level)) end
    local key = ('%s:%d'):format(s.id, index)
    if (G.global[key] or 0) > os.time() then return Veyl.Err('COOLDOWN', 'Someone just picked that over') end
    local left = Prod.Sec.cooldownLeft(cid, 'gather:' .. key)
    if left > 0 then return Veyl.Err('COOLDOWN', ('Picked over. Try again in %d min'):format(math.ceil(left / 60))) end
    if G.jobs[src] and GetGameTimer() - G.jobs[src].at < s.durationMs then return Veyl.Err('BUSY', 'Already busy') end
    local token = Veyl.NewId()
    G.jobs[src] = { token = token, spot = s.id, index = index, at = GetGameTimer(), cid = cid }
    return Veyl.Ok({ token = token, durationMs = s.durationMs })
end

function G.finish(src, cid, token)
    local job = G.jobs[src]
    G.jobs[src] = nil
    if not job or job.token ~= token or job.cid ~= cid then Prod.Sec.invalid(src, cid, 'gather_bad_token') return Veyl.Err('INVALID_STATE', 'Start again') end
    local s = spot(job.spot)
    if not s then return Veyl.Err('INVALID_STATE', 'Start again') end
    if GetGameTimer() - job.at < s.durationMs - 600 then Prod.Sec.invalid(src, cid, 'gather_too_fast') return Veyl.Err('TOO_FAST', 'You stopped too early') end
    local p = s.points[job.index]
    local pc = Veyl.GetPlayerCoords(src)
    if not pc or pointDistance(s, pc, p) > (s.flat and 6.0 or (s.radius or 5.0) + 4.0) then return Veyl.Err('TOO_FAR', 'You moved away') end
    local key = ('%s:%d'):format(s.id, job.index)
    -- The point is claimed (for everyone and for you) before anything is given, so a second finish cannot pay again.
    if (G.global[key] or 0) > os.time() then return Veyl.Err('COOLDOWN', 'Someone just picked that over') end
    if not Prod.Sec.try(cid, 'gather:' .. key, s.cooldown) then return Veyl.Err('COOLDOWN', 'Already picked') end
    if s.respawn > 0 then G.global[key] = os.time() + s.respawn end
    local level = Prod.Prog.level(cid, s.branch)
    local got = {}
    local tag = ('prodgather:%s:%s'):format(cid, Veyl.NewId())
    for i, r in ipairs(s.rewards) do
        if (not r.level or level >= r.level) and (i == 1 or math.random() < r.chance) then
            local n = math.random(r.min, r.max)
            local g = Prod.Inv.give(cid, r.item, n, nil, ('%s:%d'):format(tag, i))
            if g and g.ok then got[#got + 1] = { item = r.item, count = n, label = ProdItemLabels[r.item] or r.item } end
        end
    end
    Prod.Prog.award(cid, s.branch, s.xp)
    Prod.Prog.stat(cid, s.flat and 'searched' or 'gathered')
    if s.alert then Prod.Police.maybeAlert(cid, s.alert, p) end
    local text = {}
    for _, g in ipairs(got) do text[#text + 1] = ('%dx %s'):format(g.count, g.label) end
    Prod.Log.event('gather', cid, ('%s at %s: %s'):format(s.flat and 'searched' or 'gathered', key, table.concat(text, ', ')))
    if #got == 0 then return Veyl.Err('INVENTORY_FULL', 'You could not carry anything') end
    return Veyl.Ok({ rewards = got }, 'Found ' .. table.concat(text, ', '))
end

AddEventHandler('playerDropped', function() G.jobs[source] = nil end)
