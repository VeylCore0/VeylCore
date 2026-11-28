-- Request hygiene: argument checks, distance checks and per-player cooldowns. Callbacks are already rate limited by
-- Veyl.RegisterCallback; this adds action cooldowns (stored, so they survive reconnects) and records forged requests.

Prod = Prod or {}
Prod.Sec = {}
local Sec = Prod.Sec
local strikes = {}

function Sec.int(v, max)
    v = tonumber(v)
    if not v or v ~= math.floor(v) or v < 0 or (max and v > max) then return nil end
    return math.floor(v)
end

function Sec.str(v, max, pattern)
    if type(v) ~= 'string' or #v == 0 or #v > (max or 64) then return nil end
    if pattern and not v:match(pattern) then return nil end
    return v
end

--- A forged request: counted, recorded and (after a few) flagged loudly.
function Sec.invalid(src, cid, reason, data)
    local s = strikes[cid]
    if not s or os.time() - s.at > 60 then s = { n = 0, at = os.time() } strikes[cid] = s end
    s.n = s.n + 1
    Prod.Log.suspicious(src, cid, reason, data)
end

--- Is the player within `max` metres of `point`? (vector3 or { x, y, z }). The server's own coordinates decide.
function Sec.near(src, point, max)
    local pc = Veyl.GetPlayerCoords(src)
    if not pc or not point then return false end
    return ProdUtil.distance(pc, point) <= max
end

-- Cooldowns -----------------------------------------------------------------------------------------------------------
local cool = {} -- [cid] = { [key] = until }

local function load(cid)
    if cool[cid] then return cool[cid] end
    local t = {}
    for _, r in ipairs(MySQL.query.await('SELECT ckey, until_at FROM veyl_prod_cooldowns WHERE citizenid = ? AND until_at > ?', { cid, os.time() }) or {}) do t[r.ckey] = r.until_at end
    cool[cid] = t
    return t
end

function Sec.cooldownLeft(cid, key)
    local left = (load(cid)[key] or 0) - os.time()
    return left > 0 and left or 0
end

--- Starts a cooldown. Persisted for long ones (>= 60 s) so a reconnect does not clear them.
function Sec.setCooldown(cid, key, seconds)
    if seconds <= 0 then return end
    local untilAt = os.time() + seconds
    load(cid)[key] = untilAt
    if seconds >= 60 then
        MySQL.update('INSERT INTO veyl_prod_cooldowns (citizenid, ckey, until_at) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE until_at = VALUES(until_at)', { cid, key, untilAt })
    end
end

--- Returns true (and starts the cooldown) if the action may happen now.
function Sec.try(cid, key, seconds)
    if Sec.cooldownLeft(cid, key) > 0 then return false end
    Sec.setCooldown(cid, key, seconds)
    return true
end

AddEventHandler('playerDropped', function()
    local cid = Veyl.GetCitizenId(source)
    if cid then cool[cid] = nil strikes[cid] = nil end
end)
