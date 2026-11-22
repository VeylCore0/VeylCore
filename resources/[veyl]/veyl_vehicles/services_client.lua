-- veyl_vehicles services (client): trunk / glovebox, plate shop, fake plates, selling a vehicle, insurance office.

local C = VehiclesConfig

local function openTrunk(entity)
    if GetVehicleClass(entity) == 8 or GetVehicleClass(entity) == 13 then return Veyl.Notify('No trunk on this vehicle', 'error') end
    local netId = NetworkGetNetworkIdFromEntity(entity)
    SetVehicleDoorOpen(entity, 5, false, false)
    exports.veyl_inventory:openInventory('stash', ('veh_trunk@%d'):format(netId))
    CreateThread(function()
        Wait(500)
        while exports.veyl_inventory:IsOpen() do Wait(250) end
        if DoesEntityExist(entity) then SetVehicleDoorShut(entity, 5, false) end
    end)
end

local function openGlovebox()
    local veh = GetVehiclePedIsIn(PlayerPedId(), false)
    if veh == 0 then return Veyl.Notify('Sit in a vehicle', 'error') end
    exports.veyl_inventory:openInventory('stash', ('veh_glovebox@%d'):format(NetworkGetNetworkIdFromEntity(veh)))
end
RegisterCommand('glovebox', openGlovebox, false)
vlib.addKeybind({ name = 'veyl_glovebox', description = 'Open glovebox', defaultKey = C.Glovebox.key or '', onPressed = function()
    if GetVehiclePedIsIn(PlayerPedId(), false) ~= 0 then openGlovebox() end
end })

