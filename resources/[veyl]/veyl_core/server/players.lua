-- veyl_core players: sessions (account level), the live player registry (character level), PlayerData views,
-- the player object exposed through exports / the core-object facade, saving and lifecycle events.

Core = Core or {}
Core.Sessions = {}     -- [source] = { accountId, license, name, maxCharacters, generation, pending }
Core.Players = {}      -- [source] = internal player (logged-in character)
Core.ByCitizen = {}    -- [citizenid] = source

local function deepcopy(v)
    if type(v) ~= 'table' then return v end
    local out = {}
    for k, val in pairs(v) do out[k] = deepcopy(val) end
    return out
end
Core.DeepCopy = deepcopy

---------------------------------------------------------------------------
-- Views
---------------------------------------------------------------------------
function Core.BuildJob(p)
    local name = p.job
    local def = VeylShared.Jobs[name] or VeylShared.Jobs[VeylConfig.DefaultJob]
    local level = p.jobs[name] or 0
    local grade = VeylShared.GetGrade('job', name, level) or { name = tostring(level), payment = 0 }
    return {
        name = name, label = def.label, type = def.type or 'none', onduty = p.onduty == true,
        payment = grade.payment or 0, isboss = grade.isboss == true,
        grade = { name = grade.name, level = level },
    }
end

function Core.BuildGang(p)
    local name = p.gang
    local def = VeylShared.Gangs[name] or VeylShared.Gangs[VeylConfig.DefaultGang]
    local level = p.gangs[name] or 0
    local grade = VeylShared.GetGrade('gang', name, level) or { name = tostring(level) }
    return { name = name, label = def.label, isboss = grade.isboss == true, grade = { name = grade.name, level = level } }
end

--- Full server-side PlayerData (includes license). Returned as a copy; callers cannot mutate core state.
function Core.BuildPlayerData(p)
    return {
        source = p.source,
        citizenid = p.citizenid,
        cid = p.cid,
        license = p.license,
        name = GetPlayerName(p.source),
        charinfo = deepcopy(p.charinfo),
        money = deepcopy(p.money),
        job = Core.BuildJob(p),
        jobs = deepcopy(p.jobs),
        gang = Core.BuildGang(p),
        gangs = deepcopy(p.gangs),
        metadata = deepcopy(p.metadata),
        position = deepcopy(p.position),
    }
end

--- Allowlisted view for the owning client only (no license / server identifiers).
function Core.BuildClientView(p)
    local view = Core.BuildPlayerData(p)
    view.license = nil
    return view
end

--- Coalesces several changes in the same tick into one SetPlayerData send.
function Core.SyncPlayer(p)
    if p.syncScheduled then return end
    p.syncScheduled = true
    SetTimeout(50, function()
        p.syncScheduled = false
        if Core.Players[p.source] == p then
            TriggerClientEvent('VeylCore:Player:SetPlayerData', p.source, Core.BuildClientView(p))
        end
    end)
end

---------------------------------------------------------------------------
-- Player object (QB-shaped; also returned by native exports.veyl_core:GetPlayer)
---------------------------------------------------------------------------
local function makeFunctions(p)
    local src = p.source
    local F = {}
    -- Money (legacy contract: returns boolean). Use exports CreditOnce/DebitOnce for repeat-safe rewards.
    F.AddMoney = function(moneyType, amount, reason) return Money.Add(src, moneyType, amount, reason) end
    F.RemoveMoney = function(moneyType, amount, reason) return Money.Remove(src, moneyType, amount, reason) end
    F.SetMoney = function(moneyType, amount, reason) return Money.Set(src, moneyType, amount, reason) end
    F.GetMoney = function(moneyType) return Money.Get(src, moneyType) end
    -- Groups
    F.SetJob = function(job, grade) return Groups.SetPrimaryReplacing(src, 'job', job, grade) end
    F.SetGang = function(gang, grade) return Groups.SetPrimaryReplacing(src, 'gang', gang, grade) end
    F.SetJobDuty = function(onDuty) return Groups.SetDuty(src, onDuty) end
    -- Metadata (QB casing)
    F.SetMetaData = function(key, value) return Metadata.Set(src, key, value) end
    F.GetMetaData = function(key) return Metadata.Get(src, key) end
    -- Data
    F.UpdatePlayerData = function() local pl = Core.Players[src]; if pl then Core.SyncPlayer(pl) end end
    F.SetPlayerData = function(key, value)
        if key == 'metadata' and type(value) == 'table' then
            for k, v in pairs(value) do Metadata.Set(src, k, v) end
            return true
        end
        print(('^3[veyl_core] SetPlayerData("%s") is not supported; use the dedicated API^7'):format(tostring(key)))
        return false
    end
    F.Save = function() local pl = Core.Players[src]; if pl then Core.SavePlayer(pl) end end
    F.Logout = function() return Core.Logout(src, 'logout') end
    -- Inventory delegates to veyl_inventory (the item authority). Legacy contract: synchronous booleans.
    local function inv() return GetResourceState('veyl_inventory') == 'started' end
    F.AddItem = function(item, amount, _, info)
        if not inv() then return false end
        return exports.veyl_inventory:AddItem(src, item, amount or 1, info) == true
    end
    F.RemoveItem = function(item, amount)
        if not inv() then return false end
        return exports.veyl_inventory:RemoveItem(src, item, amount or 1) == true
    end
    F.GetItemByName = function(item)
        if not inv() then return nil end
        return exports.veyl_inventory:GetSlotWithItem(src, item)
    end
    F.GetItemsByName = function(item)
        if not inv() then return {} end
        return exports.veyl_inventory:GetSlotsWithItem(src, item) or {}
    end
    F.HasItem = function(item, amount)
        if not inv() then return false end
        return (exports.veyl_inventory:GetItemCount(src, item) or 0) >= (amount or 1)
    end
    return F
