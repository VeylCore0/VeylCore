-- vlib.callback (server side).
--   vlib.callback.register('myresource:action', function(source, ...) return ... end, { cooldownMs = 250 })
-- Names must start with '<this resource>:' (namespacing, not access control: handlers validate everything).
-- Responses preserve every return value, including nil positions. One in-flight request per player+name.

local RES = GetCurrentResourceName()
local handlers = {}
local lastCall, inflight = {}, {}
local MAX_ARGS = 32

local M = {}

local function reply(src, reqId, ok, packed)
    TriggerClientEvent('vlib:cbr', src, reqId, ok, packed)
end

function M.register(name, handler, opts)
    if type(name) ~= 'string' or name:sub(1, #RES + 1) ~= RES .. ':' then
        error(('vlib.callback.register: "%s" must be namespaced as "%s:<name>"'):format(tostring(name), RES), 2)
    end
    if handlers[name] then error(('vlib.callback.register: %s already registered'):format(name), 2) end
    opts = opts or {}
    handlers[name] = true
    local cooldown = tonumber(opts.cooldownMs) or 0
    RegisterNetEvent('vlib:cb:' .. name, function(reqId, ...)
        local src = source
        if type(reqId) ~= 'string' or #reqId > 64 then return end
        if select('#', ...) > MAX_ARGS then return reply(src, reqId, false, { n = 1, 'TOO_MANY_ARGUMENTS' }) end
        local key = src .. '|' .. name
        if inflight[key] then return reply(src, reqId, false, { n = 1, 'BUSY' }) end
        local now = GetGameTimer()
        if cooldown > 0 and lastCall[key] and now - lastCall[key] < cooldown then
            return reply(src, reqId, false, { n = 1, 'RATE_LIMITED' })
        end
        lastCall[key] = now
        inflight[key] = true
        local results = table.pack(pcall(handler, src, ...))
        inflight[key] = nil
        if not results[1] then
            print(('^1[vlib] callback %s failed: %s^7'):format(name, tostring(results[2])))
            return reply(src, reqId, false, { n = 1, 'INTERNAL' })
        end
        reply(src, reqId, true, table.pack(table.unpack(results, 2, results.n)))
    end)
end

AddEventHandler('playerDropped', function()
    local prefix = tostring(source) .. '|'
    for k in pairs(lastCall) do if k:sub(1, #prefix) == prefix then lastCall[k] = nil end end
    for k in pairs(inflight) do if k:sub(1, #prefix) == prefix then inflight[k] = nil end end
end)

return M
