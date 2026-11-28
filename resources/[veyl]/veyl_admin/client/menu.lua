-- veyl_admin menu client: the screen, the self tools (noclip, god mode, invisibility, names, vehicles) and the actions the server sends to
-- a player (freeze, heal, kill, spectate). The page can only call names in ALLOWED; the server checks the permission on every one of them.

local C = AdminConfig
local screen = vlib.createScreen({ name = 'admin' })
local self_ = { noclip = false, god = false, invisible = false, names = false, speed = 3, spectating = false }

local function reply(cb, res) cb({ ok = res.ok, code = res.code, message = res.message, data = res.data }) end

local function selfState()
    return { noclip = self_.noclip, god = self_.god, invisible = self_.invisible, names = self_.names, spectating = self_.spectating, speed = self_.speed }
end

local function open()
    if screen:isOpen() then return end
    local res = Veyl.CallbackTimeout('veyl_admin', 'overview', 10000)
    if not res.ok then return Veyl.NotifyResult(res) end
    local ok, reason = screen:open('admin:open', { overview = res.data, self = selfState(), vehicles = C.QuickVehicles, speeds = C.NoclipSpeeds })
    if not ok then Veyl.Notify(reason == 'busy' and 'Close the open menu first.' or 'Not available right now.', 'warning') end
end

RegisterNetEvent('veyl_admin:open', function() CreateThread(open) end)
if C.Key and C.Key ~= '' then RegisterKeyMapping(C.Command, 'Open the staff menu', 'keyboard', C.Key) end

---------------------------------------------------------------------------
-- Page -> server
---------------------------------------------------------------------------
local ALLOWED = {
    overview = true, players = true, playerInfo = true, action = true, reports = true, closeReport = true, logs = true, bans = true, unban = true,
    announce = true, world = true, resources = true, resource = true, itemList = true,
}

RegisterNUICallback('api', function(data, cb)
    if not screen:isOpen() or type(data) ~= 'table' or not ALLOWED[data.name] then return cb({ ok = false, code = 'INVALID_INPUT' }) end
    local args = type(data.args) == 'table' and data.args or {}
    CreateThread(function()
        local res = Veyl.CallbackTimeout('veyl_admin', data.name, 15000, table.unpack(args, 1, 3))
        reply(cb, res)
        -- Teleporting to someone, or watching them, is for the world, not the menu.
        if res.ok and data.name == 'action' and (args[1] == 'spectate') then screen:close('spectate') end
    end)
end)

---------------------------------------------------------------------------
-- Self tools
---------------------------------------------------------------------------
local function allow(what, detail)
    local r = Veyl.CallbackTimeout('veyl_admin', 'allow', 8000, what, detail)
    return r.ok
end

local function ground(x, y)
    for z = 1000.0, 0.0, -25.0 do
        RequestCollisionAtCoord(x, y, z)
        local found, gz = GetGroundZFor_3dCoord(x, y, z, false)
        if found then return gz end
        Wait(10)
    end
    return nil
end

local function applyInvisible()
    local ped = PlayerPedId()
    SetEntityVisible(ped, not self_.invisible, false)
    SetEntityAlpha(ped, self_.invisible and 80 or 255, false)
    if not self_.invisible then ResetEntityAlpha(ped) end
end

local function applyGod()
    SetPlayerInvincible(PlayerId(), self_.god)
    SetEntityInvincible(PlayerPedId(), self_.god)
end

