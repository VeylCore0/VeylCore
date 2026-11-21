-- veyl_dealership server: catalog and purchases. Prices come from veyl_core's vehicle catalog (server side).
-- A purchase is one operation id 'dealer:<citizenid>:<client op>':
--   DebitOnce(op) -> RegisterOwnedVehicle(created_op = op) -> deliver (spawn) or park in the fallback garage.
-- Repeating the same op never charges twice and never registers a second vehicle. If registration fails after
-- the charge, the charge is refunded once (op .. ':refund').

Veyl.Startup({ 'veyl_core', 'veyl_vehicles' }, function() return true end)

local function core(name, ...) return Veyl.Await('veyl_core', name, 15000, ...) end
local function vehicles(name, ...) return Veyl.Await('veyl_vehicles', name, 20000, ...) end

local function forSale()
    local out = {}
    for model, def in pairs(exports.veyl_core:GetVehicles()) do
        if def.shop == DealershipConfig.Shop and (tonumber(def.price) or 0) > 0 then out[model] = def end
    end
    return out
end

local function nearCounter(src)
    local pc, c = Veyl.GetPlayerCoords(src), DealershipConfig.Salesperson.coords
    return pc ~= nil and #(pc - vector3(c.x, c.y, c.z)) <= DealershipConfig.UseRadius + 4.0
end

local function balancesOf(src)
    local pd = Veyl.GetPlayerData(src)
    return { cash = pd and pd.money.cash or 0, bank = pd and pd.money.bank or 0 }
end

Veyl.RegisterCallback('catalog', function(src)
    if not nearCounter(src) then return Veyl.Err('TOO_FAR', 'Talk to the salesperson') end
    local list = {}
    for model, def in pairs(forSale()) do
        list[#list + 1] = { model = model, name = def.name, brand = def.brand, price = def.price, category = def.category }
    end
    table.sort(list, function(a, b) if a.category ~= b.category then return a.category < b.category end return a.price < b.price end)
    return Veyl.Ok({
        title = DealershipConfig.Label, subtitle = DealershipConfig.Subtitle, categories = DealershipConfig.Categories,
        vehicles = list, balances = balancesOf(src), methods = DealershipConfig.PaymentMethods,
    })
end, { cooldown = 750 })

--- purchase({ model, method, opId, expectedPrice, deliver = bool })
Veyl.RegisterCallback('purchase', function(src, citizenid, req)
    if type(req) ~= 'table' then return Veyl.Err('INVALID_INPUT', 'Invalid request') end
    if not nearCounter(src) then return Veyl.Err('TOO_FAR', 'Talk to the salesperson') end
    local def = Veyl.Validate.str(req.model, 1, 64) and forSale()[req.model]
    if not def then return Veyl.Err('NOT_FOUND', 'That vehicle is not for sale') end
    if not Veyl.Validate.oneOf(req.method, DealershipConfig.PaymentMethods) then return Veyl.Err('INVALID_INPUT', 'Choose cash or bank') end
    if not Veyl.Validate.str(req.opId, 8, 64, '^[%w%-]+$') then return Veyl.Err('INVALID_INPUT', 'Missing operation id') end
    if tonumber(req.expectedPrice) ~= def.price then
        return Veyl.Err('PRICE_CHANGED', ('The price is now $%d'):format(def.price), { price = def.price })
    end

    local op = ('dealer:%s:%s'):format(citizenid, req.opId)
    local pay = core('DebitOnce', citizenid, req.method, def.price, ('Vehicle purchase: %s %s'):format(def.brand or '', def.name), op)
    if not pay.ok and pay.code ~= 'DUPLICATE_OPERATION' then
        if pay.code == 'TIMEOUT' then return Veyl.Err('PENDING', 'Payment is being verified. Press Buy again to check.') end
        return pay
    end
    if pay.code == 'DUPLICATE_OPERATION' then
        -- A repeat of an earlier attempt: if that attempt was refunded, it must not turn into a free vehicle now.
        local refunded = core('GetMoneyOperation', op .. ':refund')
        if refunded.ok and refunded.data then return Veyl.Err('INVALID_STATE', 'That purchase was refunded. Start a new purchase.') end
    end

    local reg = vehicles('RegisterOwnedVehicle', citizenid, req.model, { label = def.name, garage = DealershipConfig.FallbackGarage, opId = op })
    if not reg.ok then
        local refund = core('CreditOnce', citizenid, req.method, def.price, ('Refund: %s registration failed'):format(def.name), op .. ':refund')
        print(('^1[veyl_dealership] registration failed for %s (%s); refund: %s^7'):format(citizenid, op, tostring(refund.ok or refund.code)))
        return Veyl.Err('DATABASE_ERROR', 'The sale could not be completed; you have been refunded')
    end
    if reg.data.existing then
        return Veyl.Ok({ plate = reg.data.plate, delivered = false, balances = balancesOf(src) },
            ('You already bought this %s (plate %s).'):format(def.name, reg.data.plate))
    end
    Veyl.Audit(src, 'vehicle_purchase', { model = req.model, price = def.price, plate = reg.data.plate, op = op })

    -- Deliver to the bay when the client says it's clear; otherwise (or on failure) it waits in the fallback garage.
    if req.deliver and not reg.data.existing then
        local spawned = vehicles('SpawnOwnedVehicle', src, citizenid, reg.data.ownedId, DealershipConfig.Delivery,
            { from = 'garaged', garage = DealershipConfig.FallbackGarage })
        if spawned.ok then
            return Veyl.Ok({ plate = reg.data.plate, delivered = true, balances = balancesOf(src) },
                ('Bought the %s (plate %s). It is outside.'):format(def.name, reg.data.plate))
        end
    end
    return Veyl.Ok({ plate = reg.data.plate, delivered = false, balances = balancesOf(src) },
        ('Bought the %s (plate %s). Collect it from the garage.'):format(def.name, reg.data.plate))
end, { cooldown = 2000 })
