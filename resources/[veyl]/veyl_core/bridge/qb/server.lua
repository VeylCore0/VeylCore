-- QBCore-style core object for the server, backed entirely by veyl_core services (no second registry,
-- balance cache or save thread). Returned by exports.veyl_core:GetCoreObject() and by the optional
-- qb-core shim. Only the APIs listed in docs/COMPATIBILITY.md are supported.

local QBShared = {}

-- Small helpers many QB resources call through QBCore.Shared.
function QBShared.RandomStr(length)
    local chars, out = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz', {}
    for i = 1, math.max(0, tonumber(length) or 0) do local n = math.random(1, #chars) out[i] = chars:sub(n, n) end
    return table.concat(out)
end
function QBShared.RandomInt(length)
    local out = {}
    for i = 1, math.max(0, tonumber(length) or 0) do out[i] = tostring(math.random(0, 9)) end
    return table.concat(out)
end
function QBShared.SplitStr(str, delimiter)
    local result = {}
    for part in (tostring(str) .. delimiter):gmatch('(.-)' .. delimiter:gsub('%p', '%%%0')) do result[#result + 1] = part end
    return result
end
function QBShared.Trim(value) return value and (tostring(value):gsub('^%s*(.-)%s*$', '%1')) or nil end
function QBShared.FirstToUpper(value) return value and (tostring(value):gsub('^%l', string.upper)) or nil end
function QBShared.Round(value, decimals)
    local mult = 10 ^ (decimals or 0)
    return math.floor(value * mult + 0.5) / mult
end

--- Weapons keyed by hash, as QB scripts expect.
local function weaponsByHash()
    local out = {}
    for name, w in pairs(VeylShared.Weapons) do out[joaat(name)] = w end
    return out
end

--- Compatibility view of veyl_inventory's item definitions (veyl_inventory remains the authority).
function QBItemsView()
    if GetResourceState('veyl_inventory') ~= 'started' then return {} end
    local ok, items = pcall(function() return exports.veyl_inventory:Items() end)
    if not ok or type(items) ~= 'table' then return {} end
    local out = {}
    for name, it in pairs(items) do
        out[name] = {
            name = name, label = it.label, weight = it.weight or 0, type = 'item', image = it.image or (name .. '.svg'),
            unique = it.stack == false, useable = it.usable == true, shouldClose = true, description = it.description or '',
        }
    end
    return out
end

--- veyl_inventory slots in QB's PlayerData.items shape (read-only, derived view).
local function qbItemsFor(src)
    if GetResourceState('veyl_inventory') ~= 'started' then return {} end
    local ok, inv = pcall(function() return exports.veyl_inventory:GetInventoryItems(src) end)
    if not ok or type(inv) ~= 'table' then return {} end
    local out = {}
    for slot, it in pairs(inv) do
        out[slot] = { name = it.name, label = it.label, amount = it.count, count = it.count, info = it.metadata or {},
            slot = it.slot or slot, weight = it.weight, type = 'item', unique = it.stack == false }
    end
    return out
end

---------------------------------------------------------------------------
-- QB-style callbacks (request ids, timeouts, per-player inflight limits)
---------------------------------------------------------------------------
local qbCallbacks = {}
local inflight = {}

RegisterNetEvent('veyl_core:qbcb:req', function(name, reqId, ...)
    local src = source
    if type(name) ~= 'string' or type(reqId) ~= 'string' or #reqId > 64 then return end
    local handler = qbCallbacks[name]
    if not handler then
        print(('^3[veyl_core] QB callback "%s" is not registered^7'):format(name))
        return TriggerClientEvent('veyl_core:qbcb:res', src, reqId)
    end
    inflight[src] = (inflight[src] or 0) + 1
    if inflight[src] > 25 then
        inflight[src] = inflight[src] - 1
        return TriggerClientEvent('veyl_core:qbcb:res', src, reqId)
    end
    local replied = false
    local ok, err = pcall(handler, src, function(...)
        if replied then return end
        replied = true
        inflight[src] = math.max(0, (inflight[src] or 1) - 1)
        TriggerClientEvent('veyl_core:qbcb:res', src, reqId, ...)
    end, ...)
    if not ok then
        print(('^1[veyl_core] QB callback "%s" error: %s^7'):format(name, tostring(err)))
        if not replied then
            replied = true
            inflight[src] = math.max(0, (inflight[src] or 1) - 1)
            TriggerClientEvent('veyl_core:qbcb:res', src, reqId)
        end
    end
end)

AddEventHandler('playerDropped', function() inflight[source] = nil end)

---------------------------------------------------------------------------
-- Usable items: QB CreateUseableItem routes into veyl_inventory's single use pipeline.
---------------------------------------------------------------------------
local pendingUsable = {}

local function registerUsable(item, cb)
    if GetResourceState('veyl_inventory') == 'started' then
        exports.veyl_inventory:RegisterUsableItem(item, cb)
    else
        pendingUsable[item] = cb
    end
end

AddEventHandler('onResourceStart', function(res)
    if res ~= 'veyl_inventory' then return end
    SetTimeout(500, function()
        for item, cb in pairs(pendingUsable) do exports.veyl_inventory:RegisterUsableItem(item, cb) end
        pendingUsable = {}
    end)
end)

---------------------------------------------------------------------------
-- Core object
---------------------------------------------------------------------------
local function buildFunctions()
    local F = {}
    F.GetPlayer = function(src)
        local obj = Core.GetPlayerObject(src)
        if obj then obj.PlayerData.items = qbItemsFor(obj.PlayerData.source) end
        return obj
    end
    F.GetPlayerByCitizenId = function(citizenid)
        local src = Core.ByCitizen[citizenid]
        return src and F.GetPlayer(src) or nil
    end
    F.GetPlayerByPhone = function(phone)
        for src, p in pairs(Core.Players) do
            if p.charinfo.phone == phone then return F.GetPlayer(src) end
        end
        return nil
    end
    F.GetPlayers = function()
        local list = {}
        for src in pairs(Core.Players) do list[#list + 1] = src end
        return list
    end
    F.GetQBPlayers = function()
        local map = {}
        for src in pairs(Core.Players) do map[src] = Core.GetPlayerObject(src) end
        return map
    end
    F.GetIdentifier = function(src, idtype) return GetPlayerIdentifierByType(src, idtype or 'license') end
    F.GetSource = function(identifier)
        for src, p in pairs(Core.Players) do
            if p.license == identifier then return src end
        end
        return 0
    end
    F.Notify = function(src, text, kind, length)
        if type(text) == 'table' then text = text.text or text.caption or '' end
        if kind == 'primary' then kind = 'info' end
        TriggerClientEvent('veyl_ui:notify', src, { message = tostring(text), type = kind or 'info', duration = length })
    end
    F.HasPermission = function(src, perm) return Permissions.Has(src, perm) end
    F.Kick = function(src, reason) DropPlayer(src, reason or 'Kicked') end
    F.IsPlayerBanned = function() return false end
    F.GetDutyCount = function(job)
        local count, list = 0, {}
        for src, p in pairs(Core.Players) do
            if p.job == job and p.onduty then count = count + 1 list[#list + 1] = src end
        end
        return count, list
    end
    F.CreateCallback = function(name, cb) qbCallbacks[name] = cb end
    F.CreateUseableItem = function(item, cb) registerUsable(item, cb) end
    F.CanUseItem = function(item)
        if GetResourceState('veyl_inventory') ~= 'started' then return nil end
        return exports.veyl_inventory:GetUsableItem(item)
    end
    F.HasItem = function(src, items, amount)
        if GetResourceState('veyl_inventory') ~= 'started' then return false end
        if type(items) ~= 'table' then items = { items } end
        for k, v in pairs(items) do
            local name = type(k) == 'string' and k or v
            local need = type(k) == 'string' and v or (amount or 1)
            if (exports.veyl_inventory:GetItemCount(src, name) or 0) < need then return false end
        end
        return true
    end
    return F
end

local function buildShared()
    return {
        Jobs = VeylShared.Jobs, Gangs = VeylShared.Gangs, Vehicles = VeylShared.Vehicles,
        Weapons = weaponsByHash(), Items = QBItemsView(), Locations = VeylShared.Locations,
        RandomStr = QBShared.RandomStr, RandomInt = QBShared.RandomInt, SplitStr = QBShared.SplitStr,
        Trim = QBShared.Trim, FirstToUpper = QBShared.FirstToUpper, Round = QBShared.Round,
        StarterItems = {},
    }
end

local function buildCommands()
    return { Add = Commands.Add, Refresh = Commands.Refresh, List = Commands.List }
end

local function buildConfig()
    return {
        Money = { MoneyTypes = VeylServerConfig.StartingMoney, DontAllowMinus = { 'cash', 'bank', 'crypto' } },
        Player = { HungerRate = 4.2, ThirstRate = 3.8 },
        Server = { Name = VeylConfig.ServerName },
    }
end

local sections = { Functions = buildFunctions, Shared = buildShared, Commands = buildCommands, Config = buildConfig }

--- GetCoreObject(filter?) where filter is e.g. { 'Functions', 'Shared' }.
exports('GetCoreObject', function(filter)
    local obj = {}
    if type(filter) == 'table' and #filter > 0 then
        for _, key in ipairs(filter) do if sections[key] then obj[key] = sections[key]() end end
    else
        for key, build in pairs(sections) do obj[key] = build() end
    end
    return obj
end)
