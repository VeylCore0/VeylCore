-- veyl_vehicles services (server): trunks and gloveboxes, custom plates, fake plates, ownership transfers and insurance.

local C = VehiclesConfig
local function core(name, ...) return Veyl.Await('veyl_core', name, 15000, ...) end
local function charName(pd) return pd and ('%s %s'):format(pd.charinfo.firstname or '', pd.charinfo.lastname or '') or 'Unknown' end
local function trim(p) return (tostring(p or ''):gsub('^%s+', ''):gsub('%s+$', '')) end

local function entityFromNet(netId)
    netId = tonumber(netId)
    if not netId then return nil end
    local e = NetworkGetEntityFromNetworkId(netId)
    if not e or e == 0 or not DoesEntityExist(e) or GetEntityType(e) ~= 2 then return nil end
    return e
end

local function distTo(src, entity)
    local pc = Veyl.GetPlayerCoords(src)
    return pc and #(pc - GetEntityCoords(entity)) or math.huge
end

---------------------------------------------------------------------------
-- Trunks and gloveboxes: keyed stashes in veyl_inventory ('veh_trunk@<netId>', 'veh_glovebox@<netId>')
---------------------------------------------------------------------------
local function registerStorage()
    local auth = { resource = 'veyl_vehicles', export = 'StorageAccess' }
    exports.veyl_inventory:RegisterStash({ id = 'veh_trunk', label = 'Trunk', slots = C.Trunk.slots, maxWeight = C.Trunk.maxWeight, keyed = true, authorize = auth })
    exports.veyl_inventory:RegisterStash({ id = 'veh_glovebox', label = 'Glovebox', slots = C.Glovebox.slots, maxWeight = C.Glovebox.maxWeight, keyed = true, authorize = auth })
end
CreateThread(function()
    while GetResourceState('veyl_inventory') ~= 'started' do Wait(500) end
    Wait(500)
    registerStorage()
end)
-- veyl_inventory forgets registrations when it restarts: register again.
AddEventHandler('onResourceStart', function(res) if res == 'veyl_inventory' then SetTimeout(1500, registerStorage) end end)

--- Called by veyl_inventory before every open and every move: (src, citizenid, stashId, key) -> storageKey (string) when
--- allowed, or false, code when refused.
--- Owned vehicles keep their storage for good ('own<id>'); any other vehicle (dealer test cars, job vehicles, cars spawned
--- by staff menus, NPC cars) uses its plate ('p<PLATE>').
exports('StorageAccess', function(src, citizenid, stashId, key)
    local entity = entityFromNet(key)
    if not entity then return '!NOT_FOUND' end
    local ped = GetPlayerPed(src)
    if stashId == 'veh_glovebox' then
        if GetVehiclePedIsIn(ped, false) ~= entity then return '!TOO_FAR' end
    else
        if GetVehicleType(entity) == 'bike' then return '!NO_PERMISSION' end
        if GetVehiclePedIsIn(ped, false) ~= entity then
            if distTo(src, entity) > C.Trunk.distance then return '!TOO_FAR' end
            -- Locked: only someone with the keys can open it.
            if GetVehicleDoorLockStatus(entity) >= 2 then
                local vid = exports.veyl_vehicles:GetVehicleIdFromEntity(entity)
                local hasKey = vid and GetResourceState('veyl_vehiclekeys') == 'started' and exports.veyl_vehiclekeys:HasKey(vid, citizenid)
                if not hasKey then return '!LOCKED' end
            end
        end
    end
    local ownedId = exports.veyl_vehicles:GetOwnedVehicleIdFromEntity(entity)
    if ownedId then return ('own%d'):format(ownedId) end
    -- A fake plate must not open someone else's trunk: use the real one.
    local plate = (Entity(entity).state.realPlate or GetVehicleNumberPlateText(entity) or ''):gsub('[^%w]', ''):upper()
    if plate == '' then return '!NOT_FOUND' end
    return 'p' .. plate
end)

