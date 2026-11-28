-- The underground contact(s) and the /boosting command. Peds and zones are registered through veyl_interact and removed on stop.

local C = BoostingConfig
local registered = {}

local function register()
    for _, c in ipairs(C.Contacts) do
        local id = 'veyl_boosting_contact_' .. c.id
        exports.veyl_interact:AddPed({
            id = id, model = c.model, coords = c.coords, scenario = c.scenario, radius = c.radius or 2.2, title = c.label,
            options = { { label = 'Open the boosting tablet', icon = 'car', onSelect = function() TriggerEvent('veyl_boosting:openLocal', 'contact') end } },
        })
        registered[#registered + 1] = id
    end
end

CreateThread(function()
    while GetResourceState('veyl_interact') ~= 'started' do Wait(250) end
    Wait(500)
    register()
end)

-- veyl_interact restarted: put the contacts back.
AddEventHandler('onResourceStart', function(res)
    if res ~= 'veyl_interact' then return end
    CreateThread(function() Wait(2000) registered = {} register() end)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, id in ipairs(registered) do pcall(function() exports.veyl_interact:Remove(id) end) end
end)

if C.Tablet.Command then
    RegisterCommand(C.Tablet.Command, function() TriggerEvent('veyl_boosting:openLocal', 'command') end, false)
end

-- The phone's Boosting app (optional): opens the tablet.
AddEventHandler('veyl_boosting:menu', function() TriggerEvent('veyl_boosting:openLocal', 'phone') end)
CreateThread(function()
    while GetResourceState('veyl_phone') ~= 'started' do Wait(1000) end
    pcall(function() exports.veyl_phone:RegisterApp({ id = 'boosting', label = 'Boosting', icon = 'car', color = '#3b1f4f', event = 'veyl_boosting:menu' }) end)
end)
