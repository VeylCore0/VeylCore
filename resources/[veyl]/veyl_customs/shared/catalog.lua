-- veyl_customs catalogue: every customisable option, its kind and its valid range. Shared: the client uses it to build
-- the menus (after asking the game which options the vehicle supports); the server uses it to validate and price.
--
-- Kinds (distinct semantics, never mixed):
--   mod      indexed mod slot (SetVehicleMod), value -1 (stock) .. count-1
--   toggle   toggle mod (ToggleVehicleMod), value true/false
--   index    a plain indexed setting (window tint, plate style, wheel type, colours), value min..max
--   livery   SetVehicleLivery, value -1 (none) .. count-1
--   extra    vehicle extra n (SetVehicleExtra), value true (on) / false (off)
--   rgb      custom colour { r, g, b } 0-255 (neon, tyre smoke)
--   paint    { index = 0-160, rgb = { r, g, b }? } primary / secondary paint; the index defines the finish
--   neon     { l, r, f, b } booleans (which neon tubes are on)

CustomsCatalog = {}

-- Categories in UI order. bike = shown for motorcycles (class 8); car = shown for everything else.
CustomsCatalog.Categories = {
    { id = 'performance', label = 'Performance', camera = 'front', bike = true, car = true },
    { id = 'bodywork', label = 'Bodywork', camera = 'front34', bike = true, car = true },
    { id = 'wheels', label = 'Wheels', camera = 'wheel', bike = true, car = true },
    { id = 'paint', label = 'Paint', camera = 'side34', bike = true, car = true },
    { id = 'lighting', label = 'Lighting', camera = 'front', bike = true, car = true },
    { id = 'details', label = 'Details', camera = 'rear34', bike = true, car = true },
}

