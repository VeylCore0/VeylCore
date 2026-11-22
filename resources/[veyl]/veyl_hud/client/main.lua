-- veyl_hud client: collects game and framework state and sends only CHANGED sections to the NUI.
-- Rates: vehicle instruments 100 ms (only while in a vehicle), voice 200 ms, location 300 ms, status / money 500 ms,
-- layout on change. Nothing is sent while the HUD is hidden.

local uiReady, last = false, {}
local menuOpen, focusToken = false, nil
local layoutDirty = true

---------------------------------------------------------------------------
-- Sending (diffed per section)
---------------------------------------------------------------------------
local function sig(v) local ok, s = pcall(json.encode, v) return ok and s or tostring(v) end

local function push(sections)
    if not uiReady then return end
    local changed, any = {}, false
    for k, v in pairs(sections) do
        local s = sig(v)
        if last[k] ~= s then last[k] = s changed[k] = v any = true end
    end
    if any then SendNUIMessage({ action = 'hud:frame', data = changed }) end
end

local function caps()
    return { circle = Minimap.circleAvailable, postal = Bridge.Postal.Available(), fuel = Bridge.Fuel.provider,
        voice = Bridge.Voice.provider, seatbelt = HudConfig.Seatbelt ~= 'none' }
end

local function sendSettings()
    if uiReady then SendNUIMessage({ action = 'hud:settings', data = { settings = Settings.current, caps = caps() } }) end
    layoutDirty = true
end

RegisterNUICallback('ui:ready', function(_, cb)
    uiReady, last = true, {}
    cb({ ok = true })
    sendSettings()
end)

---------------------------------------------------------------------------
-- Vehicles
---------------------------------------------------------------------------
local MS = { MPH = 2.236936, KMH = 3.6, KTS = 1.943844 }
local DIRS = { 'N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW' }
local function dirOf(h) return DIRS[(math.floor((h + 22.5) / 45) % 8) + 1] end

local function layoutFor(veh, s)
    local model = GetEntityModel(veh)
    local mode = HudConfig.ModelOverrides[model] or HudConfig.VehicleClasses[GetVehicleClass(veh)] or 'none'
    if mode == 'none' then return nil end
    if not s.vehicle.auto and mode ~= 'bicycle' then mode = 'car' end
    if not s.vehicle.modes[mode] then return nil end
    return mode
end

local function engineState(veh)
    local h = GetVehicleEngineHealth(veh)
    if h < 300 then return 'critical' elseif h < 600 then return 'warn' end
    return nil
end

local lastBeep = 0
local function vehicleSection(ped, veh, s)
    local mode = layoutFor(veh, s)
    if not mode then return false end
    local v = s.vehicle
    local on = GetIsVehicleEngineRunning(veh)
    local out = { mode = mode }
    local vel = GetEntityVelocity(veh)
    if mode == 'car' or mode == 'motorcycle' or mode == 'bicycle' then
        local mps = GetEntitySpeed(veh)
        out.speed, out.unit = math.floor(mps * MS[v.roadUnit] + 0.5), v.roadUnit
    else
        -- Boats and helicopters: horizontal ground speed (GTA has no airspeed or water-speed sensor).
        local gs = math.sqrt(vel.x * vel.x + vel.y * vel.y)
        out.speed, out.unit = math.floor(gs * MS[v.airSeaUnit] + 0.5), v.airSeaUnit
    end
    if mode == 'bicycle' then
        if v.bikeStamina then out.stamina = math.max(0, math.min(100, math.floor(100 - GetPlayerSprintStaminaRemaining(PlayerId())))) end
        return out
    end
    local showRpm = v.rpm and (mode ~= 'boat' or HudConfig.BoatRpm)
    if showRpm then out.rpm = on and (math.floor(GetVehicleCurrentRpm(veh) * 50 + 0.5) / 50) or 0 end
    if v.fuel then out.fuel = Bridge.Fuel.Level(veh) and math.floor(Bridge.Fuel.Level(veh) + 0.5) or nil end
    if v.engine then out.engine = not on and 'off' or engineState(veh) end
    if mode == 'car' or mode == 'motorcycle' then
        if v.gear then
            local fwd = GetEntitySpeedVector(veh, true).y
            local g = GetVehicleCurrentGear(veh)
            out.gear = not on and '-' or (fwd < -0.5 and 'R') or (math.abs(fwd) < 0.5 and 'N') or (g == 0 and 'R' or tostring(g))
        end
        if mode == 'car' and HudConfig.BeltClasses[GetVehicleClass(veh)] then
            local belt = Bridge.Seatbelt.State()
            if v.seatbelt then out.seatbelt = belt end
            if v.seatbeltAlert and belt == 'off' and GetEntitySpeed(veh) * 2.236936 > HudConfig.SeatbeltAlertMph then
                out.beltAlert = true
                if GetGameTimer() - lastBeep > 3000 then
                    lastBeep = GetGameTimer()
                    PlaySoundFrontend(-1, 'Beep_Red', 'DLC_HEIST_HACKING_SNAKE_SOUNDS', true)
                end
            end
        end
    else
        -- Heading for boats and helicopters (compass degrees, 0 = north).
        out.heading = math.floor((360.0 - GetEntityHeading(veh)) % 360.0)
    end
    if mode == 'heli' then
        local metres = v.altMode == 'AGL' and GetEntityHeightAboveGround(veh) or GetEntityCoords(veh).z
        out.alt = math.floor((v.altUnit == 'FT' and metres * 3.28084 or metres) + 0.5)
        out.altUnit, out.altMode = v.altUnit, v.altMode
        out.vs = v.vsUnit == 'FPM' and math.floor(vel.z * 196.8504 / 10 + 0.5) * 10 or math.floor(vel.z * 10 + 0.5) / 10
        out.vsUnit = v.vsUnit == 'FPM' and 'ft/min' or 'm/s'
    end
    return out
