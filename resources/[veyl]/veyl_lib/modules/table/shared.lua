-- vlib.table helpers.
local M = {}

function M.deepcopy(v)
    if type(v) ~= 'table' then return v end
    local out = {}
    for k, val in pairs(v) do out[k] = M.deepcopy(val) end
    return out
end

function M.contains(tbl, value)
    for _, v in pairs(tbl) do if v == value then return true end end
    return false
end

--- Deep equality for JSON-like data (used for stack identity of item metadata).
function M.equals(a, b)
    if a == b then return true end
    if type(a) ~= 'table' or type(b) ~= 'table' then return false end
    for k, v in pairs(a) do if not M.equals(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end

function M.count(tbl)
    local n = 0
    for _ in pairs(tbl) do n = n + 1 end
    return n
end

return M
