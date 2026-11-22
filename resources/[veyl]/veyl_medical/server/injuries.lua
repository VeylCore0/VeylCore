-- veyl_medical injuries: per body part, stored on the character (metadata.injuries), treated by EMS, items and beds.
--
-- metadata.injuries = { parts = { [part] = { kind, severity 1-4 } }, bleeding = 0-4 }
-- The client reports hits (it is the only side that knows which bone was hit); the server clamps and stores them.

local C = MedicalConfig
local I = C.Injuries
Injuries = {}

local PARTS = { head = 'Head', torso = 'Torso', larm = 'Left arm', rarm = 'Right arm', lleg = 'Left leg', rleg = 'Right leg' }
local KINDS = { gunshot = 'Gunshot wound', cut = 'Laceration', bruise = 'Bruising', fracture = 'Fracture', burn = 'Burn' }
local BLEEDS = { gunshot = 2, cut = 1 }

local function get(src)
    local v = exports.veyl_core:GetMetadata(src, 'injuries')
    if type(v) ~= 'table' then v = {} end
    v.parts = type(v.parts) == 'table' and v.parts or {}
    v.bleeding = math.max(0, math.min(4, tonumber(v.bleeding) or 0))
    return v
end

local function set(src, v)
    exports.veyl_core:SetMetadata(src, 'injuries', v)
    TriggerClientEvent('veyl_medical:injuries', src, v)
end

function Injuries.Has(src)
    local v = get(src)
    return next(v.parts) ~= nil or v.bleeding > 0
end

function Injuries.Clear(src)
    if not src or not GetPlayerName(src) then return end
    set(src, { parts = {}, bleeding = 0 })
end

