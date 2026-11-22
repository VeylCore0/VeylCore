-- veyl_medical injuries (client): which body part a hit landed on, injury effects (limp, shake, bleeding),
-- treatment items, hospital beds and the EMS "Check injuries" / "Put in bed" options.

local C = MedicalConfig
local I = C.Injuries
local injuries = { parts = {}, bleeding = 0 }
local painkillersUntil = 0

---------------------------------------------------------------------------
-- Hit detection
---------------------------------------------------------------------------
local BONES = {
    head = { 31086, 39317, 12844, 65068 },
    torso = { 24816, 24817, 24818, 23553, 57597, 11816, 10706, 64729 },
    larm = { 18905, 61163, 45509, 26610, 4089, 4090, 60309 },
    rarm = { 57005, 28252, 40269, 6286, 64016, 28422 },
    lleg = { 58271, 63931, 14201, 65245, 57717 },
    rleg = { 51826, 36864, 52301, 35502, 24806 },
}
local boneToPart = {}
for part, list in pairs(BONES) do for _, b in ipairs(list) do boneToPart[b] = part end end

local BLADES = {}
for _, w in ipairs({ 'WEAPON_KNIFE', 'WEAPON_DAGGER', 'WEAPON_BOTTLE', 'WEAPON_HATCHET', 'WEAPON_MACHETE', 'WEAPON_SWITCHBLADE', 'WEAPON_BATTLEAXE', 'WEAPON_STONE_HATCHET' }) do
    BLADES[joaat(w)] = true
end
local FALLS = { [joaat('WEAPON_FALL')] = true, [joaat('WEAPON_RUN_OVER_BY_CAR')] = true, [joaat('WEAPON_RAMMED_BY_CAR')] = true }

local function kindOf(weapon, amount, part)
    if FALLS[weapon] then return (amount >= 20 and (part == 'lleg' or part == 'rleg' or part == 'larm' or part == 'rarm')) and 'fracture' or 'bruise' end
    local t = GetWeaponDamageType(weapon)
    if t == 3 then return 'gunshot' end
    if t == 5 or t == 6 or t == 13 then return 'burn' end
    if t == 2 then return BLADES[weapon] and 'cut' or 'bruise' end
    return 'bruise'
end

local lastHealth = nil
AddEventHandler('gameEventTriggered', function(name, args)
    if name ~= 'CEventNetworkEntityDamage' then return end
    local ped = PlayerPedId()
    if args[1] ~= ped or not Veyl.IsLoaded() then return end
    local health = GetEntityHealth(ped)
    local amount = math.max(0, (lastHealth or health) - health)
    lastHealth = health
    if amount < I.MinDamage then return end
    local hit, bone = GetPedLastDamageBone(ped)
    local part = (hit and boneToPart[bone]) or 'torso'
    local weapon = args[7]
    if FALLS[weapon] and not boneToPart[bone] then part = math.random() < 0.5 and 'lleg' or 'rleg' end
    TriggerServerEvent('veyl_medical:hit', part, kindOf(weapon, amount, part), amount)
end)

CreateThread(function()
    while true do
        Wait(1000)
        lastHealth = GetEntityHealth(PlayerPedId()) -- keeps the baseline current after healing
    end
end)

---------------------------------------------------------------------------
-- Effects
---------------------------------------------------------------------------
RegisterNetEvent('veyl_medical:injuries', function(v)
    if type(v) ~= 'table' then return end
    local wasBleeding = injuries.bleeding or 0
    injuries = { parts = type(v.parts) == 'table' and v.parts or {}, bleeding = tonumber(v.bleeding) or 0 }
    if injuries.bleeding > 0 and wasBleeding == 0 then Veyl.Notify('You are bleeding. Gauze or a medkit will help.', 'warning', 6000) end
end)

