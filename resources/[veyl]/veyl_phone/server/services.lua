-- Services: ask police, EMS, mechanics, taxis and businesses for help; the on-duty queue.

local C = PhoneConfig
local function session(src)
    local s = Phone.Session(src)
    if not s then return nil, Veyl.Err('NO_SESSION', 'Open your phone first') end
    return s
end
local function core(name, ...) return Veyl.Await('veyl_core', name, 15000, ...) end
local function cidByNumber(number) return Phone.CidByNumber(number) end
local function clean(s, max) return PhoneUtil.Clean(s, max) end
local function charName(pd) return pd and ('%s %s'):format(pd.charinfo.firstname or '', pd.charinfo.lastname or '') or 'Unknown' end
local seq = 0
local function op(kind, cid) seq = seq + 1 return ('phone:%s:%s:%d:%d'):format(kind, cid, os.time(), seq) end
local function onDutyIn(jobs)
    local list = {}
    for _, s in ipairs(GetPlayers()) do
        s = tonumber(s)
        local pd = Veyl.GetPlayerData(s)
        if pd and pd.job.onduty then for _, j in ipairs(jobs) do if pd.job.name == j then list[#list + 1] = s break end end end
    end
    return list
end
local services = {}
for _, sv in ipairs(C.Services or {}) do services[sv.id] = sv end

---------------------------------------------------------------------------
-- Services
---------------------------------------------------------------------------
local lastRequest = {}

local function myService(src)
    local pd = Veyl.GetPlayerData(src)
    if not pd or not pd.job.onduty then return nil end
    for id, sv in pairs(services) do for _, j in ipairs(sv.jobs) do if pd.job.name == j then return id end end end
    return nil
end

Veyl.RegisterCallback('servicesData', function(src, citizenid)
    local _, err = session(src)
    if err then return err end
    local list = {}
    for _, sv in ipairs(C.Services or {}) do
        list[#list + 1] = { id = sv.id, label = sv.label, icon = sv.icon, onDuty = #onDutyIn(sv.jobs) }
    end
    local mine = MySQL.query.await([[SELECT id, service, message, status, taken_by, UNIX_TIMESTAMP(created_at) AS at FROM veyl_phone_service_requests
        WHERE citizenid = ? AND status <> 'closed' AND created_at > NOW() - INTERVAL 2 HOUR ORDER BY id DESC LIMIT 10]], { citizenid }) or {}
    local duty = myService(src)
    local queue = duty and MySQL.query.await([[SELECT id, caller_name, caller_number, message, status, taken_by, x, y, UNIX_TIMESTAMP(created_at) AS at
        FROM veyl_phone_service_requests WHERE service = ? AND status <> 'closed' AND created_at > NOW() - INTERVAL 2 HOUR ORDER BY id DESC LIMIT 30]], { duty }) or nil
    return Veyl.Ok({ services = list, mine = mine, duty = duty, queue = queue })
end, { cooldown = 500 })

Veyl.RegisterCallback('serviceRequest', function(src, citizenid, id, message)
    local s, err = session(src)
    if err then return err end
    local sv = services[id]
    if not sv then return Veyl.Err('NOT_FOUND', 'Unknown service') end
    message = clean(message, 240)
    if not message or #message < 3 then return Veyl.Err('INVALID_INPUT', 'Say what you need') end
    local wait = (lastRequest[citizenid] or 0) + (C.ServiceCooldownSeconds or 60) - os.time()
    if wait > 0 then return Veyl.Err('RATE_LIMITED', ('Wait %ds before another request'):format(wait)) end
    lastRequest[citizenid] = os.time()
    local pc = Veyl.GetPlayerCoords(src)
    local rid = MySQL.insert.await([[INSERT INTO veyl_phone_service_requests (service, citizenid, caller_name, caller_number, message, x, y)
        VALUES (?, ?, ?, ?, ?, ?, ?)]], { id, citizenid, s.name or 'Caller', s.number, message, pc.x, pc.y })
    local staff = onDutyIn(sv.jobs)
    if sv.dispatch and GetResourceState('veyl_dispatch') == 'started' then
        pcall(function()
            exports.veyl_dispatch:Alert({ services = { sv.dispatch }, code = sv.dispatch == 'ems' and '10-52' or '10-35', title = ('%s request (phone)'):format(sv.label),
                priority = 2, coords = pc, street = Player(src).state.street, message = message, caller = { name = s.name, phone = s.number } })
        end)
    end
    for _, m in ipairs(staff) do
        local mcid = Veyl.GetCitizenId(m)
        if mcid then Notify.Send(mcid, { app = 'services', title = ('%s request #%d'):format(sv.label, rid), body = message, route = 'services' }) end
    end
    return Veyl.Ok(nil, #staff > 0 and ('Sent to %d on duty'):format(#staff) or 'Sent. Nobody is on duty right now; it stays in the queue.')
end, { cooldown = 1500 })

Veyl.RegisterCallback('serviceTake', function(src, _, rid)
    local _, err = session(src)
    if err then return err end
    local duty = myService(src)
    local r = duty and MySQL.single.await("SELECT * FROM veyl_phone_service_requests WHERE id = ? AND service = ? AND status = 'open'", { tonumber(rid) or 0, duty })
    if not r then return Veyl.Err('NOT_FOUND', 'Already taken or closed') end
    local pd = Veyl.GetPlayerData(src)
    local name = ('%s %s'):format(pd.charinfo.firstname or '', pd.charinfo.lastname or '')
    MySQL.update.await("UPDATE veyl_phone_service_requests SET status = 'taken', taken_by = ? WHERE id = ?", { name, r.id })
    Notify.Send(r.citizenid, { app = 'services', title = services[duty].label, body = ('%s is on the way'):format(name), route = 'services' })
    return Veyl.Ok({ x = r.x, y = r.y }, 'GPS set to the caller')
end, { cooldown = 800 })

Veyl.RegisterCallback('serviceClose', function(src, citizenid, rid)
    local _, err = session(src)
    if err then return err end
    local duty = myService(src)
    local n = MySQL.update.await([[UPDATE veyl_phone_service_requests SET status = 'closed' WHERE id = ? AND (citizenid = ? OR service = ?)]],
        { tonumber(rid) or 0, citizenid, duty or '' })
    return n == 1 and Veyl.Ok(nil, 'Closed') or Veyl.Err('NOT_FOUND', 'Not found')
end, { cooldown = 500 })
