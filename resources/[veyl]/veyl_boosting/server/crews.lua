-- Crews: a leader and up to Crews.MaxSize members. Everything is checked on the server: who is nearby, who leads, who may join
-- or leave at which contract stage. A crew lives in memory; the contract stores who was on it.

Boost = Boost or {}
Boost.Crew = {}
local Crew = Boost.Crew
local K = BoostingConfig.Crews
local crews = {}     -- [id] = { id, leader, members = { cid = { cid, src, name } }, order = { cid }, log = {}, contract = id|nil }
local byCid = {}     -- [cid] = crew id
local invites = {}   -- [targetCid] = { crew, from, fromName, at }

local function nameOf(src)
    local pd = Veyl.GetPlayerData(src)
    local ci = pd and pd.charinfo or {}
    local name = ((ci.firstname or '') .. ' ' .. (ci.lastname or '')):match('^%s*(.-)%s*$')
    return name ~= '' and name or 'Operator'
end
Crew.nameOf = nameOf

local function logEntry(crew, text)
    table.insert(crew.log, 1, { at = os.time(), text = text })
    while #crew.log > K.LogSize do table.remove(crew.log) end
end

local function refresh(crew)
    for _, m in pairs(crew.members) do if m.src then TriggerClientEvent('veyl_boosting:refresh', m.src) end end
end
Crew.refresh = refresh

--- An invite waiting for this player (for the tablet).
function Crew.pending(cid)
    local inv = invites[cid]
    if inv and os.time() - inv.at <= K.InviteSeconds then return { from = inv.fromName, seconds = K.InviteSeconds - (os.time() - inv.at) } end
    return nil
end

function Crew.of(cid) return byCid[cid] and crews[byCid[cid]] or nil end
function Crew.size(crew) local n = 0 for _ in pairs(crew.members) do n = n + 1 end return n end

local function stateOf(crew)
    local c = crew.contract and Boost.Contracts.byId[crew.contract]
    return c and c.state or nil
end

local function dissolveIfAlone(crew)
    if Crew.size(crew) <= 1 and not crew.contract then
        for cid in pairs(crew.members) do byCid[cid] = nil end
        crews[crew.id] = nil
    end
end

local function create(cid, src)
    local crew = { id = Veyl.NewId(), leader = cid, members = {}, order = { cid }, log = {}, contract = nil }
    crew.members[cid] = { cid = cid, src = src, name = nameOf(src) }
    crews[crew.id], byCid[cid] = crew, crew.id
    return crew
end

--- The invite list: players within range who could be asked.
function Crew.nearby(src, cid)
    local mine = Veyl.GetPlayerCoords(src)
    local out = {}
    if not mine then return out end
    for _, s in ipairs(GetPlayers()) do
        local t = tonumber(s)
        local tcid = t ~= src and Veyl.GetCitizenId(t)
        local pc = tcid and Veyl.GetPlayerCoords(t)
        if tcid and pc and #(mine - pc) <= K.InviteRange and not byCid[tcid] then out[#out + 1] = { id = t, name = nameOf(t) } end
    end
    return out
end

function Crew.invite(src, cid, targetSrc)
    targetSrc = tonumber(targetSrc)
    local tcid = targetSrc and targetSrc ~= src and Veyl.GetCitizenId(targetSrc)
    if not tcid then return Veyl.Err('NOT_FOUND', 'That player is not available') end
    local crew = Crew.of(cid)
    if crew and crew.leader ~= cid then return Veyl.Err('NO_PERMISSION', 'Only the crew leader can invite') end
    if byCid[tcid] then return Veyl.Err('INVALID_STATE', 'They are already in a crew') end
    local mine, theirs = Veyl.GetPlayerCoords(src), Veyl.GetPlayerCoords(targetSrc)
    if not mine or not theirs or #(mine - theirs) > K.InviteRange then return Veyl.Err('TOO_FAR', 'They are too far away') end
    if crew then
        if Crew.size(crew) >= K.MaxSize then return Veyl.Err('LIMIT', ('A crew holds up to %d'):format(K.MaxSize)) end
        local st = stateOf(crew)
        if st and not K.JoinStates[st] then return Veyl.Err('INVALID_STATE', 'The contract has already started') end
    end
    if Boost.Contracts.byCid[tcid] then return Veyl.Err('INVALID_STATE', 'They are on a contract') end
    local old = invites[tcid]
    if old and os.time() - old.at < 5 then return Veyl.Err('RATE_LIMITED', 'Wait a moment before inviting again') end
    crew = crew or create(cid, src)
    invites[tcid] = { crew = crew.id, from = cid, fromName = nameOf(src), at = os.time() }
    TriggerClientEvent('veyl_boosting:invite', targetSrc, { from = invites[tcid].fromName, seconds = K.InviteSeconds })
    logEntry(crew, ('Invited %s'):format(nameOf(targetSrc)))
    refresh(crew)
    return Veyl.Ok(nil, ('Invite sent to %s'):format(nameOf(targetSrc)))
end

