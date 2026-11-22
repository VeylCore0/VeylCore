-- veyl_departments client: garage and locker points, and "Return to garage" on department vehicles.

local C = DepartmentsConfig

local function openGarage()
    local res = Veyl.Callback('veyl_departments', 'garage')
    if not res.ok then return Veyl.NotifyResult(res) end
    local items = {}
    for i, v in ipairs(res.data.vehicles) do
        items[i] = { label = v.label, description = v.locked and 'Your rank cannot take this' or nil, value = v.index, disabled = v.locked }
    end
    local choice = Veyl.UI.Menu({ title = res.data.label .. ' garage', subtitle = res.data.hasActive and 'Taking a vehicle returns your current one' or 'Choose a vehicle', items = items })
    if not choice then return end
    local r = Veyl.CallbackTimeout('veyl_departments', 'takeVehicle', 20000, choice)
    Veyl.NotifyResult(r)
    if r.ok then
        local t = GetGameTimer() + 5000
        local veh = 0
        while veh == 0 and GetGameTimer() < t do veh = NetworkGetEntityFromNetworkId(r.data.netId) Wait(50) end
        if veh ~= 0 then TaskWarpPedIntoVehicle(PlayerPedId(), veh, -1) end
    end
end

AddEventHandler('veyl_departments:garage', function() CreateThread(openGarage) end)
AddEventHandler('veyl_departments:supplies', function() CreateThread(function() Veyl.NotifyResult(Veyl.CallbackTimeout('veyl_departments', 'supplies', 20000)) end) end)

CreateThread(function()
    while GetResourceState('veyl_interact') ~= 'started' do Wait(250) end
    for key, d in pairs(C.Departments) do
        exports.veyl_interact:AddZone({ id = 'veyl_dept_garage_' .. key, coords = d.garage.menu, radius = 2.0, title = d.label .. ' garage',
            options = { { label = 'Department vehicles', icon = 'garage', event = 'veyl_departments:garage', groups = d.jobs } } })
        if d.supplies then
            exports.veyl_interact:AddZone({ id = 'veyl_dept_supplies_' .. key, coords = d.supplies.coords, radius = 1.5, title = d.supplies.label,
                options = { { label = 'Take equipment', icon = 'box', event = 'veyl_departments:supplies', groups = d.jobs } } })
        end
    end
end)

CreateThread(function()
    while GetResourceState('veyl_target') ~= 'started' do Wait(250) end
    exports.veyl_target:addGlobalVehicle({
        { name = 'veyl_dept_return', label = 'Return to garage', icon = 'garage', distance = 3.0, priority = 0,
          canInteract = function(entity)
              local job = (Veyl.PlayerData or {}).job
              if not job or not job.onduty then return false end
              local plate = GetVehicleNumberPlateText(entity) or ''
              for _, d in pairs(C.Departments) do
                  if plate:find(d.platePrefix, 1, true) then
                      for _, j in ipairs(d.jobs) do if j == job.name then return true end end
                  end
              end
              return false
          end,
          onSelect = function(data) CreateThread(function()
              Veyl.NotifyResult(Veyl.Callback('veyl_departments', 'returnVehicle', NetworkGetNetworkIdFromEntity(data.entity)))
          end) end },
    })
end)
