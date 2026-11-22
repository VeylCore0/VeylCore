-- veyl_customs client: shop points, the preview session (a local copy of the car, so unpaid changes never touch the real
-- vehicle), camera, lighting preview, photo mode, mechanic work at the vehicle and the NUI bridge.

local C, Cat = CustomsConfig, CustomsCatalog
local function cb(name, ...) return Veyl.CallbackTimeout('veyl_customs', name, 15000, ...) end

local view = nil      -- 'customize' | 'dashboard' | 'approval'
local session = nil   -- { id, data, clone, real, snapshot, state, cam, frame... }
local screen = vlib.createScreen({ name = 'customs', closeOnDeath = true, onClose = function(reason) OnScreenClosed(reason) end })

local function shopById(id) for _, s in ipairs(C.Shops) do if s.id == id then return s end end end
local function shopAt(pos)
    for _, s in ipairs(C.Shops) do if #(pos - s.coords) <= s.radius then return s end end
end
local function myJob() local pd = Veyl.PlayerData return pd and pd.job or {} end
local function isStaff(shop) local pd = Veyl.PlayerData return shop.job and pd and pd.jobs and pd.jobs[shop.job] ~= nil end

---------------------------------------------------------------------------
-- Catalogue for this vehicle (asks the game what the model supports)
---------------------------------------------------------------------------
local function modLabel(veh, slot, i)
    local lbl = GetModTextLabel(veh, slot, i)
    local txt = lbl and lbl ~= '' and GetLabelText(lbl) or nil
    if not txt or txt == 'NULL' or txt == '' then return ('Option %d'):format(i + 1) end
    return txt
end

