-- veyl_prison client: placing the prisoner, the sentence counter on screen, yard work spots and release.

local C = PrisonConfig
local sentence = nil -- { remaining, months, ... } while serving
local workZones = {}

local function teleport(p)
    DoScreenFadeOut(400)
    local t = GetGameTimer() + 1000
    while not IsScreenFadedOut() and GetGameTimer() < t do Wait(10) end
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then TaskLeaveVehicle(ped, GetVehiclePedIsIn(ped, false), 16) Wait(300) end
    RequestCollisionAtCoord(p.x, p.y, p.z)
    SetEntityCoordsNoOffset(ped, p.x, p.y, p.z, false, false, false)
    SetEntityHeading(ped, p.w or 0.0)
    t = GetGameTimer() + 5000
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < t do Wait(25) end
    DoScreenFadeIn(600)
end

local function clearWork()
    for _, id in ipairs(workZones) do exports.veyl_interact:Remove(id) end
    workZones = {}
end

local function addWork()
    clearWork()
    if GetResourceState('veyl_interact') ~= 'started' then return end
    for i, s in ipairs(C.Work.Spots) do
        workZones[#workZones + 1] = exports.veyl_interact:AddZone({
            id = ('veyl_prison_work_%d'):format(i), coords = s.coords, radius = 1.5, title = 'Yard work',
            options = { { label = s.label, icon = 'wrench', event = 'veyl_prison:work', args = { spot = i } } },
        })
    end
    if C.Canteen then
        workZones[#workZones + 1] = exports.veyl_interact:AddZone({
            id = 'veyl_prison_canteen', coords = C.Canteen.coords, radius = 1.5, title = 'Canteen',
            options = { { label = 'Get a meal', icon = 'burger', event = 'veyl_prison:canteen' } },
        })
    end
end

RegisterNetEvent('veyl_prison:state', function(st)
    local was = sentence ~= nil
    sentence = st
    if st and not was then addWork() elseif not st and was then clearWork() end
end)

RegisterNetEvent('veyl_prison:placeInside', function(p) CreateThread(function() teleport(p) end) end)

-- Logging out / switching character: forget this character's prison state (the server sends it again on load).
RegisterNetEvent('VeylCore:Client:OnPlayerUnload', function() sentence = nil clearWork() end)

RegisterNetEvent('veyl_prison:released', function(p)
    sentence = nil
    clearWork()
    CreateThread(function() teleport(p) end)
end)

AddEventHandler('veyl_prison:work', function(args)
    if not sentence or type(args) ~= 'table' then return end
    CreateThread(function()
        local s = C.Work.Spots[args.spot]
        local start = Veyl.Callback('veyl_prison', 'workStart', args.spot)
        if not start.ok then return Veyl.NotifyResult(start) end
        if s.scenario then TaskStartScenarioInPlace(PlayerPedId(), s.scenario, 0, true) end
        local done = vlib.progress({ label = s.label, duration = start.data.seconds * 1000, canCancel = true, disable = { move = true, car = true, combat = true } })
        ClearPedTasks(PlayerPedId())
        if not done then return Veyl.Notify('Stopped', 'info') end
        Veyl.NotifyResult(Veyl.Callback('veyl_prison', 'workFinish'))
    end)
end)

-- Sentence counter, top centre.
CreateThread(function()
    while true do
        if not sentence then
            Wait(1000)
        else
            SetTextFont(4)
            SetTextScale(0.0, 0.5)
            SetTextColour(255, 255, 255, 230)
            SetTextOutline()
            SetTextCentre(true)
            BeginTextCommandDisplayText('STRING')
            AddTextComponentSubstringPlayerName(('BOLINGBROKE  ·  %d month%s left'):format(sentence.remaining, sentence.remaining == 1 and '' or 's'))
            EndTextCommandDisplayText(0.5, 0.025)
            Wait(0)
        end
    end
end)

AddEventHandler('onResourceStop', function(res) if res == GetCurrentResourceName() then clearWork() end end)
AddEventHandler('veyl_prison:canteen', function()
    CreateThread(function() Veyl.NotifyResult(Veyl.Callback('veyl_prison', 'canteen')) end)
end)
