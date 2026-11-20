-- vlib.callback (client side).
--   local a, b = vlib.callback.await('myresource:action', { timeoutMs = 10000 }, ...)   -- yields
--   vlib.callback('myresource:action', { timeoutMs }, function(a, b) end, ...)           -- callback form
-- On failure (timeout, busy, rate limit, handler error) await returns nil, errCode... as `false, code`
-- through vlib.callback.awaitResult. timeoutMs (network wait) and a retrigger delay are separate concepts.

local RES = GetCurrentResourceName()
local pending = {}
local seq = 0

RegisterNetEvent('vlib:cbr', function(reqId, ok, packed)
    local p = pending[reqId]
    if not p then return end -- late, duplicate or someone else's response
    pending[reqId] = nil
    p:resolve({ ok = ok, packed = packed })
end)

local function request(name, opts, ...)
    seq = seq + 1
    local reqId = ('%s:%d:%d'):format(RES, GetGameTimer(), seq)
    local p = promise.new()
    pending[reqId] = p
    TriggerServerEvent('vlib:cb:' .. name, reqId, ...)
    local timeout = math.max(500, math.min(tonumber(opts and opts.timeoutMs) or 10000, 120000))
    SetTimeout(timeout, function()
        if pending[reqId] then
            pending[reqId] = nil
            p:resolve({ ok = false, packed = { n = 1, 'TIMEOUT' } })
        end
    end)
    return Citizen.Await(p)
end

local M = {}

--- Returns ok:boolean, then the handler's values (ok) or an error code (not ok).
function M.awaitResult(name, opts, ...)
    local r = request(name, opts, ...)
    local packed = r.packed or { n = 0 }
    return r.ok, table.unpack(packed, 1, packed.n or #packed)
end

--- Returns the handler's values, or nil (and logs) on failure.
function M.await(name, opts, ...)
    local r = request(name, opts, ...)
    local packed = r.packed or { n = 0 }
    if not r.ok then
        print(('^3[vlib] callback %s failed: %s^7'):format(name, tostring(packed[1])))
        return nil
    end
    return table.unpack(packed, 1, packed.n or #packed)
end

--- Cancels every pending request of this resource (logout, resource shutdown).
function M.cancelAll(reason)
    for reqId, p in pairs(pending) do
        pending[reqId] = nil
        p:resolve({ ok = false, packed = { n = 1, reason or 'CANCELLED' } })
    end
end

AddEventHandler('onResourceStop', function(res) if res == RES then M.cancelAll('RESOURCE_STOPPED') end end)

return setmetatable(M, {
    __call = function(_, name, opts, cb, ...)
        local args = table.pack(...)
        CreateThread(function()
            local r = request(name, opts, table.unpack(args, 1, args.n))
            if r.ok and cb then cb(table.unpack(r.packed, 1, r.packed.n or #r.packed)) end
        end)
    end,
})
