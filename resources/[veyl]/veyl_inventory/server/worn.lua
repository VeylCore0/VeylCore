-- Hat, glasses and mask: the three pieces that come from the character's saved look (veyl_appearance). They are real items in their equipment
-- slots, and the slot and the look are kept in step both ways:
--   * what the saved look has on (a hat from the clothing store, say) shows up as an item in the slot, made for the character,
--   * moving that item out takes it off the look, and wearing one puts its style and colour on the look and saves it.
-- The item carries the style (d) and colour (t). Only these three slots work this way; every other slot is plain inventory.

Worn = {}

local KEYS = { 'hat', 'glasses', 'mask' }
local ITEM = { hat = 'clothing_hat', glasses = 'clothing_glasses', mask = 'clothing_mask' }

local last = {}               -- [cid][key] = what the slot held when we last looked (so only real slot changes are pushed to the look)
local busy, again = {}, {}
local seq = 0

local function ctx(cid)
    seq = seq + 1
    return { opId = ('worn:%s:%d:%d'):format(cid, GetGameTimer(), seq), actor = 'veyl_appearance', reason = 'appearance sync' }
end

local function look(cid)
    if GetResourceState('veyl_appearance') ~= 'started' then return nil end
    local ok, w = pcall(function() return exports.veyl_appearance:GetWorn(cid) end)
    return ok and type(w) == 'table' and w or nil
end

local function sig(it)
    if not it or it.name == nil then return '' end
    local m = it.metadata or {}
    return ('%s:%s:%s'):format(it.name, tostring(m.d), tostring(m.t or 0))
end

--- The look is the truth: make the three slots match it.
function Worn.Reconcile(cid)
    local w = look(cid)
    local eq = Store.Get(Containers.EquipId(cid))
    if not w or not eq then return end
    for _, key in ipairs(KEYS) do
        local idx = Containers.SlotIndex(key)
        local it = idx and eq.items[idx]
        local want = w[key]
        if idx then
            if want then
                if not it then
                    Ops.PlaceInSlot(eq, idx, ITEM[key], { d = want.d, t = want.t }, ctx(cid))
                elseif it.name == ITEM[key] and not (it.metadata and it.metadata.d == want.d and (it.metadata.t or 0) == (want.t or 0)) then
                    Ops.SetMetadata(eq, idx, { d = want.d, t = want.t }, ctx(cid))
                end
            elseif it and it.name == ITEM[key] then
                Ops.Remove(eq, ITEM[key], 1, nil, ctx(cid))
            end
        end
    end
    last[cid] = last[cid] or {}
    for _, key in ipairs(KEYS) do
        local idx = Containers.SlotIndex(key)
        last[cid][key] = sig(idx and eq.items[idx])
    end
end

--- The slots are the truth for what the player just did: put the change on the look.
function Worn.Push(cid)
    local w = look(cid)
    local eq = Store.Get(Containers.EquipId(cid))
    if not w or not eq then return end
    last[cid] = last[cid] or {}
    for _, key in ipairs(KEYS) do
        local idx = Containers.SlotIndex(key)
        local it = idx and eq.items[idx]
        local now = sig(it)
        local before = last[cid][key]
        last[cid][key] = now
        -- Only a change we have seen happen (before ~= nil) is pushed; the first look at a slot just records it.
        if idx and before ~= nil and before ~= now then
            if it and it.name == ITEM[key] then
                local m = it.metadata or {}
                if type(m.d) == 'number' then
                    local cur = w[key]
                    if not cur or cur.d ~= m.d or (cur.t or 0) ~= (m.t or 0) then
                        pcall(function() exports.veyl_appearance:SetWorn(cid, key, m.d, m.t or 0) end)
                    end
                end
            elseif not it and w[key] then
                pcall(function() exports.veyl_appearance:SetWorn(cid, key, -1, 0) end)
            end
        end
    end
end

local function once(cid, fn)
    if busy[cid] then again[cid] = fn return end
    busy[cid] = true
    local ok, err = pcall(fn, cid)
    busy[cid] = nil
    if not ok then print(('^1[veyl_inventory] worn pieces for %s: %s^7'):format(cid, tostring(err))) end
    local next = again[cid]
    if next then again[cid] = nil once(cid, next) end
end

-- The inventory changed a character's equipment.
AddEventHandler('veyl_inventory:changed', function(invId)
    if type(invId) ~= 'string' or invId:sub(1, 6) ~= 'equip:' then return end
    local cid = invId:sub(7)
    CreateThread(function() once(cid, Worn.Push) end)
end)

-- The saved look changed (a clothing store, an outfit, the editor, or our own push).
AddEventHandler('veyl_appearance:saved', function(cid)
    if type(cid) ~= 'string' then return end
    local known = false
    for _, p in pairs(Players) do if p.citizenid == cid then known = true break end end
    if known then CreateThread(function() once(cid, Worn.Reconcile) end) end
end)

AddEventHandler('playerDropped', function()
    local p = Players[source]
    if p then last[p.citizenid] = nil end
end)
