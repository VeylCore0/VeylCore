-- Selling to pedestrians and the street economy around it. Two steps, both decided here: an offer (is this ped real, in range and willing,
-- what could you sell) and a sale (what they take and pay). The ped's answer is rolled at the offer and the ped is used up for everyone for
-- a while, so walking away and asking again gains nothing. The client only names a ped (or a meeting) and, later, an item and a count.
--
-- Around that:
--   * the market (server/market.lua) moves every item's price with what has been sold,
--   * territories (config/economy.lua) change prices and how willing peds are, build heat while you sell, and give influence to your crew,
--   * regulars are peds you built a relationship with: they buy more, pay better and meet you at a spot the server sends you to.

Prod = Prod or {}
Prod.Street = { sessions = {}, peds = {}, hourly = {}, heat = {}, influence = {}, meets = {} }
local S = Prod.Street
local C = ProductionConfig

local function cfg() return C.Street end
local function areas() return C.Territories.Areas end

---------------------------------------------------------------------------
-- Territories, heat, influence
---------------------------------------------------------------------------

--- The territory a position is in, or a cell of the open streets (no modifiers).
function S.zoneAt(pos)
    local best, bestD
    for _, a in ipairs(areas()) do
        local d = ProdUtil.distance2d(pos, a.center)
        if d <= a.radius and (not bestD or d < bestD) then best, bestD = a, d end
    end
    if best then return best end
    local cell = C.Territories.OutsideCell
    return { id = ('cell:%d:%d'):format(math.floor(pos.x / cell), math.floor(pos.y / cell)), label = 'The streets', price = 1.0, accept = 1.0, wild = true }
end

local function heatNow(id)
    local h = S.heat[id]
    if not h then return 0 end
    local v = h.v - (os.time() - h.at) / 60 * C.Territories.Heat.DecayPerMinute
    return v > 0 and v or 0
end
S.heatNow = heatNow

local function addHeat(id)
    local H = C.Territories.Heat
    S.heat[id] = { v = math.min(H.Max, heatNow(id) + H.PerSale), at = os.time() }
end

--- Influence belongs to a crew, or to a lone player without one. Decays by a share every hour.
local function ownerKey(cid)
    local crew = Prod.Crews.of(cid)
    if crew then return 'c' .. crew.id end
    return 'p' .. cid
end

local function infNow(area, key)
    local r = S.influence[area] and S.influence[area][key]
    if not r then return 0 end
    local hours = (os.time() - r.at) / 3600
    return r.v * (1 - C.Territories.Influence.DecayPerHour) ^ hours
end

local function addInfluence(area, key, units)
    S.influence[area] = S.influence[area] or {}
    local v = infNow(area, key) + units * C.Territories.Influence.PerUnit
    S.influence[area][key] = { v = v, at = os.time() }
    MySQL.update('INSERT INTO veyl_prod_influence (area, owner, value, updated_at) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE value = VALUES(value), updated_at = VALUES(updated_at)',
        { area, key, v, os.time() })
end

--- Who controls a territory: the owner key with the most influence, once it is at least MinToControl.
function S.controller(area)
    local best, bestV = nil, 0
    for key in pairs(S.influence[area] or {}) do
        local v = infNow(area, key)
        if v > bestV then best, bestV = key, v end
    end
    if best and bestV >= C.Territories.Influence.MinToControl then return best, bestV end
    return nil, 0
end

local function ownerName(key)
    if not key then return nil end
    if key:sub(1, 1) == 'c' then local c = Prod.Crews.crews[tonumber(key:sub(2))] return c and c.name or 'A crew' end
    return Prod.Props.nameOf(key:sub(2))
end

function S.load()
    S.influence = {}
    for _, r in ipairs(MySQL.query.await('SELECT area, owner, value, updated_at FROM veyl_prod_influence') or {}) do
        S.influence[r.area] = S.influence[r.area] or {}
        S.influence[r.area][r.owner] = { v = r.value, at = r.updated_at }
    end
end

---------------------------------------------------------------------------
-- Prices
---------------------------------------------------------------------------