end

---------------------------------------------------------------------------
-- Player status (normalized 0-100; nil = not available -> hidden)
---------------------------------------------------------------------------
local oxygenMax = nil
local function statusSection(ped)
    local pid = PlayerId()
    local maxH = math.max(1, GetEntityMaxHealth(ped) - 100) -- GTA: 100 is dead, max is usually 200
    local st = {
        health = IsEntityDead(ped) and 0 or math.max(0, math.min(100, math.floor((GetEntityHealth(ped) - 100) / maxH * 100 + 0.5))),
        armor = math.max(0, math.min(100, GetPedArmour(ped))),
        -- GetPlayerSprintStaminaRemaining counts stamina USED (0 = fresh), so remaining = 100 - value.
        stamina = math.max(0, math.min(100, math.floor(100 - GetPlayerSprintStaminaRemaining(pid)))),
    }
    local needs = Bridge.Framework.Needs()
    if needs then
        for k, v in pairs(needs) do if v then st[k] = math.max(0, math.min(100, math.floor(v + 0.5))) end end
    end
    if IsPedSwimmingUnderWater(ped) then
        local left = GetPlayerUnderwaterTimeRemaining(pid)
        oxygenMax = math.max(oxygenMax or 0, left)
        st.oxygen = oxygenMax > 0 and math.max(0, math.min(100, math.floor(left / oxygenMax * 100))) or 0
    else
        oxygenMax = nil
    end
    return st
end

---------------------------------------------------------------------------
-- Visibility and lifecycle
---------------------------------------------------------------------------
local function hudVisible()
    local s = Settings.current
    if not s.enabled and not menuOpen then return false end
    if not Bridge.Framework.IsReady() then return false end
    if IsPauseMenuActive() or IsScreenFadedOut() or IsScreenFadingOut() then return false end
    if Bridge.Framework.MedicalState() == 'dead' then return false end -- the death screen takes over
    if not menuOpen and GetResourceState('veyl_lib') == 'started' and exports.veyl_lib:IsModalOpen() then return false end
    return true
end

Bridge.Framework.OnUnload(function()
    last = {}
    if uiReady then SendNUIMessage({ action = 'hud:reset' }) end
end)

local wasPaused = false
CreateThread(function()
    Settings.Load()
    Bridge.Voice.Detect()
    Bridge.Fuel.Detect()
    Bridge.Postal.Load()
    Minimap.DetectCircle()
    Minimap.Apply(Settings.current, true)
    sendSettings()

    local tick = 0
    while true do
        local show = hudVisible()
        local s = Settings.current
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        local radar = Minimap.Tick(s, veh ~= 0, show)

        -- Back from the pause map: GTA may reset the minimap layout.
        local paused = IsPauseMenuActive()
        if wasPaused and not paused then Minimap.Apply(s, true) layoutDirty = true end
        wasPaused = paused

        local sections = { visible = show }
        if show then
            tick = tick + 1
            sections.vehicle = veh ~= 0 and vehicleSection(ped, veh, s) or false
            if tick % 2 == 0 then sections.voice = Bridge.Voice.State() end
            if tick % 3 == 0 then
                local c = GetEntityCoords(ped)
                local h = (360.0 - GetGameplayCamRot(2).z) % 360.0
                local s1, s2 = GetStreetNameAtCoord(c.x, c.y, c.z)
                sections.location = {
                    heading = math.floor(h), dir = dirOf(h), street = GetStreetNameFromHashKey(s1),
                    cross = s2 ~= 0 and GetStreetNameFromHashKey(s2) or nil, zone = GetLabelText(GetNameOfZone(c.x, c.y, c.z)),
                    postal = Bridge.Postal.Nearest(c.x, c.y),
                }
            end
            if tick % 5 == 0 or tick == 1 then
                sections.status = statusSection(ped)
                local cash, bank = Bridge.Framework.Money()
                sections.info = { id = GetPlayerServerId(PlayerId()), cash = cash, bank = bank,
                    time = ('%02d:%02d'):format(GetClockHours(), GetClockMinutes()) }
            end
            if layoutDirty or tick % 50 == 0 then
                local rect = Minimap.Rect(s)
                rect.shown = radar
                sections.layout = rect
                layoutDirty = false
            end
        end
        push(sections)
        Wait(show and 100 or 400)
    end
end)

