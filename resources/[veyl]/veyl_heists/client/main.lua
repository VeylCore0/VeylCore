-- veyl_heists client: the action points, the Fleeca vault doors and the lockboxes inside the vaults. The server decides every step
-- (thermite, hack, drill, smash); this only moves the door and asks.

local C = HeistsConfig

local ANIMS = {
    thermite = { scenario = 'WORLD_HUMAN_WELDING' },
    hack = { anim = { dict = 'anim@heists@prison_heistig1_p1_guard_checks_bus', clip = 'loop', flag = 49 } },
    loot = { scenario = 'WORLD_HUMAN_CONST_DRILL' },
    smash = { anim = { dict = 'missheist_jewel', clip = 'smash_case', flag = 1 } },
}
local LABELS = { thermite = 'Placing thermite', hack = 'Hacking the panel', loot = 'Drilling a lockbox', smash = 'Smashing the case' }

local function act(id, box)
    local start = Veyl.CallbackTimeout('veyl_heists', 'start', 10000, id, box)
    if not start.ok then return Veyl.NotifyResult(start) end
    local s = start.data
    local a = ANIMS[s.step] or {}
    local ped = PlayerPedId()
    if s.step == 'loot' and box then
        -- Face the lockbox while drilling.
        for _, b in ipairs(C.Fleeca.banks) do
            if b.id == id and b.boxes[box] then TaskTurnPedToFaceCoord(ped, b.boxes[box].x, b.boxes[box].y, b.boxes[box].z, 600) Wait(600) end
        end
    end
    if a.scenario then TaskStartScenarioInPlace(ped, a.scenario, 0, true) end
    local done = vlib.progress({ label = LABELS[s.step], duration = s.seconds * 1000, canCancel = true,
        disable = { move = true, car = true, combat = true }, anim = a.anim })
    ClearPedTasks(PlayerPedId())
    if not done then
        Veyl.Callback('veyl_heists', 'cancel')
        return Veyl.Notify('Stopped. The alarm is still ringing.', 'warning')
    end
    if s.step == 'smash' then PlaySoundFromCoord(-1, 'Glass_Smash', GetEntityCoords(PlayerPedId()), '', false, 0, false) end
    Veyl.NotifyResult(Veyl.CallbackTimeout('veyl_heists', 'finish', 10000, s.token))
end

AddEventHandler('veyl_heists:act', function(a) if type(a) == 'table' then CreateThread(function() act(a.id, a.box) end) end end)

---------------------------------------------------------------------------
-- Fleeca vault doors: open once the vault panel is hacked, closed again when the place resets
---------------------------------------------------------------------------
local stages = {}   -- [bankId] = 'idle' | 'door' | 'open' (what the server last said)
local applied = {}  -- [bankId] = the stage the door was last moved for
local swinging = {}

local function findDoor(b)
    local model = joaat(b.door.model)
    local e = GetClosestObjectOfType(b.panel.x, b.panel.y, b.panel.z, 12.0, model, false, false, false)
    return e ~= 0 and e or nil
end

local function setDoor(b, open, smooth)
    local e = findDoor(b)
    if not e then return false end
    local target = open and b.door.open or b.door.closed
    FreezeEntityPosition(e, false)
    if smooth then
        local from = GetEntityHeading(e)
        local diff = ((target - from + 540.0) % 360.0) - 180.0
        local steps = 40
        for i = 1, steps do
            if not DoesEntityExist(e) then return false end
            SetEntityHeading(e, from + diff * (i / steps))
            Wait(25)
        end
    end
    if DoesEntityExist(e) then
        SetEntityHeading(e, target)
        FreezeEntityPosition(e, true)
    end
    return true
end

local function applyStage(b, smooth)
    local open = stages[b.id] == 'open'
    if applied[b.id] == (open and 'open' or 'closed') or swinging[b.id] then return end
    swinging[b.id] = true
    CreateThread(function()
        if setDoor(b, open, smooth) then applied[b.id] = open and 'open' or 'closed' end
        swinging[b.id] = nil
    end)
end

