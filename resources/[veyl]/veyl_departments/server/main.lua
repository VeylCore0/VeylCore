-- veyl_departments server: department vehicles (one per member, keys included) and free supply lockers.

local C = DepartmentsConfig
local active = {}       -- [citizenid] = vehicleId
local lastSupply = {}   -- [citizenid .. ':' .. dept] = os.time()

Veyl.Startup({ 'veyl_core', 'veyl_vehicles', 'veyl_inventory' }, function() return true end)

local function memberOf(src)
    local pd = Veyl.GetPlayerData(src)
    if not pd or not pd.job.onduty then return nil end
    for key, d in pairs(C.Departments) do
        for _, j in ipairs(d.jobs) do if j == pd.job.name then return key, d, pd end end
    end
    return nil
end

local function near(src, pos, dist)
    local pc = Veyl.GetPlayerCoords(src)
    return pc ~= nil and #(pc - vector3(pos.x, pos.y, pos.z)) <= dist
end

local function grade(pd) return pd.job.grade and pd.job.grade.level or 0 end

Veyl.RegisterCallback('garage', function(src)
    local key, d, pd = memberOf(src)
    if not key then return Veyl.Err('NO_PERMISSION', 'You need to be on duty') end
    if not near(src, d.garage.menu, 4.0) then return Veyl.Err('TOO_FAR', 'Use the garage point') end
    local list = {}
    for i, v in ipairs(d.garage.vehicles) do list[#list + 1] = { index = i, label = v.label, locked = grade(pd) < (v.grade or 0) } end
    return Veyl.Ok({ label = d.label, vehicles = list, hasActive = active[pd.citizenid] ~= nil })
end, { cooldown = 500 })

Veyl.RegisterCallback('takeVehicle', function(src, citizenid, index)
    local key, d, pd = memberOf(src)
    if not key then return Veyl.Err('NO_PERMISSION', 'You need to be on duty') end
    if not near(src, d.garage.menu, 4.0) then return Veyl.Err('TOO_FAR', 'Use the garage point') end
    local v = d.garage.vehicles[tonumber(index) or 0]
    if not v then return Veyl.Err('NOT_FOUND', 'Unknown vehicle') end
    if grade(pd) < (v.grade or 0) then return Veyl.Err('NO_PERMISSION', 'Your rank cannot take this vehicle') end
    -- One department vehicle each: taking a new one returns the old one.
    if active[citizenid] then exports.veyl_vehicles:DeleteVehicle(active[citizenid]) active[citizenid] = nil end
    local res = Veyl.Await('veyl_vehicles', 'SpawnAuthorizedVehicle', 15000, {
        model = v.model, coords = d.garage.spawn, citizenid = citizenid, temporary = true, platePrefix = d.platePrefix, fuel = 100,
    })
    if not res.ok then return Veyl.Err(res.code or 'INTERNAL', 'The vehicle could not be brought out') end
    active[citizenid] = res.data.vehicleId
    Veyl.Audit(src, 'department_vehicle', { dept = key, model = v.model, plate = res.data.plate })
    return Veyl.Ok({ netId = res.data.netId, plate = res.data.plate }, ('%s ready: %s'):format(v.label, res.data.plate))
end, { cooldown = 3000 })

Veyl.RegisterCallback('returnVehicle', function(src, citizenid, netId)
    local key, d = memberOf(src)
    if not key then return Veyl.Err('NO_PERMISSION', 'You need to be on duty') end
    if not near(src, d.garage.menu, C.ReturnDistance) then return Veyl.Err('TOO_FAR', 'Bring it back to the garage') end
    local entity = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    local id = entity ~= 0 and exports.veyl_vehicles:GetVehicleIdFromEntity(entity)
    if not id or id ~= active[citizenid] then return Veyl.Err('NO_PERMISSION', 'This is not your department vehicle') end
    exports.veyl_vehicles:DeleteVehicle(id)
    active[citizenid] = nil
    return Veyl.Ok(nil, 'Vehicle returned')
end, { cooldown = 1000 })

Veyl.RegisterCallback('supplies', function(src, citizenid)
    local key, d, pd = memberOf(src)
    if not key or not d.supplies then return Veyl.Err('NO_PERMISSION', 'You need to be on duty') end
    if not near(src, d.supplies.coords, 3.5) then return Veyl.Err('TOO_FAR', 'Use the locker') end
    local k = citizenid .. ':' .. key
    local wait = (lastSupply[k] or 0) + d.supplies.cooldownSeconds - os.time()
    if wait > 0 then return Veyl.Err('RATE_LIMITED', ('The locker restocks in %d min'):format(math.ceil(wait / 60))) end
    lastSupply[k] = os.time()
    local given, op = {}, ('dept:%s:%s:%d'):format(key, citizenid, os.time())
    for i, it in ipairs(d.supplies.items) do
        if grade(pd) >= (it.grade or 0) then
            local r = Veyl.Await('veyl_inventory', 'GiveItem', 15000, citizenid, it.item, it.count or 1, nil, op .. ':' .. i)
            if r.ok then given[#given + 1] = ('%dx %s'):format(it.count or 1, it.item) end
        end
    end
    if #given == 0 then lastSupply[k] = nil return Veyl.Err('INVENTORY_FULL', 'Make room in your pockets first') end
    Veyl.Audit(src, 'department_supplies', { dept = key, items = given })
    return Veyl.Ok(nil, 'Collected: ' .. table.concat(given, ', '))
end, { cooldown = 2000 })

-- Going off duty or leaving returns the vehicle.
local function cleanup(src)
    local cid = Veyl.GetCitizenId(src)
    if cid and active[cid] then exports.veyl_vehicles:DeleteVehicle(active[cid]) active[cid] = nil end
end
AddEventHandler('VeylCore:Server:SetDuty', function(src, onDuty) if not onDuty then cleanup(src) end end)
AddEventHandler('VeylCore:Server:OnPlayerUnload', function(src) cleanup(src) end)
AddEventHandler('playerDropped', function() cleanup(source) end)
