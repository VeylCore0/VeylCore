-- veyl_heists server: Fleeca banks, the Paleto bank and Vangelico.
-- Each location has a state: idle -> (thermite) -> hacked/open -> looted, then a cooldown back to idle.
-- Every step is timed (start token, finish re-checks time, distance, items) and the first step alerts the police.

local C = HeistsConfig
local state = {}   -- [id] = { stage = 'idle'|'door'|'open', loots = n, cooldownUntil, lastSet }
local actions = {} -- [src] = { id, step, at, token, seconds }

local function core(name, ...) return Veyl.Await('veyl_core', name, 15000, ...) end
Veyl.Startup({ 'veyl_core', 'veyl_inventory' }, function() return true end)

local locations = {}
for _, b in ipairs(C.Fleeca.banks) do
    locations[b.id] = { id = b.id, kind = 'fleeca', label = b.label, panel = b.panel, cfg = C.Fleeca, boxes = b.boxes }
end
locations[C.Paleto.id] = { id = C.Paleto.id, kind = 'paleto', label = C.Paleto.label, panel = C.Paleto.panel, door = C.Paleto.door, cfg = C.Paleto }
locations[C.Jewelry.id] = { id = C.Jewelry.id, kind = 'jewelry', label = C.Jewelry.label, panel = C.Jewelry.center, cfg = C.Jewelry }

local function st(id)
    state[id] = state[id] or { stage = 'idle', loots = 0, cooldownUntil = 0 }
    local s = state[id]
    if s.stage ~= 'idle' and s.cooldownUntil > 0 and os.time() >= s.cooldownUntil then state[id] = { stage = 'idle', loots = 0, cooldownUntil = 0 } end
    return state[id]
end

local function police()
    local n = 0
    for _, s in ipairs(GetPlayers()) do
        local pd = Veyl.GetPlayerData(tonumber(s))
        if pd and pd.job.onduty then for _, j in ipairs(C.PoliceJobs) do if pd.job.name == j then n = n + 1 end end end
    end
    return n
end

local function near(src, pos, d) local pc = Veyl.GetPlayerCoords(src) return pc ~= nil and #(pc - pos) <= d end
local function count(src, item) return exports.veyl_inventory:GetItemCount(src, item) or 0 end

local function alarm(loc, title)
    TriggerClientEvent('veyl_heists:sync', -1, loc.id, state[loc.id] and state[loc.id].stage or 'idle')
    if GetResourceState('veyl_dispatch') ~= 'started' then return end
    pcall(function()
        exports.veyl_dispatch:Alert({ services = { 'police' }, code = '10-90', title = title, priority = 1, coords = loc.panel, street = loc.label,
            message = ('Alarm triggered at %s'):format(loc.label), blip = { sprite = 161, colour = 1, scale = 1.4 } })
    end)
end

local function bankBusy(exceptId)
    if not C.OneBankAtATime then return false end
    for id, s in pairs(state) do
        local loc = locations[id]
        if id ~= exceptId and loc.kind ~= 'jewelry' and s.stage ~= 'idle' and (s.cooldownUntil == 0 or os.time() < (s.lastActive or 0) + 900) then return true end
    end
    return false
end

--- What this player can do at a location right now: 'thermite', 'hack', 'loot', 'smash' or nil, err.
local function nextStep(src, id, box)
    local loc = locations[id]
    if not loc then return nil, Veyl.Err('NOT_FOUND', 'Unknown place') end
    local s = st(id)
    local cfg = loc.cfg
    if Player(src).state.medical or Player(src).state.cuffed then return nil, Veyl.Err('INVALID_STATE', 'Not right now') end
    if s.stage == 'idle' then
        if s.cooldownUntil > os.time() then return nil, Veyl.Err('RATE_LIMITED', 'This place was hit recently') end
        if police() < cfg.minPolice then return nil, Veyl.Err('UNAVAILABLE', 'Too quiet. Come back when the city is busier.') end
        if loc.kind ~= 'jewelry' and bankBusy(id) then return nil, Veyl.Err('UNAVAILABLE', 'Another bank job is going on') end
    end
    if loc.kind == 'jewelry' then
        if s.loots >= cfg.loots then return nil, Veyl.Err('INVALID_STATE', 'Every case is empty') end
        if GetSelectedPedWeapon(GetPlayerPed(src)) == `WEAPON_UNARMED` then return nil, Veyl.Err('NO_ITEM', 'Draw a weapon to smash the glass') end
        return 'smash', cfg.smashSeconds
    end
    if loc.kind == 'paleto' and s.stage == 'idle' then
        if count(src, cfg.thermiteItem) < 1 then return nil, Veyl.Err('NO_ITEM', 'The vault door needs thermite') end
        return 'thermite', cfg.thermiteSeconds
    end
    if s.stage == 'idle' or s.stage == 'door' then
        if count(src, cfg.hackItem) < 1 then return nil, Veyl.Err('NO_ITEM', 'You need a hacking device') end
        return 'hack', cfg.hackSeconds
    end
    if s.loots >= cfg.loots then return nil, Veyl.Err('INVALID_STATE', 'The deposit boxes are empty') end
    if loc.boxes then
        if not box then return nil, Veyl.Err('INVALID_STATE', 'The vault is open. Walk in and drill the lockboxes.') end
        if not loc.boxes[box] then return nil, Veyl.Err('INVALID_INPUT', 'No such lockbox') end
        if s.drilled and s.drilled[box] then return nil, Veyl.Err('INVALID_STATE', 'That lockbox is already empty') end
    end
    if count(src, cfg.drillItem) < 1 then return nil, Veyl.Err('NO_ITEM', 'You need a drill') end
    return 'loot', cfg.lootSeconds
