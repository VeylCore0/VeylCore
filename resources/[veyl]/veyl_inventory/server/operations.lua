-- Inventory operations. Durable paths follow the plan's transfer algorithm:
--   resolve + authorise -> lock inventories (sorted) -> dedupe op id -> re-validate under lock on a copy ->
--   one DB transaction (slots + revisions + operation record) -> apply to memory -> publish deltas.
-- Nothing is acknowledged before the commit succeeds.

Ops = {}

local function err(code, message, data) return { ok = false, code = code, message = message, data = data } end
local function ok(data, message) return { ok = true, code = 'OK', data = data, message = message } end
Ops.err, Ops.ok = err, ok

local function fingerprint(t)
    local ok2, s = pcall(json.encode, t)
    return ok2 and s:sub(1, 500) or '?'
end

--- Stored result for a repeated operation id, or a rejection if the id is reused for a different request.
local function dedupe(opId, actor, fp)
    local row = DB.GetOperation(opId)
    if not row then return nil end
    if row.actor ~= actor or row.fingerprint ~= fp then
        return err('DUPLICATE_OPERATION', 'Operation id already used for a different request')
    end
    local okDecode, stored = pcall(json.decode, row.result or 'null')
    return ok(okDecode and stored or nil, 'Already processed')
end

-- Large enough for a cash stack (the money item); stacks are still limited by each item's maxStack.
local MAX_COUNT = InventoryConfig.MaxCount or 1000000000
local function validCount(c) return vlib.validate.int(c, 1, MAX_COUNT) end
local function validOp(id) return vlib.validate.str(id, 6, 90, '^[%w%-_:.]+$') end

---------------------------------------------------------------------------
-- Transfer: move / split / merge / swap between (or within) two inventories
---------------------------------------------------------------------------
--- req = { opId, actor, from = inv, fromSlot, to = inv, toSlot, count?, revisions = { [invId] = rev } }
function Ops.Transfer(req)
    local from, to = req.from, req.to
    if not validOp(req.opId) then return err('INVALID_INPUT', 'Bad operation id') end
    if not vlib.validate.int(req.fromSlot, 1, from.slots) or not vlib.validate.int(req.toSlot, 1, to.slots) then
        return err('INVALID_INPUT', 'Bad slot')
    end
    if from == to and req.fromSlot == req.toSlot then return err('INVALID_INPUT', 'Same slot') end
    local fp = fingerprint({ 'move', from.id, req.fromSlot, to.id, req.toSlot, req.count })

    local result, lockErr = Store.WithLocks({ from.id, to.id }, function()
        local stored = dedupe(req.opId, req.actor, fp)
        if stored then return stored end
        if from.dead or to.dead then return err('NOT_FOUND', 'Those items are gone') end
        -- Stale client view -> authoritative refresh instead of guessing.
        for _, inv in ipairs({ from, to }) do
            local expected = req.revisions and req.revisions[inv.id]
            if expected ~= nil and expected ~= inv.revision then return err('STALE', 'Inventory changed; refreshed') end
        end
        local src = from.items[req.fromSlot]
        if not src then return err('NOT_FOUND', 'Nothing in that slot') end
        local d = ItemDefs[src.name]
        local count = req.count or src.count
        if not validCount(count) or count > src.count then return err('INVALID_INPUT', 'Bad quantity') end
        if count > src.count - Store.Reserved(from, req.fromSlot) then return err('RESERVED', 'That item is being used') end

        local fromItems = Store.CopyItems(from)
        local toItems = from == to and fromItems or Store.CopyItems(to)
        local dst = toItems[req.toSlot]

        if not dst then
            -- Move (or split) into an empty slot.
            toItems[req.toSlot] = { slot = req.toSlot, name = src.name, count = count, metadata = src.metadata,
                instance = (count == src.count) and src.instance or nil }
            if count == src.count then fromItems[req.fromSlot] = nil
            else fromItems[req.fromSlot] = { slot = req.fromSlot, name = src.name, count = src.count - count, metadata = src.metadata, instance = src.instance } end
        elseif Store.CanStack(src, dst) then
            -- Merge (never silently merges different metadata: CanStack compares it).
            if dst.count + count > d.maxStack then return err('STACK_FULL', ('Stacks hold at most %d'):format(d.maxStack)) end
            toItems[req.toSlot] = { slot = req.toSlot, name = dst.name, count = dst.count + count, metadata = dst.metadata, instance = dst.instance }
            if count == src.count then fromItems[req.fromSlot] = nil
            else fromItems[req.fromSlot] = { slot = req.fromSlot, name = src.name, count = src.count - count, metadata = src.metadata, instance = src.instance } end
        else
            -- Swap whole stacks only.
            if count ~= src.count then return err('INVALID_INPUT', 'Split into an empty slot') end
            if Store.Reserved(to, req.toSlot) > 0 then return err('RESERVED', 'That item is being used') end
            toItems[req.toSlot] = { slot = req.toSlot, name = src.name, count = src.count, metadata = src.metadata, instance = src.instance }
            fromItems[req.fromSlot] = { slot = req.fromSlot, name = dst.name, count = dst.count, metadata = dst.metadata, instance = dst.instance }
        end

        -- Equipment slots take only the item type they are for, one at a time.
        local function fits(inv, slot, item)
            local rule = inv.slotRules and inv.slotRules[slot]
            if not rule or not item then return true end
            local def = ItemDefs[item.name]
            return def ~= nil and def.equip == rule and item.count == 1
        end
        if not fits(to, req.toSlot, toItems[req.toSlot]) then return err('INVALID_STATE', 'That does not go there') end
        if not fits(from, req.fromSlot, fromItems[req.fromSlot]) then return err('INVALID_STATE', 'That does not go there') end

        if from ~= to then
            if Store.ComputeWeight(toItems) > to.maxWeight then return err('INVENTORY_FULL', 'Not enough space') end
            if Store.ComputeWeight(fromItems) > from.maxWeight then return err('INVENTORY_FULL', 'Not enough space for the swap') end
        end

        local changes = {}
        local fromRev = from.revision + 1
        if from == to then
            changes[1] = { inv = from, items = fromItems, slots = { req.fromSlot, req.toSlot }, revision = fromRev }
        else
            changes[1] = { inv = from, items = fromItems, slots = { req.fromSlot }, revision = fromRev }
            changes[2] = { inv = to, items = toItems, slots = { req.toSlot }, revision = to.revision + 1 }
        end
        local audit = {}
        if from ~= to then
            audit[1] = { inventory = from.id, item = src.name, delta = -count, reason = 'transfer' }
            audit[2] = { inventory = to.id, item = src.name, delta = count, reason = 'transfer' }
        end
        local op = { id = req.opId, actor = req.actor, kind = 'move', inventories = from.id .. '>' .. to.id, fingerprint = fp, result = true }
        if not DB.Commit(changes, op, audit) then
            if DB.GetOperation(req.opId) then return dedupe(req.opId, req.actor, fp) end
            return err('DATABASE_ERROR', 'Could not save; nothing changed')
        end
        for _, c in ipairs(changes) do Store.Apply(c.inv, c.items, c.slots, c.revision) end
        return ok(true)
    end)
    if lockErr then return err('BUSY', 'Inventory busy, try again') end
    return result