RegisterNetEvent('veyl_medical:painkillers', function(seconds) painkillersUntil = GetGameTimer() + (tonumber(seconds) or 300) * 1000 end)
RegisterNetEvent('veyl_medical:addHealth', function(amount)
    local ped = PlayerPedId()
    if IsEntityDead(ped) or LocalPlayer.state.medical then return end
    SetEntityHealth(ped, math.min(GetEntityMaxHealth(ped), GetEntityHealth(ped) + (tonumber(amount) or 0)))
end)

local function severity(part) local p = injuries.parts[part] return p and p.severity or 0 end

CreateThread(function()
    local limping, nextBleed, nextShake = false, 0, 0
    while true do
        local ped = PlayerPedId()
        local now = GetGameTimer()
        local masked = now < painkillersUntil
        local down = LocalPlayer.state.medical ~= nil
        -- No limp and no camera shake: injuries only bleed (and show in /injuries and to EMS).
        if limping then ResetPedMovementClipset(ped, 0.5) limping = false end
        if injuries.bleeding > 0 and not down and now >= nextBleed then
            if nextBleed > 0 then
                SetEntityHealth(ped, math.max(0, GetEntityHealth(ped) - I.BleedDamage))
            end
            nextBleed = now + math.floor(I.BleedSecondsPerLevel * 1000 / injuries.bleeding)
        elseif injuries.bleeding == 0 then
            nextBleed = 0
        end
        if limping then DisableControlAction(0, 21, true) Wait(0) else Wait(500) end
    end
end)

