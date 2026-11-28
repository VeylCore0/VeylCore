-- Jobs: your jobs, clock in and out, the city job board, applications.

local C = PhoneConfig
local function session(src)
    local s = Phone.Session(src)
    if not s then return nil, Veyl.Err('NO_SESSION', 'Open your phone first') end
    return s
end
local function core(name, ...) return Veyl.Await('veyl_core', name, 15000, ...) end
local function cidByNumber(number) return Phone.CidByNumber(number) end
local function charName(pd) return pd and ('%s %s'):format(pd.charinfo.firstname or '', pd.charinfo.lastname or '') or 'Unknown' end
local seq = 0
local function op(kind, cid) seq = seq + 1 return ('phone:%s:%s:%d:%d'):format(kind, cid, os.time(), seq) end

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
    message = PhoneUtil.Clean(message, 500)
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
