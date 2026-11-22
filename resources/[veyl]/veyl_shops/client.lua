-- veyl_shops client: the shop screen. Prices/stock shown are for display; the server decides every charge.

local screen = vlib.createScreen({ name = 'shop' })
local currentShop = nil

local function openShop(shopId)
    if screen:isOpen() or not Veyl.IsLoaded() then return end
    local res = Veyl.Callback('veyl_shops', 'catalog', shopId)
    if not res.ok then return Veyl.NotifyResult(res) end
    currentShop = shopId
    local ok, reason = screen:open('shop:open', res.data)
    if not ok then Veyl.Notify(reason == 'busy' and 'Close the open menu first.' or 'Shop UI unavailable.', 'warning') end
end

RegisterNUICallback('checkout', function(data, cb)
    if not screen:isOpen() or type(data) ~= 'table' or type(data.lines) ~= 'table' then return cb({ ok = false, code = 'INVALID_INPUT' }) end
    local lines = {}
    for i, l in ipairs(data.lines) do
        if i > 20 or type(l) ~= 'table' then break end
        lines[#lines + 1] = { index = tonumber(l.index), count = tonumber(l.count) }
    end
    local opId = tostring(data.opId or '')
    local res = Veyl.CallbackTimeout('veyl_shops', 'checkout', 20000, {
        opId = opId, shopId = currentShop, method = data.method == 'bank' and 'bank' or 'cash',
        lines = lines, expectedTotal = tonumber(data.expectedTotal),
    })
    -- A transport timeout does not prove failure: ask for the stored outcome before the player retries.
    if res.code == 'TIMEOUT' then
        local status = Veyl.CallbackTimeout('veyl_shops', 'status', 10000, opId)
        if status.ok or (status.code ~= 'TIMEOUT' and status.code ~= 'NOT_FOUND') then res = status end
    end
    cb({ ok = res.ok, code = res.code, message = res.message, data = res.data })
end)

AddEventHandler('veyl_shops:open', function(args) if args then CreateThread(function() openShop(args.id) end) end end)

CreateThread(function()
    while GetResourceState('veyl_interact') ~= 'started' do Wait(200) end
    for _, s in ipairs(ShopsConfig.Shops) do
        exports.veyl_interact:AddPed({
            id = 'shop_' .. s.id, model = s.ped.model, coords = s.ped.coords, radius = ShopsConfig.UseDistance, icon = 'basket',
            label = 'Shop at ' .. (s.blip and s.blip.name or s.label), event = 'veyl_shops:open', args = { id = s.id },
        })
        if s.blip then
            local c = s.ped.coords
            local blip = AddBlipForCoord(c.x, c.y, c.z)
            SetBlipSprite(blip, s.blip.sprite)
            SetBlipColour(blip, s.blip.colour)
            SetBlipScale(blip, 0.7)
            SetBlipAsShortRange(blip, true)
            BeginTextCommandSetBlipName('STRING')
            AddTextComponentSubstringPlayerName(s.blip.name or s.label)
            EndTextCommandSetBlipName(blip)
        end
    end
end)

--- GetShops() -> every shop definition (used by veyl_robbery to find the registers).
exports('GetShops', function() return ShopsConfig.Shops end)
