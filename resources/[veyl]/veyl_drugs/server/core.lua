-- veyl_drugs server core: migrations, logging and adapters over the real VeylCore services.
-- Inventory  : veyl_inventory durable exports (GiveItem / TakeItem / GetOperation, all keyed by operation ids)
-- Money      : veyl_core DebitOnce / CreditOnce
-- Identity   : veyl_core (citizenid, sessions, groups)
-- Property / phone / dispatch: no such resources exist on this server yet; see DrugsConfig.Adapters.

Drugs = { ready = false }

Veyl.Startup({ 'veyl_core', 'veyl_inventory' }, function()
    local ok = Veyl.Migrate({
        {
            id = '001_plants',
            sql = {
                [[CREATE TABLE IF NOT EXISTS veyl_drug_plants (
                    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                    owner_cid VARCHAR(16) NOT NULL,
                    type VARCHAR(16) NOT NULL,
                    variety VARCHAR(32) NOT NULL,
                    container ENUM('ground','pot','tub') NOT NULL,
                    x DOUBLE NOT NULL, y DOUBLE NOT NULL, z DOUBLE NOT NULL, heading FLOAT NOT NULL DEFAULT 0,
                    bucket INT NOT NULL DEFAULT 0,
                    interior INT NOT NULL DEFAULT 0,
                    state ENUM('pending','growing','harvesting','harvested','dead','removed','seized') NOT NULL DEFAULT 'pending',
                    growth FLOAT NOT NULL DEFAULT 0, water FLOAT NOT NULL DEFAULT 70, care FLOAT NOT NULL DEFAULT 70,
                    health FLOAT NOT NULL DEFAULT 100, care_sum FLOAT NOT NULL DEFAULT 0, care_weight FLOAT NOT NULL DEFAULT 0,
                    ready_at INT UNSIGNED NULL,
                    planted_at INT UNSIGNED NOT NULL,
                    updated_at INT UNSIGNED NOT NULL,
                    op_id VARCHAR(100) NOT NULL,
                    claim_op VARCHAR(100) NULL,
                    claim_by VARCHAR(16) NULL,
                    claimed_at INT UNSIGNED NULL,
                    PRIMARY KEY (id),
                    UNIQUE KEY uq_op (op_id),
                    KEY idx_owner (owner_cid),
                    KEY idx_state (state)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
                [[CREATE TABLE IF NOT EXISTS veyl_drug_logs (
                    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                    citizenid VARCHAR(16) NULL,
                    action VARCHAR(32) NOT NULL,
                    plant_id INT UNSIGNED NULL,
                    suspicious TINYINT(1) NOT NULL DEFAULT 0,
                    details TEXT NULL,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (id),
                    KEY idx_cid (citizenid),
                    KEY idx_action (action)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
                [[CREATE TABLE IF NOT EXISTS veyl_drug_supplier_stock (
                    k VARCHAR(64) NOT NULL,
                    stock INT NOT NULL,
                    restocked_at INT UNSIGNED NOT NULL,
                    PRIMARY KEY (k)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            },
        },
    })
    if not ok then return false end
    Drugs.ready = true
    TriggerEvent('veyl_drugs:ready')
    return true
end)

---------------------------------------------------------------------------
-- Logging
---------------------------------------------------------------------------
function Drugs.Log(citizenid, action, plantId, details)
    local okJson, s = pcall(json.encode, details or {})
    MySQL.insert('INSERT INTO veyl_drug_logs (citizenid, action, plant_id, details) VALUES (?, ?, ?, ?)',
        { citizenid, action, plantId, okJson and s:sub(1, 2000) or nil })
end

--- Rejected requests that look like tampering (too far, replayed tokens, impossible values).
function Drugs.Suspicious(src, citizenid, reason, details)
    print(('^3[veyl_drugs] rejected from %s (%s): %s^7'):format(tostring(src), tostring(citizenid), reason))
    local okJson, s = pcall(json.encode, details or {})
    MySQL.insert('INSERT INTO veyl_drug_logs (citizenid, action, suspicious, details) VALUES (?, ?, 1, ?)',
        { citizenid, reason:sub(1, 32), okJson and s:sub(1, 2000) or nil })
end

---------------------------------------------------------------------------
-- Adapters
---------------------------------------------------------------------------
Drugs.Inv = {}
function Drugs.Inv.Give(citizenid, item, count, metadata, opId)
    return Veyl.Await('veyl_inventory', 'GiveItem', 15000, citizenid, item, count, metadata, opId)
end
function Drugs.Inv.Take(citizenid, item, count, metadata, opId)
    return Veyl.Await('veyl_inventory', 'TakeItem', 15000, citizenid, item, count, metadata, opId)
end
function Drugs.Inv.CanCarry(citizenid, item, count, metadata)
    return Veyl.Await('veyl_inventory', 'CanCarry', 10000, citizenid, item, count, metadata)
end
--- Whether an operation id was committed by the inventory (it happened atomically, or not at all).
function Drugs.Inv.Done(opId)
    local r = Veyl.Await('veyl_inventory', 'GetOperation', 10000, opId)
    return r.ok and r.data ~= nil
end
function Drugs.Inv.Count(src, item, metadata)
    return exports.veyl_inventory:GetItemCount(src, item, metadata) or 0
end

Drugs.Money = {}
function Drugs.Money.Debit(citizenid, method, amount, reason, opId)
    return Veyl.Await('veyl_core', 'DebitOnce', 15000, citizenid, method, amount, reason, opId)
end
function Drugs.Money.Credit(citizenid, method, amount, reason, opId)
    return Veyl.Await('veyl_core', 'CreditOnce', 15000, citizenid, method, amount, reason, opId)
end

--- Whether a character is online right now (owner responsibility for offline protection).
function Drugs.IsOnline(citizenid) return exports.veyl_core:GetSourceByCitizenId(citizenid) ~= nil end

--- Property adapter: may a player plant inside this interior? No property resource exists yet.
function Drugs.PropertyAllows(src, interior)
    if interior == 0 then return true end
    if DrugsConfig.Adapters.Property == 'none' then return DrugsConfig.Placement.AllowInteriors end
    return false
end

function Drugs.PlayerPos(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped), GetPlayerRoutingBucket(src)
end

function Drugs.NewOp(prefix)
    return ('%s:%x%04x%04x'):format(prefix, os.time(), math.random(0, 0xffff), math.random(0, 0xffff))
end

function Drugs.ValidClientOp(op) return Veyl.Validate.str(op, 8, 64, '^[%w%-]+$') end
