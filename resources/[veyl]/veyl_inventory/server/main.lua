-- veyl_inventory server: VeylCore-facing facade over the configured provider.

if InventoryConfig.Provider ~= 'builtin' then
    error('veyl_inventory: provider "' .. tostring(InventoryConfig.Provider) .. '" is not implemented in this release')
end

Veyl.Startup({ 'veyl_core' }, function()
    return Veyl.Migrate(Provider.Migrations())
end)

local function charOwner(charId) return 'char:' .. tostring(charId) end

local function validItem(item) return type(item) == 'string' and Items[item] ~= nil end
local function validCount(count) return Veyl.Validate.int(count, 1, 1000) end

---------------------------------------------------------------------------
-- Server exports (async: Veyl.Await('veyl_inventory', name, timeout, ...))
---------------------------------------------------------------------------
exports('GetItemDefinition', function(item) return Items[item] end)

Veyl.AsyncExport('CanCarry', function(charId, item, count)
    if not Veyl.IsReady() then return Veyl.Err('NOT_READY', 'Inventory not ready') end
    if not validItem(item) or not validCount(count) then return Veyl.Err('INVALID_INPUT', 'Invalid item') end
    local weight = Provider.GetWeight(charOwner(charId))
    if weight + Items[item].weight * count > InventoryConfig.MaxWeight then
        return Veyl.Err('INVENTORY_FULL', 'Not enough space')
    end
    return Veyl.Ok(true)
end)

--- GiveItem(characterId, item, count, metadata, operationId). metadata is not stored by the builtin provider.
--- Repeat-safe: the same operationId never grants twice (returns DUPLICATE_OPERATION).
Veyl.AsyncExport('GiveItem', function(charId, item, count, _metadata, opId)
    if not Veyl.IsReady() then return Veyl.Err('NOT_READY', 'Inventory not ready') end
    if not validItem(item) or not validCount(count) or not Veyl.Validate.str(opId, 3, 90) then
        return Veyl.Err('INVALID_INPUT', 'Invalid grant')
    end
    local res = Provider.Change(charOwner(charId), item, count, opId, InventoryConfig.MaxWeight)
    if res.ok then TriggerEvent('veyl_inventory:changed', charId) end
    return res
end)

Veyl.AsyncExport('RemoveItem', function(charId, item, count, opId)
    if not Veyl.IsReady() then return Veyl.Err('NOT_READY', 'Inventory not ready') end
    if not validItem(item) or not validCount(count) or not Veyl.Validate.str(opId, 3, 90) then
        return Veyl.Err('INVALID_INPUT', 'Invalid removal')
    end
    return Provider.Change(charOwner(charId), item, -count, opId)
end)

Veyl.AsyncExport('GetItemCount', function(charId, item)
    return Veyl.Ok(Provider.GetCount(charOwner(charId), item))
end)

Veyl.AsyncExport('GetItems', function(charId)
    return Veyl.Ok(Provider.GetItems(charOwner(charId)))
end)

Veyl.AsyncExport('GetOperation', function(opId)
    return Veyl.Ok(Provider.GetOperation(opId))
end)

