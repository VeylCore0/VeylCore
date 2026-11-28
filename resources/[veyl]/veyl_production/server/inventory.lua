-- Inventory and money through VeylCore's durable operations (veyl_inventory GiveItem / TakeItem / CanCarry, veyl_core DebitOnce /
-- CreditOnce). Every call carries an operation id, so a retry never doubles anything.

Prod = Prod or {}
Prod.Inv = {}
local Inv = Prod.Inv

local function opId(tag) return tag end

function Inv.give(cid, item, count, meta, op)
    return Veyl.Await('veyl_inventory', 'GiveItem', 15000, cid, item, count, meta or nil, opId(op))
end

function Inv.take(cid, item, count, meta, op)
    return Veyl.Await('veyl_inventory', 'TakeItem', 15000, cid, item, count, meta or nil, opId(op))
end

function Inv.canCarry(cid, item, count, meta)
    local r = Veyl.Await('veyl_inventory', 'CanCarry', 10000, cid, item, count, meta or nil)
    return r and r.ok == true
end

function Inv.count(src, item) return exports.veyl_inventory:GetItemCount(src, item) or 0 end

function Inv.debit(cid, amount, reason, op, method)
    return Veyl.Await('veyl_core', 'DebitOnce', 15000, cid, method or 'cash', amount, reason, op)
end

function Inv.credit(cid, amount, reason, op, method)
    return Veyl.Await('veyl_core', 'CreditOnce', 15000, cid, method or 'cash', amount, reason, op)
end

--- Authoritative metadata for a product (never taken from a client).
function Inv.productMeta(variety, quality, batch, branch)
    local v = ProdUtil.variety(variety)
    return { variety = variety or 'none', varietyLabel = v and v.label or 'Mixed', quality = ProdUtil.clamp(ProdUtil.round(quality), 1, 100),
        batch = batch or '', branch = branch or 'botanical', created = os.time() }
end

--- The player's stacks of an item with their metadata, best quality first.
function Inv.stacks(src, item)
    local out = {}
    for _, it in pairs(exports.veyl_inventory:GetInventoryItems(src) or {}) do
        if it.name == item then out[#out + 1] = { slot = it.slot, count = it.count, metadata = it.metadata or {} } end
    end
    table.sort(out, function(a, b) return (a.metadata.quality or 0) > (b.metadata.quality or 0) end)
    return out
end

--- Takes `count` of an item, best quality first (so the best leaves are used for the batch). On any failure everything already
--- taken is given back. Returns { ok, avg = average quality, variety, groups = what was taken (for a refund) }.
function Inv.takeBest(src, cid, item, count, tag)
    local have = Inv.count(src, item)
    if have < count then return { ok = false, code = 'NO_ITEM' } end
    local groups, remaining, qsum, vcount = {}, count, 0, {}
    for _, s in ipairs(Inv.stacks(src, item)) do
        if remaining <= 0 then break end
        local n = math.min(remaining, s.count)
        local meta = next(s.metadata) and s.metadata or nil
        local r = Inv.take(cid, item, n, meta, ('%s:%d'):format(tag, #groups + 1))
        if not (r and r.ok) then
            for i, g in ipairs(groups) do Inv.give(cid, item, g.count, g.meta, ('%s:undo:%d'):format(tag, i)) end
            return { ok = false, code = r and r.code or 'FAILED' }
        end
        groups[#groups + 1] = { count = n, meta = meta }
        remaining = remaining - n
        qsum = qsum + (s.metadata.quality or 0) * n
        local v = s.metadata.variety
        if v then vcount[v] = (vcount[v] or 0) + n end
    end
    local best, bn = nil, 0
    for v, n in pairs(vcount) do if n > bn then best, bn = v, n end end
    return { ok = true, avg = qsum / count, variety = best, groups = groups }
end

--- Gives back what takeBest took (used by cancellation).
function Inv.refund(cid, groups, item, tag, fraction)
    for i, g in ipairs(groups or {}) do
        local n = math.floor(g.count * (fraction or 1.0))
        if n > 0 then Inv.give(cid, item, n, g.meta, ('%s:%d'):format(tag, i)) end
    end
end
