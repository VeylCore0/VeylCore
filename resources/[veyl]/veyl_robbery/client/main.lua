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
local function rob(store, kind, method)
    if busy then return end
    busy = true
    if kind == 'safe' or method == 'lockpick' then
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
    local start = Veyl.CallbackTimeout('veyl_robbery', 'start', 10000, store, kind, method)
    if not start.ok then busy = false return Veyl.NotifyResult(start) end
    local ped = PlayerPedId()
    if kind == 'register' then TaskStartScenarioInPlace(ped, 'PROP_HUMAN_BUM_BIN', 0, true) end
    local done = vlib.progress({
        label = kind == 'safe' and 'Opening the safe' or 'Emptying the register', duration = start.data.seconds * 1000, canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = kind == 'safe' and { dict = 'mini@safe_cracking', clip = 'dial_turn_anti_fast_1', flag = 1 } or nil,
    })
    ClearPedTasks(ped)
    busy = false
    if not done then
        Veyl.Callback('veyl_robbery', 'cancel')
        return Veyl.Notify('You left it. The alarm was already raised.', 'warning')
    end
    Veyl.NotifyResult(Veyl.CallbackTimeout('veyl_robbery', 'finish', 10000, start.data.token))
end

local zones = {}

local function addZones(list)
    for _, id in ipairs(zones) do exports.veyl_target:removeZone(id) end
    zones = {}
    for _, s in ipairs(list) do
        local storeId = s.id
        -- The clerk stands behind the counter: centre the zone a little in front of them, so aiming at the counter,
        -- the till or the clerk all work.
        local h = math.rad(s.heading or 0.0)
        local center = vector3(s.register.x - math.sin(h) * 0.6, s.register.y + math.cos(h) * 0.6, s.register.z + 0.1)
        zones[#zones + 1] = exports.veyl_target:addSphereZone({
            name = 'register_' .. storeId, coords = center, radius = 1.6, title = 'Register',
            options = {
                { name = 'veyl_rob_register', label = 'Threaten the clerk', icon = 'money', distance = 3.5,
                  canInteract = function() return not LocalPlayer.state.cuffed and not busy end,
                  onSelect = function() CreateThread(function() rob(storeId, 'register', 'weapon') end) end },
                { name = 'veyl_rob_register_pick', label = 'Pick the register lock', icon = 'lock', distance = 3.5,
                  canInteract = function() return not LocalPlayer.state.cuffed and not busy and (exports.veyl_inventory:GetItemCount(C.Register.item) or 0) > 0 end,
                  onSelect = function() CreateThread(function() rob(storeId, 'register', 'lockpick') end) end },
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
end)
