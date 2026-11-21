-- Garage app: the character's owned vehicles (veyl_vehicles) and where to find them (veyl_garages places, or the
-- live position of a vehicle that is out). Read-only: taking out and parking still happen at the garage.

local function places()
    if GetResourceState('veyl_garages') ~= 'started' then return {} end
    local ok, list = pcall(function() return exports.veyl_garages:GetPlaces() end)
    return ok and type(list) == 'table' and list or {}
end

Veyl.RegisterCallback('garageList', function(src, citizenid)
    if not Phone.Session(src) then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    if GetResourceState('veyl_vehicles') ~= 'started' then return Veyl.Err('UNAVAILABLE', 'Vehicle records are unavailable right now') end
    local res = Veyl.Await('veyl_vehicles', 'GetOwnedVehicles', 10000, citizenid)
    if not res.ok then return res end
    local catalog = exports.veyl_core:GetVehicles() or {}
    local placeList = places()
    local byId = {}
    for _, p in ipairs(placeList) do byId[p.id] = p end
    local out = {}
    for i, v in ipairs(res.data or {}) do
        local def = catalog[v.model]
        local place = v.state == 'impound' and byId.impound or (v.state == 'garaged' and byId[v.garage]) or nil
        out[i] = {
            id = v.id, model = v.model, plate = v.plate, name = v.label or (def and def.name) or v.model, brand = def and def.brand or nil,
            state = v.out and 'out' or v.state, fuel = v.fuel, engine = v.engine, body = v.body,
            impoundFee = v.impoundFee, place = place and place.label or nil,
        }
    end
    return Veyl.Ok({ vehicles = out })
end, { cooldown = 500 })

--- garageLocate(ownedId) -> { x, y, label } : the live vehicle if it is out, otherwise its garage / the impound lot.
Veyl.RegisterCallback('garageLocate', function(src, citizenid, ownedId)
    if not Phone.Session(src) then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    if not Veyl.Validate.int(ownedId, 1) then return Veyl.Err('INVALID_INPUT', 'Invalid vehicle') end
    local res = Veyl.Await('veyl_vehicles', 'GetOwnedVehicles', 10000, citizenid)
    if not res.ok then return res end
    local v
    for _, row in ipairs(res.data or {}) do if row.id == ownedId then v = row end end
    if not v then return Veyl.Err('NOT_FOUND', 'Vehicle not found') end
    if v.out or v.state == 'out' then
        local live = Veyl.Await('veyl_vehicles', 'GetOwnedVehicleCoords', 10000, citizenid, ownedId)
        if live.ok then return Veyl.Ok({ x = live.data.x, y = live.data.y, label = v.plate }) end
        return Veyl.Err('NOT_FOUND', 'We could not find this vehicle. It may have been towed.')
    end
    for _, p in ipairs(places()) do
        if (v.state == 'impound' and p.kind == 'impound') or (v.state == 'garaged' and p.id == v.garage) then
            return Veyl.Ok({ x = p.x, y = p.y, label = p.label })
        end
    end
    return Veyl.Err('NOT_FOUND', 'That location is unavailable')
end, { cooldown = 800 })
