-- veyl_core schema. Each migration runs once and is recorded in veyl_migrations.

CoreMigrations = {
    {
        id = '001_core_v2',
        sql = {
            [[CREATE TABLE IF NOT EXISTS veyl_accounts (
                id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                license VARCHAR(64) NOT NULL,
                name VARCHAR(64) NOT NULL DEFAULT '',
                max_characters TINYINT UNSIGNED NOT NULL DEFAULT 3,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                last_seen TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (id),
                UNIQUE KEY uq_license (license)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS veyl_players (
                id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                citizenid VARCHAR(16) NOT NULL,
                account_id INT UNSIGNED NOT NULL,
                cid TINYINT UNSIGNED NOT NULL,
                license VARCHAR(64) NOT NULL,
                charinfo LONGTEXT NOT NULL,
                metadata LONGTEXT NOT NULL,
                position LONGTEXT NULL,
                job VARCHAR(32) NOT NULL DEFAULT 'unemployed',
                gang VARCHAR(32) NOT NULL DEFAULT 'none',
                inventory LONGTEXT NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                last_updated TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                last_played TIMESTAMP NULL DEFAULT NULL,
                deleted_at TIMESTAMP NULL DEFAULT NULL,
                PRIMARY KEY (id),
                UNIQUE KEY uq_citizenid (citizenid),
                KEY idx_account (account_id, deleted_at)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS veyl_player_groups (
                citizenid VARCHAR(16) NOT NULL,
                group_type ENUM('job','gang') NOT NULL,
                name VARCHAR(32) NOT NULL,
                grade TINYINT UNSIGNED NOT NULL DEFAULT 0,
                PRIMARY KEY (citizenid, group_type, name)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS veyl_money (
                citizenid VARCHAR(16) NOT NULL,
                type VARCHAR(16) NOT NULL,
                balance BIGINT NOT NULL DEFAULT 0,
                last_op VARCHAR(100) NULL,
                PRIMARY KEY (citizenid, type),
                CONSTRAINT chk_money_nonneg CHECK (balance >= 0)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS veyl_money_ledger (
                id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                op_id VARCHAR(100) NOT NULL,
                citizenid VARCHAR(16) NOT NULL,
                type VARCHAR(16) NOT NULL,
                delta BIGINT NOT NULL,
                balance_after BIGINT NOT NULL,
                reason VARCHAR(128) NOT NULL,
                actor VARCHAR(64) NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (id),
                UNIQUE KEY uq_op (op_id),
                KEY idx_citizen (citizenid, id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS veyl_audit (
                id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                account_id INT UNSIGNED NULL,
                citizenid VARCHAR(16) NULL,
                resource VARCHAR(64) NOT NULL,
                action VARCHAR(64) NOT NULL,
                data LONGTEXT NULL,
                PRIMARY KEY (id),
                KEY idx_action (action),
                KEY idx_citizen (citizenid)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        },
    },
}

---------------------------------------------------------------------------
-- Per-citizen ordered work queue. Every DB write for a character (money, groups, saves) goes through it,
-- so writes apply in the same order as the in-memory changes they mirror.
---------------------------------------------------------------------------
local queues = {}

--- Enqueue fn for citizenid; returns a promise resolved with fn's result (or an INTERNAL error).
function CoreEnqueue(citizenid, fn)
    local q = queues[citizenid]
    if not q then
        q = { items = {}, running = false }
        queues[citizenid] = q
    end
    local p = promise.new()
    q.items[#q.items + 1] = { fn = fn, p = p }
    if not q.running then
        q.running = true
        Citizen.CreateThread(function()
            while #q.items > 0 do
                local item = table.remove(q.items, 1)
                local ok, res = pcall(item.fn)
                if not ok then
                    print(('^1[veyl_core] queued write for %s failed: %s^7'):format(citizenid, tostring(res)))
                    res = Veyl.Err('INTERNAL', 'internal error')
                end
                item.p:resolve(res)
            end
            q.running = false
            if queues[citizenid] == q then queues[citizenid] = nil end
        end)
    end
    return p
end

function CoreQueueDepth()
    local n = 0
    for _, q in pairs(queues) do n = n + #q.items + (q.running and 1 or 0) end
    return n
end
