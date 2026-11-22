-- veyl_minigames client: the lockpick mini game. Other resources call it with a callback (an export cannot yield):
--   exports.veyl_minigames:Lockpick({ difficulty = 'easy'|'medium'|'hard', pins?, misses?, title?, subtitle? }, function(success) end)
-- To wait for the result inside a thread:
--   local p = promise.new()
--   exports.veyl_minigames:Lockpick({ difficulty = 'hard' }, function(ok) p:resolve(ok) end)
--   local success = Citizen.Await(p)

local pending = nil
local screen = vlib.createScreen({ name = 'lockpick', closeOnDeath = true, onClose = function()
    local p = pending
    pending = nil
    if p then p:resolve(false) end
end })

local function lockpick(opts)
    if pending then return false end
    pending = promise.new()
    local p = pending
    local ok = screen:open('lockpick:open', type(opts) == 'table' and opts or {})
    if not ok then pending = nil return false end
    return Citizen.Await(p) == true
end

RegisterNUICallback('result', function(data, cb)
    cb({ ok = true })
    local p = pending
    pending = nil
    screen:close('done')
    if p then p:resolve(type(data) == 'table' and data.success == true) end
end)

exports('Lockpick', function(opts, cb)
    CreateThread(function()
        local ok = lockpick(opts)
        if type(cb) == 'function' or type(cb) == 'table' then cb(ok) end
    end)
end)
exports('IsActive', function() return pending ~= nil end)

-- /lockpicktest [easy|medium|hard] to try it out.
RegisterCommand('lockpicktest', function(_, args)
    CreateThread(function()
        local ok = lockpick({ difficulty = args[1] or 'medium', title = 'Practice lock' })
        Veyl.Notify(ok and 'Unlocked!' or 'The pick broke', ok and 'success' or 'error')
    end)
end, false)
