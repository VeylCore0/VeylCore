-- Player profiles (reputation, stats, heat), cooldowns, challenges and the activity feed. All of it server-side and persistent.

Boost = Boost or {}
Boost.Prog = {}
local Prog = Boost.Prog
local C = BoostingConfig
local profiles = {} -- [cid] = profile (cached while the player is online)

local function core(name, ...) return Veyl.Await('veyl_core', name, 15000, ...) end

--- Loads (or creates) the player's profile.
function Prog.get(cid)
    local p = profiles[cid]
    if p then return p end
    MySQL.insert.await('INSERT IGNORE INTO veyl_boost_players (citizenid) VALUES (?)', { cid })
    local row = MySQL.single.await('SELECT rep, completed, failed, earnings, best_seconds, heat, heat_at FROM veyl_boost_players WHERE citizenid = ?', { cid })
    p = { cid = cid, rep = row.rep, completed = row.completed, failed = row.failed, earnings = row.earnings, best = row.best_seconds,
        heat = row.heat, heatAt = row.heat_at > 0 and row.heat_at or os.time(), cool = {}, done = {} }
    for _, c in ipairs(MySQL.query.await('SELECT ckey, until_at FROM veyl_boost_cooldowns WHERE citizenid = ? AND until_at > ?', { cid, os.time() }) or {}) do
        p.cool[c.ckey] = c.until_at
    end
    -- How often each template was completed (for `requires`).
    for _, r in ipairs(MySQL.query.await([[SELECT c.template, COUNT(*) AS n FROM veyl_boost_contracts c
        JOIN veyl_boost_members m ON m.contract_id = c.id WHERE m.citizenid = ? AND c.state = 'completed' GROUP BY c.template]], { cid }) or {}) do
        p.done[r.template] = r.n
    end
    profiles[cid] = p
    return p
end

function Prog.forget(cid) profiles[cid] = nil end

function Prog.saveHeat(p)
    MySQL.update('UPDATE veyl_boost_players SET heat = ?, heat_at = ? WHERE citizenid = ?', { p.heat, p.heatAt, p.cid })
end

local function addActivity(cid, kind, text, detail)
    MySQL.insert('INSERT INTO veyl_boost_activity (citizenid, kind, text, detail, at) VALUES (?, ?, ?, ?, ?)', { cid, kind, text:sub(1, 120), detail, os.time() })
end
Prog.activity = addActivity

function Prog.recent(cid, n)
    return MySQL.query.await('SELECT kind, text, detail, at FROM veyl_boost_activity WHERE citizenid = ? ORDER BY id DESC LIMIT ?', { cid, n or 6 }) or {}
end

--- Changes reputation (never below 0). Returns the new total and, when the rank changed, the new rank row.
function Prog.addRep(cid, delta, reason)
    local p = Prog.get(cid)
    local before = BoostingUtil.rankFor(p.rep)
    p.rep = math.max(0, p.rep + math.floor(delta))
    MySQL.update('UPDATE veyl_boost_players SET rep = ? WHERE citizenid = ?', { p.rep, cid })
    local idx, rank = BoostingUtil.rankFor(p.rep)
    Boost.Log.audit(cid, 'rep', { delta = delta, rep = p.rep, reason = reason })
    if idx ~= before then
        addActivity(cid, idx > before and 'rank' or 'rankdown', ('%s: now %s'):format(idx > before and 'Rank up' or 'Rank lost', rank.label), rank.label)
        return p.rep, rank, idx > before
    end
    return p.rep
end

--- Updates lifetime statistics after a contract.
function Prog.record(cid, ok, earned, seconds, templateId)
    local p = Prog.get(cid)
    if ok then
        p.completed = p.completed + 1
        p.earnings = p.earnings + (earned or 0)
        if seconds and (not p.best or seconds < p.best) then p.best = seconds end
        p.done[templateId] = (p.done[templateId] or 0) + 1
    else
        p.failed = p.failed + 1
    end
    MySQL.update('UPDATE veyl_boost_players SET completed = ?, failed = ?, earnings = ?, best_seconds = ? WHERE citizenid = ?',
        { p.completed, p.failed, p.earnings, p.best, cid })
end

---------------------------------------------------------------------------
-- Cooldowns
---------------------------------------------------------------------------
function Prog.cooldownLeft(cid, key)
    local p = Prog.get(cid)
    local left = (p.cool[key] or 0) - os.time()
    return left > 0 and left or 0
end

function Prog.setCooldown(cid, key, seconds)
    if seconds <= 0 then return end
    local p = Prog.get(cid)
    local untilAt = os.time() + seconds
    p.cool[key] = untilAt
    MySQL.update('INSERT INTO veyl_boost_cooldowns (citizenid, ckey, until_at) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE until_at = VALUES(until_at)', { cid, key, untilAt })
end

---------------------------------------------------------------------------
-- Challenges (daily and weekly)
---------------------------------------------------------------------------
local function periodKey(kind)
    if kind == 'daily' then return 'd' .. os.date('!%Y-%m-%d') end
    return 'w' .. math.floor((os.time() + 3 * 86400) / 604800)   -- weeks start on Monday (the epoch began on a Thursday)
end

function Prog.challenges(cid)
    local out = {}
    for _, kind in ipairs({ 'daily', 'weekly' }) do
        local period = periodKey(kind)
        local rows = {}
        for _, r in ipairs(MySQL.query.await('SELECT challenge, progress, paid FROM veyl_boost_challenges WHERE citizenid = ? AND period = ?', { cid, period }) or {}) do
            rows[r.challenge] = r
        end
        for _, def in ipairs(C.Challenges[kind] or {}) do
            local r = rows[def.id]
            out[#out + 1] = { id = def.id, kind = kind, label = def.label, goal = def.goal, reward = def.reward,
                progress = math.min(def.goal, r and r.progress or 0), done = r ~= nil and r.paid == 1 }
        end
    end
    return out
end

--- Adds progress to every challenge using this metric and pays the ones that just reached their goal (once, idempotently).
function Prog.bump(cid, metric, amount)
    local paid = {}
    if amount <= 0 then return paid end
    for _, kind in ipairs({ 'daily', 'weekly' }) do
        local period = periodKey(kind)
        for _, def in ipairs(C.Challenges[kind] or {}) do
            if def.metric == metric then
                MySQL.update.await([[INSERT INTO veyl_boost_challenges (citizenid, period, challenge, progress) VALUES (?, ?, ?, ?)
                    ON DUPLICATE KEY UPDATE progress = progress + VALUES(progress)]], { cid, period, def.id, amount })
                local row = MySQL.single.await('SELECT progress FROM veyl_boost_challenges WHERE citizenid = ? AND period = ? AND challenge = ?', { cid, period, def.id })
                if row and row.progress >= def.goal then
                    -- Only one caller can flip paid from 0 to 1, so the reward is granted once.
                    local flipped = MySQL.update.await('UPDATE veyl_boost_challenges SET paid = 1 WHERE citizenid = ? AND period = ? AND challenge = ? AND paid = 0', { cid, period, def.id })
                    if (flipped or 0) > 0 then
                        core('CreditOnce', cid, 'cash', def.reward, ('Boosting challenge: %s'):format(def.label), ('boost:chal:%s:%s:%s'):format(cid, period, def.id))
                        addActivity(cid, 'challenge', ('Challenge complete: %s'):format(def.label), ('$%d'):format(def.reward))
                        Boost.Log.audit(cid, 'challenge', { id = def.id, period = period, reward = def.reward })
                        paid[#paid + 1] = def
                    end
                end
            end
        end
    end
    return paid
end
