-- veyl_mdt server: people and vehicle lookups, officer notes, warrants, vehicle flags and reports.
-- Only on-duty members of MdtConfig.Jobs can use any of it. Every write is audited.

local C = MdtConfig

Veyl.Startup({ 'veyl_core' }, function()
    return Veyl.Migrate({
        { id = '001_init', sql = {
            [[CREATE TABLE IF NOT EXISTS veyl_mdt_profiles (
                citizenid VARCHAR(16) NOT NULL,
                notes TEXT NULL,
                updated_by VARCHAR(64) NULL,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (citizenid)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS veyl_mdt_warrants (
                id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                citizenid VARCHAR(16) NOT NULL,
                reason VARCHAR(240) NOT NULL,
                issued_by VARCHAR(64) NOT NULL,
                status ENUM('active','served','cancelled') NOT NULL DEFAULT 'active',
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                closed_at TIMESTAMP NULL,
                closed_by VARCHAR(64) NULL,
                PRIMARY KEY (id),
                KEY idx_cid (citizenid, status)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS veyl_mdt_vehicle_flags (
                plate VARCHAR(8) NOT NULL,
                stolen TINYINT(1) NOT NULL DEFAULT 0,
                bolo TINYINT(1) NOT NULL DEFAULT 0,
                notes VARCHAR(400) NULL,
                updated_by VARCHAR(64) NULL,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (plate)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS veyl_mdt_reports (
                id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                type ENUM('incident','arrest','traffic','other') NOT NULL DEFAULT 'incident',
                title VARCHAR(120) NOT NULL,
                body TEXT NOT NULL,
                author_cid VARCHAR(16) NOT NULL,
                author_name VARCHAR(64) NOT NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (id),
                KEY idx_created (created_at)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS veyl_mdt_report_people (
                report_id INT UNSIGNED NOT NULL,
                citizenid VARCHAR(16) NOT NULL,
                role ENUM('suspect','victim','witness','officer') NOT NULL DEFAULT 'suspect',
                PRIMARY KEY (report_id, citizenid),
                KEY idx_cid (citizenid)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        } },
        { id = '002_report_charges', sql = { 'ALTER TABLE veyl_mdt_reports ADD COLUMN IF NOT EXISTS charges TEXT NULL' } },
    })
end)

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function officer(src)
    local pd = Veyl.GetPlayerData(src)
    if not pd or not pd.job.onduty then return nil end
    for _, j in ipairs(C.Jobs) do
        if pd.job.name == j then
            return pd, ('%s %s'):format(pd.charinfo.firstname or '', pd.charinfo.lastname or '')
        end
    end
    return nil
end

local function guard(src)
    local pd, name = officer(src)
    if not pd then return nil, nil, Veyl.Err('NO_PERMISSION', 'The MDT is for on-duty officers') end
    return pd, name
end

local function decode(v)
    if type(v) == 'table' then return v end
    local ok, t = pcall(json.decode, v or '{}')
    return ok and type(t) == 'table' and t or {}
end

local function clean(s, max)
    if type(s) ~= 'string' then return nil end
    s = s:gsub('[%z\1-\8\11\12\14-\31]', ''):gsub('^%s+', ''):gsub('%s+$', '')
    return s:sub(1, max)
end

local function personRow(r)
    local ci = decode(r.charinfo)
    return { citizenid = r.citizenid, firstname = ci.firstname, lastname = ci.lastname, birthdate = ci.birthdate,
        gender = ci.gender, phone = ci.phone, nationality = ci.nationality, job = r.job }
end

local function jobLabel(name)
    local def = exports.veyl_core:GetJob(name)
    return def and def.label or name
end

---------------------------------------------------------------------------
-- Dashboard
---------------------------------------------------------------------------
Veyl.RegisterCallback('dashboard', function(src)
    local pd, name, err = guard(src)
    if err then return err end
    local warrants = MySQL.query.await([[SELECT w.id, w.citizenid, w.reason, w.issued_by, UNIX_TIMESTAMP(w.created_at) AS at, p.charinfo
        FROM veyl_mdt_warrants w LEFT JOIN veyl_players p ON p.citizenid = w.citizenid WHERE w.status = 'active' ORDER BY w.id DESC LIMIT 30]]) or {}
    for _, w in ipairs(warrants) do local ci = decode(w.charinfo) w.name = ('%s %s'):format(ci.firstname or '?', ci.lastname or '') w.charinfo = nil end
    local reports = MySQL.query.await([[SELECT id, type, title, author_name, UNIX_TIMESTAMP(created_at) AS at FROM veyl_mdt_reports ORDER BY id DESC LIMIT 15]]) or {}
    local flagged = MySQL.query.await([[SELECT plate, stolen, bolo, notes FROM veyl_mdt_vehicle_flags WHERE stolen = 1 OR bolo = 1 ORDER BY updated_at DESC LIMIT 20]]) or {}
    return Veyl.Ok({ officer = name, warrants = warrants, reports = reports, flagged = flagged, charges = C.Charges,
        roster = Roster(), canLicence = (pd.job.grade and pd.job.grade.level or 0) >= C.LicenceGrade })
end, { cooldown = 500 })

---------------------------------------------------------------------------
-- People
---------------------------------------------------------------------------
Veyl.RegisterCallback('searchPeople', function(src, _, query)
    local _, _, err = guard(src)
    if err then return err end
    query = clean(query, 40)
    if not query or #query < 2 then return Veyl.Err('INVALID_INPUT', 'Type at least 2 characters') end
    local like = '%' .. query:gsub('[%%_]', '') .. '%'
    local first, last = query:match('^(%S+)%s+(%S+)$')
    local rows = MySQL.query.await([[SELECT citizenid, charinfo, job FROM veyl_players WHERE deleted_at IS NULL AND (
            citizenid = ? OR JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.phone')) = ?
            OR JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname')) LIKE ? OR JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname')) LIKE ?
            OR (JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.firstname')) LIKE ? AND JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.lastname')) LIKE ?))
        LIMIT 25]], { query:upper(), query, like, like, (first or '~') .. '%', (last or '~') .. '%' }) or {}
    local out = {}
    for _, r in ipairs(rows) do
        local p = personRow(r)
        p.job = jobLabel(r.job)
        p.warrants = MySQL.scalar.await("SELECT COUNT(*) FROM veyl_mdt_warrants WHERE citizenid = ? AND status = 'active'", { r.citizenid }) or 0
        out[#out + 1] = p
    end
    return Veyl.Ok(out)
end, { cooldown = 600 })

local function profile(citizenid)
    local r = MySQL.single.await('SELECT citizenid, charinfo, metadata, job FROM veyl_players WHERE citizenid = ? AND deleted_at IS NULL', { citizenid })
    if not r then return nil end
    local p = personRow(r)
    p.job = jobLabel(r.job)
    local src = exports.veyl_core:GetSourceByCitizenId(citizenid)
    local live = src and Veyl.GetPlayerData(src)
    local meta = live and live.metadata or decode(r.metadata)
    local lic = type(meta.licences) == 'table' and meta.licences or {}
    p.licences = {}
    for _, key in ipairs(C.Licences) do p.licences[#p.licences + 1] = { key = key.key, label = key.label, held = lic[key.key] == true } end
    p.online = live ~= nil
    p.vehicles = MySQL.query.await([[SELECT v.plate, v.model, v.state, f.stolen, f.bolo FROM veyl_player_vehicles v
        LEFT JOIN veyl_mdt_vehicle_flags f ON f.plate = v.plate WHERE v.citizenid = ? ORDER BY v.id]], { citizenid }) or {}
    p.citations = GetResourceState('veyl_police') == 'started' and exports.veyl_police:GetCitations(citizenid, 25) or {}
    p.warrants = MySQL.query.await([[SELECT id, reason, issued_by, status, UNIX_TIMESTAMP(created_at) AS at FROM veyl_mdt_warrants
        WHERE citizenid = ? ORDER BY status = 'active' DESC, id DESC LIMIT 25]], { citizenid }) or {}
    p.reports = MySQL.query.await([[SELECT r.id, r.type, r.title, rp.role, UNIX_TIMESTAMP(r.created_at) AS at FROM veyl_mdt_report_people rp
        JOIN veyl_mdt_reports r ON r.id = rp.report_id WHERE rp.citizenid = ? ORDER BY r.id DESC LIMIT 25]], { citizenid }) or {}
    local prof = MySQL.single.await('SELECT notes, updated_by, UNIX_TIMESTAMP(updated_at) AS at FROM veyl_mdt_profiles WHERE citizenid = ?', { citizenid })
    p.notes = prof and prof.notes or ''
    p.notesBy = prof and prof.updated_by or nil
    if GetResourceState('veyl_prison') == 'started' then
        local ok, sentence = pcall(function() return exports.veyl_prison:GetSentence(citizenid) end)
        p.sentence = ok and sentence or nil
    end
    return p
end

Veyl.RegisterCallback('person', function(src, _, citizenid)
    local _, _, err = guard(src)
    if err then return err end
    if type(citizenid) ~= 'string' then return Veyl.Err('INVALID_INPUT', 'Unknown person') end
    local p = profile(citizenid)
    if not p then return Veyl.Err('NOT_FOUND', 'No record for that person') end
    return Veyl.Ok(p)
end, { cooldown = 300 })

Veyl.RegisterCallback('saveNotes', function(src, _, citizenid, notes)
    local _, name, err = guard(src)
    if err then return err end
    notes = clean(notes, 2000) or ''
    if type(citizenid) ~= 'string' or not MySQL.scalar.await('SELECT 1 FROM veyl_players WHERE citizenid = ?', { citizenid }) then
        return Veyl.Err('NOT_FOUND', 'Unknown person')
    end
    MySQL.query.await([[INSERT INTO veyl_mdt_profiles (citizenid, notes, updated_by) VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE notes = VALUES(notes), updated_by = VALUES(updated_by)]], { citizenid, notes, name })
    Veyl.Audit(src, 'mdt_notes', { target = citizenid })
    return Veyl.Ok(profile(citizenid), 'Notes saved')
end, { cooldown = 1000 })

---------------------------------------------------------------------------
-- Warrants
---------------------------------------------------------------------------
Veyl.RegisterCallback('issueWarrant', function(src, _, citizenid, reason)
    local _, name, err = guard(src)
    if err then return err end
    reason = clean(reason, 240)
    if not reason or #reason < 5 then return Veyl.Err('INVALID_INPUT', 'Describe the reason (at least 5 characters)') end
    if type(citizenid) ~= 'string' or not MySQL.scalar.await('SELECT 1 FROM veyl_players WHERE citizenid = ?', { citizenid }) then
        return Veyl.Err('NOT_FOUND', 'Unknown person')
    end
    local id = MySQL.insert.await('INSERT INTO veyl_mdt_warrants (citizenid, reason, issued_by) VALUES (?, ?, ?)', { citizenid, reason, name })
    Veyl.Audit(src, 'mdt_warrant', { id = id, target = citizenid })
    return Veyl.Ok(profile(citizenid), ('Warrant #%d issued'):format(id))
end, { cooldown = 1500 })

Veyl.RegisterCallback('closeWarrant', function(src, _, id, how)
    local _, name, err = guard(src)
    if err then return err end
    local status = how == 'cancelled' and 'cancelled' or 'served'
    local row = MySQL.single.await("SELECT citizenid FROM veyl_mdt_warrants WHERE id = ? AND status = 'active'", { tonumber(id) or 0 })
    if not row then return Veyl.Err('NOT_FOUND', 'No active warrant with that number') end
    MySQL.update.await('UPDATE veyl_mdt_warrants SET status = ?, closed_at = NOW(), closed_by = ? WHERE id = ?', { status, name, tonumber(id) })
    Veyl.Audit(src, 'mdt_warrant_' .. status, { id = id })
    return Veyl.Ok(profile(row.citizenid), ('Warrant #%d %s'):format(id, status))
end, { cooldown = 1000 })

---------------------------------------------------------------------------
-- Vehicles
---------------------------------------------------------------------------
local function vehicle(plate)
    local v = MySQL.single.await([[SELECT v.plate, v.model, v.state, v.citizenid, p.charinfo FROM veyl_player_vehicles v
        LEFT JOIN veyl_players p ON p.citizenid = v.citizenid WHERE v.plate = ?]], { plate })
    local f = MySQL.single.await('SELECT stolen, bolo, notes, updated_by FROM veyl_mdt_vehicle_flags WHERE plate = ?', { plate })
    if not v and not f then return nil end
    local ci = v and decode(v.charinfo) or {}
    return {
        plate = plate, model = v and v.model or nil, state = v and v.state or nil, registered = v ~= nil,
        owner = v and { citizenid = v.citizenid, name = ('%s %s'):format(ci.firstname or '?', ci.lastname or '') } or nil,
        stolen = f and f.stolen == 1 or false, bolo = f and f.bolo == 1 or false, notes = f and f.notes or '', flaggedBy = f and f.updated_by or nil,
    }
end

Veyl.RegisterCallback('searchVehicle', function(src, _, plate)
    local _, _, err = guard(src)
    if err then return err end
    plate = clean(plate, 8)
    if not plate or #plate < 2 then return Veyl.Err('INVALID_INPUT', 'Type a plate') end
    plate = plate:upper()
    local exact = vehicle(plate)
    if exact then return Veyl.Ok({ exact = exact, list = {} }) end
    local list = MySQL.query.await('SELECT plate, model FROM veyl_player_vehicles WHERE plate LIKE ? LIMIT 15', { '%' .. plate:gsub('[%%_]', '') .. '%' }) or {}
    return Veyl.Ok({ exact = nil, list = list })
end, { cooldown = 500 })

Veyl.RegisterCallback('vehicle', function(src, _, plate)
    local _, _, err = guard(src)
    if err then return err end
    local v = type(plate) == 'string' and vehicle(plate:upper():sub(1, 8))
    if not v then return Veyl.Err('NOT_FOUND', 'No record for that plate') end
    return Veyl.Ok(v)
end, { cooldown = 300 })

Veyl.RegisterCallback('flagVehicle', function(src, _, plate, stolen, bolo, notes)
    local _, name, err = guard(src)
    if err then return err end
    plate = clean(plate, 8)
    if not plate or #plate < 2 then return Veyl.Err('INVALID_INPUT', 'Type a plate') end
    plate = plate:upper()
    MySQL.query.await([[INSERT INTO veyl_mdt_vehicle_flags (plate, stolen, bolo, notes, updated_by) VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE stolen = VALUES(stolen), bolo = VALUES(bolo), notes = VALUES(notes), updated_by = VALUES(updated_by)]],
        { plate, stolen == true and 1 or 0, bolo == true and 1 or 0, clean(notes, 400) or '', name })
    Veyl.Audit(src, 'mdt_vehicle_flag', { plate = plate, stolen = stolen == true, bolo = bolo == true })
    return Veyl.Ok(vehicle(plate), 'Vehicle record saved')
end, { cooldown = 1000 })

---------------------------------------------------------------------------
-- Reports
---------------------------------------------------------------------------
local TYPES = { incident = true, arrest = true, traffic = true, other = true }
local ROLES = { suspect = true, victim = true, witness = true, officer = true }

local function report(id)
    local r = MySQL.single.await([[SELECT id, type, title, body, author_name, charges, UNIX_TIMESTAMP(created_at) AS at, UNIX_TIMESTAMP(updated_at) AS updated
        FROM veyl_mdt_reports WHERE id = ?]], { id })
    if not r then return nil end
    r.people = MySQL.query.await([[SELECT rp.citizenid, rp.role, p.charinfo FROM veyl_mdt_report_people rp
        LEFT JOIN veyl_players p ON p.citizenid = rp.citizenid WHERE rp.report_id = ?]], { id }) or {}
    for _, p in ipairs(r.people) do local ci = decode(p.charinfo) p.name = ('%s %s'):format(ci.firstname or '?', ci.lastname or '') p.charinfo = nil end
    r.charges = decode(r.charges)
    return r
end

Veyl.RegisterCallback('reports', function(src, _, query)
    local _, _, err = guard(src)
    if err then return err end
    query = clean(query, 60)
    local rows
    if query and #query >= 2 then
        local like = '%' .. query:gsub('[%%_]', '') .. '%'
        rows = MySQL.query.await([[SELECT id, type, title, author_name, UNIX_TIMESTAMP(created_at) AS at FROM veyl_mdt_reports
            WHERE title LIKE ? OR body LIKE ? OR id = ? ORDER BY id DESC LIMIT 40]], { like, like, tonumber(query) or 0 })
    else
        rows = MySQL.query.await([[SELECT id, type, title, author_name, UNIX_TIMESTAMP(created_at) AS at FROM veyl_mdt_reports ORDER BY id DESC LIMIT 40]])
    end
    return Veyl.Ok(rows or {})
end, { cooldown = 400 })

Veyl.RegisterCallback('report', function(src, _, id)
    local _, _, err = guard(src)
    if err then return err end
    local r = report(tonumber(id) or 0)
    if not r then return Veyl.Err('NOT_FOUND', 'No report with that number') end
    return Veyl.Ok(r)
end, { cooldown = 300 })

--- saveReport({ id?, type, title, body, people = { { citizenid, role } } })
Veyl.RegisterCallback('saveReport', function(src, _, data)
    local pd, name, err = guard(src)
    if err then return err end
    if type(data) ~= 'table' then return Veyl.Err('INVALID_INPUT', 'Invalid report') end
    local title, body = clean(data.title, 120), clean(data.body, 8000)
    if not title or #title < 3 then return Veyl.Err('INVALID_INPUT', 'Give the report a title') end
    if not body or #body < 5 then return Veyl.Err('INVALID_INPUT', 'Write what happened') end
    local rtype = TYPES[data.type] and data.type or 'incident'
    local id = tonumber(data.id)
    if id then
        if not MySQL.scalar.await('SELECT 1 FROM veyl_mdt_reports WHERE id = ?', { id }) then return Veyl.Err('NOT_FOUND', 'No report with that number') end
        MySQL.update.await('UPDATE veyl_mdt_reports SET type = ?, title = ?, body = ?, charges = ? WHERE id = ?', { rtype, title, body, json.encode(ValidCharges(data.charges)), id })
    else
        id = MySQL.insert.await('INSERT INTO veyl_mdt_reports (type, title, body, author_cid, author_name, charges) VALUES (?, ?, ?, ?, ?, ?)',
            { rtype, title, body, pd.citizenid, name, json.encode(ValidCharges(data.charges)) })
    end
    MySQL.update.await('DELETE FROM veyl_mdt_report_people WHERE report_id = ?', { id })
    local seen = 0
    for _, p in ipairs(type(data.people) == 'table' and data.people or {}) do
        if seen >= 20 then break end
        if type(p) == 'table' and type(p.citizenid) == 'string' and ROLES[p.role] and MySQL.scalar.await('SELECT 1 FROM veyl_players WHERE citizenid = ?', { p.citizenid }) then
            MySQL.insert.await('INSERT IGNORE INTO veyl_mdt_report_people (report_id, citizenid, role) VALUES (?, ?, ?)', { id, p.citizenid, p.role })
            seen = seen + 1
        end
    end
    Veyl.Audit(src, 'mdt_report', { id = id, edited = tonumber(data.id) ~= nil })
    return Veyl.Ok(report(id), ('Report #%d saved'):format(id))
end, { cooldown = 1500 })

---------------------------------------------------------------------------
-- Prison hand-off (veyl_prison): sentence a person from their profile
---------------------------------------------------------------------------
Veyl.RegisterCallback('sentence', function(src, _, citizenid, months, reason)
    local _, name, err = guard(src)
    if err then return err end
    if GetResourceState('veyl_prison') ~= 'started' then return Veyl.Err('UNAVAILABLE', 'The prison system is not running') end
    local ok, res = pcall(function() return exports.veyl_prison:Sentence(src, citizenid, tonumber(months), clean(reason, 160)) end)
    if not ok or type(res) ~= 'table' then return Veyl.Err('INTERNAL', 'Could not sentence') end
    if not res.ok then return res end
    return Veyl.Ok(profile(citizenid), res.message)
end, { cooldown = 2000 })

---------------------------------------------------------------------------
-- Penal code: fines and sentences from charges
---------------------------------------------------------------------------
local chargeById = {}
for _, c in ipairs(C.Charges) do chargeById[c.id] = c end

--- Known charge ids from a client list (max 20, repeats allowed: two counts of the same charge).
function ValidCharges(list)
    local out = {}
    for _, id in ipairs(type(list) == 'table' and list or {}) do
        if #out >= 20 then break end
        if chargeById[id] then out[#out + 1] = id end
    end
    return out
end

local function totals(ids)
    local fine, months, labels = 0, 0, {}
    for _, id in ipairs(ids) do
        local c = chargeById[id]
        fine, months = fine + c.fine, months + c.months
        labels[#labels + 1] = c.label
    end
    return fine, months, table.concat(labels, ', ')
end

Veyl.RegisterCallback('chargeFine', function(src, _, citizenid, list)
    local _, _, err = guard(src)
    if err then return err end
    if GetResourceState('veyl_police') ~= 'started' then return Veyl.Err('UNAVAILABLE', 'Citations need veyl_police') end
    local ids = ValidCharges(list)
    if #ids == 0 then return Veyl.Err('INVALID_INPUT', 'Pick at least one charge') end
    local fine, _, labels = totals(ids)
    local res = exports.veyl_police:RecordCitation(src, citizenid, fine, labels:sub(1, 160))
    if not res.ok then return res end
    return Veyl.Ok(profile(citizenid), res.message)
end, { cooldown = 2000 })

Veyl.RegisterCallback('chargeSentence', function(src, _, citizenid, list, withFine)
    local _, _, err = guard(src)
    if err then return err end
    if GetResourceState('veyl_prison') ~= 'started' then return Veyl.Err('UNAVAILABLE', 'The prison system is not running') end
    local ids = ValidCharges(list)
    if #ids == 0 then return Veyl.Err('INVALID_INPUT', 'Pick at least one charge') end
    local fine, months, labels = totals(ids)
    if months < 1 then return Veyl.Err('INVALID_INPUT', 'These charges carry no prison time: issue a fine instead') end
    local ok, res = pcall(function() return exports.veyl_prison:Sentence(src, citizenid, months, labels:sub(1, 160)) end)
    if not ok or type(res) ~= 'table' then return Veyl.Err('INTERNAL', 'Could not sentence') end
    if not res.ok then return res end
    local msg = res.message
    if withFine == true and fine > 0 and GetResourceState('veyl_police') == 'started' then
        local f = exports.veyl_police:RecordCitation(src, citizenid, fine, labels:sub(1, 160))
        if f.ok then msg = msg .. ' · ' .. f.message end
    end
    return Veyl.Ok(profile(citizenid), msg)
end, { cooldown = 2000 })

---------------------------------------------------------------------------
-- Licences (senior officers)
---------------------------------------------------------------------------
Veyl.RegisterCallback('setLicence', function(src, _, citizenid, key, on)
    local pd, _, err = guard(src)
    if err then return err end
    if (pd.job.grade and pd.job.grade.level or 0) < C.LicenceGrade then return Veyl.Err('NO_PERMISSION', 'Your rank cannot change licences') end
    local known = false
    for _, l in ipairs(C.Licences) do if l.key == key then known = true end end
    if not known or type(citizenid) ~= 'string' then return Veyl.Err('INVALID_INPUT', 'Unknown licence') end
    on = on == true
    local tsrc = exports.veyl_core:GetSourceByCitizenId(citizenid)
    if tsrc then
        local lic = exports.veyl_core:GetMetadata(tsrc, 'licences')
        lic = type(lic) == 'table' and lic or {}
        lic[key] = on
        exports.veyl_core:SetMetadata(tsrc, 'licences', lic)
        Veyl.Notify(tsrc, ('Your %s was %s.'):format(key == 'driver' and "driver's licence" or key .. ' licence', on and 'granted' or 'revoked'), on and 'success' or 'warning')
    else
        local affected = MySQL.update.await(("UPDATE veyl_players SET metadata = JSON_SET(metadata, '$.licences.%s', JSON_EXTRACT(?, '$')) WHERE citizenid = ?"):format(key),
            { on and 'true' or 'false', citizenid })
        if affected ~= 1 then return Veyl.Err('NOT_FOUND', 'Unknown person') end
    end
    Veyl.Audit(src, 'mdt_licence', { target = citizenid, licence = key, on = on })
    return Veyl.Ok(profile(citizenid), on and 'Licence granted' or 'Licence revoked')
end, { cooldown = 1000 })

---------------------------------------------------------------------------
-- Roster (on-duty officers from veyl_dispatch)
---------------------------------------------------------------------------
function Roster()
    if GetResourceState('veyl_dispatch') ~= 'started' then return nil end
    local ok, list = pcall(function() return exports.veyl_dispatch:GetUnits('police') end)
    return ok and list or nil
end

Veyl.RegisterCallback('roster', function(src)
    local _, _, err = guard(src)
    if err then return err end
    return Veyl.Ok(Roster() or {})
end, { cooldown = 500 })
