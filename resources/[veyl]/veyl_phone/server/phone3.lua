-- Phone 2.0, phase 2 (server): Camera / Gallery, Jobs, Garage valet, Bank 2.0 (bills, standing orders, credit
-- score), Music speaker, News, Racing and the Tablet item.

local C = PhoneConfig
local function core(name, ...) return Veyl.Await('veyl_core', name, 15000, ...) end
local function session(src)
    local s = Phone.Session(src)
    if not s then return nil, Veyl.Err('NO_SESSION', 'Open your phone first') end
    return s
end
local function charName(pd) return pd and ('%s %s'):format(pd.charinfo.firstname or '', pd.charinfo.lastname or '') or 'Unknown' end
local function cidByNumber(number)
    if type(number) ~= 'string' then return nil end
    return MySQL.scalar.await('SELECT citizenid FROM veyl_phone_accounts WHERE number = ?', { number:gsub('%D', '') })
end
local seq = 0
local function op(kind, cid) seq = seq + 1 return ('phone:%s:%s:%d:%d'):format(kind, cid, os.time(), seq) end

---------------------------------------------------------------------------
-- Camera / Gallery (photos are taken on the client with screenshot-basic and stored as small JPEG data URLs)
---------------------------------------------------------------------------
Veyl.RegisterCallback('photoSave', function(src, citizenid, image)
    local _, err = session(src)
    if err then return err end
    if type(image) ~= 'string' or not image:match('^data:image/jpe?g;base64,') or #image > 600000 then return Veyl.Err('INVALID_INPUT', 'Photo too large or not a photo') end
    if (MySQL.scalar.await('SELECT COUNT(*) FROM veyl_phone_photos WHERE citizenid = ?', { citizenid }) or 0) >= C.Camera.Max then
        return Veyl.Err('LIMIT', ('Your gallery is full (%d photos)'):format(C.Camera.Max))
    end
    local id = MySQL.insert.await('INSERT INTO veyl_phone_photos (citizenid, image) VALUES (?, ?)', { citizenid, image })
    return Veyl.Ok({ id = id }, 'Saved to Gallery')
end, { cooldown = 1500 })

Veyl.RegisterCallback('photoList', function(src, citizenid)
    local _, err = session(src)
    if err then return err end
    return Veyl.Ok(MySQL.query.await('SELECT id, UNIX_TIMESTAMP(created_at) AS at FROM veyl_phone_photos WHERE citizenid = ? ORDER BY id DESC', { citizenid }) or {})
end, { cooldown = 300 })

Veyl.RegisterCallback('photoGet', function(src, citizenid, id)
    local _, err = session(src)
    if err then return err end
    local img = MySQL.scalar.await('SELECT image FROM veyl_phone_photos WHERE id = ? AND citizenid = ?', { tonumber(id) or 0, citizenid })
    return img and Veyl.Ok({ image = img }) or Veyl.Err('NOT_FOUND', 'Photo not found')
end, { cooldown = 50 })

Veyl.RegisterCallback('photoDelete', function(src, citizenid, id)
    local _, err = session(src)
    if err then return err end
    MySQL.update.await('DELETE FROM veyl_phone_photos WHERE id = ? AND citizenid = ?', { tonumber(id) or 0, citizenid })
    return Veyl.Ok()
end, { cooldown = 200 })

