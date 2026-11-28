-- Heat: attention on a player. It rises when things go wrong (or loud), cools over real time, can raise pay and hide easy jobs,
-- and can send an alert through the dispatch adapter. All of it is server-side.

Boost = Boost or {}
Boost.Heat = {}
local Heat = Boost.Heat
local H = BoostingConfig.Heat
local lastAlert = {} -- [cid] = os.time()

--- Current heat (0-Max). Cooling is applied from the time elapsed since it last changed, also while the player was offline.
function Heat.value(cid)
    local p = Boost.Prog.get(cid)
    local now = os.time()
    if p.heat > 0 then
        local cooled = (now - p.heatAt) / 60 * H.DecayPerMinute
        p.heat = math.max(0, p.heat - cooled)
    end
    p.heatAt = now
    return p.heat
end

function Heat.level(cid) return BoostingUtil.heatLevel(Heat.value(cid)) end

function Heat.add(cid, amount, reason)
    if amount == 0 then return end
    local p = Boost.Prog.get(cid)
    p.heat = BoostingUtil.clamp(Heat.value(cid) + amount, 0, H.Max)
    Boost.Prog.saveHeat(p)
    Boost.Log.debug('heat %s %+d -> %.1f (%s)', cid, amount, p.heat, tostring(reason))
end

--- Pay multiplier from the player's current heat level.
function Heat.rewardMult(cid) return Heat.level(cid).rewardMult end

--- Whether templates with this difficulty are shown at the player's current heat.
function Heat.allows(cid, difficulty)
    local lvl = Heat.level(cid)
    if BoostingUtil.heatLevelIndex(lvl.id) >= BoostingUtil.heatLevelIndex(H.HideEasyAt) then return difficulty >= H.MinDifficulty end
    return true
end

--- Sends a dispatch alert for the vehicle's area (rate-limited per player). Returns true when one was sent.
function Heat.alert(cid, c, coords)
    local last = lastAlert[cid] or 0
    if os.time() - last < H.AlertCooldownSeconds then return false end
    lastAlert[cid] = os.time()
    return Boost.Dispatch.send(coords, ('Suspicious activity around a %s'):format(c.vehicles[1] and c.vehicles[1].label or 'vehicle'))
end

--- Rolls the contract's alert chance. On a hit: adds heat and tries a dispatch alert. Returns true when it fired.
function Heat.roll(cid, c, coords, why)
    local profile = c.template.heat or {}
    if math.random() >= (profile.chance or 0) then return false end
    Heat.add(cid, profile.gain or 0, why)
    Heat.alert(cid, c, coords)
    return true
end

AddEventHandler('playerDropped', function()
    local cid = Veyl.GetCitizenId(source)
    if cid then lastAlert[cid] = nil end
end)