local function startNoclip()
    CreateThread(function()
        local ped = PlayerPedId()
        local ent = IsPedInAnyVehicle(ped, false) and GetVehiclePedIsIn(ped, false) or ped
        FreezeEntityPosition(ent, true)
        SetEntityCollision(ent, false, false)
        SetEntityVisible(ent, false, false)
        while self_.noclip do
            Wait(0)
            DisableControlAction(0, 32, true) DisableControlAction(0, 33, true) DisableControlAction(0, 34, true) DisableControlAction(0, 35, true)
            DisableControlAction(0, 44, true) DisableControlAction(0, 38, true) DisableControlAction(0, 21, true) DisableControlAction(0, 36, true)
            local speed = C.NoclipSpeeds[self_.speed] or 1.0
            if IsDisabledControlPressed(0, 21) then speed = speed * 3.0 elseif IsDisabledControlPressed(0, 36) then speed = speed * 0.3 end
            local rot = GetGameplayCamRot(2)
            local pitch, yaw = math.rad(rot.x), math.rad(rot.z)
            local fwd = vector3(-math.sin(yaw) * math.cos(pitch), math.cos(yaw) * math.cos(pitch), math.sin(pitch))
            local right = vector3(math.cos(yaw), math.sin(yaw), 0.0)
            local pos = GetEntityCoords(ent)
            local move = vector3(0.0, 0.0, 0.0)
            if IsDisabledControlPressed(0, 32) then move = move + fwd end
            if IsDisabledControlPressed(0, 33) then move = move - fwd end
            if IsDisabledControlPressed(0, 34) then move = move - right end
            if IsDisabledControlPressed(0, 35) then move = move + right end
            if IsDisabledControlPressed(0, 44) then move = move + vector3(0.0, 0.0, 1.0) end
            if IsDisabledControlPressed(0, 38) then move = move - vector3(0.0, 0.0, 1.0) end
            pos = pos + move * (speed * 0.5)
            SetEntityCoordsNoOffset(ent, pos.x, pos.y, pos.z, true, true, true)
            SetEntityHeading(ent, GetGameplayCamRot(2).z)
            SetEntityVisible(ent, false, false)
        end
        ent = IsPedInAnyVehicle(PlayerPedId(), false) and GetVehiclePedIsIn(PlayerPedId(), false) or PlayerPedId()
        SetEntityCollision(ent, true, true)
        FreezeEntityPosition(ent, false)
        SetEntityVisible(ent, true, false)
        applyInvisible()
    end)
end

