-- veyl_dispatch server: calls, responders, unit status, panic and public 911 / 311.
--
-- Other resources raise calls with:
--   exports.veyl_dispatch:Alert({ services = { 'police' }, code = '10-90', title = 'Store robbery', message = '...',
--       coords = vector3(...), street = '...', priority = 1 (1 urgent - 3 low), blip = { sprite = 161, colour = 1 } })
-- Calls live in memory for CallLifetimeMinutes; they are not a record (reports belong in the MDT).

local C = DispatchConfig
local calls, callSeq = {}, 0      -- calls[i] = { id, ... } newest last
local units = {}                  -- [src] = { status }
local lastPanic, lastPublic = {}, {}

Veyl.Startup({ 'veyl_core' }, function() return true end)

---------------------------------------------------------------------------
-- Who is on duty for which service
---------------------------------------------------------------------------
local jobService = {}
for name, s in pairs(C.Services) do for _, j in ipairs(s.jobs) do jobService[j] = name end end

local function serviceOf(src)
    local pd = Veyl.GetPlayerData(src)
    if not pd or not pd.job.onduty then return nil end
    return jobService[pd.job.name], pd
end

local function onDuty(service)
    local list = {}
    for _, s in ipairs(GetPlayers()) do
        s = tonumber(s)
        local sv = serviceOf(s)
        if sv and (not service or sv == service) then list[#list + 1] = s end
    end
    return list
end

local function wants(call, service)
    for _, s in ipairs(call.services) do if s == service then return true end end
    return false
end

local function unitName(src, pd)
    pd = pd or Veyl.GetPlayerData(src)
    if not pd then return 'Unknown' end
    local sign = pd.metadata and pd.metadata.callsign
    local name = ('%s. %s'):format((pd.charinfo.firstname or '?'):sub(1, 1), pd.charinfo.lastname or '')
    return (sign and sign ~= '' and sign ~= 'NO CALLSIGN') and ('%s · %s'):format(sign, name) or name
end

---------------------------------------------------------------------------
-- Views sent to units
---------------------------------------------------------------------------
local function callView(c)
    local responders = {}
    for s in pairs(c.responders) do if GetPlayerName(s) then responders[#responders + 1] = unitName(s) end end
    return {
        id = c.id, code = c.code, title = c.title, message = c.message, street = c.street, priority = c.priority,
        x = c.coords.x, y = c.coords.y, z = c.coords.z, at = c.at, services = c.services, responders = responders,
        panic = c.panic or nil, caller = c.caller, blip = c.blip,
    }
end

local function unitsView()
    local out = {}
    for _, s in ipairs(onDuty()) do
        local sv, pd = serviceOf(s)
        local u = units[s] or { status = 'available' }
        units[s] = u
        out[#out + 1] = { id = s, service = sv, name = unitName(s, pd), grade = pd.job.grade and pd.job.grade.name or nil, status = u.status }
    end
    table.sort(out, function(a, b) return a.service == b.service and a.name < b.name or a.service < b.service end)
    return out
end

local function stateFor(src)
    local sv = serviceOf(src)
    if not sv then return nil end
    local list = {}
    for i = #calls, 1, -1 do if wants(calls[i], sv) then list[#list + 1] = callView(calls[i]) end end
    return { service = sv, calls = list, units = unitsView(), me = { id = src, status = (units[src] or {}).status or 'available' },
        statuses = C.Statuses, serviceLabels = (function() local m = {} for k, s in pairs(C.Services) do m[k] = s.label end return m end)() }
end

-- Coalesced: many changes in one tick send one update.
local syncQueued = false
local function sync()
    if syncQueued then return end
    syncQueued = true
    SetTimeout(150, function()
        syncQueued = false
        for _, s in ipairs(onDuty()) do TriggerClientEvent('veyl_dispatch:sync', s, stateFor(s)) end
    end)
end

---------------------------------------------------------------------------
-- Calls
---------------------------------------------------------------------------
local function prune()
    local cutoff = os.time() - C.CallLifetimeMinutes * 60
    while #calls > 0 and (calls[1].at < cutoff or #calls > C.MaxCalls) do table.remove(calls, 1) end
end

--- Alert(data) -> call id. See the header for the fields.
local function alert(data)
    if type(data) ~= 'table' or not data.coords then return nil end
    local services = {}
    for _, s in ipairs(type(data.services) == 'table' and data.services or { 'police' }) do if C.Services[s] then services[#services + 1] = s end end
    if #services == 0 then return nil end
    callSeq = callSeq + 1
    local c = {
        id = callSeq, code = tostring(data.code or '10-00'):sub(1, 12), title = tostring(data.title or 'Call'):sub(1, 60),
        message = data.message and tostring(data.message):sub(1, 240) or nil, street = data.street and tostring(data.street):sub(1, 80) or nil,
        coords = vector3(data.coords.x + 0.0, data.coords.y + 0.0, data.coords.z + 0.0), priority = math.max(1, math.min(3, tonumber(data.priority) or 2)),
        services = services, at = os.time(), responders = {}, panic = data.panic == true, caller = data.caller,
        blip = type(data.blip) == 'table' and { sprite = tonumber(data.blip.sprite), colour = tonumber(data.blip.colour), scale = tonumber(data.blip.scale) } or nil,
    }
    calls[#calls + 1] = c
    prune()
    local view = callView(c)
    for _, s in ipairs(onDuty()) do
        if wants(c, (serviceOf(s))) then TriggerClientEvent('veyl_dispatch:call', s, view, C.PopupSeconds, C.BlipSeconds) end
    end
    sync()
    return c.id
end
exports('Alert', alert)

local function findCall(id)
    id = tonumber(id)
    for _, c in ipairs(calls) do if c.id == id then return c end end
    return nil
end

Veyl.RegisterCallback('state', function(src)
    local st = stateFor(src)
    if not st then return Veyl.Err('NO_PERMISSION', 'You need to be on duty as police or EMS') end
    return Veyl.Ok(st)
end, { cooldown = 300 })

Veyl.RegisterCallback('respond', function(src, _, id)
    local sv = serviceOf(src)
    if not sv then return Veyl.Err('NO_PERMISSION', 'You need to be on duty') end
    local c = id and findCall(id) or nil
    if not id then
        for i = #calls, 1, -1 do if wants(calls[i], sv) then c = calls[i] break end end
    end
    if not c or not wants(c, sv) then return Veyl.Err('NOT_FOUND', 'No call to respond to') end
    c.responders[src] = true
    units[src] = units[src] or {}
    units[src].status = 'enroute'
    sync()
    return Veyl.Ok({ id = c.id, x = c.coords.x, y = c.coords.y, title = c.title }, ('Responding to #%d %s'):format(c.id, c.title))
end, { cooldown = 500 })

Veyl.RegisterCallback('setStatus', function(src, _, status)
    if not serviceOf(src) then return Veyl.Err('NO_PERMISSION', 'You need to be on duty') end
    local ok = false
    for _, s in ipairs(C.Statuses) do if s.id == status then ok = true end end
    if not ok then return Veyl.Err('INVALID_INPUT', 'Unknown status') end
    units[src] = units[src] or {}
    units[src].status = status
    if status == 'available' then for _, c in ipairs(calls) do c.responders[src] = nil end end
    sync()
    return Veyl.Ok(stateFor(src))
end, { cooldown = 300 })

Veyl.RegisterCallback('panic', function(src)
    local sv, pd = serviceOf(src)
    if not sv then return Veyl.Err('NO_PERMISSION', 'You need to be on duty') end
    local wait = (lastPanic[src] or 0) + C.PanicCooldownSeconds - os.time()
    if wait > 0 then return Veyl.Err('RATE_LIMITED', ('Panic button ready in %ds'):format(wait)) end
    lastPanic[src] = os.time()
    local pc = Veyl.GetPlayerCoords(src)
    local services = {}
    for k in pairs(C.Services) do services[#services + 1] = k end
    alert({ services = services, code = '10-99', title = 'PANIC BUTTON', priority = 1, panic = true, coords = pc,
        message = ('%s (%s) pressed their panic button'):format(unitName(src, pd), C.Services[sv].label),
        street = Player(src).state.street, blip = { sprite = 161, colour = 1, scale = 1.4 } })
    Veyl.Audit(src, 'dispatch_panic', {})
    return Veyl.Ok(nil, 'Panic button pressed')
end, { cooldown = 1000 })

---------------------------------------------------------------------------
-- Public calls: /911 <message>, /311 <message>
---------------------------------------------------------------------------
for cmd, def in pairs(C.PublicCalls) do
    RegisterCommand(cmd, function(src, args)
        if src == 0 then return end
        local pd = Veyl.GetPlayerData(src)
        if not pd then return end
        local text = table.concat(args, ' '):gsub('[%c]', ''):sub(1, 200)
        if text == '' then return Veyl.Notify(src, ('Usage: /%s <what is happening>'):format(cmd), 'error') end
        local wait = (lastPublic[src] or 0) + C.PublicCallCooldownSeconds - os.time()
        if wait > 0 then return Veyl.Notify(src, ('You can call again in %ds'):format(wait), 'error') end
        lastPublic[src] = os.time()
        local name = ('%s %s'):format(pd.charinfo.firstname or '', pd.charinfo.lastname or '')
        local id = alert({ services = def.services, code = def.code, title = def.title, priority = def.priority, message = text,
            coords = Veyl.GetPlayerCoords(src), street = Player(src).state.street,
            caller = { name = name, phone = pd.charinfo.phone } })
        local n = 0
        for _, s in ipairs(def.services) do n = n + #onDuty(s) end
        Veyl.Notify(src, n > 0 and ('Your call (#%d) went through. Help is on the way.'):format(id or 0)
            or 'Your call went through, but nobody is on duty right now.', n > 0 and 'success' or 'warning', 7000)
        Veyl.Audit(src, 'dispatch_public_call', { command = cmd, text = text })
    end, false)
end

---------------------------------------------------------------------------
-- /callsign <text>: on-duty units set the callsign shown in dispatch
---------------------------------------------------------------------------
RegisterCommand('callsign', function(src, args)
    if src == 0 or not serviceOf(src) then return Veyl.Notify(src, 'You need to be on duty as police or EMS', 'error') end
    local sign = (args[1] or ''):upper():gsub('[^%w%-]', ''):sub(1, 10)
    if sign == '' then return Veyl.Notify(src, 'Usage: /callsign <e.g. 1-ADAM-12>', 'error') end
    exports.veyl_core:SetMetadata(src, 'callsign', sign)
    Veyl.Notify(src, 'Callsign set to ' .. sign, 'success')
    sync()
end, false)

---------------------------------------------------------------------------
-- Unit positions (blips) and housekeeping
---------------------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(C.UnitBlipIntervalMs)
        if C.UnitBlips then
            local list = onDuty()
            if #list > 0 then
                local pos = {}
                for _, s in ipairs(list) do
                    local pc = Veyl.GetPlayerCoords(s)
                    if pc then pos[#pos + 1] = { id = s, service = serviceOf(s), x = pc.x, y = pc.y, z = pc.z, name = unitName(s), status = (units[s] or {}).status } end
                end
                for _, s in ipairs(list) do TriggerClientEvent('veyl_dispatch:units', s, pos) end
            end
        end
    end
end)

-- Duty changes: refresh everyone's panel; a unit going off duty loses its blip and its status.
AddEventHandler('VeylCore:Server:OnJobUpdate', function(src) if not serviceOf(src) then units[src] = nil TriggerClientEvent('veyl_dispatch:sync', src, nil) end sync() end)
AddEventHandler('VeylCore:Server:SetDuty', function(src) if not serviceOf(src) then units[src] = nil TriggerClientEvent('veyl_dispatch:sync', src, nil) end sync() end)
AddEventHandler('VeylCore:Server:OnPlayerUnload', function(src) units[src] = nil sync() end)
AddEventHandler('playerDropped', function()
    local src = source
    units[src], lastPanic[src], lastPublic[src] = nil, nil, nil
    for _, c in ipairs(calls) do c.responders[src] = nil end
    sync()
end)

-- Street names come from clients (the server has no street data); used for panic and public calls.
RegisterNetEvent('veyl_dispatch:street', function(street)
    if type(street) == 'string' then Player(source).state:set('street', street:sub(1, 80), false) end
end)

--- GetUnits(service?) -> on-duty units with service, name (callsign), grade and status (used by the MDT roster).
exports('GetUnits', function(service)
    local out = {}
    for _, u in ipairs(unitsView()) do if not service or u.service == service then out[#out + 1] = u end end
    return out
end)
