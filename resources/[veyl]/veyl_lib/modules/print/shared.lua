-- vlib.print.info/warn/error(...) with a resource prefix. Level via convar `veyl:loglevel` (0 errors .. 2 info).
local RES = GetCurrentResourceName()
local level = GetConvarInt('veyl:loglevel', 2)

local function fmt(...)
    local parts = table.pack(...)
    for i = 1, parts.n do parts[i] = tostring(parts[i]) end
    return table.concat(parts, ' ', 1, parts.n)
end

return {
    error = function(...) print(('^1[%s] %s^7'):format(RES, fmt(...))) end,
    warn = function(...) if level >= 1 then print(('^3[%s] %s^7'):format(RES, fmt(...))) end end,
    info = function(...) if level >= 2 then print(('[%s] %s'):format(RES, fmt(...))) end end,
}
