-- veyl_hud client: collects game/framework state and sends only CHANGED sections to the passive NUI.
-- Providers are detected once (voice) or configured (seatbelt); missing providers show "unavailable".

local settings = {}
local visible = true
local last = {}          -- section -> signature of last sent value
local uiReady = false

---------------------------------------------------------------------------
-- Settings (per player, KVP)
---------------------------------------------------------------------------
local function loadSettings()
    settings = {}
    for k, v in pairs(HudConfig.Defaults) do settings[k] = v end
    local raw = GetResourceKvpString('veyl_hud:settings')
    if raw then
        local ok, saved = pcall(json.decode, raw)
        if ok and type(saved) == 'table' then
            for k, v in pairs(saved) do if settings[k] ~= nil and type(v) == type(settings[k]) then settings[k] = v end end
        end
    end
    settings.scale = math.max(0.75, math.min(1.4, tonumber(settings.scale) or 1.0))
end

local function saveSettings()
    SetResourceKvp('veyl_hud:settings', json.encode(settings))
    last.settings = nil
end

loadSettings()

---------------------------------------------------------------------------
-- Adapters
---------------------------------------------------------------------------
local voiceProvider = 'native'
CreateThread(function()
    Wait(1000)
    if HudConfig.Voice == 'auto' and GetResourceState('pma-voice') == 'started' then voiceProvider = 'pma-voice' end
end)

local function voiceState()
    local talking = NetworkIsPlayerTalking(PlayerId())
    if voiceProvider == 'pma-voice' then
        local prox = LocalPlayer.state.proximity
        local index = type(prox) == 'table' and tonumber(prox.index) or nil
        return { talking = talking, range = index and math.min(4, index + 1) or nil, available = index ~= nil }
    end
    return { talking = talking, range = nil, available = false }
end

local function seatbeltState(veh)
    if HudConfig.Seatbelt == 'statebag' then
        local v = LocalPlayer.state.seatbelt
        if v == nil then return 'unavailable' end
        return v and 'on' or 'off'
    end
    return 'unavailable'
end

local function fuelOf(veh)
    local f = Entity(veh).state.veylFuel
    if f ~= nil then return math.floor(f + 0.5) end
    local g = GetVehicleFuelLevel(veh)
    return g and math.floor(g + 0.5) or nil
end

--- Real minimap rectangle (fractions of the screen), safezone and aspect aware.
local function minimapRect()
    local safezone = GetSafeZoneSize()
    local aspect = GetAspectRatio(false)
    local resX, resY = GetActiveScreenResolution()
    local xs, ys = 1.0 / resX, 1.0 / resY
    local width = xs * (resX / (4 * aspect))
    local height = ys * (resY / 5.674)
    local sz = math.abs(safezone - 1.0) * 10
    local left = xs * (resX * (0.05 * sz))
    local bottom = ys * (resY * (0.05 * sz))
    if aspect > 2.0 then left = left + width / 3.0 end -- ultrawide
    -- That rectangle covers the map plus GTA's bar strip; frame only the map, at its raised position.
    local mm, n = HudConfig.Minimap or {}, (HudConfig.Minimap or {}).frameNudge or {}
    local strip = mm.barStrip or 0.0
    return {
        left = left + (n.x or 0), width = width + (n.w or 0),
        bottom = bottom + (mm.raise or 0) + strip + (n.y or 0), height = height - strip + (n.h or 0),
    }
end

-- GTA default minimap component positions (alignment L/B); the HUD raises each one by HudConfig.Minimap.raise.
local MINIMAP_DEFAULTS = {
    { 'minimap',      -0.0045, 0.002, 0.150, 0.188888 },
    { 'minimap_mask',  0.020,  0.032, 0.111, 0.159 },
    { 'minimap_blur', -0.03,   0.022, 0.266, 0.237 },
}

