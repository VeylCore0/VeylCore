-- Furniture on the client: local (non-networked) props per room, and the placement editor. Teleport mode shows a
-- home's furniture to the people inside it; walk-in mode streams every leased room's furniture to players near the motel. Positions are LOCAL to the room; the same AptGeometry checks run here (preview) and on the server (final say).

AptFurnitureClient = {}
local rooms = {}     -- [unit] = { spawned = { [id] = entity }, current = { [id] = { id, item, model, x, y, z, heading } } }
local editing = false

local function loadModel(name)
    local hash = joaat(name)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local deadline = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(10) end
    return HasModelLoaded(hash) and hash or nil
end

local function worldOf(unit, f)
    return AptGeometry.ToWorld(unit, vector3(f.x, f.y, f.z)), (unit.yaw + f.heading) % 360.0
end

local function room(unit)
    rooms[unit] = rooms[unit] or { spawned = {}, current = {} }
    return rooms[unit]
end

--- Removes one room's props, or every room's when no unit is given.
function AptFurnitureClient.Clear(unit)
    for u, r in pairs(rooms) do
        if not unit or u == unit then
            for id, e in pairs(r.spawned) do if DoesEntityExist(e) then DeleteEntity(e) end end
            rooms[u] = nil
        end
    end
end

function AptFurnitureClient.Loaded(unit) return rooms[unit] ~= nil end

--- Replaces the room's furniture with the given list (idempotent: same list -> same props, no duplicates).
function AptFurnitureClient.Load(unit, list)
    local r = room(unit)
    local spawned = r.spawned
    local keep = {}
    for _, f in ipairs(list or {}) do keep[f.id] = f end
    for id, e in pairs(spawned) do
        local f, old = keep[id], r.current[id]
        if not f or not old or f.x ~= old.x or f.y ~= old.y or f.z ~= old.z or f.heading ~= old.heading then
            if DoesEntityExist(e) then DeleteEntity(e) end
            spawned[id] = nil
        end
    end
    r.current = keep
    CreateThread(function()
        for id, f in pairs(keep) do
            if not spawned[id] and f.model then
                local hash = loadModel(f.model)
                if hash and rooms[unit] == r and r.current[id] == f and not spawned[id] then
                    local pos, heading = worldOf(unit, f)
                    local e = CreateObjectNoOffset(hash, pos.x, pos.y, pos.z, false, false, false)
                    SetEntityHeading(e, heading)
                    FreezeEntityPosition(e, true)
                    spawned[id] = e
                    SetModelAsNoLongerNeeded(hash)
                end
            end
        end
    end)
end

function AptFurnitureClient.Placed(unit) return rooms[unit] and rooms[unit].current or {} end

---------------------------------------------------------------------------
-- Placement editor
---------------------------------------------------------------------------
local function rotationToDirection(rot)
    local z, x = math.rad(rot.z), math.rad(rot.x)
    local c = math.abs(math.cos(x))
    return vector3(-math.sin(z) * c, math.cos(z) * c, math.sin(x))
end

local function aim(ignore)
    local cam, rot = GetGameplayCamCoord(), GetGameplayCamRot(2)
    local to = cam + rotationToDirection(rot) * 12.0
    local ray = StartExpensiveSynchronousShapeTestLosProbe(cam.x, cam.y, cam.z, to.x, to.y, to.z, 1 + 16, ignore, 4)
    local _, hit, pos = GetShapeTestResult(ray)
    if hit ~= 1 then return nil end
    return pos
end

local function problem(current, l, heading, ignoreId)
    local why = AptGeometry.FurnitureProblem(l, heading)
    if why then return why end
    for id, f in pairs(current) do
        if id ~= ignoreId then
            local d = #(vector3(f.x, f.y, f.z) - l)
            if d < AptConfig.Furniture.MinSpacing then return 'Too close to another piece' end
        end
    end
    return nil
end

local function opId() return ('%08x%06x%06x'):format(GetGameTimer() % 0xffffffff, math.random(0, 0xffffff), math.random(0, 0xffffff)) end

