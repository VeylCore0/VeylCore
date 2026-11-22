-- vlib.notify({ id?, type = 'info'|'success'|'warning'|'error', title?, description? | message?, icon?, duration?,
--   layout? = 'standard'|'compact'|'payment', amount?, sound?, showDuration? }) -> id. Never takes focus.
-- A plain string works too: vlib.notify('Saved').
return function(data)
    if type(data) == 'string' then data = { message = data } end
    return exports.veyl_lib:Notify(data)
end
