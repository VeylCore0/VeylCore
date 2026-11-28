-- Staff tools behind /drugadmin: see who is online and what they have, remove a plant, reset someone's cooldowns, give or take XP and read
-- the audit log. Every request checks the `production.admin` permission here; a player who calls these by hand is refused and logged.

Prod = Prod or {}
Prod.Admin = {}
local A = Prod.Admin
local C = ProductionConfig

local function guard(src, cid, what)
    if not Prod.Farms.isAdmin(src) then
        Prod.Log.suspicious(src, cid, 'admin_denied', { action = what })
        return false, Veyl.Err('NO_PERMISSION', 'Staff only')
    end
    return true
end

--- A citizen id the server knows (someone with progress, plants, a crew or online). Strings only, so nothing odd reaches a query.
local function knownCid(cid)
    return Prod.Sec.str(cid, 16, '^[%w_]+$')
end

function A.players(src, cid)
    local ok, err = guard(src, cid, 'players')
    if not ok then return err end
    local out = {}
    for _, s in ipairs(GetPlayers()) do
        local t = tonumber(s)
        local tc = t and Veyl.GetCitizenId(t)
        if tc then out[#out + 1] = { id = t, cid = tc, name = Prod.Props.nameOf(tc) } end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return Veyl.Ok(out)
end

function A.player(src, cid, target)
    local ok, err = guard(src, cid, 'player')
    if not ok then return err end
    target = knownCid(target)
    if not target then return Veyl.Err('INVALID_INPUT', 'Bad request') end
    local plants = {}
    for id, r in pairs(Prod.Plants.rows) do
        if r.owner_cid == target then
            local v = ProdUtil.variety(r.variety)
            plants[#plants + 1] = { id = id, label = v and v.label or r.variety, state = r.state, lab = r.property_id ~= nil, x = r.x, y = r.y, z = r.z }
        end
    end
    table.sort(plants, function(a, b) return a.id < b.id end)
    local benches = 0
    for _, w in pairs(Prod.Ws.rows) do if w.owner_cid == target then benches = benches + 1 end end
    local prog = Prod.Prog.view(target)
    local branches = {}
    for id, b in pairs(prog.branches) do branches[#branches + 1] = { id = id, label = b.label, xp = b.xp, level = b.level } end
    table.sort(branches, function(a, b) return a.id < b.id end)
    local crew = Prod.Crews.of(target)
    return Veyl.Ok({ cid = target, name = Prod.Props.nameOf(target), plants = plants, benches = benches, branches = branches, stats = prog.stats, crew = crew and crew.name or nil })
end

function A.removePlant(src, cid, id)
    local ok, err = guard(src, cid, 'removePlant')
    if not ok then return err end
    id = Prod.Sec.int(id, 2147483647)
    local row = id and Prod.Plants.rows[id]
    if not row then return Veyl.Err('NOT_FOUND', 'That plant is gone') end
    MySQL.update.await('DELETE FROM veyl_prod_plants WHERE id = ?', { id })
    Prod.Plants.rows[id] = nil
    Prod.Log.event('admin', cid, ('removed plant #%d of %s'):format(id, row.owner_cid))
    TriggerClientEvent('veyl_production:refresh', -1, 'plants')
    return Veyl.Ok(nil, 'Plant removed')
end

function A.resetCooldowns(src, cid, target)
    local ok, err = guard(src, cid, 'resetCooldowns')
    if not ok then return err end
    target = knownCid(target)
    if not target then return Veyl.Err('INVALID_INPUT', 'Bad request') end
    Prod.Sec.clearCooldowns(target)
    Prod.Log.event('admin', cid, ('reset cooldowns for %s'):format(target))
    return Veyl.Ok(nil, 'Cooldowns cleared')
end

function A.giveXp(src, cid, target, branch, amount)
    local ok, err = guard(src, cid, 'giveXp')
    if not ok then return err end
    target = knownCid(target)
    amount = tonumber(amount)
    if not target or not C.Branches[branch] or not amount or amount ~= math.floor(amount) or math.abs(amount) > 100000 or amount == 0 then return Veyl.Err('INVALID_INPUT', 'Bad request') end
    local total = Prod.Prog.give(target, branch, amount)
    Prod.Log.event('admin', cid, ('%+d %s XP for %s (now %d)'):format(amount, branch, target, total))
    return Veyl.Ok({ xp = total, level = ProdUtil.levelFor(total) }, ('%s XP is now %d (level %d)'):format(branch, total, ProdUtil.levelFor(total)))
end

--- The last audit lines: one player's, or everyone's when no target is given.
function A.log(src, cid, target)
    local ok, err = guard(src, cid, 'log')
    if not ok then return err end
    local rows
    if target ~= nil then
        target = knownCid(target)
        if not target then return Veyl.Err('INVALID_INPUT', 'Bad request') end
        rows = MySQL.query.await('SELECT citizenid, kind, text, UNIX_TIMESTAMP(created_at) AS at FROM veyl_prod_audit WHERE citizenid = ? ORDER BY id DESC LIMIT 25', { target })
    else
        rows = MySQL.query.await('SELECT citizenid, kind, text, UNIX_TIMESTAMP(created_at) AS at FROM veyl_prod_audit ORDER BY id DESC LIMIT 25')
    end
    return Veyl.Ok(rows or {})
end
