-- veyl_appearance client: applies saved looks, runs the editor (character creator, clothing stores, barbers, /appearance).
-- Prices shown in the editor are a preview; the server prices and charges every store change itself.

local screen = vlib.createScreen({ name = 'appearance', onClose = function(reason) OnEditorClosed(reason) end })
local editor = nil -- { mode, store, index, current, original, display, cam, focus, cb, saved, outfits }

local COLOR_TYPE = { hair = 1, makeup = 2 }

local function copy(t) return json.decode(json.encode(t)) end

local function defaultAppearance(sex)
    sex = sex == 'f' and 'f' or 'm'
    local comps = {}
    for id, v in pairs(AppearanceConfig.Defaults[sex].components) do
        comps[#comps + 1] = { id = id, d = v[1], t = v[2] }
    end
    return Appearance.normalise({
        model = AppearanceConfig.Models[sex],
        components = comps,
        headBlend = { mother = sex == 'f' and 21 or 0, father = sex == 'f' and 0 or 4, shapeMix = sex == 'f' and 30 or 70, skinMix = 50 },
    })
end

local overlayCat = {}
for _, c in ipairs(AppearanceConfig.Categories) do if c.kind == 'overlay' then overlayCat[c.id] = c end end

local function applyOverlay(ped, o)
    if o.d < 0 then
        SetPedHeadOverlay(ped, o.id, 255, 0.0)
    else
        SetPedHeadOverlay(ped, o.id, o.d, (o.opacity or 100) / 100.0)
        local cat = overlayCat[o.id]
        if cat and cat.color then SetPedHeadOverlayColor(ped, o.id, COLOR_TYPE[cat.color], o.color or 0, o.color or 0) end
    end
end

local function applyToPed(ped, a)
    local hb = a.headBlend or {}
    SetPedHeadBlendData(ped, hb.mother or 21, hb.father or 0, 0, hb.mother or 21, hb.father or 0, 0,
        (hb.shapeMix or 50) / 100.0, (hb.skinMix or 50) / 100.0, 0.0, false)
    for i, v in ipairs(a.faceFeatures or {}) do SetPedFaceFeature(ped, i - 1, (v or 0) / 100.0) end
    SetPedEyeColor(ped, a.eyeColor or 0)
    for _, c in ipairs(a.components or {}) do SetPedComponentVariation(ped, c.id, c.d, c.t, 0) end
    for _, p in ipairs(a.props or {}) do
        if p.d < 0 then ClearPedProp(ped, p.id) else SetPedPropIndex(ped, p.id, p.d, p.t, true) end
    end
    if a.hair then SetPedHairColor(ped, a.hair.color or 0, a.hair.highlight or 0) end
    for _, o in ipairs(a.overlays or {}) do applyOverlay(ped, o) end
end

--- Changes the player model (if needed) and applies the appearance. Returns true on success.
local function applyAppearance(a)
    if type(a) ~= 'table' or not a.model then return false end
    Appearance.normalise(a)
    local hash = Veyl.LoadModel(a.model, 10000)
    if not hash then return false end
    if GetEntityModel(PlayerPedId()) ~= hash then
        SetPlayerModel(PlayerId(), hash)
        SetModelAsNoLongerNeeded(hash)
        SetPedDefaultComponentVariation(PlayerPedId())
    end
    applyToPed(PlayerPedId(), a)
    return true
end

-- Async exports used by veyl_spawn: Veyl.Await('veyl_appearance', 'Apply', timeout, appearance)
Veyl.AsyncExport('Apply', function(a) return applyAppearance(a) end)
Veyl.AsyncExport('ApplyDefault', function(sex) return applyAppearance(defaultAppearance(sex)) end)

---------------------------------------------------------------------------
-- Camera
---------------------------------------------------------------------------
local function focusCamera(focus)
    if not editor then return end
    local preset = AppearanceConfig.Cameras[focus] or AppearanceConfig.Cameras.full
    local ped = PlayerPedId()
    local pos = GetOffsetFromEntityInWorldCoords(ped, 0.0, preset.dist, preset.z)
    -- Aim slightly to the ped's right so the ped sits right of centre, clear of the editor panel on the left.
    local aim = GetOffsetFromEntityInWorldCoords(ped, preset.dist * 0.18, 0.0, preset.z)
    local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', pos.x, pos.y, pos.z, 0.0, 0.0, 0.0, preset.fov, false, 0)
    PointCamAtCoord(cam, aim.x, aim.y, aim.z)
    if editor.cam then
        SetCamActiveWithInterp(cam, editor.cam, 450, 1, 1)
        local old = editor.cam
        SetTimeout(500, function() DestroyCam(old, false) end)
    else
        SetCamActive(cam, true)
        RenderScriptCams(true, true, 400, true, true)
    end
    editor.cam, editor.focus = cam, focus
end

local function stopCamera()
    RenderScriptCams(false, true, 300, true, true)
    if editor and editor.cam then DestroyCam(editor.cam, false) end
end

---------------------------------------------------------------------------
-- Editor data for the UI
---------------------------------------------------------------------------
local function rgbHex(r, g, b) return ('#%02x%02x%02x'):format(r or 0, g or 0, b or 0) end

local function palettes()
    local hair, makeup = {}, {}
    for i = 0, 63 do
        hair[#hair + 1] = rgbHex(GetPedHairRgbColor(i))
        makeup[#makeup + 1] = rgbHex(GetPedMakeupRgbColor(i))
    end
    return { hair = hair, makeup = makeup }
end

local function texturesFor(ped, cat, d)
    if cat.kind == 'component' then return math.max(1, GetNumberOfPedTextureVariations(ped, cat.id, d)) end
    if cat.kind == 'prop' and d >= 0 then return math.max(1, GetNumberOfPedPropTextureVariations(ped, cat.id, d)) end
    return 1
end

--- Slot as the UI shows it: a component never set in the saved look shows what the ped is wearing.
local function displaySlot(ped, a, cat)
    local s = Appearance.getSlot(a, cat)
    if cat.kind == 'component' and s.d == nil then
        s.d, s.t = GetPedDrawableVariation(ped, cat.id), GetPedTextureVariation(ped, cat.id)
    end
    return s
end

local function allowedCategories(mode)
    local allowed = {}
    for _, k in ipairs(Appearance.allowedKeys(mode)) do allowed[k] = true end
    local list = {}
    for _, c in ipairs(AppearanceConfig.Categories) do
        if allowed[c.key] then list[#list + 1] = c end
    end
    return list
end

local function payload()
    local ped, e = PlayerPedId(), editor
    local cats, values, original = {}, {}, {}
    for _, c in ipairs(allowedCategories(e.mode)) do
        local max = nil
        if c.kind == 'component' then max = GetNumberOfPedDrawableVariations(ped, c.id) - 1
        elseif c.kind == 'prop' then max = GetNumberOfPedPropDrawableVariations(ped, c.id) - 1
        elseif c.kind == 'overlay' then max = GetPedHeadOverlayNum(c.id) - 1 end
        local v = displaySlot(ped, e.current, c)
        cats[#cats + 1] = {
            key = c.key, group = c.group, label = c.label, icon = c.icon, camera = c.camera, kind = c.kind,
            color = c.color, color2 = c.color2 == true, max = max, textures = v.d and texturesFor(ped, c, v.d) or 1,
        }
        values[c.key] = v
        original[c.key] = e.display[c.key] or v
    end
    local s = e.storeInfo
    return {
        mode = e.mode, allowCancel = e.allowCancel,
        title = s and s.title or (e.mode == 'create' and 'Create your character' or 'Appearance'),
        subtitle = s and s.subtitle or (e.mode == 'create' and 'Pick a starting look. You can change clothes and hair later in stores.' or 'Free editor'),
        sex = e.current.model == AppearanceConfig.Models.f and 'f' or 'm',
        categories = cats, values = values, original = original, palettes = palettes(),
        store = s and { prices = s.prices, balances = s.balances, methods = s.methods, outfits = e.outfits } or nil,
    }
end

--- Remembers what each category looked like when the editor opened (used for prices and "Reset").
local function snapshotDisplay()
    local ped = PlayerPedId()
    editor.display = {}
    for _, c in ipairs(allowedCategories(editor.mode)) do editor.display[c.key] = displaySlot(ped, editor.current, c) end
end

---------------------------------------------------------------------------
-- Open / close
---------------------------------------------------------------------------
function OnEditorClosed(reason)
    if not editor then return end
    local e = editor
    stopCamera()
    editor = nil
    FreezeEntityPosition(PlayerPedId(), false)
    if not e.saved and e.original then applyAppearance(e.original) end
    if e.cb then pcall(e.cb, e.saved == true) end
end

local function openEditor(opts)
    if editor or screen:isOpen() then if opts.cb then opts.cb(false) end return end
    local base = Appearance.normalise(copy(opts.base))
    if not applyAppearance(copy(base)) then if opts.cb then opts.cb(false) end return end
    local ped = PlayerPedId()
    ClearPedTasksImmediately(ped)
    FreezeEntityPosition(ped, true)
    editor = {
        mode = opts.mode, store = opts.store, index = opts.index, storeInfo = opts.storeInfo, outfits = opts.storeInfo and opts.storeInfo.outfits,
        allowCancel = opts.allowCancel, current = copy(base), original = opts.allowCancel and copy(base) or nil, cb = opts.cb,
    }
    snapshotDisplay()
    focusCamera('full')
    local ok, reason = screen:open('appearance:open', payload())
    if not ok then
        local e = editor
        e.saved = false
        OnEditorClosed('unavailable')
        Veyl.Notify(reason == 'busy' and 'Close the open menu first.' or 'Appearance editor unavailable.', 'warning')
    end
end

--- OpenEditor(sexOrNil, allowCancel, cb) -> cb(saved:boolean). Character creation (allowCancel=false) or the free editor.
exports('OpenEditor', function(sex, allowCancel, cb)
    CreateThread(function()
        local res = Veyl.Callback('veyl_appearance', 'get')
        local base = (res.ok and res.data) or defaultAppearance(sex)
        openEditor({ mode = allowCancel == false and 'create' or 'admin', base = base, allowCancel = allowCancel ~= false, cb = cb })
    end)
end)

local function openStore(storeType, index)
    if editor or not Veyl.IsLoaded() then return end
    if IsPedInAnyVehicle(PlayerPedId(), false) then return Veyl.Notify('Step out of the vehicle first', 'warning') end
    local ctx = Veyl.Callback('veyl_appearance', 'storeContext', storeType, index)
    if not ctx.ok then return Veyl.NotifyResult(ctx) end
    local res = Veyl.Callback('veyl_appearance', 'get')
    if not res.ok or not res.data then return Veyl.Notify('Create your character first', 'error') end
    openEditor({ mode = storeType, store = storeType, index = index, storeInfo = ctx.data, base = res.data, allowCancel = true })
end

---------------------------------------------------------------------------
-- NUI callbacks
---------------------------------------------------------------------------
local function reply(cb, res) cb({ ok = res.ok, code = res.code, message = res.message, data = res.data }) end

local function num(v, min, max, default)
    v = tonumber(v)
    if not v or v ~= v then return default end
    return math.max(min, math.min(max, math.floor(v)))
end

RegisterNUICallback('change', function(data, cb)
    if not editor or type(data) ~= 'table' then return cb({ ok = false }) end
    local cat = Appearance.byKey[tostring(data.key)]
    local allowed = false
    for _, k in ipairs(Appearance.allowedKeys(editor.mode)) do if k == (cat and cat.key) then allowed = true break end end
    if not allowed or type(data.value) ~= 'table' then return cb({ ok = false, code = 'INVALID_INPUT' }) end
    local ped, v, out = PlayerPedId(), data.value, nil
    if cat.kind == 'component' then
        local d = num(v.d, 0, GetNumberOfPedDrawableVariations(ped, cat.id) - 1, 0)
        local textures = texturesFor(ped, cat, d)
        out = { d = d, t = num(v.t, 0, textures - 1, 0) }
        if cat.key == 'hair' then out.color, out.color2 = num(v.color, 0, 63, 0), num(v.color2, 0, 63, 0) end
        SetPedComponentVariation(ped, cat.id, out.d, out.t, 0)
        if cat.key == 'hair' then SetPedHairColor(ped, out.color, out.color2) end
        Appearance.setSlot(editor.current, cat, out)
        return cb({ ok = true, data = { value = out, textures = textures } })
    elseif cat.kind == 'prop' then
        local d = num(v.d, -1, GetNumberOfPedPropDrawableVariations(ped, cat.id) - 1, -1)
        local textures = texturesFor(ped, cat, d)
        out = { d = d, t = d >= 0 and num(v.t, 0, textures - 1, 0) or 0 }
        if d < 0 then ClearPedProp(ped, cat.id) else SetPedPropIndex(ped, cat.id, out.d, out.t, true) end
        Appearance.setSlot(editor.current, cat, out)
        return cb({ ok = true, data = { value = out, textures = textures } })
    elseif cat.kind == 'overlay' then
        out = { d = num(v.d, -1, GetPedHeadOverlayNum(cat.id) - 1, -1), opacity = num(v.opacity, 0, 100, 100), color = num(v.color, 0, 63, 0) }
        applyOverlay(ped, { id = cat.id, d = out.d, opacity = out.opacity, color = out.color })
        Appearance.setSlot(editor.current, cat, out)
    elseif cat.kind == 'heritage' then
        out = { mother = num(v.mother, 0, 45, 21), father = num(v.father, 0, 45, 0), shapeMix = num(v.shapeMix, 0, 100, 50), skinMix = num(v.skinMix, 0, 100, 50) }
        Appearance.setSlot(editor.current, cat, out)
        applyToPed(ped, editor.current) -- head blend resets overlays and features, so re-apply everything
    elseif cat.kind == 'features' then
        local values = {}
        for i = 1, Appearance.FEATURE_COUNT do values[i] = num(type(v.values) == 'table' and v.values[i] or 0, -100, 100, 0) end
        out = { values = values }
        Appearance.setSlot(editor.current, cat, out)
        for i, f in ipairs(values) do SetPedFaceFeature(ped, i - 1, f / 100.0) end
    elseif cat.kind == 'eyes' then
        out = { d = num(v.d, 0, 31, 0) }
        Appearance.setSlot(editor.current, cat, out)
        SetPedEyeColor(ped, out.d)
    end
    cb({ ok = true, data = { value = out } })
end)

RegisterNUICallback('camera', function(data, cb)
    cb({ ok = true })
    if editor and type(data) == 'table' and AppearanceConfig.Cameras[data.focus] and data.focus ~= editor.focus then focusCamera(data.focus) end
end)

RegisterNUICallback('rotate', function(data, cb)
    cb({ ok = true })
    if not editor then return end
    local ped = PlayerPedId()
    SetEntityHeading(ped, GetEntityHeading(ped) + num(data and data.delta, -180, 180, 0))
end)

RegisterNUICallback('sex', function(data, cb)
    if not editor or editor.mode ~= 'create' or type(data) ~= 'table' then return cb({ ok = false }) end
    editor.current = defaultAppearance(data.sex)
    applyAppearance(copy(editor.current))
    snapshotDisplay()
    focusCamera(editor.focus or 'full')
    cb({ ok = true, data = payload() })
end)

--- Strips components the player never touched, so the saved look (and the price) only reflects real changes.
local function submission()
    local a = copy(editor.current)
    local base = Appearance.normalise(copy(editor.original or {}))
    for _, c in ipairs(allowedCategories(editor.mode)) do
        if c.kind == 'component' and Appearance.getSlot(base, c).d == nil
            and Appearance.sameSlot(Appearance.getSlot(a, c), editor.display[c.key]) then
            for i = #a.components, 1, -1 do if a.components[i].id == c.id then table.remove(a.components, i) end end
        end
    end
    return a
end

RegisterNUICallback('finish', function(_, cb)
    if not editor or (editor.mode ~= 'create' and editor.mode ~= 'admin') then return cb({ ok = false }) end
    local res = Veyl.Callback('veyl_appearance', 'save', editor.current)
    reply(cb, res)
    if res.ok then
        editor.saved = true
        Veyl.Notify('Appearance saved', 'success')
        screen:close('saved')
    end
end)

RegisterNUICallback('checkout', function(data, cb)
    if not editor or not editor.store or type(data) ~= 'table' then return cb({ ok = false, code = 'INVALID_INPUT' }) end
    local res = Veyl.CallbackTimeout('veyl_appearance', 'checkout', 20000, {
        store = editor.store, index = editor.index, appearance = submission(),
        method = data.method == 'bank' and 'bank' or 'cash', opId = tostring(data.opId or ''), expectedTotal = tonumber(data.expectedTotal),
    })
    if res.ok then
        -- The new look is now saved: it becomes the baseline for prices and Reset, and survives closing the editor.
        editor.current = Appearance.normalise(copy(res.data.appearance))
        editor.original = copy(editor.current)
        applyToPed(PlayerPedId(), editor.current)
        snapshotDisplay()
        editor.storeInfo.balances = res.data.balances
        res.data = payload()
    end
    reply(cb, res)
end)

RegisterNUICallback('saveOutfit', function(data, cb)
    if not editor or editor.store ~= 'clothing' then return cb({ ok = false }) end
    local res = Veyl.Callback('veyl_appearance', 'saveOutfit', editor.index, tostring(data and data.name or ''):sub(1, 32))
    if res.ok then editor.outfits = res.data end
    reply(cb, res)
end)

RegisterNUICallback('deleteOutfit', function(data, cb)
    if not editor or editor.store ~= 'clothing' then return cb({ ok = false }) end
    local res = Veyl.Callback('veyl_appearance', 'deleteOutfit', tonumber(data and data.id))
    if res.ok then editor.outfits = res.data end
    reply(cb, res)
end)

--- Wear a saved outfit: applies its slots in the editor. Paying is still needed, but outfit pieces cost nothing.
RegisterNUICallback('wearOutfit', function(data, cb)
    if not editor or editor.store ~= 'clothing' then return cb({ ok = false }) end
    local outfit
    for _, o in ipairs(editor.outfits or {}) do if o.id == tonumber(data and data.id) then outfit = o end end
    if not outfit then return cb({ ok = false, code = 'NOT_FOUND', message = 'Outfit not found' }) end
    for key, slot in pairs(outfit.slots) do
        local cat = Appearance.byKey[key]
        if cat and (cat.kind == 'component' or cat.kind == 'prop') and slot.d ~= nil then Appearance.setSlot(editor.current, cat, slot) end
    end
    applyToPed(PlayerPedId(), editor.current)
    cb({ ok = true, data = payload() })
end)

---------------------------------------------------------------------------
-- Stores: target zones and blips
---------------------------------------------------------------------------
AddEventHandler('veyl_appearance:openStore', function(args)
    if type(args) == 'table' then CreateThread(function() openStore(args.store, args.index) end) end
end)

CreateThread(function()
    for storeType, s in pairs(AppearanceConfig.Stores) do
        for _, c in ipairs(s.locations) do
            local blip = AddBlipForCoord(c.x, c.y, c.z)
            SetBlipSprite(blip, s.blip.sprite)
            SetBlipColour(blip, s.blip.colour)
            SetBlipScale(blip, s.blip.scale or 0.7)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(s.label)
            EndTextCommandSetBlipName(blip)
        end
    end
    while GetResourceState('veyl_interact') ~= 'started' do Wait(200) end
    for storeType, s in pairs(AppearanceConfig.Stores) do
        for i, c in ipairs(s.locations) do
            exports.veyl_interact:AddZone({
                id = ('appearance_%s_%d'):format(storeType, i), coords = c, radius = s.radius, icon = s.icon, title = s.label,
                label = s.option, event = 'veyl_appearance:openStore', args = { store = storeType, index = i },
            })
        end
    end
end)

RegisterCommand('appearance', function()
    if not Veyl.IsLoaded() or editor then return end
    CreateThread(function()
        local res = Veyl.Callback('veyl_appearance', 'canEditFree')
        if not (res.ok and res.data and res.data.allowed) then
            return Veyl.Notify('Visit a clothing store or barber to change your look', 'info')
        end
        exports.veyl_appearance:OpenEditor(nil, true, function() end)
    end)
end, false)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() or not editor then return end
    RenderScriptCams(false, false, 0, true, true)
    if editor.cam then DestroyCam(editor.cam, false) end
    FreezeEntityPosition(PlayerPedId(), false)
end)

-- The inventory put a hat, glasses or mask on or took it off: show it straight away (the server already saved it).
RegisterNetEvent('veyl_appearance:worn', function(key, d, t)
    local cat = Appearance.byKey[key]
    if not cat or type(d) ~= 'number' then return end
    local ped = PlayerPedId()
    if cat.kind == 'prop' then
        if d < 0 then ClearPedProp(ped, cat.id) else SetPedPropIndex(ped, cat.id, d, t or 0, true) end
    elseif cat.kind == 'component' then
        SetPedComponentVariation(ped, cat.id, d, t or 0, 0)
    end
end)
