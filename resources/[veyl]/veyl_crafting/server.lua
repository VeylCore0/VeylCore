-- veyl_crafting server: benches, recipes, crafting level (metadata.skills.crafting) and the body armour item.
-- A craft is a start/finish pair: materials are checked at both ends and taken only on finish, after the full time.

local C = CraftingConfig
Veyl.Startup({ 'veyl_core', 'veyl_inventory' }, function()
    exports.veyl_inventory:RegisterUseHandler('crafting_armor', function(ctx)
        local ped = GetPlayerPed(ctx.source)
        if ped ~= 0 then SetPedArmour(ped, 100) end
    end)
    return true
end)

local function skills(src) local s = exports.veyl_core:GetMetadata(src, 'skills') return type(s) == 'table' and s or {} end
local function level(src) return math.min(C.MaxLevel, math.floor((tonumber(skills(src).crafting) or 0) / C.XpPerLevel)) end
local function addXp(src, n)
    local s = skills(src)
    s.crafting = (tonumber(s.crafting) or 0) + n
    exports.veyl_core:SetMetadata(src, 'skills', s)
end

local function bench(id) return type(id) == 'string' and C.Benches[id] or nil end
local function near(src, pos, d) local pc = Veyl.GetPlayerCoords(src) return pc ~= nil and #(pc - pos) <= d end

local function check(src, b, ri)
    local rc = b.recipes[tonumber(ri) or 0]
    if not rc then return nil, Veyl.Err('NOT_FOUND', 'Unknown recipe') end
    if b.groups and not exports.veyl_core:HasGroup(src, b.groups) then return nil, Veyl.Err('NO_PERMISSION', 'This bench is for staff') end
    if not near(src, b.coords, 3.0) then return nil, Veyl.Err('TOO_FAR', 'Move closer') end
    if level(src) < rc.level then return nil, Veyl.Err('NO_PERMISSION', ('Needs crafting level %d'):format(rc.level)) end
    for item, n in pairs(rc.inputs) do
        if (exports.veyl_inventory:GetItemCount(src, item) or 0) < n then return nil, Veyl.Err('NO_ITEM', ('You need %dx %s'):format(n, item:gsub('_', ' '))) end
    end
    return rc
end

Veyl.RegisterCallback('bench', function(src, _, id)
    local b = bench(id)
    if not b or not near(src, b.coords, 3.5) then return Veyl.Err('TOO_FAR', 'Move closer') end
    if b.groups and not exports.veyl_core:HasGroup(src, b.groups) then return Veyl.Err('NO_PERMISSION', 'This bench is for staff') end
    local lv = level(src)
    local xp = tonumber(skills(src).crafting) or 0
    local list = {}
    for i, rc in ipairs(b.recipes) do
        local can = lv >= rc.level
        for item, n in pairs(rc.inputs) do if (exports.veyl_inventory:GetItemCount(src, item) or 0) < n then can = false end end
        list[i] = { output = rc.output, count = rc.count, seconds = rc.seconds, level = rc.level, inputs = rc.inputs, can = can, locked = lv < rc.level }
    end
    return Veyl.Ok({ label = b.label, level = lv, xp = xp, next = (lv + 1) * C.XpPerLevel, recipes = list })
end, { cooldown = 400 })

local active = {} -- [src] = { id, ri, token, at }

Veyl.RegisterCallback('start', function(src, _, id, ri)
    local b = bench(id)
    if not b then return Veyl.Err('NOT_FOUND', 'Unknown bench') end
    local rc, err = check(src, b, ri)
    if not rc then return err end
    local token = Veyl.NewId()
    active[src] = { id = id, ri = ri, token = token, at = GetGameTimer() }
    return Veyl.Ok({ token = token, seconds = rc.seconds })
end, { cooldown = 800 })

Veyl.RegisterCallback('finish', function(src, citizenid, token)
    local a = active[src]
    active[src] = nil
    if not a or a.token ~= token then return Veyl.Err('INVALID_STATE', 'Start again') end
    local b = bench(a.id)
    local rc, err = check(src, b, a.ri)
    if not rc then return err end
    if GetGameTimer() - a.at < rc.seconds * 1000 - 600 then return Veyl.Err('TOO_FAST', 'You stopped too early') end
    local fit = Veyl.Await('veyl_inventory', 'CanCarry', 15000, citizenid, rc.output, rc.count)
    if not fit.ok then return Veyl.Err('INVENTORY_FULL', 'No room for it') end
    for item, n in pairs(rc.inputs) do
        if not exports.veyl_inventory:RemoveItem(src, item, n) then return Veyl.Err('NO_ITEM', 'Missing materials') end
    end
    local r = Veyl.Await('veyl_inventory', 'GiveItem', 15000, citizenid, rc.output, rc.count, nil, 'craft:' .. token)
    if not r.ok then
        for item, n in pairs(rc.inputs) do exports.veyl_inventory:AddItem(src, item, n) end
        return Veyl.Err('INVENTORY_FULL', 'No room for it. Materials returned.')
    end
    local before = level(src)
    addXp(src, rc.xp or 1)
    local after = level(src)
    Veyl.Audit(src, 'craft', { bench = a.id, output = rc.output, count = rc.count })
    return Veyl.Ok(nil, ('Crafted %dx %s%s'):format(rc.count, rc.output:gsub('_', ' '), after > before and (' · crafting level %d!'):format(after) or ''))
end, { cooldown = 300 })

AddEventHandler('playerDropped', function() active[source] = nil end)