-- Native HUD components this HUD replaces, and the inventory-only weapon rules (unchanged from the previous HUD).
CreateThread(function()
    local movie = HudConfig.HideNativeBars and RequestScaleformMovie('minimap') or nil
    while true do
        if LocalPlayer.state.isLoggedIn then
            for _, c in ipairs(HudConfig.HideComponents) do HideHudComponentThisFrame(c) end
            if movie then
                BeginScaleformMovieMethod(movie, 'SETUP_HEALTH_ARMOUR')
                ScaleformMovieMethodAddParamInt(3) -- no health / armour bars under the map
                EndScaleformMovieMethod()
            end
            if HudConfig.DisableWeaponWheel then
                HideHudComponentThisFrame(19) HideHudComponentThisFrame(20)
                DisableControlAction(0, 37, true)
                DisableControlAction(0, 14, true) DisableControlAction(0, 15, true)
                DisableControlAction(0, 16, true) DisableControlAction(0, 17, true)
                DisableControlAction(0, 99, true) DisableControlAction(0, 100, true)
            end
            Wait(0)
        else
            Wait(500)
        end
    end
end)

---------------------------------------------------------------------------
-- Settings menu (NUI focus through veyl_lib's focus broker, so it never fights other screens)
---------------------------------------------------------------------------
local function releaseFocus()
    SetNuiFocus(false, false)
    if focusToken then pcall(function() exports.veyl_lib:ReleaseFocus(focusToken) end) focusToken = nil end
end

local function closeMenu(restore)
    if not menuOpen then return end
    menuOpen = false
    if restore then
        Settings.current = Settings.Copy(Settings.saved)
        Minimap.Apply(Settings.current)
    end
    releaseFocus()
    SendNUIMessage({ action = 'hud:menu', data = { open = false } })
    sendSettings()
end

local function openMenu()
    if menuOpen or not uiReady or not Bridge.Framework.IsReady() then return end
    local token = exports.veyl_lib:RequestFocus('veyl_hud')
    if not token then return vlib.notify({ message = 'Close the open menu first.', type = 'warning' }) end
    focusToken, menuOpen = token, true
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'hud:menu', data = { open = true, settings = Settings.saved, defaults = Settings.Defaults(), caps = caps() } })
end

RegisterCommand(HudConfig.MenuCommand, function() if menuOpen then closeMenu(true) else openMenu() end end, false)
RegisterCommand('hudsettings', function() openMenu() end, false)
RegisterCommand('veyl_hud_menu', function() if menuOpen then closeMenu(true) else openMenu() end end, false)
RegisterKeyMapping('veyl_hud_menu', 'Open HUD settings', 'keyboard', HudConfig.MenuKey or '')

AddEventHandler('veyl_lib:focusRevoked', function(token) if token == focusToken then focusToken = nil closeMenu(true) end end)
AddEventHandler('veyl_lib:brokerReset', function() focusToken = nil closeMenu(true) end)

-- Live preview: the menu sends the whole draft; it is cleaned before anything uses it.
RegisterNUICallback('menu:preview', function(data, cb)
    if not menuOpen or type(data) ~= 'table' then return cb({ ok = false }) end
    Settings.current = Settings.Clean(data.settings)
    Minimap.Apply(Settings.current, false, data.moving == true)
    layoutDirty = true
    local rect = Minimap.Rect(Settings.current)
    cb({ ok = true, settings = Settings.current, layout = rect })
end)

RegisterNUICallback('menu:save', function(data, cb)
    if not menuOpen or type(data) ~= 'table' then return cb({ ok = false }) end
    Settings.Save(data.settings)
    Minimap.Apply(Settings.current)
    cb({ ok = true, settings = Settings.current })
    closeMenu(false)
    vlib.notify({ message = 'HUD settings saved', type = 'success', duration = 2000 })
end)

RegisterNUICallback('menu:cancel', function(_, cb)
    cb({ ok = true })
    closeMenu(true)
end)

RegisterNUICallback('menu:defaults', function(_, cb)
    cb({ ok = true, settings = Settings.Defaults() })
end)

---------------------------------------------------------------------------
-- Cleanup
---------------------------------------------------------------------------
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if menuOpen then releaseFocus() end
    Minimap.Restore()
end)
