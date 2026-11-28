-- Progression: XP and a level (1-6) per branch, an overall reputation level, and lifetime statistics. Server only.

Prod = Prod or {}
Prod.Prog = {}
local Prog = Prod.Prog
local C = ProductionConfig
local cache = {} -- [cid] = { xp = { branch = n }, stats = { stat = n } }

local function load(cid)
    if cache[cid] then return cache[cid] end
    local p = { xp = {}, stats = {} }
    for _, r in ipairs(MySQL.query.await('SELECT branch, xp FROM veyl_prod_progress WHERE citizenid = ?', { cid }) or {}) do p.xp[r.branch] = r.xp end
    for _, r in ipairs(MySQL.query.await('SELECT stat, value FROM veyl_prod_stats WHERE citizenid = ?', { cid }) or {}) do p.stats[r.stat] = r.value end
    cache[cid] = p
    return p
end
function Prog.forget(cid) cache[cid] = nil end

function Prog.xp(cid, branch) return load(cid).xp[branch] or 0 end
function Prog.level(cid, branch) return ProdUtil.levelFor(Prog.xp(cid, branch)) end

function Prog.reputation(cid)
    local total = 0
    for _, n in pairs(load(cid).xp) do total = total + n end
    local lv = 1
    for i, need in ipairs(C.Reputation) do if total >= need then lv = i end end
    return lv, total
end

--- Awards XP for an activity once per its cooldown. Returns the XP given (0 when on cooldown) and the new level if it rose.
function Prog.award(cid, branch, activity, multiplier)
    local def = C.XP[activity]
    if not def or def.xp <= 0 then return 0 end
    if def.cooldown > 0 and not Prod.Sec.try(cid, 'xp:' .. activity, def.cooldown) then return 0 end
    local p = load(cid)
    local before = ProdUtil.levelFor(p.xp[branch] or 0)
    local gain = math.max(1, math.floor(def.xp * (multiplier or 1)))
    p.xp[branch] = (p.xp[branch] or 0) + gain
    MySQL.update('INSERT INTO veyl_prod_progress (citizenid, branch, xp) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE xp = VALUES(xp)', { cid, branch, p.xp[branch] })
    local after = ProdUtil.levelFor(p.xp[branch])
    if after > before then Prod.Log.event('reward', cid, ('reached %s level %d'):format(branch, after)) end
    return gain, after > before and after or nil
end

function Prog.stat(cid, stat, n)
    local p = load(cid)
    p.stats[stat] = (p.stats[stat] or 0) + (n or 1)
    MySQL.update('INSERT INTO veyl_prod_stats (citizenid, stat, value) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE value = VALUES(value)', { cid, stat, p.stats[stat] })
end

function Prog.stats(cid) return load(cid).stats end

--- What the tablet shows.
function Prog.view(cid)
    local out = { branches = {}, stats = load(cid).stats }
    for id, b in pairs(C.Branches) do
        if b.enabled then
            local xp = Prog.xp(cid, id)
            local lv = ProdUtil.levelFor(xp)
            local floor, nextXp = C.Levels[lv], C.Levels[lv + 1]
            out.branches[id] = { label = b.label, icon = b.icon, color = b.color, xp = xp, level = lv, levelName = C.LevelNames[lv],
                nextXp = nextXp, floor = floor, progress = nextXp and (xp - floor) / (nextXp - floor) or 1 }
        end
    end
    local rl, total = Prog.reputation(cid)
    out.reputation = { level = rl, name = C.LevelNames[rl], xp = total, next = C.Reputation[rl + 1], floor = C.Reputation[rl] }
    return out
end
