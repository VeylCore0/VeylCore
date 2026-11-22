-- veyl_gathering client: quarry rocks, farm points, wildlife around hunters and the buyers. Yields come from the server.

local C = GatheringConfig
local function cb(name, ...) return Veyl.CallbackTimeout('veyl_gathering', name, 15000, ...) end

local ANIMS = {
    mining = { dict = 'melee@large_wpn@streamed_core', clip = 'ground_attack_on_spot', prop = 'prop_tool_pickaxe', flag = 1 },
    crop = { scenario = 'WORLD_HUMAN_GARDENER_PLANT' },
    tree = { dict = 'missmechanic', clip = 'work_base', flag = 1 },
    cow = { scenario = 'PROP_HUMAN_BUM_BIN' },
}

local working = false
local function work(kind, index, animKey, label)
    if working then return end
    working = true
    local start = cb('begin', kind, index)
    if not start.ok then working = false return Veyl.NotifyResult(start) end
    local ped, a, prop = PlayerPedId(), ANIMS[animKey], nil
    if a.scenario then
        TaskStartScenarioInPlace(ped, a.scenario, 0, true)
    elseif Veyl.LoadAnimDict(a.dict) then
        TaskPlayAnim(ped, a.dict, a.clip, 3.0, 3.0, -1, a.flag, 0, false, false, false)
        if a.prop then
            local hash = Veyl.LoadModel(a.prop, 3000)
            if hash then
                prop = CreateObject(hash, 0.0, 0.0, 0.0, true, true, false)
                AttachEntityToEntity(prop, ped, GetPedBoneIndex(ped, 57005), 0.10, -0.1, -0.02, 80.0, 0.0, 170.0, true, true, false, true, 1, true)
                SetModelAsNoLongerNeeded(hash)
            end
        end
    end
    local ok = vlib.progress({ label = label, duration = start.data.seconds * 1000, canCancel = true, disable = { move = true, car = true, combat = true } })
    ClearPedTasks(ped)
    if prop then DeleteEntity(prop) end
    if ok then Veyl.NotifyResult(cb('complete', start.data.token)) end
    working = false
end

AddEventHandler('veyl_gathering:mine', function(a) CreateThread(function() work('mining', a.i, 'mining', 'Mining') end) end)
AddEventHandler('veyl_gathering:farm', function(a)
    local p = C.Farming.points[a.i]
    CreateThread(function() work('farming', a.i, p.kind, p.kind == 'cow' and 'Milking' or 'Harvesting') end)
end)