---------------------------------------------------------------------------
-- Custom plates (plate shop)
---------------------------------------------------------------------------
Veyl.RegisterCallback('customPlate', function(src, citizenid, netId, text)
    local entity = entityFromNet(netId)
    if not entity or GetVehiclePedIsIn(GetPlayerPed(src), false) ~= entity then return Veyl.Err('INVALID_STATE', 'Sit in your vehicle') end
    local pc = Veyl.GetPlayerCoords(src)
    if #(pc - C.PlateShop.coords.xyz) > C.PlateShop.radius then return Veyl.Err('TOO_FAR', 'Drive into the plate shop') end
    local ownedId = exports.veyl_vehicles:GetOwnedVehicleIdFromEntity(entity)
    local row = ownedId and MySQL.single.await('SELECT id, plate FROM veyl_player_vehicles WHERE id = ? AND citizenid = ?', { ownedId, citizenid })
    if not row then return Veyl.Err('NO_PERMISSION', 'Only the registered owner can change the plate') end
    text = type(text) == 'string' and text:upper() or ''
    if not text:match('^[A-Z0-9 ]+$') or #trim(text) < 2 or #text > 8 then return Veyl.Err('INVALID_INPUT', 'Letters, numbers and spaces, 2 to 8 characters') end
    for _, bad in ipairs(C.PlateShop.blocked) do if text:find(bad, 1, true) then return Veyl.Err('INVALID_INPUT', 'That plate is not allowed') end end
    if MySQL.scalar.await('SELECT 1 FROM veyl_player_vehicles WHERE plate = ?', { text }) then return Veyl.Err('INVALID_STATE', 'That plate is taken') end
    local opId = ('plate:%d:%s'):format(ownedId, text:gsub(' ', '_'))
    local pay = core('DebitOnce', citizenid, 'bank', C.PlateShop.price, ('Custom plate %s'):format(text), opId)
    if not pay.ok and pay.code ~= 'DUPLICATE_OPERATION' then return Veyl.Err(pay.code or 'INSUFFICIENT_FUNDS', ('A custom plate costs $%d'):format(C.PlateShop.price)) end
    local ok = pcall(MySQL.update.await, 'UPDATE veyl_player_vehicles SET plate = ? WHERE id = ?', { text, ownedId })
    if not ok then
        core('CreditOnce', citizenid, 'bank', C.PlateShop.price, 'Custom plate refund', opId .. ':refund')
        return Veyl.Err('INVALID_STATE', 'That plate was just taken. Refunded.')
    end
    SetVehicleNumberPlateText(entity, text)
    exports.veyl_vehicles:SetTrackedPlate(exports.veyl_vehicles:GetVehicleIdFromEntity(entity), text)
    Veyl.Audit(src, 'vehicle_plate', { ownedId = ownedId, from = row.plate, to = text })
    return Veyl.Ok({ plate = text }, ('New plate: %s'):format(text))
end, { cooldown = 3000 })

