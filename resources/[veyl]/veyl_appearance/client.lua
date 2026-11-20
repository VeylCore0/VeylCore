-- veyl_appearance client: apply saved appearance and run the editor.

local editor = nil -- { cam, snapshot, cb }

local function listToMap(list)
    local map = {}
    for _, e in ipairs(list or {}) do map[e.id] = e end
    return map
end

local function defaultAppearance(sex)
    sex = sex == 'f' and 'f' or 'm'
    local comps = {}
    for id, v in pairs(AppearanceConfig.Defaults[sex].components) do
        comps[#comps + 1] = { id = id, d = v[1], t = v[2] }
    end
    return {
        model = AppearanceConfig.Models[sex],
        components = comps,
        props = {},
        headBlend = { mother = sex == 'f' and 21 or 0, father = sex == 'f' and 0 or 4, shapeMix = sex == 'f' and 30 or 70, skinMix = 50 },
        hair = { color = 0, highlight = 0 },
    }
end

local function applyToPed(ped, a)
    local hb = a.headBlend or {}
    SetPedHeadBlendData(ped, hb.mother or 21, hb.father or 0, 0, hb.mother or 21, hb.father or 0, 0,
        (hb.shapeMix or 50) / 100.0, (hb.skinMix or 50) / 100.0, 0.0, false)
    for _, c in ipairs(a.components or {}) do
        SetPedComponentVariation(ped, c.id, c.d, c.t, 0)
    end
    for _, p in ipairs(a.props or {}) do
        if p.d < 0 then ClearPedProp(ped, p.id) else SetPedPropIndex(ped, p.id, p.d, p.t, true) end
    end
    if a.hair then SetPedHairColor(ped, a.hair.color or 0, a.hair.highlight or 0) end
end

--- Changes the player model (if needed) and applies the appearance. Returns true on success.
local function applyAppearance(a)
    if type(a) ~= 'table' or not a.model then return false end
    local hash = Veyl.LoadModel(a.model, 10000)
    if not hash then return false end
    if GetEntityModel(PlayerPedId()) ~= hash then
        SetPlayerModel(PlayerId(), hash)
        SetModelAsNoLongerNeeded(hash)
        local ped = PlayerPedId()
        SetPedDefaultComponentVariation(ped)
    end
    applyToPed(PlayerPedId(), a)
    return true
end

-- Async exports used by veyl_spawn: Veyl.Await('veyl_appearance', 'Apply', timeout, appearance)
Veyl.AsyncExport('Apply', function(a) return applyAppearance(a) end)
Veyl.AsyncExport('ApplyDefault', function(sex) return applyAppearance(defaultAppearance(sex)) end)

---------------------------------------------------------------------------
-- Editor
---------------------------------------------------------------------------
local current = nil -- appearance being edited

local function rowsFor(ped)
    local comps, props = listToMap(current.components), listToMap(current.props)
    local rows = {}
    for _, c in ipairs(AppearanceConfig.Components) do
        local d = comps[c.id] and comps[c.id].d or GetPedDrawableVariation(ped, c.id)
        local t = comps[c.id] and comps[c.id].t or GetPedTextureVariation(ped, c.id)
        rows[#rows + 1] = {
            kind = 'component', id = c.id, label = c.label, d = d, t = t, minD = 0,
            maxD = math.max(0, GetNumberOfPedDrawableVariations(ped, c.id) - 1),
            maxT = math.max(0, GetNumberOfPedTextureVariations(ped, c.id, d) - 1),
        }
    end
    for _, p in ipairs(AppearanceConfig.Props) do
        local d = props[p.id] and props[p.id].d or GetPedPropIndex(ped, p.id)
        local t = props[p.id] and props[p.id].t or math.max(0, GetPedPropTextureIndex(ped, p.id))
        rows[#rows + 1] = {
            kind = 'prop', id = p.id, label = p.label, d = d, t = t, minD = -1,
            maxD = math.max(-1, GetNumberOfPedPropDrawableVariations(ped, p.id) - 1),
            maxT = d >= 0 and math.max(0, GetNumberOfPedPropTextureVariations(ped, p.id, d) - 1) or 0,
        }
    end
    return rows
end

local function setEntry(list, id, d, t)
    for _, e in ipairs(list) do
        if e.id == id then e.d, e.t = d, t return end
    end
    list[#list + 1] = { id = id, d = d, t = t }
end

local function startEditorCam(ped)
    local coords = GetOffsetFromEntityInWorldCoords(ped, 0.0, 2.2, 0.4)
    local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', coords.x, coords.y, coords.z, 0.0, 0.0, 0.0, 45.0, false, 0)
    local head = GetEntityCoords(ped)
    PointCamAtCoord(cam, head.x, head.y, head.z + 0.2)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 400, true, true)
    return cam
end

local function closeEditor(saved)
    if not editor then return end
    local e = editor
    editor = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'close' })
    RenderScriptCams(false, true, 300, true, true)
    DestroyCam(e.cam, false)
    FreezeEntityPosition(PlayerPedId(), false)
    if not saved and e.snapshot then applyAppearance(e.snapshot) end
    if e.cb then pcall(e.cb, saved) end
