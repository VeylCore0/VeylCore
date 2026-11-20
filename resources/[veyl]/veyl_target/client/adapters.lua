-- Optional data adapters for display filters. When a provider is missing, options that NEED its data stay
-- hidden (unavailable never means unrestricted). No manifest dependency on core or inventory.

Adapters = { groups = nil, items = nil }

-- Groups from VeylCore PlayerData (jobs/gangs memberships), kept current by events.
local function setGroups(pd)
    if type(pd) ~= 'table' or not pd.citizenid then Adapters.groups = nil return end
    local g = {}
    for name, grade in pairs(pd.jobs or {}) do g[name] = grade end
    for name, grade in pairs(pd.gangs or {}) do g[name] = grade end
    Adapters.groups = g
    Adapters.duty = pd.job and pd.job.onduty or false
end

RegisterNetEvent('VeylCore:Player:SetPlayerData', setGroups)
RegisterNetEvent('VeylCore:Client:OnPlayerUnload', function() Adapters.groups = nil Adapters.items = nil end)

-- Item counts pushed by veyl_inventory's client whenever the player's inventory changes.
AddEventHandler('veyl_inventory:client:counts', function(counts) Adapters.items = counts end)

CreateThread(function()
    if GetResourceState('veyl_core') == 'started' then
        local ok, pd = pcall(function() return exports.veyl_core:GetPlayerData() end)
        if ok then setGroups(pd) end
    end
    if GetResourceState('veyl_inventory') == 'started' then
        local ok, counts = pcall(function() return exports.veyl_inventory:GetItemCounts() end)
        if ok and type(counts) == 'table' then Adapters.items = counts end
    end
end)

--- groups: 'police' | { 'police', 'ambulance' } | { police = 2 }
function Adapters.hasGroups(filter)
    if not filter then return true end
    local g = Adapters.groups
    if not g then return false end
    if type(filter) == 'string' then return g[filter] ~= nil end
    if filter[1] ~= nil then
        for _, n in ipairs(filter) do if g[n] ~= nil then return true end end
        return false
    end
    for name, min in pairs(filter) do
        if g[name] ~= nil and g[name] >= (tonumber(min) or 0) then return true end
    end
    return false
end

--- items: 'lockpick' | { 'a', 'b' } (all, count >= 1) | { lockpick = 2 }
function Adapters.hasItems(filter)
    if not filter then return true end
    local c = Adapters.items
    if not c then return false end
    if type(filter) == 'string' then return (c[filter] or 0) > 0 end
    if filter[1] ~= nil then
        for _, n in ipairs(filter) do if (c[n] or 0) < 1 then return false end end
        return true
    end
    for name, count in pairs(filter) do if (c[name] or 0) < count then return false end end
    return true
end