end

---------------------------------------------------------------------------
-- Changing one slot in place (used for equipment slots: a SIM card gets its number written on it, a card is placed in its slot)
---------------------------------------------------------------------------
--- Replaces the metadata of the item in `slot` (a single item, never a stack) under the lock, with an operation record.
function Ops.SetMetadata(inv, slot, metadata, ctx)
    if not validOp(ctx.opId) then return err('INVALID_INPUT', 'Bad operation id') end
    local fp = fingerprint({ 'setmeta', inv.id, slot, metadata })
    local result, lockErr = Store.WithLocks({ inv.id }, function()
        local stored = dedupe(ctx.opId, ctx.actor, fp)
        if stored then return stored end
        local it = inv.items[slot]
        if not it then return err('NOT_FOUND', 'Nothing in that slot') end
        if it.count ~= 1 then return err('INVALID_STATE', 'Only a single item can be marked') end
        local meta, metaErr = CleanMetadata(it.name, metadata)
        if not meta then return err('INVALID_INPUT', metaErr) end
        local items = Store.CopyItems(inv)
        items[slot] = { slot = slot, name = it.name, count = 1, metadata = meta, instance = it.instance }
        local rev = inv.revision + 1
        local op = { id = ctx.opId, actor = ctx.actor, kind = 'setmeta', inventories = inv.id, fingerprint = fp, result = true }
        if not DB.Commit({ { inv = inv, items = items, slots = { slot }, revision = rev } }, op, { { inventory = inv.id, item = it.name, delta = 0, reason = ctx.reason } }) then
            if DB.GetOperation(ctx.opId) then return dedupe(ctx.opId, ctx.actor, fp) end
            return err('DATABASE_ERROR', 'Could not save; nothing changed')
        end
        Store.Apply(inv, items, { slot }, rev)
        return ok(true)
    end)
    if lockErr then return err('BUSY', 'Inventory busy') end
    return result