end

function Core.GetPlayerObject(src)
    local p = Core.Players[tonumber(src)]
    if not p then return nil end
    p.functions = p.functions or makeFunctions(p)
    return { PlayerData = Core.BuildPlayerData(p), Functions = p.functions, Offline = false }
end

---------------------------------------------------------------------------
-- Saving (never touches money or groups: they are written by their own services)
---------------------------------------------------------------------------
local function validPosition(c)
    return c and math.abs(c.x) < 10000 and math.abs(c.y) < 10000 and c.z > -100 and c.z < 2000
        and not (math.abs(c.x) < 1 and math.abs(c.y) < 1)
end

function Core.CapturePosition(p)
    if not p.spawned then return end
    local ped = GetPlayerPed(p.source)
    if not ped or ped == 0 then return end
    local c = GetEntityCoords(ped)
    if validPosition(c) then
        p.position = { x = c.x, y = c.y, z = c.z, w = GetEntityHeading(ped) }
    end
end

--- Queues a save of metadata/position/charinfo. Returns the queue promise.
function Core.SavePlayer(p)
    Core.CapturePosition(p)
    local citizenid = p.citizenid
    local charinfo, metadata, position = json.encode(p.charinfo), json.encode(p.metadata), p.position and json.encode(p.position)
    return CoreEnqueue(citizenid, function()
        MySQL.update.await('UPDATE veyl_players SET charinfo = ?, metadata = ?, position = ? WHERE citizenid = ?',
            { charinfo, metadata, position, citizenid })
        return Veyl.Ok()
    end)
end

CreateThread(function()
    while true do
        Wait(VeylServerConfig.SaveIntervalMs)
        for _, p in pairs(Core.Players) do Core.SavePlayer(p) end
    end
end)

---------------------------------------------------------------------------
-- Login / logout
---------------------------------------------------------------------------
--- Registers a loaded character (built by characters.lua) and announces it.
function Core.Activate(src, p)
    local s = Core.Sessions[src]
    s.generation = s.generation + 1
    p.source = src
    p.generation = s.generation
    p.spawned = false
    Core.Players[src] = p
    Core.ByCitizen[p.citizenid] = src
    local state = Player(src).state
    state:set('citizenid', p.citizenid, true)
    state:set('isLoggedIn', true, true)
    TriggerEvent('VeylCore:Server:PlayerLoaded', src, p.citizenid)
    TriggerClientEvent('VeylCore:Player:SetPlayerData', src, Core.BuildClientView(p))
    TriggerClientEvent('VeylCore:Client:BeginSpawn', src, Core.BuildClientView(p))
end

--- Unloads the active character: listeners save synchronously first, then the core saves and clears.
function Core.Logout(src, reason)
    src = tonumber(src)
    local p = Core.Players[src]
    if not p then return false end
    reason = reason or 'logout'
    TriggerEvent('VeylCore:Server:OnPlayerUnload', src, p.citizenid, reason)
    Core.SavePlayer(p)
    Core.Players[src] = nil
    if Core.ByCitizen[p.citizenid] == src then Core.ByCitizen[p.citizenid] = nil end
    local s = Core.Sessions[src]
    if s then s.generation = s.generation + 1 end
    if GetPlayerName(src) then
        local state = Player(src).state
        state:set('isLoggedIn', false, true)
        state:set('citizenid', nil, true)
        TriggerClientEvent('VeylCore:Client:OnPlayerUnload', src, reason)
    end
    return true
