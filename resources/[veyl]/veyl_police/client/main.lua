-- veyl_police client: officer options on players and vehicles, the cuffed / escorted state, duty points, citations.

local C = PoliceConfig

local function isOfficer()
    local job = (Veyl.PlayerData or {}).job
    if not job or not job.onduty then return false end
    for _, j in ipairs(C.Jobs) do if job.name == j then return true end end
    return false
end

local function loadDict(dict)
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    local t = GetGameTimer() + 2000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < t do Wait(10) end
    return HasAnimDictLoaded(dict)
end

local function serverIdOf(entity)
    local idx = NetworkGetPlayerIndexFromPed(entity)
    return idx ~= -1 and GetPlayerServerId(idx) or nil
end

local function stateOf(entity)
    local id = serverIdOf(entity)
    return id and Player(id).state or nil
end

---------------------------------------------------------------------------
-- Officer actions
---------------------------------------------------------------------------
local function cuff(entity)
    local id = serverIdOf(entity)
    if not id then return end
    local res = Veyl.Callback('veyl_police', 'cuff', id)
    if not res.ok then return Veyl.NotifyResult(res) end
    if loadDict('mp_arrest_paired') then
        TaskPlayAnim(PlayerPedId(), 'mp_arrest_paired', 'cop_p2_back_right', 8.0, -8.0, 3500, 48, 0, false, false, false)
    end
    Veyl.Notify(res.message, 'success')
end

local function simple(name, entity)
    local id = serverIdOf(entity)
    if id then Veyl.NotifyResult(Veyl.Callback('veyl_police', name, id)) end
end

local function search(entity)
    local id = serverIdOf(entity)
    if not id then return end
    local res = Veyl.Callback('veyl_police', 'search', id)
    if not res.ok then return Veyl.NotifyResult(res) end
    exports.veyl_inventory:openInventory('stash', res.data.stash)
end

local function cite(entity)
    local id = serverIdOf(entity)
    if not id then return end
    local values = vlib.inputDialog('Write a citation', {
        { name = 'amount', label = 'Amount ($)', type = 'number', required = true, min = 1, max = C.Citations.Max },
        { name = 'reason', label = 'Reason', type = 'text', required = true, maxLength = 160, placeholder = 'e.g. Speeding 90 in a 50' },
    }, { submitLabel = 'Issue citation' })
    if not values then return end
    Veyl.NotifyResult(Veyl.CallbackTimeout('veyl_police', 'cite', 15000, id, math.floor(tonumber(values.amount) or 0), values.reason))
end

local function impound(entity)
    local start = Veyl.CallbackTimeout('veyl_police', 'impoundStart', 10000, NetworkGetNetworkIdFromEntity(entity))
    if not start.ok then return Veyl.NotifyResult(start) end
    TaskStartScenarioInPlace(PlayerPedId(), 'CODE_HUMAN_MEDIC_TIME_OF_DEATH', 0, true)
    local done = vlib.progress({ label = 'Calling a tow truck', duration = start.data.seconds * 1000, canCancel = true,
        disable = { move = true, car = true, combat = true } })
    ClearPedTasks(PlayerPedId())
    if not done then return Veyl.Notify('Stopped', 'info') end
    Veyl.NotifyResult(Veyl.CallbackTimeout('veyl_police', 'impoundFinish', 10000, start.data.token))
end

