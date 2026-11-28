-- Logging and suspicious-activity records.

Boost = Boost or {}
Boost.Log = {}

function Boost.Log.debug(fmt, ...)
    if BoostingConfig.Debug then print(('[veyl_boosting] ' .. fmt):format(...)) end
end

--- A durable record of something that happened (contract events, rewards, rank changes).
function Boost.Log.audit(cid, event, data, src)
    if BoostingConfig.LogAuditToDatabase then
        MySQL.insert('INSERT INTO veyl_boost_audit (citizenid, event, data) VALUES (?, ?, ?)', { cid or 'system', event, json.encode(data or {}) })
    end
    if src then Veyl.Audit(src, 'boost_' .. event, data or {}) end
end

--- Something that should not happen from a normal client: a forged request, a stale token, a replay. It is recorded, never trusted.
function Boost.Log.suspicious(src, cid, reason, data)
    Boost.Log.audit(cid, 'suspicious', { reason = reason, data = data }, src)
    print(('^3[veyl_boosting] suspicious: %s (src %s, %s)^7'):format(reason, tostring(src), tostring(cid)))
end
