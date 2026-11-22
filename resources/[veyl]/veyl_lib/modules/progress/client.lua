-- vlib.progress({ label, duration, canCancel?, disable? = { move, car, combat }, anim? = { dict, clip, flag },
--                prop? = { model, bone?, pos?, rot? } }) -> true (completed) | false (cancelled/busy)
-- A client-side "true" is never proof for a valuable reward: servers re-validate (e.g. elapsed time).
--   vlib.holdProgress({ label, duration, keyLabel?, control?, subLabel?, decay? }) -> completed, reason
--   Both return completed (true/false) and a reason: 'completed', 'cancelled', 'released', 'busy', 'dead', 'logout',
--   'vehicle', 'moved', 'replaced', 'caller_stopped'.
local function run(export, opts)
    local p = promise.new()
    exports.veyl_lib[export](exports.veyl_lib, opts or {}, function(done, reason) p:resolve({ done == true, reason }) end)
    local r = Citizen.Await(p)
    return r[1], r[2]
end

return {
    progress = function(opts) return run('StartProgress', opts) end,
    holdProgress = function(opts) return run('StartHoldProgress', opts) end,
    progressActive = function() return exports.veyl_lib:IsProgressActive() end,
    cancelProgress = function(id) exports.veyl_lib:CancelProgress(id) end,
}