local function placeMinimap(raise)
    for _, c in ipairs(MINIMAP_DEFAULTS) do
        SetMinimapComponentPosition(c[1], 'L', 'B', c[2], c[3] - raise, c[4], c[5])
    end
    -- Toggling the big map makes GTA re-read the component positions.
    SetRadarBigmapEnabled(true, false)
    Wait(0)
    SetRadarBigmapEnabled(false, false)
end

CreateThread(function()
    local raise = (HudConfig.Minimap or {}).raise or 0.0
    if raise ~= 0.0 then placeMinimap(raise) end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        for _, c in ipairs(MINIMAP_DEFAULTS) do SetMinimapComponentPosition(c[1], 'L', 'B', c[2], c[3], c[4], c[5]) end
    end
end)

---------------------------------------------------------------------------
-- Sending (diffed per section)
---------------------------------------------------------------------------
local function sig(v) local ok, s = pcall(json.encode, v) return ok and s or tostring(v) end

local function push(sections)
    local changed, any = {}, false
    for k, v in pairs(sections) do
        local s = sig(v)
        if last[k] ~= s then last[k] = s changed[k] = v any = true end
    end
    if any and uiReady then SendNUIMessage({ action = 'hud:frame', data = changed }) end
end

RegisterNUICallback('ui:ready', function(_, cb)
    uiReady = true
    last = {}
    cb({ ok = true })
end)

local function shouldShow()
    return visible and LocalPlayer.state.isLoggedIn == true and not IsPauseMenuActive() and not IsScreenFadedOut()
        and not exports.veyl_lib:IsModalOpen()
end

local headingSent = -999

CreateThread(function()
    local tick = 0
    while true do
        local show = shouldShow()
        local sections = { visible = show }
        if show then
            tick = tick + 1
            local ped, pid = PlayerPedId(), PlayerId()
            local pd = Veyl.PlayerData or {}
            local meta = pd.metadata or {}

            -- Vehicle (100 ms)
            local veh = GetVehiclePedIsIn(ped, false)
            if veh ~= 0 then
                local mps = GetEntitySpeed(veh)
                local gear = GetVehicleCurrentGear(veh)
                sections.vehicle = {
                    speed = math.floor(mps * (settings.unit == 'KMH' and 3.6 or 2.236936) + 0.5), unit = settings.unit,
                    gear = (gear == 0 and mps > 0.5) and 'R' or (mps < 0.5 and 'N' or tostring(gear)),
                    rpm = math.floor(GetVehicleCurrentRpm(veh) * 20 + 0.5) / 20,
                    fuel = fuelOf(veh), seatbelt = seatbeltState(veh),
                }
            else
                sections.vehicle = false -- hidden on foot
            end

            -- Compass (send when heading moves >= 1 degree)
            local camHeading = (360.0 - GetGameplayCamRot(2).z) % 360.0
            if math.abs(camHeading - headingSent) >= 1.0 or tick % 10 == 0 then
                headingSent = camHeading
                local c = GetEntityCoords(ped)
                local s1 = GetStreetNameAtCoord(c.x, c.y, c.z)
                sections.compass = { heading = math.floor(camHeading), street = GetStreetNameFromHashKey(s1), zone = GetLabelText(GetNameOfZone(c.x, c.y, c.z)) }
            end

            -- Status (250 ms)
            if tick % 2 == 0 then
                local maxH = math.max(1, GetEntityMaxHealth(ped) - 100)
                local status = {
                    health = math.max(0, math.min(100, math.floor((GetEntityHealth(ped) - 100) / maxH * 100))),
                    armor = GetPedArmour(ped),
                    hunger = math.floor(tonumber(meta.hunger) or 100), thirst = math.floor(tonumber(meta.thirst) or 100),
                    stress = math.floor(tonumber(meta.stress) or 0),
                    stamina = math.floor(100 - GetPlayerSprintStaminaRemaining(pid)),
                }
                if IsPedSwimmingUnderWater(ped) then status.oxygen = math.min(100, math.floor(GetPlayerUnderwaterTimeRemaining(pid) * 10)) end
                sections.status = status
                sections.voice = voiceState()
                local money = pd.money or {}
                sections.info = { serverId = GetPlayerServerId(pid), cash = money.cash, bank = money.bank }
                sections.settings = settings
            end

            -- Minimap frame (2 s): only when the radar is actually rendered
            if tick % 20 == 1 then
                sections.minimap = IsRadarHidden() and false or minimapRect()
            end
        end
        push(sections)
        Wait(show and 100 or 500)
    end
end)

