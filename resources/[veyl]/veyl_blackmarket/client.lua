-- veyl_blackmarket client: dealer peds and the menu screen. The page can only ask for 'view' and 'buy'; the server checks everything.

local C = BlackmarketConfig
local screen = vlib.createScreen({ name = 'blackmarket' })
local current = nil

local function open(dealerId)
    if screen:isOpen() or not Veyl.IsLoaded() then return end
    local res = Veyl.CallbackTimeout('veyl_blackmarket', 'view', 15000, dealerId)
    if not res.ok then return Veyl.NotifyResult(res) end
    current = dealerId
    local ok, reason = screen:open('blackmarket:open', { data = res.data })
    if not ok then Veyl.Notify(reason == 'busy' and 'Close the open menu first.' or 'Not available right now.', 'warning') end
end

local ALLOWED = { view = true, buy = true }

RegisterNUICallback('api', function(data, cb)
    if not screen:isOpen() or type(data) ~= 'table' or not ALLOWED[data.name] or not current then return cb({ ok = false, code = 'INVALID_INPUT' }) end
    local args = type(data.args) == 'table' and data.args or {}
    CreateThread(function()
        local res
        if data.name == 'view' then res = Veyl.CallbackTimeout('veyl_blackmarket', 'view', 15000, current)
        else res = Veyl.CallbackTimeout('veyl_blackmarket', 'buy', 20000, current, args[1], args[2]) end
        cb({ ok = res.ok, code = res.code, message = res.message, data = res.data })
    end)
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, d in ipairs(C.Dealers) do pcall(function() exports.veyl_interact:Remove('veyl_blackmarket_' .. d.id) end) end
end)

CreateThread(function()
    while GetResourceState('veyl_interact') ~= 'started' do Wait(500) end
    for _, d in ipairs(C.Dealers) do
        exports.veyl_interact:AddPed({ id = 'veyl_blackmarket_' .. d.id, model = d.ped.model, coords = d.ped.coords, scenario = d.ped.scenario, radius = 2.5, title = d.label,
            options = { { label = 'See what he has', icon = 'bag', onSelect = function() CreateThread(function() open(d.id) end) end } } })
        if d.blip and d.blip.show then
            local b = AddBlipForCoord(d.ped.coords.x, d.ped.coords.y, d.ped.coords.z)
            SetBlipSprite(b, d.blip.sprite) SetBlipColour(b, d.blip.colour) SetBlipAsShortRange(b, true)
            BeginTextCommandSetBlipName('STRING') AddTextComponentSubstringPlayerName(d.blip.label) EndTextCommandSetBlipName(b)
        end
    end
end)
