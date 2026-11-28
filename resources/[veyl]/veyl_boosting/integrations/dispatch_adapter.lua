-- Dispatch adapter. VeylCore does not require a dispatch resource: this stays off unless BoostingConfig.Police.Enabled is true
-- AND the configured resource is running and exports `Alert` (veyl_dispatch does: exports.veyl_dispatch:Alert({ services, code, title,
-- message, priority, coords, blip })). Swap the body of `send` to talk to a different dispatch resource.

Boost = Boost or {}
Boost.Dispatch = {}
local D = Boost.Dispatch

local function cfg() return BoostingConfig.Police end

function D.available()
    local p = cfg()
    return p.Enabled == true and p.Resource and GetResourceState(p.Resource) == 'started'
end

--- Police on duty (0 when the adapter is off, so `minPolice` never blocks a server that has no police system).
function D.policeOnline()
    if not cfg().Enabled then return 0 end
    local jobs, n = {}, 0
    for _, j in ipairs(cfg().Jobs or {}) do jobs[j] = true end
    for _, s in ipairs(GetPlayers()) do
        local pd = Veyl.GetPlayerData(tonumber(s))
        if pd and pd.job and pd.job.onduty and jobs[pd.job.name] then n = n + 1 end
    end
    return n
end

--- Sends an alert. `coords` is a vector3; with InvestigationZone the position is blurred inside the configured radius.
function D.send(coords, message, extra)
    if not D.available() then return false end
    local p = cfg()
    local c = coords
    if p.InvestigationZone then
        local a, r = math.random() * 6.2832, math.random() * (p.Radius or 250.0) * 0.6
        c = vector3(coords.x + math.cos(a) * r, coords.y + math.sin(a) * r, coords.z)
    end
    local ok = pcall(function()
        exports[p.Resource]:Alert({
            services = { 'police' }, code = p.Code, title = (extra and extra.title) or p.Title, priority = (extra and extra.priority) or p.Priority,
            coords = c, message = message, blip = p.Blip,
        })
    end)
    return ok
end
