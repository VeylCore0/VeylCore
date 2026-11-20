-- veyl_jobs server: job membership and duty are owned here; money moves only through veyl_banking.

local active = {} -- [charId] = { src, job, grade, onDuty }

Veyl.Startup({ 'veyl_core', 'veyl_banking' }, function()
    return Veyl.Migrate({
        {
            id = '001_job_assignments',
            sql = {
                [[CREATE TABLE IF NOT EXISTS veyl_job_assignments (
                    character_id INT UNSIGNED NOT NULL,
                    job VARCHAR(32) NOT NULL,
                    grade TINYINT UNSIGNED NOT NULL DEFAULT 0,
                    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                    PRIMARY KEY (character_id)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            },
        },
    })
end)

local function gradeInfo(job, grade)
    local j = JobsConfig.Jobs[job]
    return j and j.grades[grade] or nil
end

local function publicJob(a)
    local j = JobsConfig.Jobs[a.job]
    local g = gradeInfo(a.job, a.grade)
    return {
        name = a.job, label = j and j.label or a.job, grade = a.grade, gradeLabel = g and g.label or tostring(a.grade),
        onDuty = a.onDuty, boss = g and g.boss == true or false,
    }
end

local function push(charId)
    local a = active[charId]
    if not a or not GetPlayerName(a.src) then return end
    local pub = publicJob(a)
    Player(a.src).state:set('veylJob', pub, true)
    TriggerEvent('veyl_jobs:updated', a.src, charId, pub)
end

AddEventHandler('veyl:characterLoaded', function(src, charId)
    CreateThread(function()
        local row = MySQL.single.await('SELECT job, grade FROM veyl_job_assignments WHERE character_id = ?', { charId })
        if Veyl.GetCharacterId(src) ~= charId then return end
        local job, grade = JobsConfig.DefaultJob, 0
        if row and gradeInfo(row.job, row.grade) then job, grade = row.job, row.grade end
        local j = JobsConfig.Jobs[job]
        active[charId] = { src = src, job = job, grade = grade, onDuty = j.defaultDuty == true }
        push(charId)
    end)
end)

AddEventHandler('veyl:characterUnloading', function(src, charId)
    active[charId] = nil
    if GetPlayerName(src) then Player(src).state:set('veylJob', nil, true) end
end)

---------------------------------------------------------------------------
-- Exports
---------------------------------------------------------------------------
exports('GetJob', function(charId)
    local a = active[tonumber(charId)]
    return a and publicJob(a) or nil
end)

exports('IsOnDuty', function(charId, jobName)
    local a = active[tonumber(charId)]
    return a ~= nil and a.onDuty and (jobName == nil or a.job == jobName)
end)

--- SetJob(characterId, job, grade, reason) — persisted. Callers must have validated eligibility.
Veyl.AsyncExport('SetJob', function(charId, job, grade, reason)
    if not Veyl.IsReady() then return Veyl.Err('NOT_READY', 'Jobs not ready') end
    grade = tonumber(grade) or 0
    if not gradeInfo(job, grade) then return Veyl.Err('INVALID_INPUT', 'Unknown job or grade') end
    MySQL.query.await([[INSERT INTO veyl_job_assignments (character_id, job, grade) VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE job = VALUES(job), grade = VALUES(grade)]], { charId, job, grade })
    local a = active[charId]
    if a then
        a.job, a.grade = job, grade
        a.onDuty = JobsConfig.Jobs[job].defaultDuty == true
        push(charId)
    end
    exports.veyl_core:Audit(a and a.src or nil, GetInvokingResource() or 'veyl_jobs', 'job_set',
        { characterId = charId, job = job, grade = grade, reason = reason })
    return Veyl.Ok(publicJob(a or { job = job, grade = grade, onDuty = false }))
end)

local function setDuty(src, enabled)
    local charId = Veyl.GetCharacterId(src)
    local a = charId and active[charId]
    if not a then return Veyl.Err('NO_CHARACTER', 'No character loaded') end
    if a.job == JobsConfig.DefaultJob then return Veyl.Err('INVALID_STATE', 'You do not have a job') end
    a.onDuty = enabled == true
    push(charId)
    return Veyl.Ok(publicJob(a), a.onDuty and 'You are now on duty' or 'You are now off duty')
end

exports('SetDuty', setDuty)

Veyl.RegisterCallback('toggleDuty', function(src, charId)
    local a = active[charId]
    if not a then return Veyl.Err('NOT_READY', 'Job not loaded') end
    return setDuty(src, not a.onDuty)
end, { cooldown = 3000 })

Veyl.RegisterCallback('quit', function(src, charId)
    local a = active[charId]
    if not a or a.job == JobsConfig.DefaultJob then return Veyl.Err('INVALID_STATE', 'You do not have a job') end
    if not JobsConfig.Jobs[a.job].open then return Veyl.Err('NO_PERMISSION', 'Ask your supervisor to release you') end
    local res = Veyl.Await('veyl_jobs', 'SetJob', 10000, charId, JobsConfig.DefaultJob, 0, 'quit')
    if res.ok then res.message = 'You quit your job' end
    return res
end, { cooldown = 3000 })

---------------------------------------------------------------------------
-- Paychecks: one per character per interval slot; the op id makes repeats impossible.
---------------------------------------------------------------------------
CreateThread(function()
    local interval = JobsConfig.PaycheckIntervalMinutes * 60
    local lastSlot = math.floor(os.time() / interval)
    while true do
        Wait(30000)
        local slot = math.floor(os.time() / interval)
        if slot ~= lastSlot and Veyl.IsReady() then
            lastSlot = slot
            for charId, a in pairs(active) do
                local g = gradeInfo(a.job, a.grade)
                if a.onDuty and g and g.pay > 0 and Veyl.GetCharacterId(a.src) == charId then
                    local res = Veyl.Await('veyl_banking', 'Credit', 15000, charId, 'bank', g.pay,
                        ('Paycheck: %s'):format(JobsConfig.Jobs[a.job].label), ('pay:%d:%d'):format(charId, slot))
                    if res.ok then
                        Veyl.Notify(a.src, ('Paycheck received: $%d'):format(g.pay), 'success')
                    elseif res.code ~= 'DUPLICATE_OPERATION' then
                        print(('^3[veyl_jobs] paycheck failed for %d: %s^7'):format(charId, tostring(res.code)))
                    end
                end
            end
        end
    end
end)
