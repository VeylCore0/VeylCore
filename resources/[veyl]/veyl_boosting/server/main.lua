-- veyl_boosting server entry: start-up, the tablet's state, the callbacks the page and client may call, admin commands.
-- Callbacks only ever ask; the engine in contracts.lua decides.

Boost = Boost or {}
local C = BoostingConfig
local Contracts = Boost.Contracts
local Prog, Heat, Crew, Sec = Boost.Prog, Boost.Heat, Boost.Crew, Boost.Sec

Boost.ready = false

Veyl.Startup({ 'veyl_core', 'veyl_vehicles', 'veyl_inventory' }, function()
    local ok = Boost.DB.Migrate()
    if ok == false then return false end
    Contracts.reconcile()
    Boost.ready = true
    return true
end)

CreateThread(function()
    while true do
        Wait(C.Cleanup.TickMs)
        if Boost.ready then
            local ok, err = pcall(Contracts.tick)
            if not ok then print(('^1[veyl_boosting] supervisor error: %s^7'):format(tostring(err))) end
        end
    end
end)

---------------------------------------------------------------------------
-- What the tablet shows
---------------------------------------------------------------------------
local function catalogue(rep)
    local list = {}
    for _, v in ipairs(C.Vehicles) do
        list[#list + 1] = { model = v.model, label = v.label, tier = v.tier, difficulty = v.difficulty, baseReward = v.baseReward, minRep = v.minRep,
            unlocked = rep >= v.minRep, solo = v.solo, group = v.group }
    end
    return list
end

local function ranks(rep)
    local idx = BoostingUtil.rankFor(rep)
    local out = {}
    for i, r in ipairs(C.Ranks) do out[i] = { id = r.id, label = r.label, rep = r.rep, perk = C.RankPerks[r.id], current = i == idx, reached = i <= idx } end
    return out
end

local function tabletState(src, cid)
    local p = Prog.get(cid)
    local idx, rank, nextRank, progress = BoostingUtil.rankFor(p.rep)
    local heat = Heat.value(cid)
    local lvl = BoostingUtil.heatLevel(heat)
    local offers, offersAt = Contracts.offersFor(cid, false)
    local total = p.completed + p.failed
    return {
        player = { name = Crew.nameOf(src), rank = rank.label, rankIndex = idx, rep = p.rep, nextRank = nextRank and nextRank.label, nextRep = nextRank and nextRank.rep, rankFloor = rank.rep, progress = progress },
        heat = { value = math.floor(heat), max = C.Heat.Max, level = lvl.id, label = lvl.label, color = lvl.color, rewardMult = lvl.rewardMult,
            levels = C.Heat.Levels, decay = C.Heat.DecayPerMinute, police = Boost.Dispatch.available() },
        active = Contracts.view(Contracts.byCid[cid], cid),
        offers = offers, offersAt = offersAt, offersTTL = C.Offers.TTLMinutes * 60,
        catalogue = catalogue(p.rep), ranks = ranks(p.rep), tiers = C.Tiers,
        stats = { completed = p.completed, failed = p.failed, rate = total > 0 and p.completed / total or 0, earnings = p.earnings, best = p.best, rep = p.rep },
        challenges = Prog.challenges(cid), recent = Prog.recent(cid, 6),
        crew = Crew.view(cid), invite = Crew.pending(cid),
        event = Contracts.event, ui = C.UI, crewMax = C.Crews.MaxSize, serverTime = os.time(),
        dropRadius = C.Delivery.Radius, blips = C.Blips,
    }
end

local function hasTablet(src) return (exports.veyl_inventory:GetItemCount(src, C.Tablet.Item) or 0) > 0 end

---------------------------------------------------------------------------
-- Callbacks (the whitelist on the client is the second gate; every one is validated here)
---------------------------------------------------------------------------
local function register(name, fn, cooldown)
    Veyl.RegisterCallback(name, function(src, cid, ...)
        if not Boost.ready then return Veyl.Err('NOT_READY', 'Boosting is starting up') end
        -- Everything the tablet does needs the tablet item (only buying one does not).
        if name ~= 'buyTablet' and not hasTablet(src) then return Veyl.Err('NO_ITEM', 'You need a boosting tablet') end
        return fn(src, cid, ...)
    end, { cooldown = cooldown or 400 })