---------------------------------------------------------------------------
-- Player actions
---------------------------------------------------------------------------
local function listFor(owner, maxWeight)
    local items, weight = {}, 0
    for name, count in pairs(Provider.GetItems(owner)) do
        local def = Items[name]
        if def then
            items[#items + 1] = { name = name, label = def.label, count = count, weight = def.weight, usable = def.usable == true }
            weight = weight + def.weight * count
        end
    end
    table.sort(items, function(a, b) return a.label < b.label end)
    return { items = items, weight = weight, maxWeight = maxWeight }
end

Veyl.RegisterCallback('list', function(_, charId)
    return Veyl.Ok(listFor(charOwner(charId), InventoryConfig.MaxWeight))
end, { cooldown = 300 })

Veyl.RegisterCallback('use', function(src, charId, item)
    if not validItem(item) then return Veyl.Err('INVALID_INPUT', 'Unknown item') end
    local def = Items[item]
    if not def.usable then return Veyl.Err('INVALID_STATE', 'You cannot use that') end
    if GetEntityHealth(GetPlayerPed(src)) <= 0 then return Veyl.Err('INVALID_STATE', 'You cannot do that right now') end
    local res = Provider.Change(charOwner(charId), item, -1, Veyl.NewId('use:' .. item))
    if not res.ok then return res end
    if def.heal then
        local ped = GetPlayerPed(src)
        TriggerClientEvent('veyl_inventory:heal', src, def.heal)
        Veyl.Audit(src, 'item_heal', { item = item, health = ped and GetEntityHealth(ped) })
    end
    -- veyl_needs (and future resources) apply consume effects from the item definition.
    TriggerEvent('veyl_inventory:itemUsed', src, charId, item, def)
    return Veyl.Ok({ item = item, label = def.label }, 'Used ' .. def.label)
end, { cooldown = 1500 })

Veyl.RegisterCallback('give', function(src, charId, targetSrc, item, count)
    if not Veyl.Validate.int(targetSrc, 1, 65535) or not validItem(item)
        or not Veyl.Validate.int(count, 1, InventoryConfig.MaxStackPerAction) then
        return Veyl.Err('INVALID_INPUT', 'Invalid give request')
    end
    local targetChar = Veyl.GetCharacterId(targetSrc)
    if not targetChar or targetChar == charId then return Veyl.Err('NOT_FOUND', 'Player not found') end
    local a, b = Veyl.GetPlayerCoords(src), Veyl.GetPlayerCoords(targetSrc)
    if not a or not b or #(a - b) > InventoryConfig.GiveDistance then return Veyl.Err('TOO_FAR', 'Get closer to them') end
    local res = Provider.Move(charOwner(charId), charOwner(targetChar), item, count, Veyl.NewId('give'), InventoryConfig.MaxWeight)
    if res.ok then
        Veyl.Notify(targetSrc, ('You received %dx %s'):format(count, Items[item].label), 'success')
        res.message = ('Gave %dx %s'):format(count, Items[item].label)
    end
    return res
end, { cooldown = 1500 })

---------------------------------------------------------------------------
-- Stashes
---------------------------------------------------------------------------
local stashes = {}
for _, s in ipairs(InventoryConfig.Stashes) do stashes[s.id] = s end

local function stashOwner(stash, charId)
    return stash.personal and ('stash:%s:%d'):format(stash.id, charId) or ('stash:' .. stash.id)
end

local function nearStash(src, stash)
    local c = Veyl.GetPlayerCoords(src)
    return c and #(c - stash.coords) <= (stash.radius or 2.0) + 1.5
end

Veyl.RegisterCallback('stashList', function(src, charId, stashId)
    local stash = stashes[stashId]
    if not stash then return Veyl.Err('NOT_FOUND', 'Unknown stash') end
    if not nearStash(src, stash) then return Veyl.Err('TOO_FAR', 'You are too far away') end
    return Veyl.Ok({
        stash = listFor(stashOwner(stash, charId), stash.maxWeight),
        player = listFor(charOwner(charId), InventoryConfig.MaxWeight),
        label = stash.label,
    })
end, { cooldown = 300 })

Veyl.RegisterCallback('stashMove', function(src, charId, stashId, direction, item, count)
    local stash = stashes[stashId]
    if not stash or (direction ~= 'in' and direction ~= 'out') or not validItem(item)
        or not Veyl.Validate.int(count, 1, InventoryConfig.MaxStackPerAction) then
        return Veyl.Err('INVALID_INPUT', 'Invalid stash request')
    end
    if not nearStash(src, stash) then return Veyl.Err('TOO_FAR', 'You are too far away') end
    local sOwner, pOwner = stashOwner(stash, charId), charOwner(charId)
    if direction == 'in' then
        return Provider.Move(pOwner, sOwner, item, count, Veyl.NewId('stash:in'), stash.maxWeight)
    end
    return Provider.Move(sOwner, pOwner, item, count, Veyl.NewId('stash:out'), InventoryConfig.MaxWeight)
end, { cooldown = 500 })
