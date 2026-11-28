-- Crews: a leader and members. Crew mates can use each other's outdoor plants and benches (the crew's `share` switch), their XP pools into a
-- crew level, and the level adds a small bonus when selling. Everything here is decided by the server; the client only asks.

Prod = Prod or {}
Prod.Crews = { crews = {}, byCid = {}, invites = {} }
local Cr = Prod.Crews
local C = ProductionConfig

local function cfg() return C.Crews end

function Cr.load()
    Cr.crews, Cr.byCid = {}, {}
    for _, r in ipairs(MySQL.query.await('SELECT id, name, leader_cid, share, xp FROM veyl_prod_crews') or {}) do
        Cr.crews[r.id] = { id = r.id, name = r.name, leader = r.leader_cid, share = r.share == 1 or r.share == true, xp = r.xp }
    end
    for _, r in ipairs(MySQL.query.await('SELECT citizenid, crew_id, joined_at FROM veyl_prod_crew_members') or {}) do
        if Cr.crews[r.crew_id] then Cr.byCid[r.citizenid] = { crew = r.crew_id, at = r.joined_at } end
    end
end

function Cr.of(cid) local m = Cr.byCid[cid] return m and Cr.crews[m.crew] or nil end

--- Do these two share a crew whose members share their things? (Used for plants and benches placed outdoors.)
function Cr.shares(ownerCid, cid)
    local a, b = Cr.byCid[ownerCid], Cr.byCid[cid]
    return a ~= nil and b ~= nil and a.crew == b.crew and Cr.crews[a.crew].share == true
end

function Cr.level(crew)
    local lv = 1
    for i, need in ipairs(cfg().Levels) do if crew.xp >= need then lv = i end end
    return lv
end

--- The factor on sale prices for this player from their crew level (1.0 with no crew).
function Cr.sellBonus(cid)
    local crew = Cr.of(cid)
    if not crew or not cfg().Enabled then return 1.0 end
    return 1.0 + (Cr.level(crew) - 1) * cfg().SellBonusPerLevel
end

function Cr.addXp(cid, n)
    local crew = Cr.of(cid)
    if not crew or n <= 0 then return end
    crew.xp = crew.xp + n
    MySQL.update('UPDATE veyl_prod_crews SET xp = ? WHERE id = ?', { crew.xp, crew.id })
end

