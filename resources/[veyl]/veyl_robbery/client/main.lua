-- veyl_robbery client: target zones (hold ALT, aim at the counter) on every robbable store's register and safe.
-- Target zones are separate from the clerk's "Shop" prompt, so both work at the same counter.

local C = RobberyConfig

--- Lockpick mini game (veyl_minigames). Returns true on success; without the resource it always succeeds.
local function minigame(difficulty, title)
    if GetResourceState('veyl_minigames') ~= 'started' then return true end
    local p = promise.new()
    exports.veyl_minigames:Lockpick({ difficulty = difficulty, title = title }, function(ok) p:resolve(ok) end)
    return Citizen.Await(p) == true
end

local busy = false
local function rob(store, kind, till)
    if busy then return end
    busy = true
    do
        local cfg = kind == 'safe' and C.Safe or C.Register
        local ped = PlayerPedId()
        if Veyl.LoadAnimDict('mp_arresting') then TaskPlayAnim(ped, 'mp_arresting', 'a_uncuff', 3.0, 3.0, -1, 49, 0, false, false, false) end
        local ok = minigame(cfg.difficulty, kind == 'safe' and 'Crack the safe' or 'Pick the till')
        ClearPedTasks(ped)
        if not ok then
            Veyl.NotifyResult(Veyl.Callback('veyl_robbery', 'pickFailed', store, kind))
            busy = false
            return
        end
    end
    local start = Veyl.CallbackTimeout('veyl_robbery', 'start', 10000, store, kind, till and { x = till.x, y = till.y, z = till.z } or nil)
    if not start.ok then busy = false return Veyl.NotifyResult(start) end
    local ped = PlayerPedId()
    -- Another progress bar may still be finishing: wait for it instead of failing straight away.
    local waitUntil = GetGameTimer() + 3000
    while vlib.progressActive() and GetGameTimer() < waitUntil do Wait(100) end
    local done = vlib.progress({
        label = kind == 'safe' and 'Opening the safe' or 'Emptying the register', duration = start.data.seconds * 1000 + 300, canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = kind == 'safe' and { dict = 'mini@safe_cracking', clip = 'dial_turn_anti_fast_1', flag = 1 }
            or { dict = 'oddjobs@shop_robbery@rob_till', clip = 'loop', flag = 1 },
    })
    ClearPedTasks(ped)
    busy = false
    if not done then
        Veyl.Callback('veyl_robbery', 'cancel')
        return Veyl.Notify('You stopped (X cancels). The alarm was already raised.', 'warning')
    end
    local res = Veyl.CallbackTimeout('veyl_robbery', 'finish', 10000, start.data.token)
    if res.ok then PlaySoundFrontend(-1, 'ROBBERY_MONEY_TOTAL', 'HUD_FRONTEND_CUSTOM_SOUNDSET', true) end
    Veyl.NotifyResult(res)
end

local zones = {}
local storeList = {}
local tillHashes = {}
for _, m in ipairs(C.TillModels or {}) do tillHashes[#tillHashes + 1] = joaat(m) end

--- The robbable store a till belongs to (nearest store counter within 12 m).
local function storeForTill(pos)
    local best, bd = nil, 12.0
    for _, s in ipairs(storeList) do
        local d = #(pos - vector3(s.register.x, s.register.y, s.register.z))
        if d < bd then best, bd = s.id, d end
    end
    return best
end

local function tillNear(pos)
    for _, h in ipairs(tillHashes) do
        if GetClosestObjectOfType(pos.x, pos.y, pos.z, 3.0, h, false, false, false) ~= 0 then return true end
    end
    return false
end

local modelsAdded = false
local function addTillModels()
    if modelsAdded or #tillHashes == 0 then return end
    modelsAdded = true
    exports.veyl_target:addModel(C.TillModels, {
        { name = 'veyl_rob_till', label = 'Pick the register lock', icon = 'lock', distance = 2.5,
          canInteract = function(entity)
              return not LocalPlayer.state.cuffed and not busy and (exports.veyl_inventory:GetItemCount(C.Register.item) or 0) > 0
                  and storeForTill(GetEntityCoords(entity)) ~= nil
          end,
          onSelect = function(d)
              local pos = GetEntityCoords(d.entity)
              local id = storeForTill(pos)
              if id then CreateThread(function() rob(id, 'register', pos) end) end
          end },
    })
end

local function addZones(list)
    for _, id in ipairs(zones) do exports.veyl_target:removeZone(id) end
    zones = {}
    storeList = list
    addTillModels()
    for _, s in ipairs(list) do
        local storeId = s.id
        -- The clerk stands behind the counter: centre the zone a little in front of them, so aiming at the counter,
        -- the till or the clerk all work.
        local h = math.rad(s.heading or 0.0)
        local center = vector3(s.register.x - math.sin(h) * 0.6, s.register.y + math.cos(h) * 0.6, s.register.z + 0.1)
        zones[#zones + 1] = exports.veyl_target:addSphereZone({
            name = 'register_' .. storeId, coords = center, radius = 1.6, title = 'Register',
            options = {
                { name = 'veyl_rob_register_pick', label = 'Pick the register lock', icon = 'lock', distance = 3.5,
                  -- Fallback for counters without a till prop (the props themselves are targets above).
                  canInteract = function() return not LocalPlayer.state.cuffed and not busy and (exports.veyl_inventory:GetItemCount(C.Register.item) or 0) > 0 and not tillNear(center) end,
                  onSelect = function() CreateThread(function() rob(storeId, 'register') end) end },
            },
        })
        if s.safe then
            zones[#zones + 1] = exports.veyl_target:addSphereZone({
                name = 'safe_' .. storeId, coords = vector3(s.safe.x, s.safe.y, s.safe.z), radius = 1.0, title = 'Safe',
                options = { {
                    name = 'veyl_rob_safe', label = 'Crack the safe', icon = 'lock', distance = 2.5,
                    canInteract = function() return not busy and (exports.veyl_inventory:GetItemCount(C.Safe.item) or 0) > 0 end,
                    onSelect = function() CreateThread(function() rob(storeId, 'safe') end) end,
                } },
            })
        end
    end
end

CreateThread(function()
    while GetResourceState('veyl_target') ~= 'started' do Wait(250) end
    while not Veyl.IsLoaded() do Wait(1000) end
    for _ = 1, 10 do
        local res = Veyl.Callback('veyl_robbery', 'stores')
        if res.ok and type(res.data) == 'table' then addZones(res.data) return end
        Wait(3000)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, id in ipairs(zones) do pcall(function() exports.veyl_target:removeZone(id) end) end
    if modelsAdded then pcall(function() exports.veyl_target:removeModel(C.TillModels, { 'veyl_rob_till' }) end) end
end)
