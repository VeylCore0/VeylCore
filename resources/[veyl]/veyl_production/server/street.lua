-- Selling to pedestrians. Two steps, both decided here: an offer (is this ped real, in range and willing, what could you sell) and a sale
-- (what they take and pay). The ped's answer is rolled at the offer and the ped is used up for everyone for a while, so walking away and
-- asking again, or asking many players' peds in a row, gains nothing. The client only names a ped and, later, an item and a count.

Prod = Prod or {}
Prod.Street = { sessions = {}, peds = {}, hourly = {} }
local S = Prod.Street
local C = ProductionConfig

local function cfg() return C.Street end

local blocked
local function isBlocked(model)
    if not blocked then
        blocked = {}
        for _, name in ipairs(cfg().BlockedModels) do blocked[joaat(name)] = true end
    end
    return blocked[model] == true
end

--- The ped entity for a network id, if it is a real, living, non-player ped close enough to the player. Returns entity, coords or nil, reason.
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
local function holdings(src)
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
            if count > 0 then out[#out + 1] = { item = item, label = ProdItemLabels[item] or item, count = count, price = math.floor(base * best * cfg().PriceMultiplier) } end
        end
    end
    return out
end

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
    local mine = holdings(src)
    if #mine == 0 then return Veyl.Err('NO_ITEM', 'You have nothing to sell on the street') end
    if not Prod.Sec.try(cid, 'street_offer', cfg().PlayerCooldown) then return Veyl.Err('RATE_LIMITED', 'Slow down') end
    -- The ped is used up now, whatever the answer, and the answer is rolled once.
    S.peds[id] = now + cfg().PedCooldown
    h.n = h.n + 1
    if math.random() >= cfg().AcceptChance then
        Prod.Police.maybeAlert(cid, cfg().PoliceAlert, GetEntityCoords(GetPlayerPed(src)))
        local m = cfg().RefuseMessages
        return Veyl.Err('NOT_INTERESTED', m[math.random(#m)])
    end
    local q = cfg().Quantity
    local token = Veyl.NewId()
    S.sessions[src] = { token = token, cid = cid, ped = id, left = math.random(q[1], q[2]), at = now, items = mine }
    return Veyl.Ok({ token = token, maxQty = S.sessions[src].left, seconds = cfg().OfferSeconds, items = mine })
end

function S.sell(src, cid, token, item, count)
    local s = S.sessions[src]
    if not s or type(token) ~= 'string' or s.token ~= token or s.cid ~= cid then Prod.Sec.invalid(src, cid, 'street_bad_token') return Veyl.Err('INVALID_STATE', 'That offer is over') end
    if os.time() - s.at > cfg().OfferSeconds then S.sessions[src] = nil return Veyl.Err('INVALID_STATE', 'They lost interest') end
    count = Prod.Sec.int(count, 1000)
    local entry
    for _, e in ipairs(s.items) do if e.item == item then entry = e break end end
    if not entry or not count or count < 1 then Prod.Sec.invalid(src, cid, 'street_bad_item', { item = item }) return Veyl.Err('INVALID_INPUT', 'Bad request') end
    local ent = pedFor(src, s.ped)
    if not ent then S.sessions[src] = nil return Veyl.Err('TOO_FAR', 'They walked off') end
    count = math.min(count, s.left)
    local base = Prod.Shop.prices()[item]
    if not base then return Veyl.Err('INVALID_INPUT', 'Bad request') end
    -- Claim the units first (the session is the lock), then take items and pay. A failed take gives the units back to the session.
    s.left = s.left - count
    local remaining, total, sold = count, 0, 0
    local tag = ('prodstreet:%s:%s'):format(cid, Veyl.NewId())
    for _, st in ipairs(Prod.Inv.stacks(src, item)) do
        if remaining <= 0 then break end
        local n = math.min(remaining, st.count)
        local meta = next(st.metadata) and st.metadata or nil
        local q = st.metadata and st.metadata.quality
        local mult = q and ProdUtil.tier(q).mult or 1.0
        local r = Prod.Inv.take(cid, item, n, meta, ('%s:%d'):format(tag, sold + 1))
        if r and r.ok then
            total = total + math.floor(base * mult * cfg().PriceMultiplier * n)
            remaining = remaining - n
            sold = sold + 1
        end
    end
    local units = count - remaining
    s.left = s.left + remaining
    if units <= 0 then return Veyl.Err('NO_ITEM', ('You have no %s to sell'):format(ProdItemLabels[item] or item)) end
    Prod.Inv.credit(cid, total, ('Street sale: %s'):format(item), tag)
    Prod.Prog.award(cid, ProdItemBranch(item), 'sell')
    Prod.Prog.stat(cid, 'street_sales')
    Prod.Prog.stat(cid, 'money_earned', total)
    Prod.Log.event('sale', cid, ('street: %dx %s for $%d'):format(units, item, total))
    Prod.Police.maybeAlert(cid, cfg().PoliceAlert, GetEntityCoords(GetPlayerPed(src)))
    local left = s.left
    if left <= 0 then S.sessions[src] = nil end
    return Veyl.Ok({ total = total, sold = units, left = left }, ('Sold %d for $%d'):format(units, total))
end

AddEventHandler('playerDropped', function() S.sessions[source] = nil end)

-- Expired ped cooldowns and hourly counters are dropped now and then.
CreateThread(function()
    while true do
        Wait(300000)
        local now = os.time()
        for k, v in pairs(S.peds) do if v < now then S.peds[k] = nil end end
        for k, v in pairs(S.hourly) do if now - v.since > 3600 then S.hourly[k] = nil end end
    end
end)
