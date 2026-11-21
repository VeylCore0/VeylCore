-- Appearance data model shared by client and server.
-- Saved appearance (canonical):
--   { model, components = { {id,d,t} }, props = { {id,d,t} }, overlays = { {id,d,opacity,color} },
--     headBlend = { mother, father, shapeMix, skinMix }, hair = { color, highlight }, faceFeatures = { 20 x -100..100 }, eyeColor }
-- A "slot" is one category's value: { d, t, opacity, color, color2 } (overlay d = style, -1 = none; prop d = -1 = none).

Appearance = {}

Appearance.byKey = {}
for _, c in ipairs(AppearanceConfig.Categories) do Appearance.byKey[c.key] = c end

Appearance.FEATURE_COUNT = 20

local function find(list, id)
    for _, e in ipairs(list or {}) do if e.id == id then return e end end
end

local function upsert(list, entry)
    for i, e in ipairs(list) do if e.id == entry.id then list[i] = entry return end end
    list[#list + 1] = entry
end

--- Fills missing fields so old saves (before overlays/features existed) keep working.
function Appearance.normalise(a)
    a.components = type(a.components) == 'table' and a.components or {}
    a.props = type(a.props) == 'table' and a.props or {}
    a.overlays = type(a.overlays) == 'table' and a.overlays or {}
    a.headBlend = type(a.headBlend) == 'table' and a.headBlend or { mother = 21, father = 0, shapeMix = 50, skinMix = 50 }
    a.hair = type(a.hair) == 'table' and a.hair or { color = 0, highlight = 0 }
    local f = type(a.faceFeatures) == 'table' and a.faceFeatures or {}
    a.faceFeatures = {}
    for i = 1, Appearance.FEATURE_COUNT do a.faceFeatures[i] = tonumber(f[i]) or 0 end
    a.eyeColor = tonumber(a.eyeColor) or 0
    return a
end

--- Value of one category (nil fields mean "not set", e.g. a component never changed from the model default).
function Appearance.getSlot(a, cat)
    if cat.kind == 'component' then
        local e = find(a.components, cat.id)
        local s = { d = e and e.d or nil, t = e and e.t or 0 }
        if cat.key == 'hair' then s.color, s.color2 = a.hair.color or 0, a.hair.highlight or 0 end
        return s
    elseif cat.kind == 'prop' then
        local e = find(a.props, cat.id)
        return { d = e and e.d or -1, t = e and e.t or 0 }
    elseif cat.kind == 'overlay' then
        local e = find(a.overlays, cat.id)
        return { d = e and e.d or -1, opacity = e and e.opacity or 100, color = e and e.color or 0 }
    elseif cat.kind == 'heritage' then
        local h = a.headBlend
        return { mother = h.mother, father = h.father, shapeMix = h.shapeMix, skinMix = h.skinMix }
    elseif cat.kind == 'features' then
        return { values = a.faceFeatures }
    elseif cat.kind == 'eyes' then
        return { d = a.eyeColor }
    end
end

function Appearance.setSlot(a, cat, s)
    if cat.kind == 'component' then
        if s.d then upsert(a.components, { id = cat.id, d = s.d, t = s.t or 0 }) end
        if cat.key == 'hair' then a.hair = { color = s.color or 0, highlight = s.color2 or 0 } end
    elseif cat.kind == 'prop' then
        upsert(a.props, { id = cat.id, d = s.d, t = s.d >= 0 and (s.t or 0) or 0 })
    elseif cat.kind == 'overlay' then
        upsert(a.overlays, { id = cat.id, d = s.d, opacity = s.opacity or 100, color = s.color or 0 })
    elseif cat.kind == 'heritage' then
        a.headBlend = { mother = s.mother, father = s.father, shapeMix = s.shapeMix, skinMix = s.skinMix }
    elseif cat.kind == 'features' then
        a.faceFeatures = s.values
    elseif cat.kind == 'eyes' then
        a.eyeColor = s.d
    end
end

function Appearance.sameSlot(x, y)
    if x == nil or y == nil then return x == y end
    for _, k in ipairs({ 'd', 't', 'opacity', 'color', 'color2', 'mother', 'father', 'shapeMix', 'skinMix' }) do
        if x[k] ~= y[k] then return false end
    end
    if x.values or y.values then
        for i = 1, Appearance.FEATURE_COUNT do
            if (x.values or {})[i] ~= (y.values or {})[i] then return false end
        end
    end
    return true
end

--- Category keys a mode may change.
function Appearance.allowedKeys(mode)
    local m = AppearanceConfig.Modes[mode]
    if not m then return {} end
    local groups, keys = {}, {}
    for _, g in ipairs(m.groups) do groups[g] = true end
    for _, c in ipairs(AppearanceConfig.Categories) do if groups[c.group] then keys[#keys + 1] = c.key end end
    return keys
end
