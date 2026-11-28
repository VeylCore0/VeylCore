-- What you wear: the items in your equipment slots change how the character looks. The items themselves live on the server (the
-- 'equip' container); this only reads them and applies each one's `wear` data (see data/items.lua):
--   wear = { kind = 'prop',      id = 0, drawable = 8, texture = 0 }   -- hats (0), glasses (1), ears (2) ...
--   wear = { kind = 'component', id = 1, drawable = 28, texture = 0 }  -- masks (1) ...
--   wear = { kind = 'armor',     amount = 100 }                         -- body armour
-- Taking an item off puts the slot back to how it was before it was put on.

local applied = {} -- [equipSlotId] = { name = item, was = { drawable, texture } }

local function slotItems()
    local out = {}
    if InvState.equip and InvState.equip.map then
        for _, s in ipairs(InvState.equipSlots or {}) do
            local it = InvState.equip.map[s.slot]
            if it then out[s.id] = it end
        end
    end
    return out
end

local function clear(slotId, rec, def)
    local ped = PlayerPedId()
    local w = def and def.wear
    if w and w.kind == 'prop' then
        if rec.was and rec.was.drawable and rec.was.drawable >= 0 then SetPedPropIndex(ped, w.id, rec.was.drawable, rec.was.texture or 0, true) else ClearPedProp(ped, w.id) end
    elseif w and w.kind == 'component' then
        SetPedComponentVariation(ped, w.id, (rec.was and rec.was.drawable) or 0, (rec.was and rec.was.texture) or 0, 0)
    elseif w and w.kind == 'armor' then
        SetPedArmour(ped, 0)
    end
end

local function apply(slotId, item, def, fresh)
    local ped = PlayerPedId()
    local w = def.wear
    local rec = { name = item.name }
    if w.kind == 'prop' then
        rec.was = { drawable = GetPedPropIndex(ped, w.id), texture = GetPedPropTextureIndex(ped, w.id) }
        SetPedPropIndex(ped, w.id, w.drawable or 0, w.texture or 0, true)
    elseif w.kind == 'component' then
        rec.was = { drawable = GetPedDrawableVariation(ped, w.id), texture = GetPedTextureVariation(ped, w.id) }
        SetPedComponentVariation(ped, w.id, w.drawable or 0, w.texture or 0, 0)
    elseif w.kind == 'armor' then
        if fresh then SetPedArmour(ped, w.amount or 100) end
    end
    applied[slotId] = rec
end

local function sync(fresh)
    local now = slotItems()
    for slotId, rec in pairs(applied) do
        local it = now[slotId]
        if not it or it.name ~= rec.name then
            clear(slotId, rec, InvState.items[rec.name])
            applied[slotId] = nil
        end
    end
    for slotId, it in pairs(now) do
        local def = InvState.items[it.name]
        if def and def.wear and not applied[slotId] then apply(slotId, it, def, fresh) end
    end
end

AddEventHandler('veyl_inventory:client:equipChanged', function() sync(true) end)

-- After the character loads, wear what was equipped (the appearance system may redraw the ped first, so wait a moment).
RegisterNetEvent('veyl_inventory:init', function()
    CreateThread(function() Wait(3500) applied = {} sync(false) end)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for slotId, rec in pairs(applied) do clear(slotId, rec, InvState.items[rec.name]) end
end)
