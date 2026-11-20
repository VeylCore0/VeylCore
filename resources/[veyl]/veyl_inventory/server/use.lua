-- Item use: reserve the exact item/count, server-timed action, then ONE durable outcome:
-- consumption + reservation status + operation record commit together, and the single effect handler runs
-- once afterwards with that operation id. A client "progress finished" alone never grants an effect.

Use = { handlers = {}, legacy = {}, active = {} } -- active[src] = reservation

local seq = 0

--- RegisterUseHandler('consume', function(ctx) end) — ctx = { source, citizenid, item, def, metadata, opId }
function Use.RegisterHandler(name, fn, owner)
    Use.handlers[name] = { fn = fn, owner = owner }
end

--- Legacy usable items (QB CreateUseableItem): handler(source, item). Used only when the definition has no use.handler.
function Use.RegisterLegacy(item, fn, owner)
    Use.legacy[item] = { fn = fn, owner = owner }
end

function Use.IsUsable(name)
    local d = ItemDefs[name]
    if not d then return false end
    if d.use and d.use.handler then return Use.handlers[d.use.handler] ~= nil end
    return Use.legacy[name] ~= nil
end

local function release(r, status)
    if not r then return end
    local inv = Store.Get(r.invId)
    if inv then inv.reserved[r.id] = nil end
    if Use.active[r.src] == r then Use.active[r.src] = nil end
    MySQL.update("UPDATE veyl_inventory_reservations SET status = ? WHERE id = ? AND status = 'active'", { status, r.id })
end
Use.Release = release

--- Starts a use. Returns ok({ useId, durationMs, label, anim, prop }) or an error.
function Use.Start(src, citizenid, generation, inv, slot)
    if Use.active[src] then return Ops.err('BUSY', 'You are already using something') end
    if not vlib.validate.int(slot, 1, inv.slots) then return Ops.err('INVALID_INPUT', 'Bad slot') end
    local it = inv.items[slot]
    if not it then return Ops.err('NOT_FOUND', 'Nothing in that slot') end
    local d = ItemDefs[it.name]
    if not Use.IsUsable(it.name) then return Ops.err('INVALID_STATE', 'You cannot use that') end
    local ped = GetPlayerPed(src)
    if ped == 0 or GetEntityHealth(ped) <= 0 then return Ops.err('INVALID_STATE', 'You cannot do that right now') end
    local consume = d.use and d.use.consumeCount or 0
    if it.count - Store.Reserved(inv, slot) < math.max(consume, 1) then return Ops.err('RESERVED', 'That item is already in use') end
    seq = seq + 1
    local duration = d.use and d.use.durationMs or 0
    local r = {
        id = ('use%x%x%04x'):format(os.time(), seq, math.random(0, 0xffff)), src = src, citizenid = citizenid, generation = generation,
        invId = inv.id, slot = slot, name = it.name, instance = it.instance, count = consume,
        startedAt = GetGameTimer(), duration = duration,
        expiresAt = GetGameTimer() + duration + InventoryConfig.UseReservationGraceMs,
    }
    inv.reserved[r.id] = r
    Use.active[src] = r
    MySQL.insert('INSERT INTO veyl_inventory_reservations (id, inventory_id, slot, item, count, op_id, expires_at) VALUES (?, ?, ?, ?, ?, ?, FROM_UNIXTIME(?))',
        { r.id, inv.id, slot, it.name, consume, 'use:' .. r.id, os.time() + math.ceil((duration + InventoryConfig.UseReservationGraceMs) / 1000) })
    local u = d.use or {}
    return Ops.ok({ useId = r.id, durationMs = duration, label = ('Using %s'):format(d.label), anim = u.anim, prop = u.prop })
end

