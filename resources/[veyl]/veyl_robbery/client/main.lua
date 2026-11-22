-- veyl_robbery client: "Rob the register" / "Crack the safe" spots in each store.

local C = RobberyConfig

local function rob(store, kind)
    local start = Veyl.CallbackTimeout('veyl_robbery', 'start', 10000, store, kind)
    if not start.ok then return Veyl.NotifyResult(start) end
    local ped = PlayerPedId()
    if kind == 'register' then
        TaskStartScenarioInPlace(ped, 'PROP_HUMAN_BUM_BIN', 0, true)
    end
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

AddEventHandler('veyl_robbery:rob', function(args)
    if type(args) == 'table' then CreateThread(function() rob(args.store, args.kind) end) end
end)

CreateThread(function()
    while GetResourceState('veyl_interact') ~= 'started' do Wait(250) end
    for _, s in ipairs(C.Stores) do
        exports.veyl_interact:AddZone({ id = 'veyl_rob_reg_' .. s.id, coords = s.register, radius = 2.0, title = s.label,
            options = { { label = 'Rob the register', icon = 'money', event = 'veyl_robbery:rob', args = { store = s.id, kind = 'register' },
                canInteract = function() return IsPedArmed(PlayerPedId(), 4) end } } })
        if s.safe then
            exports.veyl_interact:AddZone({ id = 'veyl_rob_safe_' .. s.id, coords = s.safe, radius = 1.5, title = 'Safe',
                options = { { label = 'Crack the safe', icon = 'lock', event = 'veyl_robbery:rob', args = { store = s.id, kind = 'safe' } } } })
        end
    end
end)
