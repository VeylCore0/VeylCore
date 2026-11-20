-- veyl_core server exports (native API). Sync exports never yield; durable/DB exports take a trailing
-- callback and are called with Veyl.Await(...) from @veyl_core/lib/shared.lua.

Veyl.Startup({}, function()
    return Veyl.Migrate(CoreMigrations)
end)

-- Resources allowed to drive the character lifecycle (selection UI).
local CHARACTER_UI = { veyl_characters = true }

local function restrictedAsync(name, fn)
    exports(name, function(...)
        local args = table.pack(...)
        local cb = args[args.n]
        local invoker = GetInvokingResource()
        if not CHARACTER_UI[invoker] then
            print(('^1[veyl_core] %s refused from %s^7'):format(name, tostring(invoker)))
            if type(cb) == 'function' or type(cb) == 'table' then cb(Veyl.Err('NO_PERMISSION', 'Not allowed')) end
            return
        end
        CreateThread(function()
            if not Veyl.IsReady() then return cb(Veyl.Err('NOT_READY', 'Core not ready')) end
            local ok, res = pcall(fn, table.unpack(args, 1, args.n - 1))
            if not ok then
                print(('^1[veyl_core] %s error: %s^7'):format(name, tostring(res)))
                res = Veyl.Err('INTERNAL', 'internal error')
            end
            cb(res)
        end)
    end)
end

