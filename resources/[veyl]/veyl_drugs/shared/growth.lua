-- Deterministic plant simulation, shared so it can be tested outside the game. The server is the only caller that
-- matters: it advances plants from timestamps (no per-second work) and persists the result.
--
-- Plant state: growth (0-100), water, care, health (0-100), careSum/careWeight (quality integral),
-- readyAt (unix time growth reached 100, or nil).

Growth = {}

local function clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

function Growth.variety(p)
    local prod = DrugsProducts[p.type]
    return prod and prod.varieties[p.variety] or nil
end

--- Advances `p` from p.updatedAt to `now` (unix seconds). online = someone responsible for the plant is online.
--- Works in steps of at most 10 minutes (larger steps for very long gaps) so results don't depend on call frequency.
function Growth.advance(p, now, online)
    local v = Growth.variety(p)
    if not v or p.state ~= 'growing' then p.updatedAt = now return p end
    local cfg = DrugsConfig.Growth
    local remaining = now - (p.updatedAt or now)
    if remaining <= 0 then return p end
    local step = remaining > 86400 * 3 and 3600 or 600
    local decay = online and 1.0 or cfg.Offline.DecayMultiplier
    local floor = online and 0 or cfg.Offline.HealthFloor
    local t = p.updatedAt
    while remaining > 0 do
        local dt = math.min(step, remaining)
        local h = dt / 3600
        p.water = clamp(p.water - v.waterUse * decay * h, 0, 100)
        p.care = clamp(p.care - v.careUse * decay * h, 0, 100)
        local neglected = p.water <= cfg.DryThreshold or p.care <= cfg.DryThreshold
        if p.growth < 100 then
            p.growth = clamp(p.growth + (100 / v.growHours) * h * (neglected and cfg.NeglectGrowthFactor or 1.0) * (p.health / 100 * 0.5 + 0.5), 0, 100)
            -- Quality integral: how well kept the plant was while it grew.
            local goodness = ((p.water + p.care) / 200) * (p.health / 100)
            p.careSum = (p.careSum or 0) + goodness * h
            p.careWeight = (p.careWeight or 0) + h
            if p.growth >= 100 and not p.readyAt then p.readyAt = t + dt end
        end
        local overripe = p.readyAt ~= nil and (t + dt) - p.readyAt > cfg.ReadyWindowHours * 3600
        if p.water <= 0 or p.care <= 0 then
            p.health = math.max(floor, p.health - cfg.HealthLossPerHour * h)
        elseif overripe then
            -- Left too long after it was ready: slowly wilts toward the floor (never raises a lower health).
            p.health = math.min(p.health, math.max(cfg.OverripeHealthFloor, p.health - cfg.OverripeHealthPerHour * h))
        else
            p.health = clamp(p.health + cfg.HealthGainPerHour * h, 0, 100)
        end
        if p.health <= 0 then p.state = 'dead' break end
        t = t + dt
        remaining = remaining - dt
    end
    p.updatedAt = now
    return p
end

function Growth.stage(p)
    if p.growth >= 100 then return 4 end
    if p.growth >= 60 then return 3 end
    if p.growth >= 25 then return 2 end
    return 1
end

--- Care score 0-100 (before the variety cap).
function Growth.careScore(p)
    if not p.careWeight or p.careWeight <= 0 then return 50 end
    return clamp(math.floor(p.careSum / p.careWeight * 100 + 0.5), 0, 100)
end

--- Final quality 0-100 and grade, capped by the variety.
function Growth.quality(p)
    local v = Growth.variety(p)
    local q = math.min(Growth.careScore(p), v and v.maxQuality or 100)
    q = math.floor(q * (0.85 + 0.15 * p.health / 100) + 0.5)
    for _, g in ipairs(DrugsConfig.Grades) do
        if q >= g.min then return q, g end
    end
    return q, DrugsConfig.Grades[#DrugsConfig.Grades]
end

function Growth.yield(p)
    local v = Growth.variety(p)
    return math.max(1, math.floor((v and v.yield or 1) * (0.6 + 0.4 * p.health / 100) + 0.5))
end

--- Public view used by the plant card and journal.
function Growth.view(p)
    local v = Growth.variety(p)
    local q, grade = Growth.quality(p)
    return {
        id = p.id, type = p.type, typeLabel = DrugsProducts[p.type] and DrugsProducts[p.type].label or p.type,
        variety = p.variety, varietyLabel = v and v.label or p.variety, trait = v and v.trait or nil,
        container = p.container, state = p.state, stage = Growth.stage(p),
        growth = math.floor(p.growth), water = math.floor(p.water), care = math.floor(p.care), health = math.floor(p.health),
        ready = p.state == 'growing' and p.growth >= 100, quality = q, grade = grade.label, gradeId = grade.id,
        expectedYield = Growth.yield(p),
        etaMinutes = (p.growth < 100 and v) and math.ceil((100 - p.growth) / (100 / v.growHours) * 60) or 0,
        coords = { x = p.x, y = p.y, z = p.z },
    }
end
