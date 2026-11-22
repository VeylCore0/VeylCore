-- veyl_gathering server: mining, farming and hunting yields, skills and the buyers. Every action is a start/finish pair
-- with a server-side minimum duration, a per-spot respawn timer and a distance check.

local C = GatheringConfig
Veyl.Startup({ 'veyl_core', 'veyl_inventory' }, function() return true end)

local function near(src, pos, d) local pc = Veyl.GetPlayerCoords(src) return pc ~= nil and #(pc - vector3(pos.x, pos.y, pos.z)) <= d end
local function give(citizenid, item, n, op) return Veyl.Await('veyl_inventory', 'GiveItem', 15000, citizenid, item, n, nil, op) end

---------------------------------------------------------------------------
-- Skills (metadata.skills = { mining = xp, ... })
---------------------------------------------------------------------------
local function skillLevel(src, skill)
    local s = exports.veyl_core:GetMetadata(src, 'skills')
    local xp = type(s) == 'table' and tonumber(s[skill]) or 0
    return math.min(5, math.floor(xp / 100)), xp
end
local function addXp(src, skill, n)
    local s = exports.veyl_core:GetMetadata(src, 'skills')
    s = type(s) == 'table' and s or {}
    s[skill] = (tonumber(s[skill]) or 0) + n
    exports.veyl_core:SetMetadata(src, 'skills', s)
end
exports('GetSkill', function(src, skill) return skillLevel(src, skill) end)

local function roll(t)
    local total = 0
    for _, v in pairs(t) do total = total + v[1] end
    local r = math.random() * total
    for item, v in pairs(t) do r = r - v[1] if r <= 0 then return item, v end end
end

---------------------------------------------------------------------------
-- Timed actions (mining, farming)
---------------------------------------------------------------------------
local pending = {}  -- [src] = { kind, index, token, at }
local spotReady = { mining = {}, farming = {} } -- [index] = os.time() when it can be used again

Veyl.RegisterCallback('begin', function(src, citizenid, kind, index)
    index = tonumber(index)
    if kind == 'mining' then
        local spot = index and C.Mining.spots[index]
        if not spot then return Veyl.Err('NOT_FOUND', 'Nothing here') end
        if not near(src, spot, 3.5) then return Veyl.Err('TOO_FAR', 'Move closer') end
        if (exports.veyl_inventory:GetItemCount(src, C.Mining.tool) or 0) < 1 then return Veyl.Err('NO_ITEM', 'You need a pickaxe') end
        if (spotReady.mining[index] or 0) > os.time() then return Veyl.Err('EMPTY', 'This rock is mined out. Try another one.') end
    elseif kind == 'farming' then
        local p = index and C.Farming.points[index]
        if not p then return Veyl.Err('NOT_FOUND', 'Nothing here') end
        if not near(src, p.coords, 3.0) then return Veyl.Err('TOO_FAR', 'Move closer') end
        if (spotReady.farming[index] or 0) > os.time() then return Veyl.Err('EMPTY', p.kind == 'cow' and 'This cow needs a rest' or 'Nothing ripe here yet') end
    else
        return Veyl.Err('INVALID_INPUT', 'Unknown action')
    end
    local token = Veyl.NewId()
    pending[src] = { kind = kind, index = index, token = token, at = GetGameTimer() }
    return Veyl.Ok({ token = token, seconds = kind == 'mining' and C.Mining.seconds or C.Farming.seconds })
end, { cooldown = 800 })

Veyl.RegisterCallback('complete', function(src, citizenid, token)
    local p = pending[src]
    pending[src] = nil
    if not p or p.token ~= token then return Veyl.Err('INVALID_STATE', 'Start again') end
    local secs = p.kind == 'mining' and C.Mining.seconds or C.Farming.seconds
    if GetGameTimer() - p.at < secs * 1000 - 600 then return Veyl.Err('TOO_FAST', 'You stopped too early') end
    local item, n
    if p.kind == 'mining' then
        if not near(src, C.Mining.spots[p.index], 4.0) then return Veyl.Err('TOO_FAR', 'You walked away') end
        if (spotReady.mining[p.index] or 0) > os.time() then return Veyl.Err('EMPTY', 'Someone beat you to it') end
        local y
        item, y = roll(C.Mining.yields)
        n = math.random(y[2], y[3])
        spotReady.mining[p.index] = os.time() + C.Mining.respawnSeconds
        -- Everyone sees the rock disappear until it refills.
        local idx = p.index
        GlobalState['veylRock' .. idx] = true
        SetTimeout(C.Mining.respawnSeconds * 1000, function() GlobalState['veylRock' .. idx] = nil end)
    else
        local pt = C.Farming.points[p.index]
        if not near(src, pt.coords, 3.5) then return Veyl.Err('TOO_FAR', 'You walked away') end
        if (spotReady.farming[p.index] or 0) > os.time() then return Veyl.Err('EMPTY', 'Someone beat you to it') end
        item, n = pt.item, math.random(pt.min, pt.max)
        spotReady.farming[p.index] = os.time() + C.Farming.respawnSeconds
    end
    local lvl = skillLevel(src, p.kind)
    if math.random() < lvl * 0.06 then n = n + 1 end
    local r = give(citizenid, item, n, 'gather:' .. token)
    if not r.ok then return Veyl.Err('INVENTORY_FULL', 'No room in your pockets') end
    addXp(src, p.kind, C.Xp[p.kind])
    return Veyl.Ok({ item = item, count = n }, ('+%d %s'):format(n, item:gsub('_', ' ')))
end, { cooldown = 300 })