local function dispatch(r, d, metadata, opId)
    local ctx = { source = r.src, citizenid = r.citizenid, item = r.name, def = d, metadata = metadata, opId = opId }
    local entry = (d.use and d.use.handler) and Use.handlers[d.use.handler] or nil
    if entry then
        local okH, e = pcall(entry.fn, ctx)
        if not okH then print(('^1[veyl_inventory] use handler %s failed: %s^7'):format(d.use.handler, tostring(e))) end
    elseif Use.legacy[r.name] then
        local okH, e = pcall(Use.legacy[r.name].fn, r.src, { name = r.name, slot = r.slot, info = metadata or {}, metadata = metadata or {} })
        if not okH then print(('^1[veyl_inventory] usable item %s failed: %s^7'):format(r.name, tostring(e))) end
    end
    TriggerEvent('veyl_inventory:itemUsed', r.src, r.citizenid, r.name, metadata, opId)
end

--- Completes a use: validates timing/ownership, commits consumption + operation, then runs the effect once.
function Use.Complete(src, citizenid, generation, useId)
    local r = Use.active[src]
    if not r or r.id ~= useId then
        -- A repeated completion for an already-finished use returns the stored outcome (no second effect).
        local stored = DB.GetOperation('use:' .. tostring(useId))
        if stored then return Ops.ok(nil, 'Already used') end
        return Ops.err('INVALID_STATE', 'No active use')
    end
    if r.citizenid ~= citizenid or r.generation ~= generation then release(r, 'released') return Ops.err('INVALID_STATE', 'Character changed') end
    local now = GetGameTimer()
    if now > r.expiresAt then release(r, 'expired') return Ops.err('TIMEOUT', 'Took too long') end
    if now - r.startedAt < r.duration - InventoryConfig.UseTimeToleranceMs then
        return Ops.err('INVALID_STATE', 'Too fast')
    end
    local inv = Store.Get(r.invId)
    if not inv then release(r, 'released') return Ops.err('NOT_FOUND', 'Inventory unavailable') end
    local d = ItemDefs[r.name]
    local opId = 'use:' .. r.id
    local result, lockErr = Store.WithLocks({ inv.id }, function()
        local it = inv.items[r.slot]
        if not it or it.name ~= r.name or it.instance ~= r.instance or it.count < r.count then
            return Ops.err('NOT_FOUND', 'The item is gone')
        end
        local metadata = it.metadata
        inv.reserved[r.id] = nil -- the reservation is converted into the consumption below
        local items, changed = Store.CopyItems(inv), {}
        if r.count > 0 then
            if it.count == r.count then items[r.slot] = nil
            else items[r.slot] = { slot = r.slot, name = it.name, count = it.count - r.count, metadata = it.metadata, instance = it.instance } end
            changed = { r.slot }
        end
        local rev = inv.revision + (#changed > 0 and 1 or 0)
        local op = { id = opId, actor = citizenid, kind = 'use', inventories = inv.id, fingerprint = r.name, result = { item = r.name } }
        local okCommit = DB.Commit(
            #changed > 0 and { { inv = inv, items = items, slots = changed, revision = rev } } or {},
            op, r.count > 0 and { { inventory = inv.id, item = r.name, delta = -r.count, reason = 'use' } } or nil,
            { { query = "UPDATE veyl_inventory_reservations SET status = 'consumed' WHERE id = ?", values = { r.id } } })
        if not okCommit then
            inv.reserved[r.id] = r
            return Ops.err('DATABASE_ERROR', 'Could not use the item')
        end
        if #changed > 0 then Store.Apply(inv, items, changed, rev) end
        return Ops.ok({ metadata = metadata })
    end)
    if lockErr then return Ops.err('BUSY', 'Inventory busy') end
    if Use.active[src] == r then Use.active[src] = nil end
    if result.ok then
        dispatch(r, d, result.data.metadata, opId)
        return Ops.ok({ item = r.name }, ('Used %s'):format(d.label))
    end
    release(r, 'released')
    return result
end

function Use.Cancel(src, useId)
    local r = Use.active[src]
    if r and r.id == useId then release(r, 'released') end
    return Ops.ok()
end

function Use.CancelFor(src)
    local r = Use.active[src]
    if r then release(r, 'released') end
end

-- Expire stale reservations (client crashed mid-use, etc.).
CreateThread(function()
    while true do
        Wait(5000)
        local now = GetGameTimer()
        for _, r in pairs(Use.active) do
            if now > r.expiresAt then release(r, 'expired') end
        end
    end
end)
