-- The underground contact(s): they sell the tablet. The tablet itself is an inventory item (use it to open it). Peds and zones are registered through veyl_interact and removed on stop.

local C = BoostingConfig
local registered = {}

local function register()
    for _, c in ipairs(C.Contacts) do
        local id = 'veyl_boosting_contact_' .. c.id
        exports.veyl_interact:AddPed({
            id = id, model = c.model, coords = c.coords, scenario = c.scenario, radius = c.radius or 2.2, title = c.label,
            options = { { label = ('Buy a tablet ($%d)'):format(C.Tablet.Price), icon = 'car', onSelect = function()
                CreateThread(function() Veyl.NotifyResult(Veyl.CallbackTimeout('veyl_boosting', 'buyTablet', 15000)) end)
            end } },
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

