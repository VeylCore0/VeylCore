-- veyl_doorlocks client: registers doors with the game's door system, keeps lock state in sync, shows interactions,
-- runs breaching actions, the manager panel and the in-game editor (/doorlock).

local doors = {}        -- [id] = public door
local zones = {}        -- [id] = interact zone id
local screen = vlib.createScreen({ name = 'doorlocks', onClose = function() end })
local C = DoorConfig

local function entityHash(id, i) return joaat(('veyl_door_%d_%d'):format(id, i)) end

local function applyState(d)
    for i, e in ipairs(d.entities) do
        local h = entityHash(d.id, i)
        if not IsDoorRegisteredWithSystem(h) then AddDoorToSystem(h, e.model, e.x, e.y, e.z, false, false, false) end
        DoorSystemSetDoorState(h, d.locked and 1 or 0, false, true)
    end
end

local function center(d)
    local sx, sy, sz = 0.0, 0.0, 0.0
    for _, e in ipairs(d.entities) do sx, sy, sz = sx + e.x, sy + e.y, sz + e.z end
    local n = #d.entities
    return vector3(sx / n, sy / n, sz / n)
end

local function count(item) return exports.veyl_inventory:GetItemCount(item) or 0 end
local function myJobs()
    local pd = Veyl.GetPlayerData and Veyl.GetPlayerData() or nil
    local set = {}
    if pd and pd.jobs then for name in pairs(pd.jobs) do set[name] = true end end
    if pd and pd.job then set[pd.job.name] = true end
    return set
end

local canEdit = false
local function refreshEditRight() local r = Veyl.Callback('veyl_doorlocks', 'canEdit') canEdit = r.ok and r.data == true end

local function removeDoor(id)
    local d = doors[id]
    if not d then return end
    for i in ipairs(d.entities) do
        local h = entityHash(id, i)
        if IsDoorRegisteredWithSystem(h) then DoorSystemSetDoorState(h, 0, false, true) RemoveDoorFromSystem(h) end
    end
    if zones[id] then exports.veyl_interact:Remove(zones[id]) zones[id] = nil end
    doors[id] = nil
end

local function addZone(d)
    if d.hidePrompt then return end
    local id = d.id
    zones[id] = exports.veyl_interact:AddZone({
        id = 'veyl_door_' .. id, coords = center(d), radius = d.distance, title = d.name,
        options = {
            { label = 'Unlock', icon = 'unlock', event = 'veyl_doorlocks:use', args = { id = id, locked = false },
              canInteract = function() return doors[id] and doors[id].locked end },
            { label = 'Lock', icon = 'lock', event = 'veyl_doorlocks:use', args = { id = id, locked = true },
              canInteract = function() return doors[id] and not doors[id].locked end },
            { label = 'Pick the lock', icon = 'hand', event = 'veyl_doorlocks:breach', args = { id = id, method = 'lockpick' },
              canInteract = function() return doors[id] and doors[id].locked and doors[id].lockpick and count(C.Items.lockpick) > 0 end },
            { label = 'Breach with ram', icon = 'shield', event = 'veyl_doorlocks:breach', args = { id = id, method = 'ram' },
              canInteract = function() return doors[id] and doors[id].locked and doors[id].ram and count(C.Items.ram) > 0 end },
            { label = 'Manage access', icon = 'key', event = 'veyl_doorlocks:manage', args = { id = id },
              canInteract = function()
                  local d2 = doors[id]
                  if not d2 then return false end
                  if canEdit then return true end
                  local mine = myJobs()
                  for _, j in ipairs(d2.managerJobs or {}) do if mine[j] then return true end end
                  return false
              end },
        },
    })
end

local function upsert(d)
    removeDoor(d.id)
    doors[d.id] = d
    applyState(d)
    addZone(d)
end

local function loadAll(list)
    for id in pairs(doors) do removeDoor(id) end
    for _, d in ipairs(list or {}) do upsert(d) end
end

RegisterNetEvent('veyl_doorlocks:all', loadAll)
RegisterNetEvent('veyl_doorlocks:upsert', upsert)
RegisterNetEvent('veyl_doorlocks:removed', removeDoor)
RegisterNetEvent('veyl_doorlocks:state', function(id, locked, businessOpen)
    local d = doors[id]
    if not d then return end
    d.locked, d.businessOpen = locked, businessOpen
    applyState(d)
end)

CreateThread(function()
    while GetResourceState('veyl_interact') ~= 'started' do Wait(250) end
    local res = Veyl.Callback('veyl_doorlocks', 'all')
    if res.ok then loadAll(res.data) end
    refreshEditRight()
end)
RegisterNetEvent('VeylCore:Client:OnPlayerLoaded', function() CreateThread(refreshEditRight) end)

