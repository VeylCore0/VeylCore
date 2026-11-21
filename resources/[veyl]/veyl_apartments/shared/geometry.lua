-- Room geometry, shared by client and server. All values are LOCAL to one room (the zydrec_sm_int interior
-- archetype) and were read from zydrec-starlitemotel/stream/ytyp/zydrec_sm_interior.ytyp:
--   room "main" bounds   min (-4.518, -2.650, -1.541)  max (4.436, 2.957, 1.275)
--   door  zydrec_sm_prop_door       at (4.454, -1.707, -0.399), heading -90 (front wall, +X side)
--   front window frame              at (4.377, 0.942, 0.13..0.17)
--   back window frame               at (-4.618, 0.154, 0.17..0.21)
-- Local +X points out of the front door onto the walkway. The floor is at local z = -1.541.

AptGeometry = {
    Bounds = { min = vector3(-4.518, -2.650, -1.541), max = vector3(4.436, 2.957, 1.275) },
    FloorZ = -1.541,
    Door = { model = 'zydrec_sm_prop_door', pos = vector3(4.454, -1.707, -0.399) },
    -- Points derived from the door: just outside (walkway), just inside, and the in-room menu spot.
    Outside = vector3(5.35, -1.707, 0.0),
    Inside = vector3(3.35, -1.40, 0.0),
    Menu = vector3(3.35, -0.30, 0.0),
    -- Furniture must stay this far from the walls, and this far from the door (so the exit is never blocked).
    WallMargin = 0.25,
    DoorClearance = 1.30,
    MaxFurnitureHeight = 2.2,  -- metres above the floor for the object's origin
}

local function rot(yaw, x, y)
    local r = math.rad(yaw)
    local c, s = math.cos(r), math.sin(r)
    return x * c - y * s, x * s + y * c
end

--- World position of a local point (lx, ly, lz) in a unit. lz is relative to the room origin.
function AptGeometry.ToWorld(unit, l)
    local wx, wy = rot(unit.yaw, l.x, l.y)
    return vector3(unit.origin.x + wx, unit.origin.y + wy, unit.origin.z + l.z)
end

--- Local position of a world point in a unit.
function AptGeometry.ToLocal(unit, w)
    local dx, dy = w.x - unit.origin.x, w.y - unit.origin.y
    local lx, ly = rot(-unit.yaw, dx, dy)
    return vector3(lx, ly, w.z - unit.origin.z)
end

--- A standing point (ped coords ~1 m above the floor) for a local floor point.
function AptGeometry.Stand(unit, l)
    return AptGeometry.ToWorld(unit, vector3(l.x, l.y, AptGeometry.FloorZ + 1.0))
end

--- GTA heading for a local direction angle (0 = local +X).
function AptGeometry.Heading(unit, localAngle)
    return (unit.yaw + localAngle - 90.0) % 360.0
end

--- True when a world point is inside the room box (optionally shrunk by a margin).
function AptGeometry.Contains(unit, w, margin)
    local l = AptGeometry.ToLocal(unit, w)
    local b, m = AptGeometry.Bounds, margin or 0.0
    return l.x >= b.min.x + m and l.x <= b.max.x - m and l.y >= b.min.y + m and l.y <= b.max.y - m
        and l.z >= b.min.z - 0.5 and l.z <= b.max.z + 0.5
end

--- Validates a furniture transform in LOCAL space. Returns nil when valid, or a reason.
function AptGeometry.FurnitureProblem(l, heading)
    local G = AptGeometry
    if type(l) ~= 'table' and type(l) ~= 'vector3' then return 'Invalid position' end
    local x, y, z = tonumber(l.x), tonumber(l.y), tonumber(l.z)
    if not x or not y or not z or x ~= x or y ~= y or z ~= z then return 'Invalid position' end
    if type(heading) ~= 'number' or heading ~= heading or heading < 0 or heading >= 360 then return 'Invalid rotation' end
    local b, m = G.Bounds, G.WallMargin
    if x < b.min.x + m or x > b.max.x - m or y < b.min.y + m or y > b.max.y - m then return 'Keep it inside the room' end
    if z < G.FloorZ - 0.05 or z > G.FloorZ + G.MaxFurnitureHeight then return 'Too high or too low' end
    local dx, dy = x - G.Door.pos.x, y - G.Door.pos.y
    if math.sqrt(dx * dx + dy * dy) < G.DoorClearance then return 'Keep the doorway clear' end
    local mx, my = x - G.Menu.x, y - G.Menu.y
    if math.sqrt(mx * mx + my * my) < 0.6 then return 'Keep the entry area clear' end
    return nil
end
