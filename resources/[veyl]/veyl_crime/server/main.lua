-- veyl_crime server: dark web orders and dead drops, USB dealer, fence, laundering, drug corners, turf and tags,
-- gang stashes, labs and branding. Every reward is decided and checked here.

local C = CrimeConfig
local seq = 0
local function op(kind, cid) seq = seq + 1 return ('crime:%s:%s:%d:%d'):format(kind, cid, os.time(), seq) end
local function core(name, ...) return Veyl.Await('veyl_core', name, 15000, ...) end
local function give(cid, item, n, meta, id) return Veyl.Await('veyl_inventory', 'GiveItem', 15000, cid, item, n, meta, id) end
local function count(src, item) return exports.veyl_inventory:GetItemCount(src, item) or 0 end
local function near(src, pos, d) local pc = Veyl.GetPlayerCoords(src) return pc ~= nil and #(pc - vector3(pos.x, pos.y, pos.z)) <= d end
local function busy(src) local st = Player(src).state return st.medical ~= nil or st.cuffed == true end

local catalog = {}
for i, c in ipairs(C.DarkWeb.Catalog) do catalog[i] = c end

Veyl.Startup({ 'veyl_core', 'veyl_inventory' }, function()
    local ok = Veyl.Migrate({
        { id = '001_init', sql = {
            [[CREATE TABLE IF NOT EXISTS veyl_crime_orders (
                id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                citizenid VARCHAR(16) NOT NULL,
                items LONGTEXT NOT NULL,
                drop_index TINYINT UNSIGNED NOT NULL,
                status ENUM('waiting','collected','expired') NOT NULL DEFAULT 'waiting',
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (id),
                KEY idx_cid (citizenid, status)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS veyl_crime_turf (
                zone VARCHAR(32) NOT NULL,
                gang VARCHAR(32) NOT NULL,
                rep INT NOT NULL DEFAULT 0,
                PRIMARY KEY (zone, gang)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        } },
    })
    if not ok then return false end
    exports.veyl_inventory:RegisterUseHandler('crime_tag', function(ctx) TriggerClientEvent('veyl_crime:tag', ctx.source) end)
    for gang, s in pairs(C.GangStashes) do
        exports.veyl_inventory:RegisterStash({ id = 'gang_' .. gang, label = s.label, slots = 60, maxWeight = 300000,
            groups = { [gang] = 0 }, coords = s.coords, radius = 2.5 })
    end
    return true
end)

---------------------------------------------------------------------------
-- USB dealer and dark web
---------------------------------------------------------------------------
Veyl.RegisterCallback('buyUsb', function(src, citizenid)
    if not near(src, C.UsbDealer.coords, 3.5) then return Veyl.Err('TOO_FAR', 'Talk to him') end
    if count(src, C.DarkWeb.UnlockItem) > 0 then return Veyl.Err('INVALID_STATE', 'You already have one') end
    local id = op('usb', citizenid)
    local r = core('DebitOnce', citizenid, 'cash', C.UsbDealer.price, 'Cash in hand', id)
    if not r.ok then return Veyl.Err('INSUFFICIENT_FUNDS', ('He wants $%d in cash'):format(C.UsbDealer.price)) end
    local g = give(citizenid, C.DarkWeb.UnlockItem, 1, nil, id .. ':item')
    if not g.ok then core('CreditOnce', citizenid, 'cash', C.UsbDealer.price, 'Refund', id .. ':refund') return Veyl.Err('INVENTORY_FULL', 'No room') end
    return Veyl.Ok(nil, '"Plug it into your phone. Do not call me."')
end, { cooldown = 2000 })

Veyl.RegisterCallback('darkweb', function(src, citizenid)
    if count(src, C.DarkWeb.UnlockItem) < 1 then return Veyl.Err('NO_PERMISSION', 'Connection refused') end
    local defs = exports.veyl_inventory:Items() or {}
    local list = {}
    for i, c in ipairs(catalog) do
        if defs[c.item] then list[#list + 1] = { index = i, item = c.item, label = defs[c.item].label, price = c.price } end
    end
    local orders = MySQL.query.await("SELECT id, items, drop_index FROM veyl_crime_orders WHERE citizenid = ? AND status = 'waiting' ORDER BY id", { citizenid }) or {}
    for _, o in ipairs(orders) do local d = C.DarkWeb.Drops[o.drop_index] o.x, o.y, o.z = d.x, d.y, d.z end
    return Veyl.Ok({ catalog = list, orders = orders })
end, { cooldown = 800 })

Veyl.RegisterCallback('order', function(src, citizenid, index, n)
    if count(src, C.DarkWeb.UnlockItem) < 1 then return Veyl.Err('NO_PERMISSION', 'Connection refused') end
    local c = catalog[tonumber(index) or 0]
    n = math.floor(tonumber(n) or 0)
    if not c or n < 1 or n > 250 then return Veyl.Err('INVALID_INPUT', 'Invalid order') end
    if c.item:sub(1, 7) == 'weapon_' and n > 3 then return Veyl.Err('INVALID_INPUT', 'Three weapons per order') end
    if MySQL.scalar.await("SELECT COUNT(*) FROM veyl_crime_orders WHERE citizenid = ? AND status = 'waiting'", { citizenid }) >= 3 then
        return Veyl.Err('RATE_LIMITED', 'Pick up your waiting orders first')
    end
    local total = c.price * n
    local id = op('order', citizenid)
    local r = core('DebitOnce', citizenid, 'cash', total, 'Cash drop', id)
    if not r.ok then return Veyl.Err('INSUFFICIENT_FUNDS', ('$%d in cash, no cards'):format(total)) end
    local drop = math.random(#C.DarkWeb.Drops)
    MySQL.insert.await('INSERT INTO veyl_crime_orders (citizenid, items, drop_index) VALUES (?, ?, ?)', { citizenid, json.encode({ { item = c.item, count = n } }), drop })
    local d = C.DarkWeb.Drops[drop]
    Veyl.Audit(src, 'crime_order', { item = c.item, count = n, total = total })
    return Veyl.Ok({ x = d.x, y = d.y, z = d.z }, ('Paid $%d. Your package is at the drop for %d min.'):format(total, C.DarkWeb.DropMinutes))
end, { cooldown = 2000 })

Veyl.RegisterCallback('collect', function(src, citizenid)
    local o
    for _, row in ipairs(MySQL.query.await("SELECT * FROM veyl_crime_orders WHERE citizenid = ? AND status = 'waiting'", { citizenid }) or {}) do
        if near(src, C.DarkWeb.Drops[row.drop_index], 3.0) then o = row break end
    end
    if not o then return Veyl.Err('NOT_FOUND', 'Nothing here for you') end
    if MySQL.update.await("UPDATE veyl_crime_orders SET status = 'collected' WHERE id = ? AND status = 'waiting'", { o.id }) ~= 1 then return Veyl.Err('NOT_FOUND', 'Nothing here') end
    local got = {}
    for i, it in ipairs(json.decode(o.items) or {}) do
        local isWeapon = it.item:sub(1, 7) == 'weapon_'
        for k = 1, isWeapon and it.count or 1 do
            local r = give(citizenid, it.item, isWeapon and 1 or it.count, isWeapon and { serial = 'SCRATCHED' } or nil, ('crime:drop:%d:%d:%d'):format(o.id, i, k))
            if r.ok or r.code == 'DUPLICATE_OPERATION' then got[#got + 1] = it.item end
        end
    end
    return Veyl.Ok(nil, #got > 0 and 'You grabbed the package' or 'Your pockets are full: make room and try again')
end, { cooldown = 1500 })

CreateThread(function()
    while true do
        Wait(60000)
        MySQL.update("UPDATE veyl_crime_orders SET status = 'expired' WHERE status = 'waiting' AND created_at < (NOW() - INTERVAL ? MINUTE)", { C.DarkWeb.DropMinutes })
    end
end)

---------------------------------------------------------------------------
-- Fence and laundering
---------------------------------------------------------------------------
Veyl.RegisterCallback('fence', function(src, citizenid)
    if not near(src, C.Fence.coords, 3.5) then return Veyl.Err('TOO_FAR', 'Talk to the fence') end
    local total = 0
    for item, price in pairs(C.Fence.prices) do
        local n = count(src, item)
        if n > 0 and exports.veyl_inventory:RemoveItem(src, item, n) then total = total + n * price end
    end
    if total == 0 then return Veyl.Err('NOT_FOUND', '"You got nothing I want."') end
    core('CreditOnce', citizenid, 'cash', total, 'Fence', op('fence', citizenid))
    Veyl.Audit(src, 'crime_fence', { total = total })
    return Veyl.Ok(nil, ('The fence paid $%d'):format(total))
end, { cooldown = 2000 })

local washing, lastWash = {}, {}
Veyl.RegisterCallback('washStart', function(src, citizenid)
    local L = C.Laundering
    if not near(src, L.coords, 3.0) then return Veyl.Err('TOO_FAR', 'Use the machines') end
    local wait = (lastWash[citizenid] or 0) + L.cooldownMinutes * 60 - os.time()
    if wait > 0 then return Veyl.Err('RATE_LIMITED', ('The machines are hot. %d min.'):format(math.ceil(wait / 60))) end
    local n = math.min(count(src, 'marked_bills'), L.maxPerRun)
    if n < 100 then return Veyl.Err('NO_ITEM', 'You need at least $100 in marked bills') end
    local token = Veyl.NewId()
    washing[src] = { token = token, at = GetGameTimer(), n = n }
    return Veyl.Ok({ token = token, seconds = L.seconds, amount = n })
end, { cooldown = 1000 })

Veyl.RegisterCallback('washFinish', function(src, citizenid, token)
    local w = washing[src]
    washing[src] = nil
    local L = C.Laundering
    if not w or w.token ~= token then return Veyl.Err('INVALID_STATE', 'Start again') end
    if GetGameTimer() - w.at < L.seconds * 1000 - 600 or not near(src, L.coords, 3.5) then return Veyl.Err('TOO_FAST', 'You walked away') end
    if not exports.veyl_inventory:RemoveItem(src, 'marked_bills', w.n) then return Veyl.Err('NO_ITEM', 'Your bills are gone') end
    local clean = math.floor(w.n * (1 - L.fee))
    core('CreditOnce', citizenid, 'cash', clean, 'Laundromat', 'crime:wash:' .. token)
    lastWash[citizenid] = os.time()
    Veyl.Audit(src, 'crime_launder', { dirty = w.n, clean = clean })
    return Veyl.Ok(nil, ('Washed $%d into $%d clean'):format(w.n, clean))
end, { cooldown = 500 })

---------------------------------------------------------------------------
-- Turf
---------------------------------------------------------------------------
local function zoneAt(src)
    local pc = Veyl.GetPlayerCoords(src)
    if not pc then return nil end
    for _, z in ipairs(C.Turf.Zones) do if #(pc - z.center) <= z.radius then return z end end
    return nil
end

local function gangOf(src)
    local pd = Veyl.GetPlayerData(src)
    return pd and pd.gang and pd.gang.name ~= 'none' and pd.gang.name or nil
end

local function controller(zone)
    return MySQL.scalar.await('SELECT gang FROM veyl_crime_turf WHERE zone = ? AND rep > 0 ORDER BY rep DESC LIMIT 1', { zone })
end

local function addRep(zone, gang, n)
    if not gang then return end
    MySQL.query('INSERT INTO veyl_crime_turf (zone, gang, rep) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE rep = rep + VALUES(rep)', { zone, gang, n })
end

Veyl.RegisterCallback('turf', function()
    local gangs = exports.veyl_core:GetGangs()
    local out = {}
    for _, z in ipairs(C.Turf.Zones) do
        local g = controller(z.id)
        out[#out + 1] = { label = z.label, gang = g and (gangs[g] and gangs[g].label or g) or nil }
    end
    return Veyl.Ok(out)
end, { cooldown = 2000 })

local lastTag = {}
Veyl.RegisterCallback('tag', function(src)
    local gang = gangOf(src)
    if not gang then return Veyl.Err('NO_PERMISSION', 'You are not in a gang') end
    local z = zoneAt(src)
    if not z then return Veyl.Err('NOT_FOUND', 'Nobody cares about this wall. Tag inside a turf.') end
    if count(src, 'spray_paint') < 1 then return Veyl.Err('NO_ITEM', 'You need spray paint') end
    local key = z.id .. ':' .. gang
    if (lastTag[key] or 0) + C.Turf.TagCooldownMinutes * 60 > os.time() then return Veyl.Err('RATE_LIMITED', 'Your gang tagged here recently') end
    lastTag[key] = os.time()
    exports.veyl_inventory:RemoveItem(src, 'spray_paint', 1)
    addRep(z.id, gang, C.Turf.TagRep)
    return Veyl.Ok(nil, ('Tagged %s (+%d rep)'):format(z.label, C.Turf.TagRep))
end, { cooldown = 3000 })

-- Daily decay.
CreateThread(function()
    while true do
        Wait(24 * 60 * 60 * 1000)
        MySQL.update('UPDATE veyl_crime_turf SET rep = FLOOR(rep * ?)', { 1 - C.Turf.DecayPercent / 100 })
    end
end)

---------------------------------------------------------------------------
-- Drug corners
---------------------------------------------------------------------------
local lastSale = {}

local function policeAlert(src, title)
    if GetResourceState('veyl_dispatch') ~= 'started' then return end
    pcall(function()
        exports.veyl_dispatch:Alert({ services = { 'police' }, code = '10-31', title = title, priority = 2, coords = Veyl.GetPlayerCoords(src),
            street = Player(src).state.street, message = 'A local reported someone selling drugs' })
    end)
end

Veyl.RegisterCallback('sell', function(src, citizenid)
    if busy(src) or GetVehiclePedIsIn(GetPlayerPed(src), false) ~= 0 then return Veyl.Err('INVALID_STATE', 'Not right now') end
    local wait = (lastSale[src] or 0) + C.Corners.CooldownSeconds - os.time()
    if wait > 0 then return Veyl.Err('RATE_LIMITED', 'Give it a moment') end
    lastSale[src] = os.time()
    -- What do they carry? The most valuable product goes first.
    local best, bestPrice
    for item, price in pairs(C.Corners.Products) do
        if count(src, item) > 0 and (not bestPrice or price > bestPrice) then best, bestPrice = item, price end
    end
    if not best then return Veyl.Err('NO_ITEM', 'You have nothing to sell') end
    local roll = math.random()
    if roll < C.Corners.Chance.police then
        policeAlert(src, 'Drug sale')
        return Veyl.Ok({ outcome = 'police' }, '"I am calling the cops!"')
    elseif roll < C.Corners.Chance.police + C.Corners.Chance.refuse then
        return Veyl.Ok({ outcome = 'refuse' }, '"Not interested."')
    end
    local slot = exports.veyl_inventory:GetSlotWithItem(src, best)
    local meta = slot and slot.metadata or {}
    local quality = math.max(40, math.min(100, tonumber(meta.quality) or 60))
    local n = math.min(math.random(1, C.Corners.MaxUnits), slot and slot.count or 1)
    if not exports.veyl_inventory:RemoveItem(src, best, n, meta) then return Veyl.Err('NO_ITEM', 'You fumbled the bag') end
    local z = zoneAt(src)
    local gang = gangOf(src)
    local bonus = (z and gang and controller(z.id) == gang) and (1 + C.Turf.ControlBonus) or 1
    local total = math.floor(bestPrice * n * quality / 100 * bonus)
    core('CreditOnce', citizenid, 'cash', total, 'Street sale', op('sale', citizenid))
    if z then addRep(z.id, gang, C.Turf.SaleRep * n) end
    return Veyl.Ok({ outcome = 'buy' }, ('Sold %d for $%d%s%s'):format(n, total, meta.brand and (' (' .. meta.brand .. ')') or '', bonus > 1 and ' · your turf' or ''))
end, { cooldown = 800 })

---------------------------------------------------------------------------
-- Labs and branding
---------------------------------------------------------------------------
local cooking = {}

Veyl.RegisterCallback('cookStart', function(src, _, index)
    local lab = C.Labs[tonumber(index) or 0]
    if not lab or not near(src, lab.coords, 3.0) then return Veyl.Err('TOO_FAR', 'Use the lab') end
    for item, n in pairs(lab.recipe.inputs) do if count(src, item) < n then return Veyl.Err('NO_ITEM', ('You need %dx %s'):format(n, item)) end end
    local token = Veyl.NewId()
    cooking[src] = { index = tonumber(index), token = token, at = GetGameTimer() }
    return Veyl.Ok({ token = token, seconds = lab.seconds })
end, { cooldown = 1000 })

Veyl.RegisterCallback('cookFinish', function(src, citizenid, token)
    local c = cooking[src]
    cooking[src] = nil
    if not c or c.token ~= token then return Veyl.Err('INVALID_STATE', 'Start again') end
    local lab = C.Labs[c.index]
    if GetGameTimer() - c.at < lab.seconds * 1000 - 600 or not near(src, lab.coords, 3.5) then return Veyl.Err('TOO_FAST', 'You walked away') end
    for item, n in pairs(lab.recipe.inputs) do
        if not exports.veyl_inventory:RemoveItem(src, item, n) then return Veyl.Err('NO_ITEM', 'Missing chemicals') end
    end
    local brand = exports.veyl_core:GetMetadata(src, 'drugbrand')
    local q = math.random(lab.recipe.quality[1], lab.recipe.quality[2])
    local meta = { product = lab.recipe.output, quality = q, batch = token:sub(-6), brand = type(brand) == 'string' and brand or nil }
    local r = give(citizenid, lab.recipe.output, lab.recipe.count, meta, 'crime:cook:' .. token)
    if not r.ok then return Veyl.Err('INVENTORY_FULL', 'No room: the batch is ruined') end
    return Veyl.Ok(nil, ('Made %dx at %d%% quality%s'):format(lab.recipe.count, q, meta.brand and (' · "' .. meta.brand .. '"') or ''))
end, { cooldown = 500 })

RegisterCommand('brand', function(src, args)
    if src == 0 then return end
    local name = table.concat(args, ' '):gsub('[^%w %-%.\']', ''):sub(1, C.BrandMaxLength)
    if #name < 2 then return Veyl.Notify(src, 'Usage: /brand <name> (your lab products carry it)', 'error') end
    exports.veyl_core:SetMetadata(src, 'drugbrand', name)
    Veyl.Notify(src, ('Your brand is now "%s"'):format(name), 'success')
end, false)

AddEventHandler('playerDropped', function() washing[source], cooking[source], lastSale[source] = nil, nil, nil end)
