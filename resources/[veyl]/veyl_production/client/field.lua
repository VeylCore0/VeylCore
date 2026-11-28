-- Field zones: a prop at every searchable point near you, with a Search option. The server decides everything (distance on the ground
-- plane, the per-point and per-player cooldowns, the reward); a searched point just hides here for a while so you do not see it as available.

local C = ProductionConfig
local spawned = {}  -- ["zone:index"] = entity
local hidden = {}   -- ["zone:index"] = until (game timer)
local busy = false
local OPTION = 'veyl_prod_field_search'
local STREAM_IN, STREAM_OUT = 60.0, 80.0

local function search(zone, idx)
    if busy then return end
    busy = true
    local start = Veyl.CallbackTimeout('veyl_production', 'gatherStart', 15000, zone.id, idx)
    if not start.ok then
        busy = false
        if start.code == 'COOLDOWN' then hidden[zone.id .. ':' .. idx] = GetGameTimer() + 120000 end
        return Veyl.NotifyResult(start)
    end
    local done = vlib.progress({ label = 'Searching', duration = start.data.durationMs, canCancel = true, disable = { move = true, car = true, combat = true },
        anim = { dict = 'amb@world_human_gardener_plant@male@base', clip = 'base', flag = 1 } })
    ClearPedTasks(PlayerPedId())
    if not done then busy = false return Veyl.Notify('Stopped', 'info') end
    local res = Veyl.CallbackTimeout('veyl_production', 'gatherFinish', 15000, start.data.token)
    hidden[zone.id .. ':' .. idx] = GetGameTimer() + 120000
    busy = false
    Veyl.NotifyResult(res)
end

local function despawn(key)
    local e = spawned[key]
    if not e then return end
    if GetResourceState('veyl_target') == 'started' then pcall(function() exports.veyl_target:removeLocalEntity(e, { OPTION }) end) end
    if DoesEntityExist(e) then DeleteEntity(e) end
    spawned[key] = nil
end

local function sync()
    local pc = GetEntityCoords(PlayerPedId())
    for _, z in ipairs((C.Field and C.Field.Zones) or {}) do
        if C.Branches[z.branch or 'field'] and C.Branches[z.branch or 'field'].enabled then
            for idx, p in ipairs(z.points) do
                local key = z.id .. ':' .. idx
                local d = #(vector2(pc.x, pc.y) - vector2(p.x, p.y))
                local gone = (hidden[key] or 0) > GetGameTimer()
                if spawned[key] and (gone or d > STREAM_OUT or ProdClient.inside) then despawn(key) end
                if not spawned[key] and not gone and not ProdClient.inside and d <= STREAM_IN then
                    local hash = joaat(z.prop or 'prop_plant_fern_01')
                    if not IsModelInCdimage(hash) then hash = joaat(C.Botanical.FallbackProp) end
                    RequestModel(hash)
                    local deadline = GetGameTimer() + 3000
                    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(10) end
                    if HasModelLoaded(hash) then
                        local e = CreateObject(hash, p.x, p.y, p.z, false, false, false)
                        PlaceObjectOnGroundProperly(e)
                        FreezeEntityPosition(e, true)
                        SetModelAsNoLongerNeeded(hash)
                        spawned[key] = e
                        if GetResourceState('veyl_target') == 'started' then
                            exports.veyl_target:addLocalEntity(e, { { name = OPTION, label = 'Search', icon = 'search', distance = 2.2,
                                canInteract = function() return not busy end,
                                onSelect = function() CreateThread(function() search(z, idx) end) end } })
                        end
                    end
                end
            end
        end
    end
end

CreateThread(function()
    while not Veyl.IsLoaded() do Wait(1000) end
    while GetResourceState('veyl_target') ~= 'started' do Wait(500) end
    while true do Wait(2500) sync() end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for key in pairs(spawned) do despawn(key) end
end)