local function members(crewId)
    local out = {}
    for cid, m in pairs(Cr.byCid) do if m.crew == crewId then out[#out + 1] = cid end end
    table.sort(out, function(a, b) return Cr.byCid[a].at < Cr.byCid[b].at or (Cr.byCid[a].at == Cr.byCid[b].at and a < b) end)
    return out
end

local function count(crewId) return #members(crewId) end

--- The crew page: your crew, its members, and any invite waiting for you.
function Cr.view(cid)
    local crew = Cr.of(cid)
    local inv = Cr.invites[cid]
    local out = { enabled = cfg().Enabled, createCost = cfg().CreateCost, max = cfg().MaxMembers, crew = nil,
        invite = inv and os.time() - inv.at <= cfg().InviteSeconds and { crew = Cr.crews[inv.crew] and Cr.crews[inv.crew].name, from = inv.fromName } or nil }
    if crew then
        local list = {}
        for _, m in ipairs(members(crew.id)) do list[#list + 1] = { id = m, name = Prod.Props.nameOf(m), leader = m == crew.leader, me = m == cid } end
        local lv = Cr.level(crew)
        local floor, nextXp = cfg().Levels[lv], cfg().Levels[lv + 1]
        out.crew = { name = crew.name, xp = crew.xp, level = lv, nextXp = nextXp, floor = floor, share = crew.share, leader = crew.leader == cid, members = list,
            bonus = math.floor((lv - 1) * cfg().SellBonusPerLevel * 100 + 0.5) }
    end
    return out
end

local function cleanName(name)
    if type(name) ~= 'string' then return nil end
    name = name:gsub('^%s+', ''):gsub('%s+$', ''):gsub('%s+', ' ')
    if #name < cfg().NameMin or #name > cfg().NameMax or not name:match('^[%w ]+$') then return nil end
    return name
end

function Cr.create(src, cid, name)
    if not cfg().Enabled then return Veyl.Err('UNAVAILABLE', 'Crews are off') end
    name = cleanName(name)
    if not name then return Veyl.Err('INVALID_INPUT', ('Name: %d to %d letters, numbers and spaces'):format(cfg().NameMin, cfg().NameMax)) end
    if Cr.byCid[cid] then return Veyl.Err('INVALID_STATE', 'You are already in a crew') end
    for _, c in pairs(Cr.crews) do if c.name:lower() == name:lower() then return Veyl.Err('INVALID_STATE', 'That name is taken') end end
    local tag = ('prodcrew:%s:%s'):format(cid, Veyl.NewId())
    if cfg().CreateCost > 0 then
        local pay = Prod.Inv.debit(cid, cfg().CreateCost, 'Crew registration', tag)
        if not (pay and pay.ok) then return Veyl.Err(pay and pay.code or 'INSUFFICIENT_FUNDS', ('You need $%d'):format(cfg().CreateCost)) end
    end
    local id = MySQL.insert.await('INSERT INTO veyl_prod_crews (name, leader_cid, share, xp) VALUES (?, ?, 1, 0)', { name, cid })
    if not id then
        if cfg().CreateCost > 0 then Prod.Inv.credit(cid, cfg().CreateCost, 'Crew refund', tag .. ':refund') end
        return Veyl.Err('FAILED', 'Could not create it')
    end
    MySQL.update('INSERT INTO veyl_prod_crew_members (citizenid, crew_id, joined_at) VALUES (?, ?, ?)', { cid, id, os.time() })
    Cr.crews[id] = { id = id, name = name, leader = cid, share = true, xp = 0 }
    Cr.byCid[cid] = { crew = id, at = os.time() }
    Prod.Log.event('crew', cid, ('created crew "%s"'):format(name))
    return Veyl.Ok(Cr.view(cid), ('%s is yours'):format(name))
end

function Cr.invite(src, cid, targetSrc)
    local crew = Cr.of(cid)
    if not crew or crew.leader ~= cid then return Veyl.Err('NO_PERMISSION', 'Only the leader invites') end
    targetSrc = Prod.Sec.int(targetSrc, 65535)
    local tcid = targetSrc and targetSrc ~= src and Veyl.GetCitizenId(targetSrc)
    if not tcid then return Veyl.Err('INVALID_INPUT', 'Pick someone nearby') end
    local mine, theirs = Veyl.GetPlayerCoords(src), Veyl.GetPlayerCoords(targetSrc)
    if not mine or not theirs or ProdUtil.distance(mine, theirs) > cfg().InviteRange then return Veyl.Err('TOO_FAR', 'They are too far away') end
    if Cr.byCid[tcid] then return Veyl.Err('INVALID_STATE', 'They are already in a crew') end
    if count(crew.id) >= cfg().MaxMembers then return Veyl.Err('LIMIT', 'The crew is full') end
    Cr.invites[tcid] = { crew = crew.id, from = cid, fromName = Prod.Props.nameOf(cid), at = os.time() }
    TriggerClientEvent('veyl_production:crewInvite', targetSrc, { crew = crew.name, from = Prod.Props.nameOf(cid), seconds = cfg().InviteSeconds })
    return Veyl.Ok(nil, 'Invite sent')
end

function Cr.answer(src, cid, accept)
    local inv = Cr.invites[cid]
    Cr.invites[cid] = nil
    if not inv or os.time() - inv.at > cfg().InviteSeconds then return Veyl.Err('INVALID_STATE', 'That invite is gone') end
    if accept ~= true then return Veyl.Ok(Cr.view(cid), 'Declined') end
    local crew = Cr.crews[inv.crew]
    if not crew then return Veyl.Err('INVALID_STATE', 'That crew is gone') end
    if Cr.byCid[cid] then return Veyl.Err('INVALID_STATE', 'You are already in a crew') end
    if count(crew.id) >= cfg().MaxMembers then return Veyl.Err('LIMIT', 'The crew is full') end
    MySQL.update('INSERT INTO veyl_prod_crew_members (citizenid, crew_id, joined_at) VALUES (?, ?, ?)', { cid, crew.id, os.time() })
    Cr.byCid[cid] = { crew = crew.id, at = os.time() }
    Prod.Log.event('crew', cid, ('joined crew "%s"'):format(crew.name))
    return Veyl.Ok(Cr.view(cid), ('Welcome to %s'):format(crew.name))
end

local function remove(cid)
    local m = Cr.byCid[cid]
    if not m then return end
    Cr.byCid[cid] = nil
    MySQL.update('DELETE FROM veyl_prod_crew_members WHERE citizenid = ?', { cid })
    return m.crew
end

local function disband(crew)
    for _, m in ipairs(members(crew.id)) do Cr.byCid[m] = nil end
    MySQL.update('DELETE FROM veyl_prod_crew_members WHERE crew_id = ?', { crew.id })
    MySQL.update('DELETE FROM veyl_prod_crews WHERE id = ?', { crew.id })
    Cr.crews[crew.id] = nil
end

--- Leave your crew. A leader who leaves passes it to the longest-standing member; the last one out closes it.
function Cr.leave(src, cid)
    local crew = Cr.of(cid)
    if not crew then return Veyl.Err('INVALID_STATE', 'You are not in a crew') end
    remove(cid)
    local rest = members(crew.id)
    if #rest == 0 then
        disband(crew)
    elseif crew.leader == cid then
        crew.leader = rest[1]
        MySQL.update('UPDATE veyl_prod_crews SET leader_cid = ? WHERE id = ?', { crew.leader, crew.id })
    end
    Prod.Log.event('crew', cid, ('left crew "%s"'):format(crew.name))
    return Veyl.Ok(Cr.view(cid), 'You left the crew')
end

function Cr.kick(src, cid, target)
    local crew = Cr.of(cid)
    if not crew or crew.leader ~= cid then return Veyl.Err('NO_PERMISSION', 'Only the leader removes people') end
    if type(target) ~= 'string' or target == cid or not Cr.byCid[target] or Cr.byCid[target].crew ~= crew.id then return Veyl.Err('INVALID_INPUT', 'They are not in your crew') end
    remove(target)
    Prod.Log.event('crew', cid, ('removed %s from "%s"'):format(target, crew.name))
    return Veyl.Ok(Cr.view(cid), 'Removed')
end

function Cr.setShare(src, cid, on)
    local crew = Cr.of(cid)
    if not crew or crew.leader ~= cid then return Veyl.Err('NO_PERMISSION', 'Only the leader changes this') end
    crew.share = on == true
    MySQL.update('UPDATE veyl_prod_crews SET share = ? WHERE id = ?', { crew.share and 1 or 0, crew.id })
    return Veyl.Ok(Cr.view(cid), crew.share and 'Crew mates can now use your outdoor plants and benches' or 'Sharing is off')
end

function Cr.disband(src, cid)
    local crew = Cr.of(cid)
    if not crew or crew.leader ~= cid then return Veyl.Err('NO_PERMISSION', 'Only the leader closes the crew') end
    disband(crew)
    Prod.Log.event('crew', cid, ('closed crew "%s"'):format(crew.name))
    return Veyl.Ok(Cr.view(cid), 'Crew closed')
end

AddEventHandler('playerDropped', function()
    local cid = Veyl.GetCitizenId(source)
    if cid then Cr.invites[cid] = nil end
end)
