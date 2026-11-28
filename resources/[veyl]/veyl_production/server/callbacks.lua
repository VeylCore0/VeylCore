-- Everything the page and the client may ask the server. Each callback validates its arguments and hands off to the engine that owns the
-- rule; none of them decide an outcome on their own. Veyl.RegisterCallback adds a per-player cooldown and one-at-a-time protection.

Prod = Prod or {}
local C = ProductionConfig
local Sec = Prod.Sec
Prod.ready = false

local function register(name, fn, cooldown)
    Veyl.RegisterCallback(name, function(src, cid, ...)
        if not Prod.ready then return Veyl.Err('NOT_READY', 'Production is starting up') end
        return fn(src, cid, ...)
    end, { cooldown = cooldown or 300 })
end

local function nearby(src, range)
    local mine = Veyl.GetPlayerCoords(src)
    local out = {}
    if not mine then return out end
    for _, s in ipairs(GetPlayers()) do
        local t = tonumber(s)
        local tcid = t ~= src and Veyl.GetCitizenId(t)
        local pc = tcid and Veyl.GetPlayerCoords(t)
        if tcid and pc and ProdUtil.distance(mine, pc) <= range then out[#out + 1] = { id = t, name = Prod.Props.nameOf(tcid) } end
    end
    return out
end

local function varieties(cid)
    local out = {}
    for _, key in ipairs(ProdUtil.varieties()) do
        local v = ProdUtil.variety(key)
        if C.Branches[v.branch] and C.Branches[v.branch].enabled then
            out[#out + 1] = { key = key, label = v.label, branch = v.branch, rarity = v.rarity, level = v.level, locked = Prod.Prog.level(cid, v.branch) < v.level, growMinutes = v.growMinutes, yield = v.yield, seed = v.seed }
        end
    end
    table.sort(out, function(a, b) return a.branch < b.branch or (a.branch == b.branch and a.level < b.level) end)
    return out
end

local function shopList()
    local out = {}
    for id, d in pairs(Prod.Shop.defs) do out[#out + 1] = { id = id, label = d.label, branch = d.branch, x = d.ped.coords.x, y = d.ped.coords.y } end
    table.sort(out, function(a, b) return a.id < b.id end)
    return out
end

--- Everything the tablet shows, in one answer.
local function tabletState(src, cid)
    return {
        player = { name = Prod.Props.nameOf(cid) },
        progress = Prod.Prog.view(cid),
        plants = Prod.Plants.mine(cid), varieties = varieties(cid),
        workstations = Prod.Ws.mine(cid),
        properties = Prod.Props.catalogue(cid, src),
        gathering = Prod.Gather.view(cid), supplier = Prod.Supplier.view(cid), shops = shopList(),
        exposure = math.floor(Prod.Hazard.exposure[src] or 0),
        recent = Prod.Log.recent(cid, 8),
        police = { enabled = Prod.Police.enabled(), dispatch = Prod.Police.dispatchAvailable(), isPolice = Prod.Police.isPolice(src) },
        branches = C.Branches, ui = C.UI, tiers = C.Quality.Tiers, levelNames = C.LevelNames, itemLabels = ProdItemLabels,
        serverTime = os.time(),
    }
end

register('state', function(src, cid) return Veyl.Ok(tabletState(src, cid)) end, 300)

-- Shop
register('shopView', function(src, cid, id)
    local d = Sec.str(id, 32, '^[%w_]+$') and Prod.Shop.def(id)
    if not d then return Veyl.Err('INVALID_INPUT', 'Unknown shop') end
    if not Sec.near(src, d.ped.coords, C.Distance.Shop) then return Veyl.Err('TOO_FAR', 'Go to the shop') end
    return Veyl.Ok(Prod.Shop.view(cid, id))
end)
register('shopBuy', function(src, cid, shop, item, qty) return Prod.Shop.buy(src, cid, shop, item, qty) end, 400)
register('shopSell', function(src, cid, item, qty) return Prod.Shop.sell(src, cid, item, qty) end, 400)
register('buyerView', function(src, cid)
    if not Sec.near(src, C.Buyer.Ped.coords, C.Distance.Shop) then return Veyl.Err('TOO_FAR', 'Go to the buyer') end
    return Veyl.Ok(Prod.Shop.view(cid))
end)

-- Gathering
register('gatherStart', function(src, cid, id, index) return Prod.Gather.start(src, cid, id, index) end, 800)
register('gatherFinish', function(src, cid, token)
    token = Sec.str(token, 64)
    if not token then return Veyl.Err('INVALID_INPUT', 'Bad request') end
    return Prod.Gather.finish(src, cid, token)
end, 500)

-- Plants
register('plantsList', function(src, cid) return Veyl.Ok(Prod.Plants.list(cid)) end, 1500)
register('plantInspect', function(src, cid, id) return Prod.Plants.inspect(src, cid, id) end, 400)
register('plantPlace', function(src, cid, d) if type(d) ~= 'table' then return Veyl.Err('INVALID_INPUT', 'Bad request') end return Prod.Plants.place(src, cid, d) end, 800)
register('plantCare', function(src, cid, id, kind) return Prod.Plants.care(src, cid, id, kind) end, 600)
register('plantHarvest', function(src, cid, id) return Prod.Plants.harvest(src, cid, id) end, 800)
register('plantRemove', function(src, cid, id) return Prod.Plants.remove(src, cid, id) end, 800)

-- Workstations
register('wsList', function(src, cid) return Veyl.Ok(Prod.Ws.list(cid)) end, 1500)
register('wsOpen', function(src, cid, id) return Prod.Ws.open(src, cid, id) end, 300)
register('wsPlace', function(src, cid, d) if type(d) ~= 'table' then return Veyl.Err('INVALID_INPUT', 'Bad request') end return Prod.Ws.place(src, cid, d) end, 800)
register('wsPack', function(src, cid, id) return Prod.Ws.packup(src, cid, id) end, 800)
register('wsChallenge', function(src, cid, id, recipe) return Prod.Ws.challenge(src, cid, id, recipe) end, 600)
register('wsStart', function(src, cid, id, recipe, token, score) return Prod.Ws.start(src, cid, id, recipe, token, score) end, 600)
register('wsClaim', function(src, cid, id) return Prod.Ws.claim(src, cid, id) end, 600)
register('wsCancel', function(src, cid, id, batch) return Prod.Ws.cancel(src, cid, id, batch) end, 600)

-- Properties
register('propList', function(src, cid) return Veyl.Ok(Prod.Props.publicList()) end, 2000)
register('propBuy', function(src, cid, id) return Prod.Props.purchase(src, cid, Sec.str(id, 32, '^[%w_]+$')) end, 1200)
register('propSell', function(src, cid, id) return Prod.Props.sell(src, cid, Sec.str(id, 32, '^[%w_]+$')) end, 1200)
register('propTransfer', function(src, cid, id, target) return Prod.Props.transferOffer(src, cid, Sec.str(id, 32, '^[%w_]+$'), target) end, 1000)
register('propTransferAnswer', function(src, cid, accept) return Prod.Props.transferAnswer(src, cid, accept == true) end, 600)
register('propUpgrade', function(src, cid, id, key) return Prod.Props.upgrade(src, cid, Sec.str(id, 32, '^[%w_]+$'), Sec.str(key, 24, '^[%w_]+$')) end, 1000)
register('propLock', function(src, cid, id, locked) return Prod.Props.setLocked(src, cid, Sec.str(id, 32, '^[%w_]+$'), locked == true) end, 600)
register('propCode', function(src, cid, id, code) return Prod.Props.setCode(src, cid, Sec.str(id, 32, '^[%w_]+$'), type(code) == 'string' and code:sub(1, 16) or nil) end, 800)
register('propMemberAdd', function(src, cid, id, target, role) return Prod.Props.addMember(src, cid, Sec.str(id, 32, '^[%w_]+$'), target, role) end, 800)
register('propMemberRemove', function(src, cid, id, target) return Prod.Props.removeMember(src, cid, Sec.str(id, 32, '^[%w_]+$'), target) end, 800)
register('propEnter', function(src, cid, id, code) return Prod.Props.enter(src, cid, Sec.str(id, 32, '^[%w_]+$'), type(code) == 'string' and code:sub(1, 16) or nil) end, 800)
register('propExit', function(src, cid) return Prod.Props.exit(src, cid) end, 800)
register('propRecover', function(src, cid) return Prod.Props.recover(src) or Veyl.Ok(nil) end, 3000)
register('propStorage', function(src, cid, id) return Prod.Props.storage(src, cid, Sec.str(id, 32, '^[%w_]+$')) end, 500)
register('nearbyPlayers', function(src, cid) return Veyl.Ok(nearby(src, C.Distance.Property)) end, 800)

-- Police
register('raidStart', function(src, cid, id) return Prod.Props.raidStart(src, cid, Sec.str(id, 32, '^[%w_]+$')) end, 1000)
register('raidFinish', function(src, cid, token) return Prod.Props.raidFinish(src, cid, Sec.str(token, 64)) end, 600)
register('raidSeize', function(src, cid, id) return Prod.Props.raidSeize(src, cid, Sec.str(id, 32, '^[%w_]+$')) end, 1500)
register('propCatalogue', function(src, cid) return Veyl.Ok(Prod.Props.catalogue(cid, src)) end, 500)

-- Supplier runs
register('supplierView', function(src, cid) return Veyl.Ok(Prod.Supplier.view(cid)) end, 500)
register('runStart', function(src, cid, id) return Prod.Supplier.start(src, cid, id) end, 1000)
register('runPickup', function(src, cid) return Prod.Supplier.pickup(src, cid) end, 800)
register('runDeliver', function(src, cid) return Prod.Supplier.deliver(src, cid) end, 800)
register('runCancel', function(src, cid) return Prod.Supplier.cancel(src, cid) end, 800)
register('runCurrent', function(src, cid) return Veyl.Ok(Prod.Supplier.current(cid)) end, 1500)
