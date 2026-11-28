-- Contract presence in the world: the search-area blip, the handoff blip and zone, and the options on the contract vehicles.
-- Everything here is presentation: the server decides whether any action works.

local C = BoostingConfig
local active           -- the latest contract view from the server (or nil)
local areaBlip, dropBlip
local nets = {}        -- [netId] = vehicle status ('waiting' | 'acquired' | 'delivered')
local busy = false
local DROP_ZONE = 'veyl_boosting_drop'

local function clearBlips()
    if areaBlip and DoesBlipExist(areaBlip) then RemoveBlip(areaBlip) end
    if dropBlip and DoesBlipExist(dropBlip) then RemoveBlip(dropBlip) end
    areaBlip, dropBlip = nil, nil
end

local function removeDrop() pcall(function() exports.veyl_interact:Remove(DROP_ZONE) end) end

local function deliver()
    if busy then return end
    busy = true
    local res = Veyl.CallbackTimeout('veyl_boosting', 'deliver', 10000)
    busy = false
    Veyl.NotifyResult(res)
end

local function apply(view)
    active = view
    clearBlips()
    removeDrop()
    nets = {}
    if not view then return end
    for _, v in ipairs(view.vehicles or {}) do if v.netId then nets[v.netId] = v.status end end

    if view.area and view.acquired == 0 then
        areaBlip = AddBlipForRadius(view.area.x + 0.0, view.area.y + 0.0, 0.0, (view.area.r or C.Blips.Area.radius) + 0.0)
        SetBlipColour(areaBlip, C.Blips.Area.colour)
        SetBlipAlpha(areaBlip, C.Blips.Area.alpha)
    end
    if view.drop then
        dropBlip = AddBlipForCoord(view.drop.x + 0.0, view.drop.y + 0.0, view.drop.z + 0.0)
        SetBlipSprite(dropBlip, C.Blips.Drop.sprite)
        SetBlipColour(dropBlip, C.Blips.Drop.colour)
        SetBlipRoute(dropBlip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(view.drop.label or C.Blips.Drop.label)
        EndTextCommandSetBlipName(dropBlip)
        exports.veyl_interact:AddZone({
            id = DROP_ZONE, coords = vector3(view.drop.x, view.drop.y, view.drop.z), radius = (view.drop.radius or 9.0) + 3.0, title = view.drop.label or 'Handoff',
            options = { { label = 'Hand over the vehicle', icon = 'car', onSelect = function() CreateThread(deliver) end } },
        })
    end
end

RegisterNetEvent('veyl_boosting:contract', function(view) apply(view) end)

-- Rejoin: ask the server whether a contract is waiting for this character.
CreateThread(function()
    while not Veyl.IsLoaded() do Wait(1000) end
    local res = Veyl.CallbackTimeout('veyl_boosting', 'sync', 10000)
    if res.ok then apply(res.data) end
end)

---------------------------------------------------------------------------
-- Options on the contract vehicles
---------------------------------------------------------------------------
local function trackerJob(entity)
    if busy then return end
    busy = true
    local netId = NetworkGetNetworkIdFromEntity(entity)
    local start = Veyl.CallbackTimeout('veyl_boosting', 'trackerStart', 10000, netId)
    if not start.ok then busy = false return Veyl.NotifyResult(start) end
    local done = vlib.progress({ label = 'Disabling the tracker', duration = start.data.seconds * 1000, canCancel = true,
        disable = { move = true, car = true, combat = true }, anim = { dict = 'anim@amb@clubhouse@tutorial@bkr_tut_ig3@', clip = 'machinic_loop_mechandplayer', flag = 1 } })
    ClearPedTasks(PlayerPedId())
    if not done then busy = false return Veyl.Notify('Stopped', 'info') end
    local res = Veyl.CallbackTimeout('veyl_boosting', 'trackerFinish', 10000, start.data.token)
    busy = false
    Veyl.NotifyResult(res)
end

CreateThread(function()
    while GetResourceState('veyl_target') ~= 'started' do Wait(250) end
    local function mine(entity) return nets[NetworkGetNetworkIdFromEntity(entity)] end
    exports.veyl_target:addGlobalVehicle({
        { name = 'veyl_boosting_access', label = 'Access the vehicle', icon = 'lock', distance = 2.5, priority = 3,
          canInteract = function(e) return mine(e) == 'waiting' and not busy and GetVehiclePedIsIn(PlayerPedId(), false) == 0 end,
          onSelect = function(d) CreateThread(function() BoostClient.startAccess(d.entity) end) end },
        { name = 'veyl_boosting_tracker', label = 'Disable tracker', icon = 'gear', distance = 2.5, priority = 2,
          canInteract = function(e) return mine(e) ~= nil and active and active.tracked == true and not busy end,
          onSelect = function(d) CreateThread(function() trackerJob(d.entity) end) end },
    })
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clearBlips()
    removeDrop()
    pcall(function() exports.veyl_target:removeGlobalVehicle({ 'veyl_boosting_access', 'veyl_boosting_tracker' }) end)
end)
