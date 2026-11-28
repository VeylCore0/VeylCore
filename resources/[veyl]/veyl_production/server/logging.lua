-- Logging: console, the database audit table, and an optional Discord webhook. Each event kind can be turned off in config.
-- Access codes and other secrets are never passed in here.

Prod = Prod or {}
Prod.Log = {}
local L = ProductionConfig.Logging

function Prod.Log.debug(fmt, ...)
    if ProductionConfig.Debug then print(('[veyl_production] ' .. fmt):format(...)) end
end

--- Records something that happened. `kind` is one of the keys in Logging.Events.
function Prod.Log.event(kind, cid, text, data)
    if L.Events[kind] == false then return end
    MySQL.insert('INSERT INTO veyl_prod_audit (citizenid, kind, text, data) VALUES (?, ?, ?, ?)', { cid or 'system', kind, text:sub(1, 200), json.encode(data or {}) })
    if L.Console then print(('[veyl_production] %s %s: %s'):format(kind, tostring(cid or 'system'), text)) end
    if L.Webhook and L.Webhook ~= '' then
        PerformHttpRequest(L.Webhook, function() end, 'POST', json.encode({ username = 'veyl_production', content = ('**%s** %s: %s'):format(kind, tostring(cid or 'system'), text) }),
            { ['Content-Type'] = 'application/json' })
    end
end

--- Something that no honest client sends (a forged id, a bad distance, a replayed token).
function Prod.Log.suspicious(src, cid, reason, data)
    Prod.Log.event('security', cid, 'suspicious: ' .. reason, data)
    if src then Veyl.Audit(src, 'prod_suspicious', { reason = reason }) end
end

--- Recent activity for a player (shown on the dashboard).
function Prod.Log.recent(cid, n)
    return MySQL.query.await("SELECT kind, text, UNIX_TIMESTAMP(created_at) AS at FROM veyl_prod_audit WHERE citizenid = ? AND kind <> 'security' ORDER BY id DESC LIMIT ?", { cid, n or 8 }) or {}
end