end

--- Client reports the initial spawn finished: emit the "loaded" notifications exactly once per login.
RegisterNetEvent('veyl_core:server:spawnComplete', function()
    local src = source
    local p = Core.Players[src]
    if not p or p.spawned then return end
    p.spawned = true
    TriggerEvent('VeylCore:Server:OnPlayerSpawned', src, p.citizenid)
    TriggerClientEvent('VeylCore:Client:OnPlayerLoaded', src)
end)

---------------------------------------------------------------------------
-- Accounts & sessions
---------------------------------------------------------------------------
local function getLicense(src)
    return GetPlayerIdentifierByType(src, VeylServerConfig.AccountIdentifier)
end

local function upsertAccount(license, name)
    MySQL.insert.await([[INSERT INTO veyl_accounts (license, name, max_characters) VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE name = VALUES(name), last_seen = CURRENT_TIMESTAMP]],
        { license, name or '', VeylServerConfig.DefaultMaxCharacters })
    return MySQL.single.await('SELECT id, max_characters FROM veyl_accounts WHERE license = ?', { license })
end

AddEventHandler('playerConnecting', function(name, _, deferrals)
    local src = source
    deferrals.defer()
    Wait(0)
    deferrals.update('VeylCore: checking your account...')
    if not Veyl.IsReady() then
        return deferrals.done('VeylCore is still starting. Please try again in a moment.')
    end
    local license = getLicense(src)
    if not license then
        return deferrals.done('VeylCore requires a Rockstar license identifier. Restart FiveM and try again.')
    end
    local ok, account = pcall(upsertAccount, license, name)
    if not ok or not account then
        print(('^1[veyl_core] account lookup failed for %s: %s^7'):format(name, tostring(account)))
        return deferrals.done('VeylCore could not load your account (database error). Please try again.')
    end
    deferrals.done()
end)

RegisterNetEvent('veyl_core:clientReady', function()
    local src = source
    local s = Core.Sessions[src]
    if s and s.pending then return end
    if s then
        TriggerClientEvent('veyl_core:sessionReady', src, { maxCharacters = s.maxCharacters })
        local p = Core.Players[src]
        if p then TriggerClientEvent('VeylCore:Player:SetPlayerData', src, Core.BuildClientView(p)) end
        return
    end
    if not Veyl.IsReady() then
        TriggerClientEvent('veyl_core:sessionFailed', src, { code = 'NOT_READY', stage = 'core' })
        return
    end
    local license = getLicense(src)
    if not license then return DropPlayer(src, 'VeylCore: missing license identifier') end
    Core.Sessions[src] = { pending = true }
    local ok, account = pcall(upsertAccount, license, GetPlayerName(src))
    if not GetPlayerName(src) then Core.Sessions[src] = nil return end
    if not ok or not account then
        Core.Sessions[src] = nil
        print(('^1[veyl_core] session creation failed for %s: %s^7'):format(src, tostring(account)))
        TriggerClientEvent('veyl_core:sessionFailed', src, { code = 'DATABASE_ERROR', stage = 'account' })
        return
    end
    Core.Sessions[src] = {
        accountId = account.id, license = license, name = GetPlayerName(src),
        maxCharacters = account.max_characters, generation = 0,
    }
    TriggerClientEvent('veyl_core:sessionReady', src, { maxCharacters = account.max_characters })
end)

AddEventHandler('playerDropped', function()
    local src = source
    if Core.Players[src] then Core.Logout(src, 'dropped') end
    Core.Sessions[src] = nil
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for src, p in pairs(Core.Players) do
        Core.CapturePosition(p)
        -- Synchronous best-effort save on shutdown (the queue thread will not run after stop).
        MySQL.update('UPDATE veyl_players SET charinfo = ?, metadata = ?, position = ? WHERE citizenid = ?',
            { json.encode(p.charinfo), json.encode(p.metadata), p.position and json.encode(p.position), p.citizenid })
        Player(src).state:set('isLoggedIn', false, true)
        Player(src).state:set('citizenid', nil, true)
        TriggerClientEvent('VeylCore:Client:OnPlayerUnload', src, 'core_stopped')
    end
end)
