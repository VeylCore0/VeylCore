-- veyl_prison server: sentences that persist, the countdown, yard work and controlled release.
--
-- A sentence is a row in veyl_prison_sentences (citizenid, months, remaining). It counts down only while the prisoner
-- is online. It ends when remaining reaches 0, or when police / staff release them. Nothing else releases a prisoner:
-- leaving the grounds, dying or reconnecting puts them back inside.

local C = PrisonConfig
local inmates = {} -- [src] = { citizenid, remaining, months, lastWork }

Veyl.Startup({ 'veyl_core' }, function()
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

function LoadInmate(src)
    local cid = src and Veyl.GetCitizenId(src)
    if not cid then return end
    local row = MySQL.single.await('SELECT months, remaining FROM veyl_prison_sentences WHERE citizenid = ?', { cid })
    if row and row.remaining > 0 then
        inmates[src] = { citizenid = cid, remaining = row.remaining, months = row.months, lastWork = 0 }
        push(src)
        TriggerClientEvent('veyl_prison:placeInside', src, C.Inside)
    elseif row then
        MySQL.update.await('DELETE FROM veyl_prison_sentences WHERE citizenid = ?', { cid })
    end
end

local function release(src, cid, by)
    if not MySQL.scalar.await('SELECT 1 FROM veyl_prison_sentences WHERE citizenid = ?', { cid }) then return false end
    MySQL.insert.await([[INSERT INTO veyl_prison_history (citizenid, months, reason, officer, sentenced_at, released_by)
        SELECT citizenid, months, reason, officer, created_at, ? FROM veyl_prison_sentences WHERE citizenid = ?]], { tostring(by or ''):sub(1, 64), cid })
    MySQL.update.await('DELETE FROM veyl_prison_sentences WHERE citizenid = ?', { cid })
    if src then
        inmates[src] = nil
        push(src)
        TriggerClientEvent('veyl_prison:released', src, C.Release)
    end
    return true
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
    local row = MySQL.single.await('SELECT months, remaining, reason FROM veyl_prison_sentences WHERE citizenid = ?', { citizenid })
    return row and { months = row.months, remaining = row.remaining, reason = row.reason } or nil
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
                if out and not downed then
                    TriggerClientEvent('veyl_prison:placeInside', src, C.Inside)
                    Veyl.Notify(src, 'You cannot leave the prison grounds.', 'error')
                end
                if tick then
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