--- Human-readable list for EMS (and the patient).
function Injuries.Describe(src)
    local v, out = get(src), {}
    for part, inj in pairs(v.parts) do
        out[#out + 1] = { part = PARTS[part] or part, kind = KINDS[inj.kind] or inj.kind, severity = inj.severity }
    end
    table.sort(out, function(a, b) return a.severity > b.severity end)
    return out, v.bleeding
end

local lastReport = {}
RegisterNetEvent('veyl_medical:hit', function(part, kind, amount)
    local src = source
    if not PARTS[part] or not KINDS[kind] or not Veyl.GetCitizenId(src) then return end
    local now = GetGameTimer()
    if lastReport[src] and now - lastReport[src] < 150 then return end
    lastReport[src] = now
    amount = tonumber(amount) or 0
    if amount < I.MinDamage then return end
    local v = get(src)
    local cur = v.parts[part]
    local add = amount >= 40 and 2 or 1
    -- A worse kind of injury replaces a milder one on the same part.
    local rank = { bruise = 1, burn = 2, cut = 2, fracture = 3, gunshot = 4 }
    local newKind = (cur and rank[cur.kind] and rank[cur.kind] > rank[kind]) and cur.kind or kind
    v.parts[part] = { kind = newKind, severity = math.min(4, (cur and cur.severity or 0) + add) }
    v.bleeding = math.min(4, v.bleeding + (BLEEDS[kind] or 0))
    set(src, v)
end)

---------------------------------------------------------------------------
-- EMS: diagnose
---------------------------------------------------------------------------
local function isEMS(src)
    local pd = Veyl.GetPlayerData(src)
    if not pd or not pd.job.onduty then return false end
    for _, j in ipairs(C.EMSJobs) do if pd.job.name == j then return true end end
    return false
end

local function near(a, b, d)
    local pa, pb = Veyl.GetPlayerCoords(a), Veyl.GetPlayerCoords(b)
    return pa and pb and #(pa - pb) <= (d or C.ActionDistance) + 1.0
end

Veyl.RegisterCallback('diagnose', function(src, _, target)
    target = tonumber(target)
    if not isEMS(src) then return Veyl.Err('NO_PERMISSION', 'Only on-duty EMS can examine patients') end
    if not target or not Veyl.GetCitizenId(target) or not near(src, target) then return Veyl.Err('TOO_FAR', 'Move closer') end
    local list, bleeding = Injuries.Describe(target)
    local ped = GetPlayerPed(target)
    return Veyl.Ok({ injuries = list, bleeding = bleeding, health = ped ~= 0 and GetEntityHealth(ped) or nil, state = Player(target).state.medical })
end, { cooldown = 800 })

Veyl.RegisterCallback('myInjuries', function(src)
    local list, bleeding = Injuries.Describe(src)
    return Veyl.Ok({ injuries = list, bleeding = bleeding })
end, { cooldown = 800 })

---------------------------------------------------------------------------
-- Items (inventory use handlers): gauze, painkillers, medkit
---------------------------------------------------------------------------
CreateThread(function()
    while GetResourceState('veyl_inventory') ~= 'started' do Wait(500) end
    Wait(1000)
    for key, def in pairs(C.Items) do
        exports.veyl_inventory:RegisterUseHandler('medical_' .. key, function(ctx)
            local src = ctx.source
            if Player(src).state.medical then return end
            local v = get(src)
            if def.bleeding then v.bleeding = math.max(0, v.bleeding + def.bleeding) end
            set(src, v)
            if def.heal then TriggerClientEvent('veyl_medical:addHealth', src, def.heal) end
            if key == 'painkillers' then TriggerClientEvent('veyl_medical:painkillers', src, I.PainkillerSeconds) end
            Veyl.Notify(src, key == 'gauze' and (v.bleeding > 0 and 'The bleeding slowed.' or 'The bleeding stopped.')
                or key == 'medkit' and 'You patched yourself up.' or 'The pain fades.', 'success')
        end)
    end
end)

---------------------------------------------------------------------------
-- Beds
---------------------------------------------------------------------------
local beds = {} -- [index] = src

local function freeBed()
    for i = 1, #C.Beds do
        local s = beds[i]
        if not s or not GetPlayerName(s) then beds[i] = nil return i end
    end
    return nil
end

function Injuries.PutInBed(target)
    for i, s in pairs(beds) do if s == target then return i end end
    local i = freeBed()
    if not i then return nil end
    beds[i] = target
    TriggerClientEvent('veyl_medical:bed', target, i, C.Beds[i])
    return i
end

function Injuries.LeaveBed(src)
    for i, s in pairs(beds) do if s == src then beds[i] = nil TriggerClientEvent('veyl_medical:bed', src, nil) end end
end

Veyl.RegisterCallback('putInBed', function(src, _, target)
    target = tonumber(target)
    if not isEMS(src) then return Veyl.Err('NO_PERMISSION', 'Only on-duty EMS can do that') end
    if not target or not Veyl.GetCitizenId(target) or not near(src, target, 4.0) then return Veyl.Err('TOO_FAR', 'Move closer') end
    if #C.Beds == 0 then return Veyl.Err('UNAVAILABLE', 'No beds are set up') end
    local pc = Veyl.GetPlayerCoords(src)
    local b = C.Beds[1]
    if not pc or #(pc - vector3(b.x, b.y, b.z)) > C.BedDistance then return Veyl.Err('TOO_FAR', 'Bring them to the hospital') end
    local i = Injuries.PutInBed(target)
    if not i then return Veyl.Err('UNAVAILABLE', 'All beds are taken') end
    return Veyl.Ok(nil, ('Patient in bed %d'):format(i))
end, { cooldown = 1000 })

Veyl.RegisterCallback('leaveBed', function(src)
    if Player(src).state.medical then return Veyl.Err('INVALID_STATE', 'You are in no state to get up') end
    Injuries.LeaveBed(src)
    return Veyl.Ok()
end, { cooldown = 500 })

AddEventHandler('playerDropped', function() Injuries.LeaveBed(source) lastReport[source] = nil end)

-- Sync on load.
AddEventHandler('VeylCore:Server:PlayerLoaded', function(src)
    SetTimeout(2000, function() if GetPlayerName(src) then TriggerClientEvent('veyl_medical:injuries', src, get(src)) end end)
end)
