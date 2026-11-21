-- veyl_mechanic server: on-duty repairs that consume parts, and service invoices paid through the core ledger.
--
-- Repairs: start (checks duty, workshop, vehicle, part in inventory) -> client progress -> complete (server checks the
-- elapsed time, removes ONE part with a durable operation id, then the vehicle's owner client applies the repair).
-- Invoices: veyl_invoices rows; paying = one TransferMoney keyed 'invoice:<id>' (customer -> the mechanic who sent it).

Veyl.Startup({ 'veyl_core', 'veyl_inventory' }, function()
    return Veyl.Migrate({
        {
            id = '001_invoices',
            sql = {
                [[CREATE TABLE IF NOT EXISTS veyl_invoices (
                    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                    job VARCHAR(32) NOT NULL,
                    sender_cid VARCHAR(16) NOT NULL,
                    sender_name VARCHAR(64) NOT NULL,
                    recipient_cid VARCHAR(16) NOT NULL,
                    amount INT UNSIGNED NOT NULL,
                    reason VARCHAR(100) NOT NULL,
                    status ENUM('pending','paid','declined','cancelled') NOT NULL DEFAULT 'pending',
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    settled_at TIMESTAMP NULL,
                    PRIMARY KEY (id),
                    KEY idx_recipient (recipient_cid, status)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            },
        },
    })
end)

local function core(name, ...) return Veyl.Await('veyl_core', name, 15000, ...) end
local function inv(name, ...) return Veyl.Await('veyl_inventory', name, 15000, ...) end

local repairs = {}
for _, r in ipairs(MechanicConfig.Repairs) do repairs[r.id] = r end

local function onDuty(src)
    local pd = Veyl.GetPlayerData(src)
    return pd and pd.job.name == MechanicConfig.Job and pd.job.onduty == true
end

local function shopAt(pos)
    for _, s in ipairs(MechanicConfig.Shops) do
        if #(pos - s.coords) <= s.radius then return s end
    end
end

local function nameOf(src)
    local pd = Veyl.GetPlayerData(src)
    return pd and ('%s %s'):format(pd.charinfo.firstname or '', pd.charinfo.lastname or ''):gsub('^%s+', '') or ('#' .. src)
end

---------------------------------------------------------------------------
-- Duty
---------------------------------------------------------------------------
Veyl.RegisterCallback('toggleDuty', function(src)
    local pd = Veyl.GetPlayerData(src)
    if pd.job.name ~= MechanicConfig.Job then
        if exports.veyl_core:HasGroup(src, MechanicConfig.Job) then
            return Veyl.Err('INVALID_STATE', 'Make Mechanic your primary job first (/jobs)')
        end
        return Veyl.Err('NO_PERMISSION', 'You do not work here')
    end
    local pc = Veyl.GetPlayerCoords(src)
    if not pc or not shopAt(pc) then return Veyl.Err('TOO_FAR', 'Clock in at the workshop') end
    exports.veyl_core:SetJobDuty(src, not pd.job.onduty)
    return Veyl.Ok({ onduty = not pd.job.onduty }, pd.job.onduty and 'You are now off duty' or 'You are now on duty')
end, { cooldown = 3000 })

---------------------------------------------------------------------------
-- Repairs
---------------------------------------------------------------------------
local active = {} -- [src] = { token, repair, netId, startedAt }
local seq = 0

local function vehicleFor(src, netId)
    if not Veyl.Validate.int(netId, 1) then return nil, Veyl.Err('INVALID_INPUT', 'Invalid vehicle') end
    local entity = NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or not DoesEntityExist(entity) or GetEntityType(entity) ~= 2 then
        return nil, Veyl.Err('NOT_FOUND', 'Vehicle not found')
    end
    local pc = Veyl.GetPlayerCoords(src)
    if not pc or #(pc - GetEntityCoords(entity)) > 5.0 then return nil, Veyl.Err('TOO_FAR', 'Stand next to the vehicle') end
    if not shopAt(GetEntityCoords(entity)) then return nil, Veyl.Err('TOO_FAR', 'Bring the vehicle into the workshop') end
    return entity
end

Veyl.RegisterCallback('startRepair', function(src, _, netId, repairId)
    if not onDuty(src) then return Veyl.Err('NO_PERMISSION', 'Only on-duty mechanics can do that') end
    local r = repairs[repairId]
    if not r then return Veyl.Err('INVALID_INPUT', 'Unknown repair') end
    if active[src] then return Veyl.Err('BUSY', 'Finish the current job first') end
    local entity, err = vehicleFor(src, netId)
    if not entity then return err end
    if (exports.veyl_inventory:GetItemCount(src, r.item) or 0) < 1 then
        local def = exports.veyl_inventory:GetItemDefinition(r.item)
        return Veyl.Err('NOT_ENOUGH_ITEMS', ('You need %s'):format(def and def.label or r.item))
    end
    seq = seq + 1
    local token = ('%x%x%04x'):format(os.time(), seq, math.random(0, 0xffff))
    active[src] = { token = token, repair = r, netId = netId, startedAt = GetGameTimer() }
    return Veyl.Ok({ token = token, durationMs = r.durationMs, label = r.label })
end, { cooldown = 1000 })

Veyl.RegisterCallback('cancelRepair', function(src, _, token)
    if active[src] and active[src].token == token then active[src] = nil end
    return Veyl.Ok()
end)

Veyl.RegisterCallback('completeRepair', function(src, citizenid, token)
    local a = active[src]
    if not a or a.token ~= token then return Veyl.Err('INVALID_STATE', 'No repair in progress') end
    active[src] = nil
    if GetGameTimer() - a.startedAt < a.repair.durationMs - 500 then return Veyl.Err('INVALID_STATE', 'Too fast') end
    if not onDuty(src) then return Veyl.Err('NO_PERMISSION', 'You went off duty') end
    local entity, err = vehicleFor(src, a.netId)
    if not entity then return err end
    local take = inv('TakeItem', citizenid, a.repair.item, 1, nil, 'mech:' .. token)
    if not take.ok and take.code ~= 'DUPLICATE_OPERATION' then
        return Veyl.Err(take.code or 'NOT_ENOUGH_ITEMS', take.message or 'The part is gone')
    end
    -- Health/visual repairs are applied by the client that owns the entity (and the mechanic, as a fallback).
    local owner = NetworkGetEntityOwner(entity)
    if owner and owner > 0 then TriggerClientEvent('veyl_mechanic:apply', owner, a.netId, a.repair.id) end
    if owner ~= src then TriggerClientEvent('veyl_mechanic:apply', src, a.netId, a.repair.id) end
    Veyl.Audit(src, 'mechanic_repair', { repair = a.repair.id, plate = GetVehicleNumberPlateText(entity) })
    return Veyl.Ok(nil, ('%s: done'):format(a.repair.label))
end)

AddEventHandler('playerDropped', function() active[source] = nil end)

---------------------------------------------------------------------------
-- Invoices
---------------------------------------------------------------------------
local function nearbyPlayers(src)
    local ped = GetPlayerPed(src)
    if ped == 0 then return {} end
    local pos, bucket, list = GetEntityCoords(ped), GetPlayerRoutingBucket(src), {}
    for _, pd in ipairs(exports.veyl_core:GetPlayersData()) do
        local t = pd.source
        if t ~= src and GetPlayerRoutingBucket(t) == bucket then
            local tped = GetPlayerPed(t)
            local d = tped ~= 0 and #(GetEntityCoords(tped) - pos) or math.huge
            if d <= MechanicConfig.Invoice.Distance then
                list[#list + 1] = { id = t, citizenid = pd.citizenid, distance = math.floor(d * 10 + 0.5) / 10,
                    name = ('%s %s.'):format(pd.charinfo.firstname or '?', (pd.charinfo.lastname or ''):sub(1, 1)) }
            end
        end
    end
    table.sort(list, function(x, y) return x.distance < y.distance end)
    return list
end

Veyl.RegisterCallback('nearbyCustomers', function(src)
    if not onDuty(src) then return Veyl.Err('NO_PERMISSION', 'Only on-duty mechanics can send invoices') end
    local out = {}
    for i, p in ipairs(nearbyPlayers(src)) do out[i] = { id = p.id, name = p.name, distance = p.distance } end
    return Veyl.Ok(out)
end, { cooldown = 500 })

-- Optional veyl_phone integration: a notification per invoice and a badge with the unpaid count.
local function phoneStarted() return GetResourceState('veyl_phone') == 'started' end
local function syncPhoneBadge(citizenid)
    if not phoneStarted() then return end
    local n = MySQL.scalar.await("SELECT COUNT(*) FROM veyl_invoices WHERE recipient_cid = ? AND status = 'pending'", { citizenid }) or 0
    pcall(function() exports.veyl_phone:SetBadge(citizenid, 'invoices', n) end)
end

AddEventHandler('veyl_phone:sessionStarted', function(_, session)
    if type(session) == 'table' and type(session.cid) == 'string' then syncPhoneBadge(session.cid) end
end)

Veyl.RegisterCallback('sendInvoice', function(src, citizenid, target, amount, reason)
    if not onDuty(src) then return Veyl.Err('NO_PERMISSION', 'Only on-duty mechanics can send invoices') end
    if not Veyl.Validate.int(amount, 1, MechanicConfig.Invoice.Max) then
        return Veyl.Err('INVALID_INPUT', ('Amount must be $1 to $%d'):format(MechanicConfig.Invoice.Max))
    end
    reason = tostring(reason or ''):gsub('[%c<>]', ''):sub(1, 100)
    if #reason < 3 then return Veyl.Err('INVALID_INPUT', 'Describe the work (at least 3 characters)') end
    local customer
    for _, p in ipairs(nearbyPlayers(src)) do if p.id == target then customer = p break end end
    if not customer then return Veyl.Err('TOO_FAR', 'That customer is no longer nearby') end
    local pending = MySQL.scalar.await("SELECT COUNT(*) FROM veyl_invoices WHERE recipient_cid = ? AND status = 'pending'", { customer.citizenid }) or 0
    if pending >= MechanicConfig.Invoice.PendingLimit then return Veyl.Err('LIMIT', 'That customer has too many unpaid invoices') end
    local id = MySQL.insert.await('INSERT INTO veyl_invoices (job, sender_cid, sender_name, recipient_cid, amount, reason) VALUES (?, ?, ?, ?, ?, ?)',
        { MechanicConfig.Job, citizenid, nameOf(src), customer.citizenid, amount, reason })
    if not id then return Veyl.Err('DATABASE_ERROR', 'Could not create the invoice') end
    TriggerClientEvent('veyl_mechanic:invoiceReceived', customer.id, { id = id, from = 'Mechanic', amount = amount, reason = reason })
    if phoneStarted() then
        pcall(function()
            exports.veyl_phone:Notify(customer.citizenid, { app = 'invoices', title = 'Mechanic invoice',
                body = ('#%d · $%d · %s'):format(id, amount, reason), route = 'invoices', dedupe = 'invoice:' .. id })
        end)
        syncPhoneBadge(customer.citizenid)
    end
    Veyl.Audit(src, 'invoice_sent', { id = id, to = customer.citizenid, amount = amount })
    return Veyl.Ok({ id = id }, ('Invoice #%d sent to %s ($%d)'):format(id, customer.name, amount))
end, { cooldown = 5000 })

Veyl.RegisterCallback('myInvoices', function(_, citizenid)
    local rows = MySQL.query.await([[SELECT id, job, sender_name, amount, reason, DATE_FORMAT(created_at, '%d %b %H:%i') AS at
        FROM veyl_invoices WHERE recipient_cid = ? AND status = 'pending' ORDER BY id DESC LIMIT 20]], { citizenid }) or {}
    return Veyl.Ok(rows)
end, { cooldown = 500 })

Veyl.RegisterCallback('payInvoice', function(src, citizenid, id, method)
    if not Veyl.Validate.int(id, 1) or not Veyl.Validate.oneOf(method, { 'cash', 'bank' }) then return Veyl.Err('INVALID_INPUT', 'Invalid invoice') end
    local row = MySQL.single.await('SELECT id, sender_cid, amount, reason, status FROM veyl_invoices WHERE id = ? AND recipient_cid = ?', { id, citizenid })
    if not row then return Veyl.Err('NOT_FOUND', 'Invoice not found') end
    if row.status ~= 'pending' then return Veyl.Err('INVALID_STATE', 'This invoice is already ' .. row.status) end
    local pay = core('TransferMoney', citizenid, method, row.sender_cid, 'bank', row.amount, ('Invoice #%d: %s'):format(id, row.reason), 'invoice:' .. id)
    if not pay.ok and pay.code ~= 'DUPLICATE_OPERATION' then
        if pay.code == 'TIMEOUT' then return Veyl.Err('PENDING', 'Payment is being verified. Try again in a moment.') end
        return pay
    end
    MySQL.update.await("UPDATE veyl_invoices SET status = 'paid', settled_at = NOW() WHERE id = ? AND status = 'pending'", { id })
    local senderSrc = exports.veyl_core:GetSourceByCitizenId(row.sender_cid)
    if senderSrc then Veyl.Notify(senderSrc, ('Invoice #%d paid ($%d)'):format(id, row.amount), 'success') end
    syncPhoneBadge(citizenid)
    return Veyl.Ok(nil, ('Paid invoice #%d ($%d)'):format(id, row.amount))
end, { cooldown = 2000 })

Veyl.RegisterCallback('declineInvoice', function(_, citizenid, id)
    if not Veyl.Validate.int(id, 1) then return Veyl.Err('INVALID_INPUT', 'Invalid invoice') end
    local n = MySQL.update.await("UPDATE veyl_invoices SET status = 'declined', settled_at = NOW() WHERE id = ? AND recipient_cid = ? AND status = 'pending'",
        { id, citizenid })
    if n ~= 1 then return Veyl.Err('NOT_FOUND', 'Invoice not found') end
    syncPhoneBadge(citizenid)
    return Veyl.Ok(nil, ('Declined invoice #%d'):format(id))
end, { cooldown = 1000 })
