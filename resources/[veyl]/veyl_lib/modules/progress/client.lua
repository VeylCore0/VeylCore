-- vlib.progress({ label, duration, canCancel?, disable? = { move, car, combat }, anim? = { dict, clip, flag },
--                prop? = { model, bone?, pos?, rot? } }) -> true (completed) | false (cancelled/busy)
-- A client-side "true" is never proof for a valuable reward: servers re-validate (e.g. elapsed time).
return {
    progress = function(opts)
        local p = promise.new()
        exports.veyl_lib:StartProgress(opts or {}, function(done) p:resolve(done == true) end)
        return Citizen.Await(p)
    end,
    progressActive = function() return exports.veyl_lib:IsProgressActive() end,
    cancelProgress = function() exports.veyl_lib:CancelProgress() end,
}
