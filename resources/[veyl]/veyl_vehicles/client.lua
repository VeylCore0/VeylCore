-- veyl_vehicles client: lock key, key-required driving for VeylCore vehicles, empty-tank handling, refuelling.

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
    if not keys then return true end -- not a VeylCore-managed vehicle
    local me = Veyl.GetCharacterId()
    for _, id in ipairs(keys) do if id == me then return true end end
    return false
end

RegisterCommand('vehlock', function()
    if not Veyl.IsLoaded() then return end
    local veh = closestVehicle(VehiclesConfig.LockDistance)
    if not veh or not NetworkGetEntityIsNetworked(veh) then return end
    if not Entity(veh).state.veylId then return end
    Veyl.NotifyResult(Veyl.Callback('veyl_vehicles', 'toggleLock', VehToNet(veh)))
end, false)
RegisterKeyMapping('vehlock', 'Lock / unlock vehicle', 'keyboard', 'L')

RegisterNetEvent('veyl_vehicles:lockFeedback', function(netId, locked)
    if not NetworkDoesNetworkIdExist(netId) then return end
    local veh = NetToVeh(netId)
    if veh == 0 then return end
    SetVehicleLights(veh, 2)
    Wait(200)
    SetVehicleLights(veh, 0)
    PlaySoundFromEntity(-1, locked and 'Remote_Control_Close' or 'Remote_Control_Open', veh, 'PI_Menu_Sounds', true, 0)
end)

-- Driving restrictions for managed vehicles.
CreateThread(function()
    local warned = 0
    while true do
        local sleep = 500
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped and Entity(veh).state.veylId then
            sleep = 0
            local noKey = not hasKey(veh)
            local fuel = Entity(veh).state.veylFuel
            if noKey or (fuel and fuel <= 0) then
                SetVehicleEngineOn(veh, false, true, true)
                DisableControlAction(0, 71, true)
                if GetGameTimer() > warned then
                    warned = GetGameTimer() + 5000
                    Veyl.Notify(noKey and 'You do not have keys for this vehicle' or 'Out of fuel', 'warning', 2500)
                end
            end
        end
        Wait(sleep)
    end
end)

-- Fuel stations
AddEventHandler('veyl_vehicles:refuel', function()
    local veh = closestVehicle(6.0)
    if not veh or not Entity(veh).state.veylId then return Veyl.Notify('No VeylCore vehicle nearby', 'error') end
    if GetPedInVehicleSeat(veh, -1) == PlayerPedId() then return Veyl.Notify('Get out of the vehicle first', 'error') end
    local ok = Veyl.UI.Progress({ label = 'Refuelling...', duration = 5000, disableMovement = true,
        anim = { dict = 'timetable@gardener@filling_can', clip = 'gar_ig_5_filling_can', flag = 49 } })
    if ok then Veyl.NotifyResult(Veyl.Callback('veyl_vehicles', 'refuel', VehToNet(veh))) end
end)

CreateThread(function()
    while GetResourceState('veyl_interact') ~= 'started' do Wait(200) end
    for i, s in ipairs(VehiclesConfig.FuelStations) do
        exports.veyl_interact:AddZone({ id = 'fuel_' .. i, coords = s, radius = VehiclesConfig.FuelStationRadius,
            label = 'Refuel vehicle', event = 'veyl_vehicles:refuel' })
        local blip = AddBlipForCoord(s.x, s.y, s.z)
        SetBlipSprite(blip, 361)
        SetBlipScale(blip, 0.6)
        SetBlipColour(blip, 27)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName('Fuel')
        EndTextCommandSetBlipName(blip)
    end
end)
