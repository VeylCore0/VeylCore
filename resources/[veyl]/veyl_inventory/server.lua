-- veyl_inventory server: VeylCore-facing adapter. ox_inventory owns slots, quantities and metadata.
--
-- Repeat safety: every grant/removal records an operation row BEFORE calling ox_inventory.
--   pending -> done | failed
-- A row left 'pending' (crash between the ox call and the status update) is UNKNOWN: callers must not
-- blindly retry or refund it; veyl_shops flags such purchases for staff review.

local usable = {} -- [itemName] = handler(source, item)

Veyl.Startup({ 'veyl_core' }, function()
    if GetResourceState('ox_inventory') ~= 'started' then
        error('ox_inventory is not started')
    end
    local ok = Veyl.Migrate({
        {
            id = '001_ops',
            sql = {
                [[CREATE TABLE IF NOT EXISTS veyl_inventory_ops (
                    op_id VARCHAR(100) NOT NULL,
                    citizenid VARCHAR(16) NOT NULL,
                    action ENUM('give','remove') NOT NULL,
                    item VARCHAR(64) NOT NULL,
                    count INT UNSIGNED NOT NULL,
                    status ENUM('pending','done','failed') NOT NULL DEFAULT 'pending',
                    detail VARCHAR(64) NULL,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                    PRIMARY KEY (op_id),
                    KEY idx_status (status)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            },
        },
    })
    if not ok then return false end
    for _, s in ipairs(InventoryConfig.Stashes) do
        exports.ox_inventory:RegisterStash(s.id, s.label, s.slots, s.maxWeight, s.owner, nil, s.coords)
    end
    return true
end)

local function itemDef(name)
    if type(name) ~= 'string' then return nil end
    return exports.ox_inventory:Items(name)
end

local function sourceFor(citizenid)
    return type(citizenid) == 'string' and exports.veyl_core:GetSourceByCitizenId(citizenid) or nil
end

local function validCount(count) return type(count) == 'number' and count % 1 == 0 and count >= 1 and count <= 1000 end

local function beginOp(opId, citizenid, action, item, count)
    local ok = pcall(MySQL.insert.await, 'INSERT INTO veyl_inventory_ops (op_id, citizenid, action, item, count) VALUES (?, ?, ?, ?, ?)',
        { opId, citizenid, action, item, count })
    if ok then return true end
    if MySQL.scalar.await('SELECT 1 FROM veyl_inventory_ops WHERE op_id = ?', { opId }) then
        return false, Veyl.Err('DUPLICATE_OPERATION', 'Operation already processed')
    end
    return false, Veyl.Err('DATABASE_ERROR', 'Could not record inventory operation')
end

local function finishOp(opId, status, detail)
    MySQL.update.await('UPDATE veyl_inventory_ops SET status = ?, detail = ? WHERE op_id = ?', { status, detail, opId })
end

---------------------------------------------------------------------------
-- Async exports: Veyl.Await('veyl_inventory', name, timeout, ...)
---------------------------------------------------------------------------
Veyl.AsyncExport('CanCarry', function(citizenid, item, count, metadata)
    local src = sourceFor(citizenid)
    if not src then return Veyl.Err('NOT_READY', 'Character is not online') end
    if not itemDef(item) or not validCount(count) then return Veyl.Err('INVALID_INPUT', 'Unknown item') end
    if not exports.ox_inventory:CanCarryItem(src, item, count, metadata) then return Veyl.Err('INVENTORY_FULL', 'Not enough space') end
    return Veyl.Ok(true)
end)

--- GiveItem(citizenid, item, count, metadata, operationId)
Veyl.AsyncExport('GiveItem', function(citizenid, item, count, metadata, opId)
    if not Veyl.IsReady() then return Veyl.Err('NOT_READY', 'Inventory not ready') end
    if not itemDef(item) or not validCount(count) or not Veyl.Validate.str(opId, 3, 90) then
        return Veyl.Err('INVALID_INPUT', 'Invalid grant')
    end
    local src = sourceFor(citizenid)
    if not src then return Veyl.Err('NOT_READY', 'Character is not online') end
    if not exports.ox_inventory:CanCarryItem(src, item, count, metadata) then return Veyl.Err('INVENTORY_FULL', 'Not enough space') end
    local started, err = beginOp(opId, citizenid, 'give', item, count)
    if not started then return err end
    -- Re-check the character is still the same one after the DB round trip.
    if exports.veyl_core:GetCitizenId(src) ~= citizenid then
        finishOp(opId, 'failed', 'character_changed')
        return Veyl.Err('INVALID_STATE', 'Character changed')
    end
    local success, response = exports.ox_inventory:AddItem(src, item, count, metadata)
    if success then
        finishOp(opId, 'done', nil)
        return Veyl.Ok({ item = item, count = count })
    end
    finishOp(opId, 'failed', tostring(response))
    if response == 'inventory_full' then return Veyl.Err('INVENTORY_FULL', 'Not enough space') end
    return Veyl.Err('INVALID_STATE', 'Could not add item: ' .. tostring(response))
end)

--- RemoveItem(citizenid, item, count, metadata, operationId)
Veyl.AsyncExport('RemoveItem', function(citizenid, item, count, metadata, opId)
    if not Veyl.IsReady() then return Veyl.Err('NOT_READY', 'Inventory not ready') end
    if not itemDef(item) or not validCount(count) or not Veyl.Validate.str(opId, 3, 90) then
        return Veyl.Err('INVALID_INPUT', 'Invalid removal')
    end
    local src = sourceFor(citizenid)
    if not src then return Veyl.Err('NOT_READY', 'Character is not online') end
    if (exports.ox_inventory:GetItemCount(src, item, metadata) or 0) < count then
        return Veyl.Err('NOT_ENOUGH_ITEMS', 'Not enough items')
    end
    local started, err = beginOp(opId, citizenid, 'remove', item, count)
    if not started then return err end
    if exports.veyl_core:GetCitizenId(src) ~= citizenid then
        finishOp(opId, 'failed', 'character_changed')
        return Veyl.Err('INVALID_STATE', 'Character changed')
    end
    local success, response = exports.ox_inventory:RemoveItem(src, item, count, metadata)
    finishOp(opId, success and 'done' or 'failed', success and nil or tostring(response))
    if not success then return Veyl.Err('NOT_ENOUGH_ITEMS', 'Could not remove item') end
    return Veyl.Ok({ item = item, count = count })
end)

Veyl.AsyncExport('GetItemCount', function(citizenid, item, metadata)
    local src = sourceFor(citizenid)
    if not src then return Veyl.Err('NOT_READY', 'Character is not online') end
    return Veyl.Ok(exports.ox_inventory:GetItemCount(src, item, metadata) or 0)
end)

--- GetOperation(opId) -> Ok(row|nil). status 'pending' means the outcome is unknown.
Veyl.AsyncExport('GetOperation', function(opId)
    return Veyl.Ok(MySQL.single.await('SELECT op_id, citizenid, action, item, count, status, detail FROM veyl_inventory_ops WHERE op_id = ?', { opId }))
end)

---------------------------------------------------------------------------
-- Sync exports
---------------------------------------------------------------------------
exports('GetItemDefinition', function(item) return itemDef(item) end)

--- RegisterUsableItem(item, handler(source, item)) — one use pipeline for native and QB-registered items.
exports('RegisterUsableItem', function(item, handler)
    if type(item) ~= 'string' then return false end
    local owner = GetInvokingResource() or GetCurrentResourceName()
    if usable[item] then print(('^3[veyl_inventory] usable item %s re-registered by %s^7'):format(item, owner)) end
    usable[item] = { handler = handler, owner = owner }
    return true
end)

exports('GetUsableItem', function(item) return usable[item] ~= nil end)

--- ox_inventory item server export hook: items defined with server = { export = 'veyl_inventory.useItem' }.
--- It only permits use; the effect runs once, from the 'ox_inventory:usedItem' event below.
exports('useItem', function(event)
    if event == 'usingItem' then return true end
end)

-- Single dispatch point for item effects (fires after ox_inventory has consumed the item, if consumable).
AddEventHandler('ox_inventory:usedItem', function(playerId, name, slot, metadata)
    local citizenid = exports.veyl_core:GetCitizenId(playerId)
    if not citizenid then return end
    TriggerEvent('veyl_inventory:itemUsed', playerId, citizenid, name, metadata)
    local entry = usable[name]
    if entry then
        local ok, err = pcall(entry.handler, playerId, { name = name, slot = slot, info = metadata or {}, metadata = metadata or {} })
        if not ok then print(('^1[veyl_inventory] usable item %s error: %s^7'):format(name, tostring(err))) end
    end
end)

-- Handlers registered by a resource die with it (QB-registered items come through veyl_core, which re-registers).
AddEventHandler('onResourceStop', function(res)
    for item, entry in pairs(usable) do
        if entry.owner == res then usable[item] = nil end
    end
end)