---------------------------------------------------------------------------
-- Fake plates (item): put on hides the registered plate; using it again takes it off and gives the plate back
---------------------------------------------------------------------------
local PLATE_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ0123456789'
local function randomPlate()
    local t = {}
    for i = 1, 8 do local n = math.random(1, #PLATE_CHARS) t[i] = PLATE_CHARS:sub(n, n) end
    t[4] = ' '
    return table.concat(t)
end

local function nearestVehicle(src, maxDist)
    local pc = Veyl.GetPlayerCoords(src)
    if not pc then return nil end
    local best, bd = nil, maxDist
    for _, v in ipairs(GetAllVehicles()) do
        local d = #(GetEntityCoords(v) - pc)
        if d < bd then best, bd = v, d end
    end
    return best
end

CreateThread(function()
    while GetResourceState('veyl_inventory') ~= 'started' do Wait(500) end
    Wait(500)
    exports.veyl_inventory:RegisterUseHandler('fake_plate', function(ctx)
        local src = ctx.source
        local entity = nearestVehicle(src, 3.5)
        if not entity or GetVehiclePedIsIn(GetPlayerPed(src), false) == entity then return Veyl.Notify(src, 'Stand at the back of a vehicle', 'error') end
        local vehicleId = exports.veyl_vehicles:GetVehicleIdFromEntity(entity)
        if not vehicleId or not exports.veyl_vehiclekeys:HasKey(vehicleId, ctx.citizenid) then return Veyl.Notify(src, 'You need the keys to this vehicle', 'error') end
        local st = Entity(entity).state
        if st.realPlate then return Veyl.Notify(src, 'It already has a fake plate. Take it off from the vehicle menu first.', 'error') end
        if not exports.veyl_inventory:RemoveItem(src, 'fake_plate', 1) then return end
        local real = GetVehicleNumberPlateText(entity)
        st:set('realPlate', real, true)
        SetVehicleNumberPlateText(entity, randomPlate())
        Veyl.Audit(src, 'fake_plate_on', { vehicleId = vehicleId })
        Veyl.Notify(src, 'Fake plate fitted', 'success')
    end)
end)

Veyl.RegisterCallback('removeFakePlate', function(src, citizenid, netId)
    local entity = entityFromNet(netId)
    if not entity or distTo(src, entity) > 4.0 then return Veyl.Err('TOO_FAR', 'Move closer') end
    local st = Entity(entity).state
    if not st.realPlate then return Veyl.Err('INVALID_STATE', 'This plate is real') end
    local vehicleId = exports.veyl_vehicles:GetVehicleIdFromEntity(entity)
    if not vehicleId or not exports.veyl_vehiclekeys:HasKey(vehicleId, citizenid) then return Veyl.Err('NO_PERMISSION', 'You need the keys') end
    SetVehicleNumberPlateText(entity, st.realPlate)
    st:set('realPlate', nil, true)
    exports.veyl_inventory:AddItem(src, 'fake_plate', 1)
    return Veyl.Ok(nil, 'Real plate back on')
end, { cooldown = 3000 })

--- Police: the real registration behind a fake plate (for the MDT and checks).
exports('GetRealPlate', function(entity)
    local st = entity and DoesEntityExist(entity) and Entity(entity).state
    return st and st.realPlate or (entity and DoesEntityExist(entity) and GetVehicleNumberPlateText(entity)) or nil
end)

---------------------------------------------------------------------------
-- Ownership transfer: the owner offers the vehicle (optionally for a price) to a player standing next to it
---------------------------------------------------------------------------
local offers = {} -- [token] = { from, to, ownedId, entity, price, expires }

Veyl.RegisterCallback('transferOffer', function(src, citizenid, netId, target, price)
    local entity = entityFromNet(netId)
    if not entity or distTo(src, entity) > 6.0 then return Veyl.Err('TOO_FAR', 'Stand next to the vehicle') end
    local ownedId = exports.veyl_vehicles:GetOwnedVehicleIdFromEntity(entity)
    local row = ownedId and MySQL.single.await('SELECT id, plate, model, label FROM veyl_player_vehicles WHERE id = ? AND citizenid = ?', { ownedId, citizenid })
    if not row then return Veyl.Err('NO_PERMISSION', 'Only the registered owner can sell this vehicle') end
    target = tonumber(target)
    local tcid = target and Veyl.GetCitizenId(target)
    if not tcid or target == src or distTo(target, entity) > 8.0 then return Veyl.Err('NOT_FOUND', 'The buyer must be next to the vehicle') end
    price = math.floor(tonumber(price) or 0)
    if price < 0 or price > 10000000 then return Veyl.Err('INVALID_INPUT', 'Invalid price') end
    local token = Veyl.NewId()
    offers[token] = { from = src, fromCid = citizenid, to = target, toCid = tcid, ownedId = ownedId, entity = entity, price = price, expires = os.time() + 60 }
    TriggerClientEvent('veyl_vehicles:transferPrompt', target, token, { seller = charName(Veyl.GetPlayerData(src)), vehicle = row.label or row.model, plate = row.plate, price = price })
    return Veyl.Ok(nil, 'Offer sent')
end, { cooldown = 3000 })

Veyl.RegisterCallback('transferAnswer', function(src, citizenid, token, accept)
    local o = type(token) == 'string' and offers[token]
    if not o or o.to ~= src or o.toCid ~= citizenid then return Veyl.Err('NOT_FOUND', 'This offer is no longer valid') end
    offers[token] = nil
    if accept ~= true then
        if GetPlayerName(o.from) then Veyl.Notify(o.from, 'The buyer declined', 'info') end
        return Veyl.Ok(nil, 'Declined')
    end
    if os.time() > o.expires then return Veyl.Err('EXPIRED', 'The offer expired') end
    if not DoesEntityExist(o.entity) or distTo(src, o.entity) > 8.0 then return Veyl.Err('TOO_FAR', 'Stay next to the vehicle') end
    if o.price > 0 then
        local pay = core('TransferMoney', citizenid, 'bank', o.fromCid, 'bank', o.price, ('Vehicle purchase (#%d)'):format(o.ownedId), 'vehtransfer:' .. token)
        if not pay.ok and pay.code ~= 'DUPLICATE_OPERATION' then return Veyl.Err(pay.code or 'INSUFFICIENT_FUNDS', ('You need $%d in the bank'):format(o.price)) end
    end
    local n = MySQL.update.await('UPDATE veyl_player_vehicles SET citizenid = ?, insured_until = NULL WHERE id = ? AND citizenid = ?', { citizenid, o.ownedId, o.fromCid })
    if n ~= 1 then
        if o.price > 0 then core('TransferMoney', o.fromCid, 'bank', citizenid, 'bank', o.price, 'Vehicle purchase refund', 'vehtransfer:' .. token .. ':refund') end
        return Veyl.Err('INVALID_STATE', 'The vehicle could not be transferred')
    end
    local vehicleId = exports.veyl_vehicles:GetVehicleIdFromEntity(o.entity)
    if vehicleId then
        exports.veyl_vehicles:SetTrackedOwner(vehicleId, citizenid)
        exports.veyl_vehiclekeys:GiveKey(vehicleId, citizenid)
        exports.veyl_vehiclekeys:RevokeKey(vehicleId, o.fromCid)
    end
    Veyl.Audit(src, 'vehicle_transfer', { ownedId = o.ownedId, from = o.fromCid, to = citizenid, price = o.price })
    if GetPlayerName(o.from) then Veyl.Notify(o.from, o.price > 0 and ('Sold for $%d'):format(o.price) or 'Vehicle handed over', 'success') end
    return Veyl.Ok(nil, 'The vehicle is yours. Insurance does not transfer.')
end, { cooldown = 1500 })

---------------------------------------------------------------------------
-- Insurance: weekly cover. Wrecked or abandoned insured vehicles are recovered and repaired for free.
---------------------------------------------------------------------------
local function nearOffice(src) local pc = Veyl.GetPlayerCoords(src) return pc and #(pc - C.Insurance.coords.xyz) <= 4.0 end

Veyl.RegisterCallback('insuranceList', function(src, citizenid)
    if not nearOffice(src) then return Veyl.Err('TOO_FAR', 'Visit the insurance office') end
    local rows = MySQL.query.await([[SELECT id, model, label, plate, DATE_FORMAT(insured_until, '%b %e, %H:%i') AS until_at, insured_until > NOW() AS active
        FROM veyl_player_vehicles WHERE citizenid = ? ORDER BY id]], { citizenid }) or {}
    return Veyl.Ok({ vehicles = rows, weekly = C.Insurance.weekly })
end, { cooldown = 500 })

Veyl.RegisterCallback('insuranceBuy', function(src, citizenid, ownedId, weeks)
    if not nearOffice(src) then return Veyl.Err('TOO_FAR', 'Visit the insurance office') end
    ownedId, weeks = tonumber(ownedId), math.floor(tonumber(weeks) or 0)
    if not ownedId or weeks < 1 or weeks > C.Insurance.maxWeeks then return Veyl.Err('INVALID_INPUT', ('1 to %d weeks'):format(C.Insurance.maxWeeks)) end
    local row = MySQL.single.await('SELECT id, plate FROM veyl_player_vehicles WHERE id = ? AND citizenid = ?', { ownedId, citizenid })
    if not row then return Veyl.Err('NOT_FOUND', 'Not your vehicle') end
    local cost = C.Insurance.weekly * weeks
    local pay = core('DebitOnce', citizenid, 'bank', cost, ('Insurance %s, %d week(s)'):format(row.plate, weeks), ('insure:%d:%d:%d'):format(ownedId, os.time(), weeks))
    if not pay.ok then return Veyl.Err(pay.code or 'INSUFFICIENT_FUNDS', ('Cover costs $%d from your bank'):format(cost)) end
    MySQL.update.await([[UPDATE veyl_player_vehicles SET insured_until = GREATEST(COALESCE(insured_until, NOW()), NOW()) + INTERVAL ? DAY WHERE id = ?]], { weeks * 7, ownedId })
    return Veyl.Ok(nil, ('%s insured for %d more week(s)'):format(row.plate, weeks))
end, { cooldown = 2000 })

exports('IsInsured', function(ownedId)
    return MySQL.scalar.await('SELECT 1 FROM veyl_player_vehicles WHERE id = ? AND insured_until > NOW()', { ownedId }) ~= nil
end)

AddEventHandler('playerDropped', function()
    local src = source
    for t, o in pairs(offers) do if o.from == src or o.to == src then offers[t] = nil end end
end)