end

--- Puts one new item into an EMPTY slot (the slot rules still apply).
function Ops.PlaceInSlot(inv, slot, name, metadata, ctx)
    if not ItemDefs[name] or not validOp(ctx.opId) then return err('INVALID_INPUT', 'Unknown item or bad operation id') end
    local meta, metaErr = CleanMetadata(name, metadata)
    if not meta then return err('INVALID_INPUT', metaErr) end
    local rule = inv.slotRules and inv.slotRules[slot]
    if rule and ItemDefs[name].equip ~= rule then return err('INVALID_STATE', 'That does not go there') end
    local fp = fingerprint({ 'place', inv.id, slot, name, meta })
    local result, lockErr = Store.WithLocks({ inv.id }, function()
        local stored = dedupe(ctx.opId, ctx.actor, fp)
        if stored then return stored end
        if inv.items[slot] then return err('INVALID_STATE', 'That slot is taken') end
        local items = Store.CopyItems(inv)
        items[slot] = { slot = slot, name = name, count = 1, metadata = meta, instance = (not ItemDefs[name].stack) and Store.NewInstance() or nil }
        local rev = inv.revision + 1
        local op = { id = ctx.opId, actor = ctx.actor, kind = 'place', inventories = inv.id, fingerprint = fp, result = true }
        if not DB.Commit({ { inv = inv, items = items, slots = { slot }, revision = rev } }, op, { { inventory = inv.id, item = name, delta = 1, reason = ctx.reason } }) then
            if DB.GetOperation(ctx.opId) then return dedupe(ctx.opId, ctx.actor, fp) end
            return err('DATABASE_ERROR', 'Could not save; nothing was added')
        end
        Store.Apply(inv, items, { slot }, rev)
        return ok(true)
    end)
    if lockErr then return err('BUSY', 'Inventory busy') end
    return result
end

---------------------------------------------------------------------------
-- Durable add / remove (operation-aware; used by shops, rewards, staff tools)
---------------------------------------------------------------------------
function Ops.Add(inv, name, count, metadata, ctx)
    if not ItemDefs[name] or not validCount(count) then return err('INVALID_INPUT', 'Unknown item or bad count') end
    if not validOp(ctx.opId) then return err('INVALID_INPUT', 'Bad operation id') end
    local meta, metaErr = CleanMetadata(name, metadata)
    if not meta then return err('INVALID_INPUT', metaErr) end
    local fp = fingerprint({ 'add', inv.id, name, count, meta })
    local result, lockErr = Store.WithLocks({ inv.id }, function()
        local stored = dedupe(ctx.opId, ctx.actor, fp)
        if stored then return stored.ok and err('DUPLICATE_OPERATION', 'Already delivered', stored.data) or stored end
        local items, changed = Store.PlanAdd(inv, Store.CopyItems(inv), name, count, meta)
        if not items then return err('INVENTORY_FULL', 'Not enough slots') end
        if Store.ComputeWeight(items) > inv.maxWeight then return err('INVENTORY_FULL', 'Not enough space') end
        local rev = inv.revision + 1
        local op = { id = ctx.opId, actor = ctx.actor, kind = 'add', inventories = inv.id, fingerprint = fp, result = { item = name, count = count } }
        if not DB.Commit({ { inv = inv, items = items, slots = changed, revision = rev } }, op,
            { { inventory = inv.id, item = name, delta = count, reason = ctx.reason } }) then
            if DB.GetOperation(ctx.opId) then return err('DUPLICATE_OPERATION', 'Already delivered') end
            return err('DATABASE_ERROR', 'Could not save; nothing was added')
        end
        Store.Apply(inv, items, changed, rev)
        return ok({ item = name, count = count })
    end)
    if lockErr then return err('BUSY', 'Inventory busy') end
    return result
end

