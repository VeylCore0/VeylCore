-- Request hygiene. Every callback already runs through Veyl.RegisterCallback (per-player cooldowns, one request at a time per name).
-- This adds a record of requests that no honest client sends, so repeated forgeries stand out in the audit log.

Boost = Boost or {}
Boost.Sec = {}
local strikes = {} -- [cid] = { n, at }

--- Count a rejected-because-forged request. After a few in a short time, record it loudly.
function Boost.Sec.invalid(src, cid, reason, data)
    local s = strikes[cid]
    if not s or os.time() - s.at > 60 then s = { n = 0, at = os.time() } strikes[cid] = s end
    s.n = s.n + 1
    Boost.Log.suspicious(src, cid, reason, data)
    if s.n >= 5 then Boost.Log.audit(cid, 'abuse', { reason = reason, count = s.n }, src) s.n = 0 end
end

--- A positive integer (netIds, server ids, ...), or nil.
function Boost.Sec.int(v, max)
    v = tonumber(v)
    if not v or v ~= math.floor(v) or v < 0 or (max and v > max) then return nil end
    return math.floor(v)
end

--- A short plain string, or nil.
function Boost.Sec.str(v, max)
    if type(v) ~= 'string' or #v == 0 or #v > (max or 64) then return nil end
    return v
end

AddEventHandler('playerDropped', function()
    local cid = Veyl.GetCitizenId(source)
    if cid then strikes[cid] = nil end
end)
