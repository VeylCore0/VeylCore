-- veyl_apartments server core: migrations, unit registry, adapters and small helpers.
-- Stable ids: a unit's `id` (veyl_apartment_units.id) never changes. Runtime routing buckets are derived at runtime
-- (AptConfig.BucketBase + id) and are never stored.

Apt = { ready = false, units = {}, unitsById = {}, buildings = {} }

local function json_ok(s, default)
    if not s or s == '' then return default end
    local ok, v = pcall(json.decode, s)
    return ok and v ~= nil and v or default
end
Apt.Decode = json_ok

Veyl.Startup({ 'veyl_core', 'veyl_inventory' }, function()
    local ok = Veyl.Migrate({
        {
            id = '001_apartments',
            sql = {
                [[CREATE TABLE IF NOT EXISTS veyl_apartment_units (
                    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                    unit_key VARCHAR(48) NOT NULL,
                    building VARCHAR(32) NOT NULL,
                    number SMALLINT UNSIGNED NOT NULL,
                    type VARCHAR(32) NOT NULL,
                    disabled TINYINT(1) NOT NULL DEFAULT 0,
                    PRIMARY KEY (id),
                    UNIQUE KEY uq_key (unit_key)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
                -- live_unit is NULL unless the lease is pending/active, so the UNIQUE key allows only ONE live lease
                -- per unit at the database level (two players can never lease the same room).
                [[CREATE TABLE IF NOT EXISTS veyl_apartment_leases (
                    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                    unit_id INT UNSIGNED NOT NULL,
                    citizenid VARCHAR(16) NOT NULL,
                    status ENUM('pending','active','ended','void') NOT NULL DEFAULT 'pending',
                    live_unit INT UNSIGNED AS (IF(status IN ('pending','active'), unit_id, NULL)) PERSISTENT,
                    rent INT UNSIGNED NOT NULL,
                    deposit INT UNSIGNED NOT NULL DEFAULT 0,
                    interval_days SMALLINT UNSIGNED NOT NULL,
                    periods_paid INT UNSIGNED NOT NULL DEFAULT 0,
                    started_at DATETIME NOT NULL,
                    paid_until DATETIME NOT NULL,
                    next_charge_at DATETIME NOT NULL,
                    reminded_for INT UNSIGNED NOT NULL DEFAULT 0,
                    autopay TINYINT(1) NOT NULL DEFAULT 1,
                    overdue_since DATETIME NULL,
                    directory TINYINT(1) NOT NULL DEFAULT 0,
                    client_op VARCHAR(64) NULL,
                    ended_at DATETIME NULL,
                    end_reason VARCHAR(32) NULL,
                    ended_by VARCHAR(64) NULL,
                    deposit_returned TINYINT(1) NOT NULL DEFAULT 0,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (id),
                    UNIQUE KEY uq_live_unit (live_unit),
                    UNIQUE KEY uq_client_op (citizenid, client_op),
                    KEY idx_cid (citizenid, status),
                    KEY idx_due (status, next_charge_at)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
                [[CREATE TABLE IF NOT EXISTS veyl_apartment_payments (
                    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                    lease_id INT UNSIGNED NOT NULL,
                    kind ENUM('initial','rent','refund','contribution') NOT NULL,
                    period INT UNSIGNED NOT NULL DEFAULT 0,
                    amount INT UNSIGNED NOT NULL,
                    paid_by VARCHAR(16) NOT NULL,
                    method VARCHAR(8) NOT NULL,
                    op_id VARCHAR(90) NOT NULL,
                    note VARCHAR(80) NULL,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (id),
                    UNIQUE KEY uq_op (op_id),
                    KEY idx_lease (lease_id, id)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
                [[CREATE TABLE IF NOT EXISTS veyl_apartment_members (
                    lease_id INT UNSIGNED NOT NULL,
                    citizenid VARCHAR(16) NOT NULL,
                    perms VARCHAR(120) NOT NULL,
                    status ENUM('invited','active') NOT NULL DEFAULT 'invited',
                    expires_at DATETIME NULL,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (lease_id, citizenid),
                    KEY idx_cid (citizenid)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
                [[CREATE TABLE IF NOT EXISTS veyl_apartment_guests (
                    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                    lease_id INT UNSIGNED NOT NULL,
                    citizenid VARCHAR(16) NOT NULL,
                    granted_by VARCHAR(16) NOT NULL,
                    source ENUM('pass','doorbell','maintenance') NOT NULL DEFAULT 'pass',
                    single_use TINYINT(1) NOT NULL DEFAULT 0,
                    expires_at DATETIME NOT NULL,
                    used_at DATETIME NULL,
                    revoked_at DATETIME NULL,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (id),
                    KEY idx_lease (lease_id, expires_at),
                    KEY idx_cid (citizenid, expires_at)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
                [[CREATE TABLE IF NOT EXISTS veyl_apartment_blocks (
                    lease_id INT UNSIGNED NOT NULL,
                    citizenid VARCHAR(16) NOT NULL,
                    PRIMARY KEY (lease_id, citizenid)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
                [[CREATE TABLE IF NOT EXISTS veyl_apartment_presence (
                    citizenid VARCHAR(16) NOT NULL,
                    unit_id INT UNSIGNED NOT NULL,
                    lease_id INT UNSIGNED NULL,
                    kind ENUM('home','tour') NOT NULL DEFAULT 'home',
                    origin VARCHAR(120) NULL,
                    entered_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (citizenid)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
                -- Storage is keyed by LEASE, so ending a lease never moves items: the stash simply becomes recovery storage.
                [[CREATE TABLE IF NOT EXISTS veyl_apartment_storage (
                    stash_id VARCHAR(64) NOT NULL,
                    lease_id INT UNSIGNED NOT NULL,
                    kind ENUM('shared','locker') NOT NULL,
                    owner_cid VARCHAR(16) NOT NULL,
                    status ENUM('active','recovery','closed') NOT NULL DEFAULT 'active',
                    recover_until DATETIME NULL,
                    PRIMARY KEY (stash_id),
                    KEY idx_owner (owner_cid, status)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
                [[CREATE TABLE IF NOT EXISTS veyl_apartment_furniture (
                    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                    owner_cid VARCHAR(16) NOT NULL,
                    lease_id INT UNSIGNED NULL,
                    item VARCHAR(32) NOT NULL,
                    price INT UNSIGNED NOT NULL,
                    state ENUM('pending','placed','stored','sold') NOT NULL DEFAULT 'stored',
                    lx FLOAT NULL, ly FLOAT NULL, lz FLOAT NULL, heading FLOAT NULL,
                    op_id VARCHAR(90) NOT NULL,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                    PRIMARY KEY (id),
                    UNIQUE KEY uq_op (op_id),
                    KEY idx_lease (lease_id, state),
                    KEY idx_owner (owner_cid, state)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
                [[CREATE TABLE IF NOT EXISTS veyl_apartment_parcels (
                    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                    citizenid VARCHAR(16) NOT NULL,
                    building VARCHAR(32) NOT NULL,
                    sender VARCHAR(48) NOT NULL,
                    label VARCHAR(64) NOT NULL,
                    items LONGTEXT NOT NULL,
                    status ENUM('waiting','collected','returned') NOT NULL DEFAULT 'waiting',
                    source_op VARCHAR(90) NOT NULL,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    collected_at DATETIME NULL,
                    PRIMARY KEY (id),
                    UNIQUE KEY uq_source (source_op),
                    KEY idx_cid (citizenid, status)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
                [[CREATE TABLE IF NOT EXISTS veyl_apartment_notices (
                    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                    building VARCHAR(32) NOT NULL,
                    citizenid VARCHAR(16) NOT NULL,
                    author VARCHAR(48) NOT NULL,
                    category ENUM('announcement','roommate','event','forsale') NOT NULL,
                    title VARCHAR(60) NOT NULL,
                    body VARCHAR(400) NOT NULL,
                    reports SMALLINT UNSIGNED NOT NULL DEFAULT 0,
                    removed_by VARCHAR(64) NULL,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    expires_at DATETIME NOT NULL,
                    PRIMARY KEY (id),
                    KEY idx_building (building, removed_by, expires_at)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
                [[CREATE TABLE IF NOT EXISTS veyl_apartment_notice_reports (
                    notice_id INT UNSIGNED NOT NULL,
                    citizenid VARCHAR(16) NOT NULL,
                    PRIMARY KEY (notice_id, citizenid)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
                [[CREATE TABLE IF NOT EXISTS veyl_apartment_maintenance (
                    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                    lease_id INT UNSIGNED NOT NULL,
                    unit_id INT UNSIGNED NOT NULL,
                    citizenid VARCHAR(16) NOT NULL,
                    category VARCHAR(16) NOT NULL,
                    description VARCHAR(300) NOT NULL,
                    preference VARCHAR(60) NULL,
                    allow_entry TINYINT(1) NOT NULL DEFAULT 0,
                    status ENUM('open','accepted','scheduled','in_progress','completed','cancelled') NOT NULL DEFAULT 'open',
                    staff_cid VARCHAR(16) NULL,
                    staff_name VARCHAR(48) NULL,
                    scheduled_for VARCHAR(60) NULL,
                    note VARCHAR(200) NULL,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                    PRIMARY KEY (id),
                    KEY idx_lease (lease_id, status),
                    KEY idx_status (status, id)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            },
        },
    })
    if not ok then return false end
    Apt.LoadUnits()
    Apt.ready = true
    TriggerEvent('veyl_apartments:ready')
    return true
end)

---------------------------------------------------------------------------
-- Units: every configured MLO room gets a stable row (unit_key = building:number)
---------------------------------------------------------------------------
function Apt.LoadUnits()
    for bid, b in pairs(AptBuildings) do
        local list = _G[b.units]
        assert(type(list) == 'table', ('veyl_apartments: building %s units table %s missing'):format(bid, tostring(b.units)))
        Apt.buildings[bid] = { id = bid, def = b, units = {} }
        for _, u in ipairs(list) do
            local key = ('%s:%d'):format(bid, u.number)
            MySQL.insert.await('INSERT IGNORE INTO veyl_apartment_units (unit_key, building, number, type) VALUES (?, ?, ?, ?)',
                { key, bid, u.number, b.type })
            local row = MySQL.single.await('SELECT id, disabled FROM veyl_apartment_units WHERE unit_key = ?', { key })
            local unit = { id = row.id, key = key, building = bid, number = u.number, floor = u.floor, wing = u.wing,
                origin = u.origin, yaw = u.yaw, type = b.type, disabled = row.disabled == 1 or row.disabled == true }
            Apt.units[key] = unit
            Apt.unitsById[unit.id] = unit
            table.insert(Apt.buildings[bid].units, unit)
        end
        table.sort(Apt.buildings[bid].units, function(a, c) return a.number < c.number end)
    end
end

function Apt.Unit(id) return Apt.unitsById[tonumber(id) or -1] end
function Apt.Type(unit) return AptTypes[unit.type] end
function Apt.Bucket(unit) return AptConfig.BucketBase + unit.id end
function Apt.UnitLabel(unit)
    local b = AptBuildings[unit.building]
    return ('%s · Room %d'):format(b and b.label or unit.building, unit.number)
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
function Apt.Clean(s, maxLen)
    if type(s) ~= 'string' then return nil end
    s = s:gsub('[%c<>]', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if #s == 0 then return nil end
    return s:sub(1, maxLen)
end

function Apt.ValidOp(op) return type(op) == 'string' and #op >= 6 and #op <= 48 and op:match('^[%w%-]+$') ~= nil end

local rate = {}
function Apt.Rate(src, key, ms)
    local now = GetGameTimer()
    rate[src] = rate[src] or {}
    if (rate[src][key] or 0) > now then return false end
    rate[src][key] = now + ms
    return true
end
AddEventHandler('playerDropped', function() rate[source] = nil end)

--- Serialises async work per key (a lease, a unit, a character) so double clicks and races queue instead of overlap.
local locks = {}
function Apt.WithLock(key, fn, ...)
    local waited = 0
    while locks[key] do
        Wait(25)
        waited = waited + 25
        if waited > 15000 then return Veyl.Err('BUSY', 'Please try again in a moment') end
    end
    locks[key] = true
    local ok, res = pcall(fn, ...)
    locks[key] = nil
    if not ok then
        print(('^1[veyl_apartments] %s failed: %s^7'):format(key, tostring(res)))
        return Veyl.Err('ERROR', 'Something went wrong. Nothing was charged twice; please try again.')
    end
    return res
end

function Apt.CharName(citizenid)
    local src = Veyl.GetSourceByCitizenId(citizenid)
    local pd = src and Veyl.GetPlayerData(src)
    local ci = pd and pd.charinfo
    if not ci then
        local row = MySQL.single.await('SELECT charinfo FROM veyl_players WHERE citizenid = ?', { citizenid })
        ci = row and json_ok(row.charinfo, nil)
    end
    if not ci then return 'Resident' end
    return (('%s %s'):format(ci.firstname or '', ci.lastname or '')):gsub('^%s+', ''):gsub('%s+$', '')
end

---------------------------------------------------------------------------
-- Adapters (each optional integration is used only when its resource is running)
---------------------------------------------------------------------------
local function started(name) return name and GetResourceState(name) == 'started' end
Apt.Has = function(key) return started(AptConfig.Integrations[key]) end

function Apt.Core(name, ...) return Veyl.Await('veyl_core', name, 15000, ...) end

--- Notify a character: in-game toast if online, and a phone notification when veyl_phone runs (works offline too).
function Apt.Notify(citizenid, title, body, opts)
    opts = opts or {}
    local src = Veyl.GetSourceByCitizenId(citizenid)
    if src and not opts.phoneOnly then Veyl.Notify(src, body and (title .. ': ' .. body) or title, opts.kind or 'info', 7000) end
    if Apt.Has('phone') then
        pcall(function()
            exports.veyl_phone:Notify(citizenid, { app = 'apartments', title = title, body = body or '', route = 'apartments', dedupe = opts.dedupe })
        end)
    end
end

function Apt.Audit(src, action, data) pcall(Veyl.Audit, src, 'apt_' .. action, data) end

--- Stable unit ids for the client's door interactions (building:number -> id).
Veyl.RegisterCallback('unitIds', function()
    local out = {}
    for key, u in pairs(Apt.units) do out[key] = u.id end
    return Veyl.Ok(out)
end, { cooldown = 2000 })
