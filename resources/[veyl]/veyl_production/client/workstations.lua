-- Workstations in the world: bench props near you, with target options to use (opens the bench page) or pack up.

local C = ProductionConfig
local spawned = {}
local OPTIONS = { 'veyl_prod_bench_use', 'veyl_prod_bench_pack' }
local STREAM_IN, STREAM_OUT = 60.0, 80.0
local busy = false

local function openBench(id)
    local r = Veyl.CallbackTimeout('veyl_production', 'wsOpen', 15000, id)
    if not r.ok then return Veyl.NotifyResult(r) end
    ProdClient.open('bench', r.data)
end

local function options(id)
    return {
        { name = OPTIONS[1], label = 'Use workstation', icon = 'gear', distance = 2.2, onSelect = function() CreateThread(function() openBench(id) end) end },
        { name = OPTIONS[2], label = 'Pack up', icon = 'box', distance = 2.2,
          onSelect = function()
              if busy then return end
              busy = true
              CreateThread(function()
                  local ok, err = pcall(function()
                      if vlib.alertDialog({ title = 'Pack up this workstation?', message = 'It goes back into your inventory.', confirmLabel = 'Pack up' }) == 'confirm' then
                          Wait(250) -- let the dialog hand its focus back before the progress bar starts
                          local done = vlib.progress({ label = 'Packing up', duration = C.ActionMs.Pickup, canCancel = true, disable = { move = true, car = true, combat = true },
                              anim = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 49 } })
                          if done then Veyl.NotifyResult(Veyl.CallbackTimeout('veyl_production', 'wsPack', 15000, id)) end
                      end
                  end)
                  -- Whatever happened above, never leave the player stuck in the animation.
                  local ped = PlayerPedId()
                  StopAnimTask(ped, 'mini@repair', 'fixing_a_ped', 1.0)
                  ClearPedTasks(ped)
                  FreezeEntityPosition(ped, false)
                  if not ok then print(('^1[veyl_production] pack up failed: %s^7'):format(tostring(err))) end
                  busy = false
              end)
          end },
    }
end

local function despawn(id)
    local s = spawned[id]
    if not s then return end
    if GetResourceState('veyl_target') == 'started' then pcall(function() exports.veyl_target:removeLocalEntity(s.entity, OPTIONS) end) end
    if DoesEntityExist(s.entity) then DeleteEntity(s.entity) end
    spawned[id] = nil
end

local function sync()
    local pc = GetEntityCoords(PlayerPedId())
    for id, b in pairs(ProdClient.benches) do
        local d = #(pc - vector3(b.x, b.y, b.z))
        local place = (b.property or false) == (ProdClient.inside or false)
        local s = spawned[id]
        if s and (not place or d > STREAM_OUT) then despawn(id) s = nil end
        if not s and place and d <= STREAM_IN and b.model then
            local hash = joaat(b.model)
            if not IsModelInCdimage(hash) then hash = joaat('prop_tool_bench02') end
            RequestModel(hash)
            local deadline = GetGameTimer() + 3000
            while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(10) end
            if HasModelLoaded(hash) then
                local e = CreateObject(hash, b.x, b.y, b.z, false, false, false)
                SetEntityHeading(e, b.heading or 0.0)
                FreezeEntityPosition(e, true)
                SetModelAsNoLongerNeeded(hash)
                spawned[id] = { entity = e }
                if b.use and GetResourceState('veyl_target') == 'started' then exports.veyl_target:addLocalEntity(e, options(id)) end
            end
        end
    end
    for id in pairs(spawned) do if not ProdClient.benches[id] then despawn(id) end end
end

AddEventHandler('veyl_production:benchesChanged', sync)
AddEventHandler('veyl_production:insideChanged', sync)
CreateThread(function()
    while true do Wait(2500) sync() end
end)
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for id in pairs(spawned) do despawn(id) end
end)
