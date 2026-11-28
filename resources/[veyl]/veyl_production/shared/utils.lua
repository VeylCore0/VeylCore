-- Small helpers.

ProdUtil = {}

function ProdUtil.clamp(v, lo, hi) if v < lo then return lo elseif v > hi then return hi end return v end
function ProdUtil.round(n) return math.floor(n + 0.5) end

--- The quality tier row for a score 0-100.
function ProdUtil.tier(q)
    for _, t in ipairs(ProductionConfig.Quality.Tiers) do if q <= t.max then return t end end
    local t = ProductionConfig.Quality.Tiers
    return t[#t]
end

--- Branch level (1-6) for an XP total.
function ProdUtil.levelFor(xp)
    local lv = 1
    for i, need in ipairs(ProductionConfig.Levels) do if xp >= need then lv = i end end
    return lv
end

function ProdUtil.distance(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end
