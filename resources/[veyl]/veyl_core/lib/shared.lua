-- VeylCore shared library. Import with:  shared_script '@veyl_core/lib/shared.lua'
Veyl = Veyl or {}
Veyl.ResourceName = GetCurrentResourceName()

--- Documented error codes used in every { ok, code, message, data } response.
Veyl.Codes = {
    OK = 'OK',
    NOT_READY = 'NOT_READY',
    NO_CHARACTER = 'NO_CHARACTER',
    NO_PERMISSION = 'NO_PERMISSION',
    INVALID_INPUT = 'INVALID_INPUT',
    NOT_FOUND = 'NOT_FOUND',
    TOO_FAR = 'TOO_FAR',
    RATE_LIMITED = 'RATE_LIMITED',
    BUSY = 'BUSY',
    TIMEOUT = 'TIMEOUT',
    INSUFFICIENT_FUNDS = 'INSUFFICIENT_FUNDS',
    INVENTORY_FULL = 'INVENTORY_FULL',
    NOT_ENOUGH_ITEMS = 'NOT_ENOUGH_ITEMS',
    DUPLICATE_OPERATION = 'DUPLICATE_OPERATION',
    INVALID_STATE = 'INVALID_STATE',
    SERVICE_UNAVAILABLE = 'SERVICE_UNAVAILABLE',
    DATABASE_ERROR = 'DATABASE_ERROR',
    INTERNAL = 'INTERNAL',
}

function Veyl.Ok(data, message)
    return { ok = true, code = 'OK', message = message, data = data }
end

function Veyl.Err(code, message, data)
    return { ok = false, code = code or 'INTERNAL', message = message, data = data }
end

local idCounter = 0
--- Unique-enough identifier for operations/requests (resource + time + counter + random).
function Veyl.NewId(prefix)
    idCounter = idCounter + 1
    local t = GetGameTimer and GetGameTimer() or 0
    local wall = os and os.time and os.time() or 0
    return ('%s%x%x%x%04x'):format(prefix and (prefix .. ':') or '', wall, t, idCounter, math.random(0, 0xffff))
end

--- Validation helpers for anything a client sends.
Veyl.Validate = {}

function Veyl.Validate.int(v, min, max)
    if type(v) ~= 'number' or v ~= v or v % 1 ~= 0 then return false end
    if min and v < min then return false end
    if max and v > max then return false end
    return true
end

function Veyl.Validate.str(v, minLen, maxLen, pattern)
    if type(v) ~= 'string' then return false end
    local len = #v
    if minLen and len < minLen then return false end
    if maxLen and len > maxLen then return false end
    if pattern and not v:match(pattern) then return false end
    return true
end

function Veyl.Validate.oneOf(v, list)
    for i = 1, #list do
        if list[i] == v then return true end
    end
    return false
end

function Veyl.Distance(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--- Call an "async export" (export whose last parameter is a callback) and wait for the result.
--- Every VeylCore export that touches the database or UI uses this convention, so cross-resource
--- calls never yield inside another resource's stack.
function Veyl.Await(resource, exportName, timeoutMs, ...)
    if GetResourceState(resource) ~= 'started' then
        return Veyl.Err('SERVICE_UNAVAILABLE', resource .. ' is not started')
    end
    local p = promise.new()
    local done = false
    local function finish(result)
        if done then return end
        done = true
        p:resolve(result)
    end
    local args = table.pack(...)
    args.n = args.n + 1
    args[args.n] = function(result) finish(result) end
    local ok, err = pcall(function()
        local target = exports[resource]
        target[exportName](target, table.unpack(args, 1, args.n))
    end)
    if not ok then
        return Veyl.Err('SERVICE_UNAVAILABLE', ('%s:%s failed: %s'):format(resource, exportName, tostring(err)))
    end
    if timeoutMs and timeoutMs > 0 then
        SetTimeout(timeoutMs, function()
            finish(Veyl.Err('TIMEOUT', resource .. ':' .. exportName .. ' timed out'))
        end)
    end
    return Citizen.Await(p)
end

--- Register an async export. fn(...) runs in its own thread; its return value goes to the caller's callback.
function Veyl.AsyncExport(name, fn)
    exports(name, function(...)
        local args = table.pack(...)
        local cb = args[args.n]
        if type(cb) ~= 'function' and type(cb) ~= 'table' then
            error(('export %s requires a callback as its last argument (use Veyl.Await)'):format(name))
        end
        Citizen.CreateThread(function()
            local ok, result = pcall(fn, table.unpack(args, 1, args.n - 1))
            if not ok then
                print(('^1[%s] export %s error: %s^7'):format(Veyl.ResourceName, name, tostring(result)))
                result = Veyl.Err('INTERNAL', 'internal error')
            end
            cb(result)
        end)
    end)
end

--- Readiness flags published through GlobalState so dependents can report a clear missing service.
function Veyl.IsServiceReady(resource)
    return GetResourceState(resource) == 'started' and GlobalState['veyl:ready:' .. resource] == true
end

function Veyl.WaitForService(resource, timeoutMs)
    local deadline = GetGameTimer() + (timeoutMs or 15000)
    while not Veyl.IsServiceReady(resource) do
        if GetGameTimer() > deadline then return false end
        Wait(100)
    end
    return true
end

--- Simple cooperative mutex: serialises async work per key inside one resource.
local locks = {}
function Veyl.WithLock(key, fn, ...)
    while locks[key] do Wait(0) end
    locks[key] = true
    local res = table.pack(pcall(fn, ...))
    locks[key] = nil
    if not res[1] then error(res[2], 0) end
    return table.unpack(res, 2, res.n)
end