-- Options. key = cart key (one cart line per key). part = stock part used by mechanic shops (Config.Parts).
CustomsCatalog.Options = {
    -- Performance (levels are capped by Config.Performance)
    { key = 'mod:11', kind = 'mod', slot = 11, cat = 'performance', label = 'Engine', part = 'perf_engine', camera = 'engine' },
    { key = 'mod:12', kind = 'mod', slot = 12, cat = 'performance', label = 'Brakes', part = 'perf_brakes', camera = 'wheel' },
    { key = 'mod:13', kind = 'mod', slot = 13, cat = 'performance', label = 'Transmission', part = 'perf_transmission' },
    { key = 'mod:15', kind = 'mod', slot = 15, cat = 'performance', label = 'Suspension', part = 'perf_suspension', camera = 'wheel' },
    { key = 'mod:16', kind = 'mod', slot = 16, cat = 'performance', label = 'Armour', part = 'body_kit' },
    { key = 'toggle:18', kind = 'toggle', slot = 18, cat = 'performance', label = 'Turbo', part = 'perf_turbo', camera = 'engine' },

    -- Bodywork (indexed mods; only slots the vehicle has are shown)
    { key = 'mod:0', kind = 'mod', slot = 0, cat = 'bodywork', label = 'Spoiler', part = 'body_kit', camera = 'rear34' },
    { key = 'mod:1', kind = 'mod', slot = 1, cat = 'bodywork', label = 'Front bumper', part = 'body_kit', camera = 'front' },
    { key = 'mod:2', kind = 'mod', slot = 2, cat = 'bodywork', label = 'Rear bumper', part = 'body_kit', camera = 'rear' },
    { key = 'mod:3', kind = 'mod', slot = 3, cat = 'bodywork', label = 'Side skirts', part = 'body_kit', camera = 'side' },
    { key = 'mod:4', kind = 'mod', slot = 4, cat = 'bodywork', label = 'Exhaust', part = 'body_kit', camera = 'rear' },
    { key = 'mod:5', kind = 'mod', slot = 5, cat = 'bodywork', label = 'Roll cage', part = 'body_kit', camera = 'side34' },
    { key = 'mod:6', kind = 'mod', slot = 6, cat = 'bodywork', label = 'Grille', part = 'body_kit', camera = 'front' },
    { key = 'mod:7', kind = 'mod', slot = 7, cat = 'bodywork', label = 'Hood', part = 'body_kit', camera = 'front' },
    { key = 'mod:8', kind = 'mod', slot = 8, cat = 'bodywork', label = 'Left fender', part = 'body_kit', camera = 'side' },
    { key = 'mod:9', kind = 'mod', slot = 9, cat = 'bodywork', label = 'Right fender', part = 'body_kit', camera = 'side' },
    { key = 'mod:10', kind = 'mod', slot = 10, cat = 'bodywork', label = 'Roof', part = 'body_kit', camera = 'top' },
    { key = 'mod:42', kind = 'mod', slot = 42, cat = 'bodywork', label = 'Arch covers', part = 'body_kit', camera = 'side' },
    { key = 'mod:43', kind = 'mod', slot = 43, cat = 'bodywork', label = 'Aerials', part = 'body_kit', camera = 'top' },
    { key = 'mod:44', kind = 'mod', slot = 44, cat = 'bodywork', label = 'Trim', part = 'body_kit', camera = 'side34' },
    { key = 'mod:45', kind = 'mod', slot = 45, cat = 'bodywork', label = 'Fuel tank', part = 'body_kit', camera = 'side' },
    { key = 'mod:39', kind = 'mod', slot = 39, cat = 'bodywork', label = 'Engine block', part = 'body_kit', camera = 'engine' },
    { key = 'mod:40', kind = 'mod', slot = 40, cat = 'bodywork', label = 'Air filter', part = 'body_kit', camera = 'engine' },
    { key = 'mod:41', kind = 'mod', slot = 41, cat = 'bodywork', label = 'Struts', part = 'body_kit', camera = 'engine' },

    -- Wheels (wheel type changes which wheels are listed; front wheels = mod 23, rear = 24 on motorcycles)
    { key = 'wheelType', kind = 'index', min = 0, max = 12, cat = 'wheels', label = 'Wheel type', camera = 'wheel' },
    { key = 'mod:23', kind = 'mod', slot = 23, cat = 'wheels', label = 'Wheels', part = 'wheel_set', camera = 'wheel' },
    { key = 'mod:24', kind = 'mod', slot = 24, cat = 'wheels', label = 'Rear wheel', part = 'wheel_set', camera = 'wheelRear', bikeOnly = true },
    { key = 'customTyres', kind = 'toggle', cat = 'wheels', label = 'Custom tyres', part = 'wheel_set', camera = 'wheel' },
    { key = 'wheelColor', kind = 'index', min = 0, max = 160, cat = 'wheels', label = 'Wheel colour', camera = 'wheel' },
    { key = 'toggle:20', kind = 'toggle', slot = 20, cat = 'wheels', label = 'Tyre smoke', camera = 'wheel' },
    { key = 'tyreSmoke', kind = 'rgb', cat = 'wheels', label = 'Tyre smoke colour', camera = 'wheel' },

    -- Paint (Paint Studio)
    { key = 'paint:primary', kind = 'paint', cat = 'paint', label = 'Primary paint', part = 'paint_can' },
    { key = 'paint:secondary', kind = 'paint', cat = 'paint', label = 'Secondary paint', part = 'paint_can' },
    { key = 'pearl', kind = 'index', min = 0, max = 160, cat = 'paint', label = 'Pearlescent', part = 'paint_can' },

    -- Lighting
    { key = 'toggle:22', kind = 'toggle', slot = 22, cat = 'lighting', label = 'Xenon headlights', part = 'light_kit', camera = 'front' },
    { key = 'xenonColor', kind = 'index', min = -1, max = 12, cat = 'lighting', label = 'Xenon colour', camera = 'front' },
    { key = 'neon', kind = 'neon', cat = 'lighting', label = 'Neon kit', part = 'light_kit', camera = 'side34', carOnly = true },
    { key = 'neonColor', kind = 'rgb', cat = 'lighting', label = 'Neon colour', camera = 'side34', carOnly = true },

    -- Details
    { key = 'windowTint', kind = 'index', min = 0, max = 6, cat = 'details', label = 'Window tint', camera = 'side34', carOnly = true },
    { key = 'plateIndex', kind = 'index', min = 0, max = 5, cat = 'details', label = 'Plate style', camera = 'rear' },
    { key = 'livery', kind = 'livery', min = -1, max = 40, cat = 'details', label = 'Livery', camera = 'side34' },
    { key = 'mod:48', kind = 'mod', slot = 48, cat = 'details', label = 'Livery (mod)', camera = 'side34' },
    { key = 'mod:14', kind = 'mod', slot = 14, cat = 'details', label = 'Horn' },
    { key = 'interiorColor', kind = 'index', min = 0, max = 160, cat = 'details', label = 'Interior colour', camera = 'interior', carOnly = true },
    { key = 'dashboardColor', kind = 'index', min = 0, max = 160, cat = 'details', label = 'Dashboard colour', camera = 'interior', carOnly = true },
    { key = 'mod:27', kind = 'mod', slot = 27, cat = 'details', label = 'Interior trim', camera = 'interior' },
    { key = 'mod:28', kind = 'mod', slot = 28, cat = 'details', label = 'Ornaments', camera = 'interior' },
    { key = 'mod:29', kind = 'mod', slot = 29, cat = 'details', label = 'Dashboard', camera = 'interior' },
    { key = 'mod:30', kind = 'mod', slot = 30, cat = 'details', label = 'Dials', camera = 'interior' },
    { key = 'mod:31', kind = 'mod', slot = 31, cat = 'details', label = 'Door speakers', camera = 'interior' },
    { key = 'mod:32', kind = 'mod', slot = 32, cat = 'details', label = 'Seats', camera = 'interior' },
    { key = 'mod:33', kind = 'mod', slot = 33, cat = 'details', label = 'Steering wheel', camera = 'interior' },
    { key = 'mod:34', kind = 'mod', slot = 34, cat = 'details', label = 'Shifter', camera = 'interior' },
    { key = 'mod:35', kind = 'mod', slot = 35, cat = 'details', label = 'Plaques', camera = 'interior' },
    { key = 'mod:25', kind = 'mod', slot = 25, cat = 'details', label = 'Plate holder', camera = 'rear' },
    { key = 'mod:26', kind = 'mod', slot = 26, cat = 'details', label = 'Vanity plates', camera = 'front' },
    -- extras 1..14 are generated (extra:<n>) for the extras the vehicle has.
}

