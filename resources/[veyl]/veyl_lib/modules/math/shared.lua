-- vlib.math helpers.
local M = {}

function M.clamp(v, min, max) return math.max(min, math.min(max, v)) end

function M.round(v, decimals)
    local m = 10 ^ (decimals or 0)
    return math.floor(v * m + 0.5) / m
end

return M