CreateThread(function()
    while GetResourceState('veyl_target') ~= 'started' do Wait(250) end
    local function officerOnPlayer(fn) return function(entity) return isOfficer() and stateOf(entity) ~= nil and fn(stateOf(entity)) end end
    exports.veyl_target:addGlobalPlayer({
        { name = 'veyl_police_cuff', label = 'Cuff', icon = 'lock', distance = C.ActionDistance, priority = 6,
          canInteract = officerOnPlayer(function(st) return not st.cuffed end), onSelect = function(d) CreateThread(function() cuff(d.entity) end) end },
        { name = 'veyl_police_uncuff', label = 'Uncuff', icon = 'unlock', distance = C.ActionDistance, priority = 6,
          canInteract = officerOnPlayer(function(st) return st.cuffed == true end), onSelect = function(d) CreateThread(function() simple('uncuff', d.entity) end) end },
        { name = 'veyl_police_escort', label = 'Escort / let go', icon = 'hand', distance = C.ActionDistance, priority = 5,
          canInteract = officerOnPlayer(function(st) return st.cuffed == true or st.medical ~= nil end), onSelect = function(d) CreateThread(function() simple('escort', d.entity) end) end },
        { name = 'veyl_police_search', label = 'Search', icon = 'inspect', distance = C.ActionDistance, priority = 4,
          canInteract = officerOnPlayer(function(st) return C.SearchRequires == 'any' or st.cuffed == true or st.medical ~= nil end),
          onSelect = function(d) CreateThread(function() search(d.entity) end) end },
        { name = 'veyl_police_cite', label = 'Write citation', icon = 'receipt', distance = C.ActionDistance, priority = 3,
          canInteract = officerOnPlayer(function() return true end), onSelect = function(d) CreateThread(function() cite(d.entity) end) end },
    })
    exports.veyl_target:addGlobalVehicle({
        { name = 'veyl_police_putin', label = 'Place in vehicle', icon = 'car', distance = 3.0, priority = 6,
          canInteract = function() return isOfficer() end,
          onSelect = function(d) CreateThread(function() Veyl.NotifyResult(Veyl.Callback('veyl_police', 'putInVehicle', NetworkGetNetworkIdFromEntity(d.entity))) end) end },
        { name = 'veyl_police_takeout', label = 'Take out of vehicle', icon = 'car', distance = 3.0, priority = 6,
          canInteract = function() return isOfficer() end,
          onSelect = function(d) CreateThread(function() Veyl.NotifyResult(Veyl.Callback('veyl_police', 'takeOut', NetworkGetNetworkIdFromEntity(d.entity))) end) end },
        { name = 'veyl_police_impound', label = 'Impound', icon = 'garage', distance = 3.0, priority = 1,
          canInteract = function() return isOfficer() end, onSelect = function(d) CreateThread(function() impound(d.entity) end) end },
    })
end)

---------------------------------------------------------------------------
-- Being cuffed / escorted
---------------------------------------------------------------------------
RegisterNetEvent('veyl_police:cuffAnim', function(officer, seconds)
    local ped = PlayerPedId()
    local opid = GetPlayerFromServerId(officer)
    if opid ~= -1 then
        local oped = GetPlayerPed(opid)
        -- Stand in front of the officer, facing away, for the paired animation.
        local oc = GetOffsetFromEntityInWorldCoords(oped, 0.0, 0.65, 0.0)
        SetEntityCoordsNoOffset(ped, oc.x, oc.y, oc.z - 1.0, false, false, false)
        SetEntityHeading(ped, GetEntityHeading(oped))
    end
    if loadDict('mp_arrest_paired') then
        TaskPlayAnim(ped, 'mp_arrest_paired', 'crook_p2_back_right', 8.0, -8.0, math.floor((seconds or 3.5) * 1000), 33, 0, false, false, false)
    end
end)

RegisterNetEvent('veyl_police:enterVehicle', function(netId)
    local veh = NetworkGetEntityFromNetworkId(netId)
    if not DoesEntityExist(veh) then return end
    local ped = PlayerPedId()
    DetachEntity(ped, true, false)
    for _, seat in ipairs({ 1, 2, 0 }) do
        if IsVehicleSeatFree(veh, seat) then TaskWarpPedIntoVehicle(ped, veh, seat) return end
    end
    Veyl.Notify('There was no free seat.', 'error')
end)

RegisterNetEvent('veyl_police:leaveVehicle', function()
    local ped = PlayerPedId()
    local veh = GetVehiclePedIsIn(ped, false)
    if veh ~= 0 then TaskLeaveVehicle(ped, veh, 16) end
end)

