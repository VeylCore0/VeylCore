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

--- A plant variety definition from any branch (botanical or field), with its branch and harvest item filled in.
function ProdUtil.variety(key)
    local B, F = ProductionConfig.Botanical, ProductionConfig.Field
    local v = B and B.Varieties[key] or (F and F.Varieties[key])
    if not v then return nil end
    v.branch = v.branch or 'botanical'
    v.harvestItem = v.harvestItem or 'prod_leaf'
    return v
end

--- Every variety key (both branches).
function ProdUtil.varieties()
    local out = {}
    for _, src in ipairs({ ProductionConfig.Botanical.Varieties, (ProductionConfig.Field or {}).Varieties or {} }) do
        for k in pairs(src) do out[#out + 1] = k end
    end
    return out
end

--- Distance on the ground plane only (for field points whose height is only a guide).
function ProdUtil.distance2d(a, b)
    local dx, dy = a.x - b.x, a.y - b.y
    return math.sqrt(dx * dx + dy * dy)
end
