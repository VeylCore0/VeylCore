-- NUI bridge. Passive overlays (placement hint, plant card) never take focus; the Grow Journal is a modal screen
-- managed by vlib.createScreen (focus token, Escape, death/logout/resource-stop cleanup).

DrugsUI = {}
local screen = vlib.createScreen({ name = 'drugs' })
local journalPlants = {}

function DrugsUI.Placement(state) SendNUIMessage({ action = 'drugs:placement', data = state }) end
function DrugsUI.Card(view) SendNUIMessage({ action = 'drugs:card', data = view }) end
function DrugsUI.IsOpen() return screen:isOpen() end

local function openJournal()
    if screen:isOpen() or not Veyl.IsLoaded() then return end
    local has = Veyl.Callback('veyl_drugs', 'hasJournal')
    if not (has.ok and has.data.ok) then return Veyl.Notify('You need a Grow Journal', 'error') end
    local res = Veyl.Callback('veyl_drugs', 'journal')
    if not res.ok then return Veyl.NotifyResult(res) end
    journalPlants = {}
    for _, p in ipairs(res.data.plants) do
        journalPlants[p.id] = p
        local street = GetStreetNameFromHashKey(GetStreetNameAtCoord(p.coords.x, p.coords.y, p.coords.z))
        p.area = GetLabelText(GetNameOfZone(p.coords.x, p.coords.y, p.coords.z))
        p.street = street ~= '' and street or nil
    end
    local ok, reason = screen:open('drugs:journal', res.data)
    if not ok then Veyl.Notify(reason == 'busy' and 'Close the open menu first.' or 'Journal unavailable.', 'warning') end
end

RegisterNetEvent('veyl_drugs:openJournal', function() CreateThread(openJournal) end)
RegisterCommand(DrugsConfig.Journal.Command, function() CreateThread(openJournal) end, false)

RegisterNUICallback('refresh', function(_, cb)
    local res = Veyl.Callback('veyl_drugs', 'journal')
    if res.ok then
        for _, p in ipairs(res.data.plants) do
            journalPlants[p.id] = p
            local street = GetStreetNameFromHashKey(GetStreetNameAtCoord(p.coords.x, p.coords.y, p.coords.z))
            p.area = GetLabelText(GetNameOfZone(p.coords.x, p.coords.y, p.coords.z))
            p.street = street ~= '' and street or nil
        end
    end
    cb({ ok = res.ok, code = res.code, message = res.message, data = res.data })
end)

RegisterNUICallback('waypoint', function(data, cb)
    local p = journalPlants[tonumber(data and data.id) or -1]
    if not p then return cb({ ok = false, code = 'NOT_FOUND' }) end
    SetNewWaypoint(p.coords.x, p.coords.y)
    cb({ ok = true, message = 'Waypoint set' })
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    DrugsUI.Placement({ visible = false })
    DrugsUI.Card(nil)
end)
