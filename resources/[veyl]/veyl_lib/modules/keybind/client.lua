-- vlib.addKeybind({ name, description, defaultKey = 'F2', defaultMapper = 'keyboard', onPressed?, onReleased? })
-- Rebindable through Settings > Key Bindings > FiveM. Returns { name, isPressed, disabled }.
return function(data)
    if type(data) ~= 'table' or type(data.name) ~= 'string' or data.name:find('%s') then
        error('vlib.addKeybind: name must be a string without spaces', 2)
    end
    local bind = { name = data.name, isPressed = false, disabled = false }
    RegisterCommand('+' .. data.name, function()
        if bind.disabled or IsPauseMenuActive() then return end
        bind.isPressed = true
        if data.onPressed then data.onPressed(bind) end
    end, false)
    RegisterCommand('-' .. data.name, function()
        if not bind.isPressed then return end
        bind.isPressed = false
        if data.onReleased then data.onReleased(bind) end
    end, false)
    RegisterKeyMapping('+' .. data.name, data.description or data.name, data.defaultMapper or 'keyboard', data.defaultKey or '')
    -- While a NUI modal has keyboard focus the game never sees the key release; reset so the bind can't stay "held".
    local function reset()
        if bind.isPressed then
            bind.isPressed = false
            if data.onReleased then data.onReleased(bind) end
        end
    end
    AddEventHandler('veyl_lib:focusReleased', reset)
    AddEventHandler('veyl_lib:focusRevoked', reset)
    return bind
end
