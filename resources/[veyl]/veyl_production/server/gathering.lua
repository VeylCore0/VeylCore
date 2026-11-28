-- Gathering: wild spots with small random rewards. The server checks the spot, the distance, the level and the per-player cooldown for that
-- spot, and rolls the reward itself; the page only asks. One start, one finish, one reward.

Prod = Prod or {}
Prod.Gather = { jobs = {} }
local G = Prod.Gather
local C = ProductionConfig
local cfg = C.Gathering

local function spot(id) for _, s in ipairs(cfg.Spots) do if s.id == id then return s end end end

function G.view(cid)
    local level = Prod.Prog.level(cid, 'botanical')
    local out = {}
    for _, s in ipairs(cfg.Spots) do
        out[#out + 1] = { id = s.id, label = s.label, level = s.level, locked = level < s.level, cooldown = Prod.Sec.cooldownLeft(cid, 'gather:' .. s.id),
            x = s.coords.x, y = s.coords.y }
    end
    return out
end

function G.start(src, cid, id)
    local s = Prod.Sec.str(id, 32, '^[%w_]+$') and spot(id)
    if not s then Prod.Sec.invalid(src, cid, 'gather_bad_spot', { id = id }) return Veyl.Err('INVALID_INPUT', 'Unknown spot') end
    if not Prod.Sec.near(src, s.coords, s.radius + 2.0) then return Veyl.Err('TOO_FAR', 'Get to the spot') end
    if Prod.Prog.level(cid, 'botanical') < s.level then return Veyl.Err('LEVEL_REQUIRED', ('Needs botanical level %d'):format(s.level)) end
    local left = Prod.Sec.cooldownLeft(cid, 'gather:' .. s.id)
    if left > 0 then return Veyl.Err('COOLDOWN', ('Picked over. Try again in %d min'):format(math.ceil(left / 60))) end
    if G.jobs[src] and GetGameTimer() - G.jobs[src].at < cfg.DurationMs then return Veyl.Err('BUSY', 'Already gathering') end
    local token = Veyl.NewId()
    G.jobs[src] = { token = token, spot = s.id, at = GetGameTimer(), cid = cid }
    return Veyl.Ok({ token = token, durationMs = cfg.DurationMs })
end

function G.finish(src, cid, token)
    local job = G.jobs[src]
    G.jobs[src] = nil
    if not job or job.token ~= token or job.cid ~= cid then Prod.Sec.invalid(src, cid, 'gather_bad_token') return Veyl.Err('INVALID_STATE', 'Start again') end
    if GetGameTimer() - job.at < cfg.DurationMs - 600 then Prod.Sec.invalid(src, cid, 'gather_too_fast') return Veyl.Err('TOO_FAST', 'You stopped too early') end
    local s = spot(job.spot)
    if not s or not Prod.Sec.near(src, s.coords, s.radius + 4.0) then return Veyl.Err('TOO_FAR', 'You moved away') end
    -- The cooldown is claimed before anything is given, so a second finish cannot pay again.
    if not Prod.Sec.try(cid, 'gather:' .. s.id, s.cooldown) then return Veyl.Err('COOLDOWN', 'Already picked') end
    local level = Prod.Prog.level(cid, 'botanical')
    local got = {}
    local tag = ('prodgather:%s:%s'):format(cid, Veyl.NewId())
    for i, r in ipairs(cfg.Rewards) do
        if (not r.level or level >= r.level) and (i == 1 or math.random() < r.chance) then
            local n = math.random(r.min, r.max)
            local g = Prod.Inv.give(cid, r.item, n, nil, ('%s:%d'):format(tag, i))
            if g and g.ok then got[#got + 1] = { item = r.item, count = n, label = ProdItemLabels[r.item] or r.item } end
        end
    end
    Prod.Prog.award(cid, 'botanical', 'gather')
    Prod.Prog.stat(cid, 'gathered')
    local text = {}
    for _, g in ipairs(got) do text[#text + 1] = ('%dx %s'):format(g.count, g.label) end
    Prod.Log.event('gather', cid, ('gathered at %s: %s'):format(s.id, table.concat(text, ', ')))
    if #got == 0 then return Veyl.Err('INVENTORY_FULL', 'You could not carry anything') end
    return Veyl.Ok({ rewards = got }, 'Found ' .. table.concat(text, ', '))
end

AddEventHandler('playerDropped', function() G.jobs[source] = nil end)
