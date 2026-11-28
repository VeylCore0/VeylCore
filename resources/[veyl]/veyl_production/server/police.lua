-- Police: who counts as police, alert rolls, and the optional dispatch adapter. Everything is off until ProductionConfig.Police.Enabled
-- (and, for alerts, Police.Dispatch.Enabled with a running dispatch resource). Raids themselves live in properties.lua.

Prod = Prod or {}
Prod.Police = {}
local Pol = Prod.Police

local function cfg() return ProductionConfig.Police end

function Pol.enabled() return cfg().Enabled == true end

--- Is this player police on duty? (job and duty come from VeylCore's player data.)
function Pol.isPolice(src)
    if not cfg().Enabled then return false end
    local pd = Veyl.GetPlayerData(src)
    if not pd or not pd.job or not pd.job.onduty then return false end
    for _, j in ipairs(cfg().Jobs) do if pd.job.name == j then return true end end
    return false
end

function Pol.onDuty()
    if not cfg().Enabled then return 0 end
    local n = 0
    for _, s in ipairs(GetPlayers()) do if Pol.isPolice(tonumber(s)) then n = n + 1 end end
    return n
end

function Pol.dispatchAvailable()
    local d = cfg().Dispatch
    return cfg().Enabled and d.Enabled and GetResourceState(d.Resource) == 'started'
end

--- Sends a dispatch alert. Returns true if one went out.
function Pol.send(coords, message)
    if not Pol.dispatchAvailable() then return false end
    local d = cfg().Dispatch
    local a = math.random() * 6.2832
    local r = math.random() * d.Radius * 0.6
    local pos = vector3(coords.x + math.cos(a) * r, coords.y + math.sin(a) * r, coords.z)
    return pcall(function()
        exports[d.Resource]:Alert({ services = cfg().Jobs, code = d.Code, title = d.Title, priority = d.Priority, coords = pos,
            message = d.Anonymous and ('Anonymous caller: %s'):format(message) or message, blip = d.Blip })
    end)
end

--- Rolls the alert chance for an activity (plant, harvest, workstation, property_entry).
function Pol.maybeAlert(cid, kind, coords, mult)
    local rule = cfg().Alerts[kind]
    if not rule or not Pol.dispatchAvailable() then return false end
    if math.random() >= rule.chance * (mult or 1) then return false end
    if not Prod.Sec.try(cid, 'alert:' .. kind, rule.cooldown) then return false end
    return Pol.send(coords, ('Suspicious activity reported (%s)'):format(kind))
end
