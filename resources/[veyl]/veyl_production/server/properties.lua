-- Properties: laboratories you can buy, sell, transfer, upgrade, share and lock. Each is a private instance of an interior (a routing
-- bucket of its own). Storage is a veyl_inventory stash whose access this resource authorizes live (export AuthorizeStash).
-- Ownership, permissions, codes and raids are all decided here; the client only moves the player where the server says.

Prod = Prod or {}
Prod.Props = { rows = {}, members = {}, inside = {}, offers = {}, raids = {}, tries = {}, ready = false }
local Props = Prod.Props
local C = ProductionConfig
local P = C.Properties
local Pol = Prod.Police

local order = {}
local byId = {}
for i, p in ipairs(P.Catalogue) do byId[p.id] = p order[#order + 1] = p.id p.index = i end

local function def(id) return id and byId[id] end
function Props.exists(id) return def(id) ~= nil end
function Props.def(id) return def(id) end

local function bucketOf(id) return P.BucketBase + (def(id) and def(id).index or 0) end

---------------------------------------------------------------------------
-- State
---------------------------------------------------------------------------
function Props.load()
    Props.rows, Props.members = {}, {}
    for _, r in ipairs(MySQL.query.await('SELECT * FROM veyl_prod_properties') or {}) do
        if byId[r.id] then Props.rows[r.id] = r end
    end
    for id in pairs(byId) do
        if not Props.rows[id] then
            MySQL.insert.await('INSERT IGNORE INTO veyl_prod_properties (id, locked) VALUES (?, 1)', { id })
            Props.rows[id] = { id = id, owner_cid = nil, locked = 1, stash_gen = 1, upgrades = nil, last_raid_at = 0, raid_until = 0, price_paid = 0 }
        end
    end
    for _, m in ipairs(MySQL.query.await('SELECT property_id, citizenid, role FROM veyl_prod_members') or {}) do
        if byId[m.property_id] then
            Props.members[m.property_id] = Props.members[m.property_id] or {}
            Props.members[m.property_id][m.citizenid] = m.role
        end
    end
    Props.ready = true
    Props.registerStashes()
end

local function upgradesOf(row)
    local u = row and row.upgrades and json.decode(row.upgrades) or {}
    return type(u) == 'table' and u or {}
end

--- The upgrade levels of a lab, for the client to dress its interior (storage, benches, equipment, security; 0 = none).
function Props.looks(id)
    local r = Props.rows[id]
    local u = r and upgradesOf(r) or {}
    return { storage = u.storage or 0, benches = u.benches or 0, equipment = u.equipment or 0, security = u.security or 0 }
end

local function level(id, key)
    local row = Props.rows[id]
    return row and upgradesOf(row)[key] or 0
end

--- Storage capacity with upgrades.
function Props.storageCaps(id)
    local slots, weight = P.BaseStorage.slots, P.BaseStorage.maxWeight
    local lv = level(id, 'storage')
    for i = 1, lv do
        local l = P.Upgrades.storage.levels[i]
        if l then slots, weight = slots + l.slots, weight + l.maxWeight end
    end
    return slots, weight
end

function Props.benchSlots(id)
    if not id then return 0 end
    local n = P.BaseBenchSlots
    for i = 1, level(id, 'benches') do local l = P.Upgrades.benches.levels[i] if l then n = n + l.slots end end
    return n
end

--- Workstation timing and quality in a lab come from its equipment upgrade (1.0 / 0 outside labs).
function Props.benchSpeed(id)
    if not id then return 1.0 end
    local l = P.Upgrades.equipment.levels[level(id, 'equipment')]
    return l and l.speed or 1.0
end
function Props.benchBonus(id)
    if not id then return 0 end
    local l = P.Upgrades.equipment.levels[level(id, 'equipment')]
    return l and l.quality or 0
end

function Props.role(cid, id)
    local row = Props.rows[id]
    if not row then return nil end
    if row.owner_cid == cid then return 'owner' end
    return Props.members[id] and Props.members[id][cid] or nil
end

--- Does this player have this permission in the lab? (owner, employee, guest)
function Props.can(cid, id, perm)
    local role = Props.role(cid, id)
    return role ~= nil and ProdEnum.RolePerms[role][perm] == true
end

function Props.insideOf(src) return Props.inside[src] end

function Props.canPlaceInside(src, cid, id, pos)
    local d = def(id)
    if not d or Props.inside[src] ~= id then return false, 'You are not inside that laboratory' end
    if not (Props.can(cid, id, 'bench') or Props.can(cid, id, 'plants')) then return false, 'You cannot build here' end
    local interior = P.Interiors[d.interior]
    if not interior or ProdUtil.distance(pos, interior.spawn) > interior.radius then return false, 'Outside the laboratory' end
    return true
end

---------------------------------------------------------------------------
-- Storage (a stash registered with veyl_inventory; access is decided by AuthorizeStash)
---------------------------------------------------------------------------
local function stashId(id) return ('prod_lab_%s_%d'):format(id, Props.rows[id] and Props.rows[id].stash_gen or 1) end
Props.stashId = stashId

local function registerStash(id)
    local slots, weight = Props.storageCaps(id)
    -- Every generation is registered, so staff with production.admin can still reach storage left behind by earlier owners.
    for gen = 1, (Props.rows[id] and Props.rows[id].stash_gen or 1) do
        pcall(function()
            exports.veyl_inventory:RegisterStash({ id = ('prod_lab_%s_%d'):format(id, gen), label = (def(id).label .. ' storage'), slots = slots, maxWeight = weight,
                authorize = { resource = GetCurrentResourceName(), export = 'AuthorizeStash' } })
        end)
    end
end

function Props.registerStashes()
    for id, row in pairs(Props.rows) do if row.owner_cid or row.prev_owner_cid then registerStash(id) end end
end

--- Export for veyl_inventory: may this character open this stash right now?
function Props.authorize(src, cid, sid)
    local id, gen = tostring(sid):match('^prod_lab_([%w_]-)_(%d+)$')
    local row = id and Props.rows[id]
    if not row or not tonumber(gen) or tonumber(gen) > row.stash_gen then return false end
    if Veyl.HasPermission(src, 'production.admin') then return true end
    if tonumber(gen) ~= row.stash_gen then return false end
    if Props.inside[src] ~= id then return '!NOT_INSIDE' end
    if Props.can(cid, id, 'storage') then return true end
    if Pol.isPolice(src) and row.raid_until > os.time() then return true end
    return '!NO_PERMISSION'
end
exports('AuthorizeStash', function(src, cid, sid) return Props.authorize(src, cid, sid) end)

---------------------------------------------------------------------------
-- Views
---------------------------------------------------------------------------
local function ownedBy(cid)
    local n = 0
    for _, r in pairs(Props.rows) do if r.owner_cid == cid then n = n + 1 end end
    return n
end

--- The labs this player may use (owner, employee or guest): the client puts a map blip on each. Never anyone else's.
function Props.mineList(cid)
    local out = {}
    for _, id in ipairs(order) do
        local role = Props.role(cid, id)
        if role then
            local d = def(id)
            out[#out + 1] = { id = id, label = d.label, role = role, x = d.entry.x, y = d.entry.y, z = d.entry.z }
        end
    end
    return out
end

--- The street doors, for the client to create entrances (labels and state only).
function Props.publicList()
    local out = {}
    for _, id in ipairs(order) do
        local d, r = def(id), Props.rows[id]
        out[#out + 1] = { id = id, label = d.label, entry = { x = d.entry.x, y = d.entry.y, z = d.entry.z, w = d.entry.w }, owned = r and r.owner_cid ~= nil }
    end
    return out
end

local function membersView(id)
    local out = {}
    for _, m in ipairs(MySQL.query.await('SELECT citizenid, role, name FROM veyl_prod_members WHERE property_id = ? ORDER BY name', { id }) or {}) do
        out[#out + 1] = { id = m.citizenid, role = m.role, name = m.name ~= '' and m.name or m.citizenid }
    end
    return out
end

--- A display name for an online character (or their id when offline).
function Props.nameOf(cid)
    local src = exports.veyl_core:GetSourceByCitizenId(cid)
    local pd = src and Veyl.GetPlayerData(src)
    if pd and pd.charinfo then
        local n = ((pd.charinfo.firstname or '') .. ' ' .. (pd.charinfo.lastname or '')):match('^%s*(.-)%s*$')
        if n ~= '' then return n end
    end
    return cid
end

--- The properties tablet page for a player: what is for sale, what they own or work at.
function Props.catalogue(cid, src)
    local out = {}
    local now = os.time()
    for _, id in ipairs(order) do
        local d, r = def(id), Props.rows[id]
        local role = Props.role(cid, id)
        local entry = { id = id, label = d.label, description = d.description, price = d.price, level = d.level, branch = d.branch, role = role,
            owned = r.owner_cid ~= nil, entry = { x = d.entry.x, y = d.entry.y }, locked = r.locked == 1 }
        if not r.owner_cid then
            entry.forSale = true
            entry.canAfford = nil
            entry.levelOk = Prod.Prog.level(cid, d.branch) >= d.level
            if r.prev_owner_cid and r.buyback_until and r.buyback_until > now then
                if r.prev_owner_cid == cid then entry.buyback = { price = r.buyback_price, seconds = r.buyback_until - now }
                else entry.reserved = true end
            end
        end
        if role then
            local slots, weight = Props.storageCaps(id)
            entry.upgrades = upgradesOf(r)
            entry.storage = { slots = slots, weight = weight }
            entry.benches = { used = Prod.Ws.countIn(id), max = Props.benchSlots(id) }
            entry.hasCode = r.code_hash ~= nil
            entry.inside = src ~= nil and Props.inside[src] == id
            entry.pricePaid = r.price_paid
            entry.raidCooldown = math.max(0, (r.last_raid_at or 0) + C.Police.Raid.CooldownMinutes * 60 - now)
            if role == 'owner' then entry.members = membersView(id) end
            entry.sellFor = role == 'owner' and math.floor((r.price_paid or 0) * P.SellBackPercent) or nil
        end
        out[#out + 1] = entry
    end
    return { properties = out, owned = ownedBy(cid), maxOwned = P.MaxOwned, upgrades = P.Upgrades, interiorBase = { slots = P.BaseStorage.slots, weight = P.BaseStorage.maxWeight } }
end

---------------------------------------------------------------------------
-- Buying, selling, transferring
---------------------------------------------------------------------------
--- Everyone inside a lab is let out when it changes hands.
local function evict(id)
    for src, inside in pairs(Props.inside) do if inside == id then Props.kick(src, id) end end
end

local function clear(id)
    for _, p in pairs(Prod.Plants.rows) do if p.property_id == id then return false, 'Remove the plants from the laboratory first' end end
    for _, w in pairs(Prod.Ws.rows) do if w.property_id == id then return false, 'Pack up the benches first' end end
    return true
end

function Props.purchase(src, cid, id)
    local d, r = def(id), Props.rows[id]
    if not d or not r then Prod.Sec.invalid(src, cid, 'prop_bad_id') return Veyl.Err('INVALID_INPUT', 'Unknown property') end
    if r.owner_cid then return Veyl.Err('UNAVAILABLE', 'It is already owned') end
    if Prod.Prog.level(cid, d.branch) < d.level then return Veyl.Err('LEVEL_REQUIRED', ('Needs %s level %d'):format(d.branch, d.level)) end
    if ownedBy(cid) >= P.MaxOwned then return Veyl.Err('LIMIT', ('You can own up to %d laboratories'):format(P.MaxOwned)) end
    local now = os.time()
    local price, buyback = d.price, false
    if r.prev_owner_cid and r.buyback_until and r.buyback_until > now then
        if r.prev_owner_cid ~= cid then return Veyl.Err('UNAVAILABLE', 'It is reserved for its previous owner for a while') end
        price, buyback = r.buyback_price, true
    end
    local gen = r.stash_gen
    -- A new owner (not the one buying back) gets a fresh, empty storage.
    if not buyback and r.prev_owner_cid ~= cid then gen = gen + 1 end
    -- Claim it first: only one buyer can flip it from unowned, whatever the timing.
    local claimed = MySQL.update.await('UPDATE veyl_prod_properties SET owner_cid = ?, price_paid = ?, purchased_at = ?, locked = 1, code_hash = NULL, stash_gen = ?, prev_owner_cid = NULL, buyback_price = NULL, buyback_until = NULL WHERE id = ? AND owner_cid IS NULL',
        { cid, price, now, gen, id })
    if (claimed or 0) < 1 then return Veyl.Err('UNAVAILABLE', 'Someone else just bought it') end
    local pay = Prod.Inv.debit(cid, price, ('Laboratory: %s'):format(d.label), ('prodprop:buy:%s:%s'):format(id, Veyl.NewId()))
    if not (pay and pay.ok) then
        MySQL.update('UPDATE veyl_prod_properties SET owner_cid = NULL, price_paid = ?, stash_gen = ? WHERE id = ? AND owner_cid = ?', { r.price_paid or 0, r.stash_gen, id, cid })
        return Veyl.Err(pay and pay.code or 'INSUFFICIENT_FUNDS', 'You cannot afford that')
    end
    r.owner_cid, r.price_paid, r.purchased_at, r.locked, r.code_hash, r.stash_gen, r.prev_owner_cid, r.buyback_price, r.buyback_until = cid, price, now, 1, nil, gen, nil, nil, nil
    if gen ~= (r.stash_gen) then r.stash_gen = gen end
    if not buyback then
        MySQL.update('DELETE FROM veyl_prod_members WHERE property_id = ?', { id })
        Props.members[id] = nil
    end
    registerStash(id)
    Prod.Log.event('property', cid, ('bought %s for $%d'):format(id, price))
    return Veyl.Ok({ id = id }, ('You bought %s'):format(d.label))
end

function Props.sell(src, cid, id)
    local d, r = def(id), Props.rows[id]
    if not d or not r or r.owner_cid ~= cid then Prod.Sec.invalid(src, cid, 'prop_sell_not_owner', { id = id }) return Veyl.Err('NO_PERMISSION', 'You do not own that') end
    local ok, why = clear(id)
    if not ok then return Veyl.Err('INVALID_STATE', why) end
    local back = math.floor((r.price_paid or 0) * P.SellBackPercent)
    local now = os.time()
    local flipped = MySQL.update.await('UPDATE veyl_prod_properties SET owner_cid = NULL, prev_owner_cid = ?, buyback_price = ?, buyback_until = ?, code_hash = NULL, locked = 1 WHERE id = ? AND owner_cid = ?',
        { cid, math.floor(back * P.BuybackPercent), now + P.BuybackHours * 3600, id, cid })
    if (flipped or 0) < 1 then return Veyl.Err('INVALID_STATE', 'It was already sold') end
    evict(id)
    r.owner_cid, r.prev_owner_cid, r.buyback_price, r.buyback_until, r.code_hash, r.locked = nil, cid, math.floor(back * P.BuybackPercent), now + P.BuybackHours * 3600, nil, 1
    Prod.Inv.credit(cid, back, ('Sold laboratory: %s'):format(d.label), ('prodprop:sell:%s:%d'):format(id, now))
    MySQL.update('DELETE FROM veyl_prod_members WHERE property_id = ?', { id })
    Props.members[id] = nil
    Prod.Log.event('property', cid, ('sold %s for $%d'):format(id, back))
    return Veyl.Ok(nil, ('Sold for $%d. You can buy it back for %d hours.'):format(back, P.BuybackHours))
end

function Props.transferOffer(src, cid, id, targetSrc)
    local r = Props.rows[id]
    if not r or r.owner_cid ~= cid then return Veyl.Err('NO_PERMISSION', 'You do not own that') end
    targetSrc = Prod.Sec.int(targetSrc, 65535)
    local tcid = targetSrc and targetSrc ~= src and Veyl.GetCitizenId(targetSrc)
    if not tcid then return Veyl.Err('NOT_FOUND', 'That player is not available') end
    local a, b = Veyl.GetPlayerCoords(src), Veyl.GetPlayerCoords(targetSrc)
    if not a or not b or ProdUtil.distance(a, b) > C.Distance.Property then return Veyl.Err('TOO_FAR', 'They are too far away') end
    if ownedBy(tcid) >= P.MaxOwned then return Veyl.Err('LIMIT', 'They own too many laboratories already') end
    local ok, why = clear(id)
    if not ok then return Veyl.Err('INVALID_STATE', why) end
    Props.offers[tcid] = { id = id, from = cid, at = os.time() }
    TriggerClientEvent('veyl_production:transferOffer', targetSrc, { property = def(id).label, from = Prod.Props.nameOf(cid), seconds = P.TransferSeconds })
    return Veyl.Ok(nil, 'Offer sent')
end

function Props.transferAnswer(src, cid, accept)
    local o = Props.offers[cid]
    Props.offers[cid] = nil
    if not o or os.time() - o.at > P.TransferSeconds then return Veyl.Err('NOT_FOUND', 'That offer expired') end
    if not accept then return Veyl.Ok(nil, 'Declined') end
    local r = Props.rows[o.id]
    if not r or r.owner_cid ~= o.from then return Veyl.Err('INVALID_STATE', 'It is no longer theirs to give') end
    if ownedBy(cid) >= P.MaxOwned then return Veyl.Err('LIMIT', 'You own too many laboratories') end
    local ok, why = clear(o.id)
    if not ok then return Veyl.Err('INVALID_STATE', why) end
    local gen = r.stash_gen + 1
    local flipped = MySQL.update.await('UPDATE veyl_prod_properties SET owner_cid = ?, stash_gen = ?, code_hash = NULL, locked = 1 WHERE id = ? AND owner_cid = ?', { cid, gen, o.id, o.from })
    if (flipped or 0) < 1 then return Veyl.Err('INVALID_STATE', 'It changed hands already') end
    evict(o.id)
    r.owner_cid, r.stash_gen, r.code_hash, r.locked = cid, gen, nil, 1
    MySQL.update('DELETE FROM veyl_prod_members WHERE property_id = ?', { o.id })
    Props.members[o.id] = nil
    registerStash(o.id)
    Prod.Log.event('property', cid, ('received %s from %s'):format(o.id, o.from))
    return Veyl.Ok(nil, ('You now own %s'):format(def(o.id).label))
end

---------------------------------------------------------------------------
-- Upgrades
---------------------------------------------------------------------------
function Props.upgrade(src, cid, id, key)
    local r = Props.rows[id]
    if not r or r.owner_cid ~= cid then return Veyl.Err('NO_PERMISSION', 'You do not own that') end
    local u = key and P.Upgrades[key]
    if not u then Prod.Sec.invalid(src, cid, 'prop_bad_upgrade', { key = key }) return Veyl.Err('INVALID_INPUT', 'Unknown upgrade') end
    local ups = upgradesOf(r)
    local lv = (ups[key] or 0) + 1
    local step = u.levels[lv]
    if not step then return Veyl.Err('INVALID_STATE', 'Already at the top level') end
    local before = r.upgrades
    ups[key] = lv
    local after = json.encode(ups)
    -- Conditional on the stored value, so two clicks at once cannot both succeed.
    local claimed = MySQL.update.await('UPDATE veyl_prod_properties SET upgrades = ? WHERE id = ? AND owner_cid = ? AND upgrades <=> ?', { after, id, cid, before })
    if (claimed or 0) < 1 then return Veyl.Err('BUSY', 'It changed, try again') end
    local pay = Prod.Inv.debit(cid, step.price, ('Laboratory upgrade: %s %d'):format(u.label, lv), ('produp:%s:%s:%d'):format(id, key, lv))
    if not (pay and pay.ok) then
        MySQL.update('UPDATE veyl_prod_properties SET upgrades = ? WHERE id = ? AND upgrades = ?', { before, id, after })
        return Veyl.Err(pay and pay.code or 'INSUFFICIENT_FUNDS', 'You cannot afford that')
    end
    r.upgrades = after
    if key == 'storage' then registerStash(id) end
    -- Anyone standing inside sees the new equipment appear.
    for who, inId in pairs(Props.inside) do
        if inId == id then TriggerClientEvent('veyl_production:looks', who, id, Props.looks(id), key, lv) end
    end
    Prod.Log.event('upgrade', cid, ('%s: %s level %d ($%d)'):format(id, key, lv, step.price))
    return Veyl.Ok({ level = lv }, ('%s upgraded to level %d'):format(u.label, lv))
end

---------------------------------------------------------------------------
-- Security and permissions
---------------------------------------------------------------------------
function Props.setLocked(src, cid, id, locked)
    local r = Props.rows[id]
    if not r or not Props.can(cid, id, 'security') then return Veyl.Err('NO_PERMISSION', 'Only the owner can do that') end
    r.locked = locked and 1 or 0
    MySQL.update('UPDATE veyl_prod_properties SET locked = ? WHERE id = ?', { r.locked, id })
    Prod.Log.event('security', cid, ('%s %s'):format(id, locked and 'locked' or 'unlocked'))
    return Veyl.Ok({ locked = locked }, locked and 'Locked' or 'Unlocked: anyone can walk in')
end

function Props.setCode(src, cid, id, code)
    local r = Props.rows[id]
    if not r or not Props.can(cid, id, 'security') then return Veyl.Err('NO_PERMISSION', 'Only the owner can do that') end
    if code == nil or code == '' then
        r.code_hash = nil
        MySQL.update('UPDATE veyl_prod_properties SET code_hash = NULL WHERE id = ?', { id })
        Prod.Log.event('security', cid, ('%s code removed'):format(id))
        return Veyl.Ok(nil, 'Access code removed')
    end
    local pattern = ('^%%d{%d,%d}$'):format(P.Code.MinLength, P.Code.MaxLength)
    if type(code) ~= 'string' or #code < P.Code.MinLength or #code > P.Code.MaxLength or not code:match('^%d+$') then
        return Veyl.Err('INVALID_INPUT', ('The code is %d to %d digits'):format(P.Code.MinLength, P.Code.MaxLength))
    end
    r.code_hash = Crypto.Hash(code)
    MySQL.update('UPDATE veyl_prod_properties SET code_hash = ? WHERE id = ?', { r.code_hash, id })
    Prod.Log.event('security', cid, ('%s code changed'):format(id)) -- never the code itself
    return Veyl.Ok(nil, 'Access code set')
end

function Props.addMember(src, cid, id, targetSrc, role)
    local r = Props.rows[id]
    if not r or not Props.can(cid, id, 'manage') then return Veyl.Err('NO_PERMISSION', 'Only the owner can do that') end
    if role ~= 'employee' and role ~= 'guest' then return Veyl.Err('INVALID_INPUT', 'Pick employee or guest') end
    targetSrc = Prod.Sec.int(targetSrc, 65535)
    local tcid = targetSrc and targetSrc ~= src and Veyl.GetCitizenId(targetSrc)
    if not tcid then return Veyl.Err('NOT_FOUND', 'That player is not available') end
    local a, b = Veyl.GetPlayerCoords(src), Veyl.GetPlayerCoords(targetSrc)
    if not a or not b or ProdUtil.distance(a, b) > C.Distance.Property then return Veyl.Err('TOO_FAR', 'They are too far away') end
    local counts = { employee = 0, guest = 0 }
    for _, rl in pairs(Props.members[id] or {}) do counts[rl] = counts[rl] + 1 end
    local existing = Props.members[id] and Props.members[id][tcid]
    if not existing and counts[role] >= (role == 'employee' and P.MaxEmployees or P.MaxGuests) then return Veyl.Err('LIMIT', 'No room for more') end
    MySQL.update('INSERT INTO veyl_prod_members (property_id, citizenid, role, name, added_by, added_at) VALUES (?, ?, ?, ?, ?, ?) ON DUPLICATE KEY UPDATE role = VALUES(role), name = VALUES(name)', { id, tcid, role, Props.nameOf(tcid), cid, os.time() })
    Props.members[id] = Props.members[id] or {}
    Props.members[id][tcid] = role
    Prod.Log.event('permission', cid, ('%s: %s is now %s'):format(id, tcid, role))
    return Veyl.Ok(nil, ('Added as %s'):format(role))
end

function Props.removeMember(src, cid, id, target)
    local r = Props.rows[id]
    if not r or not Props.can(cid, id, 'manage') then return Veyl.Err('NO_PERMISSION', 'Only the owner can do that') end
    target = Prod.Sec.str(target, 16, '^[%w]+$')
    if not target or not (Props.members[id] and Props.members[id][target]) then return Veyl.Err('NOT_FOUND', 'Not a member') end
    MySQL.update('DELETE FROM veyl_prod_members WHERE property_id = ? AND citizenid = ?', { id, target })
    Props.members[id][target] = nil
    -- Anyone removed while inside is let out by the exit, and loses storage access at once (access is checked on every open).
    local tsrc = exports.veyl_core:GetSourceByCitizenId(target)
    if tsrc and Props.inside[tsrc] == id then Props.kick(tsrc, id) end
    Prod.Log.event('permission', cid, ('%s: removed %s'):format(id, target))
    return Veyl.Ok(nil, 'Access removed')
end

---------------------------------------------------------------------------
-- Entering and leaving
---------------------------------------------------------------------------
local function setInside(src, id)
    Props.inside[src] = id
    SetPlayerRoutingBucket(src, id and bucketOf(id) or 0)
end

function Props.kick(src, id)
    local d = def(id)
    setInside(src, nil)
    if d then TriggerClientEvent('veyl_production:leave', src, { x = d.entry.x, y = d.entry.y, z = d.entry.z, w = d.entry.w }) end
end

function Props.enter(src, cid, id, code)
    local d, r = def(id), Props.rows[id]
    if not d or not r then return Veyl.Err('NOT_FOUND', 'Unknown property') end
    if not r.owner_cid then return Veyl.Err('UNAVAILABLE', 'Nobody owns this yet') end
    if Props.inside[src] then return Veyl.Err('INVALID_STATE', 'You are already inside') end
    if not Prod.Sec.near(src, d.entry, C.Distance.Property) then return Veyl.Err('TOO_FAR', 'Go to the door') end
    local role = Props.role(cid, id)
    local via = role
    if not role then
        if Pol.isPolice(src) and r.raid_until > os.time() then via = 'police'
        elseif r.locked == 1 then
            if not r.code_hash then return Veyl.Err('LOCKED', 'It is locked') end
            local key = cid .. ':' .. id
            local t = Props.tries[key]
            if t and t.lockedUntil and t.lockedUntil > os.time() then return Veyl.Err('LOCKED', ('Too many tries. Wait %d s'):format(t.lockedUntil - os.time())) end
            if type(code) ~= 'string' or code == '' then return Veyl.Err('CODE_REQUIRED', 'Enter the access code') end
            if not Crypto.Verify(code, r.code_hash) then
                t = t or { n = 0 }
                t.n = t.n + 1
                if t.n >= P.Code.MaxAttempts then t.n, t.lockedUntil = 0, os.time() + P.Code.LockoutSeconds end
                Props.tries[key] = t
                Prod.Log.event('security', cid, ('wrong code at %s'):format(id))
                return Veyl.Err('WRONG_CODE', 'Wrong code')
            end
            Props.tries[key] = nil
            via = 'visitor'
        else
            via = 'visitor'
        end
    end
    if P.RequireAccessCard and via ~= 'police' and Prod.Inv.count(src, ProdItems.access_card) < 1 then return Veyl.Err('NO_ITEM', 'You need a lab access card') end
    setInside(src, id)
    Pol.maybeAlert(cid, 'property_entry', d.entry)
    -- A visitor at a lab with security level 1+ is reported to the owner.
    if via == 'visitor' and level(id, 'security') >= 1 then
        local osrc = exports.veyl_core:GetSourceByCitizenId(r.owner_cid)
        if osrc then Veyl.Notify(osrc, ('Someone entered %s.'):format(d.label), 'warning') end
    end
    local interior = P.Interiors[d.interior]
    return Veyl.Ok({ id = id, label = d.label, role = via, ipl = interior.ipl, spawn = { x = interior.spawn.x, y = interior.spawn.y, z = interior.spawn.z, w = interior.spawn.w },
        door = { x = interior.door.x, y = interior.door.y, z = interior.door.z }, radius = interior.radius,
        interior = d.interior, looks = Props.looks(id) })
end

--- The look of the lab you are standing in (the client asks again after a reconnect to the interior).
function Props.looksInside(src)
    local id = Props.inside[src]
    if not id then return Veyl.Err('INVALID_STATE', 'You are not inside a laboratory') end
    return Veyl.Ok({ id = id, looks = Props.looks(id) })
end

function Props.exit(src, cid)
    local id = Props.inside[src]
    local d = id and def(id)
    if not d then return Veyl.Err('INVALID_STATE', 'You are not inside a laboratory') end
    local interior = P.Interiors[d.interior]
    if not Prod.Sec.near(src, interior.door, 10.0) then return Veyl.Err('TOO_FAR', 'Walk to the exit') end
    setInside(src, nil)
    return Veyl.Ok({ x = d.entry.x, y = d.entry.y, z = d.entry.z, w = d.entry.w })
end

--- A player who left the game inside a lab appears at its door again (their saved coordinates are inside an interior that is only
--- there for people in the lab's bucket). Returns the street door of the nearest lab whose interior they were standing in, or nil.
function Props.recover(src)
    if Props.inside[src] then return nil end
    local pc = Veyl.GetPlayerCoords(src)
    if not pc then return nil end
    for _, id in ipairs(order) do
        local d = def(id)
        local interior = P.Interiors[d.interior]
        if ProdUtil.distance(pc, interior.spawn) <= interior.radius + 20.0 then
            return Veyl.Ok({ x = d.entry.x, y = d.entry.y, z = d.entry.z, w = d.entry.w })
        end
    end
    return nil
end

--- Storage access for the lab the player is standing in (the page asks, the inventory then opens the stash it names).
function Props.storage(src, cid, id)
    local d = def(id)
    if not d or Props.inside[src] ~= id then return Veyl.Err('INVALID_STATE', 'Be inside the laboratory') end
    local ok = Props.authorize(src, cid, stashId(id))
    if ok ~= true then return Veyl.Err('NO_PERMISSION', 'You cannot open the storage') end
    return Veyl.Ok({ stash = stashId(id) })
end

AddEventHandler('playerDropped', function()
    local src = source
    Props.inside[src] = nil
    local cid = Veyl.GetCitizenId(src)
    if cid then Props.offers[cid] = nil end
    Props.raids[src] = nil
end)

---------------------------------------------------------------------------
-- Raids (police). Disabled unless ProductionConfig.Police.Enabled.
---------------------------------------------------------------------------
local R = C.Police.Raid

function Props.raidStart(src, cid, id)
    local d, r = def(id), Props.rows[id]
    if not d or not r or not r.owner_cid then return Veyl.Err('NOT_FOUND', 'Nothing to raid') end
    if not Pol.isPolice(src) then Prod.Sec.invalid(src, cid, 'raid_not_police') return Veyl.Err('NO_PERMISSION', 'Police only') end
    if Pol.onDuty() < C.Police.MinOnDuty then return Veyl.Err('UNAVAILABLE', 'Not enough officers on duty') end
    local now = os.time()
    if r.raid_until > now then return Veyl.Err('INVALID_STATE', 'The door is already open') end
    if now - (r.last_raid_at or 0) < R.CooldownMinutes * 60 then return Veyl.Err('RATE_LIMITED', 'This place was raided recently') end
    if not Prod.Sec.near(src, d.entry, C.Distance.Property) then return Veyl.Err('TOO_FAR', 'Go to the door') end
    local seconds = R.BreachSeconds
    local sec = P.Upgrades.security.levels[level(id, 'security')]
    if sec then seconds = seconds + sec.breachSeconds end
    local token = Veyl.NewId()
    Props.raids[src] = { id = id, token = token, at = GetGameTimer(), seconds = seconds }
    return Veyl.Ok({ token = token, seconds = seconds })
end

function Props.raidFinish(src, cid, token)
    local a = Props.raids[src]
    Props.raids[src] = nil
    if not a or a.token ~= token then Prod.Sec.invalid(src, cid, 'raid_bad_token') return Veyl.Err('INVALID_STATE', 'Start again') end
    if GetGameTimer() - a.at < a.seconds * 1000 - 600 then Prod.Sec.invalid(src, cid, 'raid_too_fast') return Veyl.Err('TOO_FAST', 'You stopped too early') end
    local d, r = def(a.id), Props.rows[a.id]
    if not Pol.isPolice(src) or not Prod.Sec.near(src, d.entry, C.Distance.Property + 2.0) then return Veyl.Err('INVALID_STATE', 'The breach failed') end
    local now = os.time()
    r.raid_until, r.last_raid_at = now + R.DurationMinutes * 60, now
    MySQL.update('UPDATE veyl_prod_properties SET raid_until = ?, last_raid_at = ? WHERE id = ?', { r.raid_until, now, a.id })
    local osrc = exports.veyl_core:GetSourceByCitizenId(r.owner_cid)
    if osrc then Veyl.Notify(osrc, ('Police have breached %s.'):format(d.label), 'error') end
    Prod.Log.event('raid', cid, ('breached %s'):format(a.id), { owner = r.owner_cid })
    return Veyl.Ok({ minutes = R.DurationMinutes }, 'Breached. You can go in and open the storage.')
end

--- Seizes the configured items from the lab's storage (the storage must be loaded: open it once first) and cancels bench batches.
function Props.raidSeize(src, cid, id)
    local d, r = def(id), Props.rows[id]
    if not d or not r or not Pol.isPolice(src) then return Veyl.Err('NO_PERMISSION', 'Police only') end
    if r.raid_until <= os.time() then return Veyl.Err('INVALID_STATE', 'The raid window has closed') end
    if Props.inside[src] ~= id then return Veyl.Err('INVALID_STATE', 'Go inside first') end
    local target = 'stash:' .. stashId(id)
    local items = exports.veyl_inventory:GetInventoryItems(target) or {}
    local wanted, all = {}, #R.SeizeItems == 0
    for _, n in ipairs(R.SeizeItems) do wanted[n] = true end
    local seized = 0
    for _, it in pairs(items) do
        if all or wanted[it.name] then
            local ok = exports.veyl_inventory:RemoveItem(target, it.name, it.count, next(it.metadata or {}) and it.metadata or nil)
            if ok then seized = seized + it.count end
        end
    end
    local benches = 0
    if R.SeizeBenches then
        for _, w in pairs(Prod.Ws.rows) do if w.property_id == id then Prod.Ws.wipe(w.id) benches = benches + 1 end end
    end
    if seized == 0 and benches == 0 then return Veyl.Err('NOTHING_FOUND', 'Nothing to seize (open the storage first if it is not loaded)') end
    Prod.Log.event('raid', cid, ('seized %d items and stopped %d benches at %s'):format(seized, benches, id), { owner = r.owner_cid })
    return Veyl.Ok({ items = seized, benches = benches }, ('Seized %d items'):format(seized))
end

