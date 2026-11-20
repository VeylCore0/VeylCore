-- veyl_lib server host: notifications from the server and callback cleanup on disconnect.

exports('Notify', function(src, data)
    if type(data) ~= 'table' then return end
    TriggerClientEvent('veyl_lib:notify', src, data)
end)

print('^5[veyl_lib] ready (v0.3.0)^7')
