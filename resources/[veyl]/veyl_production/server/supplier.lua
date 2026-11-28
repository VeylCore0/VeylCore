-- Supplier runs: pay a supplier a fee, pick up an abstract crate and bring it to a drop before the time runs out, and get supply kits.
-- Each step is claimed once in the database (active -> picked -> done), distances and timing are checked here, and the reward is a durable
-- inventory operation keyed by the run, so repeating a request never pays twice. The crate and its contents are abstract game items.

Prod = Prod or {}
Prod.Supplier = {}
local Sup = Prod.Supplier
local C = ProductionConfig
local S = C.Supplier

local function supplier(id) for _, s in ipairs(S.Suppliers) do if s.id == id then return s end end end

local function hour() return tonumber(os.date('%H', os.time())) end

--- Is the supplier working now? Hours = { from, to }; a window may cross midnight; { 0, 24 } is always.
function Sup.open(s)
    local a, b = s.Hours[1], s.Hours[2]
    if a == 0 and b >= 24 then return true end
    local h = hour()
    if a <= b then return h >= a and h < b end
    return h >= a or h < b
end

-- The crate rides on a vehicle (config: Supplier.Truck). The server remembers which vehicle and crate belong to a run, in memory only:
-- after a restart it falls back to "an allowed truck near the drop".
Sup.loaded = {} -- [cid] = { veh = netId, crate = netId }

local allowed
local function truckAllowed(model)
    if not allowed then
        allowed = {}
        for _, name in ipairs(S.Truck.Models) do allowed[joaat(name)] = true end
    end
    return allowed[model] == true
end

local function netEntity(netId)
    netId = Prod.Sec.int(netId, 2147483647)
    if not netId then return nil end
    local ok, ent = pcall(NetworkGetEntityFromNetworkId, netId)
    if not ok or not ent or ent == 0 or not DoesEntityExist(ent) then return nil end
    return ent, netId
end

--- A vehicle that may carry the crate: a real vehicle of an allowed model.
local function carrier(netId)
    local ent, id = netEntity(netId)
    if not ent then return nil end
    local okT, t = pcall(GetEntityType, ent)
    if not okT or t ~= 2 then return nil end
    local okM, model = pcall(GetEntityModel, ent)
    if not okM or not truckAllowed(model) then return nil end
    return ent, id
end

local function dropCrate(cid)
    local l = Sup.loaded[cid]
    Sup.loaded[cid] = nil
    if l and l.crate then
        local ent = netEntity(l.crate)
        if ent then pcall(DeleteEntity, ent) end
    end
end

--- Is a usable truck at the drop? Prefers the one the crate was loaded on; falls back to any allowed truck nearby (after a restart).
local function truckAtDrop(cid, src, d)
    local limit = S.Truck.DropVehicleRadius
    local l = Sup.loaded[cid]
    if l then
        local ent = carrier(l.veh)
        if not ent then return false, 'The crate went with the truck. It is gone.' end
        if ProdUtil.distance(GetEntityCoords(ent), d) > limit then return false, 'Bring the truck to the drop' end
        local pc = Veyl.GetPlayerCoords(src)
        if not pc or ProdUtil.distance(pc, GetEntityCoords(ent)) > limit + 6.0 then return false, 'Stay with the truck' end
        return true
    end
    local ok, all = pcall(GetAllVehicles)
    if ok and type(all) == 'table' then
        for _, v in ipairs(all) do
            local okM, model = pcall(GetEntityModel, v)
            if okM and truckAllowed(model) and ProdUtil.distance(GetEntityCoords(v), d) <= limit then return true end
        end
    end
    return false, 'Bring the truck to the drop'
end

local function dayStart() return math.floor(os.time() / 86400) * 86400 end

local function runsToday(cid, supplierId)
    return MySQL.scalar.await('SELECT COUNT(*) FROM veyl_prod_runs WHERE citizenid = ? AND supplier = ? AND started_at >= ?', { cid, supplierId, dayStart() }) or 0
end

--- The player's run in progress (expired runs are closed here, so nothing lingers).
local function active(cid)
    local row = MySQL.single.await("SELECT * FROM veyl_prod_runs WHERE citizenid = ? AND state IN ('active', 'picked') ORDER BY id DESC LIMIT 1", { cid })
    if row and row.expires_at < os.time() then
        MySQL.update("UPDATE veyl_prod_runs SET state = 'expired', finished_at = ? WHERE id = ? AND state IN ('active', 'picked')", { os.time(), row.id })
        dropCrate(cid)
        return nil
    end
    return row
end

local function view(row)
    if not row then return nil end
    local pickup, drop = json.decode(row.pickup), json.decode(row.dropoff)
    local s = supplier(row.supplier)
    return { id = row.id, supplier = s and s.label or row.supplier, state = row.state, kits = row.kits, expiresAt = row.expires_at, serverTime = os.time(),
        pickup = { label = pickup.label, x = pickup.x, y = pickup.y, z = pickup.z },
        -- The drop is only revealed once the crate is in hand.
        drop = row.state == 'picked' and { label = drop.label, x = drop.x, y = drop.y, z = drop.z } or nil }
