-- veyl_core groups: job/gang definitions, memberships (multijob/multigang), primary selection and duty.
-- Membership rows (veyl_player_groups) are canonical; PlayerData.job/.jobs/.gang/.gangs are derived views.
-- Semantics:
--   SetJob/SetGang (SetPrimaryReplacing): the old primary membership is replaced; other memberships stay.
--   SetPrimary: select an existing membership as primary without removing anything.
--   Add/RemoveMember: explicit membership changes. Default groups are never stored in the maps.

Groups = {}

local function defs(kind) return kind == 'gang' and VeylShared.Gangs or VeylShared.Jobs end
local function defaultName(kind) return kind == 'gang' and VeylConfig.DefaultGang or VeylConfig.DefaultJob end
local function mapKey(kind) return kind == 'gang' and 'gangs' or 'jobs' end
local function primaryKey(kind) return kind == 'gang' and 'gang' or 'job' end

function Groups.Valid(kind, name, grade)
    return type(name) == 'string' and VeylShared.GetGrade(kind, name, grade) ~= nil
end

local function persistMembership(citizenid, kind, name, grade)
    CoreEnqueue(citizenid, function()
        if grade == nil then
            MySQL.update.await('DELETE FROM veyl_player_groups WHERE citizenid = ? AND group_type = ? AND name = ?',
                { citizenid, kind, name })
        else
            MySQL.query.await([[INSERT INTO veyl_player_groups (citizenid, group_type, name, grade) VALUES (?, ?, ?, ?)
                ON DUPLICATE KEY UPDATE grade = VALUES(grade)]], { citizenid, kind, name, grade })
        end
        return Veyl.Ok()
    end)
end

local function persistPrimary(citizenid, kind, name)
    CoreEnqueue(citizenid, function()
        MySQL.update.await(('UPDATE veyl_players SET %s = ? WHERE citizenid = ?'):format(primaryKey(kind)), { name, citizenid })
        return Veyl.Ok()
    end)
end

local function notifyGroup(p, name, grade)
    TriggerEvent('VeylCore:Server:OnGroupUpdate', p.source, name, grade)
    TriggerClientEvent('VeylCore:Client:OnGroupUpdate', p.source, name, grade)
end

local function notifyPrimary(p, kind)
    if kind == 'job' then
        local job = Core.BuildJob(p)
        TriggerEvent('VeylCore:Server:OnJobUpdate', p.source, job)
        TriggerClientEvent('VeylCore:Client:OnJobUpdate', p.source, job)
    else
        local gang = Core.BuildGang(p)
        TriggerEvent('VeylCore:Server:OnGangUpdate', p.source, gang)
        TriggerClientEvent('VeylCore:Client:OnGangUpdate', p.source, gang)
    end
    Core.SyncPlayer(p)
end

local function setDutyInternal(p, onDuty)
    onDuty = onDuty == true
    if p.onduty == onDuty then return end
    p.onduty = onDuty
    TriggerEvent('VeylCore:Server:SetDuty', p.source, onDuty)
    TriggerClientEvent('VeylCore:Client:SetDuty', p.source, onDuty)
    Core.SyncPlayer(p)
end

local function onlinePlayer(citizenid)
    local src = Core.ByCitizen[citizenid]
    return src and Core.Players[src] or nil
end

--- QB-style SetJob/SetGang for an online player.
function Groups.SetPrimaryReplacing(src, kind, name, grade)
    local p = Core.Players[tonumber(src)]
    if not p then return false end
    grade = math.floor(tonumber(grade) or 0)
    if not Groups.Valid(kind, name, grade) then return false end
    local map, old, def = p[mapKey(kind)], p[primaryKey(kind)], defaultName(kind)
    if old ~= def and old ~= name then
        map[old] = nil
        persistMembership(p.citizenid, kind, old, nil)
        notifyGroup(p, old, nil)
    end
    if name ~= def then
        map[name] = grade
        persistMembership(p.citizenid, kind, name, grade)
        notifyGroup(p, name, grade)
    end
    p[primaryKey(kind)] = name
    persistPrimary(p.citizenid, kind, name)
    if kind == 'job' then setDutyInternal(p, defs('job')[name].defaultDuty == true) end
    notifyPrimary(p, kind)
    return true
end

--- Adds (or regrades) a membership. Works for online and offline characters.
function Groups.AddMember(citizenid, kind, name, grade)
    grade = math.floor(tonumber(grade) or 0)
    if name == defaultName(kind) or not Groups.Valid(kind, name, grade) then return false end
    persistMembership(citizenid, kind, name, grade)
    local p = onlinePlayer(citizenid)
    if p then
        p[mapKey(kind)][name] = grade
        notifyGroup(p, name, grade)
        if p[primaryKey(kind)] == name then notifyPrimary(p, kind) else Core.SyncPlayer(p) end
    end
    return true
end

