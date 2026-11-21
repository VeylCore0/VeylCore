-- veyl_vehicles seatbelt (client). Publishes LocalPlayer.state.seatbelt (true/false) for the HUD and other scripts.
-- Buckled: you can't leave the vehicle until you unbuckle and you stay in your seat on impact.
-- Unbuckled: a hard crash above EjectSpeed throws you through the windscreen.

local Seatbelt = {
    Key = 'B',              -- default bind (players can rebind it under Settings > Key Bindings > FiveM)
    EjectSpeedMph = 45.0,   -- minimum speed before the crash for an ejection
    EjectDropRatio = 0.55,  -- the speed must fall below this share of the previous speed in one tick (a real impact, not braking)
}

-- Classes without belts: motorcycles 8, cycles 13, boats 14, helicopters 15, planes 16, trains 21.
local NO_BELT = { [8] = true, [13] = true, [14] = true, [15] = true, [16] = true, [21] = true }

local buckled = false

local function setBuckled(v)
    if buckled == v then return end
    buckled = v
    LocalPlayer.state:set('seatbelt', v, true)
end

local function beltVehicle()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh == 0 or NO_BELT[GetVehicleClass(veh)] then return nil end
    return veh
end

RegisterCommand('veyl_seatbelt', function()
    if not beltVehicle() or IsPauseMenuActive() then return end
    setBuckled(not buckled)
    PlaySoundFrontend(-1, buckled and 'Faster_Click' or 'Click_Fail', buckled and 'RESPAWN_ONLINE_SOUNDSET' or 'WEB_NAVIGATION_SOUNDS_PHONE', true)
    Veyl.Notify(buckled and 'Seatbelt on' or 'Seatbelt off', buckled and 'success' or 'info', 1500)
end, false)
RegisterKeyMapping('veyl_seatbelt', 'Toggle seatbelt', 'keyboard', Seatbelt.Key)

local function eject(ped, veh, velocity)
    local pos = GetEntityCoords(ped)
    local fwd = GetEntityForwardVector(veh)
    SetEntityCoords(ped, pos.x + fwd.x, pos.y + fwd.y, pos.z - 0.47, true, true, true, false)
    SetEntityVelocity(ped, velocity.x, velocity.y, velocity.z)
    Wait(1)
    SetPedToRagdoll(ped, 1000, 1000, 0, false, false, false)
end

CreateThread(function()
    LocalPlayer.state:set('seatbelt', false, true)
    local ejectSpeed = Seatbelt.EjectSpeedMph / 2.236936 -- m/s
    local prevSpeed, prevVelocity = 0.0, vector3(0, 0, 0)
    while true do
        local veh = beltVehicle()
        if not veh then
            if buckled then setBuckled(false) end
            prevSpeed = 0.0
            Wait(500)
        else
            local ped = PlayerPedId()
            SetPedConfigFlag(ped, 32, false) -- 32 = native fly-through-windscreen; ejection is handled below so it's predictable
            if buckled then
                DisableControlAction(0, 75, true) -- exit vehicle
                if IsDisabledControlJustPressed(0, 75) then Veyl.Notify('Unbuckle first (' .. Seatbelt.Key .. ')', 'warning', 1500) end
            else
                local speed = GetEntitySpeed(veh)
                if prevSpeed > ejectSpeed and speed < prevSpeed * Seatbelt.EjectDropRatio and HasEntityCollidedWithAnything(veh) then
                    eject(ped, veh, prevVelocity)
                    prevSpeed = 0.0
                else
                    prevSpeed, prevVelocity = speed, GetEntityVelocity(veh)
                end
            end
            Wait(0)
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    LocalPlayer.state:set('seatbelt', nil, true)
end)
