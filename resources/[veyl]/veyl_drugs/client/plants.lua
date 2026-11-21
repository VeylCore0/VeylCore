-- Plant streaming, props, target options and timed actions. The server decides everything; this file only shows
-- what the server reported for plants near you.

local known = {}    -- [id] = stream view { id, type, container, stage, x, y, z, h, ready, own }
local spawned = {}  -- [id] = { entities = {...}, main = entity, stage }
local lastFetchPos, lastFetchAt = nil, 0
local missingWarned = {}

DrugsClient = { known = known }

local function modelFor(name)
    local hash = joaat(name)
    if IsModelInCdimage(hash) then return hash end
    if not missingWarned[name] then
        missingWarned[name] = true
        print(('^3[veyl_drugs] prop %s is not in this game build; using %s^7'):format(name, DrugsFallbackProp))
    end
    return joaat(DrugsFallbackProp)
end

local function load(hash)
    RequestModel(hash)
    local deadline = GetGameTimer() + 3000
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(10) end
    return HasModelLoaded(hash)
end

local function makeObject(name, x, y, z, h)
    local hash = modelFor(name)
    if not load(hash) then return nil end
    local e = CreateObject(hash, x, y, z, false, false, false)
    SetEntityHeading(e, h or 0.0)
    FreezeEntityPosition(e, true)
    SetModelAsNoLongerNeeded(hash)
    return e
end

local OPTION_NAMES = { 'veyl_drugs_inspect', 'veyl_drugs_water', 'veyl_drugs_care', 'veyl_drugs_harvest', 'veyl_drugs_destroy' }

local function despawn(id)
    local s = spawned[id]
    if not s then return end
    if s.main and GetResourceState('veyl_target') == 'started' then exports.veyl_target:removeLocalEntity(s.main, OPTION_NAMES) end
    for _, e in ipairs(s.entities) do if DoesEntityExist(e) then DeleteEntity(e) end end
    spawned[id] = nil
end

local function hasItem(item) return (exports.veyl_inventory:GetItemCount(item) or 0) > 0 end

local function targetOptions(id)
    local function k() return known[id] end
    return {
        { name = 'veyl_drugs_inspect', label = 'Inspect plant', icon = 'inspect', distance = DrugsConfig.InteractDistance,
          onSelect = function() CreateThread(function() DrugsClient.Inspect(id) end) end },
        { name = 'veyl_drugs_water', label = 'Water', icon = 'drop', distance = DrugsConfig.InteractDistance,
          canInteract = function() return k() and k().own and hasItem(DrugsConfig.CareItems.water) end,
          onSelect = function() CreateThread(function() DrugsClient.Action(id, 'water') end) end },
        { name = 'veyl_drugs_care', label = 'Add nutrients', icon = 'heart', distance = DrugsConfig.InteractDistance,
          canInteract = function() return k() and k().own and hasItem(DrugsConfig.CareItems.care) end,
          onSelect = function() CreateThread(function() DrugsClient.Action(id, 'care') end) end },
        { name = 'veyl_drugs_harvest', label = 'Harvest', icon = 'hand', distance = DrugsConfig.InteractDistance,
          canInteract = function() return k() and k().own and k().ready end,
          onSelect = function() CreateThread(function() DrugsClient.Action(id, 'harvest') end) end },
        { name = 'veyl_drugs_destroy', label = 'Remove plant', icon = 'close', distance = DrugsConfig.InteractDistance,
          canInteract = function() return k() and k().own end,
          onSelect = function() CreateThread(function() DrugsClient.Destroy(id) end) end },
    }
end