end

Veyl.RegisterCallback('start', function(src, _, id, box)
    local loc = locations[id]
    box = tonumber(box)
    if box and box == math.floor(box) then box = math.floor(box) else box = nil end
    local step, seconds = nextStep(src, id, box)
    if not step then return seconds end
    local point = (step == 'thermite') and loc.door or loc.panel
    if step == 'loot' and loc.boxes then point = loc.boxes[box] end
    if not near(src, point, loc.kind == 'jewelry' and loc.cfg.radius or 3.0) then return Veyl.Err('TOO_FAR', 'Move closer') end
    -- Someone else drilling that very box right now?
    if step == 'loot' and loc.boxes then
        for other, act in pairs(actions) do if other ~= src and act.id == id and act.box == box and GetGameTimer() - act.at < act.seconds * 1000 + 5000 then return Veyl.Err('UNAVAILABLE', 'Someone is already drilling that one') end end
    end
    local s = st(id)
    if s.stage == 'idle' then
        -- The alarm goes off with the first action; the cooldown starts now.
        s.cooldownUntil = os.time() + loc.cfg.cooldownMinutes * 60
        s.lastActive = os.time()
        if loc.kind == 'jewelry' then s.stage = 'open' end
        alarm(loc, loc.kind == 'jewelry' and 'Jewelry store robbery' or 'Bank robbery')
    end
    local token = Veyl.NewId()
    actions[src] = { id = id, step = step, at = GetGameTimer(), token = token, seconds = seconds, box = step == 'loot' and box or nil }
    Veyl.Audit(src, 'heist_step', { place = id, step = step })
    return Veyl.Ok({ token = token, seconds = seconds, step = step })
end, { cooldown = 1500 })

Veyl.RegisterCallback('finish', function(src, citizenid, token)
    local a = actions[src]
    actions[src] = nil
    if not a or a.token ~= token then return Veyl.Err('INVALID_STATE', 'Start again') end
    local loc, s = locations[a.id], st(a.id)
    local cfg = loc.cfg
    if GetGameTimer() - a.at < a.seconds * 1000 - 600 then return Veyl.Err('TOO_FAST', 'You stopped too early') end
    local point = (a.step == 'thermite') and loc.door or loc.panel
    if a.step == 'loot' and a.box and loc.boxes then point = loc.boxes[a.box] end
    if not near(src, point, loc.kind == 'jewelry' and cfg.radius + 1.0 or 3.5) then return Veyl.Err('TOO_FAR', 'You walked away') end
    s.lastActive = os.time()
    if a.step == 'thermite' then
        if not exports.veyl_inventory:RemoveItem(src, cfg.thermiteItem, 1) then return Veyl.Err('NO_ITEM', 'No thermite') end
        s.stage = 'door'
        TriggerClientEvent('veyl_heists:sync', -1, a.id, s.stage)
        return Veyl.Ok(nil, 'The lock melts. Hack the vault panel.')
    elseif a.step == 'hack' then
        if count(src, cfg.hackItem) < 1 then return Veyl.Err('NO_ITEM', 'No hacking device') end
        if math.random() < (cfg.hackBreakChance or 0.5) then exports.veyl_inventory:RemoveItem(src, cfg.hackItem, 1) end
        s.stage = 'open'
        TriggerClientEvent('veyl_heists:sync', -1, a.id, s.stage)
        return Veyl.Ok(nil, ('Vault open. %d deposit boxes to drill.'):format(cfg.loots))
    elseif a.step == 'loot' then
        if s.loots >= cfg.loots then return Veyl.Err('INVALID_STATE', 'Empty') end
        if a.box then
            s.drilled = s.drilled or {}
            if s.drilled[a.box] then return Veyl.Err('INVALID_STATE', 'That lockbox is already empty') end
            s.drilled[a.box] = true
        end
        s.loots = s.loots + 1
        local amount = math.random(cfg.reward[1], cfg.reward[2])
        local r = Veyl.Await('veyl_inventory', 'GiveItem', 15000, citizenid, 'marked_bills', amount, nil, 'heist:' .. token)
        if not r.ok then s.loots = s.loots - 1 if a.box then s.drilled[a.box] = nil end return Veyl.Err('INVENTORY_FULL', 'No room for the cash') end
        return Veyl.Ok(nil, ('$%d in marked bills (%d/%d boxes)'):format(amount, s.loots, cfg.loots))
    else -- smash
        if s.loots >= cfg.loots then return Veyl.Err('INVALID_STATE', 'Empty') end
        s.loots = s.loots + 1
        local got = {}
        for i, l in ipairs(cfg.loot) do
            local n = math.random(l.min, l.max)
            if n > 0 then
                local r = Veyl.Await('veyl_inventory', 'GiveItem', 15000, citizenid, l.item, n, nil, ('heist:%s:%d'):format(token, i))
                if r.ok then got[#got + 1] = ('%dx %s'):format(n, l.item) end
            end
        end
        return Veyl.Ok(nil, ('Grabbed %s (%d/%d cases)'):format(#got > 0 and table.concat(got, ', ') or 'nothing', s.loots, cfg.loots))
    end
end, { cooldown = 500 })

Veyl.RegisterCallback('cancel', function(src) actions[src] = nil return Veyl.Ok() end, { cooldown = 200 })

Veyl.RegisterCallback('states', function()
    local out = {}
    for id in pairs(locations) do
        local s = st(id)
        out[id] = s.stage
    end
    return Veyl.Ok(out)
end, { cooldown = 2000 })

AddEventHandler('playerDropped', function() actions[source] = nil end)
