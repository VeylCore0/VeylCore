-- veyl_fishing client: casting, waiting for a bite, reacting, and the fish market clerk.

local C = FishingConfig
local fishing = false

local function facingWater()
    local ped = PlayerPedId()
    local head = GetPedBoneCoords(ped, 31086, 0.0, 0.0, 0.0)
    local fwd = GetOffsetFromEntityInWorldCoords(ped, 0.0, 12.0, -12.0)
    local hit = TestProbeAgainstWater(head.x, head.y, head.z, fwd.x, fwd.y, fwd.z)
    return hit
end

local function fish()
    if fishing then return end
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) or IsPedSwimming(ped) then return Veyl.Notify('Stand on the shore or a pier', 'error') end
    if not facingWater() then return Veyl.Notify('Face the water to cast', 'error') end
    local cast = Veyl.Callback('veyl_fishing', 'cast')
    if not cast.ok then return Veyl.NotifyResult(cast) end
    fishing = true
    TaskStartScenarioInPlace(ped, 'WORLD_HUMAN_STAND_FISHING', 0, true)
    Veyl.Notify(('Line in the water at %s. Wait for a bite…'):format(cast.data.zone), 'info')
    local biteAt = GetGameTimer() + math.floor(cast.data.biteIn * 1000)
    local reacted, early = false, false
    -- Waiting: moving or pressing E too early pulls the line out.
    while GetGameTimer() < biteAt do
        Veyl.HelpText('Waiting for a bite… ~INPUT_FRONTEND_CANCEL~ to stop')
        if IsControlJustPressed(0, 38) then early = true break end
        if IsControlJustPressed(0, 177) or not IsPedUsingScenario(ped, 'WORLD_HUMAN_STAND_FISHING') then
            ClearPedTasks(ped)
            fishing = false
            Veyl.Callback('veyl_fishing', 'reel', cast.data.token, false)
            return Veyl.Notify('You reeled in.', 'info')
        end
        Wait(0)
    end
    if not early then
        PlaySoundFrontend(-1, 'Beep_Red', 'DLC_HEIST_HACKING_SNAKE_SOUNDS', true)
        local deadline = GetGameTimer() + math.floor(cast.data.react * 1000)
        while GetGameTimer() < deadline do
            Veyl.HelpText('~r~IT BITES!~s~ Press ~INPUT_CONTEXT~')
            if IsControlJustPressed(0, 38) then reacted = true break end
            Wait(0)
        end
    end
    ClearPedTasks(ped)
    fishing = false
    local res = Veyl.CallbackTimeout('veyl_fishing', 'reel', 10000, cast.data.token, reacted)
    if not res.ok then return Veyl.NotifyResult(res) end
    Veyl.Notify(res.message, res.data.caught and 'success' or 'info')
end

RegisterNetEvent('veyl_fishing:use', function() CreateThread(fish) end)
AddEventHandler('veyl_fishing:sell', function() CreateThread(function() Veyl.NotifyResult(Veyl.Callback('veyl_fishing', 'sell')) end) end)

CreateThread(function()
    while GetResourceState('veyl_interact') ~= 'started' do Wait(250) end
    local m = C.Market
    exports.veyl_interact:AddPed({ id = 'veyl_fishing_market', model = m.model, coords = m.coords, radius = 2.5, title = m.label,
        options = { { label = 'Sell your catch', icon = 'money', event = 'veyl_fishing:sell' } } })
    local blip = AddBlipForCoord(m.coords.x, m.coords.y, m.coords.z)
    SetBlipSprite(blip, 68)
    SetBlipColour(blip, 3)
    SetBlipScale(blip, 0.75)
    SetBlipAsShortRange(blip, true)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName(m.label)
    EndTextCommandSetBlipName(blip)
    for _, z in ipairs(C.Zones) do
        local b = AddBlipForCoord(z.center.x, z.center.y, z.center.z)
        SetBlipSprite(b, 68)
        SetBlipColour(b, 38)
        SetBlipScale(b, 0.6)
        SetBlipAsShortRange(b, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName('Fishing: ' .. z.label)
        EndTextCommandSetBlipName(b)
    end
end)
