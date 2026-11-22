-- Native GTA minimap: placement, scale, square / circle shape, display mode and north-up. The radar, blips and GPS
-- route are GTA's own; this file only moves and masks it, and reports where it is so the NUI can align to it.
--
-- Natives used: SetMinimapComponentPosition, SetMinimapClipType (0 rectangle, 1 circle), AddReplaceTexture /
-- RemoveReplaceTexture (circle mask), SetRadarBigmapEnabled (makes GTA re-read component positions), DisplayRadar,
-- LockMinimapAngle / UnlockMinimapAngle, GetSafeZoneSize, GetAspectRatio, GetActiveScreenResolution.

Minimap = { applied = nil, circleAvailable = false }

local RAISE = 0.045 -- room under the map for GTA's (hidden) bar strip
local STRIP = 0.014

-- GTA defaults (alignment L / B): name, x, y, w, h.
local SQUARE = {
    { 'minimap', -0.0045, 0.002, 0.150, 0.188888 },
    { 'minimap_mask', 0.020, 0.032, 0.111, 0.159 },
    { 'minimap_blur', -0.03, 0.022, 0.266, 0.237 },
}
-- Circle layout used with the round `radarmasksm` mask (clip type 1).
local CIRCLE = {
    { 'minimap', -0.0100, -0.030, 0.180, 0.258 },
    { 'minimap_mask', 0.200, 0.0, 0.065, 0.20 },
    { 'minimap_blur', -0.00, 0.015, 0.252, 0.338 },
}

function Minimap.DetectCircle()
    local dict = HudConfig.CircleTextureDict
    if not dict or dict == '' then Minimap.circleAvailable = false return end
    RequestStreamedTextureDict(dict, false)
    local t = GetGameTimer() + 3000
    while not HasStreamedTextureDictLoaded(dict) and GetGameTimer() < t do Wait(50) end
    Minimap.circleAvailable = HasStreamedTextureDictLoaded(dict)
end

local function place(shape, scale, ox, oy)
    local layout = shape == 'circle' and CIRCLE or SQUARE
    if shape == 'circle' then
        AddReplaceTexture('platform:/textures/graphics', 'radarmasksm', HudConfig.CircleTextureDict, 'radarmasksm')
        SetMinimapClipType(1)
    else
        RemoveReplaceTexture('platform:/textures/graphics', 'radarmasksm')
        SetMinimapClipType(0)
    end
    for _, c in ipairs(layout) do
        -- Scale around the bottom-left anchor; offsets move right (x) and up (y).
        SetMinimapComponentPosition(c[1], 'L', 'B', c[2] * scale + ox, c[3] * scale - RAISE - oy, c[4] * scale, c[5] * scale)
    end
    SetRadarBigmapEnabled(true, false)
    Wait(0)
    SetRadarBigmapEnabled(false, false)
end

--- Applies the minimap part of the settings (only when it changed, or when forced after the pause map / a restart).
function Minimap.Apply(s, force)
    local m = s.minimap
    local shape = (m.shape == 'circle' and Minimap.circleAvailable) and 'circle' or 'square'
    local key = ('%s|%.3f|%.3f|%.3f'):format(shape, m.scale, m.offsetX, m.offsetY)
    if not force and Minimap.applied == key then return end
    Minimap.applied = key
    place(shape, m.scale, m.offsetX, m.offsetY)
end

--- Screen rectangle of the visible map (fractions), safe-zone and aspect aware.
function Minimap.Rect(s)
    local m = s.minimap
    local safezone = GetSafeZoneSize()
    local aspect = GetAspectRatio(false)
    local resX, resY = GetActiveScreenResolution()
    local xs, ys = 1.0 / resX, 1.0 / resY
    local width = xs * (resX / (4 * aspect))
    local height = ys * (resY / 5.674)
    local sz = math.abs(safezone - 1.0) * 10
    local left = xs * (resX * (0.05 * sz))
    local bottom = ys * (resY * (0.05 * sz))
    if aspect > 2.0 then left = left + width / 3.0 end -- ultrawide: GTA keeps the map inside a 16:9 area
    -- Component offsets are in 16:9 screen units; convert x to the real aspect.
    local xk = (16 / 9) / aspect
    local shape = (m.shape == 'circle' and Minimap.circleAvailable) and 'circle' or 'square'
    return {
        left = left + m.offsetX * xk, bottom = bottom + RAISE + STRIP + m.offsetY,
        width = width * m.scale, height = (height - STRIP) * m.scale, shape = shape,
        safe = (1.0 - safezone) / 2,
    }
end

--- Radar on/off by mode; north-up lock. Called from the main loop (cheap: only changes state when needed).
local shownState, northState = nil, nil
function Minimap.Tick(s, inVehicle, hudOn)
    local mode = s.minimap.mode
    local show = hudOn and (mode == 'always' or (mode == 'vehicle' and inVehicle))
    if show ~= shownState then DisplayRadar(show) shownState = show end
    local north = s.minimap.northUp
    if north then LockMinimapAngle(0) elseif northState then UnlockMinimapAngle() end
    northState = north
    return show
end

function Minimap.Restore()
    for _, c in ipairs(SQUARE) do SetMinimapComponentPosition(c[1], 'L', 'B', c[2], c[3], c[4], c[5]) end
    RemoveReplaceTexture('platform:/textures/graphics', 'radarmasksm')
    SetMinimapClipType(0)
    UnlockMinimapAngle()
    DisplayRadar(true)
end