RegisterNetEvent('veyl_heists:sync', function(id, stage)
    stages[id] = stage
    for _, b in ipairs(C.Fleeca.banks) do if b.id == id then applyStage(b, true) end end
end)

CreateThread(function()
    while not Veyl.IsLoaded() do Wait(1000) end
    local lastPull = -999999
    while true do
        local pc = GetEntityCoords(PlayerPedId())
        local nearest = 99999.0
        for _, b in ipairs(C.Fleeca.banks) do nearest = math.min(nearest, #(pc - b.panel)) end
        -- Only bother when a bank is in range; refresh the server's states now and then so a reset closes the door again.
        if nearest < 150.0 and GetGameTimer() - lastPull > 15000 then
            lastPull = GetGameTimer()
            local r = Veyl.CallbackTimeout('veyl_heists', 'states', 8000)
            if r.ok and type(r.data) == 'table' then for id, st in pairs(r.data) do stages[id] = st end end
        end
        for _, b in ipairs(C.Fleeca.banks) do
            if #(pc - b.panel) < 60.0 then
                -- A bank that streamed in again: the door object is new, so move it to match the state.
                local e = findDoor(b)
                if e and applied[b.id] and math.abs(((GetEntityHeading(e) - (applied[b.id] == 'open' and b.door.open or b.door.closed) + 540.0) % 360.0) - 180.0) > 5.0 then applied[b.id] = nil end
                applyStage(b, false)
            else
                applied[b.id] = nil
            end
        end
        Wait(nearest < 150.0 and 1500 or 5000)
    end
end)

---------------------------------------------------------------------------
-- Action points
---------------------------------------------------------------------------
local zoneIds = {}

CreateThread(function()
    while GetResourceState('veyl_interact') ~= 'started' do Wait(250) end
    for _, b in ipairs(C.Fleeca.banks) do
        exports.veyl_interact:AddZone({ id = 'veyl_heist_' .. b.id, coords = b.panel, radius = 1.5, title = b.label,
            options = { { label = 'Hack the vault panel', icon = 'lock', event = 'veyl_heists:act', args = { id = b.id } } } })
        zoneIds[#zoneIds + 1] = 'veyl_heist_' .. b.id
        -- The lockboxes are inside the vault: walk in once it is open and drill each one.
        for i, pos in ipairs(b.boxes) do
            local zid = ('veyl_heist_%s_box%d'):format(b.id, i)
            exports.veyl_interact:AddZone({ id = zid, coords = pos, radius = 1.0, title = 'Lockbox',
                options = { { label = 'Drill the lockbox', icon = 'bolt', event = 'veyl_heists:act', args = { id = b.id, box = i },
                    canInteract = function() return stages[b.id] == 'open' end } } })
            zoneIds[#zoneIds + 1] = zid
        end
    end
    local p = C.Paleto
    exports.veyl_interact:AddZone({ id = 'veyl_heist_paleto_door', coords = p.door, radius = 1.3, title = 'Vault door',
        options = { { label = 'Use thermite', icon = 'bolt', event = 'veyl_heists:act', args = { id = p.id } } } })
    exports.veyl_interact:AddZone({ id = 'veyl_heist_paleto', coords = p.panel, radius = 1.3, title = p.label,
        options = { { label = 'Hack the vault / drill boxes', icon = 'lock', event = 'veyl_heists:act', args = { id = p.id } } } })
    local j = C.Jewelry
    exports.veyl_interact:AddZone({ id = 'veyl_heist_jewelry', coords = j.center, radius = j.radius, title = j.label,
        options = { { label = 'Smash a display case', icon = 'jewel', event = 'veyl_heists:act', args = { id = j.id },
            canInteract = function() return IsPedArmed(PlayerPedId(), 7) end } } })
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, id in ipairs(zoneIds) do pcall(function() exports.veyl_interact:Remove(id) end) end
    -- Put the vault doors back where the map has them.
    for _, b in ipairs(C.Fleeca.banks) do
        local e = findDoor(b)
        if e and applied[b.id] == 'open' then SetEntityHeading(e, b.door.closed) FreezeEntityPosition(e, true) end
    end
end)
