-- veyl_apartments client: door locks, door/front-desk interactions, controlled transitions, in-home menu, phone app.

AptClient = { context = nil }
local units = {}          -- every room: { id?, number, building, origin, yaw }
local buildings = {}      -- [id] = { desk = vector3?, deskPed, blip }
local transitioning = false

---------------------------------------------------------------------------
-- Units (client copy of the MLO data) and door locks
---------------------------------------------------------------------------
for bid, b in pairs(AptBuildings) do
    for _, u in ipairs(_G[b.units] or {}) do
        units[#units + 1] = { building = bid, number = u.number, floor = u.floor, origin = u.origin, yaw = u.yaw }
    end
end

local function doorHash(u) return joaat(('veyl_apt_%s_%d'):format(u.building, u.number)) end

--- Every room's real MLO door is locked on every client: rooms are entered only through the server-checked transition.
local function lockDoors()
    local model = joaat(AptGeometry.Door.model)
    for _, u in ipairs(units) do
        local p = AptGeometry.ToWorld(u, AptGeometry.Door.pos)
        local h = doorHash(u)
        if not IsDoorRegisteredWithSystem(h) then AddDoorToSystem(h, model, p.x, p.y, p.z, false, false, false) end
        DoorSystemSetDoorState(h, 1, false, true)
    end
end

---------------------------------------------------------------------------
-- Transitions: fade, place at a verified point once collision is loaded, restore control. Never leaves a black screen.
---------------------------------------------------------------------------
local function groundAt(x, y, z)
    for _ = 1, 20 do
        local ok, gz = GetGroundZFor_3dCoord(x, y, z + 1.0, false)
        if ok and math.abs(gz - (z - 1.0)) < 1.6 then return gz + 1.0 end
        Wait(50)
    end
    return z
end

function AptClient.Teleport(point)
    if transitioning then return false end
    transitioning = true
    local ped = PlayerPedId()
    local ok, err = pcall(function()
        DoScreenFadeOut(350)
        local t = GetGameTimer() + 1500
        while not IsScreenFadedOut() and GetGameTimer() < t do Wait(10) end
        FreezeEntityPosition(ped, true)
        RequestCollisionAtCoord(point.x, point.y, point.z)
        SetEntityCoordsNoOffset(ped, point.x, point.y, point.z, false, false, false)
        SetEntityHeading(ped, point.heading or 0.0)
        local deadline = GetGameTimer() + AptConfig.Entry.CollisionTimeoutMs
        while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < deadline do
            RequestCollisionAtCoord(point.x, point.y, point.z)
            Wait(50)
        end
        local interior = GetInteriorAtCoords(point.x, point.y, point.z)
        if interior ~= 0 then
            local t2 = GetGameTimer() + 3000
            while not IsInteriorReady(interior) and GetGameTimer() < t2 do Wait(25) end
        end
        local z = groundAt(point.x, point.y, point.z)
        SetEntityCoordsNoOffset(ped, point.x, point.y, z, false, false, false)
    end)
    FreezeEntityPosition(PlayerPedId(), false)
    SetPlayerControl(PlayerId(), true, 0)
    DoScreenFadeIn(500)
    transitioning = false
    if not ok then print(('^1[veyl_apartments] transition failed: %s^7'):format(tostring(err))) end
    return ok
end

---------------------------------------------------------------------------
-- Context (inside a home or on a tour)
---------------------------------------------------------------------------
local insideZones = {}
local function clearInside()
    for _, id in ipairs(insideZones) do exports.veyl_interact:Remove(id) end
    insideZones = {}
    if AptFurnitureClient then AptFurnitureClient.Clear() end
    AptUI.Passive('apt:tour', nil)
    AptUI.Passive('apt:revoked', nil)
end

function AptClient.SetContext(ctx)
    clearInside()
    AptClient.context = ctx
    if not ctx then return end
    local unit = nil
    for _, u in ipairs(units) do if u.building == ctx.building and u.number == ctx.number then unit = u end end
    if not unit then return end
    AptClient.context.unit = unit
    local exit = AptGeometry.Stand(unit, AptGeometry.Inside)
    local menu = AptGeometry.Stand(unit, AptGeometry.Menu)
    insideZones[#insideZones + 1] = exports.veyl_interact:AddZone({ id = 'veyl_apt_exit', coords = exit, radius = 1.2, title = ctx.label,
        options = { { label = 'Leave', icon = 'door', event = 'veyl_apartments:leave' } } })
    if ctx.kind == 'home' then
        local opts = {}
        if ctx.perms.storage then opts[#opts + 1] = { label = 'Storage', icon = 'box', event = 'veyl_apartments:storage' } end
        if ctx.perms.wardrobe then opts[#opts + 1] = { label = 'Wardrobe', icon = 'shirt', event = 'veyl_apartments:wardrobe' } end
        if ctx.perms.furniture then opts[#opts + 1] = { label = 'Furniture', icon = 'home', event = 'veyl_apartments:furnitureMenu' } end
        if ctx.role ~= 'guest' then opts[#opts + 1] = { label = 'Home panel', icon = 'key', event = 'veyl_apartments:openPanel' } end
        if #opts > 0 then
            insideZones[#insideZones + 1] = exports.veyl_interact:AddZone({ id = 'veyl_apt_menu', coords = menu, radius = 1.4, title = ctx.label, options = opts })
        end
        if AptFurnitureClient then AptFurnitureClient.Load(unit, ctx.furniture or {}) end
    end
end

RegisterNetEvent('veyl_apartments:context', function(ctx) AptClient.SetContext(ctx) end)
RegisterNetEvent('veyl_apartments:furniture', function(list) if AptFurnitureClient and AptClient.context and AptClient.context.unit then AptFurnitureClient.Load(AptClient.context.unit, list) end end)

RegisterNetEvent('veyl_apartments:forceExit', function(point, message)
    CreateThread(function()
        AptClient.SetContext(nil)
        AptUI.Close('exit')
        AptClient.Teleport(point)
        if message then Veyl.Notify(message, 'info', 7000) end
    end)
end)

RegisterNetEvent('veyl_apartments:revoked', function(seconds)
    if AptClient.context then AptClient.context.perms = { enter = true } end
    AptUI.Close('revoked')
    AptUI.Passive('apt:revoked', { seconds = seconds })
    Veyl.Notify(seconds and ('Your access to this home ended. You will be walked out in %d seconds.'):format(seconds)
        or 'Your access to this home ended. Please leave.', 'warning', 9000)
end)

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
local function enterUnit(unitId)
    if transitioning or AptClient.context then return end
    if IsPedInAnyVehicle(PlayerPedId(), false) then return Veyl.Notify('Get out of the vehicle first', 'error') end
    local res = Veyl.CallbackTimeout('veyl_apartments', 'enter', 15000, unitId)
    if not res.ok then return Veyl.NotifyResult(res) end
    AptClient.Teleport(res.data.point)
    AptClient.SetContext(res.data.context)
end

local function leave()
    if transitioning or not AptClient.context then return end
    local res = Veyl.CallbackTimeout('veyl_apartments', 'exit', 15000)
    AptClient.SetContext(nil)
    if not res.ok then
        -- Never trapped: fall back to the emergency exit.
        res = Veyl.CallbackTimeout('veyl_apartments', 'stuck', 15000)
        if not res.ok then return Veyl.NotifyResult(res) end
    end
    AptClient.Teleport(res.data.point)
end

AddEventHandler('veyl_apartments:leave', function() CreateThread(leave) end)
RegisterCommand('aptstuck', function()
    CreateThread(function()
        local res = Veyl.CallbackTimeout('veyl_apartments', 'stuck', 15000)
        if not res.ok then return Veyl.NotifyResult(res) end
        AptClient.SetContext(nil)
        AptClient.Teleport(res.data.point)
    end)
end, false)

--- Unit ids come from the server (stable DB ids); door options carry building + number.
local unitIds = {}
local function unitId(building, number)
    local key = building .. ':' .. number
    if unitIds[key] then return unitIds[key] end
    local res = Veyl.Callback('veyl_apartments', 'unitIds')
    if res.ok then for k, v in pairs(res.data) do unitIds[k] = v end end
    return unitIds[key]
end
AptClient.UnitId = unitId

AddEventHandler('veyl_apartments:door', function(args)
    if type(args) ~= 'table' then return end
    CreateThread(function()
        local id = args.unitId or unitId(args.building, args.number)
        if not id then return Veyl.Notify('This door is unavailable right now', 'error') end
        if args.action == 'ring' then
            Veyl.NotifyResult(Veyl.CallbackTimeout('veyl_apartments', 'ringDoor', 10000, id))
        else
            enterUnit(id)
        end
    end)
end)

AddEventHandler('veyl_apartments:tour', function(unitId)
    CreateThread(function()
        local res = Veyl.CallbackTimeout('veyl_apartments', 'tour', 15000, unitId)
        if not res.ok then return Veyl.NotifyResult(res) end
        AptClient.Teleport(res.data.point)
        AptClient.SetContext(res.data.context)
        AptUI.Passive('apt:tour', { seconds = res.data.seconds, label = res.data.context.label })
        Veyl.Notify('Take a look around. Use the door to leave.', 'info', 6000)
    end)
end)

AddEventHandler('veyl_apartments:storage', function()
    CreateThread(function()
        local res = Veyl.Callback('veyl_apartments', 'storageList')
        if not res.ok then return Veyl.NotifyResult(res) end
        if #res.data == 1 then return TriggerEvent('veyl_apartments:openStash', res.data[1].id) end
        if #res.data == 0 then return Veyl.Notify('You cannot use the storage here', 'error') end
        local options = {}
        for i, s in ipairs(res.data) do options[i] = { id = s.id, label = s.label, icon = 'box' } end
        vlib.registerMenu({ id = 'veyl_apt_storage', title = 'Storage', options = options }, function(id) TriggerEvent('veyl_apartments:openStash', id) end)
        vlib.showMenu('veyl_apt_storage')
    end)
end)

RegisterNetEvent('veyl_apartments:openStash', function(id)
    exports.veyl_inventory:openInventory('stash', id)
end)

AddEventHandler('veyl_apartments:wardrobe', function()
    CreateThread(function()
        local res = Veyl.Callback('veyl_apartments', 'wardrobe')
        if not res.ok then return Veyl.NotifyResult(res) end
        AptUI.Open('wardrobe', res.data)
    end)
end)

local function openPanel()
    if not Veyl.IsLoaded() then return end
    local res = Veyl.Callback('veyl_apartments', 'dashboard')
    if not res.ok then return Veyl.NotifyResult(res) end
    AptUI.Open('dashboard', res.data)
end
AddEventHandler('veyl_apartments:openPanel', function() CreateThread(openPanel) end)
RegisterCommand('apartment', function() CreateThread(openPanel) end, false)

AddEventHandler('veyl_apartments:desk', function(args)
    if type(args) ~= 'table' then return end
    CreateThread(function()
        if args.view == 'lease' then
            local res = Veyl.Callback('veyl_apartments', 'catalog', args.building)
            if not res.ok then return Veyl.NotifyResult(res) end
            AptUI.Open('leasing', res.data)
        else
            AptUI.Open('desk', { building = args.building, label = AptBuildings[args.building].label, tab = args.view,
                directory = AptBuildings[args.building].directory })
        end
    end)
end)

---------------------------------------------------------------------------
-- Visitors
---------------------------------------------------------------------------
RegisterNetEvent('veyl_apartments:visitRequest', function(req)
    PlaySoundFrontend(-1, 'Text_Arrive_Tone', 'Phone_SoundSet_Default', true)
    AptUI.Doorbell(req)
end)

RegisterNetEvent('veyl_apartments:visitAnswer', function(ans)
    if ans.allowed then
        Veyl.Notify(('You were let in. Go to Room %d (floor %d) within %d minutes.'):format(ans.number, ans.floor, ans.minutes), 'success', 10000)
        if ans.door then SetNewWaypoint(ans.door.x, ans.door.y) end
    else
        Veyl.Notify('No one answered.', 'info')
    end
end)

---------------------------------------------------------------------------
-- World setup: blips, front desks (ground found in game), door interactions
---------------------------------------------------------------------------
local function deskPoint(bid)
    local sx, sy, n, z = 0, 0, 0, nil
    for _, u in ipairs(units) do
        if u.building == bid and u.floor == 1 then
            local p = AptGeometry.ToWorld(u, AptGeometry.Outside)
            sx, sy, n = sx + p.x, sy + p.y, n + 1
            z = u.origin.z + AptGeometry.FloorZ + 1.0
        end
    end
    if n == 0 then return nil end
    return vector3(sx / n, sy / n, z)
end

local function setupDesk(bid, b, point)
    local z = point.z
    local found, gz = GetGroundZFor_3dCoord(point.x, point.y, point.z + 2.0, false)
    if found then z = gz + 1.0 end
    local coords = vector3(point.x, point.y, z)
    local heading = 0.0
    local opts = {
        { label = 'Rent a room', icon = 'key', event = 'veyl_apartments:desk', args = { building = bid, view = 'lease' } },
        { label = 'Parcels & storage', icon = 'box', event = 'veyl_apartments:desk', args = { building = bid, view = 'parcels' } },
        { label = 'Noticeboard', icon = 'note', event = 'veyl_apartments:desk', args = { building = bid, view = 'notices' } },
        { label = 'My home', icon = 'home', event = 'veyl_apartments:openPanel' },
    }
    if b.directory then table.insert(opts, 2, { label = 'Visit a resident', icon = 'users', event = 'veyl_apartments:desk', args = { building = bid, view = 'directory' } }) end
    exports.veyl_interact:AddPed({ id = 'veyl_apt_desk_' .. bid, model = b.frontDesk.model or 'a_f_y_business_02',
        coords = vector4(coords.x, coords.y, coords.z, heading), scenario = 'WORLD_HUMAN_CLIPBOARD', radius = 2.5,
        title = b.label .. ' front desk', options = opts })
    buildings[bid].desk = coords
end

CreateThread(function()
    while GetResourceState('veyl_interact') ~= 'started' do Wait(250) end
    lockDoors()
    for bid, b in pairs(AptBuildings) do
        buildings[bid] = {}
        local p = deskPoint(bid)
        if p and b.blip then
            local blip = AddBlipForCoord(p.x, p.y, p.z)
            SetBlipSprite(blip, b.blip.sprite)
            SetBlipColour(blip, b.blip.colour)
            SetBlipScale(blip, b.blip.scale or 0.75)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(b.label)
            EndTextCommandSetBlipName(blip)
            buildings[bid].blip = blip
        end
        buildings[bid].pending = p
    end
    for _, u in ipairs(units) do
        exports.veyl_interact:AddZone({
            id = ('veyl_apt_door_%s_%d'):format(u.building, u.number), coords = AptGeometry.Stand(u, AptGeometry.Outside), radius = 1.3,
            title = ('Room %d'):format(u.number),
            options = {
                { label = 'Enter', icon = 'door', event = 'veyl_apartments:door', args = { action = 'enter', building = u.building, number = u.number } },
                { label = 'Knock', icon = 'bell', event = 'veyl_apartments:door', args = { action = 'ring', building = u.building, number = u.number } },
            },
        })
    end
    -- Desks are placed once the player is close enough for the courtyard's collision to exist (ground probe).
    while true do
        local pos = GetEntityCoords(PlayerPedId())
        for bid, b in pairs(AptBuildings) do
            local pending = buildings[bid].pending
            if pending and not buildings[bid].desk and #(vector2(pos.x, pos.y) - vector2(pending.x, pending.y)) < 120.0 then
                RequestCollisionAtCoord(pending.x, pending.y, pending.z)
                if HasCollisionLoadedAroundEntity(PlayerPedId()) then setupDesk(bid, b, pending) end
            end
        end
        Wait(2000)
    end
end)

---------------------------------------------------------------------------
-- Phone app (veyl_phone RegisterApp): opens the same resident panel
---------------------------------------------------------------------------
local function registerPhoneApp()
    if GetResourceState('veyl_phone') ~= 'started' then return end
    pcall(function()
        exports.veyl_phone:RegisterApp({ id = 'apartments', label = 'Apartments', icon = 'home', color = '#8b63d6', event = 'veyl_apartments:openPanel' })
    end)
end
AddEventHandler('onClientResourceStart', function(res)
    if res == 'veyl_phone' or res == GetCurrentResourceName() then registerPhoneApp() end
end)

---------------------------------------------------------------------------
-- Cleanup
---------------------------------------------------------------------------
RegisterNetEvent('VeylCore:Client:OnPlayerUnload', function() AptClient.SetContext(nil) end)
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if transitioning or IsScreenFadedOut() or IsScreenFadingOut() then DoScreenFadeIn(300) end
    FreezeEntityPosition(PlayerPedId(), false)
    clearInside()
    for _, b in pairs(buildings) do if b.blip then RemoveBlip(b.blip) end end
end)
