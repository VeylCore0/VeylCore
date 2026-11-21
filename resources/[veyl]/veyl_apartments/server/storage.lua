-- Storage and wardrobe.
-- Stashes are registered with veyl_inventory and keyed by LEASE: apt_l<lease> (shared) and apt_l<lease>_k<citizenid>
-- (a roommate's private locker). veyl_inventory asks this resource (export AuthorizeStash) before every open, so access
-- follows the apartment's live permissions. When a lease ends, nothing is moved: its stashes switch to 'recovery' and
-- can be emptied at the front desk by their owner for AptConfig.Billing.RecoveryDays. Nothing is ever deleted
-- automatically; after the window, staff can still open them (/aptstorage).

Storage = {}
local adminOpen = {} -- [src] = stashId staff opened through the admin tool

local function sharedId(leaseId) return ('apt_l%d'):format(leaseId) end
local function lockerId(leaseId, cid) return ('apt_l%d_k%s'):format(leaseId, cid) end

local function register(row)
    local lease = Access.Lease(row.lease_id)
    local unit = lease and Apt.Unit(lease.unit_id)
    local t = unit and Apt.Type(unit) or AptTypes[next(AptTypes)]
    local slots = row.kind == 'locker' and math.max(1, t.lockerSlots or 10) or t.storage.slots
    local label = row.kind == 'locker' and 'Private locker' or (unit and ('Room %d storage'):format(unit.number) or 'Apartment storage')
    if row.status ~= 'active' then label = label .. ' (recovery)' end
    local ok, err = pcall(function()
        exports.veyl_inventory:RegisterStash({ id = row.stash_id, label = label, slots = slots, maxWeight = t.storage.maxWeight,
            authorize = { resource = GetCurrentResourceName(), export = 'AuthorizeStash' } })
    end)
    if not ok then print(('^1[veyl_apartments] could not register stash %s: %s^7'):format(row.stash_id, tostring(err))) end
    return ok
end

function Storage.RegisterAll()
    for _, row in ipairs(MySQL.query.await("SELECT * FROM veyl_apartment_storage WHERE status IN ('active','recovery')") or {}) do register(row) end
end
AddEventHandler('veyl_apartments:ready', Storage.RegisterAll)
AddEventHandler('onResourceStart', function(res) if res == 'veyl_inventory' and Apt.ready then SetTimeout(1000, Storage.RegisterAll) end end)

function Storage.EnsureForLease(leaseId)
    local lease = Access.Lease(leaseId)
    MySQL.insert.await("INSERT IGNORE INTO veyl_apartment_storage (stash_id, lease_id, kind, owner_cid, status) VALUES (?, ?, 'shared', ?, 'active')",
        { sharedId(leaseId), leaseId, lease.citizenid })
    register(MySQL.single.await('SELECT * FROM veyl_apartment_storage WHERE stash_id = ?', { sharedId(leaseId) }))
end

function Storage.EnsureLocker(leaseId, cid)
    local lease = Access.Lease(leaseId)
    local t = Apt.Type(Apt.Unit(lease.unit_id))
    if (t.lockerSlots or 0) <= 0 then return end
    local id = lockerId(leaseId, cid)
    MySQL.query.await([[INSERT INTO veyl_apartment_storage (stash_id, lease_id, kind, owner_cid, status) VALUES (?, ?, 'locker', ?, 'active')
        ON DUPLICATE KEY UPDATE status = 'active', recover_until = NULL]], { id, leaseId, cid })
    register(MySQL.single.await('SELECT * FROM veyl_apartment_storage WHERE stash_id = ?', { id }))
end

--- A roommate left: their locker becomes recovery storage for them.
function Storage.LockerToRecovery(leaseId, cid)
    MySQL.update.await([[UPDATE veyl_apartment_storage SET status = 'recovery', recover_until = DATE_ADD(NOW(), INTERVAL ? DAY)
        WHERE stash_id = ? AND status = 'active']], { AptConfig.Billing.RecoveryDays, lockerId(leaseId, cid) })
end

function Storage.ToRecovery(leaseId)
    MySQL.update.await([[UPDATE veyl_apartment_storage SET status = 'recovery', recover_until = DATE_ADD(NOW(), INTERVAL ? DAY)
        WHERE lease_id = ? AND status = 'active']], { AptConfig.Billing.RecoveryDays, leaseId })
    for _, row in ipairs(MySQL.query.await('SELECT * FROM veyl_apartment_storage WHERE lease_id = ?', { leaseId }) or {}) do register(row) end
end

--- Asked by veyl_inventory before opening (and on every move) for one of our stashes.
exports('AuthorizeStash', function(src, citizenid, stashId)
    if type(stashId) ~= 'string' or type(citizenid) ~= 'string' then return false, 'NO_PERMISSION' end
    if adminOpen[src] == stashId and Veyl.HasPermission(src, 'apartments.manage') then return true end
    local row = MySQL.single.await('SELECT * FROM veyl_apartment_storage WHERE stash_id = ?', { stashId })
    if not row then return false, 'NOT_FOUND' end
    if row.status == 'active' then
        local lease = Access.Lease(row.lease_id)
        if not Presence.IsInside(src, row.lease_id) then return false, 'TOO_FAR' end
        local role, perms = Access.Get(lease, citizenid)
        if row.kind == 'locker' then
            return row.owner_cid == citizenid and (role == 'roommate' or role == 'leaseholder'), 'NO_PERMISSION'
        end
        return perms.storage == true, 'NO_PERMISSION'
    elseif row.status == 'recovery' then
        if row.owner_cid ~= citizenid then return false, 'NO_PERMISSION' end
        local open = MySQL.scalar.await('SELECT recover_until > NOW() FROM veyl_apartment_storage WHERE stash_id = ?', { stashId })
        if open ~= 1 and open ~= true then return false, 'EXPIRED' end
        local lease = Access.Lease(row.lease_id)
        local unit = lease and Apt.Unit(lease.unit_id)
        if not unit or not Lease.NearDesk(src, unit.building) then return false, 'TOO_FAR' end
        return true
    end
    return false, 'NO_PERMISSION'
end)

--- Storage the character can open right now from inside their home.
Veyl.RegisterCallback('storageList', function(src, citizenid)
    local inside = Presence.Of(src)
    if not inside or inside.kind ~= 'home' then return Veyl.Err('NOT_INSIDE', 'You need to be inside the home') end
    local lease = Access.Lease(inside.leaseId)
    local role, perms = Access.Get(lease, citizenid)
    local out = {}
    if perms.storage then out[#out + 1] = { id = sharedId(lease.id), label = 'Shared storage' } end
    if role == 'roommate' and MySQL.scalar.await("SELECT 1 FROM veyl_apartment_storage WHERE stash_id = ? AND status = 'active'", { lockerId(lease.id, citizenid) }) then
        out[#out + 1] = { id = lockerId(lease.id, citizenid), label = 'My private locker' }
    end
    return Veyl.Ok(out)
end, { cooldown = 300 })

--- Former homes' storage waiting at the front desk.
Veyl.RegisterCallback('recoveryList', function(src, citizenid)
    local rows = MySQL.query.await([[SELECT s.stash_id, s.kind, s.lease_id, UNIX_TIMESTAMP(s.recover_until) AS until_at, (s.recover_until > NOW()) AS open
        FROM veyl_apartment_storage s WHERE s.owner_cid = ? AND s.status = 'recovery' ORDER BY s.recover_until DESC]], { citizenid }) or {}
    local out = {}
    for _, r in ipairs(rows) do
        local lease = Access.Lease(r.lease_id)
        local unit = lease and Apt.Unit(lease.unit_id)
        out[#out + 1] = { id = r.stash_id, kind = r.kind, label = (unit and Apt.UnitLabel(unit) or 'Former home') .. (r.kind == 'locker' and ' · locker' or ''),
            until_at = r.until_at, open = r.open == 1 or r.open == true }
    end
    return Veyl.Ok(out)
end, { cooldown = 400 })

--- Staff: open any apartment stash (recorded).
function Storage.AdminOpen(src, stashId)
    local row = MySQL.single.await('SELECT * FROM veyl_apartment_storage WHERE stash_id = ?', { stashId })
    if not row then return false end
    register(row)
    adminOpen[src] = stashId
    Apt.Audit(src, 'admin_storage_open', { stash = stashId })
    TriggerClientEvent('veyl_apartments:openStash', src, stashId)
    return true
end
AddEventHandler('playerDropped', function() adminOpen[source] = nil end)

---------------------------------------------------------------------------
-- Wardrobe: veyl_appearance owns outfits; we only check that you are home with the 'wardrobe' permission.
---------------------------------------------------------------------------
local function wardrobeAllowed(src, citizenid)
    if not Apt.Has('appearance') then return nil, Veyl.Err('UNAVAILABLE', 'The wardrobe is unavailable right now') end
    local inside = Presence.Of(src)
    if not inside or inside.kind ~= 'home' then return nil, Veyl.Err('NOT_INSIDE', 'You need to be inside the home') end
    if not Access.Can(Access.Lease(inside.leaseId), citizenid, 'wardrobe') then return nil, Veyl.Err('NO_PERMISSION', 'You cannot use this wardrobe') end
    return true
end

local function appearance(name, ...) return Veyl.Await('veyl_appearance', name, 10000, ...) end

Veyl.RegisterCallback('wardrobe', function(src, citizenid)
    local ok, err = wardrobeAllowed(src, citizenid)
    if not ok then return err end
    return appearance('GetOutfits', citizenid)
end, { cooldown = 300 })

Veyl.RegisterCallback('wardrobeAction', function(src, citizenid, action, id, name)
    local ok, err = wardrobeAllowed(src, citizenid)
    if not ok then return err end
    if action == 'save' then return appearance('SaveCurrentOutfit', citizenid, name) end
    if action == 'rename' then return appearance('RenameOutfit', citizenid, id, name) end
    if action == 'delete' then return appearance('DeleteOutfit', citizenid, id) end
    if action == 'wear' then return appearance('WearOutfit', citizenid, id) end
    return Veyl.Err('INVALID_INPUT', 'Unknown action')
end, { cooldown = 600 })