---------------------------------------------------------------------------
-- Buyers
---------------------------------------------------------------------------
AddEventHandler('veyl_gathering:sell', function(a)
    CreateThread(function()
        local res = cb('sellList', a.id)
        if not res.ok then return Veyl.NotifyResult(res) end
        if #res.data == 0 then return Veyl.Notify('You have nothing they want', 'info') end
        local defs = exports.veyl_inventory:Items() or {}
        local items = {}
        for _, r in ipairs(res.data) do
            local label = defs[r.item] and defs[r.item].label or r.item
            items[#items + 1] = { label = ('%s × %d'):format(label, r.count), right = ('$%d each'):format(r.price), value = r.item }
        end
        local pick = Veyl.UI.Menu({ title = 'Sell', subtitle = 'Paid in cash', items = items })
        if not pick then return end
        local have = 0
        for _, r in ipairs(res.data) do if r.item == pick then have = r.count end end
        local v = vlib.inputDialog('How many?', { { name = 'n', label = 'Amount', type = 'number', required = true, min = 1, max = have, default = have } }, { submitLabel = 'Sell' })
        if v then Veyl.NotifyResult(cb('sell', a.id, pick, tonumber(v.n))) end
    end)
end)

---------------------------------------------------------------------------
-- Hunting: wildlife spawns around you in a hunting zone (networked, registered with the server)
---------------------------------------------------------------------------
local mine = {} -- [entity] = model
local function pickModel()
    local total = 0
    for _, a in pairs(C.Hunting.animals) do total = total + a.weight end
    local r = math.random() * total
    for model, a in pairs(C.Hunting.animals) do r = r - a.weight if r <= 0 then return model end end
end

local function zoneAt(pos)
    for _, z in ipairs(C.Hunting.zones) do if #(pos - z.center) <= z.radius then return z end end
end

local function despawn(e)
    if DoesEntityExist(e) then
        local net = NetworkGetNetworkIdFromEntity(e)
        CreateThread(function() cb('releaseAnimal', net) end)
        DeleteEntity(e)
    end
    mine[e] = nil
end

CreateThread(function()
    while true do
        Wait(5000)
        local pc = GetEntityCoords(PlayerPedId())
        local z = LocalPlayer.state.isLoggedIn and zoneAt(pc)
        local count = 0
        for e in pairs(mine) do
            if not DoesEntityExist(e) then mine[e] = nil
            elseif not IsPedDeadOrDying(e, true) and (#(GetEntityCoords(e) - pc) > 250.0 or not z) then despawn(e)
            else count = count + 1 end
        end
        if z and count < C.Hunting.maxAnimals then
            local model = pickModel()
            local hash = Veyl.LoadModel(model, 3000)
            local ang = math.random() * math.pi * 2
            local dist = 70.0 + math.random() * 60.0
            local x, y = pc.x + math.cos(ang) * dist, pc.y + math.sin(ang) * dist
            local found, gz = GetGroundZFor_3dCoord(x, y, pc.z + 100.0, false)
            if hash and found and zoneAt(vector3(x, y, gz)) then
                local e = CreatePed(28, hash, x, y, gz, math.random() * 360.0, true, true)
                SetModelAsNoLongerNeeded(hash)
                local deadline = GetGameTimer() + 2000
                while not NetworkGetEntityIsNetworked(e) and GetGameTimer() < deadline do Wait(50) end
                TaskWanderStandard(e, 10.0, 10)
                local res = cb('registerAnimal', NetworkGetNetworkIdFromEntity(e), model)
                if res.ok then mine[e] = model else DeleteEntity(e) end
            end
        end
    end
end)

local animalHashes = {}
for model in pairs(C.Hunting.animals) do animalHashes[joaat(model)] = true end
local function isAnimal(entity) return animalHashes[GetEntityModel(entity)] == true end

CreateThread(function()
    while GetResourceState('veyl_target') ~= 'started' do Wait(500) end
    exports.veyl_target:addGlobalPed({
        { name = 'veyl_hunt_skin', label = 'Skin animal', icon = 'hand', distance = 2.5, priority = 5,
          canInteract = function(entity) return IsPedDeadOrDying(entity, true) and isAnimal(entity) end,
          onSelect = function(d)
              CreateThread(function()
                  local ped = PlayerPedId()
                  TaskStartScenarioInPlace(ped, 'CODE_HUMAN_MEDIC_TEND_TO_DEAD', 0, true)
                  local ok = vlib.progress({ label = 'Skinning', duration = 6000, canCancel = true, disable = { move = true, car = true, combat = true } })
                  ClearPedTasks(ped)
                  if ok then Veyl.NotifyResult(cb('skin', NetworkGetNetworkIdFromEntity(d.entity))) end
              end)
          end },
    })
end)

---------------------------------------------------------------------------
-- Rock props at the quarry (local objects; hidden while a rock is mined out)
---------------------------------------------------------------------------
local rocks = {} -- [index] = object handle
local rockModel = nil

local function pickRockModel()
    for _, m in ipairs(C.Mining.rockModels or {}) do
        local h = joaat(m)
        if IsModelInCdimage(h) then return h end
    end
end

local function removeRock(i)
    if rocks[i] and DoesEntityExist(rocks[i]) then DeleteEntity(rocks[i]) end
    rocks[i] = nil
end

local function spawnRock(i, pos)
    if rocks[i] or not rockModel then return end
    RequestModel(rockModel)
    local deadline = GetGameTimer() + 3000
    while not HasModelLoaded(rockModel) and GetGameTimer() < deadline do Wait(20) end
    if not HasModelLoaded(rockModel) then return end
    local obj = CreateObject(rockModel, pos.x, pos.y, pos.z - 1.0, false, false, false)
    SetEntityHeading(obj, (i * 47) % 360 + 0.0)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    SetEntityInvincible(obj, true)
    rocks[i] = obj
end

CreateThread(function()
    rockModel = pickRockModel()
    if not rockModel then return print('^3[veyl_gathering] none of Mining.rockModels exist in this game build; no rock props^7') end
    while true do
        local pc = GetEntityCoords(PlayerPedId())
        local near = #(pc - C.Mining.blip.coords) < (C.Mining.rockDrawDistance or 120.0) + 60.0
        for i, s in ipairs(C.Mining.spots) do
            local show = near and not GlobalState['veylRock' .. i] and #(pc - s) < (C.Mining.rockDrawDistance or 120.0)
            if show then spawnRock(i, s) elseif rocks[i] then removeRock(i) end
        end
        if not near then SetModelAsNoLongerNeeded(rockModel) end
        Wait(near and 1000 or 4000)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then for i in pairs(rocks) do removeRock(i) end end
end)

---------------------------------------------------------------------------
-- Zones and blips
---------------------------------------------------------------------------
local function blip(c, sprite, colour, name)
    local b = AddBlipForCoord(c.x, c.y, c.z)
    SetBlipSprite(b, sprite) SetBlipColour(b, colour) SetBlipScale(b, 0.7) SetBlipAsShortRange(b, true)
    BeginTextCommandSetBlipName('STRING') AddTextComponentSubstringPlayerName(name) EndTextCommandSetBlipName(b)
end

CreateThread(function()
    while GetResourceState('veyl_interact') ~= 'started' do Wait(250) end
    for i, s in ipairs(C.Mining.spots) do
        exports.veyl_interact:AddZone({ id = 'veyl_mine_' .. i, coords = s, radius = 2.0, title = 'Rock',
            options = { { label = 'Mine', icon = 'hand', event = 'veyl_gathering:mine', args = { i = i }, canInteract = function() return not GlobalState['veylRock' .. i] end } } })
    end
    blip(C.Mining.blip.coords, C.Mining.blip.sprite, C.Mining.blip.colour, 'Quarry (mining)')
    for i, p in ipairs(C.Farming.points) do
        exports.veyl_interact:AddZone({ id = 'veyl_farm_' .. i, coords = p.coords, radius = 1.8, title = p.label,
            options = { { label = p.kind == 'cow' and 'Milk the cow' or ('Pick %s'):format(p.label:lower()), icon = 'leaf', event = 'veyl_gathering:farm', args = { i = i } } } })
    end
    blip(C.Farming.blip.coords, C.Farming.blip.sprite, C.Farming.blip.colour, 'Farm (harvesting)')
    for _, z in ipairs(C.Hunting.zones) do
        local r = AddBlipForRadius(z.center.x, z.center.y, z.center.z, z.radius)
        SetBlipColour(r, 25) SetBlipAlpha(r, 60)
        blip(z.center, 141, 25, ('Hunting: %s'):format(z.label))
    end
    for _, b in ipairs(C.Buyers) do
        exports.veyl_interact:AddPed({ id = 'veyl_buyer_' .. b.id, model = b.model, coords = b.coords, radius = 2.5, label = b.label, icon = 'money',
            options = { { label = 'Sell', icon = 'money', event = 'veyl_gathering:sell', args = { id = b.id } } } })
        blip(b.coords, b.blip[1], b.blip[2], b.label)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then for e in pairs(mine) do if DoesEntityExist(e) then DeleteEntity(e) end end end
end)
