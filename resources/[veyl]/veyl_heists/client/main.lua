-- veyl_heists client: the action points. The server decides the next step (thermite, hack, drill, smash).

local C = HeistsConfig

local ANIMS = {
    thermite = { scenario = 'WORLD_HUMAN_WELDING' },
    hack = { anim = { dict = 'anim@heists@prison_heistig1_p1_guard_checks_bus', clip = 'loop', flag = 49 } },
    loot = { scenario = 'WORLD_HUMAN_CONST_DRILL' },
    smash = { anim = { dict = 'missheist_jewel', clip = 'smash_case', flag = 1 } },
}
local LABELS = { thermite = 'Placing thermite', hack = 'Hacking the panel', loot = 'Drilling a deposit box', smash = 'Smashing the case' }

local function act(id)
    local start = Veyl.CallbackTimeout('veyl_heists', 'start', 10000, id)
    if not start.ok then return Veyl.NotifyResult(start) end
    local s = start.data
    local a = ANIMS[s.step] or {}
    if a.scenario then TaskStartScenarioInPlace(PlayerPedId(), a.scenario, 0, true) end
    local done = vlib.progress({ label = LABELS[s.step], duration = s.seconds * 1000, canCancel = true,
        disable = { move = true, car = true, combat = true }, anim = a.anim })
    ClearPedTasks(PlayerPedId())
    if not done then
        Veyl.Callback('veyl_heists', 'cancel')
        return Veyl.Notify('Stopped. The alarm is still ringing.', 'warning')
    end
    if s.step == 'smash' then PlaySoundFromCoord(-1, 'Glass_Smash', GetEntityCoords(PlayerPedId()), '', false, 0, false) end
    Veyl.NotifyResult(Veyl.CallbackTimeout('veyl_heists', 'finish', 10000, s.token))
end

AddEventHandler('veyl_heists:act', function(a) if type(a) == 'table' then CreateThread(function() act(a.id) end) end end)
RegisterNetEvent('veyl_heists:sync', function() end) -- reserved for door / vault visuals

CreateThread(function()
    while GetResourceState('veyl_interact') ~= 'started' do Wait(250) end
    for _, b in ipairs(C.Fleeca.banks) do
        exports.veyl_interact:AddZone({ id = 'veyl_heist_' .. b.id, coords = b.panel, radius = 1.5, title = b.label,
            options = { { label = 'Hack the vault / drill boxes', icon = 'lock', event = 'veyl_heists:act', args = { id = b.id } } } })
    end
    local p = C.Paleto
    exports.veyl_interact:AddZone({ id = 'veyl_heist_paleto_door', coords = p.door, radius = 1.3, title = 'Vault door',
        options = { { label = 'Use thermite', icon = 'bolt', event = 'veyl_heists:act', args = { id = p.id } } } })
    exports.veyl_interact:AddZone({ id = 'veyl_heist_paleto', coords = p.panel, radius = 1.3, title = p.label,
        options = { { label = 'Hack the vault / drill boxes', icon = 'lock', event = 'veyl_heists:act', args = { id = p.id } } } })
    local j = C.Jewelry
    exports.veyl_interact:AddZone({ id = 'veyl_heist_jewelry', coords = j.center, radius = j.radius, title = j.label,
        options = { { label = 'Smash a display case', icon = 'jewel', event = 'veyl_heists:act', args = { id = j.id },
            canInteract = function() return IsPedArmed(PlayerPedId(), 7) end } } })
end)
