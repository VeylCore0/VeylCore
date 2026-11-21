-- veyl_fuel client: empty-tank handling and fuel pumps.

local function closestManaged(maxDist)
    local pos = GetEntityCoords(PlayerPedId())
    local best, bestDist = nil, maxDist
    for _, v in ipairs(GetGamePool('CVehicle')) do
        if Entity(v).state.veylVehicleId then
            local d = #(pos - GetEntityCoords(v))
            if d < bestDist then best, bestDist = v, d end
        end
    end
    return best
end

CreateThread(function()
    local warned = 0
    while true do
        local sleep = 500
        local ped = PlayerPedId()
        local veh = GetVehiclePedIsIn(ped, false)
        if veh ~= 0 and GetPedInVehicleSeat(veh, -1) == ped then
            local fuel = Entity(veh).state.veylFuel
            if fuel and fuel <= 0 then
                sleep = 0
                SetVehicleEngineOn(veh, false, true, true)
                if GetGameTimer() > warned then
                    warned = GetGameTimer() + 5000
                    Veyl.Notify('Out of fuel', 'warning', 2500)
                end
            end
        end
        Wait(sleep)
    end
end)

AddEventHandler('veyl_fuel:refuel', function()
    local veh = closestManaged(6.0)
    if not veh then return Veyl.Notify('No VeylCore vehicle nearby', 'error') end
    if GetPedInVehicleSeat(veh, -1) == PlayerPedId() then return Veyl.Notify('Get out of the vehicle first', 'error') end
    local ok = Veyl.UI.Progress({ label = 'Refuelling...', duration = 5000, disableMovement = true,
        anim = { dict = 'timetable@gardener@filling_can', clip = 'gar_ig_5_filling_can', flag = 49 } })
    if ok then Veyl.NotifyResult(Veyl.Callback('veyl_fuel', 'refuel', VehToNet(veh))) end
end)

CreateThread(function()
    while GetResourceState('veyl_interact') ~= 'started' do Wait(200) end
    for i, s in ipairs(FuelConfig.Stations) do
        exports.veyl_interact:AddZone({ id = 'fuel_' .. i, coords = s, radius = FuelConfig.StationRadius, icon = 'gas', title = 'Fuel pump',
            label = 'Refuel vehicle', event = 'veyl_fuel:refuel' })
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
