-- vlib.validate: bounded input checks for anything that crosses a network or NUI boundary.
local M = {}

function M.int(v, min, max)
    if type(v) ~= 'number' or v ~= v or v % 1 ~= 0 then return false end
    return (min == nil or v >= min) and (max == nil or v <= max)
end

function M.str(v, minLen, maxLen, pattern)
    if type(v) ~= 'string' then return false end
    if minLen and #v < minLen then return false end
    if maxLen and #v > maxLen then return false end
    return pattern == nil or v:match(pattern) ~= nil
end

function M.oneOf(v, list)
    for i = 1, #list do if list[i] == v then return true end end
    return false
end

--- Rough size of a JSON-able value, used to cap metadata and payloads.
function M.size(v)
    local ok, s = pcall(json.encode, v)
    return ok and #s or math.huge
end

return M
