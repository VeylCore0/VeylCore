-- veyl_delivery client: presentation only. Every step is a server request; the server decides outcomes.

local cfg = DeliveryConfig
local run = nil
local stopBlip, boxProp = nil, nil

local function removeStopBlip()
    if stopBlip then RemoveBlip(stopBlip) stopBlip = nil end
end

local function dropBox()
    if boxProp then
        DeleteEntity(boxProp)
        boxProp = nil
    end
    ClearPedTasks(PlayerPedId())
end

local function carryBox()
    if boxProp then return end
    local ped = PlayerPedId()
    local hash = Veyl.LoadModel('prop_cs_cardbox_01', 5000)
    if not hash then return end
    local c = GetEntityCoords(ped)
    boxProp = CreateObject(hash, c.x, c.y, c.z + 0.2, true, true, false)
    AttachEntityToEntity(boxProp, ped, GetPedBoneIndex(ped, 28422), 0.0, -0.03, 0.0, 5.0, 0.0, 0.0, true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(hash)
    if Veyl.LoadAnimDict('anim@heists@box_carry@') then
        TaskPlayAnim(ped, 'anim@heists@box_carry@', 'idle', 5.0, 5.0, -1, 51, 0, false, false, false)
    end
end

local function updateRoute()
    removeStopBlip()
    exports.veyl_interact:Remove('delivery_stop')
    exports.veyl_interact:Remove('delivery_van')
    if not run then return end

    if run.current <= run.total then
        local stop = run.stops[run.current]
        stopBlip = AddBlipForCoord(stop.x, stop.y, stop.z)
        SetBlipSprite(stopBlip, 478)
        SetBlipColour(stopBlip, 27)
        SetBlipRoute(stopBlip, true)
        SetBlipRouteColour(stopBlip, 27)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(('Delivery %d/%d'):format(run.current, run.total))
        EndTextCommandSetBlipName(stopBlip)

        exports.veyl_interact:AddZone({
            id = 'delivery_stop', coords = stop, radius = cfg.StopRadius - 0.5, label = 'Deliver package',
            event = 'veyl_delivery:deliver', canInteract = function() return run ~= nil and run.carrying end,
        })
        exports.veyl_interact:AddEntity({
            id = 'delivery_van', netId = run.netId, radius = 4.5, label = 'Take package',
            event = 'veyl_delivery:take', canInteract = function() return run ~= nil and not run.carrying end,
        })
    end

    if run.carrying then carryBox() else dropBox() end
end

local function setRun(data)
    run = data
    updateRoute()
end

local function clearRun()
    run = nil
    dropBox()
    removeStopBlip()
    exports.veyl_interact:Remove('delivery_stop')
    exports.veyl_interact:Remove('delivery_van')
end

-- Depot interactions ------------------------------------------------------
AddEventHandler('veyl_delivery:start', function()
    local ok = Veyl.UI.Confirm({
        title = 'GoPostal shift',
        message = ('Deliver %d packages around Mirror Park. $%d per stop plus a $%d bonus for finishing and returning the van.')
            :format(cfg.StopsPerRun, cfg.PayPerStop, cfg.CompletionBonus),
        confirmLabel = 'Start shift',
    })
    if not ok then return end
    local res = Veyl.Callback('veyl_delivery', 'start')
    Veyl.NotifyResult(res)
    if res.ok then
        setRun(res.data)
        Veyl.Notify('Your van is in the loading bay. Take a package from the back of the van.', 'info', 7000)
    end
end)

AddEventHandler('veyl_delivery:finish', function()
    local res = Veyl.Callback('veyl_delivery', 'finish')
    Veyl.NotifyResult(res)
    if res.ok then clearRun() end
end)

AddEventHandler('veyl_delivery:cancel', function()
    if not Veyl.UI.Confirm({ title = 'Cancel route', message = 'Cancel this route? Delivered packages are only paid when you finish at the depot.' }) then return end
    local res = Veyl.Callback('veyl_delivery', 'cancel')
    Veyl.NotifyResult(res)
    if res.ok then clearRun() end
end)

AddEventHandler('veyl_delivery:take', function()
    local res = Veyl.Callback('veyl_delivery', 'takePackage')
    Veyl.NotifyResult(res)
    if res.ok then setRun(res.data) end
end)

AddEventHandler('veyl_delivery:deliver', function()
    local ok = Veyl.UI.Progress({ label = 'Delivering package...', duration = 3000, disableMovement = true })
    if not ok then return end
    local res = Veyl.Callback('veyl_delivery', 'deliver')
    Veyl.NotifyResult(res)
    if res.ok then
        dropBox()
        setRun(res.data)
        if run and run.current > run.total then SetNewWaypoint(cfg.Depot.ped.coords.x, cfg.Depot.ped.coords.y) end
    end
end)

RegisterNetEvent('veyl_delivery:ended', function(status, reason)
    if run then
        if status ~= 'completed' then Veyl.Notify(('Your route ended (%s).'):format(reason), 'warning', 6000) end
        clearRun()
    end
end)

-- Character switch / reconnect: ask the server for the authoritative state.
RegisterNetEvent('VeylCore:Client:OnPlayerLoaded', function()
    clearRun()
    CreateThread(function()
        Wait(2000)
        local res = Veyl.Callback('veyl_delivery', 'status')
        if res.ok and res.data then setRun(res.data) end
    end)
end)
RegisterNetEvent('VeylCore:Client:OnPlayerUnload', clearRun)

-- Setup -------------------------------------------------------------------
CreateThread(function()
    while GetResourceState('veyl_interact') ~= 'started' do Wait(200) end
    local p = cfg.Depot.ped
    exports.veyl_interact:AddPed({
        id = 'delivery_depot', model = p.model, coords = p.coords, radius = cfg.Depot.radius,
        label = 'GoPostal depot', scenario = 'WORLD_HUMAN_CLIPBOARD', icon = 'fa-solid fa-box',
        options = {
            { label = 'Start a delivery shift', event = 'veyl_delivery:start', canInteract = function() return run == nil end },
            { label = 'Finish shift and get paid', event = 'veyl_delivery:finish', canInteract = function() return run ~= nil end },
            { label = 'Cancel route', event = 'veyl_delivery:cancel', canInteract = function() return run ~= nil end },
        },
    })
    local blip = AddBlipForCoord(p.coords.x, p.coords.y, p.coords.z)
    SetBlipSprite(blip, 67)
    SetBlipColour(blip, 27)
    SetBlipScale(blip, 0.8)
    SetBlipAsShortRange(blip, false)
    BeginTextCommandSetBlipName('STRING')
    AddTextComponentSubstringPlayerName('GoPostal Depot (Jobs)')
    EndTextCommandSetBlipName(blip)
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then clearRun() end
end)
