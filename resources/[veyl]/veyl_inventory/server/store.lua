-- In-memory inventories (authoritative cache of the DB), locks, weight, views and delta publishing.

Store = { inventories = {} }
local loading = {}
local locks = {}

---------------------------------------------------------------------------
-- Locks: per inventory, always acquired in sorted id order (no deadlocks between opposite transfers).
---------------------------------------------------------------------------
local function acquire(id, kind)
    local deadline = GetGameTimer() + 10000
    while locks[id] do
        if GetGameTimer() > deadline then return false end
        Wait(0)
    end
    locks[id] = kind
    return true
end

--- Runs fn with every listed inventory locked. Returns fn's results, or nil, 'BUSY' on lock timeout.
function Store.WithLocks(ids, fn, kind)
    kind = kind or 'durable'
    local sorted, seen = {}, {}
    for _, id in ipairs(ids) do if not seen[id] then seen[id] = true sorted[#sorted + 1] = id end end
    table.sort(sorted)
    local held = {}
    for _, id in ipairs(sorted) do
        if not acquire(id, kind) then
            for _, h in ipairs(held) do locks[h] = nil end
            return nil, 'BUSY'
        end
        held[#held + 1] = id
    end
    local res = table.pack(pcall(fn))
    for _, h in ipairs(held) do locks[h] = nil end
    if not res[1] then error(res[2], 0) end
    return table.unpack(res, 2, res.n)
end

--- True while a durable operation (which works on a copy) holds the inventory.
function Store.IsLocked(id) return locks[id] == 'durable' end

---------------------------------------------------------------------------
-- Inventories
---------------------------------------------------------------------------
local function computeWeight(items)
    local w = 0
    for _, it in pairs(items) do
        local d = ItemDefs[it.name]
        if d then w = w + d.weight * it.count end
    end
    return w
end
Store.ComputeWeight = computeWeight

--- Returns the loaded inventory, loading it from the DB (once) if needed.
function Store.Get(id, defaults)
    local inv = Store.inventories[id]
    if inv then return inv end
    if not defaults then return nil end
    while loading[id] do Wait(0) end
    inv = Store.inventories[id]
    if inv then return inv end
    loading[id] = true
    local ok, row, items = pcall(DB.Load, id, defaults)
    loading[id] = nil
    if not ok or not row then
        print(('^1[veyl_inventory] failed to load %s: %s^7'):format(id, tostring(row)))
        return nil
    end
    inv = {
        id = id, type = row.type, owner = row.owner, label = row.label, slots = row.slots, maxWeight = row.max_weight,
        revision = row.revision, items = items, weight = computeWeight(items), viewers = {}, reserved = {},
        coords = defaults.coords, radius = defaults.radius, groups = defaults.groups,
    }
    Store.inventories[id] = inv
    return inv
end

function Store.Unload(id)
    local inv = Store.inventories[id]
    if not inv or next(inv.viewers) or locks[id] then return false end
    for _ in pairs(inv.reserved) do return false end
    Store.inventories[id] = nil
    return true
end

---------------------------------------------------------------------------
-- Stack rules
---------------------------------------------------------------------------
function Store.CanStack(a, b)
    if not a or not b or a.name ~= b.name then return false end
    local d = ItemDefs[a.name]
    if not d or not d.stack then return false end
    return vlib.table.equals(a.metadata or {}, b.metadata or {})
end

function Store.Reserved(inv, slot)
    local n = 0
    for _, r in pairs(inv.reserved) do if r.slot == slot then n = n + r.count end end
    return n
end

local instanceSeq = 0
function Store.NewInstance()
    instanceSeq = instanceSeq + 1
    return ('I%x%x%04x'):format(os.time(), instanceSeq, math.random(0, 0xffff))
end

--- Plans where `count` of an item would go (existing stacks first, then empty slots) on a COPY.
--- Returns newItems, changedSlots or nil, code.
function Store.PlanAdd(inv, items, name, count, metadata)
    local d = ItemDefs[name]
    local changed, remaining = {}, count
    if d.stack then
        for s = 1, inv.slots do
            local it = items[s]
            if remaining > 0 and it and Store.CanStack(it, { name = name, metadata = metadata }) and it.count < d.maxStack then
                local add = math.min(d.maxStack - it.count, remaining)
                items[s] = { slot = s, name = it.name, count = it.count + add, metadata = it.metadata, instance = it.instance }
                remaining = remaining - add
                changed[#changed + 1] = s
            end
        end
    end
    for s = 1, inv.slots do
        if remaining <= 0 then break end
        if not items[s] then
            local put = d.stack and math.min(d.maxStack, remaining) or 1
            items[s] = { slot = s, name = name, count = put, metadata = vlib.table.deepcopy(metadata or {}),
                instance = (not d.stack) and Store.NewInstance() or nil }
            remaining = remaining - put
            changed[#changed + 1] = s
        end
    end
    if remaining > 0 then return nil, 'INVENTORY_FULL' end
    return items, changed
end

function Store.CopyItems(inv)
    local out = {}
    for s, it in pairs(inv.items) do out[s] = it end -- slot records are immutable: replaced, never edited
    return out
end

---------------------------------------------------------------------------
-- Views & deltas
---------------------------------------------------------------------------
local function slotView(it)
    if not it then return nil end
    return { slot = it.slot, name = it.name, count = it.count, metadata = PublicMetadata(it.metadata) }
end

function Store.View(inv, ref)
    local list = {}
    for _, it in pairs(inv.items) do list[#list + 1] = slotView(it) end
    return { ref = ref, id = inv.id, label = inv.label, type = inv.type, slots = inv.slots, maxWeight = inv.maxWeight,
        weight = inv.weight, revision = inv.revision, items = list }
end

--- Applies committed items to memory and pushes deltas to every viewer of the inventory.
function Store.Apply(inv, newItems, changedSlots, revision)
    inv.items = newItems
    inv.revision = revision
    inv.weight = computeWeight(newItems)
    local slots = {}
    for i, s in ipairs(changedSlots) do slots[i] = { slot = s, item = slotView(newItems[s]) } end
    for src, ref in pairs(inv.viewers) do
        if GetPlayerName(src) then
            TriggerClientEvent('veyl_inventory:delta', src, { ref = ref, id = inv.id, revision = revision, weight = inv.weight, slots = slots })
        else
            inv.viewers[src] = nil
        end
    end
    TriggerEvent('veyl_inventory:changed', inv.id, changedSlots)
end

function Store.Snapshot(inv, src)
    local ref = inv.viewers[src]
    if ref then TriggerClientEvent('veyl_inventory:snapshot', src, Store.View(inv, ref)) end
end