end

local function openEditor(base, allowCancel, cb)
    if editor then if cb then cb(false) end return end
    current = json.decode(json.encode(base)) -- deep copy
    if not applyAppearance(current) then if cb then cb(false) end return end
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, true)
    ClearPedTasksImmediately(ped)
    editor = { cam = startEditorCam(ped), snapshot = allowCancel and base or nil, cb = cb }
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'open',
        allowCancel = allowCancel,
        rows = rowsFor(ped),
        headBlend = current.headBlend,
        hair = current.hair,
        sex = current.model == AppearanceConfig.Models.f and 'f' or 'm',
    })
end

--- OpenEditor(sexOrNil, allowCancel, cb) -> cb(saved:boolean). Loads saved appearance when present.
exports('OpenEditor', function(sex, allowCancel, cb)
    CreateThread(function()
        local res = Veyl.Callback('veyl_appearance', 'get')
        local base = (res.ok and res.data) or defaultAppearance(sex)
        openEditor(base, allowCancel ~= false, cb)
    end)
end)

RegisterNUICallback('change', function(data, cb)
    if not editor or type(data) ~= 'table' then return cb({}) end
    local ped = PlayerPedId()
    local id, d, t = tonumber(data.id), tonumber(data.d), tonumber(data.t)
    if data.kind == 'component' and id and d and t then
        local maxT = math.max(0, GetNumberOfPedTextureVariations(ped, id, d) - 1)
        t = math.min(t, maxT)
        SetPedComponentVariation(ped, id, d, t, 0)
        setEntry(current.components, id, d, t)
        return cb({ maxT = maxT, t = t })
    elseif data.kind == 'prop' and id and d and t then
        local maxT = 0
        if d < 0 then
            ClearPedProp(ped, id)
            t = 0
        else
            maxT = math.max(0, GetNumberOfPedPropTextureVariations(ped, id, d) - 1)
            t = math.min(t, maxT)
            SetPedPropIndex(ped, id, d, t, true)
        end
        setEntry(current.props, id, d, t)
        return cb({ maxT = maxT, t = t })
    elseif data.kind == 'headBlend' and type(data.values) == 'table' then
        current.headBlend = data.values
        applyToPed(ped, { headBlend = current.headBlend })
    elseif data.kind == 'hair' and type(data.values) == 'table' then
        current.hair = data.values
        SetPedHairColor(ped, current.hair.color or 0, current.hair.highlight or 0)
    elseif data.kind == 'sex' then
        current = defaultAppearance(data.value)
        applyAppearance(current)
        return cb({ rows = rowsFor(PlayerPedId()), headBlend = current.headBlend, hair = current.hair })
    elseif data.kind == 'rotate' then
        SetEntityHeading(ped, GetEntityHeading(ped) + (tonumber(data.value) or 0))
    end
    cb({})
end)

RegisterNUICallback('save', function(_, cb)
    cb({})
    if not editor then return end
    local res = Veyl.Callback('veyl_appearance', 'save', current)
    if res.ok then
        Veyl.Notify('Appearance saved', 'success')
        closeEditor(true)
    else
        SendNUIMessage({ action = 'error', message = res.message or res.code })
    end
end)

RegisterNUICallback('cancel', function(_, cb)
    cb({})
    if editor and editor.snapshot then closeEditor(false) end
end)

RegisterCommand('appearance', function()
    if not AppearanceConfig.AllowCommand or not Veyl.IsLoaded() or editor then return end
    exports.veyl_appearance:OpenEditor(nil, true, function() end)
end, false)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() or not editor then return end
    SetNuiFocus(false, false)
    RenderScriptCams(false, false, 0, true, true)
    DestroyCam(editor.cam, false)
    FreezeEntityPosition(PlayerPedId(), false)
end)
