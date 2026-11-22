-- Native GTA minimap: placement, scale, square / circle shape, display mode and north-up. The radar, blips and GPS
-- route are GTA's own; this file only moves and masks it, and reports where it is so the NUI can align to it.
--
-- Natives used: SetMinimapComponentPosition, SetMinimapClipType (0 rectangle, 1 circle), AddReplaceTexture /
-- RemoveReplaceTexture (circle mask), SetRadarBigmapEnabled (makes GTA re-read component positions), DisplayRadar,
-- LockMinimapAngle / UnlockMinimapAngle, GetSafeZoneSize, GetAspectRatio, GetActiveScreenResolution.

Minimap = { applied = nil, circleAvailable = true, circleTexture = false }

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

-- GTA's circular clip (type 1) only rounds the blips; the map picture itself is cut by the `radarmasksm` texture.
-- A streamed circlemap.ytd is used when present, otherwise a round mask is drawn once at runtime (no download).
local RT_DICT = 'veyl_hud_circle'
local maskDict = nil

local function buildRuntimeMask()
    local size = 256
    local txd = CreateRuntimeTxd(RT_DICT)
    local tex = CreateRuntimeTexture(txd, 'radarmasksm', size, size)
    local c, r = (size - 1) / 2, size / 2 - 1.5
    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local d = math.sqrt((x - c) ^ 2 + (y - c) ^ 2)
            local a = math.floor(math.max(0.0, math.min(1.0, r - d + 0.5)) * 255) -- 1 px anti-aliased edge
            SetRuntimeTexturePixel(tex, x, y, a, a, a, a)
        end
        if y % 32 == 0 then Wait(0) end
    end
    CommitRuntimeTexture(tex)
    return RT_DICT
end

function Minimap.DetectCircle()
    Minimap.circleAvailable = true
    local dict = HudConfig.CircleTextureDict
    if dict and dict ~= '' then
        RequestStreamedTextureDict(dict, false)
        local t = GetGameTimer() + 2000
        while not HasStreamedTextureDictLoaded(dict) and GetGameTimer() < t do Wait(50) end
        if HasStreamedTextureDictLoaded(dict) then maskDict = dict end
    end
    if not maskDict then
        local ok, res = pcall(buildRuntimeMask)
        maskDict = ok and res or nil
        if not ok then print(('^3[veyl_hud] could not build the circle mask: %s^7'):format(tostring(res))) end
    end
    Minimap.circleTexture = maskDict ~= nil
end

local function place(shape, scale, ox, oy)
    local layout = shape == 'circle' and CIRCLE or SQUARE
    if shape == 'circle' then
        if maskDict then AddReplaceTexture('platform:/textures/graphics', 'radarmasksm', maskDict, 'radarmasksm') end
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
--- While dragging (`moving`), only the positions are updated and GTA is refreshed at most every 50 ms.
local lastRefresh = 0
function Minimap.Apply(s, force, moving)
    local m = s.minimap
    local shape = (m.shape == 'circle' and Minimap.circleAvailable) and 'circle' or 'square'
    local key = ('%s|%.4f|%.4f|%.4f'):format(shape, m.scale, m.offsetX, m.offsetY)
    if not force and Minimap.applied == key and not Minimap.dirty then return end
    local shapeKey = Minimap.applied and Minimap.applied:match('^[^|]+')
    Minimap.applied = key
    if moving and shapeKey == shape and GetGameTimer() - lastRefresh < 50 then
        local layout = shape == 'circle' and CIRCLE or SQUARE
        for _, c in ipairs(layout) do
            SetMinimapComponentPosition(c[1], 'L', 'B', c[2] * m.scale + m.offsetX, c[3] * m.scale - RAISE - m.offsetY, c[4] * m.scale, c[5] * m.scale)
        end
        Minimap.dirty = true -- the final position still gets a full refresh
        return
    end
    Minimap.dirty = false
    lastRefresh = GetGameTimer()
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
    if shape == 'circle' then
        -- The circle layout is a larger map moved down; the visible disc is about 1.2x the square map's width,
        -- and round in pixels (same pixel height as width).
        local w = width * 1.2 * m.scale
        local h = w * aspect
        return { left = left + (m.offsetX - 0.0055) * xk, bottom = bottom + RAISE + m.offsetY - 0.012, width = w, height = h, shape = shape, safe = (1.0 - safezone) / 2, ox = m.offsetX, oy = m.offsetY }
    end
    return {
        left = left + m.offsetX * xk, bottom = bottom + RAISE + STRIP + m.offsetY,
        width = width * m.scale, height = (height - STRIP) * m.scale, shape = shape,
        safe = (1.0 - safezone) / 2, ox = m.offsetX, oy = m.offsetY,
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
