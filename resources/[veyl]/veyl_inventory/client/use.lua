-- Item use: server reserves -> client progress -> server completes (validates timing) -> server applies effect.

local using = false
local lastUse = 0

function UseSlot(slot)
    -- The server accepts one use start every 500 ms: ignore repeat presses instead of showing a rate-limit error.
    if using or GetGameTimer() - lastUse < 600 then return end
    lastUse = GetGameTimer()
    using = true
    local start = vlib.callback.await('veyl_inventory:useStart', { timeoutMs = 8000 }, slot)
    if type(start) ~= 'table' or not start.ok then
        using = false
        return vlib.notify({ message = (start and start.message) or 'Could not use that', type = 'error' })
    end
    local d = start.data
    local done = true
    if d.durationMs > 0 then
        done = vlib.progress({ label = d.label, duration = d.durationMs, canCancel = true,
            disable = { move = false, car = false, combat = true }, anim = d.anim, prop = d.prop })
    end
    if done then
        local res = vlib.callback.await('veyl_inventory:useComplete', { timeoutMs = 8000 }, d.useId)
        if type(res) == 'table' and not res.ok then vlib.notify({ message = res.message or 'Could not use that', type = 'error' }) end
    else
        vlib.callback.await('veyl_inventory:useCancel', { timeoutMs = 5000 }, d.useId)
    end
    using = false
end

exports('useSlot', function(slot) CreateThread(function() UseSlot(slot) end) end)

-- Optional heal effect sent by the consume handler.
RegisterNetEvent('veyl_inventory:heal', function(amount)
    local ped = PlayerPedId()
    SetEntityHealth(ped, math.min(GetEntityMaxHealth(ped), GetEntityHealth(ped) + math.min(tonumber(amount) or 0, 100)))
end)