local function spawn(p)
    local prod = DrugsProducts[p.type]
    if not prod then return end
    local stages = prod.props[p.container] or prod.props.ground
    local entities, main = {}, nil
    if p.container == 'pot' and prod.potProp then
        entities[#entities + 1] = makeObject(prod.potProp, p.x, p.y, p.z, p.h)
    end
    main = makeObject(stages[math.max(1, math.min(4, p.stage))], p.x, p.y, p.z, p.h)
    entities[#entities + 1] = main
    if p.container == 'tub' and prod.stageProps and prod.stageProps[p.stage] then
        local e = makeObject(prod.stageProps[p.stage], p.x, p.y, p.z + 0.35, p.h)
        if e then SetEntityCollision(e, false, false) entities[#entities + 1] = e end
    end
    if not main then
        for _, e in ipairs(entities) do if e and DoesEntityExist(e) then DeleteEntity(e) end end
        return
    end
    spawned[p.id] = { entities = entities, main = main, stage = p.stage }
    if GetResourceState('veyl_target') == 'started' then exports.veyl_target:addLocalEntity(main, targetOptions(p.id)) end
end

--- Server pushed a change near us (stage, ready, ownership view).
RegisterNetEvent('veyl_drugs:plantUpdated', function(p)
    known[p.id] = p
    if spawned[p.id] and spawned[p.id].stage ~= p.stage then despawn(p.id) end
end)
RegisterNetEvent('veyl_drugs:plantRemoved', function(id)
    known[id] = nil
    despawn(id)
    DrugsClient.HideCardFor(id)
end)

function DrugsClient.Refresh()
    local res = Veyl.Callback('veyl_drugs', 'nearby')
    if not res.ok then return end
    local seen = {}
    for _, p in ipairs(res.data) do
        seen[p.id] = true
        known[p.id] = p
        if spawned[p.id] and spawned[p.id].stage ~= p.stage then despawn(p.id) end
    end
    for id in pairs(known) do if not seen[id] then known[id] = nil despawn(id) end end
    lastFetchPos, lastFetchAt = GetEntityCoords(PlayerPedId()), GetGameTimer()
end

-- Fetch when you've moved or every 20 s; spawn/despawn props by distance every second.
CreateThread(function()
    while true do
        if Veyl.IsLoaded() then
            local pos = GetEntityCoords(PlayerPedId())
            if not lastFetchPos or #(pos - lastFetchPos) > DrugsConfig.Stream.MoveThreshold or GetGameTimer() - lastFetchAt > 20000 then
                DrugsClient.Refresh()
            end
            for id, p in pairs(known) do
                local near = #(pos - vector3(p.x, p.y, p.z)) <= DrugsConfig.Stream.SpawnRadius
                if near and not spawned[id] then spawn(p) elseif not near and spawned[id] then despawn(id) end
            end
        end
        Wait(1000)
    end
end)

RegisterNetEvent('VeylCore:Client:OnPlayerUnload', function()
    for id in pairs(spawned) do despawn(id) end
    for id in pairs(known) do known[id] = nil end
    lastFetchPos = nil
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(spawned) do despawn(id) end
end)

---------------------------------------------------------------------------
-- Plant card (passive): shown after Inspect / actions, hidden when you walk away
---------------------------------------------------------------------------
local card = nil -- { id, until }

function DrugsClient.ShowCard(view)
    card = { id = view.id, untilAt = GetGameTimer() + 15000 }
    DrugsUI.Card(view)
end

function DrugsClient.HideCardFor(id)
    if card and card.id == id then card = nil DrugsUI.Card(nil) end
end

CreateThread(function()
    while true do
        if card then
            local p = known[card.id]
            local far = not p or #(GetEntityCoords(PlayerPedId()) - vector3(p.x, p.y, p.z)) > 5.0
            if far or GetGameTimer() > card.untilAt or DrugsUI.IsOpen() then card = nil DrugsUI.Card(nil) end
            Wait(300)
        else
            Wait(800)
        end
    end
end)

function DrugsClient.Inspect(id)
    local res = Veyl.Callback('veyl_drugs', 'inspect', id)
    if not res.ok then return Veyl.NotifyResult(res) end
    DrugsClient.ShowCard(res.data)
end

---------------------------------------------------------------------------
-- Timed actions
---------------------------------------------------------------------------
local ANIMS = {
    water = { anim = { dict = 'weapon@w_sp_jerrycan', clip = 'fire', flag = 1 },
              prop = { model = 'prop_wateringcan', bone = 28422, pos = vec3(0.4, 0.1, 0.0), rot = vec3(90.0, 180.0, 0.0) }, label = 'Watering' },
    care = { anim = { dict = 'amb@world_human_gardener_plant@male@base', clip = 'base', flag = 1 }, label = 'Adding nutrients' },
    harvest = { anim = { dict = 'amb@world_human_gardener_plant@male@base', clip = 'base', flag = 1 },
                prop = { model = 'prop_cs_scissors', bone = 28422, pos = vec3(0.0, 0.0, 0.0), rot = vec3(0.0, 0.0, 0.0) }, label = 'Harvesting' },
    destroy = { anim = { dict = 'amb@world_human_gardener_plant@male@base', clip = 'base', flag = 1 }, label = 'Pulling it out' },
}

local busy = false

function DrugsClient.Action(id, kind)
    if busy then return end
    busy = true
    local p = known[id]
    local start = Veyl.Callback('veyl_drugs', 'actionStart', id, kind)
    if not start.ok then busy = false return Veyl.NotifyResult(start) end
    if p then TaskTurnPedToFaceCoord(PlayerPedId(), p.x, p.y, p.z, 600) Wait(600) end
    local a = ANIMS[kind]
    local done = vlib.progress({ label = a.label, duration = start.data.durationMs, canCancel = true,
        disable = { move = true, car = true, combat = true }, anim = a.anim, prop = a.prop })
    if done then
        local res = Veyl.Callback('veyl_drugs', 'actionComplete', start.data.token)
        Veyl.NotifyResult(res)
        if res.ok and res.data and res.data.id then DrugsClient.ShowCard(res.data) end
    else
        Veyl.Callback('veyl_drugs', 'actionCancel', start.data.token)
    end
    ClearPedTasks(PlayerPedId())
    busy = false
end

function DrugsClient.Destroy(id)
    if vlib.alertDialog({ title = 'Remove this plant?', message = 'It will be destroyed and nothing is returned.', confirmLabel = 'Remove',
        destructive = true }) ~= 'confirm' then return end
    DrugsClient.Action(id, 'destroy')
end
