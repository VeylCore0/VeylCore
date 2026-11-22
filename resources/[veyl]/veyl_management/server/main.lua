-- veyl_management server: boss menus for jobs and gangs (employee list, hire by offer, promote/demote, fire).
-- veyl_core owns memberships; this resource only decides who may change them. Every change is audited.
--
-- Rules (checked here, never in the UI):
--   * you manage a group only while you hold one of its isboss grades;
--   * you can only act on members whose grade is BELOW yours, and only assign grades below yours;
--   * hiring sends an offer that the other person must accept within OfferSeconds.

local C = ManagementConfig
local offers = {} -- [token] = { from, fromCid, target, targetCid, kind, name, grade, expires }

Veyl.Startup({ 'veyl_core' }, function() return true end)

local function defsOf(kind) return kind == 'gang' and exports.veyl_core:GetGangs() or exports.veyl_core:GetJobs() end
local function defaultOf(kind) return kind == 'gang' and 'none' or 'unemployed' end
local function membership(pd, kind) return kind == 'gang' and pd.gangs or pd.jobs end

local function gradeDef(def, grade) return def and def.grades[tostring(grade)] or nil end

local function nearOffice(src, job)
    if C.JobMenuAnywhere then return true end
    local pc = Veyl.GetPlayerCoords(src)
    if not pc then return false end
    for _, o in ipairs(C.Offices) do
        if o.job == job and #(pc - o.coords) <= C.OfficeRadius + 2.0 then return true end
    end
    return false
end

--- The caller's boss grade in the group, or nil, err.
local function bossOf(src, kind, name)
    if kind ~= 'job' and kind ~= 'gang' then return nil, Veyl.Err('INVALID_INPUT', 'Invalid group') end
    if type(name) ~= 'string' or name == defaultOf(kind) then return nil, Veyl.Err('INVALID_INPUT', 'Invalid group') end
    local def = defsOf(kind)[name]
    local pd = Veyl.GetPlayerData(src)
    local grade = def and pd and membership(pd, kind)[name]
    local g = grade ~= nil and gradeDef(def, grade)
    if not g or not g.isboss then return nil, Veyl.Err('NO_PERMISSION', 'You are not a boss here') end
    if kind == 'job' and not nearOffice(src, name) then return nil, Veyl.Err('TOO_FAR', 'Use the boss menu at your office') end
    return grade, def
end

local function charName(charinfo)
    local ci = charinfo
    if type(ci) == 'string' then
        local ok, decoded = pcall(json.decode, ci)
        ci = ok and decoded or nil
    end
    ci = type(ci) == 'table' and ci or {}
    local n = ('%s %s'):format(ci.firstname or '', ci.lastname or ''):gsub('^%s+', ''):gsub('%s+$', '')
    return n ~= '' and n or 'Unknown'
end

