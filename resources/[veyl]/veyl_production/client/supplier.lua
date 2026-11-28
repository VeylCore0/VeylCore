-- Supplier runs on the client: the supplier peds, and while you have a run the pickup crate, the carrying animation and the drop. The
-- server holds the run; this draws what it says and asks it for each step.

local C = ProductionConfig
local S = C.Supplier
local run            -- the current run view from the server (or nil)
local pickupBlip, dropBlip, crate, carried
local loadedCrate    -- the crate on the truck bed (a networked object attached to the truck)
local busy = false
local DROP_ZONE = 'veyl_prod_run_drop'
local CRATE_OPTION = 'veyl_prod_run_pickup'

local function clear()
    if pickupBlip and DoesBlipExist(pickupBlip) then RemoveBlip(pickupBlip) end
    if dropBlip and DoesBlipExist(dropBlip) then RemoveBlip(dropBlip) end
    pickupBlip, dropBlip = nil, nil
    if crate then
        if GetResourceState('veyl_target') == 'started' then pcall(function() exports.veyl_target:removeLocalEntity(crate, { CRATE_OPTION }) end) end
        if DoesEntityExist(crate) then DeleteEntity(crate) end
        crate = nil
    end
    pcall(function() exports.veyl_interact:Remove(DROP_ZONE) end)
end

local function carry(on)
    local ped = PlayerPedId()
    if on and not carried then
        local hash = joaat(S.CrateModel)
        if not IsModelInCdimage(hash) then hash = joaat('prop_cs_cardbox_01') end
        RequestModel(hash)
        local deadline = GetGameTimer() + 3000
        while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(10) end
        carried = CreateObject(hash, 0.0, 0.0, 0.0, false, false, false)
        AttachEntityToEntity(carried, ped, GetPedBoneIndex(ped, 28422), 0.0, 0.0, -0.1, 0.0, 0.0, 0.0, true, true, false, true, 1, true)
        SetModelAsNoLongerNeeded(hash)
        if Veyl.LoadAnimDict('anim@heists@box_carry@') then TaskPlayAnim(ped, 'anim@heists@box_carry@', 'idle', 3.0, 3.0, -1, 49, 0, false, false, false) end
    elseif not on and carried then
        ClearPedTasks(ped)
        if DoesEntityExist(carried) then DeleteEntity(carried) end
        carried = nil
    end
end

local function step(name, label, ms)
    if busy then return end
    busy = true
    local done = vlib.progress({ label = label, duration = ms, canCancel = true, disable = { move = true, car = true, combat = true },
        anim = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 1 } })
    ClearPedTasks(PlayerPedId())
    if done then
        local res = Veyl.CallbackTimeout('veyl_production', name, 15000)
        Veyl.NotifyResult(res)
        if res.ok then TriggerEvent('veyl_production:runChanged', res.data and res.data.run or nil, name) end
    end
    busy = false
end

local truckHashes
local function isTruck(veh)
    if not truckHashes then
        truckHashes = {}
        for _, name in ipairs(S.Truck.Models) do truckHashes[joaat(name)] = true end
    end
    return truckHashes[GetEntityModel(veh)] == true
end

--- The closest allowed truck to a point, within the load radius.
local function truckNear(coords)
    local best, bestD
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        if isTruck(veh) then
            local d = #(GetEntityCoords(veh) - coords)
            if d <= S.Truck.LoadRadius and (not bestD or d < bestD) then best, bestD = veh, d end
        end
    end
    return best
end

local function bedOffset(veh, crateHash)
    local name = nil
    for _, n in ipairs(S.Truck.Models) do if joaat(n) == GetEntityModel(veh) then name = n break end end
    local o = name and S.Truck.Offsets[name]
    if o then return o.x, o.y, o.z end
    local mn, mx = GetModelDimensions(GetEntityModel(veh))
    local cmn = GetModelDimensions(crateHash)
    local z = mn.z + (mx.z - mn.z) * S.Truck.BedHeight - (cmn and cmn.z or -0.3)
    return 0.0, mn.y + S.Truck.BedFromRear, z
end

--- Puts the crate on a truck bed: a networked object attached to the truck, so everyone sees it ride along.
local function loadOntoTruck(entity)
    if busy then return end
    local veh = truckNear(GetEntityCoords(entity))
    if not veh then return Veyl.Notify('Back a pickup truck up to the crate first.', 'warning') end
    busy = true
    local done = vlib.progress({ label = 'Loading the crate', duration = 2500, canCancel = true, disable = { move = true, car = true, combat = true },
        anim = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 1 } })
    ClearPedTasks(PlayerPedId())
    if not done or not DoesEntityExist(veh) then busy = false return end
    local hash = joaat(S.CrateModel)
    if not IsModelInCdimage(hash) then hash = joaat('prop_cs_cardbox_01') end
    RequestModel(hash)
    local deadline = GetGameTimer() + 3000
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(10) end
    local vc = GetEntityCoords(veh)
    local obj = CreateObject(hash, vc.x, vc.y, vc.z + 3.0, true, true, false)
    SetModelAsNoLongerNeeded(hash)
    local ox, oy, oz = bedOffset(veh, hash)
    local bone = GetEntityBoneIndexByName(veh, 'chassis')
    AttachEntityToEntity(obj, veh, bone >= 0 and bone or 0, ox, oy, oz, 0.0, 0.0, 0.0, false, false, true, false, 2, true)
    local res = Veyl.CallbackTimeout('veyl_production', 'runPickup', 15000, NetworkGetNetworkIdFromEntity(veh), NetworkGetNetworkIdFromEntity(obj))
    busy = false
    Veyl.NotifyResult(res)
    if res.ok then
        loadedCrate = obj
        TriggerEvent('veyl_production:runChanged', res.data and res.data.run or nil, 'runPickup')
    else
        DeleteEntity(obj)
    end
