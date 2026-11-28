-- Client view of the player's inventory (server snapshots + deltas only; never edited locally).

InvState = { primary = nil, secondary = nil, equip = nil, backpack = nil, equipSlots = {}, items = {}, imagePath = '' }

local function toMap(view)
    if not view then return nil end
    local map = {}
    for _, it in ipairs(view.items or {}) do map[it.slot] = it end
    view.map = map
    return view
end

local function pushCounts()
    local counts = {}
    -- Pockets, backpack and what you wear all count as "you have it".
    for _, view in ipairs({ InvState.primary or false, InvState.backpack or false, InvState.equip or false }) do
        if view then for _, it in pairs(view.map) do counts[it.name] = (counts[it.name] or 0) + it.count end end
    end
    InvState.counts = counts
    TriggerEvent('veyl_inventory:client:counts', counts)
end

RegisterNetEvent('veyl_inventory:init', function(data)
    InvState.primary = toMap(data.primary)
    InvState.equip = toMap(data.equip)
    InvState.backpack = toMap(data.backpack)
    InvState.equipSlots = data.equipSlots or {}
    InvState.items = data.items or {}
    InvState.imagePath = data.imagePath or ''
    pushCounts()
end)

local function applyDelta(view, d)
    for _, change in ipairs(d.slots or {}) do view.map[change.slot] = change.item end
    view.revision, view.weight = d.revision, d.weight
end

RegisterNetEvent('veyl_inventory:delta', function(d)
    local view = InvState[d.ref]
    if not view or view.id ~= d.id then return end
    applyDelta(view, d)
    if d.ref ~= 'secondary' then pushCounts() end
    if d.ref == 'equip' then TriggerEvent('veyl_inventory:client:equipChanged') end
    UI_Forward('delta', d)
end)

RegisterNetEvent('veyl_inventory:snapshot', function(view)
    if view.ref == 'primary' or view.ref == 'equip' or view.ref == 'backpack' then
        InvState[view.ref] = toMap(view)
        pushCounts()
        if view.ref == 'equip' then TriggerEvent('veyl_inventory:client:equipChanged') end
    elseif InvState.secondary and (InvState.secondary.id == view.id or (InvState.secondary.type == 'drop' and view.type == 'drop')) then
        -- A ground box can become a real drop (first item dropped) or fall back to an empty Ground box.
        InvState.secondary = toMap(view)
    end
    UI_Forward('snapshot', view)
end)

RegisterNetEvent('VeylCore:Client:OnPlayerUnload', function()
    InvState.primary, InvState.secondary, InvState.equip, InvState.backpack = nil, nil, nil, nil
    pushCounts()
    TriggerEvent('veyl_inventory:client:equipChanged')
end)

exports('GetItemCounts', function() return InvState.counts or {} end)
exports('GetItemCount', function(item) return (InvState.counts or {})[item] or 0 end)
exports('Items', function(name) if name then return InvState.items[name] end return InvState.items end)
exports('GetItemDefinition', function(name) return InvState.items[name] end)
