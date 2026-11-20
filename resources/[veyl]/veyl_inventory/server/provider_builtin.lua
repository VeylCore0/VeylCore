-- Built-in inventory provider: the canonical item store when InventoryConfig.Provider == 'builtin'.
-- Owners are strings: 'char:<characterId>' or 'stash:<id>' (personal stashes: 'stash:<id>:<characterId>').
-- Every mutation runs under a per-owner lock in a single DB transaction with a unique op_id.

Provider = {}

function Provider.Migrations()
    return {
        {
            id = '001_builtin_inventory',
            sql = {
                [[CREATE TABLE IF NOT EXISTS veyl_inventory_items (
                    owner VARCHAR(64) NOT NULL,
                    item VARCHAR(64) NOT NULL,
                    count INT UNSIGNED NOT NULL,
                    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                    PRIMARY KEY (owner, item)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
                [[CREATE TABLE IF NOT EXISTS veyl_inventory_ops (
                    op_id VARCHAR(100) NOT NULL,
                    owner VARCHAR(64) NOT NULL,
                    item VARCHAR(64) NOT NULL,
                    delta INT NOT NULL,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (op_id)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            },
        },
    }
end

function Provider.GetItems(owner)
    local rows = MySQL.query.await('SELECT item, count FROM veyl_inventory_items WHERE owner = ? AND count > 0', { owner }) or {}
    local items = {}
    for _, r in ipairs(rows) do items[r.item] = r.count end
    return items
end

function Provider.GetCount(owner, item)
    return MySQL.scalar.await('SELECT count FROM veyl_inventory_items WHERE owner = ? AND item = ?', { owner, item }) or 0
end

function Provider.GetWeight(owner)
    local total = 0
    for item, count in pairs(Provider.GetItems(owner)) do
        local def = Items[item]
        total = total + (def and def.weight or 0) * count
    end
    return total
end

function Provider.GetOperation(opId)
    return MySQL.single.await('SELECT op_id, owner, item, delta FROM veyl_inventory_ops WHERE op_id = ?', { opId })
end

local function addQueries(list, owner, item, delta, opId)
    if delta > 0 then
        list[#list + 1] = {
            query = [[INSERT INTO veyl_inventory_items (owner, item, count) VALUES (?, ?, ?)
                ON DUPLICATE KEY UPDATE count = count + VALUES(count)]],
            values = { owner, item, delta },
        }
    else
        list[#list + 1] = {
            query = 'UPDATE veyl_inventory_items SET count = count - ? WHERE owner = ? AND item = ? AND count >= ?',
            values = { -delta, owner, item, -delta },
        }
        list[#list + 1] = { query = 'DELETE FROM veyl_inventory_items WHERE owner = ? AND item = ? AND count = 0', values = { owner, item } }
    end
    list[#list + 1] = {
        query = 'INSERT INTO veyl_inventory_ops (op_id, owner, item, delta) VALUES (?, ?, ?, ?)',
        values = { opId, owner, item, delta },
    }
end

--- Adds (delta > 0) or removes (delta < 0) items. maxWeight applies to additions.
function Provider.Change(owner, item, delta, opId, maxWeight)
    return Veyl.WithLock('inv:' .. owner, function()
        if Provider.GetOperation(opId) then return Veyl.Err('DUPLICATE_OPERATION', 'Operation already processed') end
        local def = Items[item]
        if delta > 0 then
            if maxWeight and Provider.GetWeight(owner) + def.weight * delta > maxWeight then
                return Veyl.Err('INVENTORY_FULL', 'Not enough space')
            end
        else
            if Provider.GetCount(owner, item) < -delta then return Veyl.Err('NOT_ENOUGH_ITEMS', 'Not enough items') end
        end
        local queries = {}
        addQueries(queries, owner, item, delta, opId)
        if not MySQL.transaction.await(queries) then return Veyl.Err('DATABASE_ERROR', 'Inventory change failed') end
        return Veyl.Ok({ count = Provider.GetCount(owner, item) })
    end)
end

--- Moves items between two owners in one transaction (give, stash deposit/withdraw).
function Provider.Move(fromOwner, toOwner, item, count, opId, toMaxWeight)
    local a, b = fromOwner, toOwner
    if b < a then a, b = b, a end
    return Veyl.WithLock('inv:' .. a, function()
        return Veyl.WithLock('inv:' .. b, function()
            if Provider.GetOperation(opId) then return Veyl.Err('DUPLICATE_OPERATION', 'Operation already processed') end
            if Provider.GetCount(fromOwner, item) < count then return Veyl.Err('NOT_ENOUGH_ITEMS', 'Not enough items') end
            if toMaxWeight and Provider.GetWeight(toOwner) + Items[item].weight * count > toMaxWeight then
                return Veyl.Err('INVENTORY_FULL', 'Not enough space')
            end
            local queries = {}
            addQueries(queries, fromOwner, item, -count, opId)
            addQueries(queries, toOwner, item, count, opId .. '#in')
            if not MySQL.transaction.await(queries) then return Veyl.Err('DATABASE_ERROR', 'Move failed; nothing changed') end
            return Veyl.Ok({})
        end)
    end)
end
