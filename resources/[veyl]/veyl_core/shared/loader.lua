-- Loads and validates the `return { ... }` definition files in shared/ on both sides.
-- Grades use string keys in configuration ('0', '1', ...) and numeric levels in player data.

VeylShared = {}

local RES = GetCurrentResourceName()

local function loadDefinition(name)
    local path = ('shared/%s.lua'):format(name)
    local code = LoadResourceFile(RES, path)
    if not code then error(('veyl_core: missing %s'):format(path)) end
    local chunk, err = load(code, ('@@%s/%s'):format(RES, path), 't')
    if not chunk then error(('veyl_core: syntax error in %s: %s'):format(path, err)) end
    local ok, result = pcall(chunk)
    if not ok or type(result) ~= 'table' then error(('veyl_core: %s must return a table (%s)'):format(path, tostring(result))) end
    return result
end

local function validateGroups(kind, defs, defaultName)
    for name, def in pairs(defs) do
        assert(type(name) == 'string' and name:match('^[%w_%-]+$'), ('%s: invalid %s name %s'):format(RES, kind, tostring(name)))
        assert(type(def.label) == 'string', ('%s: %s %s needs a label'):format(RES, kind, name))
        assert(type(def.grades) == 'table', ('%s: %s %s needs grades'):format(RES, kind, name))
        local count = 0
        for key, grade in pairs(def.grades) do
            assert(type(key) == 'string' and tonumber(key), ('%s: %s %s grade keys must be numeric strings'):format(RES, kind, name))
            assert(type(grade.name) == 'string', ('%s: %s %s grade %s needs a name'):format(RES, kind, name, key))
            grade.payment = tonumber(grade.payment) or 0
            assert(grade.payment >= 0 and grade.payment % 1 == 0, ('%s: %s %s grade %s payment must be a whole number'):format(RES, kind, name, key))
            count = count + 1
        end
        assert(count > 0, ('%s: %s %s has no grades'):format(RES, kind, name))
    end
    assert(defs[defaultName], ('%s: the default %s "%s" must be defined'):format(RES, kind, defaultName))
end

VeylShared.Jobs = loadDefinition('jobs')
VeylShared.Gangs = loadDefinition('gangs')
VeylShared.Vehicles = loadDefinition('vehicles')
VeylShared.Weapons = loadDefinition('weapons')
VeylShared.Locations = loadDefinition('locations')

validateGroups('job', VeylShared.Jobs, VeylConfig.DefaultJob)
validateGroups('gang', VeylShared.Gangs, VeylConfig.DefaultGang)

--- Returns the grade definition for a group and numeric level, or nil.
function VeylShared.GetGrade(kind, name, level)
    local defs = kind == 'gang' and VeylShared.Gangs or VeylShared.Jobs
    local def = defs[name]
    if not def or level == nil then return nil end
    return def.grades[tostring(math.floor(tonumber(level) or -1))]
end
