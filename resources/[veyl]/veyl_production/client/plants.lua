-- Plants in the world: local props for plants near you (and only those in the place you are: the open world, or the lab you are in),
-- with target options to inspect, water, feed, harvest and remove. Everything is asked of the server, which decides.

local C = ProductionConfig
local B = C.Botanical
local spawned = {}   -- [id] = { entity, stage, state }
local OPTIONS = { 'veyl_prod_inspect', 'veyl_prod_water', 'veyl_prod_feed', 'veyl_prod_harvest', 'veyl_prod_remove' }
local busy = false
local STREAM_IN, STREAM_OUT = 60.0, 80.0

local function modelHash(name)
    local h = joaat(name)
    if not IsModelInCdimage(h) then h = joaat(B.FallbackProp) end
    return h
end

local function make(p)
    local v = ProdUtil.variety(p.variety)
    if not v then return nil end
    local name = v.stages[math.max(1, math.min(#v.stages, p.stage))]
    local hash = modelHash(name)
    RequestModel(hash)
    local deadline = GetGameTimer() + 3000
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(10) end
    if not HasModelLoaded(hash) then return nil end
    local e = CreateObject(hash, p.x, p.y, p.z, false, false, false)
    SetEntityHeading(e, p.heading or 0.0)
    FreezeEntityPosition(e, true)
    SetModelAsNoLongerNeeded(hash)
    return e
end

local function count(item) return exports.veyl_inventory:GetItemCount(item) or 0 end

local function act(id, fn) if busy then return end busy = true CreateThread(function() fn() busy = false end) end

local function tend(id, kind)
    local label = kind == 'water' and 'Watering' or 'Feeding'
    local done = vlib.progress({ label = label, duration = C.ActionMs.Water, canCancel = true, disable = { move = true, car = true, combat = true },
        anim = { dict = 'amb@world_human_gardener_plant@male@base', clip = 'base', flag = 1 } })
    ClearPedTasks(PlayerPedId())
    if not done then return end
    Veyl.NotifyResult(Veyl.CallbackTimeout('veyl_production', 'plantCare', 15000, id, kind))
    ProdClient.refreshWorld()
end

local function options(id)
    return {
        { name = OPTIONS[1], label = 'Inspect plant', icon = 'search', distance = 2.0,
          onSelect = function() act(id, function()
              local r = Veyl.CallbackTimeout('veyl_production', 'plantInspect', 15000, id)
              if not r.ok then return Veyl.NotifyResult(r) end
              local d = r.data
              Veyl.Notify(('%s: %s. Growth %d%%, water %d, nutrients %d, health %d%s'):format(d.label, d.state, math.floor(d.growth * 100), d.water, d.nutrient, d.health,
                  d.minutesLeft > 0 and (', about %d min left'):format(d.minutesLeft) or ''), 'info', 8000)
          end) end },
        { name = OPTIONS[2], label = 'Water', icon = 'droplet', distance = 2.0, canInteract = function() local s = spawned[id] return s and s.state == 'growing' and count(B.WaterItem) > 0 end,
          onSelect = function() act(id, function() tend(id, 'water') end) end },
        { name = OPTIONS[3], label = 'Feed', icon = 'leaf', distance = 2.0, canInteract = function() local s = spawned[id] return s and s.state == 'growing' and count(B.NutrientItem) > 0 end,
          onSelect = function() act(id, function() tend(id, 'nutrient') end) end },
        { name = OPTIONS[4], label = 'Harvest', icon = 'hand', distance = 2.0, canInteract = function() local s = spawned[id] return s and s.state == 'ready' end,
          onSelect = function() act(id, function()
              local done = vlib.progress({ label = 'Harvesting', duration = C.ActionMs.Harvest, canCancel = true, disable = { move = true, car = true, combat = true },
                  anim = { dict = 'amb@world_human_gardener_plant@male@base', clip = 'base', flag = 1 } })
              ClearPedTasks(PlayerPedId())
              if not done then return end
              Veyl.NotifyResult(Veyl.CallbackTimeout('veyl_production', 'plantHarvest', 15000, id))
              ProdClient.refreshWorld()
          end) end },
        { name = OPTIONS[5], label = 'Remove', icon = 'trash', distance = 2.0,
          onSelect = function() act(id, function()
              if vlib.alertDialog({ title = 'Remove this plant?', message = 'It will be destroyed. You may get the planter back.', confirmLabel = 'Remove' }) ~= 'confirm' then return end
              Veyl.NotifyResult(Veyl.CallbackTimeout('veyl_production', 'plantRemove', 15000, id))
              ProdClient.refreshWorld()
          end) end },
    }
end

local function despawn(id)
    local s = spawned[id]
    if not s then return end
    if GetResourceState('veyl_target') == 'started' then pcall(function() exports.veyl_target:removeLocalEntity(s.entity, OPTIONS) end) end
    if DoesEntityExist(s.entity) then DeleteEntity(s.entity) end
    spawned[id] = nil
end

--- Is this plant in the place the player is (the open world, or the lab they are in)?
local function here(p) return (p.property or false) == (ProdClient.inside or false) end

local function sync()
    local pc = GetEntityCoords(PlayerPedId())
    for id, p in pairs(ProdClient.plants) do
        local d = #(pc - vector3(p.x, p.y, p.z))
        local s = spawned[id]
        if s and (not here(p) or d > STREAM_OUT or s.stage ~= p.stage or s.state ~= p.state) then despawn(id) s = nil end
        if not s and here(p) and d <= STREAM_IN then
            local e = make(p)
            if e then
                spawned[id] = { entity = e, stage = p.stage, state = p.state }
                if p.tend and GetResourceState('veyl_target') == 'started' then exports.veyl_target:addLocalEntity(e, options(id)) end
            end
        end
    end
    for id in pairs(spawned) do if not ProdClient.plants[id] then despawn(id) end end
end

function ProdClient.refreshWorld()
    local r = Veyl.CallbackTimeout('veyl_production', 'plantsList', 15000)
    if r.ok then
        ProdClient.plants = {}
        for _, p in ipairs(r.data) do ProdClient.plants[p.id] = p end
        sync()
    end
    local w = Veyl.CallbackTimeout('veyl_production', 'wsList', 15000)
    if w.ok then
        ProdClient.benches = {}
        for _, b in ipairs(w.data) do ProdClient.benches[b.id] = b end
        TriggerEvent('veyl_production:benchesChanged')
    end
end

AddEventHandler('veyl_production:refreshLocal', function() CreateThread(ProdClient.refreshWorld) end)
AddEventHandler('veyl_production:insideChanged', function() sync() end)

CreateThread(function()
    while not Veyl.IsLoaded() do Wait(1000) end
    while GetResourceState('veyl_target') ~= 'started' do Wait(500) end
    ProdClient.refreshWorld()
    local lastPull = GetGameTimer()
    while true do
        Wait(2500)
        sync()
        if GetGameTimer() - lastPull > 60000 then lastPull = GetGameTimer() ProdClient.refreshWorld() end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(spawned) do despawn(id) end
end)