--- data = { item = key } (buy), { id = n } (place a stored piece) or { move = id } (reposition a placed piece)
local function begin(data)
    if editing then return end
    local ctx = AptClient.context
    if not ctx or ctx.kind ~= 'home' or not ctx.perms.furniture or not ctx.unit then return Veyl.Notify('You need to be inside your home', 'error') end
    local unit = ctx.unit
    local r = room(unit)
    local current, spawned = r.current, r.spawned
    local def = data.item and AptFurniture[data.item]
    local model = def and def.model or data.model
    local moving = data.move and current[data.move]
    if moving then model = moving.model end
    if not model then return end
    local hash = loadModel(model)
    if not hash then return Veyl.Notify('That item is not available on this game version', 'error') end
    editing = true
    if moving and spawned[data.move] then SetEntityVisible(spawned[data.move], false, false) end
    local ghost = CreateObjectNoOffset(hash, 0.0, 0.0, 0.0, false, false, false)
    SetEntityAlpha(ghost, 170, false)
    SetEntityCollision(ghost, false, false)
    FreezeEntityPosition(ghost, true)
    SetEntityDrawOutline(ghost, true)

    local ped = PlayerPedId()
    local l
    if moving then l = vector3(moving.x, moving.y, moving.z)
    else
        local fwd = GetEntityCoords(ped) + GetEntityForwardVector(ped) * 1.4
        local lp = AptGeometry.ToLocal(unit, fwd)
        l = vector3(lp.x, lp.y, AptGeometry.FloorZ)
    end
    local heading = moving and moving.heading or 0.0
    local followAim = not moving
    local confirmed, last
    local label = def and def.label or (moving and moving.item and AptFurniture[moving.item] and AptFurniture[moving.item].label) or 'Furniture'

    while editing do
        Wait(0)
        for _, c in ipairs({ 24, 25, 37, 38, 44, 45, 46, 47, 51, 140, 141, 142, 257, 263, 14, 15, 16, 17, 172, 173, 174, 175, 10, 11, 199, 200, 322, 177, 191, 201 }) do DisableControlAction(0, c, true) end
        local fine = IsControlPressed(0, 21) -- Shift: fine steps
        local step, rstep = fine and 0.01 or 0.05, fine and 1.0 or 5.0
        -- Arrow keys move along the room's own axes; any arrow press switches off "follow aim" (G turns it back on).
        local dx, dy = 0.0, 0.0
        if IsDisabledControlPressed(0, 172) then dx = dx + step end
        if IsDisabledControlPressed(0, 173) then dx = dx - step end
        if IsDisabledControlPressed(0, 174) then dy = dy + step end
        if IsDisabledControlPressed(0, 175) then dy = dy - step end
        if dx ~= 0 or dy ~= 0 then followAim = false l = vector3(l.x + dx, l.y + dy, l.z) end
        if IsDisabledControlJustPressed(0, 47) then followAim = not followAim end
        if followAim then
            local hit = aim(ghost)
            if hit then local lp = AptGeometry.ToLocal(unit, hit) l = vector3(lp.x, lp.y, l.z) end
        end
        if IsDisabledControlPressed(0, 10) then l = vector3(l.x, l.y, math.min(AptGeometry.FloorZ + AptGeometry.MaxFurnitureHeight, l.z + step * 0.5)) end
        if IsDisabledControlPressed(0, 11) then l = vector3(l.x, l.y, math.max(AptGeometry.FloorZ, l.z - step * 0.5)) end
        -- Rotate: mouse wheel (5 deg, Shift 1 deg) or hold Q / E.
        if IsDisabledControlJustPressed(0, 15) then heading = (heading + rstep) % 360 end
        if IsDisabledControlJustPressed(0, 14) then heading = (heading - rstep) % 360 end
        if IsDisabledControlPressed(0, 44) then heading = heading - (fine and 0.5 or 2.0) end
        if IsDisabledControlPressed(0, 38) then heading = heading + (fine and 0.5 or 2.0) end
        heading = heading % 360
        if heading < 0 then heading = heading + 360.0 end
        local pos, wh = worldOf(unit, { x = l.x, y = l.y, z = l.z, heading = heading })
        SetEntityCoordsNoOffset(ghost, pos.x, pos.y, pos.z, false, false, false)
        SetEntityHeading(ghost, wh)
        local why = problem(r.current, l, heading, moving and moving.id or nil)
        if why then SetEntityDrawOutlineColor(239, 143, 150, 255) else SetEntityDrawOutlineColor(152, 211, 174, 255) end
        if not last or last.reason ~= why then
            AptUI.Passive('apt:placement', { visible = true, valid = why == nil, reason = why, label = label, price = def and def.price or nil, moving = moving ~= nil })
            last = { reason = why }
        end
        if IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 322) or IsEntityDead(ped)
            or not AptClient.context then
            editing = false
        elseif IsDisabledControlJustPressed(0, 191) or IsDisabledControlJustPressed(0, 201) then
            if why then Veyl.Notify(why, 'error') else confirmed = { x = l.x, y = l.y, z = l.z, heading = heading } editing = false end
        end
    end
    -- Swallow the pause menu for a moment after Escape.
    local untilAt = GetGameTimer() + 700
    CreateThread(function() while GetGameTimer() < untilAt do DisableControlAction(0, 199, true) DisableControlAction(0, 200, true) DisableControlAction(0, 322, true) Wait(0) end end)
    SetEntityDrawOutline(ghost, false)
    DeleteEntity(ghost)
    SetModelAsNoLongerNeeded(hash)
    AptUI.Passive('apt:placement', { visible = false })
    if moving and spawned[data.move] and DoesEntityExist(spawned[data.move]) then SetEntityVisible(spawned[data.move], true, false) end
    if not confirmed then return Veyl.Notify('Placement cancelled. Nothing was charged.', 'info') end
    local res
    if moving then
        res = Veyl.CallbackTimeout('veyl_apartments', 'furnitureMove', 15000, data.move, confirmed)
    else
        confirmed.item, confirmed.id, confirmed.clientOp = data.item, data.id, opId()
        res = Veyl.CallbackTimeout('veyl_apartments', 'furniturePlace', 20000, confirmed)
    end
    Veyl.NotifyResult(res)
end

AddEventHandler('veyl_apartments:beginPlacement', function(data) if type(data) == 'table' then CreateThread(function() begin(data) end) end end)

AddEventHandler('veyl_apartments:furnitureMenu', function()
    CreateThread(function()
        local res = Veyl.Callback('veyl_apartments', 'furnitureCatalog')
        if not res.ok then return Veyl.NotifyResult(res) end
        local placed = {}
        local ctx = AptClient.context
        for _, f in pairs(ctx and ctx.unit and AptFurnitureClient.Placed(ctx.unit) or {}) do placed[#placed + 1] = f end
        table.sort(placed, function(a, b) return a.id < b.id end)
        res.data.placedList = placed
        -- Which models exist on this client's game build (the catalog greys out the rest).
        local missing = {}
        for _, it in ipairs(res.data.items) do if not IsModelInCdimage(joaat(it.model)) then missing[#missing + 1] = it.key end end
        res.data.missing = missing
        AptUI.Open('furniture', res.data)
    end)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    editing = false
    AptFurnitureClient.Clear()
end)