RegisterCommand('injuries', function()
    CreateThread(function()
        local res = Veyl.Callback('veyl_medical', 'myInjuries')
        if not res.ok then return Veyl.NotifyResult(res) end
        if #res.data.injuries == 0 and res.data.bleeding == 0 then return Veyl.Notify('You have no injuries.', 'success') end
        local parts = {}
        for _, i in ipairs(res.data.injuries) do parts[#parts + 1] = ('%s: %s (%d/4)'):format(i.part, i.kind:lower(), i.severity) end
        if res.data.bleeding > 0 then parts[#parts + 1] = ('Bleeding %d/4'):format(res.data.bleeding) end
        Veyl.Notify(table.concat(parts, ' · '), 'warning', 9000)
    end)
end, false)

---------------------------------------------------------------------------
-- Beds
---------------------------------------------------------------------------
local inBed = nil
RegisterNetEvent('veyl_medical:bed', function(index, spot)
    local ped = PlayerPedId()
    if not index then
        if inBed then
            FreezeEntityPosition(ped, false)
            ClearPedTasks(ped)
            local off = GetOffsetFromEntityInWorldCoords(ped, 1.0, 0.0, 0.0)
            SetEntityCoordsNoOffset(ped, off.x, off.y, inBed.z + 0.2, false, false, false)
        end
        inBed = nil
        return
    end
    inBed = spot
    DetachEntity(ped, true, false)
    SetEntityCoordsNoOffset(ped, spot.x, spot.y, spot.z, false, false, false)
    SetEntityHeading(ped, spot.w)
    FreezeEntityPosition(ped, true)
end)

CreateThread(function()
    local dict, clip = 'anim@gangops@morgue@table@', 'body_search'
    while true do
        if not inBed then Wait(500) else
            local ped = PlayerPedId()
            if not LocalPlayer.state.medical and not IsEntityPlayingAnim(ped, dict, clip, 3) then
                RequestAnimDict(dict)
                if HasAnimDictLoaded(dict) then TaskPlayAnim(ped, dict, clip, 8.0, -8.0, -1, 1, 0, false, false, false) end
            end
            if not LocalPlayer.state.medical then
                Veyl.HelpText('Press ~INPUT_CONTEXT~ to get out of bed')
                if IsControlJustPressed(0, 38) then CreateThread(function() Veyl.NotifyResult(Veyl.Callback('veyl_medical', 'leaveBed')) end) end
            end
            Wait(0)
        end
    end
end)

---------------------------------------------------------------------------
-- EMS options
---------------------------------------------------------------------------
local function isEMS()
    local job = (Veyl.PlayerData or {}).job
    if not job or not job.onduty then return false end
    for _, j in ipairs(C.EMSJobs) do if job.name == j then return true end end
    return false
end

local function serverIdOf(entity)
    local idx = NetworkGetPlayerIndexFromPed(entity)
    return idx ~= -1 and GetPlayerServerId(idx) or nil
end

local function diagnose(entity)
    local id = serverIdOf(entity)
    if not id then return end
    local res = Veyl.Callback('veyl_medical', 'diagnose', id)
    if not res.ok then return Veyl.NotifyResult(res) end
    local items = {}
    local d = res.data
    items[#items + 1] = { label = ('Health %d / 200'):format(d.health or 0), description = d.state == 'down' and 'Downed' or d.state == 'dead' and 'Unconscious' or 'Conscious', disabled = true }
    if d.bleeding > 0 then items[#items + 1] = { label = ('Bleeding %d / 4'):format(d.bleeding), description = 'Gauze or a medkit slows it; treatment stops it', disabled = true } end
    for _, i in ipairs(d.injuries) do
        items[#items + 1] = { label = ('%s · %s'):format(i.part, i.kind), right = ('%d/4'):format(i.severity), disabled = true }
    end
    if #d.injuries == 0 and d.bleeding == 0 then items[#items + 1] = { label = 'No injuries found', disabled = true } end
    Veyl.UI.Menu({ title = 'Examination', subtitle = 'Treat injuries to heal all of them', items = items })
end

CreateThread(function()
    while GetResourceState('veyl_target') ~= 'started' do Wait(250) end
    exports.veyl_target:addGlobalPlayer({
        { name = 'veyl_medical_diagnose', label = 'Check injuries', icon = 'inspect', distance = C.ActionDistance, priority = 4,
          canInteract = function() return isEMS() and not LocalPlayer.state.medical end, onSelect = function(d) CreateThread(function() diagnose(d.entity) end) end },
        { name = 'veyl_medical_bill', label = 'Send medical bill', icon = 'receipt', distance = C.ActionDistance, priority = 1,
          canInteract = function() return isEMS() and not LocalPlayer.state.medical end,
          onSelect = function(d) CreateThread(function()
              local id = serverIdOf(d.entity)
              if not id then return end
              local v = vlib.inputDialog('Medical bill', {
                  { name = 'amount', label = 'Amount ($)', type = 'number', required = true, min = 1, max = C.Bills.Max },
                  { name = 'reason', label = 'For', type = 'text', required = true, maxLength = 100, placeholder = 'e.g. Gunshot treatment and transport' },
              }, { submitLabel = 'Send bill' })
              if v then Veyl.NotifyResult(Veyl.CallbackTimeout('veyl_medical', 'bill', 15000, id, math.floor(tonumber(v.amount) or 0), v.reason)) end
          end) end },
        { name = 'veyl_medical_bed', label = 'Put in hospital bed', icon = 'heart', distance = C.ActionDistance, priority = 2,
          canInteract = function() return isEMS() and #C.Beds > 0 and #(GetEntityCoords(PlayerPedId()) - vector3(C.Beds[1].x, C.Beds[1].y, C.Beds[1].z)) < C.BedDistance end,
          onSelect = function(d) CreateThread(function() local id = serverIdOf(d.entity) if id then Veyl.NotifyResult(Veyl.Callback('veyl_medical', 'putInBed', id)) end end) end },
    })
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    ResetPedMovementClipset(PlayerPedId(), 0.0)
    if inBed then FreezeEntityPosition(PlayerPedId(), false) end
end)

-- Clear any camera shake or limp left over from the old injury effects.
CreateThread(function()
    StopGameplayCamShaking(true)
    ResetPedMovementClipset(PlayerPedId(), 0.0)
end)
