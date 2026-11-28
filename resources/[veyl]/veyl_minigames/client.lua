-- veyl_minigames client: the lockpick mini game. Other resources call it with a callback (an export cannot yield):
--   exports.veyl_minigames:Lockpick({ difficulty = 'easy'|'medium'|'hard', pins?, misses?, title?, subtitle? }, function(success) end)
-- To wait for the result inside a thread:
--   local p = promise.new()
--   exports.veyl_minigames:Lockpick({ difficulty = 'hard' }, function(ok) p:resolve(ok) end)
--   local success = Citizen.Await(p)

-- Each game is its own screen on the same page: 'lockpick' (pins), 'tumbler' (slip a car lock) and 'hotwire' (reconnect the ignition wires).
local pending = {}
local screens = {}

-- All the games share one page, but every vlib screen registers its own 'ui:ready' callback and the last one wins, so only that screen would
-- ever see the page load. One handler of our own marks every screen ready (and remembers it for screens made later).
local pageReady = false
local loadedAt = GetGameTimer()
RegisterNUICallback('ui:ready', function(_, cb)
    pageReady = true
    for _, sc in pairs(screens) do sc.ready = true end
    cb({ ok = true })
end)

local function screenFor(mode)
    if not screens[mode] then
        screens[mode] = vlib.createScreen({ name = mode, closeOnDeath = true, onClose = function()
            local pp = pending[mode]
            pending[mode] = nil
            if pp then pp:resolve(false) end
        end })
        -- createScreen registered its own ui:ready; take the callback back so all screens are marked.
        RegisterNUICallback('ui:ready', function(_, cb)
            pageReady = true
            for _, sc in pairs(screens) do sc.ready = true end
            cb({ ok = true })
        end)
        -- The same goes for 'close' (Esc): close whichever game is open, not just the last screen made.
        RegisterNUICallback('close', function(_, cb)
            cb({ ok = true })
            for _, sc in pairs(screens) do if sc.visible then sc:close('player') end end
        end)
        -- The page announces itself once, at load; a screen made later never hears it. By now the page has long been up.
        if pageReady or GetGameTimer() - loadedAt > 8000 then screens[mode].ready = true end
    end
    return screens[mode]
end

local function run(mode, action, opts)
    if next(pending) then return false end
    pending[mode] = promise.new()
    local p = pending[mode]
    local ok = screenFor(mode):open(action, type(opts) == 'table' and opts or {})
    if not ok then pending[mode] = nil return false end
    return Citizen.Await(p) == true
end

local function lockpick(opts) return run('lockpick', 'lockpick:open', opts) end

RegisterNUICallback('result', function(data, cb)
    cb({ ok = true })
    local mode = type(data) == 'table' and type(data.mode) == 'string' and data.mode or 'lockpick'
    local p = pending[mode]
    pending[mode] = nil
    if screens[mode] then screens[mode]:close('done') end
    if p then p:resolve(type(data) == 'table' and data.success == true) end
end)

local function export(name, fn)
    exports(name, function(opts, cb)
        CreateThread(function()
            local ok = fn(opts)
            if type(cb) == 'function' or type(cb) == 'table' then cb(ok) end
        end)
    end)
end
export('Lockpick', lockpick)
--- CarLockpick({ difficulty, rounds?, title?, subtitle? }, cb): slip a car door lock (hit the green zone with a moving needle).
export('CarLockpick', function(opts) return run('tumbler', 'tumbler:open', opts) end)
--- Hotwire({ difficulty, wires?, seconds?, title?, subtitle? }, cb): reconnect the ignition wires to the right terminals before time runs out.
export('Hotwire', function(opts) return run('hotwire', 'hotwire:open', opts) end)
exports('IsActive', function() return next(pending) ~= nil end)

-- /lockpicktest [easy|medium|hard] to try it out.
RegisterCommand('lockpicktest', function(_, args)
    CreateThread(function()
        local ok = lockpick({ difficulty = args[1] or 'medium', title = 'Practice lock' })
        Veyl.Notify(ok and 'Unlocked!' or 'The pick broke', ok and 'success' or 'error')
    end)
end, false)

RegisterCommand('tumblertest', function(_, args) CreateThread(function() local ok = run('tumbler', 'tumbler:open', { difficulty = args[1] or 'medium' }) Veyl.Notify(ok and 'Click!' or 'The pick snapped', ok and 'success' or 'error') end) end, false)
RegisterCommand('hotwiretest', function(_, args) CreateThread(function() local ok = run('hotwire', 'hotwire:open', { difficulty = args[1] or 'medium' }) Veyl.Notify(ok and 'The engine turns over' or 'Shorted out', ok and 'success' or 'error') end) end, false)
