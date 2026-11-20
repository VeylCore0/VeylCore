-- vlib.notify(source, { title?, message, type?, duration? }) from the server.
return function(src, data)
    if type(data) == 'string' then data = { message = data } end
    TriggerClientEvent('veyl_lib:notify', src, data)
end
