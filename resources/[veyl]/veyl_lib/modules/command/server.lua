-- vlib.addCommand(name, { help?, restricted? = 'veyl.admin' }, function(source, args, raw) end)
-- `restricted` is checked as an ACE before the handler runs; the handler still validates its own action.
return function(name, opts, handler)
    if type(handler) ~= 'function' then handler, opts = opts, {} end
    opts = opts or {}
    RegisterCommand(name, function(src, args, raw)
        if opts.restricted and src > 0 and not IsPlayerAceAllowed(src, opts.restricted) then
            TriggerClientEvent('veyl_lib:notify', src, { message = 'You do not have permission to use this command.', type = 'error' })
            return
        end
        local ok, err = pcall(handler, src, args, raw)
        if not ok then print(('^1[vlib] command /%s failed: %s^7'):format(name, tostring(err))) end
    end, false)
end