end

register('state', function(src, cid) return Veyl.Ok(tabletState(src, cid)) end, 300)

--- The underground contact sells the tablet: near the contact, one per person, one debit and one grant (the grant is undone with a refund if it fails).
register('buyTablet', function(src, cid)
    local pc = Veyl.GetPlayerCoords(src)
    local near = false
    for _, c in ipairs(C.Contacts) do
        if pc and #(pc - vector3(c.coords.x, c.coords.y, c.coords.z)) <= (c.radius or 2.2) + 3.0 then near = true break end
    end
    if not near then return Veyl.Err('TOO_FAR', 'Go to the contact') end
    if hasTablet(src) then return Veyl.Err('INVALID_STATE', 'You already have a tablet') end
    local tag = ('boosttablet:%s:%s'):format(cid, Veyl.NewId())
    local can = Veyl.Await('veyl_inventory', 'CanCarry', 10000, cid, C.Tablet.Item, 1, nil)
    if not (can and can.ok) then return Veyl.Err('INVENTORY_FULL', 'You cannot carry it') end
    local pay = Veyl.Await('veyl_core', 'DebitOnce', 15000, cid, 'cash', C.Tablet.Price, 'Boosting tablet', tag)
    if not (pay and pay.ok) then return Veyl.Err(pay and pay.code or 'INSUFFICIENT_FUNDS', ('It costs $%d in cash'):format(C.Tablet.Price)) end
    local give = Veyl.Await('veyl_inventory', 'GiveItem', 15000, cid, C.Tablet.Item, 1, nil, tag)
    if not (give and give.ok) then
        Veyl.Await('veyl_core', 'CreditOnce', 15000, cid, 'cash', C.Tablet.Price, 'Boosting tablet refund', tag .. ':refund')
        return Veyl.Err('FAILED', 'Could not hand it over. You were refunded.')
    end
    return Veyl.Ok(nil, 'Here. Do not lose it.')
end, 1500)

register('sync', function(src, cid)
    Contracts.onBack(cid, src)
    return Veyl.Ok(Contracts.view(Contracts.byCid[cid], cid))
end, 1000)

register('refreshOffers', function(src, cid)
    local _, at = Contracts.offersFor(cid, true)
    return Veyl.Ok(tabletState(src, cid), os.time() - at < 2 and 'Contracts refreshed' or 'Please wait before refreshing again')
end, 1500)

register('accept', function(src, cid, offerId)
    offerId = Sec.str(offerId, 64)
    if not offerId then Sec.invalid(src, cid, 'accept_bad_id') return Veyl.Err('INVALID_INPUT', 'Bad request') end
    return Contracts.accept(src, cid, offerId)
end, 1200)

register('startContract', function(src, cid) return Contracts.start(src, cid) end, 1500)
register('cancelContract', function(src, cid) return Contracts.cancel(src, cid) end, 1500)
register('deliver', function(src, cid) return Contracts.deliver(src, cid) end, 1200)

register('accessBegin', function(src, cid, netId)
    netId = Sec.int(netId, 65535)
    if not netId then Sec.invalid(src, cid, 'access_bad_netid') return Veyl.Err('INVALID_INPUT', 'Bad request') end
    return Contracts.accessBegin(src, cid, netId)
end, 800)

register('accessSubmit', function(src, cid, token, answer)
    token = Sec.str(token, 64)
    if not token or type(answer) ~= 'table' or #answer > 16 then Sec.invalid(src, cid, 'access_bad_submit') return Veyl.Err('INVALID_INPUT', 'Bad request') end
    return Contracts.accessSubmit(src, cid, token, answer)
end, 120)

register('accessAbort', function(src, cid) Contracts.accessAbort(cid) return Veyl.Ok() end, 300)

