-- World interactions: the supplier and the buyer (peds through veyl_interact) and the gathering spots (sphere zones through veyl_target).
-- Duplicate prompts are avoided: each of these registers exactly once and is removed on stop.

local C = ProductionConfig
local registered, zones = {}, {}
local gathering = false

local function openShop(kind)
    local res = Veyl.CallbackTimeout('veyl_production', kind == 'buyer' and 'buyerView' or 'shopView', 15000)
    if not res.ok then return Veyl.NotifyResult(res) end
    ProdClient.open(kind, res.data)
end

local function gather(spot)
    if gathering then return end
    gathering = true
    local start = Veyl.CallbackTimeout('veyl_production', 'gatherStart', 15000, spot.id)
    if not start.ok then gathering = false return Veyl.NotifyResult(start) end
    local done = vlib.progress({ label = 'Gathering', duration = start.data.durationMs, canCancel = true, disable = { move = true, car = true, combat = true },
        anim = { dict = 'amb@world_human_gardener_plant@male@base', clip = 'base', flag = 1 } })
    ClearPedTasks(PlayerPedId())
    if not done then gathering = false return Veyl.Notify('Stopped', 'info') end
    Veyl.NotifyResult(Veyl.CallbackTimeout('veyl_production', 'gatherFinish', 15000, start.data.token))
    gathering = false
end

local function register()
    local shop, buyer = C.Shop.Ped, C.Buyer.Ped
    exports.veyl_interact:AddPed({ id = 'veyl_prod_shop', model = shop.model, coords = shop.coords, scenario = shop.scenario, radius = shop.radius, title = shop.label,
        options = { { label = 'Browse supplies', icon = 'bag', onSelect = function() CreateThread(function() openShop('shop') end) end } } })
    exports.veyl_interact:AddPed({ id = 'veyl_prod_buyer', model = buyer.model, coords = buyer.coords, scenario = buyer.scenario, radius = buyer.radius, title = buyer.label,
        options = { { label = 'Sell goods', icon = 'money', onSelect = function() CreateThread(function() openShop('buyer') end) end } } })
    registered = { 'veyl_prod_shop', 'veyl_prod_buyer' }

    if C.Shop.Blip.show then
        local b = AddBlipForCoord(C.Shop.Ped.coords.x, C.Shop.Ped.coords.y, C.Shop.Ped.coords.z)
        SetBlipSprite(b, C.Shop.Blip.sprite) SetBlipColour(b, C.Shop.Blip.colour) SetBlipAsShortRange(b, true)
        BeginTextCommandSetBlipName('STRING') AddTextComponentSubstringPlayerName(C.Shop.Blip.label) EndTextCommandSetBlipName(b)
        registered.blip = b
    end

    for _, spot in ipairs(C.Gathering.Spots) do
        local id = exports.veyl_target:addSphereZone({
            name = 'veyl_prod_gather_' .. spot.id, title = spot.label, coords = spot.coords, radius = spot.radius,
            options = { { name = 'veyl_prod_gather_' .. spot.id, label = 'Gather', icon = 'leaf', distance = spot.radius + 1.0,
                onSelect = function() CreateThread(function() gather(spot) end) end } },
        })
        zones[#zones + 1] = id
        if C.Gathering.Blip.show then
            local b = AddBlipForRadius(spot.coords.x, spot.coords.y, spot.coords.z, spot.radius * 3.0)
            SetBlipColour(b, C.Gathering.Blip.colour) SetBlipAlpha(b, 90)
            zones[#zones + 1] = { blip = b }
        end
    end
end

CreateThread(function()
    while GetResourceState('veyl_interact') ~= 'started' or GetResourceState('veyl_target') ~= 'started' do Wait(500) end
    Wait(500)
    register()
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for _, id in ipairs(registered) do pcall(function() exports.veyl_interact:Remove(id) end) end
    if registered.blip and DoesBlipExist(registered.blip) then RemoveBlip(registered.blip) end
    for _, z in ipairs(zones) do
        if type(z) == 'table' and z.blip then if DoesBlipExist(z.blip) then RemoveBlip(z.blip) end
        else pcall(function() exports.veyl_target:removeZone(z) end) end
    end
end)