--- Everything that scales a street price for this player in this zone (not the item's quality).
local function factor(cid, item, zone, regular)
    local f = cfg().PriceMultiplier * Prod.Market.mult(item) * (zone.price or 1.0) * Prod.Crews.sellBonus(cid)
    if not zone.wild then
        local ctrl = S.controller(zone.id)
        if ctrl and ctrl == ownerKey(cid) then f = f * (1 + C.Territories.Influence.ControlBonus) end
    end
    if regular then f = f * (1 + math.min(C.Regulars.MaxPriceBonus, regular.loyalty * C.Regulars.PriceBonusPerLoyalty)) end
    return f
end

local blocked
local function isBlocked(model)
    if not blocked then
        blocked = {}
        for _, name in ipairs(cfg().BlockedModels) do blocked[joaat(name)] = true end
    end
    return blocked[model] == true
end

--- The ped entity for a network id, if it is a real, living, non-player ped close enough to the player. Returns entity, coords, netId or nil, reason.
local function pedFor(src, netId)
    netId = Prod.Sec.int(netId, 2147483647)
    if not netId then return nil, 'bad' end
    local ok, ent = pcall(NetworkGetEntityFromNetworkId, netId)
    if not ok or not ent or ent == 0 or not DoesEntityExist(ent) then return nil, 'gone' end
    local okT, etype = pcall(GetEntityType, ent)
    if not okT or etype ~= 1 then return nil, 'bad' end
    local okP, isPlayer = pcall(IsPedAPlayer, ent)
    if okP and isPlayer then return nil, 'player' end
    local okM, model = pcall(GetEntityModel, ent)
    if okM and model and isBlocked(model) then return nil, 'blocked' end
    local okH, hp = pcall(GetEntityHealth, ent)
    if okH and hp and hp <= 0 then return nil, 'dead' end
    local pc, ec = Veyl.GetPlayerCoords(src), GetEntityCoords(ent)
    if not pc or not ec or ProdUtil.distance(pc, ec) > cfg().Distance + 2.0 then return nil, 'far' end
    return ent, ec, netId
end

--- Everything of theirs that can be sold on the street, with a quote at the quality they hold.
local function holdings(src, cid, zone, regular)
    local prices = Prod.Shop.prices()
    local out = {}
    for _, item in ipairs(cfg().Items) do
        local base = prices[item]
        if base then
            local count, best = 0, 0
            for _, st in ipairs(Prod.Inv.stacks(src, item)) do
                count = count + st.count
                local q = st.metadata and st.metadata.quality
                local mult = q and ProdUtil.tier(q).mult or 1.0
                if mult > best then best = mult end
            end
            if count > 0 then out[#out + 1] = { item = item, label = ProdItemLabels[item] or item, count = count, price = math.floor(base * best * factor(cid, item, zone, regular)) } end
        end
    end
    return out
end

---------------------------------------------------------------------------
-- Regulars
---------------------------------------------------------------------------

local function regularsOf(cid) return MySQL.query.await('SELECT * FROM veyl_prod_regulars WHERE citizenid = ? ORDER BY id', { cid }) or {} end

local function maybeNewRegular(cid, zone)
    local R = C.Regulars
    if not R.Enabled or math.random() >= R.ChanceOnSale then return nil end
    if #regularsOf(cid) >= R.Max then return nil end
    local area = not zone.wild and zone.id or areas()[math.random(#areas())].id
    local name = R.Names[math.random(#R.Names)]
    local model = R.Models[math.random(#R.Models)]
    local id = MySQL.insert.await('INSERT INTO veyl_prod_regulars (citizenid, name, model, territory, loyalty, sales, created_at) VALUES (?, ?, ?, ?, ?, 1, ?)', { cid, name, model, area, R.LoyaltyPerSale, os.time() })
    return id and name or nil
end

local function areaById(id) for _, a in ipairs(areas()) do if a.id == id then return a end end end

function S.regularsView(cid)
    local R = C.Regulars
    local out = {}
    for _, r in ipairs(regularsOf(cid)) do
        local a = areaById(r.territory)
        out[#out + 1] = { id = r.id, name = r.name, territory = a and a.label or r.territory, loyalty = r.loyalty, sales = r.sales,
            bonus = math.floor(math.min(R.MaxPriceBonus, r.loyalty * R.PriceBonusPerLoyalty) * 100 + 0.5), wait = Prod.Sec.cooldownLeft(cid, 'regular:' .. r.id) }
    end
    return out
end

--- Call a regular: the server picks a meeting spot in their territory and opens a meeting for a while.
function S.regularCall(src, cid, id)
    if not C.Regulars.Enabled then return Veyl.Err('UNAVAILABLE', 'Not available') end
    id = Prod.Sec.int(id, 2147483647)
    local r = id and MySQL.single.await('SELECT * FROM veyl_prod_regulars WHERE id = ? AND citizenid = ?', { id, cid })
    if not r then return Veyl.Err('INVALID_INPUT', 'You do not know them') end
    if S.meets[cid] and os.time() - S.meets[cid].at < C.Regulars.MeetSeconds then return Veyl.Err('INVALID_STATE', 'You already have a meeting set up') end
    if not Prod.Sec.try(cid, 'regular:' .. r.id, C.Regulars.CallCooldown) then return Veyl.Err('COOLDOWN', ('They are busy. Try again in %d min'):format(math.ceil(Prod.Sec.cooldownLeft(cid, 'regular:' .. r.id) / 60))) end
    local a = areaById(r.territory) or areas()[1]
    local p = a.meets[math.random(#a.meets)]
    S.meets[cid] = { regular = r.id, point = p, at = os.time(), token = Veyl.NewId(), used = false }
    return Veyl.Ok({ token = S.meets[cid].token, x = p.x, y = p.y, z = p.z, name = r.name, model = r.model, seconds = C.Regulars.MeetSeconds, radius = C.Regulars.MeetRadius },
        ('%s will meet you in %s'):format(r.name, a.label))
end

--- You are at the meeting: the regular buys a lot and pays better.
function S.regularOffer(src, cid, token)
    local m = S.meets[cid]
    if not m or m.used or type(token) ~= 'string' or m.token ~= token then return Veyl.Err('INVALID_STATE', 'There is no meeting') end
    if os.time() - m.at > C.Regulars.MeetSeconds then S.meets[cid] = nil return Veyl.Err('INVALID_STATE', 'They did not wait for you') end
    if not Prod.Sec.near(src, m.point, C.Regulars.MeetRadius + 4.0) then return Veyl.Err('TOO_FAR', 'Get to the meeting spot') end
    local r = MySQL.single.await('SELECT * FROM veyl_prod_regulars WHERE id = ? AND citizenid = ?', { m.regular, cid })
    if not r then return Veyl.Err('INVALID_STATE', 'There is no meeting') end
    local zone = S.zoneAt(m.point)
    local mine = holdings(src, cid, zone, r)
    if #mine == 0 then return Veyl.Err('NO_ITEM', ('%s wants product, and you have none'):format(r.name)) end
    local q = C.Regulars.Quantity
    m.used = true
    local token2 = Veyl.NewId()
    S.sessions[src] = { token = token2, cid = cid, left = math.random(q[1], q[2]), at = os.time(), items = mine, regular = r, zone = zone, coords = m.point }
    return Veyl.Ok({ token = token2, maxQty = S.sessions[src].left, seconds = cfg().OfferSeconds, items = mine, regular = r.name })
end

---------------------------------------------------------------------------
-- Offers and sales to ambient peds
---------------------------------------------------------------------------

function S.offer(src, cid, netId)
    if not cfg().Enabled then return Veyl.Err('INVALID_STATE', 'Not available') end
    local ent, ec, id = pedFor(src, netId)
    if not ent then
        if ec == 'bad' then Prod.Sec.invalid(src, cid, 'street_bad_ped', { net = netId }) end
        if ec == 'blocked' or ec == 'player' then return Veyl.Err('NOT_INTERESTED', 'They would never') end
        return Veyl.Err('TOO_FAR', 'Get closer to them')
    end
    if GetVehiclePedIsIn(GetPlayerPed(src), false) ~= 0 then return Veyl.Err('INVALID_STATE', 'Get out of the vehicle') end
    local now = os.time()
    if (S.peds[id] or 0) > now then return Veyl.Err('NOT_INTERESTED', 'They have already heard your pitch') end
    local h = S.hourly[cid]
    if not h or now - h.since > 3600 then h = { n = 0, since = now } S.hourly[cid] = h end
    if h.n >= cfg().MaxOffersPerHour then return Veyl.Err('RATE_LIMITED', 'Word is getting around. Lay low for a while.') end
    local pos = Veyl.GetPlayerCoords(src)
    local zone = S.zoneAt(pos)
    local mine = holdings(src, cid, zone, nil)
    if #mine == 0 then return Veyl.Err('NO_ITEM', 'You have nothing to sell on the street') end
    if not Prod.Sec.try(cid, 'street_offer', cfg().PlayerCooldown) then return Veyl.Err('RATE_LIMITED', 'Slow down') end
    -- The ped is used up now, whatever the answer, and the answer is rolled once.
    S.peds[id] = now + cfg().PedCooldown
    h.n = h.n + 1
    local heat = heatNow(zone.id)
    local H = C.Territories.Heat
    local chance = math.max(0.05, math.min(1.0, cfg().AcceptChance * (zone.accept or 1.0) * (1 - heat * H.AcceptPenalty)))
    if math.random() >= chance then
        Prod.Police.maybeAlert(cid, cfg().PoliceAlert, pos, 1 + heat * H.AlertBonus)
        local m = cfg().RefuseMessages
        return Veyl.Err('NOT_INTERESTED', m[math.random(#m)])
    end
    local q = cfg().Quantity
    local token = Veyl.NewId()
    S.sessions[src] = { token = token, cid = cid, ped = id, left = math.random(q[1], q[2]), at = now, items = mine, zone = zone }
    return Veyl.Ok({ token = token, maxQty = S.sessions[src].left, seconds = cfg().OfferSeconds, items = mine, area = zone.label, heat = math.floor(heat) })
end

function S.sell(src, cid, token, item, count)
    local s = S.sessions[src]
    if not s or type(token) ~= 'string' or s.token ~= token or s.cid ~= cid then Prod.Sec.invalid(src, cid, 'street_bad_token') return Veyl.Err('INVALID_STATE', 'That offer is over') end
    if os.time() - s.at > cfg().OfferSeconds then S.sessions[src] = nil return Veyl.Err('INVALID_STATE', 'They lost interest') end
    count = Prod.Sec.int(count, 1000)
    local entry
    for _, e in ipairs(s.items) do if e.item == item then entry = e break end end
    if not entry or not count or count < 1 then Prod.Sec.invalid(src, cid, 'street_bad_item', { item = item }) return Veyl.Err('INVALID_INPUT', 'Bad request') end
    if s.ped then
        local ent = pedFor(src, s.ped)
        if not ent then S.sessions[src] = nil return Veyl.Err('TOO_FAR', 'They walked off') end
    elseif not Prod.Sec.near(src, s.coords, C.Regulars.MeetRadius + 4.0) then
        S.sessions[src] = nil
        return Veyl.Err('TOO_FAR', 'Stay at the meeting spot')
    end
    count = math.min(count, s.left)
    local base = Prod.Shop.prices()[item]
    if not base then return Veyl.Err('INVALID_INPUT', 'Bad request') end
    -- Claim the units first (the session is the lock), then take items and pay. A failed take gives the units back to the session.
    s.left = s.left - count
    local mult = factor(cid, item, s.zone, s.regular)
    local remaining, total, sold = count, 0, 0
    local tag = ('prodstreet:%s:%s'):format(cid, Veyl.NewId())
    for _, st in ipairs(Prod.Inv.stacks(src, item)) do
        if remaining <= 0 then break end
        local n = math.min(remaining, st.count)
        local meta = next(st.metadata) and st.metadata or nil
        local q = st.metadata and st.metadata.quality
        local qm = q and ProdUtil.tier(q).mult or 1.0
        local r = Prod.Inv.take(cid, item, n, meta, ('%s:%d'):format(tag, sold + 1))
        if r and r.ok then
            total = total + math.floor(base * qm * mult * n)
            remaining = remaining - n
            sold = sold + 1
        end
    end
    local units = count - remaining
    s.left = s.left + remaining
    if units <= 0 then return Veyl.Err('NO_ITEM', ('You have no %s to sell'):format(ProdItemLabels[item] or item)) end
    Prod.Inv.credit(cid, total, ('Street sale: %s'):format(item), tag)
    Prod.Market.record(item, units)
    local left = s.left
    local zone, regular, coords = s.zone, s.regular, s.coords or GetEntityCoords(GetPlayerPed(src))
    if left <= 0 then S.sessions[src] = nil end
    local heat = heatNow(zone.id)
    local alertMult = 1 + heat * C.Territories.Heat.AlertBonus
    addHeat(zone.id)
    local newRegular
    if not zone.wild then addInfluence(zone.id, ownerKey(cid), units) end
    if regular then
        MySQL.update('UPDATE veyl_prod_regulars SET loyalty = loyalty + ?, sales = sales + ? WHERE id = ?', { C.Regulars.LoyaltyPerSale, units, regular.id })
    else
        newRegular = maybeNewRegular(cid, zone)
    end
    -- XP, stats, the log and the police roll happen after the answer has gone back.
    CreateThread(function()
        Prod.Prog.award(cid, ProdItemBranch(item), 'sell')
        Prod.Prog.stat(cid, 'street_sales')
        Prod.Prog.stat(cid, 'money_earned', total)
        Prod.Log.event('sale', cid, ('street (%s): %dx %s for $%d'):format(zone.label, units, item, total))
        Prod.Police.maybeAlert(cid, cfg().PoliceAlert, coords, alertMult)
    end)
    local msg = ('Sold %d for $%d'):format(units, total)
    if newRegular then msg = msg .. ('. %s wants to deal with you again.'):format(newRegular) end
    return Veyl.Ok({ total = total, sold = units, left = left, regular = newRegular }, msg)
end

---------------------------------------------------------------------------
-- What the tablet shows
---------------------------------------------------------------------------

function S.view(cid)
    local prices = Prod.Shop.prices()
    local market = {}
    for item, base in pairs(prices) do
        local info = Prod.Market.info(item)
        market[#market + 1] = { item = item, label = ProdItemLabels[item] or item, base = base, price = math.floor(base * Prod.Market.mult(item)), mult = info.mult, trend = info.trend, street = cfg().Items_[item] == true }
    end
    table.sort(market, function(a, b) return a.base > b.base end)
    local mine = ownerKey(cid)
    local terr = {}
    for _, a in ipairs(areas()) do
        local ctrl, v = S.controller(a.id)
        terr[#terr + 1] = { id = a.id, label = a.label, x = a.center.x, y = a.center.y, price = a.price, accept = a.accept, heat = math.floor(heatNow(a.id)),
            controller = ctrl and (ctrl == mine and 'You' or ownerName(ctrl)) or nil, controlled = ctrl == mine, influence = math.floor(infNow(a.id, mine)),
            bonus = math.floor(C.Territories.Influence.ControlBonus * 100 + 0.5) }
    end
    return { market = market, territories = terr, regulars = S.regularsView(cid), meet = S.meets[cid] and os.time() - S.meets[cid].at < C.Regulars.MeetSeconds and { x = S.meets[cid].point.x, y = S.meets[cid].point.y } or nil }
end

-- A set of the street items for quick lookup.
cfg().Items_ = {}
for _, i in ipairs(cfg().Items) do cfg().Items_[i] = true end

AddEventHandler('playerDropped', function() S.sessions[source] = nil end)

-- Expired ped cooldowns, hourly counters, cold heat and old meetings are dropped now and then.
CreateThread(function()
    while true do
        Wait(300000)
        local now = os.time()
        for k, v in pairs(S.peds) do if v < now then S.peds[k] = nil end end
        for k, v in pairs(S.hourly) do if now - v.since > 3600 then S.hourly[k] = nil end end
        for k in pairs(S.heat) do if heatNow(k) <= 0 then S.heat[k] = nil end end
        for k, m in pairs(S.meets) do if now - m.at > C.Regulars.MeetSeconds then S.meets[k] = nil end end
    end
end)
