-- Small helpers shared by the server and the client.

PhoneUtil = {}

--- '555-1234', '(555) 1234', 5551234 -> '5551234' (7 digits) or nil.
function PhoneUtil.Normalize(n)
    if type(n) == 'number' then n = ('%d'):format(n) end
    if type(n) ~= 'string' then return nil end
    local digits = n:gsub('%D', '')
    if #digits ~= 7 then return nil end
    return digits
end

--- '5551234' -> '555-1234'
function PhoneUtil.Format(n)
    if type(n) ~= 'string' or #n ~= 7 then return n end
    return n:sub(1, 3) .. '-' .. n:sub(4)
end

--- Trims, removes control characters and angle brackets, caps the length. nil when empty or not a string.
function PhoneUtil.Clean(s, max)
    if type(s) ~= 'string' then return nil end
    s = s:gsub('[%c<>]', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
    if max and #s > max then s = s:sub(1, max) end
    if s == '' then return nil end
    return s
end

--- Like Clean, but keeps line breaks (message and mail bodies).
function PhoneUtil.CleanBody(s, max)
    if type(s) ~= 'string' then return nil end
    s = s:gsub('\r', ''):gsub('[%z\1-\9\11-\31<>]', ' '):gsub('\n\n\n+', '\n\n'):gsub('^%s+', ''):gsub('%s+$', '')
    if max and #s > max then s = s:sub(1, max) end
    if s == '' then return nil end
    return s
end
