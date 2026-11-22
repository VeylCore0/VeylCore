-- Phone 2.0, phase 1 (server): Maps (saved places, shared live location), Services (requests and on-duty queue),
-- Mail (inbox + SendMail export for other resources) and Voicemail.

local C = PhoneConfig

local function session(src)
    local s = Phone.Session(src)
    if not s then return nil, Veyl.Err('NO_SESSION', 'Open your phone first') end
    return s
end

local function clean(s, max) return Phone.Clean(s, max) end
local function cidByNumber(number)
    if type(number) ~= 'string' then return nil end
    number = number:gsub('%D', '')
    return MySQL.scalar.await('SELECT citizenid FROM veyl_phone_accounts WHERE number = ?', { number })
end

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
-- Maps
---------------------------------------------------------------------------
Veyl.RegisterCallback('mapsData', function(src, citizenid)
    local _, err = session(src)
    if err then return err end
    local saved = MySQL.query.await('SELECT id, label, x, y FROM veyl_phone_places WHERE citizenid = ? ORDER BY label', { citizenid }) or {}
    local shared = MySQL.query.await([[SELECT id, from_name, x, y, live, UNIX_TIMESTAMP(expires_at) AS expires FROM veyl_phone_shared_locations
        WHERE to_cid = ? AND expires_at > NOW() ORDER BY id DESC LIMIT 20]], { citizenid }) or {}
    -- Live shares follow the sender while they are online.
    for _, sh in ipairs(shared) do
        if sh.live == 1 then
            local fromCid = MySQL.scalar.await('SELECT from_cid FROM veyl_phone_shared_locations WHERE id = ?', { sh.id })
            local fsrc = fromCid and exports.veyl_core:GetSourceByCitizenId(fromCid)
            local pc = fsrc and Veyl.GetPlayerCoords(fsrc)
            if pc then sh.x, sh.y = pc.x, pc.y end
        end
    end
    return Veyl.Ok({ saved = saved, shared = shared, places = C.MapPlaces or {}, shareMinutes = C.ShareMinutes })
end, { cooldown = 500 })

Veyl.RegisterCallback('placeSave', function(src, citizenid, label)
    local _, err = session(src)
    if err then return err end
    label = clean(label, 40)
    if not label or #label < 1 then return Veyl.Err('INVALID_INPUT', 'Name the place') end
    if (MySQL.scalar.await('SELECT COUNT(*) FROM veyl_phone_places WHERE citizenid = ?', { citizenid }) or 0) >= 50 then
        return Veyl.Err('LIMIT', 'You can save 50 places')
    end
    local pc = Veyl.GetPlayerCoords(src)
    if not pc then return Veyl.Err('INTERNAL', 'No position') end
    MySQL.insert.await('INSERT INTO veyl_phone_places (citizenid, label, x, y, z) VALUES (?, ?, ?, ?, ?)', { citizenid, label, pc.x, pc.y, pc.z })
    return Veyl.Ok(nil, 'Place saved')
end, { cooldown = 1000 })

Veyl.RegisterCallback('placeDelete', function(src, citizenid, id)
    local _, err = session(src)
    if err then return err end
    MySQL.update.await('DELETE FROM veyl_phone_places WHERE id = ? AND citizenid = ?', { tonumber(id) or 0, citizenid })
    return Veyl.Ok()
end, { cooldown = 300 })

--- shareLocation(number, minutes, live)
Veyl.RegisterCallback('shareLocation', function(src, citizenid, number, minutes, live)
    local s, err = session(src)
    if err then return err end
    local ok = false
    for _, m in ipairs(C.ShareMinutes) do if tonumber(minutes) == m then ok = true end end
    if not ok then return Veyl.Err('INVALID_INPUT', 'Choose how long') end
    local to = cidByNumber(number)
    if not to then return Veyl.Err('NOT_FOUND', 'No phone with that number') end
    if to == citizenid then return Veyl.Err('INVALID_INPUT', 'That is your own number') end
    local pc = Veyl.GetPlayerCoords(src)
    MySQL.insert.await([[INSERT INTO veyl_phone_shared_locations (from_cid, from_name, to_cid, x, y, live, expires_at)
        VALUES (?, ?, ?, ?, ?, ?, NOW() + INTERVAL ? MINUTE)]], { citizenid, s.name or s.number, to, pc.x, pc.y, live == true and 1 or 0, tonumber(minutes) })
    Notify.Send(to, { app = 'maps', title = 'Location shared', body = ('%s shared %s location with you'):format(s.name or s.number, live == true and 'their live' or 'a'), route = 'maps' })
    return Veyl.Ok(nil, ('Shared for %d min'):format(minutes))
end, { cooldown = 3000 })

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

