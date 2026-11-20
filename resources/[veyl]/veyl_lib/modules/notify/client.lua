-- vlib.notify({ title?, message, type = 'info'|'success'|'warning'|'error', duration? }) — never takes focus.
return function(data)
    if type(data) == 'string' then data = { message = data } end
    exports.veyl_lib:Notify(data)
end
