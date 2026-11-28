-- veyl_boosting schema. The resource creates and migrates these tables itself at start (server/database.lua);
-- this file is the same schema for reviewing or installing by hand.

CREATE TABLE IF NOT EXISTS veyl_boost_players (
    citizenid VARCHAR(16) NOT NULL,
    rep INT UNSIGNED NOT NULL DEFAULT 0,
    completed INT UNSIGNED NOT NULL DEFAULT 0,
    failed INT UNSIGNED NOT NULL DEFAULT 0,
    earnings BIGINT UNSIGNED NOT NULL DEFAULT 0,
    best_seconds INT UNSIGNED NULL,
    heat DOUBLE NOT NULL DEFAULT 0,
    heat_at INT UNSIGNED NOT NULL DEFAULT 0,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (citizenid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS veyl_boost_contracts (
    id VARCHAR(24) NOT NULL,
    template VARCHAR(40) NOT NULL,
    leader_cid VARCHAR(16) NOT NULL,
    state VARCHAR(20) NOT NULL,
    vehicles TEXT NOT NULL,
    reward INT UNSIGNED NOT NULL DEFAULT 0,
    payout INT UNSIGNED NULL,
    rep_reward INT NOT NULL DEFAULT 0,
    result VARCHAR(32) NULL,
    created_at INT UNSIGNED NOT NULL,
    started_at INT UNSIGNED NULL,
    expires_at INT UNSIGNED NULL,
    ended_at INT UNSIGNED NULL,
    PRIMARY KEY (id),
    KEY idx_state (state),
    KEY idx_leader (leader_cid, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS veyl_boost_members (
    contract_id VARCHAR(24) NOT NULL,
    citizenid VARCHAR(16) NOT NULL,
    role VARCHAR(8) NOT NULL DEFAULT 'member',
    share INT UNSIGNED NOT NULL DEFAULT 0,
    rep INT NOT NULL DEFAULT 0,
    paid TINYINT(1) NOT NULL DEFAULT 0,
    PRIMARY KEY (contract_id, citizenid),
    KEY idx_cid (citizenid),
    KEY idx_unpaid (paid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS veyl_boost_cooldowns (
    citizenid VARCHAR(16) NOT NULL,
    ckey VARCHAR(48) NOT NULL,
    until_at INT UNSIGNED NOT NULL,
    PRIMARY KEY (citizenid, ckey)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS veyl_boost_challenges (
    citizenid VARCHAR(16) NOT NULL,
    period VARCHAR(24) NOT NULL,
    challenge VARCHAR(40) NOT NULL,
    progress INT UNSIGNED NOT NULL DEFAULT 0,
    paid TINYINT(1) NOT NULL DEFAULT 0,
    PRIMARY KEY (citizenid, period, challenge)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS veyl_boost_activity (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    citizenid VARCHAR(16) NOT NULL,
    kind VARCHAR(16) NOT NULL,
    text VARCHAR(120) NOT NULL,
    detail VARCHAR(60) NULL,
    at INT UNSIGNED NOT NULL,
    PRIMARY KEY (id),
    KEY idx_cid (citizenid, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS veyl_boost_audit (
    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
    citizenid VARCHAR(16) NOT NULL,
    event VARCHAR(32) NOT NULL,
    data TEXT NULL,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    KEY idx_cid (citizenid, id),
    KEY idx_event (event, id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Optional, one time: carry reputation over from the first version of boosting (it kept it in veyl_boosting_rep).
-- The resource does this itself (scaled by BoostingConfig.LegacyRepMultiplier); run this only if you install by hand.
-- INSERT IGNORE INTO veyl_boost_players (citizenid, rep, completed) SELECT citizenid, rep * 5, completed FROM veyl_boosting_rep;
