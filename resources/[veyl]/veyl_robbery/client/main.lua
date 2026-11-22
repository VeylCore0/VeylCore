-- veyl_robbery client: target zones (hold ALT, aim at the counter) on every robbable store's register and safe.
-- Target zones are separate from the clerk's "Shop" prompt, so both work at the same counter.

local function rob(store, kind)
    local start = Veyl.CallbackTimeout('veyl_robbery', 'start', 10000, store, kind)
    if not start.ok then return Veyl.NotifyResult(start) end
    local ped = PlayerPedId()
    if kind == 'register' then TaskStartScenarioInPlace(ped, 'PROP_HUMAN_BUM_BIN', 0, true) end
    local done = vlib.progress({
        label = kind == 'safe' and 'Cracking the safe' or 'Emptying the register', duration = start.data.seconds * 1000, canCancel = true,
        disable = { move = true, car = true, combat = true },
        anim = kind == 'safe' and { dict = 'mini@safe_cracking', clip = 'dial_turn_anti_fast_1', flag = 1 } or nil,
    })
    ClearPedTasks(ped)
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
        zones[#zones + 1] = exports.veyl_target:addSphereZone({
            name = 'register_' .. storeId, coords = vector3(s.register.x, s.register.y, s.register.z + 0.2), radius = 1.2, title = 'Register',
            options = { {
                name = 'veyl_rob_register', label = 'Rob the register', icon = 'money', distance = 3.0,
                canInteract = function() return IsPedArmed(PlayerPedId(), 4 | 1) and not LocalPlayer.state.cuffed end,
                onSelect = function() CreateThread(function() rob(storeId, 'register') end) end,
            } },
        })
        if s.safe then
            zones[#zones + 1] = exports.veyl_target:addSphereZone({
                name = 'safe_' .. storeId, coords = vector3(s.safe.x, s.safe.y, s.safe.z), radius = 0.8, title = 'Safe',
                options = { {
                    name = 'veyl_rob_safe', label = 'Crack the safe', icon = 'lock', distance = 2.0,
                    canInteract = function() return (exports.veyl_inventory:GetItemCount('lockpick') or 0) > 0 end,
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