-- Hide default GTA components this HUD replaces.
CreateThread(function()
    local hideBars = (HudConfig.Minimap or {}).hideHealthArmour
    local minimapMovie = hideBars and RequestScaleformMovie('minimap') or nil
    while true do
        if LocalPlayer.state.isLoggedIn then
            for _, c in ipairs(HudConfig.HideComponents) do HideHudComponentThisFrame(c) end
            if minimapMovie then
                -- 3 = no health/armour bars under the minimap (the HUD status row shows health and armour).
                BeginScaleformMovieMethod(minimapMovie, 'SETUP_HEALTH_ARMOUR')
                ScaleformMovieMethodAddParamInt(3)
                EndScaleformMovieMethod()
            end
            if HudConfig.DisableWeaponWheel then
                -- Weapons come from the inventory: no Tab wheel and no scroll-wheel weapon cycling.
                HideHudComponentThisFrame(19) -- weapon wheel
                HideHudComponentThisFrame(20) -- weapon wheel stats
                DisableControlAction(0, 37, true)                                   -- select weapon (Tab)
                DisableControlAction(0, 14, true) DisableControlAction(0, 15, true) -- weapon wheel next / prev
                DisableControlAction(0, 16, true) DisableControlAction(0, 17, true) -- select next / prev weapon
                DisableControlAction(0, 99, true) DisableControlAction(0, 100, true) -- vehicle select next / prev weapon
            end
            Wait(0)
        else
            Wait(500)
        end
    end
end)

---------------------------------------------------------------------------
-- Commands
---------------------------------------------------------------------------
RegisterCommand('hud', function()
    visible = not visible
    vlib.notify({ message = visible and 'HUD shown' or 'HUD hidden', type = 'info', duration = 2000 })
end, false)

local function settingsMenu()
    local function yn(v) return v and 'On' or 'Off' end
    vlib.registerMenu({
        id = 'veyl_hud:settings', title = 'HUD settings', subtitle = 'Saved for this player',
        options = {
            { id = 'unit', label = 'Speed unit', right = settings.unit },
            { id = 'scale_up', label = 'Larger', right = ('%d%%'):format(math.floor(settings.scale * 100)) },
            { id = 'scale_down', label = 'Smaller' },
            { id = 'showStatus', label = 'Status bars', right = yn(settings.showStatus) },
            { id = 'showVehicle', label = 'Vehicle display', right = yn(settings.showVehicle) },
            { id = 'showCompass', label = 'Compass and street', right = yn(settings.showCompass) },
            { id = 'showMoney', label = 'Cash and bank', right = yn(settings.showMoney) },
            { id = 'showBrand', label = 'Branding and ID', right = yn(settings.showBrand) },
            { id = 'reset', label = 'Reset to defaults' },
        },
    }, function(id)
        if id == 'unit' then settings.unit = settings.unit == 'MPH' and 'KMH' or 'MPH'
        elseif id == 'scale_up' then settings.scale = math.min(1.4, settings.scale + 0.05)
        elseif id == 'scale_down' then settings.scale = math.max(0.75, settings.scale - 0.05)
        elseif id == 'reset' then DeleteResourceKvp('veyl_hud:settings') loadSettings()
        elseif settings[id] ~= nil then settings[id] = not settings[id] end
        saveSettings()
        SetTimeout(100, settingsMenu)
    end)
    vlib.showMenu('veyl_hud:settings')
end

RegisterCommand('hudsettings', function() settingsMenu() end, false)

AddEventHandler('onResourceStart', function(res)
    if res == GetCurrentResourceName() then last = {} end
end)
