-- Small helpers used by both sides.

BoostingUtil = {}

function BoostingUtil.clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end

function BoostingUtil.round(n) return math.floor(n + 0.5) end

--- The rank for a reputation total: index, rank row, next rank (or nil), progress 0-1 towards the next one.
function BoostingUtil.rankFor(rep)
    local ranks = BoostingConfig.Ranks
    local idx = 1
    for i, r in ipairs(ranks) do if rep >= r.rep then idx = i end end
    local nextRank = ranks[idx + 1]
    local progress = 1.0
    if nextRank then progress = BoostingUtil.clamp((rep - ranks[idx].rep) / (nextRank.rep - ranks[idx].rep), 0, 1) end
    return idx, ranks[idx], nextRank, progress
end

--- The heat level row for a heat value.
function BoostingUtil.heatLevel(value)
    for _, l in ipairs(BoostingConfig.Heat.Levels) do if value <= l.max then return l end end
    local levels = BoostingConfig.Heat.Levels
    return levels[#levels]
end

function BoostingUtil.heatLevelIndex(id)
    for i, l in ipairs(BoostingConfig.Heat.Levels) do if l.id == id then return i end end
    return 1
end