CustomsCatalog.ByKey = {}
for _, o in ipairs(CustomsCatalog.Options) do CustomsCatalog.ByKey[o.key] = o end
for n = 1, 14 do
    local o = { key = 'extra:' .. n, kind = 'extra', extra = n, cat = 'details', label = ('Extra %d'):format(n), camera = 'side34' }
    CustomsCatalog.ByKey[o.key] = o
end

-- Paint finishes: explicit mappings to GTA's indexed paints. A custom RGB colour is drawn over the indexed paint, so
-- the indexed paint chosen here is what gives the finish. Pearlescent only shows on metallic paints.
CustomsCatalog.Finishes = {
    { id = 'metallic', label = 'Metallic', index = 0 },   -- Metallic Black
    { id = 'classic', label = 'Classic', index = 147 },   -- Classic (solid) Black (Modshop colour)
    { id = 'matte', label = 'Matte', index = 12 },        -- Matte Black
    { id = 'metal', label = 'Brushed metal', index = 117 }, -- Brushed Steel
    { id = 'chrome', label = 'Chrome', index = 120 },     -- Chrome
}

-- Wheel types (SetVehicleWheelType).
CustomsCatalog.WheelTypes = {
    [0] = 'Sport', [1] = 'Muscle', [2] = 'Lowrider', [3] = 'SUV', [4] = 'Offroad', [5] = 'Tuner', [6] = 'Bike',
    [7] = 'High end', [8] = "Benny's original", [9] = "Benny's bespoke", [10] = 'Open wheel', [11] = 'Street', [12] = 'Track',
}

CustomsCatalog.WindowTints = { [0] = 'None', [1] = 'Pure black', [2] = 'Dark smoke', [3] = 'Light smoke', [4] = 'Stock', [5] = 'Limo', [6] = 'Green' }
CustomsCatalog.PlateStyles = { [0] = 'Blue on white 1', [1] = 'Yellow on black', [2] = 'Yellow on blue', [3] = 'Blue on white 2', [4] = 'Blue on white 3', [5] = 'Yankton' }
CustomsCatalog.XenonColors = { [-1] = 'Default', [0] = 'White', [1] = 'Blue', [2] = 'Electric blue', [3] = 'Mint green', [4] = 'Lime green', [5] = 'Yellow',
    [6] = 'Golden shower', [7] = 'Orange', [8] = 'Red', [9] = 'Pony pink', [10] = 'Hot pink', [11] = 'Purple', [12] = 'Blacklight' }