---------------------------------------------------------------------------
-- Hunting: clients spawn wildlife around hunters in a zone and register it here; skinning is validated against that list
---------------------------------------------------------------------------
local animals = {}  -- [entity] = { model, owner, skinned }
local perOwner = {} -- [src] = count

local function inZone(pos)
    for _, z in ipairs(C.Hunting.zones) do if #(pos - z.center) <= z.radius then return z end end
end

Veyl.RegisterCallback('registerAnimal', function(src, _, netId, model)
    if not C.Hunting.animals[model] then return Veyl.Err('INVALID_INPUT', 'Unknown animal') end
    if (perOwner[src] or 0) >= C.Hunting.maxAnimals + 2 then return Veyl.Err('LIMIT', 'Enough animals around') end
    local e = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if not e or e == 0 or not DoesEntityExist(e) or GetEntityType(e) ~= 1 or GetEntityModel(e) ~= joaat(model) then return Veyl.Err('NOT_FOUND', 'No animal') end
    if not inZone(GetEntityCoords(e)) then return Veyl.Err('TOO_FAR', 'Not in a hunting area') end
    animals[e] = { model = model, owner = src }
    perOwner[src] = (perOwner[src] or 0) + 1
    return Veyl.Ok()
end, { cooldown = 500 })

Veyl.RegisterCallback('releaseAnimal', function(src, _, netId)
    local e = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    local a = e and animals[e]
    if a and a.owner == src then animals[e] = nil perOwner[src] = math.max(0, (perOwner[src] or 1) - 1) end
    return Veyl.Ok()
end, { cooldown = 100 })

Veyl.RegisterCallback('skin', function(src, citizenid, netId)
    local e = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    local a = e and animals[e]
    if not a or a.skinned then return Veyl.Err('NOT_FOUND', 'Nothing to skin') end
    if GetEntityHealth(e) > 0 then return Veyl.Err('INVALID_STATE', 'It is still alive') end
    if not near(src, GetEntityCoords(e), 3.0) then return Veyl.Err('TOO_FAR', 'Move closer') end
    if (exports.veyl_inventory:GetItemCount(src, C.Hunting.knife) or 0) < 1 then return Veyl.Err('NO_ITEM', 'You need a knife') end
    a.skinned = true
    local def = C.Hunting.animals[a.model]
    local lvl = skillLevel(src, 'hunting')
    local got = {}
    for item, mm in pairs(def.items) do
        local n = math.random(mm[1], mm[2]) + ((math.random() < lvl * 0.06) and 1 or 0)
        if give(citizenid, item, n, ('hunt:%d:%s'):format(netId, item)).ok then got[#got + 1] = ('%dx %s'):format(n, item:gsub('_', ' ')) end
    end
    for item, chance in pairs(def.bonus or {}) do
        if math.random() < chance and give(citizenid, item, 1, ('hunt:%d:%s'):format(netId, item)).ok then got[#got + 1] = item:gsub('_', ' ') end
    end
    addXp(src, 'hunting', C.Xp.hunting)
    animals[e] = nil
    perOwner[a.owner] = math.max(0, (perOwner[a.owner] or 1) - 1)
    SetTimeout(1500, function() if DoesEntityExist(e) then DeleteEntity(e) end end)
    return Veyl.Ok(nil, #got > 0 and ('Skinned the %s: %s'):format(def.label:lower(), table.concat(got, ', ')) or 'Your pockets are full')
end, { cooldown = 2000 })

AddEventHandler('playerDropped', function()
    local src = source
    pending[src] = nil
    perOwner[src] = nil
    for e, a in pairs(animals) do if a.owner == src then animals[e] = nil end end
end)

---------------------------------------------------------------------------
-- Buyers
---------------------------------------------------------------------------
local function buyer(id) for _, b in ipairs(C.Buyers) do if b.id == id then return b end end end

Veyl.RegisterCallback('sellList', function(src, _, id)
    local b = buyer(id)
    if not b or not near(src, b.coords, 4.0) then return Veyl.Err('TOO_FAR', 'Talk to the buyer') end
    local list = {}
    for item, price in pairs(b.prices) do
        local n = exports.veyl_inventory:GetItemCount(src, item) or 0
        if n > 0 then list[#list + 1] = { item = item, count = n, price = price } end
    end
    table.sort(list, function(x, y) return x.item < y.item end)
    return Veyl.Ok(list)
end, { cooldown = 500 })

Veyl.RegisterCallback('sell', function(src, citizenid, id, item, count)
    local b = buyer(id)
    if not b or not near(src, b.coords, 4.0) then return Veyl.Err('TOO_FAR', 'Talk to the buyer') end
    local price = b.prices[item]
    count = math.floor(tonumber(count) or 0)
    if not price or count < 1 then return Veyl.Err('INVALID_INPUT', 'They do not buy that') end
    if (exports.veyl_inventory:GetItemCount(src, item) or 0) < count then return Veyl.Err('NO_ITEM', 'You do not have that many') end
    if not exports.veyl_inventory:RemoveItem(src, item, count) then return Veyl.Err('NO_ITEM', 'Could not hand it over') end
    local total = price * count
    local r = Veyl.Await('veyl_core', 'CreditOnce', 15000, citizenid, 'cash', total, ('Sold %dx %s'):format(count, item), 'sell:' .. Veyl.NewId())
    if not r.ok then exports.veyl_inventory:AddItem(src, item, count) return Veyl.Err('INTERNAL', 'The buyer could not pay. Items returned.') end
    return Veyl.Ok(nil, ('Sold %dx %s for $%d'):format(count, item:gsub('_', ' '), total))
end, { cooldown = 800 })
