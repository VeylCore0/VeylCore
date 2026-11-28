-- veyl_inventory server exports.
-- `target` = player source (number) or inventory id (string, e.g. 'player:ABC12345', 'stash:legion_shared').

local function resolve(target)
    if type(target) == 'number' then
        local p = Players[target]
        return p and Store.Get(p.invId) or nil
    end
    if type(target) == 'string' then return Store.Get(target) end
    return nil
end

--- For a player source: pockets first, then the backpack, then what they wear. Anything else is a single inventory.
local function allOf(target)
    if type(target) == 'number' then
        local p = Players[target]
        if not p then return {} end
        local out = {}
        for _, inv in ipairs({ Store.Get(p.invId) or false, Containers.OpenPack(p.citizenid) or false, p.equipId and Store.Get(p.equipId) or false }) do if inv then out[#out + 1] = inv end end
        return out
    end
    local inv = resolve(target)
    return inv and { inv } or {}
end

local function slotOut(it)
    if not it then return nil end
    local d = ItemDefs[it.name]
    return { slot = it.slot, name = it.name, label = d and d.label, count = it.count, weight = d and d.weight * it.count,
        metadata = vlib.table.deepcopy(it.metadata or {}), instance = it.instance, stack = d and d.stack }
end

local function countOf(inv, item, metadata)
    local n = 0
    for _, it in pairs(inv.items) do
        if it.name == item and (metadata == nil or vlib.table.equals(it.metadata or {}, metadata)) then n = n + it.count end
    end
    return n
end

---------------------------------------------------------------------------
-- Reads
---------------------------------------------------------------------------
exports('Items', function(name)
    if name then return ClientItemDefs()[name] end
    return ClientItemDefs()
end)
exports('GetItemDefinition', function(name) return ClientItemDefs()[name] end)

exports('GetInventory', function(target)
    local inv = resolve(target)
    return inv and Store.View(inv, 'primary') or nil
end)

exports('GetInventoryItems', function(target)
    local inv = resolve(target)
    if not inv then return {} end
    local out = {}
    for s, it in pairs(inv.items) do out[s] = slotOut(it) end
    return out
end)

exports('GetItemCount', function(target, item, metadata)
    local n = 0
    for _, inv in ipairs(allOf(target)) do n = n + countOf(inv, item, metadata) end
    return n
end)

exports('GetSlot', function(target, slot)
    local inv = resolve(target)
    return inv and slotOut(inv.items[slot]) or nil
end)

exports('GetSlotWithItem', function(target, item)
    for _, inv in ipairs(allOf(target)) do
        for s = 1, inv.slots do
            if inv.items[s] and inv.items[s].name == item then return slotOut(inv.items[s]) end
        end
    end
    return nil
end)

exports('GetSlotsWithItem', function(target, item)
    local inv = resolve(target)
    local out = {}
    if not inv then return out end
    for s = 1, inv.slots do
        if inv.items[s] and inv.items[s].name == item then out[#out + 1] = slotOut(inv.items[s]) end
    end
    return out
end)

--- Search(target, 'count' | 'slots', item)
exports('Search', function(target, mode, item)
    local list = allOf(target)
    if mode == 'count' then
        local n = 0
        for _, inv in ipairs(list) do n = n + countOf(inv, item) end
        return n
    end
    local out = {}
    for _, inv in ipairs(list) do
        for s = 1, inv.slots do
            if inv.items[s] and inv.items[s].name == item then out[#out + 1] = slotOut(inv.items[s]) end
        end
    end
    return out
end)

--- Preview only: the mutating operation re-checks capacity under the lock.
exports('CanCarryItem', function(target, item, count, metadata)
    local inv = resolve(target)
    if not inv or not ItemDefs[item] or not vlib.validate.int(count, 1, InventoryConfig.MaxCount or 1000000000) then return false end
    local items = Store.PlanAdd(inv, Store.CopyItems(inv), item, count, metadata or {})
    return items ~= nil and Store.ComputeWeight(items) <= inv.maxWeight
end)

---------------------------------------------------------------------------
-- Legacy synchronous mutations: return success, resultOrError (write-behind; see operations.lua)
---------------------------------------------------------------------------
exports('AddItem', function(target, item, count, metadata)
    local inv = resolve(target)
    if not inv then return false, 'invalid_inventory' end
    return Ops.LegacyAdd(inv, item, tonumber(count) or 1, metadata)
end)

exports('RemoveItem', function(target, item, count, metadata)
    local inv = resolve(target)
    if not inv then return false, 'invalid_inventory' end
    return Ops.LegacyRemove(inv, item, tonumber(count) or 1, metadata)
end)

---------------------------------------------------------------------------
-- Durable, operation-aware mutations (trailing callback; call with Veyl.Await or a promise)
---------------------------------------------------------------------------
local function asyncExport(name, fn)
    exports(name, function(...)
        local args = table.pack(...)
        local cb = args[args.n]
        local invoker = GetInvokingResource() or GetCurrentResourceName()
        CreateThread(function()
            while not Ready do Wait(100) end
            local okCall, res = pcall(fn, invoker, table.unpack(args, 1, args.n - 1))
            if not okCall then
                print(('^1[veyl_inventory] %s failed: %s^7'):format(name, tostring(res)))
                res = Ops.err('INTERNAL', 'internal error')
            end
            cb(res)
        end)
    end)
end

local function playerInv(citizenid)
    if type(citizenid) ~= 'string' then return nil end
    return Store.Get(PlayerInventoryId(citizenid), { type = 'player', owner = citizenid, label = 'Pockets',
        slots = InventoryConfig.PlayerSlots, maxWeight = InventoryConfig.PlayerMaxWeight })
end

--- The backpack of a character, if they are wearing one.
local function packInv(citizenid)
    return Containers.OpenPack(citizenid)
end

local function fits(inv, item, count, metadata)
    local items = Store.PlanAdd(inv, Store.CopyItems(inv), item, count, metadata or {})
    return items ~= nil and Store.ComputeWeight(items) <= inv.maxWeight
end

asyncExport('CanCarry', function(_, citizenid, item, count, metadata)
    local inv = playerInv(citizenid)
    if not inv then return Ops.err('NOT_FOUND', 'Unknown character') end
    if not ItemDefs[item] or not vlib.validate.int(count, 1, InventoryConfig.MaxCount or 1000000000) then return Ops.err('INVALID_INPUT', 'Unknown item') end
    if fits(inv, item, count, metadata) then return Ops.ok(true) end
    local pk = packInv(citizenid)
    if pk and fits(pk, item, count, metadata) then return Ops.ok(true) end
    return Ops.err('INVENTORY_FULL', 'Not enough space')
end)

--- GiveItem(citizenid, item, count, metadata, opId) — delivery and its operation record commit together.
asyncExport('GiveItem', function(invoker, citizenid, item, count, metadata, opId)
    local inv = playerInv(citizenid)
    if not inv then return Ops.err('NOT_FOUND', 'Unknown character') end
    local res = Ops.Add(inv, item, count, metadata, { opId = opId, actor = invoker, reason = invoker })
    -- Pockets full: try the backpack with the same operation id (the failed attempt recorded nothing).
    if not res.ok and res.code == 'INVENTORY_FULL' then
        local pk = packInv(citizenid)
        if pk then return Ops.Add(pk, item, count, metadata, { opId = opId, actor = invoker, reason = invoker }) end
    end
    return res
end)

--- GiveToStash(stashId, item, count, metadata, opId) — into a registered shared stash (no owner, not keyed), loading it
--- if nobody has opened it yet. Used e.g. by the pawn shop to put bought goods in its stockroom.
asyncExport('GiveToStash', function(invoker, stashId, item, count, metadata, opId)
    local def = type(stashId) == 'string' and Stashes[stashId]
    if not def or def.owner or def.keyed or def.inventory then return Ops.err('NOT_FOUND', 'Unknown stash') end
    local inv = Store.Get('stash:' .. stashId, { type = 'stash', label = def.label, slots = def.slots, maxWeight = def.maxWeight })
    if not inv then return Ops.err('NOT_READY', 'Stash unavailable') end
    return Ops.Add(inv, item, count, metadata, { opId = opId, actor = invoker, reason = invoker })
end)

--- TakeItem(citizenid, item, count, metadata, opId)
asyncExport('TakeItem', function(invoker, citizenid, item, count, metadata, opId)
    local inv = playerInv(citizenid)
    if not inv then return Ops.err('NOT_FOUND', 'Unknown character') end
    local res = Ops.Remove(inv, item, count, metadata, { opId = opId, actor = invoker, reason = invoker })
    if res.ok or res.code ~= 'NOT_ENOUGH_ITEMS' then return res end
    -- Not enough in the pockets: take from the pockets, the backpack and what they wear together, in that order.
    local list = { inv }
    local pk = packInv(citizenid)
    if pk then list[#list + 1] = pk end
    local eq = Store.Get(Containers.EquipId(citizenid))
    if eq then list[#list + 1] = eq end
    local have = {}
    local total = 0
    for i, c in ipairs(list) do have[i] = countOf(c, item, metadata) total = total + have[i] end
    if total < count then return Ops.err('NOT_ENOUGH_ITEMS', 'Not enough items') end
    local left, first = count, true
    for i, c in ipairs(list) do
        local take = math.min(left, have[i])
        if take > 0 then
            local r = Ops.Remove(c, item, take, metadata, { opId = first and opId or (opId .. ':' .. i), actor = invoker, reason = invoker })
            if not r.ok then return r end
            first = false
            left = left - take
        end
    end
    return Ops.ok({ item = item, count = count })
end)

--- GetEquipmentSlot(citizenid, slotId) -> { name, count, metadata, slot } or nil: what a character wears in one equipment slot ('sim', 'hat', ...).
exports('GetEquipmentSlot', function(citizenid, slotId)
    if type(citizenid) ~= 'string' or type(slotId) ~= 'string' then return nil end
    return Containers.EquippedIn(citizenid, slotId)
end)

--- SetEquipmentMetadata(citizenid, slotId, metadata, opId): rewrites the metadata of the single item in an equipment slot
--- (a SIM card gets the number written on it this way). Durable and idempotent per operation id.
asyncExport('SetEquipmentMetadata', function(invoker, citizenid, slotId, metadata, opId)
    local idx = type(slotId) == 'string' and Containers.SlotIndex(slotId)
    local eq = type(citizenid) == 'string' and idx and Store.Get(Containers.EquipId(citizenid))
    if not eq then return Ops.err('NOT_FOUND', 'No such equipment slot') end
    return Ops.SetMetadata(eq, idx, metadata, { opId = opId, actor = invoker, reason = invoker })
end)

--- PutInEquipment(citizenid, slotId, item, metadata, opId): places a new item in an EMPTY equipment slot.
asyncExport('PutInEquipment', function(invoker, citizenid, slotId, item, metadata, opId)
    local idx = type(slotId) == 'string' and Containers.SlotIndex(slotId)
    local eq = type(citizenid) == 'string' and idx and Store.Get(Containers.EquipId(citizenid))
    if not eq then return Ops.err('NOT_FOUND', 'No such equipment slot') end
    return Ops.PlaceInSlot(eq, idx, item, metadata, { opId = opId, actor = invoker, reason = invoker })
end)

--- GetOperation(opId) -> ok({ status = 'done', kind, ... }) or ok(nil). Operations are atomic with their effect:
--- a recorded operation happened; a missing one did not.
asyncExport('GetOperation', function(_, opId)
    local row = DB.GetOperation(opId)
    if not row then return Ops.ok(nil) end
    return Ops.ok({ op_id = row.op_id, kind = row.kind, status = 'done' })
end)

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------
exports('RegisterStash', function(def) Stashes.Register(def, GetInvokingResource()) return true end)

exports('RegisterUseHandler', function(name, fn)
    if type(name) ~= 'string' then return false end
    Use.RegisterHandler(name, fn, GetInvokingResource())
    return true
end)

exports('RegisterUsableItem', function(item, fn)
    if type(item) ~= 'string' then return false end
    Use.RegisterLegacy(item, fn, GetInvokingResource())
    return true
end)

--- RegisterItemAction(item, actionId, fn): extra right-click actions an item definition lists in `actions`.
--- fn({ source, citizenid, item, slot, metadata }) returns ok, message. Runs only when the slot holds that item.
exports('RegisterItemAction', function(item, actionId, fn)
    if type(item) ~= 'string' or type(actionId) ~= 'string' or not fn then return false end
    ItemActions[item] = ItemActions[item] or {}
    ItemActions[item][actionId] = { fn = fn, owner = GetInvokingResource() }
    return true
end)

--- RegisterItemTray(item, actionId, fn): provides the state of the box that a `tray = true` action opens in the inventory.
--- fn({ source, citizenid, item, slot, metadata }) returns { title, hint?, accepts = itemName, current? = { label, detail?, image? }, insertLabel?, removeLabel? }.
exports('RegisterItemTray', function(item, actionId, fn)
    if type(item) ~= 'string' or type(actionId) ~= 'string' or not fn then return false end
    ItemTrays[item] = ItemTrays[item] or {}
    ItemTrays[item][actionId] = { fn = fn, owner = GetInvokingResource() }
    return true
end)

exports('GetUsableItem', function(item) return Use.IsUsable(item) end)

AddEventHandler('onResourceStop', function(res)
    for _, acts in pairs(ItemTrays) do for id, a in pairs(acts) do if a.owner == res then acts[id] = nil end end end
    for _, acts in pairs(ItemActions) do for id, a in pairs(acts) do if a.owner == res then acts[id] = nil end end end
    for name, h in pairs(Use.handlers) do if h.owner == res then Use.handlers[name] = nil end end
    for name, h in pairs(Use.legacy) do if h.owner == res then Use.legacy[name] = nil end end
end)