CustomsCatalog.PerfLevelNames = { [-1] = 'Stock', [0] = 'Street', [1] = 'Sport', [2] = 'Race', [3] = 'Track', [4] = 'Elite' }

--- Validates one cart value against the catalogue. Returns the clean value or nil. Used on both sides.
function CustomsCatalog.Clean(key, value)
    local o = CustomsCatalog.ByKey[key]
    if not o then return nil end
    local function int(v, lo, hi) v = tonumber(v) if not v or v ~= v or v % 1 ~= 0 or v < lo or v > hi then return nil end return v end
    local function rgb(v)
        if type(v) ~= 'table' then return nil end
        local r, g, b = int(v.r, 0, 255), int(v.g, 0, 255), int(v.b, 0, 255)
        return (r and g and b) and { r = r, g = g, b = b } or nil
    end
    if o.kind == 'mod' then return int(value, -1, (o.slot == 23 or o.slot == 24) and 250 or 60) -- some wheel types have 200+ rims
    elseif o.kind == 'toggle' or o.kind == 'extra' then if type(value) == 'boolean' then return value end return nil
    elseif o.kind == 'index' or o.kind == 'livery' then return int(value, o.min, o.max)
    elseif o.kind == 'rgb' then return rgb(value)
    elseif o.kind == 'paint' then
        if type(value) ~= 'table' then return nil end
        local idx = int(value.index, 0, 160)
        if not idx then return nil end
        local c = value.rgb ~= nil and rgb(value.rgb) or nil
        if value.rgb ~= nil and not c then return nil end
        return { index = idx, rgb = c }
    elseif o.kind == 'neon' then
        if type(value) ~= 'table' then return nil end
        return { l = value.l == true, r = value.r == true, f = value.f == true, b = value.b == true }
    end
end

--- Writes a cart value into a veyl_vehicles props table (the framework's saved-looks format).
function CustomsCatalog.ApplyToProps(p, key, v)
    local o = CustomsCatalog.ByKey[key]
    p.mods, p.toggles, p.extras, p.neon = p.mods or {}, p.toggles or {}, p.extras or {}, p.neon or {}
    if o.kind == 'mod' then p.mods[tostring(o.slot)] = v
    elseif o.kind == 'toggle' and o.slot then p.toggles[tostring(o.slot)] = v
    elseif key == 'customTyres' then p.customTyres = v
    elseif o.kind == 'extra' then p.extras[tostring(o.extra)] = v
    elseif key == 'paint:primary' then p.color1 = v.index p.customPrimary = v.rgb or false
    elseif key == 'paint:secondary' then p.color2 = v.index p.customSecondary = v.rgb or false
    elseif key == 'neon' then p.neon = { ['0'] = v.l, ['1'] = v.r, ['2'] = v.f, ['3'] = v.b }
    else p[key] = v end
    return p
end

--- Reads a cart value out of a props table (nil when the props do not contain it).
function CustomsCatalog.FromProps(p, key)
    local o = CustomsCatalog.ByKey[key]
    if type(p) ~= 'table' or not o then return nil end
    if o.kind == 'mod' then return p.mods and tonumber(p.mods[tostring(o.slot)])
    elseif o.kind == 'toggle' and o.slot then return p.toggles and p.toggles[tostring(o.slot)]
    elseif key == 'customTyres' then return p.customTyres
    elseif o.kind == 'extra' then return p.extras and p.extras[tostring(o.extra)]
    elseif key == 'paint:primary' then return p.color1 and { index = p.color1, rgb = type(p.customPrimary) == 'table' and p.customPrimary or nil }
    elseif key == 'paint:secondary' then return p.color2 and { index = p.color2, rgb = type(p.customSecondary) == 'table' and p.customSecondary or nil }
    elseif key == 'neon' then return p.neon and { l = p.neon['0'] == true, r = p.neon['1'] == true, f = p.neon['2'] == true, b = p.neon['3'] == true }
    else return p[key] end
end

--- Deep equality for cart values.
function CustomsCatalog.Same(a, b)
    if type(a) ~= type(b) then return false end
    if type(a) ~= 'table' then return a == b end
    for k, v in pairs(a) do if not CustomsCatalog.Same(v, b[k]) then return false end end
    for k in pairs(b) do if a[k] == nil then return false end end
    return true
end