local function enumerate(veh, shop)
    SetVehicleModKit(veh, 0)
    local bike = GetVehicleClass(veh) == 8
    local cats, opts = {}, {}
    for _, o in ipairs(Cat.Options) do
        local show = shop.categories[o.cat] and not (bike and o.carOnly) and not (not bike and o.bikeOnly)
        local entry
        if show then
            if o.kind == 'mod' then
                local n = GetNumVehicleMods(veh, o.slot)
                if o.cat == 'performance' and C.Performance[o.slot] then n = math.min(n, C.Performance[o.slot] + 1) end
                if n > 0 then
                    local values = { { value = -1, label = o.cat == 'performance' and 'Stock' or 'Factory' } }
                    for i = 0, n - 1 do values[#values + 1] = { value = i, label = o.cat == 'performance' and (Cat.PerfLevelNames[i] or ('Level %d'):format(i + 1)) or modLabel(veh, o.slot, i) } end
                    entry = { values = values }
                end
            elseif o.kind == 'livery' then
                local n = GetVehicleLiveryCount(veh)
                if n and n > 0 then
                    local values = {}
                    for i = 0, n - 1 do
                        local l = GetLabelText(GetLiveryName(veh, i) or '')
                        values[#values + 1] = { value = i, label = (l and l ~= 'NULL' and l ~= '') and l or ('Livery %d'):format(i + 1) }
                    end
                    entry = { values = values }
                end
            elseif o.kind == 'toggle' then entry = { toggle = true }
            elseif o.key == 'wheelType' then
                local values = {}
                for i = 0, 12 do if (bike and i == 6) or (not bike and i ~= 6) then values[#values + 1] = { value = i, label = Cat.WheelTypes[i] } end end
                entry = { values = values }
            elseif o.key == 'windowTint' then
                local values = {} for i = 0, 6 do values[#values + 1] = { value = i, label = Cat.WindowTints[i] } end entry = { values = values }
            elseif o.key == 'plateIndex' then
                local values = {} for i = 0, 5 do values[#values + 1] = { value = i, label = Cat.PlateStyles[i] } end entry = { values = values }
            elseif o.key == 'xenonColor' then
                local values = {} for i = -1, 12 do values[#values + 1] = { value = i, label = Cat.XenonColors[i] } end entry = { values = values }
            elseif o.kind == 'index' or o.kind == 'rgb' or o.kind == 'paint' or o.kind == 'neon' then
                entry = { kind = o.kind } -- colour pickers / neon sides handled by the page
            end
        end
        if entry then
            entry.key, entry.label, entry.cat, entry.kind, entry.camera = o.key, o.label, o.cat, o.kind, o.camera
            opts[#opts + 1] = entry
            cats[o.cat] = true
        end
    end
    for n = 1, 14 do
        if shop.categories.details and DoesExtraExist(veh, n) then
            opts[#opts + 1] = { key = 'extra:' .. n, label = ('Extra %d'):format(n), cat = 'details', kind = 'extra', toggle = true, camera = 'side34' }
            cats.details = true
        end
    end
    local list = {}
    for _, c in ipairs(Cat.Categories) do if cats[c.id] then list[#list + 1] = { id = c.id, label = c.label } end end
    return list, opts, bike
end

---------------------------------------------------------------------------
-- Camera
---------------------------------------------------------------------------
local FRAMES = {
    front = { yaw = 0, pitch = 8, dist = 5.8 }, front34 = { yaw = 38, pitch = 10, dist = 6.2 }, side = { yaw = 90, pitch = 6, dist = 5.6 },
    side34 = { yaw = 130, pitch = 10, dist = 6.4 }, rear = { yaw = 180, pitch = 8, dist = 5.6 }, rear34 = { yaw = 215, pitch = 12, dist = 6.2 },
    wheel = { yaw = 72, pitch = 2, dist = 3.0, ty = 1.2, tz = -0.3 }, wheelRear = { yaw = 100, pitch = 2, dist = 3.0, ty = -1.2, tz = -0.3 },
    engine = { yaw = 0, pitch = 38, dist = 4.2, ty = 1.4 }, top = { yaw = 30, pitch = 55, dist = 7.0 },
    interior = { yaw = 200, pitch = 0, dist = 0.9, tx = -0.35, ty = 0.15, tz = 0.45, inside = true },
}

local function camTick()
    local s = session
    if not s or not s.cam or not DoesEntityExist(s.clone) then return end
    local f = s.frame
    -- Smoothly follow the target values (no motion when the player prefers reduced motion).
    local k = s.reduced and 1.0 or 0.18
    s.yaw = s.yaw + (f.yaw - s.yaw) * k
    s.pitch = s.pitch + (f.pitch - s.pitch) * k
    s.dist = s.dist + (f.dist - s.dist) * k
    local yaw, pitch = math.rad(s.yaw), math.rad(s.pitch)
    local tx, ty, tz = f.tx or 0.0, f.ty or 0.0, (f.tz or 0.0) + 0.3
    local center = GetOffsetFromEntityInWorldCoords(s.clone, tx, ty, tz)
    local pos = GetOffsetFromEntityInWorldCoords(s.clone, tx + math.sin(yaw) * s.dist * math.cos(pitch), ty + math.cos(yaw) * s.dist * math.cos(pitch), tz + math.sin(pitch) * s.dist)
    if not f.inside then
        -- Keep the camera out of walls: pull it in front of the first thing between the car and the camera.
        local ray = StartExpensiveSynchronousShapeTestLosProbe(center.x, center.y, center.z, pos.x, pos.y, pos.z, 1 + 16, s.clone, 7)
        local _, hit, hitPos = GetShapeTestResult(ray)
        if hit == 1 then pos = center + (hitPos - center) * 0.92 end
    end
    SetCamCoord(s.cam, pos.x, pos.y, pos.z)
    PointCamAtCoord(s.cam, center.x, center.y, center.z)
end

local function setFrame(name)
    local s = session
    if not s then return end
    local f = FRAMES[name] or FRAMES.front34
    s.frame = { yaw = f.yaw, pitch = f.pitch, dist = f.dist, tx = f.tx, ty = f.ty, tz = f.tz, inside = f.inside, name = name }
end

---------------------------------------------------------------------------
-- Preview session
---------------------------------------------------------------------------
local function applyState()
    local s = session
    if s and DoesEntityExist(s.clone) then exports.veyl_vehicles:SetVehicleProperties(s.clone, s.compare and s.snapshot or s.state) end
end

local function stateFromCart()
    local s = session
    local p = json.decode(json.encode(s.snapshot))
    for key, v in pairs(s.cart) do Cat.ApplyToProps(p, key, v) end
    s.state = p
end

local function cleanup()
    local s = session
    session = nil
    if not s then return end
    if s.cam then RenderScriptCams(false, true, 400, true, false) DestroyCam(s.cam, false) end
    if s.clone and DoesEntityExist(s.clone) then DeleteEntity(s.clone) end
    if s.lighting and GetResourceState('veyl_world') == 'started' then exports.veyl_world:SetLocalPreview(nil) end
    FreezeEntityPosition(PlayerPedId(), false)
    SetEntityVisible(PlayerPedId(), true, false)
    DisplayRadar(true)
    CreateThread(function() cb('close', s.id) end)
end

function OnScreenClosed()
    if view == 'customize' then cleanup() end
    view = nil
end

local function openSession(shop, veh, mode, orderId)
    if session or screen:isOpen() then return end
    local netId = NetworkGetNetworkIdFromEntity(veh)
    local res = cb('start', shop.id, netId, mode, orderId)
    if not res.ok then return Veyl.NotifyResult(res) end
    local d = res.data
    local model = GetEntityModel(veh)
    RequestModel(model)
    local deadline = GetGameTimer() + 5000
    while not HasModelLoaded(model) and GetGameTimer() < deadline do Wait(20) end
    if not HasModelLoaded(model) then cb('close', d.session) return Veyl.Notify('Could not load the vehicle model', 'error') end
    local p = shop.preview
    local clone = CreateVehicle(model, p.x, p.y, p.z, p.w, false, false) -- local only: other players never see it
    SetModelAsNoLongerNeeded(model)
    SetEntityAsMissionEntity(clone, true, true)
    SetVehicleOnGroundProperly(clone)
    FreezeEntityPosition(clone, true)
    SetVehicleDoorsLocked(clone, 2)
    SetEntityInvincible(clone, true)
    SetVehicleEngineOn(clone, false, true, true)
    SetVehicleLights(clone, 2)
    SetVehicleModKit(clone, 0)
    local snapshot = exports.veyl_vehicles:GetVehicleProperties(veh) or {}
    exports.veyl_vehicles:SetVehicleProperties(clone, snapshot)
    SetVehicleDirtLevel(clone, 0.0)
    local cats, opts, bike = enumerate(clone, shop)
    local cam = CreateCamWithParams('DEFAULT_SCRIPTED_CAMERA', p.x, p.y, p.z + 2.0, 0.0, 0.0, 0.0, 50.0, false, 0)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 500, true, false)
    session = { id = d.session, data = d, shop = shop, real = veh, clone = clone, snapshot = snapshot, cart = {}, cam = cam, yaw = 38, pitch = 10, dist = 6.2,
        model = d.model, bike = bike, reduced = GetResourceKvpInt('veyl_customs:reduced') == 1 }
    setFrame('front34')
    stateFromCart()
    if d.preload then
        for k, v in pairs(d.preload) do session.cart[k] = v end
        stateFromCart()
        applyState()
    end
    if GetVehiclePedIsIn(PlayerPedId(), false) == 0 then FreezeEntityPosition(PlayerPedId(), true) end
    DisplayRadar(false)
    view = 'customize'
    local current = {}
    for _, o in ipairs(opts) do current[o.key] = Cat.FromProps(snapshot, o.key) end
    local swatches = cb('swatches')
    local ok = screen:open('customs:open', {
        view = 'customize', session = d.session, mode = d.mode, orderId = d.orderId, shop = d.shop, model = d.model,
        vehicleLabel = GetLabelText(GetDisplayNameFromVehicleModel(model)), plate = d.plate, categories = cats, options = opts, current = current,
        preload = d.preload, finishes = Cat.Finishes, presets = C.PaintPresets, swatches = swatches.ok and swatches.data or {}, bike = bike,
        lighting = GetResourceState('veyl_world') == 'started', reduced = session.reduced, maxSwatches = C.MaxSwatches,
    })
    if not ok then cleanup() return Veyl.Notify('Customs UI unavailable', 'error') end
    CreateThread(function()
        while session and session.id == d.session do
            camTick()
            DisableAllControlActions(0)
            -- Pause/cancel on: death, the real vehicle disappearing, the preview copy disappearing.
            if IsEntityDead(PlayerPedId()) or not DoesEntityExist(session.real) or not DoesEntityExist(session.clone) then
                Veyl.Notify('Customisation closed', 'warning')
                screen:close('interrupted')
                break
            end
            Wait(0)
        end
    end)
end

RegisterNetEvent('veyl_customs:sessionClosed', function(reason)
    if session then Veyl.Notify(('Customisation closed (%s)'):format(reason), 'warning') screen:close('server') end
end)

--- The server pushes purchased / installed looks to the entity's network owner.
RegisterNetEvent('veyl_customs:applyProps', function(netId, props)
    if not NetworkDoesNetworkIdExist(netId) then return end
    local veh = NetToVeh(netId)
    local deadline = GetGameTimer() + 3000
    NetworkRequestControlOfEntity(veh)
    while not NetworkHasControlOfEntity(veh) and GetGameTimer() < deadline do Wait(25) NetworkRequestControlOfEntity(veh) end
    exports.veyl_vehicles:SetVehicleProperties(veh, props)
end)

---------------------------------------------------------------------------
-- NUI callbacks (every message carries the session id; stale ones are rejected)
---------------------------------------------------------------------------
local function valid(data) return session and type(data) == 'table' and data.session == session.id end
local function reply(r, res) r({ ok = res.ok, code = res.code, message = res.message, data = res.data }) end

RegisterNUICallback('preview', function(data, r)
    if not valid(data) then return r({ ok = false, code = 'STALE' }) end
    local key = data.key
    if not Cat.ByKey[key] then return r({ ok = false, code = 'INVALID_INPUT' }) end
    if data.temp then
        -- Temporary preview (e.g. dragging the paint picker): shown on the copy only, not added to the build.
        local v = data.value ~= nil and Cat.Clean(key, data.value)
        if v == nil or v == false and Cat.ByKey[key].kind ~= 'toggle' then applyState() return r({ ok = true }) end
        local p = json.decode(json.encode(session.state))
        Cat.ApplyToProps(p, key, v)
        if DoesEntityExist(session.clone) then exports.veyl_vehicles:SetVehicleProperties(session.clone, p) end
        return r({ ok = true })
    end
    if data.value == nil or data.remove then session.cart[key] = nil
    else
        local v = Cat.Clean(key, data.value)
        if v == nil then return r({ ok = false, code = 'INVALID_INPUT' }) end
        -- Choosing the vehicle's current value removes the line.
        if Cat.Same(v, Cat.FromProps(session.snapshot, key)) then session.cart[key] = nil else session.cart[key] = v end
    end
    stateFromCart()
    applyState()
    local extra
    if key == 'wheelType' then
        -- Wheel lists depend on the wheel type: send the new counts.
        local n = GetNumVehicleMods(session.clone, 23)
        local values = { { value = -1, label = 'Factory' } }
        for i = 0, n - 1 do values[#values + 1] = { value = i, label = modLabel(session.clone, 23, i) } end
        extra = { wheels = values }
    end
    r({ ok = true, data = { cart = session.cart, extra = extra } })
end)

RegisterNUICallback('resetCart', function(data, r)
    if not valid(data) then return r({ ok = false }) end
    session.cart = {}
    stateFromCart()
    applyState()
    r({ ok = true, data = { cart = session.cart } })
end)

RegisterNUICallback('loadCart', function(data, r)
    if not valid(data) or type(data.cart) ~= 'table' then return r({ ok = false }) end
    session.cart = {}
    for k, v in pairs(data.cart) do
        local c = Cat.ByKey[k] and Cat.Clean(k, v)
        if c ~= nil and not Cat.Same(c, Cat.FromProps(session.snapshot, k)) then session.cart[k] = c end
    end
    stateFromCart()
    applyState()
    r({ ok = true, data = { cart = session.cart } })
end)

RegisterNUICallback('compare', function(data, r)
    if not valid(data) then return r({ ok = false }) end
    session.compare = data.on == true
    applyState()
    r({ ok = true })
end)

RegisterNUICallback('camera', function(data, r)
    if not valid(data) then return r({ ok = false }) end
    local s = session
    if data.frame then setFrame(data.frame) end
    if data.dx then s.frame.yaw = s.frame.yaw - (tonumber(data.dx) or 0) * 0.35 end
    if data.dy then s.frame.pitch = math.max(-5.0, math.min(60.0, s.frame.pitch + (tonumber(data.dy) or 0) * 0.25)) end
    if data.zoom then
        local lo, hi = s.frame.inside and 0.5 or 2.5, s.frame.inside and 2.0 or 10.0
        s.frame.dist = math.max(lo, math.min(hi, s.frame.dist + (tonumber(data.zoom) or 0) * 0.004))
    end
    if data.reset then setFrame(s.frame.name or 'front34') end
    r({ ok = true })
end)

RegisterNUICallback('lighting', function(data, r)
    if not valid(data) then return r({ ok = false }) end
    if GetResourceState('veyl_world') ~= 'started' then return r({ ok = false, message = 'Lighting preview needs veyl_world' }) end
    local preset = data.mode and C.Lighting[data.mode]
    exports.veyl_world:SetLocalPreview(preset)
    session.lighting = preset ~= nil
    r({ ok = true })
end)

RegisterNUICallback('reducedMotion', function(data, r)
    if session then session.reduced = data.on == true end
    SetResourceKvpInt('veyl_customs:reduced', data.on == true and 1 or 0)
    r({ ok = true })
end)

-- Photo mode: hide the page until any key is pressed (camera keeps working with the mouse wheel).
RegisterNUICallback('photo', function(data, r)
    if not valid(data) then return r({ ok = false }) end
    r({ ok = true })
    SetNuiFocus(false, false)
    screen:send('customs:photo', { on = true })
    CreateThread(function()
        Wait(300)
        while session do
            DisableAllControlActions(0)
            if IsDisabledControlJustPressed(0, 15) then session.frame.dist = math.max(2.5, session.frame.dist - 0.4) end
            if IsDisabledControlJustPressed(0, 14) then session.frame.dist = math.min(10.0, session.frame.dist + 0.4) end
            local mx = GetDisabledControlNormal(0, 1)
            if math.abs(mx) > 0.001 then session.frame.yaw = session.frame.yaw - mx * 40.0 end
            if IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 38) or IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 24) then break end
            Wait(0)
        end
        if session then SetNuiFocus(true, true) screen:send('customs:photo', { on = false }) end
    end)
end)

-- Server pass-through (the server re-checks everything). Whitelisted names only.
local PASS = { price = true, rowPrices = true, quote = true, checkout = true, saveOrder = true, builds = true, buildSave = true, buildDelete = true,
    buildDuplicate = true, buildImport = true, swatches = true, dashboard = true, orderAction = true, partsOrder = true, partsThreshold = true,
    pricing = true, approve = true, reject = true, myQuotes = true }
RegisterNUICallback('api', function(data, r)
    if type(data) ~= 'table' or not PASS[data.name] then return r({ ok = false, code = 'INVALID_INPUT' }) end
    local args = type(data.args) == 'table' and data.args or {}
    CreateThread(function()
        local res = cb(data.name, table.unpack(args, 1, 5))
        if data.name == 'checkout' and res.ok and session then
            session.snapshot = res.data.props or session.state
            session.cart = {}
            stateFromCart()
        end
        reply(r, res)
    end)
end)

RegisterNUICallback('closeUi', function(_, r) r({ ok = true }) screen:close('player') end)

-- Dashboard actions that need the world: open a quote session on an order's / nearby vehicle.
local function vehicleInShop(shop, plate)
    local best, bd = nil, shop.radius
    local pc = GetEntityCoords(PlayerPedId())
    for _, v in ipairs(GetGamePool('CVehicle')) do
        if #(GetEntityCoords(v) - shop.coords) <= shop.radius then
            local p = GetVehicleNumberPlateText(v):gsub('^%s+', ''):gsub('%s+$', '')
            if plate and p == plate then return v end
            if not plate then local d = #(GetEntityCoords(v) - pc) if d < bd then best, bd = v, d end end
        end
    end
    return best
end

RegisterNUICallback('editOrder', function(data, r)
    r({ ok = true })
    local shop = type(data) == 'table' and shopById(data.shop)
    if not shop then return end
    screen:close('switch')
    CreateThread(function()
        Wait(250)
        local veh = vehicleInShop(shop, data.plate)
        if not veh then return Veyl.Notify(data.plate and 'That vehicle is not in the shop' or 'No vehicle in the shop', 'error') end
        openSession(shop, veh, 'quote', data.orderId)
    end)
end)

---------------------------------------------------------------------------
-- Dashboard and customer approval
---------------------------------------------------------------------------
local function openDashboard(shop)
    if screen:isOpen() then return end
    local res = cb('dashboard', shop.id)
    if not res.ok then return Veyl.NotifyResult(res) end
    view = 'dashboard'
    if not screen:open('customs:open', { view = 'dashboard', shopId = shop.id, data = res.data, reduced = GetResourceKvpInt('veyl_customs:reduced') == 1 }) then view = nil end
end

local function openApproval()
    if screen:isOpen() then return end
    local res = cb('myQuotes')
    if not res.ok then return Veyl.NotifyResult(res) end
    if #res.data.quotes == 0 then return Veyl.Notify('No quotes waiting for you', 'info') end
    view = 'approval'
    if not screen:open('customs:open', { view = 'approval', data = res.data }) then view = nil end
end

RegisterNetEvent('veyl_customs:quoteReceived', function(orderId)
    Veyl.Notify(('A mechanic sent you a quote (#%d). Type /customsquote to review it.'):format(orderId), 'info', 8000)
end)
RegisterCommand('customsquote', function() CreateThread(openApproval) end, false)

---------------------------------------------------------------------------
-- Work at the vehicle (mechanic installs approved items)
---------------------------------------------------------------------------
local ANIMS = {
    performance = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 1 }, bodywork = { scenario = 'WORLD_HUMAN_WELDING' },
    wheels = { scenario = 'CODE_HUMAN_MEDIC_KNEEL' }, paint = { scenario = 'WORLD_HUMAN_MAID_CLEAN' },
    lighting = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 1 }, details = { scenario = 'PROP_HUMAN_BUM_BIN' },
}

local function workMenu(veh)
    local res = cb('workAt', NetworkGetNetworkIdFromEntity(veh))
    if not res.ok then return Veyl.NotifyResult(res) end
    local o = res.data
    if not o then return Veyl.Notify('No work order in progress for this vehicle', 'info') end
    local items = {}
    for _, l in ipairs(o.lines) do
        items[#items + 1] = { label = l.label, value = tostring(l.id), disabled = l.installed, right = l.installed and 'Installed' or ('%ds'):format(C.InstallSeconds[l.cat] or 6) }
    end
    local pick = Veyl.UI.Menu({ title = ('Order #%d · %s'):format(o.id, o.plate), subtitle = 'Install approved items', items = items })
    if not pick then return end
    local start = cb('installStart', o.id, tonumber(pick))
    if not start.ok then return Veyl.NotifyResult(start) end
    local cat
    for _, l in ipairs(o.lines) do if tostring(l.id) == pick then cat = l.cat end end
    local a = ANIMS[cat] or ANIMS.details
    local ped = PlayerPedId()
    TaskTurnPedToFaceEntity(ped, veh, 800)
    Wait(800)
    if a.scenario then TaskStartScenarioInPlace(ped, a.scenario, 0, true) end
    local done = vlib.progress({ label = ('Installing: %s'):format(start.data.label), duration = start.data.seconds * 1000, canCancel = true,
        disable = { move = true, car = true, combat = true }, anim = a.dict and { dict = a.dict, clip = a.clip, flag = a.flag } or nil })
    ClearPedTasks(ped)
    if not done then return Veyl.Notify('Stopped', 'info') end
    Veyl.NotifyResult(cb('installFinish', start.data.token))
end

---------------------------------------------------------------------------
-- World points
---------------------------------------------------------------------------
AddEventHandler('veyl_customs:self', function(a)
    local shop = shopById(a.shop)
    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
    if veh == 0 or GetPedInVehicleSeat(veh, -1) ~= PlayerPedId() then return Veyl.Notify('Drive your vehicle in', 'error') end
    CreateThread(function() openSession(shop, veh, 'self') end)
end)
AddEventHandler('veyl_customs:dashboard', function(a) CreateThread(function() openDashboard(shopById(a.shop)) end) end)
AddEventHandler('veyl_customs:quotes', function() CreateThread(openApproval) end)
AddEventHandler('veyl_customs:request', function(a)
    CreateThread(function()
        local shop = shopById(a.shop)
        local veh = vehicleInShop(shop)
        if not veh then return Veyl.Notify('Bring your vehicle into the shop first', 'error') end
        local v = vlib.inputDialog('Request service', { { name = 'note', label = 'What would you like done?', type = 'text', required = true, maxLength = 200 } }, { submitLabel = 'Send request' })
        if v then Veyl.NotifyResult(cb('request', shop.id, NetworkGetNetworkIdFromEntity(veh), v.note)) end
    end)
end)

CreateThread(function()
    while GetResourceState('veyl_interact') ~= 'started' do Wait(250) end
    for _, s in ipairs(C.Shops) do
        if s.mode ~= 'mechanic' or s.selfFallback then
            exports.veyl_interact:AddZone({ id = 'veyl_customs_self_' .. s.id, coords = s.entry, radius = 4.0, title = s.label,
                options = { { label = 'Customise vehicle', icon = 'wrench', event = 'veyl_customs:self', args = { shop = s.id },
                    canInteract = function() return GetVehiclePedIsIn(PlayerPedId(), false) ~= 0 end } } })
        end
        if s.desk then
            exports.veyl_interact:AddZone({ id = 'veyl_customs_desk_' .. s.id, coords = s.desk, radius = 1.8, title = s.label,
                options = {
                    { label = 'Workshop dashboard', icon = 'briefcase', event = 'veyl_customs:dashboard', args = { shop = s.id }, groups = s.job and { [s.job] = 0 } or nil },
                    { label = 'Request service', icon = 'wrench', event = 'veyl_customs:request', args = { shop = s.id } },
                    { label = 'My quotes', icon = 'receipt', event = 'veyl_customs:quotes' },
                } })
        end
        if s.blip then
            local b = AddBlipForCoord(s.coords.x, s.coords.y, s.coords.z)
            SetBlipSprite(b, s.blip.sprite) SetBlipColour(b, s.blip.colour) SetBlipScale(b, 0.75) SetBlipAsShortRange(b, true)
            BeginTextCommandSetBlipName('STRING') AddTextComponentSubstringPlayerName(s.label) EndTextCommandSetBlipName(b)
        end
    end
end)

CreateThread(function()
    while GetResourceState('veyl_target') ~= 'started' do Wait(500) end
    local function staffShopHere(entity)
        local shop = shopAt(GetEntityCoords(entity))
        return shop and shop.mode ~= 'self' and isStaff(shop) and myJob().onduty and shop or nil
    end
    exports.veyl_target:addGlobalVehicle({
        { name = 'veyl_customs_quote', label = 'Write a customs quote', icon = 'receipt', distance = 3.0, priority = 2,
          canInteract = function(entity) return session == nil and staffShopHere(entity) ~= nil end,
          onSelect = function(d) local shop = staffShopHere(d.entity) if shop then CreateThread(function() openSession(shop, d.entity, 'quote') end) end end },
        { name = 'veyl_customs_work', label = 'Install approved work', icon = 'wrench', distance = 3.0, priority = 2,
          canInteract = function(entity) return session == nil and staffShopHere(entity) ~= nil end,
          onSelect = function(d) CreateThread(function() workMenu(d.entity) end) end },
    })
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if session then
        local s = session
        if s.cam then RenderScriptCams(false, false, 0, true, false) DestroyCam(s.cam, false) end
        if DoesEntityExist(s.clone) then DeleteEntity(s.clone) end
        if s.lighting and GetResourceState('veyl_world') == 'started' then exports.veyl_world:SetLocalPreview(nil) end
        FreezeEntityPosition(PlayerPedId(), false)
        DisplayRadar(true)
    end
end)
