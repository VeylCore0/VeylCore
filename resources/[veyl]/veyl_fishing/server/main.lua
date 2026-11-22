-- veyl_fishing server: casting (rod use), bites, catches by zone, selling at the market.
-- A cast is a token: the bite time is decided here, and a catch only counts if the player reacted after it.

local C = FishingConfig
local casts = {} -- [src] = { token, zone, biteAt }

local function core(name, ...) return Veyl.Await('veyl_core', name, 15000, ...) end
local function inv(name, ...) return Veyl.Await('veyl_inventory', name, 15000, ...) end

local function zoneAt(src)
    local pc = Veyl.GetPlayerCoords(src)
    if not pc then return nil end
    for i, z in ipairs(C.Zones) do if #(pc - z.center) <= z.radius then return i, z end end
    return nil
end

Veyl.Startup({ 'veyl_core', 'veyl_inventory' }, function()
    exports.veyl_inventory:RegisterUseHandler('fishing_rod', function(ctx) TriggerClientEvent('veyl_fishing:use', ctx.source) end)
    return true
end)

local function fishCount(src)
    local n = 0
    for item in pairs(C.Fish) do n = n + (exports.veyl_inventory:GetItemCount(src, item) or 0) end
    return n
end

Veyl.RegisterCallback('cast', function(src)
    local zi, z = zoneAt(src)
    if not zi then return Veyl.Err('TOO_FAR', 'Nothing bites here. Try a pier or a lake.') end
    if Player(src).state.medical or Player(src).state.cuffed then return Veyl.Err('INVALID_STATE', 'Not right now') end
    if (exports.veyl_inventory:GetItemCount(src, C.Rod) or 0) < 1 then return Veyl.Err('NO_ITEM', 'You need a fishing rod') end
    if (exports.veyl_inventory:GetItemCount(src, C.Bait) or 0) < 1 then return Veyl.Err('NO_ITEM', 'You need bait') end
    if fishCount(src) >= C.MaxCarry then return Veyl.Err('INVENTORY_FULL', 'Sell your catch first') end
    local wait = math.random(C.WaitSeconds[1] * 10, C.WaitSeconds[2] * 10) / 10
    local token = Veyl.NewId()
    casts[src] = { token = token, zone = zi, biteAt = GetGameTimer() + math.floor(wait * 1000) }
    return Veyl.Ok({ token = token, biteIn = wait, react = C.ReactSeconds, zone = z.label })
end, { cooldown = 1500 })

local function roll(catch)
    local total = 0
    for _, w in pairs(catch) do total = total + w end
    local r = math.random() * total
    for item, w in pairs(catch) do
        r = r - w
        if r <= 0 then return item end
    end
    return 'junk'
end

Veyl.RegisterCallback('reel', function(src, citizenid, token, reacted)
    local c = casts[src]
    casts[src] = nil
    if not c or c.token ~= token then return Veyl.Err('INVALID_STATE', 'Cast again') end
    local now = GetGameTimer()
    if now < c.biteAt then return Veyl.Ok({ caught = false }, 'Too early: you pulled it out of the water') end
    if reacted ~= true or now > c.biteAt + C.ReactSeconds * 1000 + 1500 then return Veyl.Ok({ caught = false }, 'It got away') end
    if zoneAt(src) ~= c.zone then return Veyl.Err('TOO_FAR', 'You moved away') end
    if not exports.veyl_inventory:RemoveItem(src, C.Bait, 1) then return Veyl.Err('NO_ITEM', 'You need bait') end
    local item = roll(C.Zones[c.zone].catch)
    if item == 'junk' then return Veyl.Ok({ caught = false }, 'Just seaweed and an old boot. The bait is gone.') end
    local r = inv('GiveItem', citizenid, item, 1, nil, 'fishing:' .. token)
    if not r.ok and r.code ~= 'DUPLICATE_OPERATION' then return Veyl.Err('INVENTORY_FULL', 'No room for the fish. It slipped away.') end
    return Veyl.Ok({ caught = true, item = item }, ('You caught a %s!'):format(C.Fish[item].label))
end, { cooldown = 500 })

Veyl.RegisterCallback('sell', function(src, citizenid)
    local m = C.Market.coords
    local pc = Veyl.GetPlayerCoords(src)
    if not pc or #(pc - vector3(m.x, m.y, m.z)) > 4.0 then return Veyl.Err('TOO_FAR', 'Talk to the buyer') end
    local total, sold = 0, 0
    for item, f in pairs(C.Fish) do
        local n = exports.veyl_inventory:GetItemCount(src, item) or 0
        if n > 0 and exports.veyl_inventory:RemoveItem(src, item, n) then
            total, sold = total + n * f.price, sold + n
        end
    end
    if sold == 0 then return Veyl.Err('NOT_FOUND', 'You have no fish to sell') end
    local r = core('CreditOnce', citizenid, 'cash', total, ('Fish market: %d fish'):format(sold), ('fishing:sell:%s:%d'):format(citizenid, os.time()))
    if not r.ok and r.code ~= 'DUPLICATE_OPERATION' then return Veyl.Err('INTERNAL', 'The buyer could not pay. Try again.') end
    Veyl.Audit(src, 'fishing_sell', { count = sold, total = total })
    return Veyl.Ok(nil, ('Sold %d fish for $%d'):format(sold, total))
end, { cooldown = 2000 })

AddEventHandler('playerDropped', function() casts[source] = nil end)