function Crew.answer(src, cid, accept)
    local inv = invites[cid]
    invites[cid] = nil
    if not inv or os.time() - inv.at > K.InviteSeconds then return Veyl.Err('NOT_FOUND', 'That invite expired') end
    local crew = crews[inv.crew]
    if not crew then return Veyl.Err('NOT_FOUND', 'That crew no longer exists') end
    if not accept then
        logEntry(crew, ('%s declined'):format(nameOf(src)))
        refresh(crew)
        return Veyl.Ok(nil, 'Declined')
    end
    if byCid[cid] then return Veyl.Err('INVALID_STATE', 'You are already in a crew') end
    if Boost.Contracts.byCid[cid] then return Veyl.Err('INVALID_STATE', 'Finish your contract first') end
    if Crew.size(crew) >= K.MaxSize then return Veyl.Err('LIMIT', 'That crew is full') end
    local st = stateOf(crew)
    if st and not K.JoinStates[st] then return Veyl.Err('INVALID_STATE', 'The contract has already started') end
    crew.members[cid] = { cid = cid, src = src, name = nameOf(src) }
    crew.order[#crew.order + 1] = cid
    byCid[cid] = crew.id
    logEntry(crew, ('%s joined'):format(nameOf(src)))
    local c = crew.contract and Boost.Contracts.byId[crew.contract]
    if c then Boost.Contracts.addMember(c, cid, src) end
    refresh(crew)
    return Veyl.Ok(nil, 'You joined the crew')
end

local function remove(crew, cid, text)
    local m = crew.members[cid]
    if not m then return end
    crew.members[cid] = nil
    byCid[cid] = nil
    for i, x in ipairs(crew.order) do if x == cid then table.remove(crew.order, i) break end end
    logEntry(crew, text:format(m.name))
    if m.src then TriggerClientEvent('veyl_boosting:refresh', m.src) end
    local c = crew.contract and Boost.Contracts.byId[crew.contract]
    if c then Boost.Contracts.removeMember(c, cid) end
    if crew.leader == cid and crew.order[1] then
        crew.leader = crew.order[1]
        logEntry(crew, ('%s is the new leader'):format(crew.members[crew.leader].name))
        if c then c.leader = crew.leader Boost.Contracts.persist(c) end
    end
    dissolveIfAlone(crew)
    refresh(crew)
end

function Crew.leave(src, cid)
    local crew = Crew.of(cid)
    if not crew then return Veyl.Err('NOT_FOUND', 'You are not in a crew') end
    local st = stateOf(crew)
    if st and not K.LeaveStates[st] then return Veyl.Err('INVALID_STATE', 'You cannot leave right now') end
    remove(crew, cid, '%s left')
    return Veyl.Ok(nil, 'You left the crew')
end

function Crew.kick(src, cid, target)
    local crew = Crew.of(cid)
    if not crew or crew.leader ~= cid then return Veyl.Err('NO_PERMISSION', 'Only the leader can remove members') end
    if target == cid or not crew.members[target] then return Veyl.Err('NOT_FOUND', 'Not a member') end
    local st = stateOf(crew)
    if st and not K.LeaveStates[st] then return Veyl.Err('INVALID_STATE', 'You cannot remove anyone right now') end
    remove(crew, target, '%s was removed')
    return Veyl.Ok(nil, 'Member removed')
end

function Crew.lead(src, cid, target)
    local crew = Crew.of(cid)
    if not crew or crew.leader ~= cid then return Veyl.Err('NO_PERMISSION', 'Only the leader can do that') end
    if target == cid or not crew.members[target] then return Veyl.Err('NOT_FOUND', 'Not a member') end
    crew.leader = target
    logEntry(crew, ('%s is the new leader'):format(crew.members[target].name))
    local c = crew.contract and Boost.Contracts.byId[crew.contract]
    if c then c.leader = target Boost.Contracts.persist(c) end
    refresh(crew)
    return Veyl.Ok(nil, 'Leadership transferred')
end

--- A member's view of their crew (nil if none).
function Crew.view(cid)
    local crew = Crew.of(cid)
    if not crew then return nil end
    local members = {}
    for _, x in ipairs(crew.order) do
        local m = crew.members[x]
        members[#members + 1] = { id = x, name = m.name, leader = x == crew.leader, online = m.src ~= nil, me = x == cid }
    end
    local st = stateOf(crew)
    return { id = crew.id, leader = crew.leader == cid, members = members, max = K.MaxSize, log = crew.log, locked = st ~= nil and not K.JoinStates[st] }
end

--- The crew's members as { cid, src } for contract creation.
function Crew.roster(cid)
    local crew = Crew.of(cid)
    local list = {}
    if not crew then return list end
    for _, x in ipairs(crew.order) do list[#list + 1] = { cid = x, src = crew.members[x].src, name = crew.members[x].name } end
    return list
end

function Crew.attach(cid, contractId)
    local crew = Crew.of(cid)
    if crew then crew.contract = contractId end
end

function Crew.detach(cid)
    local crew = Crew.of(cid)
    if crew then crew.contract = nil dissolveIfAlone(crew) end
end

function Crew.log(cid, text)
    local crew = Crew.of(cid)
    if crew then logEntry(crew, text) end
end

--- A member disconnects: keep their seat (and their contract share) but mark them offline.
function Crew.drop(cid)
    local crew = Crew.of(cid)
    invites[cid] = nil
    if not crew then return end
    local m = crew.members[cid]
    if m then m.src = nil logEntry(crew, ('%s disconnected'):format(m.name)) end
    if not crew.contract then remove(crew, cid, '%s left') else refresh(crew) end
end

function Crew.back(cid, src)
    local crew = Crew.of(cid)
    if crew and crew.members[cid] then crew.members[cid].src = src crew.members[cid].name = nameOf(src) refresh(crew) end
end