--- Removes a membership. If it was primary, the primary falls back to the default group.
function Groups.RemoveMember(citizenid, kind, name)
    if name == defaultName(kind) then return false end
    local def = defaultName(kind)
    persistMembership(citizenid, kind, name, nil)
    local p = onlinePlayer(citizenid)
    if p then
        if p[mapKey(kind)][name] == nil then return false end
        p[mapKey(kind)][name] = nil
        notifyGroup(p, name, nil)
        if p[primaryKey(kind)] == name then
            p[primaryKey(kind)] = def
            persistPrimary(citizenid, kind, def)
            if kind == 'job' then setDutyInternal(p, defs('job')[def].defaultDuty == true) end
            notifyPrimary(p, kind)
        else
            Core.SyncPlayer(p)
        end
    else
        CoreEnqueue(citizenid, function()
            MySQL.update.await(('UPDATE veyl_players SET %s = ? WHERE citizenid = ? AND %s = ?'):format(primaryKey(kind), primaryKey(kind)),
                { def, citizenid, name })
            return Veyl.Ok()
        end)
    end
    return true
end

--- Selects an existing membership (or the default group) as primary.
function Groups.SetPrimary(citizenid, kind, name)
    local def = defaultName(kind)
    local p = onlinePlayer(citizenid)
    if p then
        if name ~= def and p[mapKey(kind)][name] == nil then return false end
        if p[primaryKey(kind)] == name then return true end
        p[primaryKey(kind)] = name
        persistPrimary(citizenid, kind, name)
        if kind == 'job' then setDutyInternal(p, defs('job')[name].defaultDuty == true) end
        notifyPrimary(p, kind)
        return true
    end
    if name ~= def and not defs(kind)[name] then return false end
    CoreEnqueue(citizenid, function()
        MySQL.update.await(([[UPDATE veyl_players SET %s = ? WHERE citizenid = ? AND (? = ? OR EXISTS (
            SELECT 1 FROM veyl_player_groups g WHERE g.citizenid = ? AND g.group_type = ? AND g.name = ?))]]):format(primaryKey(kind)),
            { name, citizenid, name, def, citizenid, kind, name })
        return Veyl.Ok()
    end)
    return true
end

function Groups.SetDuty(src, onDuty)
    local p = Core.Players[tonumber(src)]
    if not p then return false end
    setDutyInternal(p, onDuty)
    return true
end

--- All memberships as name -> grade (jobs and gangs; default groups excluded). Used by ox_inventory.
function Groups.GetGroups(src)
    local p = Core.Players[tonumber(src)]
    if not p then return {} end
    local out = {}
    for name, grade in pairs(p.jobs) do out[name] = grade end
    for name, grade in pairs(p.gangs) do out[name] = grade end
    return out
end

local function matches(name, grade, filter)
    if type(filter) == 'string' then return filter == name end
    if type(filter) == 'table' then
        if filter[1] ~= nil then
            for _, n in ipairs(filter) do if n == name then return true end end
            return false
        end
        local required = filter[name]
        if required == nil then return false end
        if type(required) == 'table' then
            for _, g in ipairs(required) do if g == grade then return true end end
            return false
        end
        return grade >= (tonumber(required) or 0)
    end
    return false
end

--- HasGroup(src, filter): filter = 'police' | { 'police', 'ambulance' } | { police = 2 }. Returns name, grade.
--- Duty is NOT implied; check PlayerData.job.onduty separately when it matters.
function Groups.HasGroup(src, filter)
    local p = Core.Players[tonumber(src)]
    if not p then return nil end
    for name, grade in pairs(Groups.GetGroups(src)) do
        if matches(name, grade, filter) then return name, grade end
    end
    return nil
end

function Groups.HasPrimaryGroup(src, filter)
    local p = Core.Players[tonumber(src)]
    if not p then return nil end
    for _, kind in ipairs({ 'job', 'gang' }) do
        local name = p[primaryKey(kind)]
        local grade = p[mapKey(kind)][name] or 0
        if name ~= defaultName(kind) and matches(name, grade, filter) then return name, grade end
    end
    return nil
end

function Groups.IsGradeBoss(name, grade)
    local g = VeylShared.GetGrade('job', name, grade) or VeylShared.GetGrade('gang', name, grade)
    return g ~= nil and g.isboss == true
end

--- Loads memberships for a character. Invalid rows (removed definitions) are skipped with a warning.
function Groups.Load(citizenid)
    local rows = MySQL.query.await('SELECT group_type, name, grade FROM veyl_player_groups WHERE citizenid = ?', { citizenid }) or {}
    local jobs, gangs = {}, {}
    for _, r in ipairs(rows) do
        if Groups.Valid(r.group_type, r.name, r.grade) then
            if r.group_type == 'job' then jobs[r.name] = r.grade else gangs[r.name] = r.grade end
        else
            print(('^3[veyl_core] %s has unknown %s membership %s/%s (skipped)^7'):format(citizenid, r.group_type, r.name, r.grade))
        end
    end
    return jobs, gangs
end
