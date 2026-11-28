-- veyl_scavenge client: every configured trash can, dumpster and garbage bag prop gets a "search" option. The server decides everything.

local C = ScavengeConfig
local busy = false
local picked = {} -- keys the server said are picked over (hides the prompt for a little while)

local function key(kind, c) return ('%s:%d:%d:%d'):format(kind, math.floor(c.x / 2), math.floor(c.y / 2), math.floor(c.z / 2)) end

local function search(kind, def, entity)
    if busy then return end
    busy = true
    local c = GetEntityCoords(entity)
    local k = key(kind, c)
    local start = Veyl.CallbackTimeout('veyl_scavenge', 'searchStart', 15000, kind, c.x, c.y, c.z)
    if not start.ok then
        busy = false
        if start.code == 'COOLDOWN' then picked[k] = GetGameTimer() + 120000 end
        return Veyl.NotifyResult(start)
    end
    TaskTurnPedToFaceEntity(PlayerPedId(), entity, 500)
    Wait(500)
    local done = vlib.progress({ label = 'Searching', duration = start.data.durationMs, canCancel = true,
        disable = { move = true, car = true, combat = true }, anim = start.data.anim })
    ClearPedTasks(PlayerPedId())
    if not done then busy = false return Veyl.Notify('You stop searching', 'info') end
    local res = Veyl.CallbackTimeout('veyl_scavenge', 'searchFinish', 15000, start.data.token)
    picked[k] = GetGameTimer() + 120000
    busy = false
    Veyl.NotifyResult(res)
end

CreateThread(function()
    while GetResourceState('veyl_target') ~= 'started' do Wait(500) end
    for kind, def in pairs(C.Kinds) do
        local models = {}
        for _, m in ipairs(def.Models) do if IsModelInCdimage(joaat(m)) then models[#models + 1] = m end end
        if C.Debug then print(('[veyl_scavenge] %s: %d of %d models available'):format(kind, #models, #def.Models)) end
        exports.veyl_target:addModel(models, {
            { name = 'veyl_scavenge_' .. kind, label = def.label, icon = def.icon, distance = 2.0, priority = 2,
              canInteract = function(e)
                  if busy or GetVehiclePedIsIn(PlayerPedId(), false) ~= 0 then return false end
                  local until_ = picked[key(kind, GetEntityCoords(e))]
                  return not until_ or until_ < GetGameTimer()
              end,
              onSelect = function(d) CreateThread(function() search(kind, def, d.entity) end) end },
        })
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for kind, def in pairs(C.Kinds) do pcall(function() exports.veyl_target:removeModel(def.Models, { 'veyl_scavenge_' .. kind }) end) end
end)