local function grades(def)
    local out = {}
    for g, d in pairs(def.grades) do out[#out + 1] = { grade = tonumber(g), name = d.name, pay = d.payment, isboss = d.isboss == true } end
    table.sort(out, function(a, b) return a.grade < b.grade end)
    return out
end

local function nearbyPlayers(src)
    local pc = Veyl.GetPlayerCoords(src)
    local out = {}
    if not pc then return out end
    for _, s in ipairs(GetPlayers()) do
        s = tonumber(s)
        local p = s ~= src and Veyl.GetPlayerCoords(s)
        if p and Veyl.GetCitizenId(s) then
            local d = #(p - pc)
            if d <= C.HireDistance then out[#out + 1] = { id = s, distance = math.floor(d * 10 + 0.5) / 10 } end
        end
    end
    table.sort(out, function(a, b) return a.distance < b.distance end)
    return out
end

local function view(src, kind, name)
    local myGrade, def = bossOf(src, kind, name)
    if not myGrade then return nil, def end
    local me = Veyl.GetCitizenId(src)
    local rows = MySQL.query.await([[SELECT g.citizenid, g.grade, p.charinfo, p.job, p.gang FROM veyl_player_groups g
        JOIN veyl_players p ON p.citizenid = g.citizenid WHERE g.group_type = ? AND g.name = ? AND p.deleted_at IS NULL
        ORDER BY g.grade DESC]], { kind, name }) or {}
    local members = {}
    for _, r in ipairs(rows) do
        local s = exports.veyl_core:GetSourceByCitizenId(r.citizenid)
        local pd = s and Veyl.GetPlayerData(s)
        local primary = (kind == 'gang' and r.gang or r.job) == name
        local g = gradeDef(def, r.grade)
        members[#members + 1] = {
            citizenid = r.citizenid, name = charName(r.charinfo), grade = r.grade, gradeName = g and g.name or tostring(r.grade),
            online = pd ~= nil, onduty = kind == 'job' and pd ~= nil and pd.job.name == name and pd.job.onduty == true,
            primary = primary, self = r.citizenid == me, manageable = r.citizenid ~= me and r.grade < myGrade,
        }
    end
    return {
        kind = kind, name = name, label = def.label, myGrade = myGrade, grades = grades(def),
        members = members, nearby = nearbyPlayers(src), offerSeconds = C.OfferSeconds,
    }
end

Veyl.RegisterCallback('open', function(src, _, kind, name)
    local v, err = view(src, kind, name)
    if not v then return err end
    return Veyl.Ok(v)
end, { cooldown = 500 })

--- The groups the caller is a boss of (for /bossmenu and /gangmenu when they belong to several).
Veyl.RegisterCallback('myGroups', function(src, _, kind)
    if kind ~= 'job' and kind ~= 'gang' then return Veyl.Err('INVALID_INPUT', 'Invalid group') end
    local pd = Veyl.GetPlayerData(src)
    local defs, out = defsOf(kind), {}
    for name, grade in pairs(membership(pd, kind)) do
        local g = gradeDef(defs[name], grade)
        if g and g.isboss then out[#out + 1] = { name = name, label = defs[name].label, office = kind == 'job' and nearOffice(src, name) } end
    end
    table.sort(out, function(a, b) return a.label < b.label end)
    return Veyl.Ok(out)
end, { cooldown = 500 })

---------------------------------------------------------------------------
-- Changes
---------------------------------------------------------------------------
local function memberGrade(kind, name, citizenid)
    return MySQL.scalar.await('SELECT grade FROM veyl_player_groups WHERE citizenid = ? AND group_type = ? AND name = ?', { citizenid, kind, name })
end

local function notifyCid(citizenid, msg, kind)
    local s = exports.veyl_core:GetSourceByCitizenId(citizenid)
    if s then Veyl.Notify(s, msg, kind) end
end

Veyl.RegisterCallback('setGrade', function(src, me, kind, name, citizenid, grade)
    local myGrade, def = bossOf(src, kind, name)
    if not myGrade then return def end
    grade = tonumber(grade)
    if type(citizenid) ~= 'string' or citizenid == me then return Veyl.Err('INVALID_INPUT', 'Choose someone else') end
    if not grade or not gradeDef(def, grade) then return Veyl.Err('INVALID_INPUT', 'Unknown rank') end
    if grade >= myGrade then return Veyl.Err('NO_PERMISSION', 'You can only give ranks below your own') end
    local current = memberGrade(kind, name, citizenid)
    if current == nil then return Veyl.Err('NOT_FOUND', 'They are not a member') end
    if current >= myGrade then return Veyl.Err('NO_PERMISSION', 'They rank as high as you') end
    if current == grade then return Veyl.Ok(view(src, kind, name)) end
    local ok = kind == 'gang' and exports.veyl_core:AddPlayerToGang(citizenid, name, grade) or (kind == 'job' and exports.veyl_core:AddPlayerToJob(citizenid, name, grade))
    if not ok then return Veyl.Err('INTERNAL', 'Could not change the rank') end
    local label = gradeDef(def, grade).name
    notifyCid(citizenid, ('%s: you are now %s.'):format(def.label, label), grade > current and 'success' or 'warning')
    Veyl.Audit(src, 'management_grade', { kind = kind, group = name, target = citizenid, from = current, to = grade })
    return Veyl.Ok(view(src, kind, name), ('%s to %s'):format(grade > current and 'Promoted' or 'Demoted', label))
end, { cooldown = 1000 })

Veyl.RegisterCallback('fire', function(src, me, kind, name, citizenid)
    local myGrade, def = bossOf(src, kind, name)
    if not myGrade then return def end
    if type(citizenid) ~= 'string' or citizenid == me then return Veyl.Err('INVALID_INPUT', 'Choose someone else') end
    local current = memberGrade(kind, name, citizenid)
    if current == nil then return Veyl.Err('NOT_FOUND', 'They are not a member') end
    if current >= myGrade then return Veyl.Err('NO_PERMISSION', 'They rank as high as you') end
    local ok = kind == 'gang' and exports.veyl_core:RemovePlayerFromGang(citizenid, name) or (kind == 'job' and exports.veyl_core:RemovePlayerFromJob(citizenid, name))
    if not ok and memberGrade(kind, name, citizenid) ~= nil then return Veyl.Err('INTERNAL', 'Could not remove them') end
    notifyCid(citizenid, kind == 'gang' and ('You were kicked out of %s.'):format(def.label) or ('You were let go from %s.'):format(def.label), 'warning')
    Veyl.Audit(src, 'management_fire', { kind = kind, group = name, target = citizenid, grade = current })
    return Veyl.Ok(view(src, kind, name), kind == 'gang' and 'Removed from the gang' or 'Fired')
end, { cooldown = 1000 })

---------------------------------------------------------------------------
-- Hiring: an offer the other person accepts
---------------------------------------------------------------------------
Veyl.RegisterCallback('hire', function(src, me, kind, name, target, grade)
    local myGrade, def = bossOf(src, kind, name)
    if not myGrade then return def end
    target, grade = tonumber(target), tonumber(grade)
    if not grade or not gradeDef(def, grade) then return Veyl.Err('INVALID_INPUT', 'Unknown rank') end
    if grade >= myGrade then return Veyl.Err('NO_PERMISSION', 'You can only give ranks below your own') end
    local tcid = target and target ~= src and Veyl.GetCitizenId(target)
    if not tcid then return Veyl.Err('NOT_FOUND', 'That person is not here') end
    local a, b = Veyl.GetPlayerCoords(src), Veyl.GetPlayerCoords(target)
    if not a or not b or #(a - b) > C.HireDistance then return Veyl.Err('TOO_FAR', 'They need to be next to you') end
    local tpd = Veyl.GetPlayerData(target)
    if membership(tpd, kind)[name] ~= nil then return Veyl.Err('INVALID_STATE', 'They are already a member') end
    if kind == 'gang' and next(tpd.gangs) ~= nil then return Veyl.Err('INVALID_STATE', 'They already belong to a gang') end
    for t, o in pairs(offers) do if o.target == target then offers[t] = nil end end
    local token = Veyl.NewId()
    offers[token] = { from = src, fromCid = me, target = target, targetCid = tcid, kind = kind, name = name, grade = grade,
        expires = os.time() + C.OfferSeconds }
    TriggerClientEvent('veyl_management:offer', target, token, {
        label = def.label, rank = gradeDef(def, grade).name, kind = kind, seconds = C.OfferSeconds,
    })
    Veyl.Audit(src, 'management_offer', { kind = kind, group = name, target = tcid, grade = grade })
    return Veyl.Ok(nil, 'Offer sent. Waiting for them to accept.')
end, { cooldown = 2000 })

Veyl.RegisterCallback('answerOffer', function(src, citizenid, token, accept)
    local o = type(token) == 'string' and offers[token]
    if not o or o.target ~= src or o.targetCid ~= citizenid then return Veyl.Err('NOT_FOUND', 'This offer is no longer valid') end
    offers[token] = nil
    if os.time() > o.expires then return Veyl.Err('EXPIRED', 'This offer has expired') end
    local def = defsOf(o.kind)[o.name]
    local bossSrc = GetPlayerName(o.from) and Veyl.GetCitizenId(o.from) == o.fromCid and o.from or nil
    if accept ~= true then
        if bossSrc then Veyl.Notify(bossSrc, 'They turned down the offer.', 'info') end
        return Veyl.Ok(nil, 'Offer declined')
    end
    -- The boss must still be a boss (ranked above the offered grade) when the offer is accepted.
    local bossGrade = MySQL.scalar.await('SELECT grade FROM veyl_player_groups WHERE citizenid = ? AND group_type = ? AND name = ?', { o.fromCid, o.kind, o.name })
    local bg = bossGrade ~= nil and gradeDef(def, bossGrade)
    if not bg or not bg.isboss or bossGrade <= o.grade then return Veyl.Err('NO_PERMISSION', 'This offer is no longer valid') end
    local pd = Veyl.GetPlayerData(src)
    if membership(pd, o.kind)[o.name] ~= nil then return Veyl.Err('INVALID_STATE', 'You are already a member') end
    if o.kind == 'gang' and next(pd.gangs) ~= nil then return Veyl.Err('INVALID_STATE', 'Leave your current gang first') end
    local ok
    if o.kind == 'gang' then
        ok = exports.veyl_core:AddPlayerToGang(citizenid, o.name, o.grade)
        if ok then exports.veyl_core:SetPlayerPrimaryGang(citizenid, o.name) end
    else
        ok = exports.veyl_core:AddPlayerToJob(citizenid, o.name, o.grade)
        if ok and pd.job.name == defaultOf('job') then exports.veyl_core:SetPlayerPrimaryJob(citizenid, o.name) end
    end
    if not ok then return Veyl.Err('INTERNAL', 'Could not sign you on') end
    if bossSrc then Veyl.Notify(bossSrc, ('%s accepted. Welcome aboard.'):format(('%s %s'):format(pd.charinfo.firstname or '', pd.charinfo.lastname or '')), 'success') end
    Veyl.Audit(src, 'management_hired', { kind = o.kind, group = o.name, grade = o.grade, by = o.fromCid })
    local switchHint = o.kind == 'job' and pd.job.name ~= defaultOf('job') and ' Use /jobs to make it your main job.' or ''
    return Veyl.Ok(nil, ('You joined %s.%s'):format(def.label, switchHint))
end, { cooldown = 500 })

CreateThread(function()
    while true do
        Wait(15000)
        local now = os.time()
        for t, o in pairs(offers) do if now > o.expires + 5 then offers[t] = nil end end
    end
end)
AddEventHandler('playerDropped', function()
    local src = source
    for t, o in pairs(offers) do if o.target == src or o.from == src then offers[t] = nil end end
end)
