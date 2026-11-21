-- veyl_garages client: garage/impound screen, blips, "Open garage" zones and the "Park in garage" vehicle option.

local screen = vlib.createScreen({ name = 'garage' })
local currentPlace = nil

local places = {}
for _, g in ipairs(GaragesConfig.Garages) do places[#places + 1] = { def = g, kind = 'garage' } end
places[#places + 1] = { def = GaragesConfig.Impound, kind = 'impound' }

local function reply(cb, res) cb({ ok = res.ok, code = res.code, message = res.message, data = res.data }) end

--- First clear spawn point of a place (client-side check; the server only accepts indexes from its own config).
local function clearSpawn(def)
    for i, s in ipairs(def.spawns) do
        if not IsPositionOccupied(s.x, s.y, s.z, 2.6, false, true, true, false, false, 0, false) then return i end
    end
    return nil
end

local function openPlace(placeId)
    if screen:isOpen() or not Veyl.IsLoaded() then return end
    local res = Veyl.Callback('veyl_garages', 'list', placeId)
    if not res.ok then return Veyl.NotifyResult(res) end
    currentPlace = placeId
    local ok, reason = screen:open('garage:open', res.data)
    if not ok then Veyl.Notify(reason == 'busy' and 'Close the open menu first.' or 'Garage UI unavailable.', 'warning') end
end

local function defOf(placeId)
    for _, p in ipairs(places) do if p.def.id == placeId then return p.def end end
end

RegisterNUICallback('takeOut', function(data, cb)
    if not screen:isOpen() or type(data) ~= 'table' or not currentPlace then return cb({ ok = false, code = 'INVALID_INPUT' }) end
    local def = defOf(currentPlace)
    local res = Veyl.CallbackTimeout('veyl_garages', 'takeOut', 25000, {
        placeId = currentPlace, ownedId = tonumber(data.ownedId), spawnIndex = clearSpawn(def),
        method = data.method == 'bank' and 'bank' or 'cash', opId = tostring(data.opId or ''),
    })
    reply(cb, res)
    if res.ok then
        screen:close('done')
        Veyl.NotifyResult(res)
    end
end)

AddEventHandler('veyl_garages:open', function(args) if args then CreateThread(function() openPlace(args.id) end) end end)

--- Nearest garage (not the impound lot) within park range of a position.
local function garageNear(pos)
    for _, g in ipairs(GaragesConfig.Garages) do
        if #(pos - g.coords) <= GaragesConfig.ParkRadius then return g end
    end
end

local function park(entity)
    local g = garageNear(GetEntityCoords(entity))
    if not g then return Veyl.Notify('There is no garage nearby', 'error') end
    local props = exports.veyl_vehicles:GetVehicleProperties(entity)
    Veyl.NotifyResult(Veyl.CallbackTimeout('veyl_garages', 'park', 20000, g.id, VehToNet(entity), props))
end

local function isMine(entity)
    local st = Entity(entity).state
    if not st.veylOwnedId then return false end
    local keys, me = st.veylKeys, Veyl.GetCitizenId()
    for _, cid in ipairs(keys or {}) do if cid == me then return true end end
    return false
end

CreateThread(function()
    for _, p in ipairs(places) do
        local b = GaragesConfig.Blips[p.kind]
        local blip = AddBlipForCoord(p.def.coords.x, p.def.coords.y, p.def.coords.z)
        SetBlipSprite(blip, b.sprite)
        SetBlipColour(blip, b.colour)
        SetBlipScale(blip, b.scale)
        SetBlipAsShortRange(blip, true)
        BeginTextCommandSetBlipName('STRING')
        AddTextComponentSubstringPlayerName(p.kind == 'impound' and p.def.label or 'Garage')
        EndTextCommandSetBlipName(blip)
    end
    while GetResourceState('veyl_interact') ~= 'started' do Wait(200) end
    for _, p in ipairs(places) do
        exports.veyl_interact:AddZone({
            id = 'garage_' .. p.def.id, coords = p.def.coords, radius = GaragesConfig.UseRadius,
            icon = p.kind == 'impound' and 'lock' or 'car', title = p.def.label,
            label = p.kind == 'impound' and 'Impounded vehicles' or 'Open garage',
            event = 'veyl_garages:open', args = { id = p.def.id },
        })
    end
    while GetResourceState('veyl_target') ~= 'started' do Wait(500) end
    exports.veyl_target:addGlobalVehicle({
        { name = 'veyl_garage_park', label = 'Park in garage', icon = 'car', distance = 3.0, priority = 3,
          canInteract = function(entity)
              return isMine(entity) and GetVehicleNumberOfPassengers(entity) == 0 and IsVehicleSeatFree(entity, -1)
                  and garageNear(GetEntityCoords(entity)) ~= nil
          end,
          onSelect = function(data) if data and data.entity then CreateThread(function() park(data.entity) end) end end },
    })
end)
