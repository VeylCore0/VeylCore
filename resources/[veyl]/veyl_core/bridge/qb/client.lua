-- QBCore-style core object for the client, backed by veyl_core's PlayerData cache and veyl_ui.

local pending = {}

RegisterNetEvent('veyl_core:qbcb:res', function(reqId, ...)
    local cb = pending[reqId]
    if cb then
        pending[reqId] = nil
        cb(...)
    end
end)

RegisterNetEvent('VeylCore:Client:OnPlayerUnload', function()
    pending = {} -- abandoned requests from the previous character never call back
end)

local function buildFunctions()
    local F = {}
    F.GetPlayerData = function(cb)
        if cb then cb(PlayerData) end
        return PlayerData
    end
    F.Notify = function(text, kind, length)
        if type(text) == 'table' then text = text.text or text.caption or '' end
        if kind == 'primary' then kind = 'info' end
        TriggerEvent('veyl_ui:notify', { message = tostring(text), type = kind or 'info', duration = length })
    end
    F.TriggerCallback = function(name, cb, ...)
        local reqId = Veyl.NewId('qb')
        pending[reqId] = cb or function() end
        TriggerServerEvent('veyl_core:qbcb:req', name, reqId, ...)
        SetTimeout(30000, function()
            if pending[reqId] then
                pending[reqId] = nil
                print(('^3[veyl_core] QB callback "%s" timed out^7'):format(tostring(name)))
            end
        end)
    end
    F.HasItem = function(items, amount)
        if GetResourceState('ox_inventory') ~= 'started' then return false end
        if type(items) ~= 'table' then items = { items } end
        for k, v in pairs(items) do
            local name = type(k) == 'string' and k or v
            local need = type(k) == 'string' and v or (amount or 1)
            if (exports.ox_inventory:Search('count', name) or 0) < need then return false end
        end
        return true
    end
    F.GetPlate = function(vehicle)
        if not vehicle or vehicle == 0 then return nil end
        return (GetVehicleNumberPlateText(vehicle):gsub('^%s*(.-)%s*$', '%1'))
    end
    F.GetClosestPlayer = function(coords)
        local ped = PlayerPedId()
        coords = coords or GetEntityCoords(ped)
        local closest, dist = -1, -1
        for _, pid in ipairs(GetActivePlayers()) do
            if pid ~= PlayerId() then
                local d = #(coords - GetEntityCoords(GetPlayerPed(pid)))
                if dist == -1 or d < dist then closest, dist = pid, d end
            end
        end
        return closest, dist
    end
    F.GetClosestVehicle = function(coords)
        coords = coords or GetEntityCoords(PlayerPedId())
        local closest, dist = -1, -1
        for _, veh in ipairs(GetGamePool('CVehicle')) do
            local d = #(coords - GetEntityCoords(veh))
            if dist == -1 or d < dist then closest, dist = veh, d end
        end
        return closest, dist
    end
    --- QB Progressbar(name, label, duration, useWhileDead, canCancel, disableControls, animation, prop, propTwo, onFinish, onCancel)
    F.Progressbar = function(_, label, duration, _, canCancel, disableControls, animation, _, _, onFinish, onCancel)
        CreateThread(function()
            local anim = animation and animation.animDict and { dict = animation.animDict, clip = animation.anim, flag = animation.flags } or nil
            local done = Veyl.UI.Progress({
                label = label, duration = duration, canCancel = canCancel ~= false,
                disableMovement = type(disableControls) == 'table' and disableControls.disableMovement == true, anim = anim,
            })
            if done then
                if onFinish then onFinish() end
            elseif onCancel then
                onCancel()
            end
        end)
    end
    return F
end

local function buildShared()
    local items = {}
    if GetResourceState('ox_inventory') == 'started' then
        local ok, list = pcall(function() return exports.ox_inventory:Items() end)
        if ok and type(list) == 'table' then
            for name, it in pairs(list) do
                items[name] = { name = name, label = it.label, weight = it.weight or 0, image = name .. '.png', unique = it.stack == false }
            end
        end
    end
    local weapons = {}
    for name, w in pairs(VeylShared.Weapons) do weapons[joaat(name)] = w end
    return { Jobs = VeylShared.Jobs, Gangs = VeylShared.Gangs, Vehicles = VeylShared.Vehicles, Weapons = weapons, Items = items }
end

local sections = { Functions = buildFunctions, Shared = buildShared }

exports('GetCoreObject', function(filter)
    local obj = {}
    if type(filter) == 'table' and #filter > 0 then
        for _, key in ipairs(filter) do if sections[key] then obj[key] = sections[key]() end end
    else
        for key, build in pairs(sections) do obj[key] = build() end
    end
    return obj
end)
