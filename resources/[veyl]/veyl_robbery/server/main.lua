-- veyl_robbery server: register and safe robberies with police minimums, cooldowns and a silent alarm.
-- Timed like every other action here: start returns a token, finish re-checks distance, time and requirements.

local C = RobberyConfig
local storeCooldown, playerCooldown, jobs = {}, {}, {} -- jobs[src] = { store, kind, at, token }

local function core(name, ...) return Veyl.Await('veyl_core', name, 15000, ...) end
local stores = {} -- [shop id] = { id, label, register = vector3, safe = vector3? }

--- Every robbable shop from veyl_shops: the register is where the clerk stands.
local function loadStores()
    stores = {}
    for _, s in ipairs(exports.veyl_shops:GetShops() or {}) do
        if s.robbable and s.ped and s.ped.coords then
            local c = s.ped.coords
            local name = (s.blip and s.blip.name) or s.label
            stores[s.id] = { id = s.id, label = ('%s (%s)'):format(name, s.id), register = vector3(c.x, c.y, c.z), safe = C.Safes[s.id] }
        end
    end
end

Veyl.Startup({ 'veyl_core', 'veyl_inventory', 'veyl_shops' }, function()
    loadStores()
    local n = 0
    for _ in pairs(stores) do n = n + 1 end
    print(('^5[veyl_robbery] %d robbable stores^7'):format(n))
    return true
end)

--- The client asks for the list once (the shop list lives in veyl_shops).
Veyl.RegisterCallback('stores', function()
    local out = {}
    for id, s in pairs(stores) do out[#out + 1] = { id = id, label = s.label, register = s.register, safe = s.safe } end
    return Veyl.Ok(out)
end, { cooldown = 5000, requireCharacter = false })

local function policeOnDuty()
    local n = 0
    for _, s in ipairs(GetPlayers()) do
        local pd = Veyl.GetPlayerData(tonumber(s))
        if pd and pd.job.onduty then for _, j in ipairs(C.PoliceJobs) do if pd.job.name == j then n = n + 1 end end end
    end
    return n
end

local function near(src, pos, d)
    local pc = Veyl.GetPlayerCoords(src)
    return pc ~= nil and #(pc - pos) <= d
end

local function alarm(store, kind)
    if GetResourceState('veyl_dispatch') ~= 'started' then return end
    SetTimeout(C.AlarmDelaySeconds * 1000, function()
        pcall(function()
            exports.veyl_dispatch:Alert({ services = { 'police' }, code = '10-90', title = 'Store robbery', priority = 1,
                coords = kind == 'safe' and store.safe or store.register, street = store.label,
                message = kind == 'safe' and ('Safe alarm tripped at %s'):format(store.label) or ('Silent alarm at %s'):format(store.label),
                blip = { sprite = 156, colour = 1, scale = 1.2 } })
        end)
    end)
end

Veyl.RegisterCallback('start', function(src, citizenid, storeId, kind)
    local s = stores[storeId]
    if not s or (kind ~= 'register' and kind ~= 'safe') or (kind == 'safe' and not s.safe) then return Veyl.Err('INVALID_INPUT', 'Unknown target') end
    if not near(src, kind == 'safe' and s.safe or s.register, 3.0) then return Veyl.Err('TOO_FAR', 'Move closer') end
    if Player(src).state.medical or Player(src).state.cuffed then return Veyl.Err('INVALID_STATE', 'Not right now') end
    local pd = Veyl.GetPlayerData(src)
    for _, j in ipairs(C.PoliceJobs) do if pd.job.name == j and pd.job.onduty then return Veyl.Err('NO_PERMISSION', 'Not while on duty') end end
    if policeOnDuty() < C.MinPolice then return Veyl.Err('UNAVAILABLE', 'The store is too quiet right now. Come back later.') end
    local now = os.time()
    local key = storeId .. ':' .. kind
    if (storeCooldown[key] or 0) > now then return Veyl.Err('RATE_LIMITED', ('This %s was emptied recently'):format(kind)) end
    if (playerCooldown[citizenid] or 0) > now then return Veyl.Err('RATE_LIMITED', 'Lie low for a while first') end
    if kind == 'register' and GetSelectedPedWeapon(GetPlayerPed(src)) == `WEAPON_UNARMED` then return Veyl.Err('NO_ITEM', 'You need a weapon to threaten the clerk') end
    if kind == 'safe' and (exports.veyl_inventory:GetItemCount(src, C.Safe.item) or 0) < 1 then return Veyl.Err('NO_ITEM', 'You need a lockpick') end
    storeCooldown[key] = now + C.StoreCooldownMinutes * 60
    playerCooldown[citizenid] = now + C.PlayerCooldownMinutes * 60
    local token = Veyl.NewId()
    jobs[src] = { store = storeId, kind = kind, at = GetGameTimer(), token = token }
    alarm(s, kind)
    Veyl.Audit(src, 'robbery_start', { store = storeId, kind = kind })
    return Veyl.Ok({ token = token, seconds = kind == 'safe' and C.Safe.seconds or C.Register.seconds })
end, { cooldown = 2000 })

Veyl.RegisterCallback('finish', function(src, citizenid, token)
    local j = jobs[src]
    jobs[src] = nil
    if not j or j.token ~= token then return Veyl.Err('INVALID_STATE', 'Start again') end
    local s = stores[j.store]
    local cfg = j.kind == 'safe' and C.Safe or C.Register
    if GetGameTimer() - j.at < cfg.seconds * 1000 - 600 then return Veyl.Err('TOO_FAST', 'You ran off too early') end
    if not near(src, j.kind == 'safe' and s.safe or s.register, 3.5) then return Veyl.Err('TOO_FAR', 'You walked away') end
    if Player(src).state.medical or Player(src).state.cuffed then return Veyl.Err('INVALID_STATE', 'You were stopped') end
    if j.kind == 'safe' then
        if (exports.veyl_inventory:GetItemCount(src, C.Safe.item) or 0) < 1 then return Veyl.Err('NO_ITEM', 'You need a lockpick') end
        if math.random() < C.Safe.breakChance then exports.veyl_inventory:RemoveItem(src, C.Safe.item, 1) end
    end
    local amount = math.random(cfg.reward[1], cfg.reward[2])
    local r = core('CreditOnce', citizenid, 'cash', amount, ('Robbery: %s %s'):format(s.label, j.kind), 'robbery:' .. token)
    if not r.ok and r.code ~= 'DUPLICATE_OPERATION' then return Veyl.Err('INTERNAL', 'Something went wrong') end
    Veyl.Audit(src, 'robbery_finish', { store = j.store, kind = j.kind, amount = amount })
    return Veyl.Ok({ amount = amount }, ('You got away with $%d'):format(amount))
end, { cooldown = 1000 })

Veyl.RegisterCallback('cancel', function(src) jobs[src] = nil return Veyl.Ok() end, { cooldown = 200 })
AddEventHandler('playerDropped', function() jobs[source] = nil end)
