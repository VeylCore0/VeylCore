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
    return Veyl.Ok({ vehicles = out, valetFee = PhoneConfig.Valet.Fee })
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


local C = PhoneConfig
local function session(src)
    local s = Phone.Session(src)
    if not s then return nil, Veyl.Err('NO_SESSION', 'Open your phone first') end
    return s
end
local function core(name, ...) return Veyl.Await('veyl_core', name, 15000, ...) end
local seq = 0
local function op(kind, cid) seq = seq + 1 return ('phone:%s:%s:%d:%d'):format(kind, cid, os.time(), seq) end

---------------------------------------------------------------------------
-- Garage valet: a garaged vehicle is brought to the road next to you
---------------------------------------------------------------------------
Veyl.RegisterCallback('garageValet', function(src, citizenid, ownedId, spot)
    local _, err = session(src)
    if err then return err end
    ownedId = tonumber(ownedId)
    if not ownedId or type(spot) ~= 'table' or not tonumber(spot.x) then return Veyl.Err('INVALID_INPUT', 'Invalid request') end
    local pc = Veyl.GetPlayerCoords(src)
    local at = vector3(spot.x + 0.0, spot.y + 0.0, spot.z + 0.0)
    if not pc or #(pc - at) > 80.0 then return Veyl.Err('TOO_FAR', 'Stand near a road') end
    if not MySQL.scalar.await("SELECT 1 FROM veyl_player_vehicles WHERE id = ? AND citizenid = ? AND state = 'garaged'", { ownedId, citizenid }) then
        return Veyl.Err('INVALID_STATE', 'Only vehicles parked in a garage can be delivered')
    end
    local id = op('valet', citizenid)
    local pay = core('DebitOnce', citizenid, 'bank', C.Valet.Fee, 'Valet delivery', id)
    if not pay.ok then return Veyl.Err('INSUFFICIENT_FUNDS', ('Valet costs $%d from your bank'):format(C.Valet.Fee)) end
    local r = Veyl.Await('veyl_vehicles', 'SpawnOwnedVehicle', 20000, src, citizenid, ownedId, vector4(at.x, at.y, at.z, tonumber(spot.h) or 0.0), { from = 'garaged' })
    if not r.ok then
        core('CreditOnce', citizenid, 'bank', C.Valet.Fee, 'Valet delivery refund', id .. ':refund')
        return Veyl.Err(r.code or 'INTERNAL', r.message or 'The valet could not bring it. Refunded.')
    end
    return Veyl.Ok({ x = at.x, y = at.y }, ('Your vehicle is waiting on the road ($%d)'):format(C.Valet.Fee))
end, { cooldown = 5000 })
