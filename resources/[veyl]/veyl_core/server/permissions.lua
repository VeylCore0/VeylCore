-- veyl_core permissions: ACE-backed checks and a QB-style command registry.
-- HasPermission(src, 'admin') checks the ACE 'veyl.admin'. The console (source 0) is always allowed.

Permissions = {}
Commands = { List = {} }

function Permissions.Has(src, permission)
    src = tonumber(src)
    if src == 0 then return true end
    if not src or type(permission) ~= 'string' then return false end
    if permission == 'user' then return true end
    return IsPlayerAceAllowed(src, 'veyl.' .. permission)
end

--- Commands.Add(name, help, arguments, argsRequired, callback(source, args, raw), permission?)
--- permission nil/'user' = everyone; otherwise checked with HasPermission before callback runs.
function Commands.Add(name, help, arguments, argsRequired, callback, permission)
    if type(name) == 'table' then
        for _, n in ipairs(name) do Commands.Add(n, help, arguments, argsRequired, callback, permission) end
        return
    end
    name = tostring(name):lower()
    permission = permission or 'user'
    Commands.List[name] = { name = name, help = help, arguments = arguments or {}, argsrequired = argsRequired, permission = permission }
    RegisterCommand(name, function(src, args, raw)
        if not Permissions.Has(src, permission) then
            exports.veyl_core:Audit(src, 'veyl_core', 'command_denied', { command = name })
            if src > 0 then TriggerClientEvent('veyl_ui:notify', src, { message = 'You do not have permission to use this command.', type = 'error' }) end
            return
        end
        if argsRequired and #args < #(arguments or {}) then
            if src > 0 then TriggerClientEvent('veyl_ui:notify', src, { message = 'Missing arguments: /' .. name, type = 'error' }) end
            return
        end
        callback(src, args, raw)
    end, false)
end

function Commands.Refresh() end -- chat suggestions are not managed by VeylCore yet
