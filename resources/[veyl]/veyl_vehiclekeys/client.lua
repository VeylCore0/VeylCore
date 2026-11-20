-- veyl_vehiclekeys client: lock key and key-required driving for VeylCore-managed vehicles.

local function closestVehicle(maxDist)
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 then return veh end
    local pos = GetEntityCoords(ped)
    local best, bestDist = nil, maxDist
    for _, v in ipairs(GetGamePool('CVehicle')) do
        local d = #(pos - GetEntityCoords(v))
        if d < bestDist then best, bestDist = v, d end
    end
    return best
end

local function hasKey(veh)
    local keys = Entity(veh).state.veylKeys
    if not keys then return false end
    local me = Veyl.GetCitizenId()
    for _, cid in ipairs(keys) do if cid == me then return true end end
    return false
end

RegisterCommand('vehlock', function()
    if not Veyl.IsLoaded() then return end
    local veh = closestVehicle(KeysConfig.LockDistance)
    if not veh or not NetworkGetEntityIsNetworked(veh) or not Entity(veh).state.veylVehicleId then return end
    Veyl.NotifyResult(Veyl.Callback('veyl_vehiclekeys', 'toggleLock', VehToNet(veh)))
end, false)
RegisterKeyMapping('vehlock', 'Lock / unlock vehicle', 'keyboard', 'L')

RegisterNetEvent('veyl_vehiclekeys:lockFeedback', function(netId, locked)
    if not NetworkDoesNetworkIdExist(netId) then return end
    local veh = NetToVeh(netId)
    if veh == 0 then return end
    SetVehicleLights(veh, 2)
    Wait(200)
    SetVehicleLights(veh, 0)
    PlaySoundFromEntity(-1, locked and 'Remote_Control_Close' or 'Remote_Control_Open', veh, 'PI_Menu_Sounds', true, 0)
end)

-- VeylCore-managed vehicles need a key to drive. Ambient traffic is unaffected.
CreateThread(function()
    local warned = 0
    while true do
        local sleep = 500
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped and Entity(veh).state.veylVehicleId and not hasKey(veh) then
            sleep = 0
            SetVehicleEngineOn(veh, false, true, true)
            DisableControlAction(0, 71, true)
            if GetGameTimer() > warned then
                warned = GetGameTimer() + 5000
                Veyl.Notify('You do not have keys for this vehicle', 'warning', 2500)
            end
        end
        Wait(sleep)
    end
end)