---------------------------------------------------------------------------
-- Players
---------------------------------------------------------------------------
exports('GetPlayer', function(src) return Core.GetPlayerObject(src) end)
exports('GetPlayerByCitizenId', function(citizenid)
    local src = Core.ByCitizen[citizenid]
    return src and Core.GetPlayerObject(src) or nil
end)
exports('GetPlayerData', function(src)
    local p = Core.Players[tonumber(src)]
    return p and Core.BuildPlayerData(p) or nil
end)
exports('GetPlayersData', function()
    local list = {}
    for _, p in pairs(Core.Players) do list[#list + 1] = Core.BuildPlayerData(p) end
    return list
end)
exports('GetCitizenId', function(src)
    local p = Core.Players[tonumber(src)]
    return p and p.citizenid or nil
end)
exports('GetSourceByCitizenId', function(citizenid) return Core.ByCitizen[citizenid] end)
exports('GetSessionGeneration', function(src)
    local s = Core.Sessions[tonumber(src)]
    return s and s.generation or nil
end)
--- QB-style: list of sources with a loaded character.
exports('GetPlayers', function()
    local list = {}
    for src in pairs(Core.Players) do list[#list + 1] = src end
    return list
end)
--- Diagnostics: every connected session, with or without a character.
exports('GetSessions', function()
    local list = {}
    for src, s in pairs(Core.Sessions) do
        if s.accountId then
            local p = Core.Players[src]
            list[#list + 1] = {
                source = src, accountId = s.accountId, name = s.name, citizenid = p and p.citizenid or nil,
                characterName = p and ('%s %s'):format(p.charinfo.firstname or '', p.charinfo.lastname or '') or nil,
            }
        end
    end
    return list
end)
exports('IsSpawned', function(src)
    local p = Core.Players[tonumber(src)]
    return p ~= nil and p.spawned == true
end)
exports('Save', function(src)
    local p = Core.Players[tonumber(src)]
    if p then Core.SavePlayer(p) end
end)
exports('Logout', function(src, reason) return Core.Logout(src, reason) end)

---------------------------------------------------------------------------
-- Money (legacy contract: booleans)
---------------------------------------------------------------------------
exports('GetMoney', function(src, moneyType) return Money.Get(src, moneyType) end)
exports('AddMoney', function(src, moneyType, amount, reason) return Money.Add(src, moneyType, amount, reason, GetInvokingResource()) end)
exports('RemoveMoney', function(src, moneyType, amount, reason) return Money.Remove(src, moneyType, amount, reason, GetInvokingResource()) end)
exports('SetMoney', function(src, moneyType, amount, reason) return Money.Set(src, moneyType, amount, reason) end)

-- Durable, repeat-safe money: Veyl.Await('veyl_core', 'CreditOnce', timeout, citizenid, type, amount, reason, opId)
local function durableExport(name, fn)
    exports(name, function(...)
        local args = table.pack(...)
        local cb = args[args.n]
        local actor = GetInvokingResource() or 'veyl_core'
        CreateThread(function()
            if not Veyl.IsReady() then return cb(Veyl.Err('NOT_READY', 'Core not ready')) end
            local ok, res = pcall(fn, actor, table.unpack(args, 1, args.n - 1))
            if not ok then
                print(('^1[veyl_core] %s error: %s^7'):format(name, tostring(res)))
                res = Veyl.Err('INTERNAL', 'internal error')
            end
            cb(res)
        end)
    end)
end

durableExport('CreditOnce', function(actor, citizenid, moneyType, amount, reason, opId)
    return Money.CreditOnce(citizenid, moneyType, amount, reason, opId, actor)
end)
durableExport('DebitOnce', function(actor, citizenid, moneyType, amount, reason, opId)
    return Money.DebitOnce(citizenid, moneyType, amount, reason, opId, actor)
end)
durableExport('TransferMoney', function(actor, fromCid, fromType, toCid, toType, amount, reason, opId)
    return Money.Transfer(fromCid, fromType, toCid, toType, amount, reason, opId, actor)
end)
durableExport('GetMoneyOperation', function(_, opId) return Veyl.Ok(Money.GetOperation(opId)) end)
durableExport('GetMoneyHistory', function(_, citizenid, limit) return Veyl.Ok(Money.History(citizenid, limit)) end)

---------------------------------------------------------------------------
-- Metadata
---------------------------------------------------------------------------
exports('GetMetadata', function(src, key) return Metadata.Get(src, key) end)
exports('SetMetadata', function(src, key, value) return Metadata.Set(src, key, value) end)
exports('SetMetadataMany', function(src, values) return Metadata.SetMany(src, values) end)

---------------------------------------------------------------------------
-- Jobs / gangs
---------------------------------------------------------------------------
exports('SetJob', function(src, name, grade) return Groups.SetPrimaryReplacing(src, 'job', name, grade) end)
exports('SetGang', function(src, name, grade) return Groups.SetPrimaryReplacing(src, 'gang', name, grade) end)
exports('SetJobDuty', function(src, onDuty) return Groups.SetDuty(src, onDuty) end)
exports('AddPlayerToJob', function(citizenid, name, grade) return Groups.AddMember(citizenid, 'job', name, grade) end)
exports('RemovePlayerFromJob', function(citizenid, name) return Groups.RemoveMember(citizenid, 'job', name) end)
exports('SetPlayerPrimaryJob', function(citizenid, name) return Groups.SetPrimary(citizenid, 'job', name) end)
exports('AddPlayerToGang', function(citizenid, name, grade) return Groups.AddMember(citizenid, 'gang', name, grade) end)
exports('RemovePlayerFromGang', function(citizenid, name) return Groups.RemoveMember(citizenid, 'gang', name) end)
exports('SetPlayerPrimaryGang', function(citizenid, name) return Groups.SetPrimary(citizenid, 'gang', name) end)
exports('GetGroups', function(src) return Groups.GetGroups(src) end)
exports('HasGroup', function(src, filter) return Groups.HasGroup(src, filter) end)
exports('HasPrimaryGroup', function(src, filter) return Groups.HasPrimaryGroup(src, filter) end)
exports('IsGradeBoss', function(name, grade) return Groups.IsGradeBoss(name, grade) end)

---------------------------------------------------------------------------
-- Shared catalogs
---------------------------------------------------------------------------
exports('GetJobs', function() return VeylShared.Jobs end)
exports('GetJob', function(name) return VeylShared.Jobs[name] end)
exports('GetGangs', function() return VeylShared.Gangs end)
exports('GetVehicles', function() return VeylShared.Vehicles end)
exports('GetWeapons', function() return VeylShared.Weapons end)
exports('GetLocations', function() return VeylShared.Locations end)

---------------------------------------------------------------------------
-- Permissions, notifications, audit
---------------------------------------------------------------------------
exports('HasPermission', function(src, permission) return Permissions.Has(src, permission) end)

exports('Notify', function(src, message, kind, duration)
    TriggerClientEvent('veyl_ui:notify', src, { message = tostring(message), type = kind or 'info', duration = duration })
end)

exports('Audit', function(src, resource, action, data)
    local p = src and Core.Players[tonumber(src)]
    local s = src and Core.Sessions[tonumber(src)]
    MySQL.insert('INSERT INTO veyl_audit (account_id, citizenid, resource, action, data) VALUES (?, ?, ?, ?, ?)',
        { s and s.accountId or nil, p and p.citizenid or nil, tostring(resource or '?'), tostring(action),
          data ~= nil and json.encode(data) or nil })
end)

---------------------------------------------------------------------------
-- Character lifecycle (veyl_characters only)
---------------------------------------------------------------------------
restrictedAsync('ListCharacters', function(src) return Characters.List(src) end)
restrictedAsync('CreateCharacter', function(src, data) return Characters.Create(src, data) end)
restrictedAsync('DeleteCharacter', function(src, citizenid, confirmName) return Characters.Delete(src, citizenid, confirmName) end)
restrictedAsync('LoginCharacter', function(src, citizenid) return Characters.Login(src, citizenid) end)