--- Plans removal of `count` (optionally matching metadata), honouring reservations. Returns items, slots or nil, code.
function Ops.PlanRemove(inv, name, count, metadata)
    local items, changed, remaining = Store.CopyItems(inv), {}, count
    for s = inv.slots, 1, -1 do
        local it = items[s]
        if remaining > 0 and it and it.name == name and (metadata == nil or vlib.table.equals(it.metadata or {}, metadata)) then
            local free = it.count - Store.Reserved(inv, s)
            local take = math.min(free, remaining)
            if take > 0 then
                if take == it.count then items[s] = nil
                else items[s] = { slot = s, name = it.name, count = it.count - take, metadata = it.metadata, instance = it.instance } end
                remaining = remaining - take
                changed[#changed + 1] = s
            end
        end
    end
    if remaining > 0 then return nil, 'NOT_ENOUGH_ITEMS' end
    return items, changed
end

function Ops.Remove(inv, name, count, metadata, ctx)
    if not ItemDefs[name] or not validCount(count) then return err('INVALID_INPUT', 'Unknown item or bad count') end
    if not validOp(ctx.opId) then return err('INVALID_INPUT', 'Bad operation id') end
    local fp = fingerprint({ 'remove', inv.id, name, count, metadata })
    local result, lockErr = Store.WithLocks({ inv.id }, function()
        local stored = dedupe(ctx.opId, ctx.actor, fp)
        if stored then return stored.ok and err('DUPLICATE_OPERATION', 'Already removed', stored.data) or stored end
        local items, changed = Ops.PlanRemove(inv, name, count, metadata)
        if not items then return err('NOT_ENOUGH_ITEMS', 'Not enough items') end
        local rev = inv.revision + 1
        local op = { id = ctx.opId, actor = ctx.actor, kind = 'remove', inventories = inv.id, fingerprint = fp, result = { item = name, count = count } }
        if not DB.Commit({ { inv = inv, items = items, slots = changed, revision = rev } }, op,
            { { inventory = inv.id, item = name, delta = -count, reason = ctx.reason } }) then
            return err('DATABASE_ERROR', 'Could not save; nothing was removed')
        end
        Store.Apply(inv, items, changed, rev)
        return ok({ item = name, count = count })
    end)
    if lockErr then return err('BUSY', 'Inventory busy') end
    return result
end

---------------------------------------------------------------------------
-- Legacy synchronous add/remove (QB-style `success, resultOrError` contract).
-- Applied to memory immediately, then persisted in order under the inventory lock (write-behind).
-- Refused while a durable operation holds the lock. Use Ops.Add/Remove (GiveItem/TakeItem) for valuables.
---------------------------------------------------------------------------
local function persistLater(inv, slots, audit)
    local rev = inv.revision
    CreateThread(function()
        Store.WithLocks({ inv.id }, function()
            local snapshot = Store.CopyItems(inv) -- current memory values for those slots (absolute, idempotent)
            local okCommit = false
            for attempt = 1, 5 do
                okCommit = DB.Commit({ { inv = inv, items = snapshot, slots = slots, revision = math.max(rev, inv.revision) } }, nil, audit)
                if okCommit then break end
                Wait(1000 * attempt)
            end
            if not okCommit then print(('^1[veyl_inventory] CRITICAL: write-behind for %s failed after retries^7'):format(inv.id)) end
        end, 'persist')
    end)
end

--- Apply already-planned items to memory and persist them in order (used by the cash mirror).
function Ops.ApplyAndPersist(inv, items, slots, audit)
    Store.Apply(inv, items, slots, inv.revision + 1)
    persistLater(inv, slots, audit)
end

function Ops.LegacyAdd(inv, name, count, metadata)
    if not ItemDefs[name] then return false, 'invalid_item' end
    if not validCount(count) then return false, 'invalid_count' end
    if Store.IsLocked(inv.id) then return false, 'busy' end
    local meta, metaErr = CleanMetadata(name, metadata)
    if not meta then return false, metaErr end
    local items, changed = Store.PlanAdd(inv, Store.CopyItems(inv), name, count, meta)
    if not items or Store.ComputeWeight(items) > inv.maxWeight then return false, 'inventory_full' end
    Store.Apply(inv, items, changed, inv.revision + 1)
    persistLater(inv, changed, { { inventory = inv.id, item = name, delta = count, reason = 'legacy AddItem: ' .. tostring(GetInvokingResource()) } })
    return true, { item = name, count = count }
end

function Ops.LegacyRemove(inv, name, count, metadata)
    if not ItemDefs[name] then return false, 'invalid_item' end
    if not validCount(count) then return false, 'invalid_count' end
    if Store.IsLocked(inv.id) then return false, 'busy' end
    local items, changed = Ops.PlanRemove(inv, name, count, metadata)
    if not items then return false, 'not_enough_items' end
    Store.Apply(inv, items, changed, inv.revision + 1)
    persistLater(inv, changed, { { inventory = inv.id, item = name, delta = -count, reason = 'legacy RemoveItem: ' .. tostring(GetInvokingResource()) } })
    return true, { item = name, count = count }
end
