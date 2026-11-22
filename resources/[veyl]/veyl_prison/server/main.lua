-- veyl_prison server: sentences that persist, the countdown, yard work and controlled release.
--
-- A sentence is a row in veyl_prison_sentences (citizenid, months, remaining). It counts down only while the prisoner
-- is online. It ends when remaining reaches 0, or when police / staff release them. Nothing else releases a prisoner:
-- leaving the grounds, dying or reconnecting puts them back inside.

local C = PrisonConfig
local inmates = {} -- [src] = { citizenid, remaining, months, lastWork }

Veyl.Startup({ 'veyl_core', 'veyl_inventory' }, function()
    local ok = Veyl.Migrate({
        { id = '001_sentences', sql = {
            [[CREATE TABLE IF NOT EXISTS veyl_prison_sentences (
                citizenid VARCHAR(16) NOT NULL,
                months INT UNSIGNED NOT NULL,
                remaining INT UNSIGNED NOT NULL,
                reason VARCHAR(160) NULL,
                officer VARCHAR(64) NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (citizenid)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS veyl_prison_history (
                id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                citizenid VARCHAR(16) NOT NULL,
                months INT UNSIGNED NOT NULL,
                reason VARCHAR(160) NULL,
                officer VARCHAR(64) NULL,
                sentenced_at TIMESTAMP NULL,
                released_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                released_by VARCHAR(64) NULL,
                PRIMARY KEY (id),
                KEY idx_cid (citizenid)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        } },
        { id = '002_belongings_escape', sql = {
            [[ALTER TABLE veyl_prison_sentences ADD COLUMN IF NOT EXISTS belongings LONGTEXT NULL,
                ADD COLUMN IF NOT EXISTS escaped TINYINT(1) NOT NULL DEFAULT 0,
                ADD COLUMN IF NOT EXISTS updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP]],
        } },
    })
    if not ok then return false end
    for _, s in ipairs(GetPlayers()) do LoadInmate(tonumber(s)) end
    return true
end)

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function charName(pd) return pd and ('%s %s'):format(pd.charinfo.firstname or '', pd.charinfo.lastname or '') or 'Unknown' end

local function isOfficer(src)
    local pd = Veyl.GetPlayerData(src)
    if not pd or not pd.job.onduty then return nil end
    for _, j in ipairs(C.PoliceJobs) do if pd.job.name == j then return pd end end
    return nil
end

local function push(src)
    local i = inmates[src]
    TriggerClientEvent('veyl_prison:state', src, i and { remaining = i.remaining, months = i.months, inside = C.Inside, grounds = C.Grounds,
        secondsPerMonth = C.SecondsPerMonth, work = C.Work } or nil)
    exports.veyl_core:SetMetadata(src, 'jailtime', i and i.remaining or 0)
end

local function decode(v)
    if type(v) == 'table' then return v end
    local ok, t = pcall(json.decode, v or '[]')
    return ok and type(t) == 'table' and t or {}
end

--- Hands confiscated belongings back. Returns the items that did not fit (left in the record for next time).
local function returnBelongings(src, cid)
    local list = decode(MySQL.scalar.await('SELECT belongings FROM veyl_prison_sentences WHERE citizenid = ?', { cid }))
    local failed = {}
    for _, it in ipairs(list) do
        local ok = exports.veyl_inventory:AddItem(src, it.name, it.count, it.metadata)
        if not ok then failed[#failed + 1] = it end
    end
    if #list > 0 then
        Veyl.Notify(src, #failed == 0 and 'Your belongings were returned.'
            or ('Some belongings did not fit (%d). Make room and log in again to collect them.'):format(#failed), #failed == 0 and 'success' or 'warning', 8000)
    end
    return failed
end

--- Archives and removes a finished sentence (keeps it with remaining = 0 when belongings are still owed).
local function finish(cid, by, failed)
    MySQL.insert.await([[INSERT INTO veyl_prison_history (citizenid, months, reason, officer, sentenced_at, released_by)
        SELECT citizenid, months, reason, officer, created_at, ? FROM veyl_prison_sentences WHERE citizenid = ? AND remaining > 0]], { tostring(by or ''):sub(1, 64), cid })
    if failed and #failed > 0 then
        MySQL.update.await('UPDATE veyl_prison_sentences SET remaining = 0, escaped = 0, belongings = ? WHERE citizenid = ?', { json.encode(failed), cid })
    else
        MySQL.update.await('DELETE FROM veyl_prison_sentences WHERE citizenid = ?', { cid })
    end
end

function LoadInmate(src)
    local cid = src and Veyl.GetCitizenId(src)
    if not cid then return end
    local row = MySQL.single.await([[SELECT months, remaining, escaped, UNIX_TIMESTAMP(updated_at) AS updated FROM veyl_prison_sentences
        WHERE citizenid = ?]], { cid })
    if not row then return end
    if row.escaped == 1 then
        Veyl.Notify(src, 'You escaped from Bolingbroke. The police are looking for you.', 'warning', 8000)
        return
    end
    local remaining = row.remaining
    if remaining > 0 and C.CountOffline and row.updated then
        remaining = math.max(0, remaining - math.floor((os.time() - row.updated) / C.SecondsPerMonth))
        MySQL.update.await('UPDATE veyl_prison_sentences SET remaining = ? WHERE citizenid = ?', { math.max(remaining, 0), cid })
    end
    if remaining > 0 then
        inmates[src] = { citizenid = cid, remaining = remaining, months = row.months, lastWork = 0 }
        push(src)
        TriggerClientEvent('veyl_prison:placeInside', src, C.Inside)
    else
        -- Released (or served) while away: hand back what is owed.
        local failed = returnBelongings(src, cid)
        finish(cid, row.remaining > 0 and 'served offline' or nil, failed)
        if row.remaining > 0 then Veyl.Notify(src, 'Your sentence ended while you were away.', 'success', 8000) end
    end
end

local function release(src, cid, by)
    if not MySQL.scalar.await('SELECT 1 FROM veyl_prison_sentences WHERE citizenid = ? AND remaining > 0', { cid }) then return false end
    if not src then
        -- Offline: they collect their belongings when they next log in.
        MySQL.insert.await([[INSERT INTO veyl_prison_history (citizenid, months, reason, officer, sentenced_at, released_by)
            SELECT citizenid, months, reason, officer, created_at, ? FROM veyl_prison_sentences WHERE citizenid = ?]], { tostring(by or ''):sub(1, 64), cid })
        MySQL.update.await('UPDATE veyl_prison_sentences SET remaining = 0, escaped = 0 WHERE citizenid = ?', { cid })
        return true
    end
    inmates[src] = nil
    push(src)
    TriggerClientEvent('veyl_prison:released', src, C.Release)
    SetTimeout(2500, function()
        if not GetPlayerName(src) then return end
        finish(cid, by, returnBelongings(src, cid))
    end)
    return true
end

--- Takes everything but KeepItems. Returns the list taken.
local function confiscate(src)
    local taken = {}
    for _, it in pairs(exports.veyl_inventory:GetInventoryItems(src) or {}) do
        if it and not C.KeepItems[it.name] then
            local ok = exports.veyl_inventory:RemoveItem(src, it.name, it.count, it.metadata)
            if ok then taken[#taken + 1] = { name = it.name, count = it.count, metadata = it.metadata } end
        end
    end
    return taken
end

---------------------------------------------------------------------------
-- Sentencing (MDT export and /jail)
---------------------------------------------------------------------------
--- Sentence(officerSrc, citizenid, months, reason) -> Veyl.Ok / Veyl.Err. The person must be online.
local function sentence(officerSrc, citizenid, months, reason)
    local opd = officerSrc == 0 and { charinfo = { firstname = 'Staff', lastname = '' } } or isOfficer(officerSrc)
    if not opd and not (Veyl.HasPermission(officerSrc, 'prison.manage') or Veyl.HasPermission(officerSrc, 'admin')) then
        return Veyl.Err('NO_PERMISSION', 'You need to be an on-duty officer')
    end
    opd = opd or Veyl.GetPlayerData(officerSrc)
    months = math.floor(tonumber(months) or 0)
    if months < 1 or months > C.MaxMonths then return Veyl.Err('INVALID_INPUT', ('Months must be 1 - %d'):format(C.MaxMonths)) end
    if type(citizenid) ~= 'string' then return Veyl.Err('INVALID_INPUT', 'Unknown person') end
    local target = exports.veyl_core:GetSourceByCitizenId(citizenid)
    if not target then return Veyl.Err('NOT_FOUND', 'They must be in the city to be sentenced') end
    if inmates[target] then return Veyl.Err('INVALID_STATE', 'They are already serving a sentence') end
    reason = type(reason) == 'string' and reason:gsub('[%c]', ''):sub(1, 160) or nil
    local officerName = charName(opd)
    MySQL.query.await([[INSERT INTO veyl_prison_sentences (citizenid, months, remaining, reason, officer) VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE months = VALUES(months), remaining = VALUES(remaining), reason = VALUES(reason), officer = VALUES(officer), created_at = NOW()]],
        { citizenid, months, months, reason, officerName })
    MySQL.update.await('UPDATE veyl_prison_sentences SET escaped = 0 WHERE citizenid = ?', { citizenid })
    if C.Confiscate then
        local taken = confiscate(target)
        if #taken > 0 then
            -- Keep anything still owed from an earlier sentence.
            local owed = decode(MySQL.scalar.await('SELECT belongings FROM veyl_prison_sentences WHERE citizenid = ?', { citizenid }))
            for _, it in ipairs(taken) do owed[#owed + 1] = it end
            MySQL.update.await('UPDATE veyl_prison_sentences SET belongings = ? WHERE citizenid = ?', { json.encode(owed), citizenid })
            Veyl.Notify(target, ('%d item%s taken into storage until your release.'):format(#taken, #taken == 1 and ' was' or 's were'), 'info', 7000)
        end
    end
    inmates[target] = { citizenid = citizenid, remaining = months, months = months, lastWork = 0 }
    if GetResourceState('veyl_police') == 'started' then pcall(function() exports.veyl_police:SetCuffed(target, false) end) end
    push(target)
    TriggerClientEvent('veyl_prison:placeInside', target, C.Inside)
    Veyl.Notify(target, ('You were sentenced to %d months%s.'):format(months, reason and (' for ' .. reason) or ''), 'warning', 9000)
    Veyl.Audit(officerSrc, 'prison_sentence', { target = citizenid, months = months, reason = reason })
    local tpd = Veyl.GetPlayerData(target)
    return Veyl.Ok(nil, ('%s sentenced to %d months'):format(charName(tpd), months))
end
exports('Sentence', sentence)

exports('GetSentence', function(citizenid)
    local row = MySQL.single.await('SELECT months, remaining, reason, escaped FROM veyl_prison_sentences WHERE citizenid = ? AND remaining > 0', { citizenid })
    return row and { months = row.months, remaining = row.remaining, reason = row.reason, escaped = row.escaped == 1 } or nil
end)

exports('Release', function(citizenid, by)
    return release(exports.veyl_core:GetSourceByCitizenId(citizenid), citizenid, by or GetInvokingResource())
end)

RegisterCommand('jail', function(src, args)
    local target, months = tonumber(args[1]), tonumber(args[2])
    local reason = table.concat(args, ' ', 3)
    local function reply(msg, kind) if src == 0 then print('[veyl_prison] ' .. msg) else Veyl.Notify(src, msg, kind) end end
    if not target or not months then return reply('Usage: /jail <id> <months> <charges>', 'error') end
    local cid = Veyl.GetCitizenId(target)
    if not cid then return reply('Nobody with that id is in the city', 'error') end
    if src ~= 0 and isOfficer(src) then
        local a, b = Veyl.GetPlayerCoords(src), Veyl.GetPlayerCoords(target)
        if not a or not b or #(a - b) > C.JailDistance then return reply('Stand next to them', 'error') end
    end
    local res = sentence(src, cid, months, reason ~= '' and reason or nil)
    reply(res.message or (res.ok and 'Sentenced' or 'Failed'), res.ok and 'success' or 'error')
end, false)

RegisterCommand('release', function(src, args)
    local function reply(msg, kind) if src == 0 then print('[veyl_prison] ' .. msg) else Veyl.Notify(src, msg, kind) end end
    local allowed = src == 0 or isOfficer(src) or Veyl.HasPermission(src, 'prison.manage') or Veyl.HasPermission(src, 'admin')
    if not allowed then return reply('You cannot release prisoners', 'error') end
    local target = tonumber(args[1])
    local cid = target and Veyl.GetCitizenId(target)
    if not cid then return reply('Usage: /release <id>', 'error') end
    local by = src == 0 and 'console' or charName(Veyl.GetPlayerData(src))
    if not release(target, cid, by) then return reply('They are not serving a sentence', 'error') end
    Veyl.Notify(target, 'You have been released.', 'success')
    Veyl.Audit(src, 'prison_release', { target = cid })
    reply('Released', 'success')
end, false)

---------------------------------------------------------------------------
-- Countdown (online time only) and escape checks
---------------------------------------------------------------------------
CreateThread(function()
    local acc = 0
    while true do
        Wait(5000)
        acc = acc + 5
        local tick = acc >= C.SecondsPerMonth
        if tick then acc = 0 end
        for src, i in pairs(inmates) do
            if not GetPlayerName(src) then
                inmates[src] = nil
            else
                local pc = Veyl.GetPlayerCoords(src)
                local out = pc and #(vector2(pc.x, pc.y) - vector2(C.Grounds.center.x, C.Grounds.center.y)) > C.Grounds.radius + 10.0
                local downed = Player(src).state.medical ~= nil
                if out and not downed and C.AllowEscape then
                    Escape(src, i, pc)
                elseif out and not downed then
                    TriggerClientEvent('veyl_prison:placeInside', src, C.Inside)
                    Veyl.Notify(src, 'You cannot leave the prison grounds.', 'error')
                end
                if tick and inmates[src] then
                    i.remaining = math.max(0, i.remaining - 1)
                    MySQL.update('UPDATE veyl_prison_sentences SET remaining = ? WHERE citizenid = ?', { i.remaining, i.citizenid })
                    if i.remaining == 0 then
                        release(src, i.citizenid, 'served')
                        Veyl.Notify(src, 'You have served your sentence. You are free to go.', 'success', 8000)
                    else
                        push(src)
                    end
                end
            end
        end
    end
end)

---------------------------------------------------------------------------
-- Yard work
---------------------------------------------------------------------------
local working = {} -- [src] = { spot, at }

Veyl.RegisterCallback('workStart', function(src, _, spot)
    local i = inmates[src]
    if not i then return Veyl.Err('INVALID_STATE', 'Only prisoners work the yard') end
    local s = C.Work.Spots[tonumber(spot) or 0]
    if not s then return Veyl.Err('NOT_FOUND', 'Unknown job') end
    local pc = Veyl.GetPlayerCoords(src)
    if not pc or #(pc - s.coords) > 3.0 then return Veyl.Err('TOO_FAR', 'Move closer') end
    local wait = i.lastWork + C.Work.CooldownSeconds - os.time()
    if wait > 0 then return Veyl.Err('RATE_LIMITED', ('Take a break: %ds'):format(wait)) end
    working[src] = { spot = tonumber(spot), at = GetGameTimer() }
    return Veyl.Ok({ seconds = C.Work.Seconds })
end, { cooldown = 1000 })

Veyl.RegisterCallback('workFinish', function(src)
    local w, i = working[src], inmates[src]
    working[src] = nil
    if not w or not i then return Veyl.Err('INVALID_STATE', 'Start again') end
    if GetGameTimer() - w.at < C.Work.Seconds * 1000 - 600 then return Veyl.Err('TOO_FAST', 'You stopped too early') end
    local pc = Veyl.GetPlayerCoords(src)
    if not pc or #(pc - C.Work.Spots[w.spot].coords) > 3.0 then return Veyl.Err('TOO_FAR', 'You walked away') end
    i.lastWork = os.time()
    i.remaining = math.max(1, i.remaining - C.Work.MonthsOff)
    MySQL.update.await('UPDATE veyl_prison_sentences SET remaining = ? WHERE citizenid = ?', { i.remaining, i.citizenid })
    push(src)
    return Veyl.Ok(nil, ('Good work. %d month%s off: %d left.'):format(C.Work.MonthsOff, C.Work.MonthsOff == 1 and '' or 's', i.remaining))
end, { cooldown = 500 })

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
AddEventHandler('VeylCore:Server:OnPlayerSpawned', function(src) LoadInmate(tonumber(src)) end)
AddEventHandler('VeylCore:Server:OnPlayerUnload', function(src) inmates[src] = nil working[src] = nil end)
AddEventHandler('playerDropped', function() inmates[source] = nil working[source] = nil end)

-- After a hospital respawn a prisoner goes straight back inside.
AddEventHandler('veyl:playerRespawned', function(src)
    if inmates[src] then SetTimeout(1500, function() if inmates[src] then TriggerClientEvent('veyl_prison:placeInside', src, C.Inside) end end) end
end)

---------------------------------------------------------------------------
-- Escapes (AllowEscape = true): dispatch call, MDT warrant, the sentence waits for the arrest
---------------------------------------------------------------------------
function Escape(src, i, pc)
    inmates[src] = nil
    MySQL.update.await('UPDATE veyl_prison_sentences SET escaped = 1, remaining = ? WHERE citizenid = ?', { i.remaining, i.citizenid })
    push(src)
    local pd = Veyl.GetPlayerData(src)
    local who = charName(pd)
    if GetResourceState('veyl_dispatch') == 'started' then
        pcall(function()
            exports.veyl_dispatch:Alert({ services = { 'police' }, code = '10-98', title = 'Prison break', priority = 1, coords = pc,
                street = 'Bolingbroke Penitentiary', message = ('%s escaped with %d months left'):format(who, i.remaining), blip = { sprite = 188, colour = 1, scale = 1.3 } })
        end)
    end
    if GetResourceState('veyl_mdt') == 'started' then
        MySQL.insert.await('INSERT INTO veyl_mdt_warrants (citizenid, reason, issued_by) VALUES (?, ?, ?)',
            { i.citizenid, ('Escaped from Bolingbroke (%d months left)'):format(i.remaining), 'Bolingbroke Penitentiary' })
    end
    Veyl.Notify(src, 'You escaped! The police have been alerted.', 'warning', 8000)
    Veyl.Audit(src, 'prison_escape', { remaining = i.remaining })
end

---------------------------------------------------------------------------
-- Canteen
---------------------------------------------------------------------------
local lastMeal = {}
Veyl.RegisterCallback('canteen', function(src, citizenid)
    if not inmates[src] then return Veyl.Err('INVALID_STATE', 'The canteen is for inmates') end
    local pc = Veyl.GetPlayerCoords(src)
    if not pc or #(pc - C.Canteen.coords) > 3.5 then return Veyl.Err('TOO_FAR', 'Go to the canteen') end
    local wait = (lastMeal[citizenid] or 0) + C.Canteen.cooldownSeconds - os.time()
    if wait > 0 then return Veyl.Err('RATE_LIMITED', ('Next meal in %d min'):format(math.ceil(wait / 60))) end
    lastMeal[citizenid] = os.time()
    for _, it in ipairs(C.Canteen.items) do exports.veyl_inventory:AddItem(src, it.item, it.count or 1) end
    return Veyl.Ok(nil, 'You got a tray of food')
end, { cooldown = 1000 })
