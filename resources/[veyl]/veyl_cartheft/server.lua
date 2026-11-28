-- veyl_cartheft server. The client plays the minigames and moves the peds; the server decides what is allowed: who may try which car, how long
-- an attempt takes at least, whether it worked, who holds keys and what is in the trunk and glovebox. Nothing the client says is trusted
-- beyond "I finished" at the earliest time the attempt could honestly be done.

local C = CartheftConfig
local tokens = {}     -- [src] = { kind, netId, at, minMs, plate }
local keys = {}       -- [citizenid] = { [plate] = expires }
local last = {}       -- [citizenid .. ':' .. kind] = os.time()
local jacked = {}     -- [netId] = os.time(): a driver already being threatened
local alerted = {}    -- [citizenid] = os.time()
local rolled = {}     -- ['trunk:pABC123'] = true (this run); the database remembers across restarts

Veyl.Startup({ 'veyl_core', 'veyl_inventory' }, function()
    return Veyl.Migrate({
        { id = '001_loot', sql = {
            [[CREATE TABLE IF NOT EXISTS veyl_cartheft_loot (
                kind VARCHAR(16) NOT NULL, vkey VARCHAR(40) NOT NULL, rolled_at INT UNSIGNED NOT NULL,
                PRIMARY KEY (kind, vkey)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        } },
    })
end)

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function entityFromNet(netId)
    netId = tonumber(netId)
    if not netId or netId ~= math.floor(netId) or netId < 1 then return nil end
    local e = NetworkGetEntityFromNetworkId(netId)
    if not e or e == 0 or not DoesEntityExist(e) or GetEntityType(e) ~= 2 then return nil end
    return e, netId
end

local function plateOf(e) return (GetVehicleNumberPlateText(e) or ''):gsub('[^%w]', ''):upper() end

--- Cars VeylCore manages (owned, dealer, job, mission) are not ours to lock or steal.
local function managed(e)
    local ok, id = pcall(function() return exports.veyl_vehicles:GetVehicleIdFromEntity(e) end)
    return ok and id ~= nil
end

local function distance(src, e)
    local pc = Veyl.GetPlayerCoords(src)
    return pc and #(pc - GetEntityCoords(e)) or math.huge
end

local function cooling(cid, kind, seconds)
    local k = cid .. ':' .. kind
    if os.time() - (last[k] or 0) < seconds then return true end
    last[k] = os.time()
    return false
end

local function opId(cid) return ('cartheft:%s:%s'):format(cid, Veyl.NewId()) end

local function keyList(cid)
    local out, now, t = {}, os.time(), keys[cid]
    if not t then return out end
    for plate, exp in pairs(t) do
        if exp > now then out[#out + 1] = plate else t[plate] = nil end
    end
    return out
end

local function hasKey(cid, plate)
    local exp = keys[cid] and keys[cid][plate]
    return exp ~= nil and exp > os.time()
end

local function giveKey(src, cid, plate)
    keys[cid] = keys[cid] or {}
    keys[cid][plate] = os.time() + C.KeysMinutes * 60
    TriggerClientEvent('veyl_cartheft:keys', src, keyList(cid))
end

--- Police alert: chance, per-player cooldown, only when switched on.
local function alert(src, cid, coords, text, chance)
    local P = C.Police
    if not P.Enabled or not P.Dispatch.Enabled or GetResourceState(P.Dispatch.Resource) ~= 'started' then return end
    if math.random() >= chance then return end
    if os.time() - (alerted[cid] or 0) < P.PlayerCooldownSeconds then return end
    alerted[cid] = os.time()
    local d = P.Dispatch
    pcall(function()
        exports[d.Resource]:Alert({ services = P.Jobs, code = d.Code, title = d.Title, priority = d.Priority, coords = coords, message = text, blip = d.Blip })
    end)
end

local function attempt(src, cid, kind, netId, minMs, plate)
    tokens[src] = { kind = kind, netId = netId, at = GetGameTimer(), minMs = minMs, plate = plate, cid = cid, token = Veyl.NewId() }
    return tokens[src].token
end

--- The attempt this player started, if the token is right and enough time has passed. Always consumes it.
local function finish(src, cid, kind, token)
    local t = tokens[src]
    tokens[src] = nil
    if not t or t.kind ~= kind or t.cid ~= cid or type(token) ~= 'string' or t.token ~= token then
        Veyl.Audit(src, 'cartheft_bad_token', { kind = kind })
        return nil, Veyl.Err('INVALID_STATE', 'That attempt is over')
    end
    if GetGameTimer() - t.at < t.minMs then
        Veyl.Audit(src, 'cartheft_too_fast', { kind = kind })
        return nil, Veyl.Err('TOO_FAST', 'That was too quick')
    end
    return t
end

local function diff(name) return ({ easy = 3, medium = 4, hard = 5 })[name] or 4 end

---------------------------------------------------------------------------
-- Lockpicking a parked car
---------------------------------------------------------------------------
Veyl.RegisterCallback('lockpickStart', function(src, cid, netId)
    local L = C.Lockpick
    local e, id = entityFromNet(netId)
    if not e or managed(e) then return Veyl.Err('INVALID_STATE', 'You cannot do that to this one') end
    if distance(src, e) > L.Distance + 2.0 then return Veyl.Err('TOO_FAR', 'Get closer to the door') end
    if GetPedInVehicleSeat(e, -1) ~= 0 then return Veyl.Err('INVALID_STATE', 'Somebody is in it') end
    if (exports.veyl_inventory:GetItemCount(src, L.Item) or 0) < 1 then return Veyl.Err('NO_ITEM', 'You need a lockpick') end
    if cooling(cid, 'lockpick', L.CooldownSeconds) then return Veyl.Err('RATE_LIMITED', 'Slow down') end
    local plate = plateOf(e)
    if hasKey(cid, plate) then return Veyl.Err('INVALID_STATE', 'You already have the keys') end
    local rounds = diff(L.Difficulty)
    return Veyl.Ok({ token = attempt(src, cid, 'lockpick', id, rounds * L.MinMsPerRound, plate), difficulty = L.Difficulty })
end, { cooldown = 600 })

Veyl.RegisterCallback('lockpickFinish', function(src, cid, token, success)
    local L = C.Lockpick
    local t, err = finish(src, cid, 'lockpick', token)
    if not t then return err end
    local e = entityFromNet(t.netId)
    if not e or distance(src, e) > L.Distance + 4.0 then return Veyl.Err('TOO_FAR', 'You moved away') end
    local alarm = math.random() < L.AlarmChance
    alert(src, cid, GetEntityCoords(e), 'Someone is breaking into a car', success == true and C.Hotwire.AlertChance or C.Hotwire.AlertChance * 0.5)
    if success == true then
        return Veyl.Ok({ alarm = alarm }, 'The lock gives')
    end
    local broke = false
    if math.random() < L.BreakChanceOnFail then
        local r = Veyl.Await('veyl_inventory', 'TakeItem', 15000, cid, L.Item, 1, nil, opId(cid))
        broke = r and r.ok == true
    end
    return Veyl.Err('FAILED', broke and 'The lockpick snapped' or 'It would not give', { alarm = alarm, broke = broke })
end, { cooldown = 400 })

---------------------------------------------------------------------------
-- Hotwiring from the driver's seat
---------------------------------------------------------------------------
Veyl.RegisterCallback('hotwireStart', function(src, cid, netId)
    local H = C.Hotwire
    local e, id = entityFromNet(netId)
    if not e or managed(e) then return Veyl.Err('INVALID_STATE', 'You cannot do that to this one') end
    if GetPedInVehicleSeat(e, -1) ~= GetPlayerPed(src) then return Veyl.Err('INVALID_STATE', 'Sit in the driver\'s seat') end
    local plate = plateOf(e)
    if hasKey(cid, plate) then return Veyl.Err('INVALID_STATE', 'You already have the keys') end
    if cooling(cid, 'hotwire', H.CooldownSeconds) then return Veyl.Err('RATE_LIMITED', 'Slow down') end
    return Veyl.Ok({ token = attempt(src, cid, 'hotwire', id, H.MinMs, plate), difficulty = H.Difficulty })
end, { cooldown = 600 })

Veyl.RegisterCallback('hotwireFinish', function(src, cid, token, success)
    local t, err = finish(src, cid, 'hotwire', token)
    if not t then return err end
    local e = entityFromNet(t.netId)
    if not e or GetPedInVehicleSeat(e, -1) ~= GetPlayerPed(src) then return Veyl.Err('INVALID_STATE', 'You left the car') end
    if success ~= true then
        alert(src, cid, GetEntityCoords(e), 'Someone is tampering with a car', C.Hotwire.AlertChance)
        return Veyl.Err('FAILED', 'The wires shorted out')
    end
    giveKey(src, cid, t.plate)
    alert(src, cid, GetEntityCoords(e), 'A car was just stolen', C.Hotwire.AlertChance)
    return Veyl.Ok(nil, 'The engine turns over')
end, { cooldown = 400 })

---------------------------------------------------------------------------
-- Threatening a driver
---------------------------------------------------------------------------
Veyl.RegisterCallback('carjackStart', function(src, cid, netId)
    local J = C.Carjack
    if not J.Enabled then return Veyl.Err('INVALID_STATE', 'Not available') end
    local e, id = entityFromNet(netId)
    if not e or managed(e) then return Veyl.Err('INVALID_STATE', 'You cannot do that to this one') end
    if distance(src, e) > J.Range + 6.0 then return Veyl.Err('TOO_FAR', 'Too far away') end
    local driver = GetPedInVehicleSeat(e, -1)
    if driver == 0 or not DoesEntityExist(driver) or IsPedAPlayer(driver) then return Veyl.Err('INVALID_STATE', 'There is nobody to threaten') end
    local plate = plateOf(e)
    if hasKey(cid, plate) then return Veyl.Err('INVALID_STATE', 'You already have the keys') end
    if os.time() - (jacked[id] or 0) < 30 then return Veyl.Err('INVALID_STATE', 'They are already scared') end
    if cooling(cid, 'carjack', J.CooldownSeconds) then return Veyl.Err('RATE_LIMITED', 'Give it a moment') end
    jacked[id] = os.time()
    return Veyl.Ok({ token = attempt(src, cid, 'carjack', id, J.HoldMs - 400, plate), holdMs = J.HoldMs })
end, { cooldown = 800 })

Veyl.RegisterCallback('carjackFinish', function(src, cid, token)
    local J = C.Carjack
    local t, err = finish(src, cid, 'carjack', token)
    if not t then return err end
    local e = entityFromNet(t.netId)
    if not e or distance(src, e) > J.Range + 10.0 then return Veyl.Err('TOO_FAR', 'They got away') end
    alert(src, cid, GetEntityCoords(e), 'Someone is being carjacked at gunpoint', J.AlertChance)
    if math.random() < J.SuccessChance then
        giveKey(src, cid, t.plate)
        return Veyl.Ok({ gave = true }, 'They hand over the keys')
    end
    return Veyl.Ok({ gave = false }, 'They are not giving it up')
end, { cooldown = 400 })

Veyl.RegisterCallback('keys', function(src, cid) return Veyl.Ok(keyList(cid)) end, { cooldown = 1000 })

exports('HasKey', function(citizenid, plate) return type(citizenid) == 'string' and type(plate) == 'string' and hasKey(citizenid, plate:gsub('[^%w]', ''):upper()) end)
exports('GiveKey', function(citizenid, plate)
    if type(citizenid) ~= 'string' or type(plate) ~= 'string' then return false end
    local src = exports.veyl_core:GetSourceByCitizenId(citizenid)
    keys[citizenid] = keys[citizenid] or {}
    keys[citizenid][plate:gsub('[^%w]', ''):upper()] = os.time() + C.KeysMinutes * 60
    if src then TriggerClientEvent('veyl_cartheft:keys', src, keyList(citizenid)) end
    return true
end)

AddEventHandler('playerDropped', function() tokens[source] = nil end)

---------------------------------------------------------------------------
-- Loot in trunks and gloveboxes nobody owns
---------------------------------------------------------------------------
local function pick(def)
    local rolls = math.random(def.Rolls[1], def.Rolls[2])
    local total = def.EmptyWeight
    for _, e in ipairs(def.Items) do total = total + e.weight end
    local out = {}
    for _ = 1, rolls do
        local r = math.random() * total
        if r >= def.EmptyWeight then
            r = r - def.EmptyWeight
            for _, e in ipairs(def.Items) do
                r = r - e.weight
                if r <= 0 then out[#out + 1] = { item = e.item, count = math.random(e.min, e.max) } break end
            end
        end
    end
    return out
end
CartheftPick = pick -- for the tests

--- veyl_vehicles calls this each time a trunk or glovebox is opened or changed. For a car nobody owns ('p<PLATE>') that has not been
--- searched in the last RerollHours it puts a few random things inside. It must not yield (it runs inside an export), so the work is
--- done on its own thread; the contents appear in the open stash as soon as they are in.
exports('EnsureLoot', function(stashId, storageKey)
    local kind = stashId == 'veh_trunk' and 'trunk' or stashId == 'veh_glovebox' and 'glovebox' or nil
    if not kind or type(storageKey) ~= 'string' or #storageKey > 32 or not storageKey:match('^p[%w_%-]+$') then return end
    local mem = kind .. ':' .. storageKey
    if rolled[mem] then return end
    rolled[mem] = true
    CreateThread(function()
        local def = C.Loot[kind == 'trunk' and 'Trunk' or 'Glovebox']
        local row = MySQL.single.await('SELECT rolled_at FROM veyl_cartheft_loot WHERE kind = ? AND vkey = ?', { kind, storageKey })
        if row and os.time() - row.rolled_at < C.Loot.RerollHours * 3600 then return end
        MySQL.update.await('INSERT INTO veyl_cartheft_loot (kind, vkey, rolled_at) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE rolled_at = VALUES(rolled_at)', { kind, storageKey, os.time() })
        for i, f in ipairs(pick(def)) do
            Veyl.Await('veyl_inventory', 'GiveToKeyedStash', 15000, stashId, storageKey, f.item, f.count, nil, ('cartheftloot:%s:%s:%d:%d'):format(kind, storageKey, os.time(), i))
        end
    end)
end)