register('trackerStart', function(src, cid, netId)
    netId = Sec.int(netId, 65535)
    if not netId then Sec.invalid(src, cid, 'tracker_bad_netid') return Veyl.Err('INVALID_INPUT', 'Bad request') end
    return Contracts.trackerStart(src, cid, netId)
end, 1000)

register('trackerFinish', function(src, cid, token)
    token = Sec.str(token, 64)
    if not token then return Veyl.Err('INVALID_INPUT', 'Bad request') end
    return Contracts.trackerFinish(src, cid, token)
end, 500)

register('crewNearby', function(src, cid) return Veyl.Ok(Crew.nearby(src, cid)) end, 800)
register('crewInvite', function(src, cid, target)
    target = Sec.int(target, 65535)
    if not target then return Veyl.Err('INVALID_INPUT', 'Bad request') end
    return Crew.invite(src, cid, target)
end, 1000)
register('crewAnswer', function(src, cid, accept) return Crew.answer(src, cid, accept == true) end, 500)
register('crewLeave', function(src, cid) return Crew.leave(src, cid) end, 800)
register('crewKick', function(src, cid, target)
    target = Sec.str(target, 16)
    if not target then return Veyl.Err('INVALID_INPUT', 'Bad request') end
    return Crew.kick(src, cid, target)
end, 800)
register('crewLead', function(src, cid, target)
    target = Sec.str(target, 16)
    if not target then return Veyl.Err('INVALID_INPUT', 'Bad request') end
    return Crew.lead(src, cid, target)
end, 800)

---------------------------------------------------------------------------
-- Players, items, resource lifecycle
---------------------------------------------------------------------------
AddEventHandler('playerDropped', function()
    local cid = Veyl.GetCitizenId(source)
    if not cid then return end
    Contracts.onDrop(cid)
    Prog.forget(cid)
end)

CreateThread(function()
    while GetResourceState('veyl_inventory') ~= 'started' do Wait(1000) end
    Wait(1000)
    exports.veyl_inventory:RegisterUseHandler('boosting_tablet', function(ctx) TriggerClientEvent('veyl_boosting:open', ctx.source) end)
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then Contracts.shutdown() end
end)

---------------------------------------------------------------------------
-- Admin: /boostadmin <event on|off | rep <id> <n> | heat <id> <n> | cancel <id> | status>
---------------------------------------------------------------------------
RegisterCommand('boostadmin', function(src, args)
    if src ~= 0 and not Veyl.HasPermission(src, C.Admin.Permission) then return end
    local function say(text) if src == 0 then print('[veyl_boosting] ' .. text) else Veyl.Notify(src, text, 'info') end end
    local sub = args[1]
    if sub == 'event' then
        Contracts.event = args[2] == 'on'
        say(('Event contracts are now %s'):format(Contracts.event and 'ON' or 'OFF'))
        Boost.Log.audit('system', 'admin_event', { on = Contracts.event, by = src })
    elseif sub == 'rep' or sub == 'heat' or sub == 'cancel' then
        local target = tonumber(args[2])
        local cid = target and Veyl.GetCitizenId(target)
        if not cid then return say('Usage: boostadmin ' .. sub .. ' <server id>' .. (sub ~= 'cancel' and ' <amount>' or '')) end
        local n = tonumber(args[3]) or 0
        if sub == 'rep' then say(('Reputation is now %d'):format(Prog.addRep(cid, n, 'admin')))
        elseif sub == 'heat' then Heat.add(cid, n, 'admin') say(('Heat is now %d'):format(math.floor(Heat.value(cid))))
        else
            local c = Contracts.byCid[cid]
            if not c then return say('No contract') end
            Contracts.finish(c, 'cancelled', 'admin')
            say('Contract cancelled')
        end
        Boost.Log.audit(cid, 'admin_' .. sub, { amount = n, by = src })
    else
        local live = 0
        for _ in pairs(Contracts.byId) do live = live + 1 end
        say(('Live contracts: %d | event: %s | dispatch adapter: %s | police on duty: %d'):format(live, Contracts.event and 'on' or 'off', Boost.Dispatch.available() and 'on' or 'off', Boost.Dispatch.policeOnline()))
    end
end, false)
