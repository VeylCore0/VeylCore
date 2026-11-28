-- Schema (also in sql/install.sql). Migrations run through Veyl.Migrate and are tracked, so each runs once.

Prod = Prod or {}
Prod.DB = {}

Prod.DB.Migrations = {
    {
        id = 'v1_001_core',
        sql = {
            [[CREATE TABLE IF NOT EXISTS veyl_prod_progress (
                citizenid VARCHAR(16) NOT NULL,
                branch VARCHAR(24) NOT NULL,
                xp INT UNSIGNED NOT NULL DEFAULT 0,
                PRIMARY KEY (citizenid, branch)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS veyl_prod_stats (
                citizenid VARCHAR(16) NOT NULL,
                stat VARCHAR(32) NOT NULL,
                value BIGINT UNSIGNED NOT NULL DEFAULT 0,
                PRIMARY KEY (citizenid, stat)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS veyl_prod_cooldowns (
                citizenid VARCHAR(16) NOT NULL,
                ckey VARCHAR(64) NOT NULL,
                until_at INT UNSIGNED NOT NULL,
                PRIMARY KEY (citizenid, ckey)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS veyl_prod_stock (
                shop VARCHAR(32) NOT NULL,
                item VARCHAR(48) NOT NULL,
                stock INT UNSIGNED NOT NULL DEFAULT 0,
                restocked_at INT UNSIGNED NOT NULL DEFAULT 0,
                PRIMARY KEY (shop, item)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            -- A plant stores its meters AS OF updated_at; the current state is computed from the elapsed time.
            [[CREATE TABLE IF NOT EXISTS veyl_prod_plants (
                id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                owner_cid VARCHAR(16) NOT NULL,
                branch VARCHAR(24) NOT NULL DEFAULT 'botanical',
                variety VARCHAR(32) NOT NULL,
                x DOUBLE NOT NULL, y DOUBLE NOT NULL, z DOUBLE NOT NULL, heading DOUBLE NOT NULL DEFAULT 0,
                property_id VARCHAR(32) NULL,
                water DOUBLE NOT NULL, nutrient DOUBLE NOT NULL, health DOUBLE NOT NULL DEFAULT 100,
                growth DOUBLE NOT NULL DEFAULT 0,
                care_minutes DOUBLE NOT NULL DEFAULT 0, total_minutes DOUBLE NOT NULL DEFAULT 0,
                state VARCHAR(12) NOT NULL DEFAULT 'growing',
                harvest_claim VARCHAR(40) NULL,
                planted_at INT UNSIGNED NOT NULL, updated_at INT UNSIGNED NOT NULL,
                PRIMARY KEY (id),
                KEY idx_owner (owner_cid), KEY idx_property (property_id), KEY idx_state (state)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS veyl_prod_workstations (
                id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                owner_cid VARCHAR(16) NOT NULL,
                type VARCHAR(32) NOT NULL,
                x DOUBLE NOT NULL, y DOUBLE NOT NULL, z DOUBLE NOT NULL, heading DOUBLE NOT NULL DEFAULT 0,
                property_id VARCHAR(32) NULL,
                created_at INT UNSIGNED NOT NULL,
                PRIMARY KEY (id),
                KEY idx_owner (owner_cid), KEY idx_property (property_id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            -- A batch's times are absolute server timestamps, so progress survives restarts. claimed_at is set once, atomically.
            [[CREATE TABLE IF NOT EXISTS veyl_prod_batches (
                id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                workstation_id INT UNSIGNED NOT NULL,
                owner_cid VARCHAR(16) NOT NULL,
                recipe VARCHAR(32) NOT NULL,
                state VARCHAR(12) NOT NULL DEFAULT 'queued',
                input_quality DOUBLE NOT NULL DEFAULT 0,
                variety VARCHAR(32) NULL,
                quality DOUBLE NOT NULL DEFAULT 0,
                starts_at INT UNSIGNED NOT NULL, ends_at INT UNSIGNED NOT NULL,
                stages TEXT NOT NULL,
                refund TEXT NULL,
                created_at INT UNSIGNED NOT NULL,
                claimed_at INT UNSIGNED NULL,
                PRIMARY KEY (id),
                KEY idx_ws (workstation_id, state), KEY idx_owner (owner_cid, state)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            -- Laboratories: a row exists per catalogue property once somebody owns (or used to own) it.
            [[CREATE TABLE IF NOT EXISTS veyl_prod_properties (
                id VARCHAR(32) NOT NULL,
                owner_cid VARCHAR(16) NULL,
                price_paid INT UNSIGNED NOT NULL DEFAULT 0,
                code_hash VARCHAR(200) NULL,
                locked TINYINT(1) NOT NULL DEFAULT 1,
                upgrades TEXT NULL,
                prev_owner_cid VARCHAR(16) NULL,
                buyback_price INT UNSIGNED NULL,
                buyback_until INT UNSIGNED NULL,
                stash_gen INT UNSIGNED NOT NULL DEFAULT 1,
                last_raid_at INT UNSIGNED NOT NULL DEFAULT 0,
                raid_until INT UNSIGNED NOT NULL DEFAULT 0,
                purchased_at INT UNSIGNED NULL,
                PRIMARY KEY (id),
                KEY idx_owner (owner_cid)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS veyl_prod_members (
                property_id VARCHAR(32) NOT NULL,
                citizenid VARCHAR(16) NOT NULL,
                role VARCHAR(12) NOT NULL,
                name VARCHAR(48) NOT NULL DEFAULT '',
                added_by VARCHAR(16) NOT NULL,
                added_at INT UNSIGNED NOT NULL,
                PRIMARY KEY (property_id, citizenid),
                KEY idx_cid (citizenid)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS veyl_prod_audit (
                id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                citizenid VARCHAR(16) NOT NULL,
                kind VARCHAR(24) NOT NULL,
                text VARCHAR(200) NOT NULL,
                data TEXT NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (id),
                KEY idx_cid (citizenid, id), KEY idx_kind (kind, id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        },
    },
}

Prod.DB.Migrations[#Prod.DB.Migrations + 1] = {
    id = 'v1_002_branches',
    sql = {
        [[ALTER TABLE veyl_prod_batches ADD COLUMN yield_pct DOUBLE NOT NULL DEFAULT 1]],
        -- Supplier runs: one row per run, claimed once at each step. Times are absolute server timestamps.
        [[CREATE TABLE IF NOT EXISTS veyl_prod_runs (
            id INT UNSIGNED NOT NULL AUTO_INCREMENT,
            citizenid VARCHAR(16) NOT NULL,
            supplier VARCHAR(32) NOT NULL,
            state VARCHAR(12) NOT NULL DEFAULT 'active',
            pickup TEXT NOT NULL, dropoff TEXT NOT NULL,
            kits INT UNSIGNED NOT NULL,
            started_at INT UNSIGNED NOT NULL, expires_at INT UNSIGNED NOT NULL,
            picked_at INT UNSIGNED NULL, finished_at INT UNSIGNED NULL,
            PRIMARY KEY (id),
            KEY idx_cid (citizenid, state), KEY idx_day (citizenid, started_at)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    },
}

Prod.DB.Migrations[#Prod.DB.Migrations + 1] = {
    id = 'v1_003_farms',
    sql = {
        -- Farms placed by staff with /drugadmin: points and rewards are JSON.
        [[CREATE TABLE IF NOT EXISTS veyl_prod_farms (
            id INT UNSIGNED NOT NULL AUTO_INCREMENT,
            label VARCHAR(48) NOT NULL,
            kind VARCHAR(16) NOT NULL,
            branch VARCHAR(16) NOT NULL,
            level TINYINT UNSIGNED NOT NULL DEFAULT 1,
            prop VARCHAR(64) NOT NULL,
            respawn_min INT UNSIGNED NOT NULL DEFAULT 12,
            cooldown_min INT UNSIGNED NOT NULL DEFAULT 40,
            rewards TEXT NOT NULL, points TEXT NOT NULL,
            created_by VARCHAR(16) NULL,
            created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    },
}

Prod.DB.Migrations[#Prod.DB.Migrations + 1] = {
    id = 'v1_004_economy',
    sql = {
        [[CREATE TABLE IF NOT EXISTS veyl_prod_market (
            item VARCHAR(48) NOT NULL, pressure DOUBLE NOT NULL DEFAULT 0, updated_at INT UNSIGNED NOT NULL,
            PRIMARY KEY (item)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        [[CREATE TABLE IF NOT EXISTS veyl_prod_crews (
            id INT UNSIGNED NOT NULL AUTO_INCREMENT, name VARCHAR(24) NOT NULL, leader_cid VARCHAR(16) NOT NULL,
            share TINYINT NOT NULL DEFAULT 1, xp INT UNSIGNED NOT NULL DEFAULT 0,
            PRIMARY KEY (id), UNIQUE KEY uq_name (name)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        [[CREATE TABLE IF NOT EXISTS veyl_prod_crew_members (
            citizenid VARCHAR(16) NOT NULL, crew_id INT UNSIGNED NOT NULL, joined_at INT UNSIGNED NOT NULL,
            PRIMARY KEY (citizenid), KEY idx_crew (crew_id)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        [[CREATE TABLE IF NOT EXISTS veyl_prod_influence (
            area VARCHAR(24) NOT NULL, owner VARCHAR(24) NOT NULL, value DOUBLE NOT NULL DEFAULT 0, updated_at INT UNSIGNED NOT NULL,
            PRIMARY KEY (area, owner)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        [[CREATE TABLE IF NOT EXISTS veyl_prod_regulars (
            id INT UNSIGNED NOT NULL AUTO_INCREMENT, citizenid VARCHAR(16) NOT NULL, name VARCHAR(24) NOT NULL, model VARCHAR(48) NOT NULL,
            territory VARCHAR(24) NOT NULL, loyalty INT UNSIGNED NOT NULL DEFAULT 1, sales INT UNSIGNED NOT NULL DEFAULT 0, created_at INT UNSIGNED NOT NULL,
            PRIMARY KEY (id), KEY idx_cid (citizenid)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        [[CREATE TABLE IF NOT EXISTS veyl_prod_run_members (
            run_id INT UNSIGNED NOT NULL, citizenid VARCHAR(16) NOT NULL,
            PRIMARY KEY (run_id, citizenid), KEY idx_cid (citizenid)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    },
}

function Prod.DB.Migrate() return Veyl.Migrate(Prod.DB.Migrations) end
