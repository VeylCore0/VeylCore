-- The market: every item's price moves with what has been sold. Selling pushes an item's pressure up (by the number of units), pressure drains
-- away over time, and the price is the base price times (1 - pressure * Impact), never below MinMult, times a small deterministic swing
-- per item per day. Both the buyer and street sales read and feed it, so dumping one product everywhere pays less and less.

Prod = Prod or {}
Prod.Market = { pressure = {}, at = {} }
local M = Prod.Market
local C = ProductionConfig

local function cfg() return C.Market end

function M.load()
    M.pressure, M.at = {}, {}
    for _, r in ipairs(MySQL.query.await('SELECT item, pressure, updated_at FROM veyl_prod_market') or {}) do
        M.pressure[r.item], M.at[r.item] = r.pressure, r.updated_at
    end
end

local function current(item)
    local p = M.pressure[item] or 0
    if p <= 0 then return 0 end
    local hours = (os.time() - (M.at[item] or os.time())) / 3600
    return math.max(0, p - hours * cfg().RecoverPerHour)
end

--- A stable number in -1..1 for an item on a given day (so prices differ day to day without any randomness to reroll).
local function swing(item)
    local h = 0
    for i = 1, #item do h = (h * 31 + item:byte(i)) % 1000003 end
    h = (h + math.floor(os.time() / 86400) * 7919) % 1000003
    return (h % 2001) / 1000 - 1
end

--- The multiplier on an item's base price right now.
function M.mult(item)
    if not cfg().Enabled then return 1.0 end
    local drop = math.max(cfg().MinMult, 1 - current(item) * cfg().Impact)
    return drop * (1 + swing(item) * cfg().DailySwing)
end

function M.price(item, base) return math.floor(base * M.mult(item)) end

--- Selling `units` of an item raises its pressure.
function M.record(item, units)
    if not cfg().Enabled or units <= 0 then return end
    M.pressure[item] = current(item) + units
    M.at[item] = os.time()
    MySQL.update('INSERT INTO veyl_prod_market (item, pressure, updated_at) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE pressure = VALUES(pressure), updated_at = VALUES(updated_at)',
        { item, M.pressure[item], M.at[item] })
end

--- What the pages show for an item: the multiplier and a plain word for it.
function M.info(item)
    local m = M.mult(item)
    local word = m >= 1.04 and 'high' or (m <= 0.85 and 'low' or 'steady')
    return { mult = math.floor(m * 100 + 0.5) / 100, trend = word }
end
