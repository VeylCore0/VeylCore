-- HUD settings: per-player preferences in resource KVP, versioned. Everything coming from storage or from the NUI
-- goes through Settings.Clean, which merges onto the defaults, keeps only known keys, checks types and clamps ranges.

Settings = { current = nil, saved = nil }
local KVP_KEY = 'veyl_hud:settings:v2'
local SCHEMA = 2

local function copy(v)
    if type(v) ~= 'table' then return v end
    local out = {}
    for k, x in pairs(v) do out[k] = copy(x) end
    return out
end
Settings.Copy = copy

local function clamp(v, lo, hi, default)
    v = tonumber(v)
    if not v or v ~= v then return default end
    return math.max(lo, math.min(hi, v))
end

local function oneOf(v, list, default)
    for _, x in ipairs(list) do if v == x then return v end end
    return default
end

local function color(v, default)
    if type(v) == 'string' and v:match('^#%x%x%x%x%x%x$') then return v:upper() end
    return default
end

--- Defaults merged with `input` (any shape). Unknown keys are dropped, wrong types fall back to the default.
function Settings.Clean(input)
    local d = HudConfig.Defaults
    local s = copy(d)
    if type(input) ~= 'table' then return s end
    local function bool(tbl, src, key) if type(src[key]) == 'boolean' then tbl[key] = src[key] end end

    bool(s, input, 'enabled') bool(s, input, 'showPercent') bool(s, input, 'reducedMotion') bool(s, input, 'snap')
    s.scale = clamp(input.scale, 0.7, 1.5, d.scale)
    s.opacity = clamp(input.opacity, 0.2, 1.0, d.opacity)
    s.borderOpacity = clamp(input.borderOpacity, 0.0, 1.0, d.borderOpacity)

    local c = type(input.colors) == 'table' and input.colors or {}
    s.colors = { primary = color(c.primary, d.colors.primary), secondary = color(c.secondary, d.colors.secondary), text = color(c.text, d.colors.text) }

    local p = type(input.player) == 'table' and input.player or {}
    for k, v in pairs(d.player) do if type(v) == 'boolean' then bool(s.player, p, k) end end
    s.player.layout = oneOf(p.layout, { 'list', 'compact' }, d.player.layout)

    local t = type(input.thresholds) == 'table' and input.thresholds or {}
    for k, v in pairs(d.thresholds) do s.thresholds[k] = math.floor(clamp(t[k], 0, 100, v)) end

    local m = type(input.minimap) == 'table' and input.minimap or {}
    s.minimap.shape = oneOf(m.shape, { 'square', 'circle' }, d.minimap.shape)
    s.minimap.mode = oneOf(m.mode, { 'always', 'vehicle', 'never' }, d.minimap.mode)
    bool(s.minimap, m, 'northUp') bool(s.minimap, m, 'street') bool(s.minimap, m, 'direction') bool(s.minimap, m, 'postal')
    s.minimap.scale = clamp(m.scale, 0.75, 1.4, d.minimap.scale)
    s.minimap.offsetX = clamp(m.offsetX, -0.3, 0.6, 0.0)
    s.minimap.offsetY = clamp(m.offsetY, -0.6, 0.3, 0.0)

    local v = type(input.vehicle) == 'table' and input.vehicle or {}
    for k, x in pairs(d.vehicle) do if type(x) == 'boolean' then bool(s.vehicle, v, k) end end
    local modes = type(v.modes) == 'table' and v.modes or {}
    for k in pairs(d.vehicle.modes) do bool(s.vehicle.modes, modes, k) end
    s.vehicle.roadUnit = oneOf(v.roadUnit, { 'MPH', 'KMH' }, d.vehicle.roadUnit)
    s.vehicle.airSeaUnit = oneOf(v.airSeaUnit, { 'KTS', 'MPH', 'KMH' }, d.vehicle.airSeaUnit)
    s.vehicle.altUnit = oneOf(v.altUnit, { 'FT', 'M' }, d.vehicle.altUnit)
    s.vehicle.vsUnit = oneOf(v.vsUnit, { 'FPM', 'MS' }, d.vehicle.vsUnit)
    s.vehicle.altMode = oneOf(v.altMode, { 'AGL', 'MSL' }, d.vehicle.altMode)

    -- Positions: normalized 0-1 anchors per known group (top-left corner of the group).
    s.positions = {}
    local pos = type(input.positions) == 'table' and input.positions or {}
    for _, key in ipairs({ 'status', 'voice', 'vehicle', 'info', 'location' }) do
        local q = pos[key]
        if type(q) == 'table' and tonumber(q.x) and tonumber(q.y) then
            s.positions[key] = { x = clamp(q.x, 0, 0.98, 0), y = clamp(q.y, 0, 0.98, 0) }
        end
    end
    return s
end

function Settings.Load()
    local raw = GetResourceKvpString(KVP_KEY)
    local data
    if raw then
        local ok, decoded = pcall(json.decode, raw)
        if ok and type(decoded) == 'table' and decoded.schema == SCHEMA then data = decoded.settings
        else print('^3[veyl_hud] stored settings were unreadable; using defaults^7') end
    else
        -- Migrate the v1 settings (scale and speed unit) once.
        local old = GetResourceKvpString('veyl_hud:settings')
        local ok, v1 = pcall(json.decode, old or '')
        if ok and type(v1) == 'table' then data = { scale = v1.scale, vehicle = { roadUnit = v1.unit } } end
    end
    Settings.saved = Settings.Clean(data)
    Settings.current = copy(Settings.saved)
end

function Settings.Save(s)
    Settings.saved = Settings.Clean(s)
    Settings.current = copy(Settings.saved)
    SetResourceKvp(KVP_KEY, json.encode({ schema = SCHEMA, settings = Settings.saved }))
end

function Settings.Defaults() return Settings.Clean(nil) end
