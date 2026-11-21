-- Access: who may do what in a home. Checked on the server for EVERY protected action; the client never holds a key.
-- Roles: leaseholder (everything), roommate (permissions granted by the leaseholder), guest (enter only, until expiry).

Access = {}
local ALL = { 'enter', 'storage', 'wardrobe', 'furniture', 'guests', 'roommates', 'lease' }
local ALLOWED_ROOMMATE = {}
for _, p in ipairs(AptConfig.RoommatePermissions) do ALLOWED_ROOMMATE[p] = true end

function Access.CleanPerms(list)
    local out, seen = {}, {}
    for _, p in ipairs(type(list) == 'table' and list or {}) do
        if ALLOWED_ROOMMATE[p] and not seen[p] then seen[p] = true out[#out + 1] = p end
    end
    if not seen.enter and #out > 0 then table.insert(out, 1, 'enter') end
    return out
end

local function toSet(list) local s = {} for _, p in ipairs(list) do s[p] = true end return s end

--- The character's current live lease (as leaseholder), or nil.
function Access.LeaseOf(citizenid)
    return MySQL.single.await("SELECT * FROM veyl_apartment_leases WHERE citizenid = ? AND status = 'active' ORDER BY id DESC LIMIT 1", { citizenid })
end

function Access.Lease(leaseId)
    return MySQL.single.await('SELECT * FROM veyl_apartment_leases WHERE id = ?', { leaseId })
end

function Access.ActiveLeaseForUnit(unitId)
    return MySQL.single.await("SELECT * FROM veyl_apartment_leases WHERE unit_id = ? AND status = 'active'", { unitId })
end

--- Role and permission set of a character for a lease. Returns role ('leaseholder'|'roommate'|'guest'|nil), perms set, guestRow.
function Access.Get(lease, citizenid)
    if not lease or lease.status ~= 'active' or type(citizenid) ~= 'string' then return nil, {} end
    if lease.citizenid == citizenid then return 'leaseholder', toSet(ALL) end
    local m = MySQL.single.await("SELECT perms FROM veyl_apartment_members WHERE lease_id = ? AND citizenid = ? AND status = 'active'", { lease.id, citizenid })
    if m then return 'roommate', toSet(Access.CleanPerms(Apt.Decode(m.perms, {}))) end
    local g = Access.GuestPass(lease.id, citizenid)
    if g then return 'guest', { enter = true }, g end
    return nil, {}
end

--- A valid guest pass: not expired, not revoked, and (if single use) not used yet, or used by a visit that is still
--- going on (the guest is inside right now). Leaving ends a single visit.
function Access.GuestPass(leaseId, citizenid)
    return MySQL.single.await([[SELECT g.* FROM veyl_apartment_guests g WHERE g.lease_id = ? AND g.citizenid = ? AND g.revoked_at IS NULL
        AND g.expires_at > NOW() AND (g.single_use = 0 OR g.used_at IS NULL OR EXISTS (SELECT 1 FROM veyl_apartment_presence p
        WHERE p.citizenid = g.citizenid AND p.lease_id = g.lease_id AND p.kind = 'home')) ORDER BY g.id DESC LIMIT 1]], { leaseId, citizenid })
end

function Access.Can(lease, citizenid, perm)
    local role, perms = Access.Get(lease, citizenid)
    return role ~= nil and perms[perm] == true, role
end

--- All homes a character can enter (own lease, roommate homes, valid guest passes). Used for the door and phone.
function Access.HomesOf(citizenid)
    local rows = MySQL.query.await([[
        SELECT l.*, 'leaseholder' AS role FROM veyl_apartment_leases l WHERE l.citizenid = ? AND l.status = 'active'
        UNION SELECT l.*, 'roommate' AS role FROM veyl_apartment_leases l JOIN veyl_apartment_members m ON m.lease_id = l.id
            WHERE m.citizenid = ? AND m.status = 'active' AND l.status = 'active'
        UNION SELECT l.*, 'guest' AS role FROM veyl_apartment_leases l JOIN veyl_apartment_guests g ON g.lease_id = l.id
            WHERE g.citizenid = ? AND g.revoked_at IS NULL AND g.expires_at > NOW() AND (g.single_use = 0 OR g.used_at IS NULL) AND l.status = 'active']],
        { citizenid, citizenid, citizenid }) or {}
    local seen, out = {}, {}
    local rank = { leaseholder = 1, roommate = 2, guest = 3 }
    table.sort(rows, function(a, b) return rank[a.role] < rank[b.role] end)
    for _, r in ipairs(rows) do if not seen[r.id] then seen[r.id] = true out[#out + 1] = r end end
    return out
end

function Access.IsBlocked(leaseId, citizenid)
    return MySQL.scalar.await('SELECT 1 FROM veyl_apartment_blocks WHERE lease_id = ? AND citizenid = ?', { leaseId, citizenid }) ~= nil
end

--- Called whenever someone's access to a lease may have shrunk: anyone inside without 'enter' is handled.
function Access.Recheck(leaseId)
    if Presence and Presence.RecheckLease then Presence.RecheckLease(leaseId) end
end
