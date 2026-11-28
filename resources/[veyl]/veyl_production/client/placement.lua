-- Placement preview for plants and workstations: a ghost follows where you look (green = ok, red = not, with the reason).
-- E place, scroll / R rotate, Esc or Backspace cancel. Nothing is consumed until the server accepts the placement.

local C = ProductionConfig
local P = C.Placement
local placing = false

local function rotationToDirection(rot)
    local z, x = math.rad(rot.z), math.rad(rot.x)
    local c = math.abs(math.cos(x))
    return vector3(-math.sin(z) * c, math.cos(z) * c, math.sin(x))
end

local function aim(ignore)
    local cam, rot = GetGameplayCamCoord(), GetGameplayCamRot(2)
    local to = cam + rotationToDirection(rot) * (P.MaxDistance + 6.0)
    local ray = StartExpensiveSynchronousShapeTestLosProbe(cam.x, cam.y, cam.z, to.x, to.y, to.z, 1 + 16, ignore, 4)
    local _, hit, pos, normal = GetShapeTestResult(ray)
    if hit ~= 1 then return nil end
    return pos, normal
end

local function loadModel(name)
    local hash = joaat(name)
    if not IsModelInCdimage(hash) then hash = joaat(C.Botanical.FallbackProp) end
    RequestModel(hash)
    local deadline = GetGameTimer() + 3000
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(10) end
    return hash
end

--- Why this spot cannot be used (client-side hints only; the server checks again).
local function problem(ped, pos, normal, data, ghost)
    if not pos then return 'Aim at the ground' end
    if #(GetEntityCoords(ped) - pos) > P.MaxDistance then return 'Too far' end
    local slope = math.deg(math.acos(math.max(-1.0, math.min(1.0, normal.z))))
    if slope > P.MaxSlopeDegrees then return 'Too steep' end
    if data.property then
        local interior = ProdClient.interior
        if interior and #(pos - vector3(interior.spawn.x, interior.spawn.y, interior.spawn.z)) > interior.radius then return 'Outside the laboratory' end
    else
        for _, z in ipairs(P.RestrictedZones) do if #(pos - z.coords) <= z.radius then return 'Too close to ' .. z.label end end
        if GetInteriorAtCoords(pos.x, pos.y, pos.z) ~= 0 and not P.AllowInteriors then return 'Not indoors here' end
    end
    for _, list in ipairs({ ProdClient.plants, ProdClient.benches }) do
        for _, o in pairs(list) do
            if (o.property or false) == (data.property or false) and #(pos - vector3(o.x, o.y, o.z)) < P.MinSpacing then return 'Too close to something else' end
        end
    end
    if IsPositionOccupied(pos.x, pos.y, pos.z + 0.3, 0.45, false, true, true, true, false, ghost, false) then return 'Something is in the way' end
    return nil
end

local function overlay(state) SendNUIMessage({ action = 'production:placement', data = state }) end

local function begin(data)
    if placing then return end
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return Veyl.Notify('Get out of the vehicle first', 'error') end
    local model, label
    if data.kind == 'plant' then
        local v = ProdUtil.variety(data.variety)
        if not v then return end
        model, label = v.stages[2] or v.stages[1], v.label
    else
        local t = C.Workstations.Types[data.type]
        if not t then return end
        model, label = t.model, t.label
    end
    placing = true
    local hash = loadModel(model)
    local ghost = CreateObject(hash, 0.0, 0.0, 0.0, false, false, false)
    SetEntityAlpha(ghost, 170, false)
    SetEntityCollision(ghost, false, false)
    FreezeEntityPosition(ghost, true)
    SetEntityDrawOutline(ghost, true)
    local heading = GetEntityHeading(ped)
    local confirmed, last
    while placing do
        Wait(0)
        for _, c in ipairs({ 24, 25, 37, 44, 45, 47, 140, 141, 142, 257, 263, 14, 15, 16, 17, 199, 200, 322, 177 }) do DisableControlAction(0, c, true) end
        local pos, normal = aim(ghost)
        if pos then
            SetEntityCoordsNoOffset(ghost, pos.x, pos.y, pos.z, false, false, false)
            SetEntityHeading(ghost, heading)
            SetEntityVisible(ghost, true, false)
        else
            SetEntityVisible(ghost, false, false)
        end
        local why = problem(ped, pos, normal, data, ghost)
        if why then SetEntityDrawOutlineColor(239, 143, 150, 255) else SetEntityDrawOutlineColor(152, 211, 174, 255) end
        if not last or last.reason ~= why then last = { reason = why } overlay({ visible = true, valid = why == nil, reason = why, label = label }) end
        if IsDisabledControlJustPressed(0, 45) or IsDisabledControlJustPressed(0, 15) then heading = (heading + P.RotateStep) % 360 end
        if IsDisabledControlJustPressed(0, 14) then heading = (heading - P.RotateStep) % 360 end
        if IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 322) or IsEntityDead(ped) or IsPedInAnyVehicle(ped, false) then
            placing = false
        elseif IsControlJustReleased(0, 38) and not why then
            confirmed = { pos = pos, heading = heading }
            placing = false
        end
    end
    DeleteEntity(ghost)
    SetModelAsNoLongerNeeded(hash)
    overlay({ visible = false })
    if not confirmed then return Veyl.Notify('Placement cancelled', 'info') end

    local done = vlib.progress({ label = data.kind == 'plant' and 'Planting' or 'Setting up', duration = C.ActionMs.Place, canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = data.kind == 'plant' and { dict = 'amb@world_human_gardener_plant@male@base', clip = 'base', flag = 1 } or { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 1 } })
    ClearPedTasks(ped)
    if not done then return Veyl.Notify('Placement cancelled', 'info') end
    local c = confirmed.pos
    local req = { x = c.x, y = c.y, z = c.z, heading = confirmed.heading, property = data.property }
    local res
    if data.kind == 'plant' then
        req.variety = data.variety
        res = Veyl.CallbackTimeout('veyl_production', 'plantPlace', 20000, req)
    else
        req.type = data.type
        res = Veyl.CallbackTimeout('veyl_production', 'wsPlace', 20000, req)
    end
    Veyl.NotifyResult(res)
end

RegisterNetEvent('veyl_production:beginPlacement', function(data) CreateThread(function() begin(data) end) end)
AddEventHandler('onResourceStop', function(res) if res == GetCurrentResourceName() then placing = false end end)