end

local function apply(view)
    run = view
    clear()
    if not view then carry(false) return end
    if view.state == 'active' then
        carry(false)
        local p = view.pickup
        pickupBlip = AddBlipForCoord(p.x, p.y, p.z)
        SetBlipSprite(pickupBlip, 478) SetBlipColour(pickupBlip, 5) SetBlipRoute(pickupBlip, true)
        BeginTextCommandSetBlipName('STRING') AddTextComponentSubstringPlayerName('Supply crate') EndTextCommandSetBlipName(pickupBlip)
        local hash = joaat(S.CrateModel)
        if not IsModelInCdimage(hash) then hash = joaat('prop_cs_cardbox_01') end
        RequestModel(hash)
        local deadline = GetGameTimer() + 3000
        while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(10) end
        if HasModelLoaded(hash) then
            -- The crate only exists on your screen; it is created once you are near it (see the loop below).
            run.crateHash = hash
        end
    elseif view.state == 'picked' and view.drop then
        carry(not S.Truck.Required)
        local d = view.drop
        dropBlip = AddBlipForCoord(d.x, d.y, d.z)
        SetBlipSprite(dropBlip, 478) SetBlipColour(dropBlip, 2) SetBlipRoute(dropBlip, true)
        BeginTextCommandSetBlipName('STRING') AddTextComponentSubstringPlayerName(d.label or 'Drop') EndTextCommandSetBlipName(dropBlip)
        exports.veyl_interact:AddZone({
            id = DROP_ZONE, coords = vector3(d.x, d.y, d.z), radius = S.DropRadius, title = d.label or 'Drop',
            options = { { label = S.Truck.Required and 'Unload the crate' or 'Hand over the crate', icon = 'box', onSelect = function() CreateThread(function() step('runDeliver', 'Unloading', 1800) end) end } },
        })
    end
end

AddEventHandler('veyl_production:runChanged', function(view, which)
    if which == 'runDeliver' then
        if loadedCrate and DoesEntityExist(loadedCrate) then DeleteEntity(loadedCrate) end
        loadedCrate = nil
        apply(nil)
    else apply(view) end
end)

-- The crate is created when you get close to its pickup point and removed when you leave.
CreateThread(function()
    while true do
        Wait(1500)
        if run and run.state == 'active' then
            local p = run.pickup
            local d = #(GetEntityCoords(PlayerPedId()) - vector3(p.x, p.y, p.z))
            if d < 70.0 and not crate and run.crateHash then
                crate = CreateObject(run.crateHash, p.x, p.y, p.z, false, false, false)
                PlaceObjectOnGroundProperly(crate)
                FreezeEntityPosition(crate, true)
                if GetResourceState('veyl_target') == 'started' then
                    exports.veyl_target:addLocalEntity(crate, { { name = CRATE_OPTION, label = S.Truck.Required and 'Load the crate onto a truck' or 'Take the crate', icon = 'box', distance = 3.5,
                        onSelect = function() CreateThread(function() if S.Truck.Required then loadOntoTruck(crate) else step('runPickup', 'Loading the crate', 2000) end end) end } })
                end
            elseif d >= 90.0 and crate then
                if GetResourceState('veyl_target') == 'started' then pcall(function() exports.veyl_target:removeLocalEntity(crate, { CRATE_OPTION }) end) end
                if DoesEntityExist(crate) then DeleteEntity(crate) end
                crate = nil
            end
        end
    end
end)

-- Where the supplier is: the ped gives you a run, or ends the one you have.
local function askFor(s)
    if busy then return end
    busy = true
    local res = Veyl.CallbackTimeout('veyl_production', 'runStart', 15000, s.id)
    busy = false
    Veyl.NotifyResult(res)
    if res.ok then apply(res.data.run) end
end

local peds = {}
CreateThread(function()
    while GetResourceState('veyl_interact') ~= 'started' do Wait(500) end
    Wait(800)
    if not (C.Branches.supplier and C.Branches.supplier.enabled) then return end
    for _, s in ipairs(S.Suppliers) do
        local id = 'veyl_prod_supplier_' .. s.id
        exports.veyl_interact:AddPed({ id = id, model = s.Ped.model, coords = s.Ped.coords, scenario = s.Ped.scenario, radius = s.Ped.radius, title = s.Ped.label,
            options = {
                { label = ('Take a run ($%d)'):format(s.fee), icon = 'box', onSelect = function() CreateThread(function() askFor(s) end) end },
                { label = 'Drop my current run', icon = 'x', onSelect = function() CreateThread(function()
                    if vlib.alertDialog({ title = 'Drop this run?', message = 'The fee is not refunded and you wait before the next one.', confirmLabel = 'Drop it' }) ~= 'confirm' then return end
                    local r = Veyl.CallbackTimeout('veyl_production', 'runCancel', 15000)
                    Veyl.NotifyResult(r)
                    if r.ok then
                        if loadedCrate and DoesEntityExist(loadedCrate) then DeleteEntity(loadedCrate) end
                        loadedCrate = nil
                        apply(nil)
                    end
                end) end },
            } })
        peds[#peds + 1] = id
    end
    -- A run in progress survives a reconnect: the server remembers it.
    while not Veyl.IsLoaded() do Wait(1000) end
    local cur = Veyl.CallbackTimeout('veyl_production', 'runCurrent', 15000)
    if cur.ok and cur.data then apply(cur.data) end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    clear()
    carry(false)
    for _, id in ipairs(peds) do pcall(function() exports.veyl_interact:Remove(id) end) end
end)
