-- Persistence: migrations, loading and one-transaction commits. Every mutation writes the changed slots,
-- the inventory revisions and the operation record together, so a change either fully happened or not at all.

DB = {}

local MIGRATIONS = {
    {
        id = '001_engine',
        sql = {
            [[CREATE TABLE IF NOT EXISTS veyl_inventories (
                id VARCHAR(96) NOT NULL,
                type ENUM('player','stash','trunk','glovebox','drop') NOT NULL,
                owner VARCHAR(64) NULL,
                label VARCHAR(64) NOT NULL DEFAULT '',
                slots SMALLINT UNSIGNED NOT NULL,
                max_weight INT UNSIGNED NOT NULL,
                revision BIGINT UNSIGNED NOT NULL DEFAULT 0,
                schema_version SMALLINT UNSIGNED NOT NULL DEFAULT 1,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (id),
                KEY idx_owner (owner)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS veyl_inventory_slots (
                inventory_id VARCHAR(96) NOT NULL,
                slot SMALLINT UNSIGNED NOT NULL,
                item VARCHAR(64) NOT NULL,
                count INT UNSIGNED NOT NULL,
                metadata LONGTEXT NULL,
                instance_id VARCHAR(40) NULL,
                PRIMARY KEY (inventory_id, slot),
                UNIQUE KEY uq_instance (instance_id),
                CONSTRAINT chk_slot_count CHECK (count > 0)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS veyl_inventory_operations (
                op_id VARCHAR(100) NOT NULL,
                actor VARCHAR(64) NOT NULL,
                kind VARCHAR(32) NOT NULL,
                inventories VARCHAR(255) NOT NULL,
                fingerprint VARCHAR(512) NOT NULL,
                outcome ENUM('ok','failed') NOT NULL,
                result LONGTEXT NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (op_id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS veyl_inventory_reservations (
                id VARCHAR(64) NOT NULL,
                inventory_id VARCHAR(96) NOT NULL,
                slot SMALLINT UNSIGNED NOT NULL,
                item VARCHAR(64) NOT NULL,
                count INT UNSIGNED NOT NULL,
                op_id VARCHAR(100) NOT NULL,
                status ENUM('active','consumed','released','expired') NOT NULL DEFAULT 'active',
                expires_at TIMESTAMP NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (id),
                KEY idx_status (status)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS veyl_inventory_audit (
                id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                op_id VARCHAR(100) NOT NULL,
                kind VARCHAR(32) NOT NULL,
                inventory_id VARCHAR(96) NOT NULL,
                item VARCHAR(64) NOT NULL,
                delta INT NOT NULL,
                actor VARCHAR(64) NULL,
                reason VARCHAR(128) NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (id),
                KEY idx_op (op_id),
                KEY idx_inventory (inventory_id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        },
    },
}

function DB.Migrate()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS veyl_migrations (
        resource VARCHAR(64) NOT NULL, id VARCHAR(128) NOT NULL,
        applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (resource, id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    for _, m in ipairs(MIGRATIONS) do
        if not MySQL.scalar.await('SELECT 1 FROM veyl_migrations WHERE resource = ? AND id = ?', { 'veyl_inventory', m.id }) then
            for _, sql in ipairs(m.sql) do MySQL.query.await(sql) end
            MySQL.insert.await('INSERT INTO veyl_migrations (resource, id) VALUES (?, ?)', { 'veyl_inventory', m.id })
            print(('^2[veyl_inventory] applied migration %s^7'):format(m.id))
        end
    end
    -- Item-use reservations never survive a restart: the effect was never applied.
    MySQL.update.await("UPDATE veyl_inventory_reservations SET status = 'expired' WHERE status = 'active'")
end

--- Loads (or creates) an inventory row and its slots.
function DB.Load(id, defaults)
    local row = MySQL.single.await('SELECT id, type, owner, label, slots, max_weight, revision FROM veyl_inventories WHERE id = ?', { id })
    if not row then
        MySQL.insert.await('INSERT IGNORE INTO veyl_inventories (id, type, owner, label, slots, max_weight) VALUES (?, ?, ?, ?, ?, ?)',
            { id, defaults.type, defaults.owner, defaults.label or '', defaults.slots, defaults.maxWeight })
        row = MySQL.single.await('SELECT id, type, owner, label, slots, max_weight, revision FROM veyl_inventories WHERE id = ?', { id })
    elseif defaults.slots ~= row.slots or defaults.maxWeight ~= row.max_weight or (defaults.label and defaults.label ~= row.label) then
        -- Configuration changes apply to existing inventories (slots only ever grow here: shrinking is refused).
        local slots = math.max(defaults.slots, row.slots)
        MySQL.update.await('UPDATE veyl_inventories SET slots = ?, max_weight = ?, label = ? WHERE id = ?',
            { slots, defaults.maxWeight, defaults.label or row.label, id })
        row.slots, row.max_weight, row.label = slots, defaults.maxWeight, defaults.label or row.label
    end
    local rows = MySQL.query.await('SELECT slot, item, count, metadata, instance_id FROM veyl_inventory_slots WHERE inventory_id = ?', { id }) or {}
    local items, unknown = {}, 0
    for _, r in ipairs(rows) do
        if ItemDefs[r.item] then
            local ok, meta = pcall(json.decode, r.metadata or '{}')
            items[r.slot] = { slot = r.slot, name = r.item, count = r.count, metadata = ok and meta or {}, instance = r.instance_id }
        else
            -- Unknown items are kept in the database untouched (never silently discarded) but not loaded.
            unknown = unknown + 1
        end
    end
    if unknown > 0 then print(('^3[veyl_inventory] %s has %d slot(s) with unknown items (left in the database)^7'):format(id, unknown)) end
    return row, items
end

--- Commits one operation atomically.
--- changes = { { inv = inventory, items = newItemsMap, slots = { slot, ... } }, ... }
--- op = { id, actor, kind, fingerprint, result } ; audit = { { inventory, item, delta, reason } }
function DB.Commit(changes, op, audit, extra)
    local queries = {}
    -- Delete every changed slot first, then insert, so moving a unique instance never trips the unique key mid-transaction.
    for _, c in ipairs(changes) do
        if #c.slots > 0 then
            local marks = {}
            for i = 1, #c.slots do marks[i] = '?' end
            local values = { c.inv.id }
            for _, s in ipairs(c.slots) do values[#values + 1] = s end
            queries[#queries + 1] = { query = ('DELETE FROM veyl_inventory_slots WHERE inventory_id = ? AND slot IN (%s)'):format(table.concat(marks, ',')), values = values }
        end
    end
    for _, c in ipairs(changes) do
        for _, s in ipairs(c.slots) do
            local it = c.items[s]
            if it then
                queries[#queries + 1] = {
                    query = 'INSERT INTO veyl_inventory_slots (inventory_id, slot, item, count, metadata, instance_id) VALUES (?, ?, ?, ?, ?, ?)',
                    values = { c.inv.id, s, it.name, it.count, json.encode(it.metadata or {}), it.instance },
                }
            end
        end
        queries[#queries + 1] = { query = 'UPDATE veyl_inventories SET revision = ? WHERE id = ?', values = { c.revision, c.inv.id } }
    end
    if op then
        queries[#queries + 1] = {
            query = 'INSERT INTO veyl_inventory_operations (op_id, actor, kind, inventories, fingerprint, outcome, result) VALUES (?, ?, ?, ?, ?, ?, ?)',
            values = { op.id, op.actor, op.kind, op.inventories, op.fingerprint, 'ok', op.result and json.encode(op.result) or nil },
        }
    end
    for _, a in ipairs(audit or {}) do
        queries[#queries + 1] = {
            query = 'INSERT INTO veyl_inventory_audit (op_id, kind, inventory_id, item, delta, actor, reason) VALUES (?, ?, ?, ?, ?, ?, ?)',
            values = { op and op.id or 'none', op and op.kind or 'write', a.inventory, a.item, a.delta, op and op.actor, a.reason },
        }
    end
    for _, q in ipairs(extra or {}) do queries[#queries + 1] = q end
    if #queries == 0 then return true end
    local ok, res = pcall(MySQL.transaction.await, queries)
    if not ok then print(('^1[veyl_inventory] commit error: %s^7'):format(tostring(res))) return false end
    return res == true
end

function DB.GetOperation(opId)
    return MySQL.single.await('SELECT op_id, actor, kind, fingerprint, outcome, result FROM veyl_inventory_operations WHERE op_id = ?', { opId })
end