---------------------------------------------------------------------------
-- Status hint near doors (passive; never takes focus)
---------------------------------------------------------------------------
CreateThread(function()
    local shown = nil
    while true do
        local sleep = 500
        local pos = GetEntityCoords(PlayerPedId())
        local best, bestDist = nil, 99.0
        for _, d in pairs(doors) do
            if not d.hidePrompt then
                local dist = #(pos - center(d))
                if dist <= d.distance and dist < bestDist then best, bestDist = d, dist end
            end
        end
        local state = best and { visible = true, name = best.name, locked = best.locked, open = best.businessOpen } or nil
        local key = state and (best.id .. tostring(best.locked) .. tostring(best.businessOpen)) or nil
        if key ~= shown then
            SendNUIMessage({ action = 'door:status', data = state or { visible = false } })
            shown = key
        end
        if best then sleep = 200 end
        Wait(sleep)
    end
end)

---------------------------------------------------------------------------
-- Using doors
---------------------------------------------------------------------------
local function playAnim(dict, clip, ms)
    RequestAnimDict(dict)
    local t = GetGameTimer() + 1500
    while not HasAnimDictLoaded(dict) and GetGameTimer() < t do Wait(10) end
    if HasAnimDictLoaded(dict) then TaskPlayAnim(PlayerPedId(), dict, clip, 8.0, -8.0, ms or 1200, 48, 0, false, false, false) end
end

AddEventHandler('veyl_doorlocks:use', function(args)
    if type(args) ~= 'table' then return end
    CreateThread(function()
        playAnim('anim@heists@keycard@', 'exit', 900)
        local res = Veyl.CallbackTimeout('veyl_doorlocks', 'toggle', 10000, args.id, args.locked)
        if not res.ok then Veyl.NotifyResult(res) end
        PlaySoundFrontend(-1, res.ok and 'Door_Open' or 'ERROR', res.ok and 'Lowrider_Super_Mod_Garage_Sounds' or 'HUD_AMMO_SHOP_SOUNDSET', true)
    end)
end)

AddEventHandler('veyl_doorlocks:breach', function(args)
    if type(args) ~= 'table' then return end
    CreateThread(function()
        local start = Veyl.CallbackTimeout('veyl_doorlocks', 'breachStart', 10000, args.id, args.method)
        if not start.ok then return Veyl.NotifyResult(start) end
        local ram = args.method == 'ram'
        if ram then TaskStartScenarioInPlace(PlayerPedId(), 'WORLD_HUMAN_HAMMERING', 0, true) end
        local done = vlib.progress({ label = ram and 'Breaching the door' or 'Picking the lock', duration = start.data.seconds * 1000, canCancel = true,
            disable = { move = true, car = true, combat = true },
            anim = (not ram) and { dict = 'mp_arresting', clip = 'a_uncuff', flag = 49 } or nil })
        ClearPedTasks(PlayerPedId())
        if not done then return Veyl.Notify('Stopped', 'info') end
        Veyl.NotifyResult(Veyl.CallbackTimeout('veyl_doorlocks', 'breachFinish', 10000, start.data.token))
    end)
end)

---------------------------------------------------------------------------
-- NUI
---------------------------------------------------------------------------
local function reply(cb, res) cb({ ok = res.ok, code = res.code, message = res.message, data = res.data }) end
local ALLOWED = { manage = true, businessOpen = true, grant = true, revoke = true, makeKey = true, changeLocks = true,
    adminData = true, adminSave = true, adminDelete = true, adminToggle = true, adminLog = true, adminLookup = true }

RegisterNUICallback('api', function(data, cb)
    if type(data) ~= 'table' or not ALLOWED[data.name] then return cb({ ok = false, code = 'INVALID_INPUT' }) end
    local args = type(data.args) == 'table' and data.args or {}
    CreateThread(function() reply(cb, Veyl.CallbackTimeout('veyl_doorlocks', data.name, 15000, table.unpack(args, 1, 4))) end)
end)

AddEventHandler('veyl_doorlocks:manage', function(args)
    CreateThread(function()
        local res = Veyl.Callback('veyl_doorlocks', 'manage', args and args.id)
        if not res.ok then return Veyl.NotifyResult(res) end
        screen:open('door:open', { view = 'manage', data = res.data })
    end)
end)

---------------------------------------------------------------------------
-- Editor: /doorlock opens the list; "New door" / "Re-pick" enters aim mode to capture door entities
---------------------------------------------------------------------------
local function openEditor(focus)
    local res = Veyl.Callback('veyl_doorlocks', 'adminData')
    if not res.ok then return Veyl.NotifyResult(res) end
    local p = GetEntityCoords(PlayerPedId())
    res.data.player = { x = p.x, y = p.y, z = p.z }
    res.data.focus = focus
    if screen:isOpen() then screen:send('door:open', { view = 'editor', data = res.data })
    else screen:open('door:open', { view = 'editor', data = res.data }) end
end

RegisterCommand(C.Command, function()
    CreateThread(function()
        refreshEditRight()
        if not canEdit then return Veyl.Notify('You do not have permission to edit doors.', 'error') end
        openEditor()
    end)
end, false)

local function rotationToDirection(rot)
    local z, x = math.rad(rot.z), math.rad(rot.x)
    local c = math.abs(math.cos(x))
    return vector3(-math.sin(z) * c, math.cos(z) * c, math.sin(x))
end