---------------------------------------------------------------------------
-- Jobs
---------------------------------------------------------------------------
Veyl.RegisterCallback('jobsData', function(src, citizenid)
    local _, err = session(src)
    if err then return err end
    local pd = Veyl.GetPlayerData(src)
    local defs = exports.veyl_core:GetJobs()
    local mine = {}
    for name, grade in pairs(pd.jobs or {}) do
        local d = defs[name]
        if d then
            local g = d.grades[tostring(grade)]
            mine[#mine + 1] = { name = name, label = d.label, grade = g and g.name or tostring(grade), pay = g and g.payment or 0, primary = pd.job.name == name }
        end
    end
    local board = {}
    local list = GetResourceState('veyl_cityhall') == 'started' and exports.veyl_cityhall:GetJobBoard() or {}
    for _, j in ipairs(list or {}) do
        local d = defs[j.job]
        if d then board[#board + 1] = { job = j.job, label = d.label, description = j.description, open = d.open == true, apply = j.apply, member = pd.jobs[j.job] ~= nil } end
    end
    local apps = MySQL.query.await("SELECT id, job, status, UNIX_TIMESTAMP(created_at) AS at FROM veyl_phone_job_apps WHERE citizenid = ? ORDER BY id DESC LIMIT 10", { citizenid }) or {}
    -- Bosses see applications for their job.
    local inbox
    if pd.job and pd.job.isboss then
        inbox = MySQL.query.await([[SELECT id, name, number, message, status, UNIX_TIMESTAMP(created_at) AS at FROM veyl_phone_job_apps
            WHERE job = ? AND status <> 'closed' ORDER BY id DESC LIMIT 30]], { pd.job.name }) or {}
    end
    return Veyl.Ok({ mine = mine, primary = pd.job.name, onduty = pd.job.onduty == true, jobLabel = pd.job.label, board = board, apps = apps, inbox = inbox })
end, { cooldown = 500 })

Veyl.RegisterCallback('jobsDuty', function(src)
    local _, err = session(src)
    if err then return err end
    local pd = Veyl.GetPlayerData(src)
    if pd.job.name == 'unemployed' then return Veyl.Err('INVALID_STATE', 'You have no job to clock in to') end
    exports.veyl_core:SetJobDuty(src, not pd.job.onduty)
    return Veyl.Ok(nil, pd.job.onduty and 'Clocked out' or 'Clocked in')
end, { cooldown = 2000 })

Veyl.RegisterCallback('jobsPrimary', function(src, citizenid, name)
    local _, err = session(src)
    if err then return err end
    if type(name) ~= 'string' or not exports.veyl_core:SetPlayerPrimaryJob(citizenid, name) then return Veyl.Err('NO_PERMISSION', 'You do not work there') end
    return Veyl.Ok(nil, 'Main job changed')
end, { cooldown = 2000 })

Veyl.RegisterCallback('jobsApply', function(src, citizenid, job, message)
    local s, err = session(src)
    if err then return err end
    local def = type(job) == 'string' and exports.veyl_core:GetJob(job)
    if not def then return Veyl.Err('NOT_FOUND', 'Unknown job') end
    message = Phone.Clean(message, 500)
    if not message or #message < 10 then return Veyl.Err('INVALID_INPUT', 'Write a few words about yourself') end
    if MySQL.scalar.await("SELECT 1 FROM veyl_phone_job_apps WHERE citizenid = ? AND job = ? AND status <> 'closed'", { citizenid, job }) then
        return Veyl.Err('INVALID_STATE', 'You already applied there')
    end
    local pd = Veyl.GetPlayerData(src)
    MySQL.insert.await('INSERT INTO veyl_phone_job_apps (job, citizenid, name, number, message) VALUES (?, ?, ?, ?, ?)', { job, citizenid, charName(pd), s.number, message })
    for _, p in ipairs(GetPlayers()) do
        local o = Veyl.GetPlayerData(tonumber(p))
        if o and o.jobs and o.jobs[job] ~= nil and exports.veyl_core:IsGradeBoss(job, o.jobs[job]) then
            Notify.Send(o.citizenid, { app = 'jobs', title = ('New application: %s'):format(def.label), body = charName(pd), route = 'jobs' })
        end
    end
    return Veyl.Ok(nil, ('Application sent to %s'):format(def.label))
end, { cooldown = 3000 })

Veyl.RegisterCallback('jobsAppClose', function(src, _, id)
    local _, err = session(src)
    if err then return err end
    local pd = Veyl.GetPlayerData(src)
    if not pd.job.isboss then return Veyl.Err('NO_PERMISSION', 'Managers only') end
    MySQL.update.await("UPDATE veyl_phone_job_apps SET status = 'closed' WHERE id = ? AND job = ?", { tonumber(id) or 0, pd.job.name })
    return Veyl.Ok()
end, { cooldown = 300 })

---------------------------------------------------------------------------
-- Garage valet: a garaged vehicle is brought to the road next to you
---------------------------------------------------------------------------
Veyl.RegisterCallback('garageValet', function(src, citizenid, ownedId, spot)
    local _, err = session(src)
    if err then return err end
    ownedId = tonumber(ownedId)
    if not ownedId or type(spot) ~= 'table' or not tonumber(spot.x) then return Veyl.Err('INVALID_INPUT', 'Invalid request') end
    local pc = Veyl.GetPlayerCoords(src)
    local at = vector3(spot.x + 0.0, spot.y + 0.0, spot.z + 0.0)
    if not pc or #(pc - at) > 80.0 then return Veyl.Err('TOO_FAR', 'Stand near a road') end
    if not MySQL.scalar.await("SELECT 1 FROM veyl_player_vehicles WHERE id = ? AND citizenid = ? AND state = 'garaged'", { ownedId, citizenid }) then
        return Veyl.Err('INVALID_STATE', 'Only vehicles parked in a garage can be delivered')
    end
    local id = op('valet', citizenid)
    local pay = core('DebitOnce', citizenid, 'bank', C.Valet.Fee, 'Valet delivery', id)
    if not pay.ok then return Veyl.Err('INSUFFICIENT_FUNDS', ('Valet costs $%d from your bank'):format(C.Valet.Fee)) end
    local r = Veyl.Await('veyl_vehicles', 'SpawnOwnedVehicle', 20000, src, citizenid, ownedId, vector4(at.x, at.y, at.z, tonumber(spot.h) or 0.0), { from = 'garaged' })
    if not r.ok then
        core('CreditOnce', citizenid, 'bank', C.Valet.Fee, 'Valet delivery refund', id .. ':refund')
        return Veyl.Err(r.code or 'INTERNAL', r.message or 'The valet could not bring it. Refunded.')
    end
    return Veyl.Ok({ x = at.x, y = at.y }, ('Your vehicle is waiting on the road ($%d)'):format(C.Valet.Fee))
end, { cooldown = 5000 })

---------------------------------------------------------------------------
-- Bank 2.0: bills (mechanic invoices, citations), standing orders, credit score
---------------------------------------------------------------------------
local function tableExists(name)
    return MySQL.scalar.await('SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ?', { name }) > 0
end

local function bills(citizenid)
    local out = {}
    if tableExists('veyl_invoices') then
        for _, r in ipairs(MySQL.query.await([[SELECT id, amount, reason, UNIX_TIMESTAMP(created_at) AS at FROM veyl_invoices
            WHERE recipient_cid = ? AND status = 'pending' ORDER BY id]], { citizenid }) or {}) do
            out[#out + 1] = { kind = 'invoice', id = r.id, amount = r.amount, label = ('Invoice #%d · %s'):format(r.id, r.reason), at = r.at }
        end
    end
    if tableExists('veyl_police_citations') then
        for _, r in ipairs(MySQL.query.await([[SELECT id, amount, reason, UNIX_TIMESTAMP(created_at) AS at FROM veyl_police_citations
            WHERE citizenid = ? AND status = 'unpaid' ORDER BY id]], { citizenid }) or {}) do
            out[#out + 1] = { kind = 'citation', id = r.id, amount = r.amount, label = ('Citation #%d · %s'):format(r.id, r.reason), at = r.at }
        end
    end
    return out
end

local function creditScore(citizenid, unpaid)
    local paid = 0
    if tableExists('veyl_invoices') then paid = paid + (MySQL.scalar.await("SELECT COUNT(*) FROM veyl_invoices WHERE recipient_cid = ? AND status = 'paid'", { citizenid }) or 0) end
    if tableExists('veyl_police_citations') then paid = paid + (MySQL.scalar.await("SELECT COUNT(*) FROM veyl_police_citations WHERE citizenid = ? AND status = 'paid'", { citizenid }) or 0) end
    local failures = MySQL.scalar.await('SELECT COALESCE(SUM(failures), 0) FROM veyl_phone_standing WHERE citizenid = ?', { citizenid }) or 0
    local bank = MySQL.scalar.await("SELECT balance FROM veyl_money WHERE citizenid = ? AND type = 'bank'", { citizenid }) or 0
    local score = 600 + math.min(150, paid * 5) - unpaid * 40 - failures * 20 + (bank >= 100000 and 60 or bank >= 25000 and 35 or bank >= 5000 and 15 or 0)
    return math.max(300, math.min(850, score))
end

Veyl.RegisterCallback('billsData', function(src, citizenid)
    local _, err = session(src)
    if err then return err end
    local list = bills(citizenid)
    local standing = MySQL.query.await([[SELECT id, to_label, amount, every_days, note, UNIX_TIMESTAMP(next_at) AS next_at, failures FROM veyl_phone_standing
        WHERE citizenid = ? AND active = 1 ORDER BY id]], { citizenid }) or {}
    return Veyl.Ok({ bills = list, standing = standing, score = creditScore(citizenid, #list) })
end, { cooldown = 500 })

Veyl.RegisterCallback('billPay', function(src, citizenid, kind, id, method)
    local _, err = session(src)
    if err then return err end
    id = tonumber(id)
    method = method == 'cash' and 'cash' or 'bank'
    if kind == 'invoice' then
        local row = id and MySQL.single.await("SELECT sender_cid, amount, reason FROM veyl_invoices WHERE id = ? AND recipient_cid = ? AND status = 'pending'", { id, citizenid })
        if not row then return Veyl.Err('NOT_FOUND', 'Already paid or not yours') end
        -- Same operation id as the mechanic's own pay flow, so the two can never both charge.
        local pay = core('TransferMoney', citizenid, method, row.sender_cid, 'bank', row.amount, ('Invoice #%d: %s'):format(id, row.reason), 'invoice:' .. id)
        if not pay.ok and pay.code ~= 'DUPLICATE_OPERATION' then return Veyl.Err(pay.code or 'INSUFFICIENT_FUNDS', 'Payment failed') end
        MySQL.update.await("UPDATE veyl_invoices SET status = 'paid', settled_at = NOW() WHERE id = ? AND status = 'pending'", { id })
    elseif kind == 'citation' then
        local row = id and MySQL.single.await("SELECT amount, reason FROM veyl_police_citations WHERE id = ? AND citizenid = ? AND status = 'unpaid'", { id, citizenid })
        if not row then return Veyl.Err('NOT_FOUND', 'Already paid or not yours') end
        local pay = core('DebitOnce', citizenid, method, row.amount, ('Citation #%d: %s'):format(id, row.reason), 'citation:' .. id)
        if not pay.ok and pay.code ~= 'DUPLICATE_OPERATION' then return Veyl.Err(pay.code or 'INSUFFICIENT_FUNDS', 'Payment failed') end
        MySQL.update.await("UPDATE veyl_police_citations SET status = 'paid', paid_at = NOW() WHERE id = ?", { id })
    else
        return Veyl.Err('INVALID_INPUT', 'Unknown bill')
    end
    return Veyl.Ok(nil, 'Paid')
end, { cooldown = 1500 })

Veyl.RegisterCallback('standingCreate', function(src, citizenid, number, amount, days, note)
    local _, err = session(src)
    if err then return err end
    local to = cidByNumber(number)
    if not to or to == citizenid then return Veyl.Err('NOT_FOUND', 'No phone with that number') end
    amount, days = math.floor(tonumber(amount) or 0), math.floor(tonumber(days) or 0)
    if amount < 1 or amount > C.Standing.MaxAmount then return Veyl.Err('INVALID_INPUT', ('Amount $1 - $%d'):format(C.Standing.MaxAmount)) end
    if days < 1 or days > 30 then return Veyl.Err('INVALID_INPUT', 'Every 1 to 30 days') end
    if (MySQL.scalar.await('SELECT COUNT(*) FROM veyl_phone_standing WHERE citizenid = ? AND active = 1', { citizenid }) or 0) >= C.Standing.Max then
        return Veyl.Err('LIMIT', ('Up to %d standing orders'):format(C.Standing.Max))
    end
    local label = MySQL.scalar.await('SELECT display_name FROM veyl_phone_accounts WHERE citizenid = ?', { to }) or number
    MySQL.insert.await([[INSERT INTO veyl_phone_standing (citizenid, to_cid, to_label, amount, every_days, note, next_at)
        VALUES (?, ?, ?, ?, ?, ?, NOW() + INTERVAL ? DAY)]], { citizenid, to, label, amount, days, Phone.Clean(note, 80), days })
    return Veyl.Ok(nil, ('$%d to %s every %d day%s'):format(amount, label, days, days == 1 and '' or 's'))
end, { cooldown = 2000 })

Veyl.RegisterCallback('standingCancel', function(src, citizenid, id)
    local _, err = session(src)
    if err then return err end
    MySQL.update.await('UPDATE veyl_phone_standing SET active = 0 WHERE id = ? AND citizenid = ?', { tonumber(id) or 0, citizenid })
    return Veyl.Ok(nil, 'Standing order cancelled')
end, { cooldown = 500 })

-- Due standing orders are paid every few minutes (each run has its own operation id: never paid twice).
CreateThread(function()
    while true do
        Wait(5 * 60 * 1000)
        for _, r in ipairs(MySQL.query.await('SELECT *, UNIX_TIMESTAMP(next_at) AS due FROM veyl_phone_standing WHERE active = 1 AND next_at <= NOW() LIMIT 50') or {}) do
            local res = core('TransferMoney', r.citizenid, 'bank', r.to_cid, 'bank', r.amount, ('Standing order: %s'):format(r.note or r.to_label), ('standing:%d:%d'):format(r.id, r.due))
            if res.ok or res.code == 'DUPLICATE_OPERATION' then
                MySQL.update.await('UPDATE veyl_phone_standing SET next_at = next_at + INTERVAL every_days DAY, failures = 0 WHERE id = ?', { r.id })
            else
                local fails = r.failures + 1
                MySQL.update.await('UPDATE veyl_phone_standing SET failures = ?, active = ?, next_at = NOW() + INTERVAL 1 DAY WHERE id = ?', { fails, fails >= 3 and 0 or 1, r.id })
                Notify.Send(r.citizenid, { app = 'bills', title = 'Standing order failed', body = ('$%d to %s%s'):format(r.amount, r.to_label, fails >= 3 and ' (cancelled after 3 tries)' or ''), route = 'bills' })
            end
        end
    end
end)

---------------------------------------------------------------------------
-- Music speaker: nearby players hear the same station, louder the closer they are
---------------------------------------------------------------------------
local speakers = {} -- [src] = station id
Veyl.RegisterCallback('speakerPlay', function(src, _, station)
    local _, err = session(src)
    if err then return err end
    local ok = station == 'veyl'
    for _, s in ipairs(C.Music.Stations) do if s.id == station then ok = true end end
    if not ok then return Veyl.Err('NOT_FOUND', 'Unknown station') end
    speakers[src] = station
    TriggerClientEvent('veyl_phone:speaker', -1, src, station)
    return Veyl.Ok(nil, 'Playing out loud')
end, { cooldown = 2000 })

Veyl.RegisterCallback('speakerStop', function(src)
    speakers[src] = nil
    TriggerClientEvent('veyl_phone:speaker', -1, src, nil)
    return Veyl.Ok()
end, { cooldown = 500 })

AddEventHandler('playerDropped', function()
    local src = source
    if speakers[src] then speakers[src] = nil TriggerClientEvent('veyl_phone:speaker', -1, src, nil) end
end)

---------------------------------------------------------------------------
-- News (Weazel News)
---------------------------------------------------------------------------
local function isReporter(src)
    local pd = Veyl.GetPlayerData(src)
    if not pd or not pd.job.onduty then return false end
    for _, j in ipairs(C.News.Jobs) do if pd.job.name == j then return true, pd end end
    return false
end

Veyl.RegisterCallback('newsList', function(src)
    local _, err = session(src)
    if err then return err end
    local rows = MySQL.query.await('SELECT id, author, title, body, breaking, UNIX_TIMESTAMP(created_at) AS at FROM veyl_phone_news ORDER BY id DESC LIMIT 40') or {}
    return Veyl.Ok({ articles = rows, reporter = isReporter(src) })
end, { cooldown = 500 })

Veyl.RegisterCallback('newsPost', function(src, citizenid, title, body, breaking)
    local _, err = session(src)
    if err then return err end
    local ok, pd = isReporter(src)
    if not ok then return Veyl.Err('NO_PERMISSION', 'Only on-duty Weazel News reporters can publish') end
    title, body = Phone.Clean(title, 120), tostring(body or ''):sub(1, 4000)
    if not title or #title < 5 or #body < 20 then return Veyl.Err('INVALID_INPUT', 'Write a headline and a story') end
    MySQL.insert.await('INSERT INTO veyl_phone_news (author_cid, author, title, body, breaking) VALUES (?, ?, ?, ?, ?)', { citizenid, charName(pd), title, body, breaking == true and 1 or 0 })
    if breaking == true then
        for _, p in ipairs(GetPlayers()) do
            local cid = Veyl.GetCitizenId(tonumber(p))
            if cid then Notify.Send(cid, { app = 'news', title = 'BREAKING · Weazel News', body = title, route = 'news' }) end
        end
    end
    Veyl.Audit(src, 'news_post', { title = title, breaking = breaking == true })
    return Veyl.Ok(nil, 'Published')
end, { cooldown = 10000 })

---------------------------------------------------------------------------
-- Racing: tracks are recorded checkpoint by checkpoint; races are hosted, joined nearby, timed on the server
---------------------------------------------------------------------------
local races, raceSeq = {}, 0 -- [id] = { id, track, host, hostName, racers = { [src] = { name, next, done } }, state, startAt }

local function trackRow(id)
    local t = MySQL.single.await('SELECT id, name, creator, checkpoints FROM veyl_phone_race_tracks WHERE id = ?', { tonumber(id) or 0 })
    if t then t.checkpoints = json.decode(t.checkpoints) or {} end
    return t
end

Veyl.RegisterCallback('raceData', function(src)
    local _, err = session(src)
    if err then return err end
    local tracks = MySQL.query.await([[SELECT t.id, t.name, t.creator, JSON_LENGTH(t.checkpoints) AS points,
        (SELECT MIN(ms) FROM veyl_phone_race_results r WHERE r.track_id = t.id) AS best FROM veyl_phone_race_tracks t ORDER BY t.id DESC LIMIT 50]]) or {}
    local open = {}
    for id, r in pairs(races) do
        if r.state == 'lobby' then
            local n = 0
            for _ in pairs(r.racers) do n = n + 1 end
            open[#open + 1] = { id = id, track = r.track.name, host = r.hostName, racers = n, mine = r.host == src, joined = r.racers[src] ~= nil }
        end
    end
    return Veyl.Ok({ tracks = tracks, open = open })
end, { cooldown = 500 })

Veyl.RegisterCallback('raceBoard', function(src, _, trackId)
    local _, err = session(src)
    if err then return err end
    return Veyl.Ok(MySQL.query.await('SELECT name, MIN(ms) AS ms FROM veyl_phone_race_results WHERE track_id = ? GROUP BY citizenid, name ORDER BY ms LIMIT 10', { tonumber(trackId) or 0 }) or {})
end, { cooldown = 500 })

Veyl.RegisterCallback('raceTrackSave', function(src, citizenid, name, points)
    local _, err = session(src)
    if err then return err end
    name = Phone.Clean(name, 40)
    if not name or #name < 3 then return Veyl.Err('INVALID_INPUT', 'Name the track') end
    if type(points) ~= 'table' or #points < 2 or #points > 40 then return Veyl.Err('INVALID_INPUT', 'A track needs 2 to 40 checkpoints') end
    local clean = {}
    for _, p in ipairs(points) do
        if not (tonumber(p.x) and tonumber(p.y) and tonumber(p.z)) then return Veyl.Err('INVALID_INPUT', 'Bad checkpoint') end
        clean[#clean + 1] = { x = tonumber(p.x), y = tonumber(p.y), z = tonumber(p.z) }
    end
    local pd = Veyl.GetPlayerData(src)
    MySQL.insert.await('INSERT INTO veyl_phone_race_tracks (name, creator_cid, creator, checkpoints) VALUES (?, ?, ?, ?)', { name, citizenid, charName(pd), json.encode(clean) })
    return Veyl.Ok(nil, 'Track saved')
end, { cooldown = 3000 })

Veyl.RegisterCallback('raceHost', function(src, _, trackId)
    local _, err = session(src)
    if err then return err end
    local t = trackRow(trackId)
    if not t then return Veyl.Err('NOT_FOUND', 'Unknown track') end
    for _, r in pairs(races) do if r.host == src and r.state ~= 'done' then return Veyl.Err('INVALID_STATE', 'You are already hosting a race') end end
    raceSeq = raceSeq + 1
    local pd = Veyl.GetPlayerData(src)
    races[raceSeq] = { id = raceSeq, track = t, host = src, hostName = charName(pd), racers = { [src] = { name = charName(pd), next = 1 } }, state = 'lobby', created = os.time() }
    return Veyl.Ok({ id = raceSeq, start = t.checkpoints[1] }, 'Race open: others near the start can join from their Racing app')
end, { cooldown = 3000 })

Veyl.RegisterCallback('raceJoin', function(src, _, id)
    local _, err = session(src)
    if err then return err end
    local r = races[tonumber(id) or 0]
    if not r or r.state ~= 'lobby' then return Veyl.Err('NOT_FOUND', 'That race is not open') end
    local p, pc = r.track.checkpoints[1], Veyl.GetPlayerCoords(src)
    if not pc or #(pc - vector3(p.x, p.y, p.z)) > C.Racing.JoinRadius then return Veyl.Err('TOO_FAR', 'Get to the start line first') end
    r.racers[src] = { name = charName(Veyl.GetPlayerData(src)), next = 1 }
    return Veyl.Ok({ start = p }, 'Joined. Wait for the host to start.')
end, { cooldown = 1000 })

Veyl.RegisterCallback('raceStart', function(src, _, id)
    local r = races[tonumber(id) or 0]
    if not r or r.host ~= src or r.state ~= 'lobby' then return Veyl.Err('NO_PERMISSION', 'Only the host can start it') end
    r.state = 'running'
    r.startAt = GetGameTimer() + 5000
    for s in pairs(r.racers) do TriggerClientEvent('veyl_phone:race', s, { id = r.id, name = r.track.name, checkpoints = r.track.checkpoints, countdown = 5 }) end
    return Veyl.Ok(nil, 'Starting')
end, { cooldown = 2000 })

Veyl.RegisterCallback('raceCheckpoint', function(src, citizenid, id, index)
    local r = races[tonumber(id) or 0]
    local me = r and r.racers[src]
    if not me or r.state ~= 'running' or me.done or tonumber(index) ~= me.next then return Veyl.Err('INVALID_STATE', 'Not in this race') end
    if GetGameTimer() < r.startAt then return Veyl.Err('TOO_FAST', 'Jumped the start') end
    local p, pc = r.track.checkpoints[me.next], Veyl.GetPlayerCoords(src)
    if not pc or #(pc - vector3(p.x, p.y, p.z)) > 25.0 then return Veyl.Err('TOO_FAR', 'Missed the checkpoint') end
    me.next = me.next + 1
    if me.next > #r.track.checkpoints then
        me.done = GetGameTimer() - r.startAt
        MySQL.insert.await('INSERT INTO veyl_phone_race_results (track_id, citizenid, name, ms) VALUES (?, ?, ?, ?)', { r.track.id, citizenid, me.name, me.done })
        local place = 0
        for _, o in pairs(r.racers) do if o.done and o.done <= me.done then place = place + 1 end end
        local allDone = true
        for _, o in pairs(r.racers) do if not o.done then allDone = false end end
        if allDone then r.state = 'done' end
        return Veyl.Ok({ finished = true, ms = me.done, place = place }, ('Finished #%d in %.2fs'):format(place, me.done / 1000))
    end
    return Veyl.Ok({ finished = false, next = me.next })
end, { cooldown = 100 })

CreateThread(function()
    while true do
        Wait(60000)
        for id, r in pairs(races) do if os.time() - r.created > 3600 then races[id] = nil end end
    end
end)

---------------------------------------------------------------------------
-- Tablet item: a bigger screen for the MDT, dispatch and real estate
---------------------------------------------------------------------------
CreateThread(function()
    while GetResourceState('veyl_inventory') ~= 'started' do Wait(1000) end
    Wait(1000)
    exports.veyl_inventory:RegisterUseHandler('phone_tablet', function(ctx) TriggerClientEvent('veyl_phone:tablet', ctx.source) end)
end)