-- Names above everyone's head (server id, name)
CreateThread(function()
    while true do
        local sleep = 500
        if self_.names then
            sleep = 0
            local me = PlayerPedId()
            local mc = GetEntityCoords(me)
            for _, pid in ipairs(GetActivePlayers()) do
                local ped = GetPlayerPed(pid)
                if ped ~= me and #(GetEntityCoords(ped) - mc) < 60.0 then
                    local c = GetEntityCoords(ped)
                    local on, sx, sy = GetScreenCoordFromWorldCoord(c.x, c.y, c.z + 1.05)
                    if on then
                        SetTextFont(4) SetTextScale(0.0, 0.32) SetTextColour(255, 255, 255, 230) SetTextOutline() SetTextCentre(true)
                        BeginTextCommandDisplayText('STRING')
                        AddTextComponentSubstringPlayerName(('[%d] %s'):format(GetPlayerServerId(pid), GetPlayerName(pid)))
                        EndTextCommandDisplayText(sx, sy)
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

local function modelOk(name)
    if type(name) ~= 'string' or not name:match('^[%w_]+$') or #name > 32 then return nil end
    local hash = joaat(name)
    if not IsModelInCdimage(hash) or not IsModelAVehicle(hash) then return nil end
    return hash
end

local function currentVehicle()
    local ped = PlayerPedId()
    local v = GetVehiclePedIsIn(ped, false)
    if v ~= 0 then return v end
    local c = GetEntityCoords(ped)
    local near = GetClosestVehicle(c.x, c.y, c.z, 6.0, 0, 71)
    return near ~= 0 and near or nil
end

local TOOLS = {}

TOOLS.noclip = function()
    if not self_.noclip and not allow('noclip') then return false, 'Not allowed' end
    self_.noclip = not self_.noclip
    if self_.noclip then startNoclip() Veyl.Notify('Noclip on. WASD to fly, Shift fast, Ctrl slow, Q up, E down.', 'info', 7000) else Veyl.Notify('Noclip off', 'info') end
    screen:close('tool')
    return true
end
TOOLS.speed = function(v)
    v = math.floor(tonumber(v) or 3)
    self_.speed = math.max(1, math.min(#C.NoclipSpeeds, v))
    return true
end
TOOLS.god = function()
    if not self_.god and not allow('god') then return false, 'Not allowed' end
    self_.god = not self_.god
    applyGod()
    return true, self_.god and 'God mode on' or 'God mode off'
end
TOOLS.invisible = function()
    if not self_.invisible and not allow('invisible') then return false, 'Not allowed' end
    self_.invisible = not self_.invisible
    applyInvisible()
    return true, self_.invisible and 'You are invisible' or 'You are visible'
end
TOOLS.names = function()
    self_.names = not self_.names
    return true, self_.names and 'Names on' or 'Names off'
end
TOOLS.heal = function()
    local ped = PlayerPedId()
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    ClearPedBloodDamage(ped)
    return true, 'Healed'
end
TOOLS.armor = function()
    SetPedArmour(PlayerPedId(), 100)
    return true, 'Armour full'
end
TOOLS.tpm = function()
    local blip = GetFirstBlipInfoId(8)
    if not DoesBlipExist(blip) then return false, 'Set a waypoint on the map first' end
    screen:close('tool')
    TriggerEvent('veyl_admin:tpm')
    return true
end
TOOLS.coords = function()
    local ped = PlayerPedId()
    local c, h = GetEntityCoords(ped), GetEntityHeading(ped)
    local text = ('vector4(%.2f, %.2f, %.2f, %.2f)'):format(c.x, c.y, c.z, h)
    print('[veyl_admin] ' .. text)
    return true, text, text
end
TOOLS.spawn = function(model, plate)
    local hash = modelOk(model)
    if not hash then return false, 'That is not a vehicle model' end
    if not allow('vehicle', model) then return false, 'Not allowed' end
    RequestModel(hash)
    local t = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < t do Wait(10) end
    if not HasModelLoaded(hash) then return false, 'The model did not load' end
    local ped = PlayerPedId()
    local c, h = GetEntityCoords(ped), GetEntityHeading(ped)
    local old = GetVehiclePedIsIn(ped, false)
    if old ~= 0 then DeleteEntity(old) end
    local veh = CreateVehicle(hash, c.x, c.y, c.z, h, true, false)
    SetPedIntoVehicle(ped, veh, -1)
    SetVehicleOnGroundProperly(veh)
    if type(plate) == 'string' and plate:match('^[%w ]+$') and #plate <= 8 and #plate > 0 then SetVehicleNumberPlateText(veh, plate:upper()) end
    SetVehicleEngineOn(veh, true, true, false)
    SetModelAsNoLongerNeeded(hash)
    return true, 'Spawned ' .. model
end
TOOLS.fix = function()
    local v = currentVehicle()
    if not v then return false, 'No vehicle nearby' end
    SetVehicleFixed(v) SetVehicleDeformationFixed(v) SetVehicleEngineHealth(v, 1000.0) SetVehicleUndriveable(v, false)
    return true, 'Vehicle repaired'
end
TOOLS.clean = function()
    local v = currentVehicle()
    if not v then return false, 'No vehicle nearby' end
    WashDecalsFromVehicle(v, 1.0) SetVehicleDirtLevel(v, 0.0)
    return true, 'Vehicle cleaned'
end
TOOLS.flip = function()
    local v = currentVehicle()
    if not v then return false, 'No vehicle nearby' end
    SetVehicleOnGroundProperly(v)
    return true, 'Vehicle flipped upright'
end
TOOLS.delete = function()
    local v = currentVehicle()
    if not v then return false, 'No vehicle nearby' end
    SetEntityAsMissionEntity(v, true, true)
    DeleteEntity(v)
    return true, 'Vehicle deleted'
end

RegisterNUICallback('tool', function(data, cb)
    if not screen:isOpen() or type(data) ~= 'table' or type(data.kind) ~= 'string' or not TOOLS[data.kind] then return cb({ ok = false, code = 'INVALID_INPUT' }) end
    CreateThread(function()
        local ok, msg, extra = TOOLS[data.kind](data.value, data.extra)
        cb({ ok = ok == true, message = msg, data = { state = selfState(), copy = extra } })
    end)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    if self_.noclip then self_.noclip = false end
    SetEntityInvincible(PlayerPedId(), false)
    SetEntityVisible(PlayerPedId(), true, false)
    ResetEntityAlpha(PlayerPedId())
    FreezeEntityPosition(PlayerPedId(), false)
end)

---------------------------------------------------------------------------
-- What the server does to this player
---------------------------------------------------------------------------
RegisterNetEvent('veyl_admin:freeze', function(on)
    local ped = PlayerPedId()
    FreezeEntityPosition(ped, on == true)
    if on then Veyl.Notify('A staff member froze you.', 'warning', 6000) else Veyl.Notify('You can move again.', 'info') end
end)

RegisterNetEvent('veyl_admin:heal', function()
    local ped = PlayerPedId()
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    SetPedArmour(ped, 100)
    ClearPedBloodDamage(ped)
end)

RegisterNetEvent('veyl_admin:kill', function() SetEntityHealth(PlayerPedId(), 0) end)

RegisterNetEvent('veyl_admin:clearArea', function(radius, centre)
    if not centre then return end
    local pc = GetEntityCoords(PlayerPedId())
    if #(pc - vector3(centre.x, centre.y, centre.z)) > radius + 150.0 then return end
    for _, veh in ipairs(GetGamePool('CVehicle')) do
        if #(GetEntityCoords(veh) - vector3(centre.x, centre.y, centre.z)) <= radius and GetPedInVehicleSeat(veh, -1) == 0 and not IsEntityAMissionEntity(veh)
            and not (Entity(veh).state.veylVehicleId ~= nil) and NetworkHasControlOfEntity(veh) then
            DeleteEntity(veh)
        end
    end
end)

-- Spectate: watch another player until Backspace. Their ped may not be streamed in yet, so fly near them first and come back after.
RegisterNetEvent('veyl_admin:spectate', function(target, name, coords)
    if self_.spectating then return end
    local me = PlayerPedId()
    local back = GetEntityCoords(me)
    local backHeading = GetEntityHeading(me)
    local pid = GetPlayerFromServerId(target)
    if (pid == -1 or not DoesEntityExist(GetPlayerPed(pid))) and coords then
        SetEntityCoords(me, coords.x, coords.y, coords.z + 15.0, false, false, false, false)
        FreezeEntityPosition(me, true)
        local t = GetGameTimer() + 4000
        repeat Wait(100) pid = GetPlayerFromServerId(target) until (pid ~= -1 and DoesEntityExist(GetPlayerPed(pid))) or GetGameTimer() > t
    end
    pid = GetPlayerFromServerId(target)
    if pid == -1 or not DoesEntityExist(GetPlayerPed(pid)) then
        FreezeEntityPosition(me, false)
        SetEntityCoords(me, back.x, back.y, back.z, false, false, false, false)
        return Veyl.Notify('Could not reach that player to watch them.', 'error')
    end
    self_.spectating = true
    NetworkSetInSpectatorMode(true, GetPlayerPed(pid))
    Veyl.Notify(('Watching %s. Press Backspace to stop.'):format(name or 'player'), 'info', 6000)
    while self_.spectating do
        Wait(0)
        BeginTextCommandDisplayHelp('STRING')
        AddTextComponentSubstringPlayerName(('Spectating ~y~%s~s~. Press ~INPUT_FRONTEND_RRIGHT~ to stop.'):format(name or 'player'))
        EndTextCommandDisplayHelp(0, false, false, -1)
        if IsControlJustPressed(0, 177) or not DoesEntityExist(GetPlayerPed(GetPlayerFromServerId(target))) then self_.spectating = false end
    end
    NetworkSetInSpectatorMode(false, PlayerPedId())
    FreezeEntityPosition(PlayerPedId(), false)
    SetEntityCoords(PlayerPedId(), back.x, back.y, back.z, false, false, false, false)
    SetEntityHeading(PlayerPedId(), backHeading)
end)
