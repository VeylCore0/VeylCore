-- Placement mode: a ghost preview that follows where you look. Green = valid, red = invalid (with the reason).
-- E place · R / scroll rotate · G ground/pot · Esc or Backspace cancel. Nothing is consumed until the server accepts.

local P = DrugsConfig.Placement
local placing = false

local function rotationToDirection(rot)
    local z, x = math.rad(rot.z), math.rad(rot.x)
    local c = math.abs(math.cos(x))
    return vector3(-math.sin(z) * c, math.cos(z) * c, math.sin(x))
end

--- Ray from the camera; returns hit position and surface normal (or nil).
local function aim(ignore)
    local cam, rot = GetGameplayCamCoord(), GetGameplayCamRot(2)
    local to = cam + rotationToDirection(rot) * (P.MaxDistance + 6.0)
    local ray = StartExpensiveSynchronousShapeTestLosProbe(cam.x, cam.y, cam.z, to.x, to.y, to.z, 1 + 16, ignore, 4)
    local _, hit, pos, normal = GetShapeTestResult(ray)
    if hit ~= 1 then return nil end
    return pos, normal
end

local function restricted(pos)
    for _, z in ipairs(DrugsConfig.RestrictedZones) do
        if #(pos - z.coords) <= z.radius then return z.label end
    end
end

local function tooClose(pos)
    for _, p in pairs(DrugsClient.known) do
        if #(pos - vector3(p.x, p.y, p.z)) < P.MinSpacing then return true end
    end
    return false
end

local function count(item) return exports.veyl_inventory:GetItemCount(item) or 0 end

--- Why this spot is not valid (or nil when it is).
local function problem(ped, pos, normal, container, ghost)
    if not pos then return 'Aim at the ground' end
    if #(GetEntityCoords(ped) - pos) > P.MaxDistance then return 'Too far' end
    local slope = math.deg(math.acos(math.max(-1.0, math.min(1.0, normal.z))))
    if slope > P.MaxSlopeDegrees then return 'Too steep' end
    local zone = restricted(pos)
    if zone then return 'Too close to ' .. zone end
    local interior = GetInteriorAtCoords(pos.x, pos.y, pos.z)
    if interior ~= 0 then
        if not P.AllowInteriors then return 'Cannot grow indoors here' end
        if container == 'ground' and P.RequirePotIndoors then return 'Use a pot indoors' end
    end
    if tooClose(pos) then return 'Too close to another plant' end
    if IsPositionOccupied(pos.x, pos.y, pos.z + 0.3, 0.45, false, true, true, true, false, ghost, false) then return 'Something is in the way' end
    return nil
end

local function ghostModel(product, container)
    local prod = DrugsProducts[product]
    local list = prod.props[container] or prod.props.ground
    local name = list[1]
    local hash = joaat(name)
    if not IsModelInCdimage(hash) then hash = joaat(DrugsFallbackProp) end
    RequestModel(hash)
    local deadline = GetGameTimer() + 3000
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(10) end
    return hash
end

local function guardPause()
    local untilAt = GetGameTimer() + 700
    CreateThread(function()
        while GetGameTimer() < untilAt do
            DisableControlAction(0, 199, true) DisableControlAction(0, 200, true) DisableControlAction(0, 322, true)
            Wait(0)
        end
    end)
end

local function begin(data)
    if placing then return end
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then return Veyl.Notify('Get out of the vehicle first', 'error') end
    if exports.veyl_lib:IsModalOpen() then return end
    local prod = DrugsProducts[data.product]
    local variety = prod and prod.varieties[data.variety]
    if not variety then return end

    local containers = {}
    for _, c in ipairs(prod.containers) do
        if c == 'ground' or (c == 'pot' and count('plant_pot') > 0) or (c == 'tub' and count(prod.tubItem) > 0) then containers[#containers + 1] = c end
    end
    if #containers == 0 then
        local def = prod.tubItem and exports.veyl_inventory:GetItemDefinition(prod.tubItem)
        return Veyl.Notify(('You need a %s'):format(def and def.label or 'container'), 'error')
    end
    local ci = 1
    placing = true

    local hash = ghostModel(data.product, containers[ci])
    local ghost = CreateObject(hash, 0.0, 0.0, 0.0, false, false, false)
    SetEntityAlpha(ghost, 170, false)
    SetEntityCollision(ghost, false, false)
    FreezeEntityPosition(ghost, true)
    SetEntityDrawOutline(ghost, true)
    local heading = GetEntityHeading(ped)
    local confirmed, last = nil, nil

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
        local why = problem(ped, pos, normal, containers[ci], ghost)
        if why then SetEntityDrawOutlineColor(239, 143, 150, 255) else SetEntityDrawOutlineColor(152, 211, 174, 255) end
        local state = { visible = true, valid = why == nil, reason = why, label = variety.label, product = prod.label,
            container = containers[ci], canToggle = #containers > 1 }
        if not last or last.valid ~= state.valid or last.reason ~= state.reason or last.container ~= state.container then
            DrugsUI.Placement(state)
            last = state
        end
        if IsDisabledControlJustPressed(0, 45) or IsDisabledControlJustPressed(0, 15) then heading = (heading + P.RotateStep) % 360 end
        if IsDisabledControlJustPressed(0, 14) then heading = (heading - P.RotateStep) % 360 end
        if IsDisabledControlPressed(0, 45) then heading = (heading + 1.5) % 360 end
        if IsDisabledControlJustPressed(0, 47) and #containers > 1 then
            ci = ci % #containers + 1
            local newHash = ghostModel(data.product, containers[ci])
            DeleteEntity(ghost)
            ghost = CreateObject(newHash, 0.0, 0.0, 0.0, false, false, false)
            SetEntityAlpha(ghost, 170, false)
            SetEntityCollision(ghost, false, false)
            FreezeEntityPosition(ghost, true)
            SetEntityDrawOutline(ghost, true)
        end
        if IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 322)
            or IsPedInAnyVehicle(ped, false) or IsEntityDead(ped) then
            placing = false
            guardPause()
        elseif IsControlJustPressed(0, 38) and not why then
            confirmed = { pos = pos, heading = heading, container = containers[ci] }
            placing = false
        end
    end
    SetEntityDrawOutline(ghost, false)
    DeleteEntity(ghost)
    SetModelAsNoLongerNeeded(hash)
    DrugsUI.Placement({ visible = false })
    if not confirmed then return Veyl.Notify('Placement cancelled', 'info') end

    local done = vlib.progress({ label = 'Planting', duration = DrugsConfig.ActionMs.place, canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = { dict = 'amb@world_human_gardener_plant@male@base', clip = 'base', flag = 1 } })
    ClearPedTasks(ped)
    if not done then return Veyl.Notify('Placement cancelled', 'info') end
    local c = confirmed.pos
    local res = Veyl.CallbackTimeout('veyl_drugs', 'place', 20000, {
        opId = ('%08x%06x%06x'):format(GetGameTimer() % 0xffffffff, math.random(0, 0xffffff), math.random(0, 0xffffff)),
        item = data.item, variety = data.variety, container = confirmed.container,
        x = c.x, y = c.y, z = c.z, heading = confirmed.heading, interior = GetInteriorAtCoords(c.x, c.y, c.z),
    })
    Veyl.NotifyResult(res)
    if res.ok then DrugsClient.Refresh() end
end

RegisterNetEvent('veyl_drugs:beginPlacement', function(data) CreateThread(function() begin(data) end) end)

AddEventHandler('onResourceStop', function(res) if res == GetCurrentResourceName() then placing = false end end)
