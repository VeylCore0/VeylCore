-- veyl_admin menu server: everything the staff menu can do. Every callback needs the 'admin' permission (checked here on each request, not
-- once when the menu opens), every action is audited, and anything that changes a player or the server goes through the same durable
-- exports the commands use. The page and the client only ask; nothing here trusts them.

local C = AdminConfig
local startedAt = os.time()

local function opts(cooldown) return { permission = 'admin', requireCharacter = false, cooldown = cooldown or 250 } end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function str(v, max)
    if type(v) ~= 'string' then return nil end
    v = v:gsub('^%s+', ''):gsub('%s+$', '')
    if #v == 0 or #v > (max or 200) then return nil end
    return v
end
local function int(v, lo, hi)
    v = tonumber(v)
    if not v or v ~= math.floor(v) or v < lo or v > hi then return nil end
    return math.floor(v)
end
local function online(id)
    id = tonumber(id)
    if not id or id ~= math.floor(id) or not GetPlayerName(id) then return nil end
    return id
end
local function staffName(src) return GetPlayerName(src) or ('#' .. tostring(src)) end
local function ident(id, kind)
    local v = GetPlayerIdentifierByType(id, kind)
    return v
end
local function sessionOf(id)
    for _, s in ipairs(exports.veyl_core:GetSessions()) do if s.source == id then return s end end
end
local function audit(src, action, data) Veyl.Audit(src, 'admin_' .. action, data) end

---------------------------------------------------------------------------
-- Bans and warnings (stored by licence so a new name does not help)
---------------------------------------------------------------------------
local function banRow(license)
    if not license then return nil end
    return MySQL.single.await('SELECT id, name, reason, banned_by, UNIX_TIMESTAMP(expires_at) AS expires FROM veyl_admin_bans WHERE license = ? AND (expires_at IS NULL OR expires_at > NOW()) ORDER BY id DESC LIMIT 1', { license })
end

AddEventHandler('playerConnecting', function(name, _, deferrals)
    local src = source
    deferrals.defer()
    local license = ident(src, 'license')
    local ok, row = pcall(banRow, license)
    if ok and row then
        local until_ = row.expires and os.date('%Y-%m-%d %H:%M', row.expires) or 'permanent'
        return deferrals.done(('You are banned. Reason: %s (%s). Ban #%d.'):format(row.reason, until_, row.id))
    end
    deferrals.done()
end)

---------------------------------------------------------------------------
-- Reading
---------------------------------------------------------------------------
local function reportCount() return MySQL.scalar.await("SELECT COUNT(*) FROM veyl_reports WHERE status = 'open'") or 0 end

