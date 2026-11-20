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
    local inv = resolve(target)
    return inv and countOf(inv, item, metadata) or 0
end)

exports('GetSlot', function(target, slot)
    local inv = resolve(target)
    return inv and slotOut(inv.items[slot]) or nil
end)

exports('GetSlotWithItem', function(target, item)
    local inv = resolve(target)
    if not inv then return nil end
    for s = 1, inv.slots do
        if inv.items[s] and inv.items[s].name == item then return slotOut(inv.items[s]) end
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
    local inv = resolve(target)
    if not inv then return mode == 'count' and 0 or {} end
    if mode == 'count' then return countOf(inv, item) end
    local out = {}
    for s = 1, inv.slots do
        if inv.items[s] and inv.items[s].name == item then out[#out + 1] = slotOut(inv.items[s]) end
    end
    return out
end)

--- Preview only: the mutating operation re-checks capacity under the lock.
exports('CanCarryItem', function(target, item, count, metadata)
    local inv = resolve(target)
    if not inv or not ItemDefs[item] or not vlib.validate.int(count, 1, 100000) then return false end
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

asyncExport('CanCarry', function(_, citizenid, item, count, metadata)
    local inv = playerInv(citizenid)
    if not inv then return Ops.err('NOT_FOUND', 'Unknown character') end
    if not ItemDefs[item] or not vlib.validate.int(count, 1, 100000) then return Ops.err('INVALID_INPUT', 'Unknown item') end
    local items = Store.PlanAdd(inv, Store.CopyItems(inv), item, count, metadata or {})
    if not items or Store.ComputeWeight(items) > inv.maxWeight then return Ops.err('INVENTORY_FULL', 'Not enough space') end
    return Ops.ok(true)
end)

--- GiveItem(citizenid, item, count, metadata, opId) — delivery and its operation record commit together.
asyncExport('GiveItem', function(invoker, citizenid, item, count, metadata, opId)
    local inv = playerInv(citizenid)
    if not inv then return Ops.err('NOT_FOUND', 'Unknown character') end
    return Ops.Add(inv, item, count, metadata, { opId = opId, actor = invoker, reason = invoker })
end)

--- TakeItem(citizenid, item, count, metadata, opId)
asyncExport('TakeItem', function(invoker, citizenid, item, count, metadata, opId)
    local inv = playerInv(citizenid)
    if not inv then return Ops.err('NOT_FOUND', 'Unknown character') end
    return Ops.Remove(inv, item, count, metadata, { opId = opId, actor = invoker, reason = invoker })
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

exports('GetUsableItem', function(item) return Use.IsUsable(item) end)

AddEventHandler('onResourceStop', function(res)
    for name, h in pairs(Use.handlers) do if h.owner == res then Use.handlers[name] = nil end end
    for name, h in pairs(Use.legacy) do if h.owner == res then Use.legacy[name] = nil end end
end)