local function aimedEntity()
    local cam, rot = GetGameplayCamCoord(), GetGameplayCamRot(2)
    local to = cam + rotationToDirection(rot) * 15.0
    local ray = StartExpensiveSynchronousShapeTestLosProbe(cam.x, cam.y, cam.z, to.x, to.y, to.z, 16, PlayerPedId(), 4)
    local _, hit, _, _, ent = GetShapeTestResult(ray)
    if hit == 1 and ent and ent ~= 0 and DoesEntityExist(ent) and GetEntityType(ent) == 3 then return ent end
    return nil
end

local selecting = false
--- Aim at doors: E adds/removes the one you look at, Enter finishes, Backspace cancels. Returns the captured list.
local function selectDoors(initial)
    selecting = true
    local picked = {}
    for _, e in ipairs(initial or {}) do picked[#picked + 1] = e end
    local outlined = {}
    local function sameAs(a, b) return a.model == b.model and #(vector3(a.x, a.y, a.z) - vector3(b.x, b.y, b.z)) < 0.05 end
    local result = nil
    while selecting do
        Wait(0)
        for _, c in ipairs({ 24, 25, 38, 44, 47, 140, 141, 142, 177, 191, 199, 200, 201, 322 }) do DisableControlAction(0, c, true) end
        local ent = aimedEntity()
        local info = nil
        if ent then
            local p = GetEntityCoords(ent)
            info = { model = GetEntityModel(ent), x = p.x, y = p.y, z = p.z, heading = GetEntityHeading(ent) }
            SetEntityDrawOutline(ent, true)
            SetEntityDrawOutlineColor(184, 146, 244, 255)
            outlined[ent] = GetGameTimer()
        end
        for e, t in pairs(outlined) do
            if e ~= ent and DoesEntityExist(e) then SetEntityDrawOutline(e, false) outlined[e] = nil end
        end
        -- Markers on already captured doors.
        for _, p in ipairs(picked) do DrawMarker(0, p.x, p.y, p.z + 1.3, 0, 0, 0, 0, 0, 0, 0.25, 0.25, 0.25, 152, 211, 174, 200, true, true, 2, false, nil, nil, false) end
        local already = false
        if info then for _, p in ipairs(picked) do if sameAs(p, info) then already = true end end end
        local known = info and DoorSystemFindExistingDoor(info.x, info.y, info.z, info.model) or false
        SendNUIMessage({ action = 'door:select', data = { visible = true, count = #picked, max = C.MaxEntities, aiming = info ~= nil, already = already,
            isDoor = known and true or false } })
        if IsDisabledControlJustPressed(0, 38) and info then
            if already then
                for i = #picked, 1, -1 do if sameAs(picked[i], info) then table.remove(picked, i) end end
            elseif #picked < C.MaxEntities then
                picked[#picked + 1] = info
                PlaySoundFrontend(-1, 'SELECT', 'HUD_FRONTEND_DEFAULT_SOUNDSET', true)
            else
                Veyl.Notify(('Up to %d doors per entry'):format(C.MaxEntities), 'error')
            end
        elseif IsDisabledControlJustPressed(0, 191) or IsDisabledControlJustPressed(0, 201) then
            if #picked == 0 then Veyl.Notify('Aim at a door and press E first', 'error') else result = picked selecting = false end
        elseif IsDisabledControlJustPressed(0, 177) or IsDisabledControlJustPressed(0, 200) or IsDisabledControlJustPressed(0, 322) then
            selecting = false
        end
    end
    for e in pairs(outlined) do if DoesEntityExist(e) then SetEntityDrawOutline(e, false) end end
    SendNUIMessage({ action = 'door:select', data = { visible = false } })
    local untilAt = GetGameTimer() + 700
    CreateThread(function() while GetGameTimer() < untilAt do DisableControlAction(0, 199, true) DisableControlAction(0, 200, true) DisableControlAction(0, 322, true) Wait(0) end end)
    return result
end

--- From the editor: pick doors, then reopen the editor with the form filled.
RegisterNUICallback('pickDoors', function(data, cb)
    cb({ ok = true })
    local draft = data and data.draft or {}
    screen:close('picking')
    CreateThread(function()
        Wait(250)
        local picked = selectDoors(draft.entities)
        if picked then draft.entities = picked end
        openEditor({ draft = draft, cancelled = picked == nil })
    end)
end)

RegisterNUICallback('teleport', function(data, cb)
    cb({ ok = true })
    if not canEdit then return end
    local x, y, z = tonumber(data and data.x), tonumber(data and data.y), tonumber(data and data.z)
    if not (x and y and z) then return end
    screen:close('teleport')
    CreateThread(function()
        DoScreenFadeOut(250) Wait(300)
        RequestCollisionAtCoord(x, y, z)
        SetEntityCoordsNoOffset(PlayerPedId(), x + 1.2, y, z, false, false, false)
        local t = GetGameTimer() + 4000
        while not HasCollisionLoadedAroundEntity(PlayerPedId()) and GetGameTimer() < t do Wait(25) end
        DoScreenFadeIn(300)
    end)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    selecting = false
    for id in pairs(doors) do removeDoor(id) end
end)
