-- A character's extra containers next to their pockets: the equipment slots (the body panel) and the backpack. Both are ordinary inventories
-- (same transactional moves, deltas and persistence), found by session ref 'equip' and 'backpack'. Equipment slots carry slot rules, which
-- Ops.Transfer enforces: an item only fits a slot whose id matches its definition's `equip`.

Containers = {}

local function equipSlots() return InventoryConfig.Equipment or {} end

function Containers.EquipId(citizenid) return 'equip:' .. citizenid end
function Containers.PackId(citizenid) return 'pack:' .. citizenid end

--- The slot list for the client: id, label, icon and which side of the body it sits on, in slot order.
function Containers.SlotList()
    local out = {}
    for i, s in ipairs(equipSlots()) do out[i] = { slot = i, id = s.id, label = s.label, icon = s.icon, side = s.side } end
    return out
end

local function ruleMap()
    local rules = {}
    for i, s in ipairs(equipSlots()) do rules[i] = s.id end
    return rules
end

--- Loads (or creates) the equipment and backpack inventories. Returns equip, backpack (backpack is nil when disabled).
function Containers.Load(citizenid)
    local eq
    if #equipSlots() > 0 then
        eq = Store.Get(Containers.EquipId(citizenid), { type = 'stash', owner = citizenid, label = 'Equipment', slots = #equipSlots(), maxWeight = 100000000 })
        if eq then eq.slotRules = ruleMap() end
    end
    local pk
    local B = InventoryConfig.Backpack
    if B and B.Enabled then
        pk = Store.Get(Containers.PackId(citizenid), { type = 'stash', owner = citizenid, label = B.Label or 'Backpack', slots = B.Slots, maxWeight = B.MaxWeight })
    end
    return eq, pk
end

--- A few facts for the personal-information panel (read from the framework; nothing here is trusted from the client).
function Containers.Profile(src, citizenid)
    local ok, pd = pcall(function() return exports.veyl_core:GetPlayerData(src) end)
    local out = { cid = citizenid }
    if ok and type(pd) == 'table' then
        local ci = pd.charinfo or {}
        out.name = ('%s %s'):format(ci.firstname or '', ci.lastname or ''):gsub('^%s+', ''):gsub('%s+$', '')
        out.phone = ci.phone
        out.job = pd.job and (pd.job.label or pd.job.name) or nil
    end
    return out
end