local function sell(entity)
    local me, pc = PlayerId(), GetEntityCoords(PlayerPedId())
    local opts = {}
    for _, pid in ipairs(GetActivePlayers()) do
        if pid ~= me and #(GetEntityCoords(GetPlayerPed(pid)) - pc) < 8.0 then
            local sid = GetPlayerServerId(pid)
            opts[#opts + 1] = { value = tostring(sid), label = ('Player #%d'):format(sid) }
        end
    end
    if #opts == 0 then return Veyl.Notify('The buyer must be standing next to you', 'error') end
    local v = vlib.inputDialog('Sell or give this vehicle', {
        { name = 'target', label = 'To', type = 'select', required = true, options = opts, default = opts[1].value },
        { name = 'price', label = 'Price ($, 0 = gift)', type = 'number', required = true, min = 0, default = 0 },
    }, { submitLabel = 'Send offer' })
    if v then Veyl.NotifyResult(Veyl.CallbackTimeout('veyl_vehicles', 'transferOffer', 15000, NetworkGetNetworkIdFromEntity(entity), tonumber(v.target), tonumber(v.price))) end
end

RegisterNetEvent('veyl_vehicles:transferPrompt', function(token, info)
    if type(info) ~= 'table' then return end
    CreateThread(function()
        local ok = Veyl.UI.Confirm({ title = 'Vehicle offer', confirmLabel = info.price > 0 and ('Pay $%d'):format(info.price) or 'Accept',
            message = ('%s offers you their %s (%s)%s. Ownership moves to you.'):format(info.seller, info.vehicle, info.plate,
                info.price > 0 and (' for $%d from your bank'):format(info.price) or ' as a gift') })
        Veyl.NotifyResult(Veyl.CallbackTimeout('veyl_vehicles', 'transferAnswer', 20000, token, ok == true))
    end)
end)

CreateThread(function()
    while GetResourceState('veyl_target') ~= 'started' do Wait(500) end
    exports.veyl_target:addGlobalVehicle({
        { name = 'veyl_veh_trunk', label = 'Open trunk', icon = 'trunk', distance = 2.5, priority = 3,
          canInteract = function(entity) return GetVehicleClass(entity) ~= 8 and GetVehicleClass(entity) ~= 13 end, -- locked: the server checks keys
          onSelect = function(d) openTrunk(d.entity) end },
        { name = 'veyl_veh_fakeplate', label = 'Remove fake plate', icon = 'tag', distance = 2.5, priority = 1,
          canInteract = function(entity) return Entity(entity).state.realPlate ~= nil end,
          onSelect = function(d) CreateThread(function() Veyl.NotifyResult(Veyl.Callback('veyl_vehicles', 'removeFakePlate', NetworkGetNetworkIdFromEntity(d.entity))) end) end },
        { name = 'veyl_veh_sell', label = 'Sell / give vehicle', icon = 'key', distance = 2.5, priority = 1,
          canInteract = function(entity) return Entity(entity).state.veylOwnedId ~= nil end,
          onSelect = function(d) CreateThread(function() sell(d.entity) end) end },
    })
end)

---------------------------------------------------------------------------
-- Plate shop and insurance office
---------------------------------------------------------------------------
AddEventHandler('veyl_vehicles:plateShop', function()
    CreateThread(function()
        local veh = GetVehiclePedIsIn(PlayerPedId(), false)
        if veh == 0 then return Veyl.Notify('Drive your vehicle in and stay seated', 'error') end
        local v = vlib.inputDialog(('Custom plate ($%d)'):format(C.PlateShop.price), {
            { name = 'plate', label = 'New plate (2-8 letters / numbers)', type = 'text', required = true, maxLength = 8 },
        }, { submitLabel = 'Order plate' })
        if v then Veyl.NotifyResult(Veyl.CallbackTimeout('veyl_vehicles', 'customPlate', 15000, NetworkGetNetworkIdFromEntity(veh), v.plate)) end
    end)
end)

AddEventHandler('veyl_vehicles:insurance', function()
    CreateThread(function()
        local res = Veyl.Callback('veyl_vehicles', 'insuranceList')
        if not res.ok then return Veyl.NotifyResult(res) end
        local items = {}
        for _, r in ipairs(res.data.vehicles) do
            items[#items + 1] = { label = ('%s · %s'):format(r.label or r.model, r.plate), value = tostring(r.id),
                description = r.active == 1 and ('Covered until %s'):format(r.until_at or '?') or 'Not insured',
                right = r.active == 1 and 'Insured' or nil }
        end
        if #items == 0 then return Veyl.Notify('You do not own any vehicles', 'info') end
        local pick = Veyl.UI.Menu({ title = 'Vehicle insurance', subtitle = ('$%d per week · free recovery and repair after a wreck'):format(res.data.weekly), items = items })
        if not pick then return end
        local v = vlib.inputDialog('Buy cover', { { name = 'weeks', label = 'Weeks', type = 'number', required = true, min = 1, max = C.Insurance.maxWeeks, default = 1 } }, { submitLabel = 'Pay' })
        if v then Veyl.NotifyResult(Veyl.CallbackTimeout('veyl_vehicles', 'insuranceBuy', 15000, tonumber(pick), tonumber(v.weeks))) end
    end)
end)

CreateThread(function()
    while GetResourceState('veyl_interact') ~= 'started' do Wait(500) end
    local function blip(c, sprite, colour, name)
        local b = AddBlipForCoord(c.x, c.y, c.z)
        SetBlipSprite(b, sprite) SetBlipColour(b, colour) SetBlipScale(b, 0.7) SetBlipAsShortRange(b, true)
        BeginTextCommandSetBlipName('STRING') AddTextComponentSubstringPlayerName(name) EndTextCommandSetBlipName(b)
    end
    exports.veyl_interact:AddZone({ id = 'veyl_plateshop', coords = C.PlateShop.coords.xyz, radius = C.PlateShop.radius, title = 'Plate shop',
        options = { { label = ('Custom plate ($%d)'):format(C.PlateShop.price), icon = 'tag', event = 'veyl_vehicles:plateShop' } } })
    blip(C.PlateShop.coords, 525, 3, 'Plate shop')
    exports.veyl_interact:AddPed({ id = 'veyl_insurance', model = C.Insurance.model, coords = C.Insurance.coords, radius = 2.5,
        label = 'Insurance', scenario = 'WORLD_HUMAN_CLIPBOARD', icon = 'shield',
        options = { { label = 'Vehicle insurance', icon = 'shield', event = 'veyl_vehicles:insurance' } } })
    blip(C.Insurance.coords, 498, 2, 'Vehicle insurance')
end)