end

function Sup.view(cid)
    local level = Prod.Prog.level(cid, 'supplier')
    local list = {}
    for _, s in ipairs(S.Suppliers) do
        local used = runsToday(cid, s.id)
        list[#list + 1] = { id = s.id, label = s.label, level = s.level, locked = level < s.level, fee = s.fee, open = Sup.open(s), hours = s.Hours,
            runsLeft = math.max(0, s.MaxRunsPerDay - used), minutes = s.TimeLimitMinutes, kits = s.KitsPerRun, x = s.Ped.coords.x, y = s.Ped.coords.y }
    end
    return { suppliers = list, run = view(active(cid)), cancelWait = Prod.Sec.cooldownLeft(cid, 'run_cancel') }
end

function Sup.start(src, cid, supplierId)
    local s = Prod.Sec.str(supplierId, 32, '^[%w_]+$') and supplier(supplierId)
    if not s then Prod.Sec.invalid(src, cid, 'run_bad_supplier') return Veyl.Err('INVALID_INPUT', 'Unknown supplier') end
    if not (C.Branches.supplier and C.Branches.supplier.enabled) then return Veyl.Err('UNAVAILABLE', 'Not available') end
    if not Prod.Sec.near(src, s.Ped.coords, C.Distance.Shop) then return Veyl.Err('TOO_FAR', 'Go to the supplier') end
    if Prod.Prog.level(cid, 'supplier') < s.level then return Veyl.Err('LEVEL_REQUIRED', ('Needs supplier level %d'):format(s.level)) end
    if not Sup.open(s) then return Veyl.Err('CLOSED', ('%s only works between %02d:00 and %02d:00'):format(s.label, s.Hours[1], s.Hours[2] % 24)) end
    if active(cid) then return Veyl.Err('INVALID_STATE', 'Finish your current run first') end
    local wait = Prod.Sec.cooldownLeft(cid, 'run_cancel')
    if wait > 0 then return Veyl.Err('COOLDOWN', ('Wait %d s before another run'):format(wait)) end
    if runsToday(cid, s.id) >= s.MaxRunsPerDay then return Veyl.Err('LIMIT', 'No more runs from them today') end
    if not Prod.Sec.try(cid, 'run_start', 3) then return Veyl.Err('RATE_LIMITED', 'Slow down') end
    local pickup = S.Pickups[math.random(#S.Pickups)]
    local drop = S.Drops[math.random(#S.Drops)]
    local kits = math.random(s.KitsPerRun[1], s.KitsPerRun[2])
    local now = os.time()
    local tag = ('prodrun:%s:%s'):format(cid, Veyl.NewId())
    local pay = Prod.Inv.debit(cid, s.fee, ('Supplier fee: %s'):format(s.label), tag)
    if not (pay and pay.ok) then return Veyl.Err(pay and pay.code or 'INSUFFICIENT_FUNDS', 'You cannot afford the fee') end
    local id = MySQL.insert.await('INSERT INTO veyl_prod_runs (citizenid, supplier, state, pickup, dropoff, kits, started_at, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        { cid, s.id, 'active', json.encode({ label = pickup.label, x = pickup.coords.x, y = pickup.coords.y, z = pickup.coords.z }),
          json.encode({ label = drop.label, x = drop.coords.x, y = drop.coords.y, z = drop.coords.z }), kits, now, now + s.TimeLimitMinutes * 60 })
    if not id then
        Prod.Inv.credit(cid, s.fee, 'Supplier fee refund', tag .. ':refund')
        return Veyl.Err('DATABASE_ERROR', 'Could not start the run')
    end
    Prod.Prog.stat(cid, 'runs_started')
    Prod.Log.event('purchase', cid, ('started a run with %s (fee $%d)'):format(s.id, s.fee))
    Prod.Police.maybeAlert(cid, 'supply_run', pickup.coords)
    return Veyl.Ok(Sup.view(cid), ('Run started. Pick up the crate at %s.'):format(pickup.label))
end

local function mine(cid, wanted)
    local row = active(cid)
    if not row or row.state ~= wanted then return nil end
    return row
end

function Sup.pickup(src, cid, vehNet, crateNet)
    local row = mine(cid, 'active')
    if not row then return Veyl.Err('INVALID_STATE', 'There is no crate to pick up') end
    local p = json.decode(row.pickup)
    if not Prod.Sec.near(src, p, S.PickupRadius + 2.0) then return Veyl.Err('TOO_FAR', 'Get to the crate') end
    local loaded
    if S.Truck.Required then
        local ent, id = carrier(vehNet)
        if not ent then return Veyl.Err('NO_VEHICLE', 'Back a pickup truck up to the crate first') end
        local vc = GetEntityCoords(ent)
        if ProdUtil.distance(vc, p) > S.Truck.LoadRadius then return Veyl.Err('TOO_FAR', 'Bring the truck next to the crate') end
        local pc = Veyl.GetPlayerCoords(src)
        if not pc or ProdUtil.distance(pc, vc) > S.Truck.LoadRadius then return Veyl.Err('TOO_FAR', 'Stay next to the truck') end
        loaded = { veh = id }
        local ce, cid2 = netEntity(crateNet)
        if ce and ProdUtil.distance(GetEntityCoords(ce), vc) <= 8.0 then loaded.crate = cid2 end
    end
    local flipped = MySQL.update.await("UPDATE veyl_prod_runs SET state = 'picked', picked_at = ? WHERE id = ? AND state = 'active'", { os.time(), row.id })
    if (flipped or 0) < 1 then return Veyl.Err('INVALID_STATE', 'Already picked up') end
    Sup.loaded[cid] = loaded
    return Veyl.Ok(Sup.view(cid), S.Truck.Required and 'Crate on the truck. Drive it to the drop.' or 'Crate loaded. Take it to the drop.')
end

function Sup.deliver(src, cid)
    local t0 = GetGameTimer()
    local row = mine(cid, 'picked')
    if not row then return Veyl.Err('INVALID_STATE', 'You are not carrying a crate') end
    local d, p = json.decode(row.dropoff), json.decode(row.pickup)
    if not Prod.Sec.near(src, d, S.DropRadius + 2.0) then return Veyl.Err('TOO_FAR', 'Get to the drop') end
    if S.Truck.Required then
        local ok, why = truckAtDrop(cid, src, d)
        if not ok then return Veyl.Err('NO_VEHICLE', why) end
    end
    local now = os.time()
    -- Nobody gets from the pickup to the drop faster than the speed limit allows.
    local least = ProdUtil.distance(p, d) / S.MaxSpeed
    if now - (row.picked_at or now) < least then Prod.Sec.invalid(src, cid, 'run_too_fast', { seconds = now - (row.picked_at or now) }) return Veyl.Err('TOO_FAST', 'That was too quick') end
    local s = supplier(row.supplier)
    local kits = row.kits
    local fast = s and (now - row.started_at) <= s.TimeLimitMinutes * 60 * S.FastBonus.within
    if fast then kits = math.floor(kits * S.FastBonus.mult + 0.5) end
    local flipped = MySQL.update.await("UPDATE veyl_prod_runs SET state = 'done', finished_at = ? WHERE id = ? AND state = 'picked'", { now, row.id })
    if (flipped or 0) < 1 then return Veyl.Err('INVALID_STATE', 'Already delivered') end
    -- One inventory call: it refuses when you cannot carry the kits, and then the run is put back so you can make room and try again.
    local g = Prod.Inv.give(cid, S.RewardItem, kits, nil, ('prodrun:%d'):format(row.id))
    if not (g and g.ok) then
        MySQL.update("UPDATE veyl_prod_runs SET state = 'picked', finished_at = NULL WHERE id = ? AND state = 'done'", { row.id })
        local full = g and (g.code == 'INVENTORY_FULL' or g.code == 'WEIGHT' or g.code == 'NO_SPACE')
        return Veyl.Err(full and 'INVENTORY_FULL' or 'FAILED', full and 'You cannot carry the contents. Make room and hand it over again.' or 'Could not hand over the contents. Try again.')
    end
    dropCrate(cid)
    -- The kits are in. Everything else (XP, stats, log, police roll) happens after the answer has gone back, so it never delays the reward.
    CreateThread(function()
        Prod.Prog.award(cid, 'supplier', 'run')
        Prod.Prog.stat(cid, 'runs_completed')
        Prod.Log.event('reward', cid, ('finished run #%d: %d kits%s'):format(row.id, kits, fast and ' (fast)' or ''))
        Prod.Police.maybeAlert(cid, 'supply_run', d)
    end)
    Prod.Log.debug('run #%d delivered in %d ms', row.id, GetGameTimer() - t0)
    return Veyl.Ok({ kits = kits, fast = fast }, ('Delivered. %d supply kits%s.'):format(kits, fast and ' (fast bonus)' or ''))
end

function Sup.cancel(src, cid)
    local row = active(cid)
    if not row then return Veyl.Err('NOT_FOUND', 'You have no run') end
    local flipped = MySQL.update.await("UPDATE veyl_prod_runs SET state = 'cancelled', finished_at = ? WHERE id = ? AND state IN ('active', 'picked')", { os.time(), row.id })
    if (flipped or 0) < 1 then return Veyl.Err('INVALID_STATE', 'It already ended') end
    dropCrate(cid)
    Prod.Sec.setCooldown(cid, 'run_cancel', S.Cooldown.Cancel)
    Prod.Log.event('purchase', cid, ('cancelled run #%d'):format(row.id))
    return Veyl.Ok(nil, 'Run cancelled. The fee is not refunded.')
end

--- The run the client should draw (blips, crate, drop).
function Sup.current(cid) return view(active(cid)) end

--- At start-up: runs that expired while the server was down are closed.
function Sup.reconcile()
    MySQL.update.await("UPDATE veyl_prod_runs SET state = 'expired', finished_at = ? WHERE state IN ('active', 'picked') AND expires_at < ?", { os.time(), os.time() })
end
