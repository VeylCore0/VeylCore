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

-- Rod: our own prop in the hand (the game's fishing scenario leaves its rod floating or stuck in the hand).
local ROD_MODEL = `prop_fishing_rod_01`
local IDLE = { dict = 'amb@world_human_stand_fishing@idle_a', clip = 'idle_c' }
local rod = nil

local function loadDict(dict)
    RequestAnimDict(dict)
    local t = GetGameTimer() + 2000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < t do Wait(10) end
    return HasAnimDictLoaded(dict)
end

local function removeRod()
    if rod and DoesEntityExist(rod) then DetachEntity(rod, true, false) DeleteEntity(rod) end
    rod = nil
    -- Clean up any rod a fishing scenario (emote) left attached to us.
    local ped = PlayerPedId()
    local pc = GetEntityCoords(ped)
    local left = GetClosestObjectOfType(pc.x, pc.y, pc.z, 3.0, ROD_MODEL, false, false, false)
    if left ~= 0 and IsEntityAttachedToEntity(left, ped) then DetachEntity(left, true, false) DeleteEntity(left) end
end

local function holdRod()
    local ped = PlayerPedId()
    RequestModel(ROD_MODEL)
    local t = GetGameTimer() + 3000
    while not HasModelLoaded(ROD_MODEL) and GetGameTimer() < t do Wait(10) end
    if not HasModelLoaded(ROD_MODEL) then return end
    local pc = GetEntityCoords(ped)
    rod = CreateObject(ROD_MODEL, pc.x, pc.y, pc.z + 0.2, true, true, false)
    AttachEntityToEntity(rod, ped, GetPedBoneIndex(ped, 18905), 0.1, 0.05, 0.0, 80.0, 120.0, 160.0, true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(ROD_MODEL)
end

local function stopFishing()
    local ped = PlayerPedId()
    StopAnimTask(ped, IDLE.dict, IDLE.clip, 1.0)
    ClearPedTasks(ped)
    removeRod()
    fishing = false
end

local function fish()
    if fishing then return end
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) or IsPedSwimming(ped) then return Veyl.Notify('Stand on the shore or a pier', 'error') end
    if not facingWater() then return Veyl.Notify('Face the water to cast', 'error') end
    local cast = Veyl.Callback('veyl_fishing', 'cast')
    if not cast.ok then return Veyl.NotifyResult(cast) end
    fishing = true
    ClearPedTasks(ped)
    holdRod()
    if loadDict(IDLE.dict) then TaskPlayAnim(ped, IDLE.dict, IDLE.clip, 4.0, -4.0, -1, 1, 0, false, false, false) end
    Veyl.Notify(('Line in the water at %s. Wait for a bite…'):format(cast.data.zone), 'info')
    local biteAt = GetGameTimer() + math.floor(cast.data.biteIn * 1000)
    local reacted, early = false, false
    -- Waiting: walking off, getting hurt or pressing Backspace reels in; pressing E too early loses the fish.
    while GetGameTimer() < biteAt do
        Veyl.HelpText('Waiting for a bite… ~INPUT_CELLPHONE_CANCEL~ to reel in')
        DisableControlAction(0, 24, true) DisableControlAction(0, 25, true)
        if IsControlJustPressed(0, 38) then early = true break end
        local moved = GetEntitySpeed(ped) > 1.0 or IsPedRagdoll(ped) or LocalPlayer.state.medical or IsPedSwimming(ped)
        if IsControlJustPressed(0, 177) or moved then
            stopFishing()
            Veyl.Callback('veyl_fishing', 'reel', cast.data.token, false)
            return Veyl.Notify('You reeled in.', 'info')
        end
        if not IsEntityPlayingAnim(ped, IDLE.dict, IDLE.clip, 3) then TaskPlayAnim(ped, IDLE.dict, IDLE.clip, 4.0, -4.0, -1, 1, 0, false, false, false) end
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
    stopFishing()
    local res = Veyl.CallbackTimeout('veyl_fishing', 'reel', 10000, cast.data.token, reacted)
    if not res.ok then return Veyl.NotifyResult(res) end
    Veyl.Notify(res.message, res.data.caught and 'success' or 'info')
end

AddEventHandler('onResourceStop', function(res) if res == GetCurrentResourceName() then removeRod() end end)

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
