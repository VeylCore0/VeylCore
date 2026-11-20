-- vlib.points (client): nearby-point queries with a coarse spatial grid and enter/exit callbacks.
--   local pt = vlib.points.new({ coords = vec3, distance = 5.0, onEnter?, onExit?, nearby? (every frame inside) })
--   pt:remove()
-- One update thread per resource; only points in nearby grid cells are evaluated.

local CELL = 100.0
local grid, all = {}, {}
local nextId = 0
local running = false

local function cellKey(x, y) return ('%d:%d'):format(math.floor(x / CELL), math.floor(y / CELL)) end

local Point = {}
Point.__index = Point

function Point:remove()
    all[self.id] = nil
    local cell = grid[self.cell]
    if cell then cell[self.id] = nil end
    if self.inside and self.onExit then pcall(self.onExit, self) end
    self.inside = false
end

local function loop()
    running = true
    CreateThread(function()
        while next(all) do
            local pos = GetEntityCoords(PlayerPedId())
            local cx, cy = math.floor(pos.x / CELL), math.floor(pos.y / CELL)
            local near = {}
            for dx = -1, 1 do
                for dy = -1, 1 do
                    local cell = grid[('%d:%d'):format(cx + dx, cy + dy)]
                    if cell then for id, p in pairs(cell) do near[id] = p end end
                end
            end
            local anyNearby = false
            for id, p in pairs(all) do
                local d = near[id] and #(pos - p.coords) or math.huge
                p.currentDistance = d
                local inside = d <= p.distance
                if inside and not p.inside then
                    p.inside = true
                    if p.onEnter then pcall(p.onEnter, p) end
                elseif not inside and p.inside then
                    p.inside = false
                    if p.onExit then pcall(p.onExit, p) end
                end
                if inside and p.nearby then anyNearby = true end
            end
            if anyNearby then
                -- Per-frame callbacks only while the player is inside a point that asked for them.
                local untilAt = GetGameTimer() + 300
                while GetGameTimer() < untilAt do
                    for _, p in pairs(all) do if p.inside and p.nearby then pcall(p.nearby, p) end end
                    Wait(0)
                end
            else
                Wait(300)
            end
        end
        running = false
    end)
end

local M = {}

function M.new(data)
    if type(data) ~= 'table' or not data.coords then error('vlib.points.new: coords required', 2) end
    local c = data.coords
    nextId = nextId + 1
    local p = setmetatable({
        id = nextId, coords = vector3(c.x + 0.0, c.y + 0.0, c.z + 0.0), distance = tonumber(data.distance) or 5.0,
        onEnter = data.onEnter, onExit = data.onExit, nearby = data.nearby, args = data.args, inside = false,
    }, Point)
    p.cell = cellKey(p.coords.x, p.coords.y)
    grid[p.cell] = grid[p.cell] or {}
    grid[p.cell][p.id] = p
    all[p.id] = p
    if not running then loop() end
    return p
end

function M.getNearby()
    local list = {}
    for _, p in pairs(all) do if p.inside then list[#list + 1] = p end end
    return list
end

return M