Veyl.RegisterCallback('overview', function(src)
    local sessions = exports.veyl_core:GetSessions()
    local spawned = 0
    for _, s in ipairs(sessions) do if s.citizenid then spawned = spawned + 1 end end
    local running = 0
    for i = 0, GetNumResources() - 1 do if GetResourceState(GetResourceByFindIndex(i)) == 'started' then running = running + 1 end end
    local world = GlobalState.veylWorld or {}
    return Veyl.Ok({
        players = #sessions, inCity = spawned, max = GetConvarInt('sv_maxclients', 48), uptime = os.time() - startedAt,
        resources = running, reports = reportCount(),
        bans = MySQL.scalar.await('SELECT COUNT(*) FROM veyl_admin_bans WHERE expires_at IS NULL OR expires_at > NOW()') or 0,
        world = { hour = world.hour, minute = world.minute, weather = world.weather, frozen = world.frozen },
        me = { id = src, name = staffName(src) },
        weather = C.Weather, jobs = (function() local out = {} for k, v in pairs(exports.veyl_core:GetJobs() or {}) do out[#out + 1] = { id = k, label = v.label or k } end table.sort(out, function(a, b) return a.id < b.id end) return out end)(),
        gangs = (function() local out = {} for k, v in pairs(exports.veyl_core:GetGangs() or {}) do out[#out + 1] = { id = k, label = v.label or k } end table.sort(out, function(a, b) return a.id < b.id end) return out end)(),
    })
end, opts(500))

Veyl.RegisterCallback('players', function()
    local out = {}
    for _, s in ipairs(exports.veyl_core:GetSessions()) do
        local pd = s.citizenid and exports.veyl_core:GetPlayerData(s.source) or nil
        out[#out + 1] = { id = s.source, name = s.name, character = s.characterName, citizenid = s.citizenid, ping = GetPlayerPing(s.source),
            job = pd and pd.job and (pd.job.label or pd.job.name) or nil, staff = Veyl.HasPermission(s.source, 'admin') }
    end
    table.sort(out, function(a, b) return a.id < b.id end)
    return Veyl.Ok(out)
end, opts(500))

Veyl.RegisterCallback('playerInfo', function(src, _, id)
    id = online(id)
    if not id then return Veyl.Err('NOT_FOUND', 'That player is not online') end
    local s = sessionOf(id)
    local pd = s and s.citizenid and exports.veyl_core:GetPlayerData(id) or nil
    local ped = GetPlayerPed(id)
    local c = ped ~= 0 and GetEntityCoords(ped) or nil
    local items = {}
    if s and s.citizenid then
        for _, it in pairs(exports.veyl_inventory:GetInventoryItems(id) or {}) do items[#items + 1] = { name = it.name, label = it.label, count = it.count } end
        table.sort(items, function(a, b) return (a.label or a.name) < (b.label or b.name) end)
    end
    local warnings = s and s.citizenid and MySQL.query.await('SELECT id, reason, issued_by, DATE_FORMAT(created_at, "%Y-%m-%d %H:%i") AS at FROM veyl_admin_warnings WHERE citizenid = ? ORDER BY id DESC LIMIT 10', { s.citizenid }) or {}
    audit(src, 'inspect', { target = id })
    return Veyl.Ok({
        id = id, name = GetPlayerName(id), character = s and s.characterName, citizenid = s and s.citizenid, ping = GetPlayerPing(id),
        identifiers = { license = ident(id, 'license'), discord = ident(id, 'discord'), fivem = ident(id, 'fivem'), steam = ident(id, 'steam') },
        money = pd and pd.money or nil, job = pd and pd.job or nil, gang = pd and pd.gang or nil,
        coords = c and { x = c.x, y = c.y, z = c.z } or nil, health = ped ~= 0 and GetEntityHealth(ped) or nil, armor = ped ~= 0 and GetPedArmour(ped) or nil,
        items = items, warnings = warnings, staff = Veyl.HasPermission(id, 'admin'),
    })
end, opts(300))

Veyl.RegisterCallback('reports', function()
    return Veyl.Ok(MySQL.query.await([[SELECT id, player_name AS name, message, status, handled_by AS handler, DATE_FORMAT(created_at, '%Y-%m-%d %H:%i') AS at
        FROM veyl_reports ORDER BY (status = 'open') DESC, id DESC LIMIT 60]]) or {})
end, opts(500))

Veyl.RegisterCallback('closeReport', function(src, _, id)
    id = int(id, 1, 2147483647)
    if not id then return Veyl.Err('INVALID_INPUT', 'Bad report') end
    local n = MySQL.update.await("UPDATE veyl_reports SET status = 'closed', handled_by = ? WHERE id = ? AND status = 'open'", { staffName(src), id })
    audit(src, 'report_closed', { report = id })
    return n > 0 and Veyl.Ok(nil, ('Report #%d closed'):format(id)) or Veyl.Err('NOT_FOUND', 'Already closed')
end, opts(300))

Veyl.RegisterCallback('logs', function(_, _, filter)
    filter = str(filter, 40)
    local rows
    if filter then
        rows = MySQL.query.await("SELECT id, resource, action, citizenid, LEFT(data, 400) AS data, DATE_FORMAT(created_at, '%m-%d %H:%i:%s') AS at FROM veyl_audit WHERE action LIKE ? OR citizenid = ? OR resource = ? ORDER BY id DESC LIMIT 100",
            { '%' .. filter:gsub('[%%_]', '') .. '%', filter, filter })
    else
        rows = MySQL.query.await("SELECT id, resource, action, citizenid, LEFT(data, 400) AS data, DATE_FORMAT(created_at, '%m-%d %H:%i:%s') AS at FROM veyl_audit ORDER BY id DESC LIMIT 100")
    end
    return Veyl.Ok(rows or {})
end, opts(700))

Veyl.RegisterCallback('bans', function()
    return Veyl.Ok(MySQL.query.await([[SELECT id, name, reason, banned_by AS bannedBy, DATE_FORMAT(created_at, '%Y-%m-%d %H:%i') AS at,
        IF(expires_at IS NULL, NULL, DATE_FORMAT(expires_at, '%Y-%m-%d %H:%i')) AS expires FROM veyl_admin_bans
        WHERE expires_at IS NULL OR expires_at > NOW() ORDER BY id DESC LIMIT 80]]) or {})
end, opts(500))

Veyl.RegisterCallback('unban', function(src, _, id)
    id = int(id, 1, 2147483647)
    if not id then return Veyl.Err('INVALID_INPUT', 'Bad ban') end
    local n = MySQL.update.await('UPDATE veyl_admin_bans SET expires_at = NOW() WHERE id = ? AND (expires_at IS NULL OR expires_at > NOW())', { id })
    audit(src, 'unban', { ban = id })
    return n > 0 and Veyl.Ok(nil, 'Unbanned') or Veyl.Err('NOT_FOUND', 'Not an active ban')
end, opts(500))

---------------------------------------------------------------------------
-- Actions on a player
---------------------------------------------------------------------------
local ACTIONS = {}

ACTIONS.teleport = function(src, t)
    local c = GetEntityCoords(GetPlayerPed(t))
    local ped = GetPlayerPed(src)
    SetEntityCoords(ped, c.x, c.y, c.z + 1.0, false, false, false, false)
    return 'Teleported to ' .. GetPlayerName(t)
end
ACTIONS.bring = function(src, t)
    local c = GetEntityCoords(GetPlayerPed(src))
    SetEntityCoords(GetPlayerPed(t), c.x + 1.0, c.y, c.z + 0.5, false, false, false, false)
    return 'Brought ' .. GetPlayerName(t)
end
ACTIONS.spectate = function(src, t)
    local c = GetEntityCoords(GetPlayerPed(t))
    TriggerClientEvent('veyl_admin:spectate', src, t, GetPlayerName(t), { x = c.x, y = c.y, z = c.z })
    return 'Spectating ' .. GetPlayerName(t)
end
ACTIONS.freeze = function(src, t, d)
    local on = d and d.on == true
    TriggerClientEvent('veyl_admin:freeze', t, on)
    return (on and 'Froze ' or 'Unfroze ') .. GetPlayerName(t)
end
ACTIONS.revive = function(src, t)
    local ok = pcall(function() exports.veyl_medical:Revive(t, 100) end)
    TriggerClientEvent('veyl_admin:revive', t)
    pcall(function() exports.veyl_core:SetMetadataMany(t, { isdead = false, inlaststand = false }) end)
    return 'Revived ' .. GetPlayerName(t)
end
ACTIONS.heal = function(src, t)
    TriggerClientEvent('veyl_admin:heal', t)
    return 'Healed ' .. GetPlayerName(t)
end
ACTIONS.kill = function(src, t)
    TriggerClientEvent('veyl_admin:kill', t)
    return 'Killed ' .. GetPlayerName(t)
end
ACTIONS.message = function(src, t, d)
    local text = str(d and d.text, 240)
    if not text then return nil, 'Write a message first' end
    Veyl.Notify(t, 'Staff: ' .. text, 'warning', 12000)
    return 'Message sent'
end
ACTIONS.kick = function(src, t, d)
    local reason = str(d and d.reason, 200)
    if not reason then return nil, 'A reason is required' end
    audit(src, 'kick', { target = t, name = GetPlayerName(t), reason = reason })
    DropPlayer(t, 'Kicked by staff: ' .. reason)
    return 'Kicked'
end
ACTIONS.warn = function(src, t, d)
    local reason = str(d and d.reason, 200)
    local cid = Veyl.GetCitizenId(t)
    if not reason then return nil, 'A reason is required' end
    if not cid then return nil, 'No character loaded' end
    MySQL.insert.await('INSERT INTO veyl_admin_warnings (citizenid, reason, issued_by) VALUES (?, ?, ?)', { cid, reason, staffName(src) })
    Veyl.Notify(t, 'Warning from staff: ' .. reason, 'error', 15000)
    return 'Warning recorded'
end
ACTIONS.ban = function(src, t, d)
    local reason = str(d and d.reason, 200)
    local hours = int(d and d.hours, 0, 24 * 365 * 5)
    if not reason then return nil, 'A reason is required' end
    if hours == nil then return nil, 'Bad duration' end
    if Veyl.HasPermission(t, 'admin') then return nil, 'You cannot ban staff from here' end
    local license = ident(t, 'license')
    if not license then return nil, 'That player has no licence to ban' end
    MySQL.insert.await('INSERT INTO veyl_admin_bans (license, name, reason, banned_by, expires_at) VALUES (?, ?, ?, ?, ' .. (hours == 0 and 'NULL' or 'DATE_ADD(NOW(), INTERVAL ? HOUR)') .. ')',
        hours == 0 and { license, GetPlayerName(t), reason, staffName(src) } or { license, GetPlayerName(t), reason, staffName(src), hours })
    audit(src, 'ban', { target = GetPlayerName(t), license = license, reason = reason, hours = hours })
    DropPlayer(t, ('You were banned: %s (%s)'):format(reason, hours == 0 and 'permanent' or hours .. ' hours'))
    return 'Banned'
end
ACTIONS.money = function(src, t, d)
    local kind = d and d.kind
    local amount = int(d and d.amount, 1, 100000000)
    local reason = str(d and d.reason, 100)
    if (kind ~= 'cash' and kind ~= 'bank' and kind ~= 'crypto') or not amount or not reason then return nil, 'Pick cash, bank or crypto, an amount and a reason' end
    local cid = Veyl.GetCitizenId(t)
    if not cid then return nil, 'No character loaded' end
    local take = d.take == true
    local res = Veyl.Await('veyl_core', take and 'DebitOnce' or 'CreditOnce', 15000, cid, kind, amount, 'Staff adjustment: ' .. reason, Veyl.NewId('admin'))
    audit(src, 'money', { target = cid, kind = kind, amount = take and -amount or amount, reason = reason, ok = res.ok, code = res.code })
    if not res.ok then return nil, tostring(res.message or res.code) end
    return ('New %s balance: $%d'):format(kind, res.data.balance)
end
ACTIONS.job = function(src, t, d)
    local name, grade = str(d and d.job, 40), int(d and d.grade, 0, 50)
    if not name or not grade then return nil, 'Pick a job and a grade' end
    local ok = exports.veyl_core:SetJob(t, name, grade)
    audit(src, 'setjob', { target = t, job = name, grade = grade, ok = ok })
    return ok and 'Job set' or nil, ok and nil or 'Unknown job or grade'
end
ACTIONS.gang = function(src, t, d)
    local name, grade = str(d and d.gang, 40), int(d and d.grade, 0, 50)
    if not name or not grade then return nil, 'Pick a gang and a grade' end
    local ok = exports.veyl_core:SetGang(t, name, grade)
    audit(src, 'setgang', { target = t, gang = name, grade = grade, ok = ok })
    return ok and 'Gang set' or nil, ok and nil or 'Unknown gang or grade'
end
ACTIONS.giveitem = function(src, t, d)
    local item, count = str(d and d.item, 60), int(d and d.count, 1, 10000)
    if not item or not count then return nil, 'Pick an item and an amount' end
    local cid = Veyl.GetCitizenId(t)
    if not cid then return nil, 'No character loaded' end
    local res = Veyl.Await('veyl_inventory', 'GiveItem', 10000, cid, item, count, nil, Veyl.NewId('admin:item'))
    audit(src, 'giveitem', { target = cid, item = item, count = count, ok = res.ok })
    if not res.ok then return nil, tostring(res.message or res.code) end
    return ('Gave %dx %s'):format(count, item)
end
ACTIONS.takeitem = function(src, t, d)
    local item, count = str(d and d.item, 60), int(d and d.count, 1, 10000)
    if not item or not count then return nil, 'Pick an item and an amount' end
    local cid = Veyl.GetCitizenId(t)
    if not cid then return nil, 'No character loaded' end
    local res = Veyl.Await('veyl_inventory', 'TakeItem', 10000, cid, item, count, nil, Veyl.NewId('admin:take'))
    audit(src, 'takeitem', { target = cid, item = item, count = count, ok = res.ok })
    if not res.ok then return nil, tostring(res.message or res.code) end
    return ('Took %dx %s'):format(count, item)
end

-- Actions that can hit a fellow admin are limited to people with the same permission anyway; the ones below also refuse staff targets.
local NOT_ON_STAFF = { kill = true, kick = true, ban = true, freeze = true, takeitem = true, money = true }

Veyl.RegisterCallback('action', function(src, _, kind, id, data)
    local fn = type(kind) == 'string' and ACTIONS[kind]
    id = online(id)
    if not fn or not id then return Veyl.Err('INVALID_INPUT', 'Unknown action or player') end
    if NOT_ON_STAFF[kind] and id ~= src and Veyl.HasPermission(id, 'admin') and not Veyl.HasPermission(src, 'admin.super') then
        return Veyl.Err('NO_PERMISSION', 'That would hit another admin')
    end
    if type(data) ~= 'table' then data = {} end
    local msg, err = fn(src, id, data)
    audit(src, 'action_' .. kind, { target = id })
    if not msg then return Veyl.Err('FAILED', err or 'That did not work') end
    return Veyl.Ok(nil, msg)
end, opts(300))

---------------------------------------------------------------------------
-- Server, world and announcements
---------------------------------------------------------------------------
Veyl.RegisterCallback('announce', function(src, _, text)
    text = str(text, 240)
    if not text then return Veyl.Err('INVALID_INPUT', 'Write the announcement') end
    for _, s in ipairs(GetPlayers()) do Veyl.Notify(tonumber(s), 'Announcement: ' .. text, 'warning', 15000) end
    audit(src, 'announce', { text = text })
    return Veyl.Ok(nil, 'Sent to everyone')
end, opts(2000))

Veyl.RegisterCallback('world', function(src, _, kind, a, b)
    if kind == 'weather' then
        local w = str(a, 24)
        if not w or not C.WeatherSet[w:upper()] then return Veyl.Err('INVALID_INPUT', 'Unknown weather') end
        ExecuteCommand('vweather ' .. w:upper())
        audit(src, 'weather', { weather = w })
        return Veyl.Ok(nil, 'Weather set to ' .. w:upper())
    elseif kind == 'time' then
        local h, m = int(a, 0, 23), int(b, 0, 59)
        if not h or not m then return Veyl.Err('INVALID_INPUT', 'Bad time') end
        ExecuteCommand(('vtime %d %d'):format(h, m))
        audit(src, 'time', { hour = h, minute = m })
        return Veyl.Ok(nil, ('Time set to %02d:%02d'):format(h, m))
    elseif kind == 'freeze' then
        ExecuteCommand('vfreezetime')
        audit(src, 'freezetime', {})
        return Veyl.Ok(nil, 'Toggled time and weather freeze')
    elseif kind == 'clear' then
        TriggerClientEvent('veyl_admin:clearArea', -1, 80.0, Veyl.GetPlayerCoords(src))
        audit(src, 'cleararea', {})
        return Veyl.Ok(nil, 'Cleared abandoned vehicles around you')
    end
    return Veyl.Err('INVALID_INPUT', 'Unknown world action')
end, opts(500))

Veyl.RegisterCallback('resources', function()
    local out = {}
    for i = 0, GetNumResources() - 1 do
        local name = GetResourceByFindIndex(i)
        if name and (name:sub(1, 5) == 'veyl_' or C.ShowAllResources) then out[#out + 1] = { name = name, state = GetResourceState(name), locked = C.ProtectedResources[name] == true } end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return Veyl.Ok(out)
end, opts(800))

Veyl.RegisterCallback('resource', function(src, _, action, name)
    name = str(name, 64)
    if not name or not name:match('^[%w_%-%.%[%]]+$') or GetResourceState(name) == 'missing' then return Veyl.Err('INVALID_INPUT', 'Unknown resource') end
    if action ~= 'start' and action ~= 'stop' and action ~= 'restart' then return Veyl.Err('INVALID_INPUT', 'Unknown action') end
    if C.ProtectedResources[name] and action ~= 'start' then return Veyl.Err('NO_PERMISSION', name .. ' is protected: stopping it would break the server') end
    if not Veyl.HasPermission(src, 'admin.super') and not C.AnyAdminMayRestart then return Veyl.Err('NO_PERMISSION', 'Needs the veyl.admin.super permission') end
    audit(src, 'resource', { name = name, action = action })
    ExecuteCommand(('%s %s'):format(action, name))
    return Veyl.Ok(nil, ('%s %s'):format(action:gsub('^%l', string.upper), name))
end, opts(1000))

-- The client wants to spawn something (vehicle) or use a self tool that needs a server nod: say yes or no and write it down.
Veyl.RegisterCallback('allow', function(src, _, what, detail)
    if what ~= 'vehicle' and what ~= 'noclip' and what ~= 'god' and what ~= 'invisible' then return Veyl.Err('INVALID_INPUT', 'Unknown tool') end
    audit(src, 'self_' .. what, { detail = type(detail) == 'string' and detail:sub(1, 40) or nil })
    return Veyl.Ok(true)
end, opts(200))

Veyl.RegisterCallback('itemList', function()
    local out = {}
    local defs = exports.veyl_inventory:Items() or {}
    for name, d in pairs(defs) do out[#out + 1] = { name = name, label = d.label or name } end
    table.sort(out, function(a, b) return a.label < b.label end)
    return Veyl.Ok(out)
end, opts(1500))

-- Opening the menu: the permission is checked here, then the client opens the page.
RegisterCommand(C.Command, function(src)
    if src == 0 then return end
    if not Veyl.HasPermission(src, 'admin') then
        Veyl.Audit(src, 'admin_denied', { command = C.Command })
        return Veyl.Notify(src, 'You do not have permission to use this command.', 'error')
    end
    TriggerClientEvent('veyl_admin:open', src)
end, false)
