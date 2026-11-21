-- veyl_garages server: take out / park owned vehicles and release impounded ones. Ownership, reservation and
-- storage state are owned by veyl_vehicles; this resource checks location, prices the impound release and charges it.

Veyl.Startup({ 'veyl_core', 'veyl_vehicles' }, function() return true end)

local function vehicles(name, ...) return Veyl.Await('veyl_vehicles', name, 20000, ...) end
local function core(name, ...) return Veyl.Await('veyl_core', name, 15000, ...) end

local places, labels = {}, {}
for _, g in ipairs(GaragesConfig.Garages) do places[g.id] = g labels[g.id] = g.label end
places[GaragesConfig.Impound.id] = GaragesConfig.Impound
labels[GaragesConfig.Impound.id] = GaragesConfig.Impound.label

local function near(src, place, radius)
    local pc = Veyl.GetPlayerCoords(src)
    return pc ~= nil and #(pc - place.coords) <= radius
end

local function catalogName(model)
    local def = exports.veyl_core:GetVehicles()[model]
    return def and def.name or model, def and def.brand or nil
end

local function balancesOf(src)
    local pd = Veyl.GetPlayerData(src)
    return { cash = pd and pd.money.cash or 0, bank = pd and pd.money.bank or 0 }
end

--- list(placeId) -> screen data for a garage or the impound lot.
Veyl.RegisterCallback('list', function(src, citizenid, placeId)
    local place = places[placeId]
    if not place then return Veyl.Err('NOT_FOUND', 'Unknown garage') end
    if not near(src, place, GaragesConfig.UseRadius + 4.0) then return Veyl.Err('TOO_FAR', 'Walk up to the garage') end
    local res = vehicles('GetOwnedVehicles', citizenid)
    if not res.ok then return res end
    local isImpound = placeId == GaragesConfig.Impound.id
    local list = {}
    for _, v in ipairs(res.data) do
        local name, brand = catalogName(v.model)
        v.name, v.brand = v.label or name, brand
        v.garageLabel = v.garage and labels[v.garage] or nil
        v.here = (v.state == 'garaged' and v.garage == placeId) or (isImpound and v.state == 'impound')
        list[#list + 1] = v
    end
    return Veyl.Ok({
        kind = isImpound and 'impound' or 'garage', placeId = placeId, title = place.label,
        vehicles = list, balances = balancesOf(src), methods = GaragesConfig.PaymentMethods,
    })
end, { cooldown = 750 })

--- takeOut({ placeId, ownedId, spawnIndex, method?, opId? })
Veyl.RegisterCallback('takeOut', function(src, citizenid, req)
    if type(req) ~= 'table' then return Veyl.Err('INVALID_INPUT', 'Invalid request') end
    local place = places[req.placeId]
    if not place then return Veyl.Err('NOT_FOUND', 'Unknown garage') end
    if not near(src, place, GaragesConfig.UseRadius + 4.0) then return Veyl.Err('TOO_FAR', 'Walk up to the garage') end
    local spawn = Veyl.Validate.int(req.spawnIndex, 1, #place.spawns) and place.spawns[req.spawnIndex]
    if not spawn then return Veyl.Err('BLOCKED', 'The parking spaces are blocked. Clear a space and try again.') end
    if not Veyl.Validate.int(req.ownedId, 1) then return Veyl.Err('INVALID_INPUT', 'Choose a vehicle') end

    local list = vehicles('GetOwnedVehicles', citizenid)
    if not list.ok then return list end
    local row
    for _, v in ipairs(list.data) do if v.id == req.ownedId then row = v break end end
    if not row then return Veyl.Err('NOT_FOUND', 'That is not your vehicle') end

    local isImpound = place.id == GaragesConfig.Impound.id
    if isImpound and row.state == 'impound' then
        if row.impoundFee > 0 then
            if not Veyl.Validate.oneOf(req.method, GaragesConfig.PaymentMethods) then return Veyl.Err('INVALID_INPUT', 'Choose cash or bank') end
            if not Veyl.Validate.str(req.opId, 8, 64, '^[%w%-]+$') then return Veyl.Err('INVALID_INPUT', 'Missing operation id') end
            local pay = core('DebitOnce', citizenid, req.method, row.impoundFee, ('Impound release %s'):format(row.plate),
                ('impound:%s:%s'):format(citizenid, req.opId))
            if not pay.ok and pay.code ~= 'DUPLICATE_OPERATION' then
                if pay.code == 'TIMEOUT' then return Veyl.Err('PENDING', 'Payment is being verified. Try again in a moment.') end
                return pay
            end
        end
        local res = vehicles('SpawnOwnedVehicle', src, citizenid, row.id, spawn, { from = 'impound', garage = place.id })
        if not res.ok then return res end
        Veyl.Audit(src, 'impound_release', { plate = row.plate, fee = row.impoundFee })
        return Veyl.Ok({ plate = res.data.plate, balances = balancesOf(src) },
            row.impoundFee > 0 and ('Released for $%d'):format(row.impoundFee) or 'Vehicle released')
    end

    local res = vehicles('SpawnOwnedVehicle', src, citizenid, row.id, spawn, { from = 'garaged', garage = place.id })
    if not res.ok then return res end
    return Veyl.Ok({ plate = res.data.plate }, ('%s is ready'):format(row.label or catalogName(row.model)))
end, { cooldown = 1500 })

--- park(placeId, netId, props): only the owner, near a garage, with the vehicle empty.
Veyl.RegisterCallback('park', function(src, citizenid, placeId, netId, props)
    local place = places[placeId]
    if not place or place.id == GaragesConfig.Impound.id then return Veyl.Err('NOT_FOUND', 'Unknown garage') end
    if not near(src, place, GaragesConfig.ParkRadius + 5.0) then return Veyl.Err('TOO_FAR', 'Drive closer to the garage') end
    local entity = Veyl.Validate.int(netId, 1) and NetworkGetEntityFromNetworkId(netId)
    if not entity or entity == 0 or #(GetEntityCoords(entity) - place.coords) > GaragesConfig.ParkRadius + 5.0 then
        return Veyl.Err('TOO_FAR', 'Bring the vehicle closer to the garage')
    end
    local pc = Veyl.GetPlayerCoords(src)
    if not pc or #(pc - GetEntityCoords(entity)) > 6.0 then return Veyl.Err('TOO_FAR', 'Stand next to the vehicle') end
    local res = vehicles('StoreOwnedVehicle', src, citizenid, netId, place.id, props)
    if not res.ok then return res end
    return Veyl.Ok(nil, ('Parked at %s'):format(place.label))
end, { cooldown = 1500 })
