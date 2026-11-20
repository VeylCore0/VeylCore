-- vlib.zones (client): geometry helpers with validated input.
--   local z = vlib.zones.sphere({ coords = vec3, radius = 2.0 })
--   local z = vlib.zones.box({ coords = vec3, size = vec3(w, l, h), rotation = 0.0 })
--   z:contains(point) / z:distance(point)

local M = {}

local function isVec3(v) return type(v) == 'vector3' or (type(v) == 'table' and tonumber(v.x) and tonumber(v.y) and tonumber(v.z)) end
local function toVec3(v) return type(v) == 'vector3' and v or vector3(v.x + 0.0, v.y + 0.0, v.z + 0.0) end

local Sphere = {}
Sphere.__index = Sphere
function Sphere:contains(p) return #(p - self.coords) <= self.radius end
function Sphere:distance(p) return math.max(0.0, #(p - self.coords) - self.radius) end

local Box = {}
Box.__index = Box
function Box:local_(p)
    local d = p - self.coords
    local x = d.x * self.cos + d.y * self.sin
    local y = -d.x * self.sin + d.y * self.cos
    return x, y, d.z
end
function Box:contains(p)
    local x, y, z = self:local_(p)
    return math.abs(x) <= self.half.x and math.abs(y) <= self.half.y and math.abs(z) <= self.half.z
end
function Box:distance(p)
    local x, y, z = self:local_(p)
    local dx = math.max(math.abs(x) - self.half.x, 0.0)
    local dy = math.max(math.abs(y) - self.half.y, 0.0)
    local dz = math.max(math.abs(z) - self.half.z, 0.0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

function M.sphere(data, caller)
    if type(data) ~= 'table' or not isVec3(data.coords) then
        error(('vlib.zones.sphere (%s): coords must be a vector3'):format(caller or GetCurrentResourceName()), 2)
    end
    local r = tonumber(data.radius)
    if not r or r <= 0 or r > 500 then error(('vlib.zones.sphere (%s): radius must be 0-500'):format(caller or GetCurrentResourceName()), 2) end
    return setmetatable({ kind = 'sphere', coords = toVec3(data.coords), radius = r + 0.0 }, Sphere)
end

function M.box(data, caller)
    if type(data) ~= 'table' or not isVec3(data.coords) then
        error(('vlib.zones.box (%s): coords must be a vector3'):format(caller or GetCurrentResourceName()), 2)
    end
    if not isVec3(data.size) or data.size.x <= 0 or data.size.y <= 0 or data.size.z <= 0 then
        error(('vlib.zones.box (%s): size must be a positive vector3'):format(caller or GetCurrentResourceName()), 2)
    end
    local rot = math.rad(tonumber(data.rotation) or 0.0)
    local size = toVec3(data.size)
    return setmetatable({
        kind = 'box', coords = toVec3(data.coords), size = size, rotation = tonumber(data.rotation) or 0.0,
        half = size / 2, cos = math.cos(rot), sin = math.sin(rot),
    }, Box)
end

return M
