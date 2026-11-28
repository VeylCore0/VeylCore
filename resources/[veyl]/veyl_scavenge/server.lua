-- veyl_scavenge server. The client says "I am searching this kind of prop here"; the server checks distance, cooldowns and rate limits,
-- times the search, rolls the loot itself and delivers it with durable inventory operations. The client never names an item or amount.

local C = ScavengeConfig
local jobs = {}        -- [src] = { token, kind, key, at, cid, x, y, z }
local propCool = {}    -- [key] = until (anyone)
local playerCool = {}  -- [cid .. key] = until
local hourly = {}      -- [cid] = { n, since }
local lastSearch = {}  -- [cid] = os.time()

local function core(name, ...) return Veyl.Await('veyl_core', name, 15000, ...) end
local function gift(cid, item, count, op) return Veyl.Await('veyl_inventory', 'GiveItem', 15000, cid, item, count, nil, op) end
local function carry(cid, item, count) local r = Veyl.Await('veyl_inventory', 'CanCarry', 10000, cid, item, count, nil) return r and r.ok end

-- Warn about loot items the inventory does not know, and drop them so a typo can never break a search.
local function validate()
    for kind, def in pairs(C.Kinds) do
        local clean = {}
        for i, e in ipairs(def.Loot) do
            if e.item then
                local known = exports.veyl_inventory:GetItemDefinition(e.item)
                if known then clean[#clean + 1] = e
                else print(('^3[veyl_scavenge] %s loot #%d: unknown item "%s" (add it to veyl_inventory/data/items.lua). Skipped.^7'):format(kind, i, e.item)) end
            elseif e.money then clean[#clean + 1] = e end
        end
        def.Active = clean
    end
end
-- Veyl.RegisterCallback refuses requests until the resource has reported ready, so this has to go through Startup.
Veyl.Startup({ 'veyl_core', 'veyl_inventory' }, function()
    validate()
    return true
end)
AddEventHandler('onResourceStart', function(res) if res == 'veyl_inventory' then SetTimeout(3000, validate) end end)

local function propKey(kind, x, y, z) return ('%s:%d:%d:%d'):format(kind, math.floor(x / 2), math.floor(y / 2), math.floor(z / 2)) end

--- Picks one entry by weight (or nil for an empty draw).
local function draw(def)
    local total = def.EmptyWeight or 0
    for _, e in ipairs(def.Active or {}) do total = total + e.weight end
    local r = math.random() * total
    for _, e in ipairs(def.Active or {}) do
        r = r - e.weight
        if r <= 0 then return e end
    end
    return nil
end

local function num(v) v = tonumber(v) if v and v == v and math.abs(v) < 10000 then return v end end

Veyl.RegisterCallback('searchStart', function(src, cid, kind, x, y, z)
    local def = type(kind) == 'string' and C.Kinds[kind]
    x, y, z = num(x), num(y), num(z)
    if not def or not x or not y or not z then Veyl.Audit(src, 'scavenge_bad_request', { kind = tostring(kind) }) return Veyl.Err('INVALID_INPUT', 'Bad request') end
    local pc = Veyl.GetPlayerCoords(src)
    if not pc or #(pc - vector3(x, y, z)) > C.Distance + 2.0 then return Veyl.Err('TOO_FAR', 'Get closer') end
    local now = os.time()
    if now - (lastSearch[cid] or 0) < C.MinSecondsBetween then return Veyl.Err('RATE_LIMITED', 'Slow down') end
    local h = hourly[cid]
    if not h or now - h.since > 3600 then h = { n = 0, since = now } hourly[cid] = h end
    if h.n >= C.MaxSearchesPerHour then return Veyl.Err('RATE_LIMITED', 'You have searched enough for now') end
    local key = propKey(kind, x, y, z)
    if (propCool[key] or 0) > now or (playerCool[cid .. key] or 0) > now then return Veyl.Err('COOLDOWN', 'Already picked over') end
    if GetVehiclePedIsIn(GetPlayerPed(src), false) ~= 0 then return Veyl.Err('INVALID_STATE', 'Get out of the vehicle') end
    local token = Veyl.NewId()
    jobs[src] = { token = token, kind = kind, key = key, at = GetGameTimer(), cid = cid, x = x, y = y, z = z }
    return Veyl.Ok({ token = token, durationMs = def.DurationMs, anim = def.Anim })
end, { cooldown = 800 })

Veyl.RegisterCallback('searchFinish', function(src, cid, token)
    local job = jobs[src]
    jobs[src] = nil
    if not job or job.token ~= token or job.cid ~= cid then Veyl.Audit(src, 'scavenge_bad_token', {}) return Veyl.Err('INVALID_STATE', 'Start again') end
    local def = C.Kinds[job.kind]
    if GetGameTimer() - job.at < def.DurationMs - 700 then Veyl.Audit(src, 'scavenge_too_fast', {}) return Veyl.Err('TOO_FAST', 'You stopped too early') end
    local pc = Veyl.GetPlayerCoords(src)
    if not pc or #(pc - vector3(job.x, job.y, job.z)) > C.Distance + 3.0 then return Veyl.Err('TOO_FAR', 'You moved away') end
    local now = os.time()
    -- Claim the prop first, so a second finish (or another player) cannot search the same thing again.
    if (propCool[job.key] or 0) > now then return Veyl.Err('COOLDOWN', 'Someone just searched it') end
    propCool[job.key] = now + def.PropCooldownMinutes * 60
    playerCool[cid .. job.key] = now + def.PlayerCooldownMinutes * 60
    lastSearch[cid] = now
    hourly[cid].n = (hourly[cid].n or 0) + 1

    local found, money = {}, 0
    local rolls = math.random(def.Rolls[1], def.Rolls[2])
    for _ = 1, rolls do
        local e = draw(def)
        if e and e.item then found[e.item] = (found[e.item] or 0) + math.random(e.min or 1, e.max or 1)
        elseif e and e.money then money = money + math.random(e.money[1], e.money[2]) end
    end

    local lines, tag = {}, ('scavenge:%s:%s'):format(cid, Veyl.NewId())
    local i = 0
    for item, n in pairs(found) do
        i = i + 1
        if carry(cid, item, n) then
            local g = gift(cid, item, n, ('%s:%d'):format(tag, i))
            if g and g.ok then
                local d = exports.veyl_inventory:GetItemDefinition(item)
                lines[#lines + 1] = ('%dx %s'):format(n, d and d.label or item)
            end
        end
    end
    if money > 0 then
        local r = core('CreditOnce', cid, 'cash', money, 'Dumpster diving', tag .. ':money')
        if r and r.ok then lines[#lines + 1] = ('$%d'):format(money) end
    end

    local h = def.Hazard
    if h and h.chance > 0 and math.random() < h.chance then
        local ped = GetPlayerPed(src)
        SetEntityHealth(ped, math.max(1, GetEntityHealth(ped) - h.damage))
        Veyl.Notify(src, h.message or 'Ouch', 'warning')
    end
    Veyl.Audit(src, 'scavenge', { kind = job.kind, items = found, money = money })
    if #lines == 0 then return Veyl.Ok({ found = {} }, 'You find nothing but trash') end
    return Veyl.Ok({ found = lines }, 'You find ' .. table.concat(lines, ', '))
end, { cooldown = 500 })

AddEventHandler('playerDropped', function()
    local src = source
    jobs[src] = nil
end)

-- Old cooldown entries are dropped now and then so the tables stay small.
CreateThread(function()
    while true do
        Wait(600000)
        local now = os.time()
        for k, v in pairs(propCool) do if v < now then propCool[k] = nil end end
        for k, v in pairs(playerCool) do if v < now then playerCool[k] = nil end end
    end
end)