---------------------------------------------------------------------------
-- Mail
---------------------------------------------------------------------------
--- exports.veyl_phone:SendMail(citizenid, sender, subject, body): works for offline characters too.
local function sendMail(citizenid, sender, subject, body)
    if type(citizenid) ~= 'string' then return false end
    sender, subject, body = clean(sender, 64) or 'City of Los Santos', clean(subject, 120) or '(no subject)', tostring(body or ''):sub(1, 4000)
    MySQL.insert.await('INSERT INTO veyl_phone_mail (citizenid, sender, subject, body) VALUES (?, ?, ?, ?)', { citizenid, sender, subject, body })
    MySQL.update('DELETE FROM veyl_phone_mail WHERE citizenid = ? AND id NOT IN (SELECT id FROM (SELECT id FROM veyl_phone_mail WHERE citizenid = ? ORDER BY id DESC LIMIT ?) t)',
        { citizenid, citizenid, C.Mail.Max })
    Notify.Send(citizenid, { app = 'mail', title = sender, body = subject, route = 'mail' })
    return true
end
exports('SendMail', sendMail)

Veyl.RegisterCallback('mailList', function(src, citizenid)
    local _, err = session(src)
    if err then return err end
    return Veyl.Ok(MySQL.query.await([[SELECT id, sender, subject, body, is_read, UNIX_TIMESTAMP(created_at) AS at FROM veyl_phone_mail
        WHERE citizenid = ? ORDER BY id DESC LIMIT ?]], { citizenid, C.Mail.Max }) or {})
end, { cooldown = 300 })

Veyl.RegisterCallback('mailRead', function(src, citizenid, id)
    local _, err = session(src)
    if err then return err end
    MySQL.update.await('UPDATE veyl_phone_mail SET is_read = 1 WHERE id = ? AND citizenid = ?', { tonumber(id) or 0, citizenid })
    return Veyl.Ok()
end, { cooldown = 100 })

Veyl.RegisterCallback('mailDelete', function(src, citizenid, id)
    local _, err = session(src)
    if err then return err end
    MySQL.update.await('DELETE FROM veyl_phone_mail WHERE id = ? AND citizenid = ?', { tonumber(id) or 0, citizenid })
    return Veyl.Ok()
end, { cooldown = 200 })

---------------------------------------------------------------------------
-- Voicemail
---------------------------------------------------------------------------
Veyl.RegisterCallback('voicemailList', function(src, citizenid)
    local _, err = session(src)
    if err then return err end
    return Veyl.Ok(MySQL.query.await([[SELECT id, from_number, from_name, body, is_read, UNIX_TIMESTAMP(created_at) AS at FROM veyl_phone_voicemail
        WHERE citizenid = ? ORDER BY id DESC LIMIT ?]], { citizenid, C.Voicemail.Max }) or {})
end, { cooldown = 300 })

Veyl.RegisterCallback('voicemailLeave', function(src, citizenid, number, body)
    local s, err = session(src)
    if err then return err end
    local to = cidByNumber(number)
    if not to then return Veyl.Err('NOT_FOUND', 'No phone with that number') end
    body = clean(body, C.Voicemail.Length)
    if not body or #body < 2 then return Veyl.Err('INVALID_INPUT', 'Say something') end
    local blocked = MySQL.scalar.await('SELECT 1 FROM veyl_phone_blocks WHERE owner_cid = ? AND number = ?', { to, s.number })
    if blocked then return Veyl.Ok(nil, 'Voicemail left') end -- silently dropped for blocked callers
    MySQL.insert.await('INSERT INTO veyl_phone_voicemail (citizenid, from_number, from_name, body) VALUES (?, ?, ?, ?)', { to, s.number, s.name, body })
    Notify.Send(to, { app = 'voicemail', title = 'New voicemail', body = ('From %s'):format(s.name or s.number), route = 'voicemail' })
    return Veyl.Ok(nil, 'Voicemail left')
end, { cooldown = 3000 })

Veyl.RegisterCallback('voicemailRead', function(src, citizenid, id)
    local _, err = session(src)
    if err then return err end
    MySQL.update.await('UPDATE veyl_phone_voicemail SET is_read = 1 WHERE id = ? AND citizenid = ?', { tonumber(id) or 0, citizenid })
    return Veyl.Ok()
end, { cooldown = 100 })

Veyl.RegisterCallback('voicemailDelete', function(src, citizenid, id)
    local _, err = session(src)
    if err then return err end
    MySQL.update.await('DELETE FROM veyl_phone_voicemail WHERE id = ? AND citizenid = ?', { tonumber(id) or 0, citizenid })
    return Veyl.Ok()
end, { cooldown = 200 })