-- Restraint loop: hands behind the back, most controls blocked; escorted = attached to the officer.
CreateThread(function()
    local attachedTo = nil
    while true do
        local st = LocalPlayer.state
        local cuffed, escortedBy = st.cuffed == true, st.escortedBy
        if not cuffed and not escortedBy then
            if attachedTo then DetachEntity(PlayerPedId(), true, false) attachedTo = nil end
            SetEnableHandcuffs(PlayerPedId(), false)
            Wait(250)
        else
            local ped = PlayerPedId()
            if cuffed then
                SetEnableHandcuffs(ped, true)
                SetCurrentPedWeapon(ped, `WEAPON_UNARMED`, true)
                if not IsPedInAnyVehicle(ped, false) and not st.medical and not IsEntityPlayingAnim(ped, 'mp_arresting', 'idle', 3)
                    and not IsEntityPlayingAnim(ped, 'mp_arrest_paired', 'crook_p2_back_right', 3) and loadDict('mp_arresting') then
                    TaskPlayAnim(ped, 'mp_arresting', 'idle', 8.0, -8.0, -1, 49, 0, false, false, false)
                end
                for _, k in ipairs({ 21, 22, 23, 24, 25, 37, 44, 45, 47, 58, 140, 141, 142, 143, 257, 263, 264, 75, 288, 289, 170, 167 }) do
                    DisableControlAction(0, k, true)
                end
                DisablePlayerFiring(PlayerId(), true)
            end
            if escortedBy and attachedTo ~= escortedBy then
                local opid = GetPlayerFromServerId(escortedBy)
                if opid ~= -1 then
                    AttachEntityToEntity(ped, GetPlayerPed(opid), 11816, 0.45, 0.45, 0.0, 0.0, 0.0, 0.0, false, false, false, false, 2, true)
                    attachedTo = escortedBy
                end
            elseif not escortedBy and attachedTo then
                DetachEntity(ped, true, false)
                attachedTo = nil
            end
            Wait(0)
        end
    end
end)

AddStateBagChangeHandler('cuffed', ('player:%d'):format(GetPlayerServerId(PlayerId())), function(_, _, value)
    if not value then
        local ped = PlayerPedId()
        if IsEntityPlayingAnim(ped, 'mp_arresting', 'idle', 3) then ClearPedTasks(ped) end
    end
end)

---------------------------------------------------------------------------
-- Duty points
---------------------------------------------------------------------------
CreateThread(function()
    while GetResourceState('veyl_interact') ~= 'started' do Wait(250) end
    for i, s in ipairs(C.Stations) do
        exports.veyl_interact:AddZone({
            id = ('veyl_police_duty_%d'):format(i), coords = s.duty, radius = 1.5, title = s.label,
            options = { { label = 'Go on / off duty', icon = 'shield', event = 'veyl_police:duty', groups = C.Jobs } },
        })
    end
end)
AddEventHandler('veyl_police:duty', function() ExecuteCommand('duty') end)

---------------------------------------------------------------------------
-- /citations: pay your own unpaid citations
---------------------------------------------------------------------------
RegisterCommand('citations', function()
    CreateThread(function()
        local res = Veyl.Callback('veyl_police', 'myCitations')
        if not res.ok then return Veyl.NotifyResult(res) end
        if #res.data == 0 then return Veyl.Notify('You have no unpaid citations.', 'success') end
        local items = {}
        for i, c in ipairs(res.data) do
            items[i] = { label = ('#%d · $%d'):format(c.id, c.amount), description = ('%s (%s)'):format(c.reason, c.officer_name), value = c.id }
        end
        local id = Veyl.UI.Menu({ title = 'Unpaid citations', subtitle = 'Choose one to pay', items = items })
        if not id then return end
        local method = Veyl.UI.Menu({ title = 'Pay with', items = { { label = 'Bank', value = 'bank' }, { label = 'Cash', value = 'cash' } } })
        if method then Veyl.NotifyResult(Veyl.Callback('veyl_police', 'payCitation', id, method)) end
    end)
end, false)
