-- veyl_needs server: hunger/thirst/stress live in veyl_core metadata (persisted by the core).
-- This resource only decays them and applies consumable effects.

Veyl.Startup({ 'veyl_core' }, function() return true end)

local function clamp(v) return math.max(0, math.min(100, v)) end

local function applyDeltas(src, deltas)
    local pd = Veyl.GetPlayerData(src)
    if not pd then return end
    local m = pd.metadata
    local values = {}
    for _, key in ipairs({ 'hunger', 'thirst', 'stress' }) do
        if deltas[key] then values[key] = clamp((tonumber(m[key]) or 0) + deltas[key]) end
    end
    if next(values) then exports.veyl_core:SetMetadataMany(src, values) end
end

AddEventHandler('veyl_inventory:itemUsed', function(src, _, item)
    local fx = NeedsConfig.ItemEffects[item]
    if not fx then return end
    applyDeltas(src, fx)
    if fx.heal then TriggerClientEvent('veyl_needs:heal', src, math.min(100, fx.heal)) end
end)

AddEventHandler('veyl:playerRespawned', function(src)
    local pd = Veyl.GetPlayerData(src)
    if not pd then return end
    exports.veyl_core:SetMetadataMany(src, {
        hunger = math.max(pd.metadata.hunger or 0, NeedsConfig.RespawnMinimum),
        thirst = math.max(pd.metadata.thirst or 0, NeedsConfig.RespawnMinimum),
    })
end)

--- AddStress(source, amount) for activities (bounded to +/-25 per call).
exports('AddStress', function(src, amount)
    amount = tonumber(amount)
    if not amount then return false end
    applyDeltas(src, { stress = math.max(-25, math.min(25, amount)) })
    return true
end)

CreateThread(function()
    while true do
        Wait(NeedsConfig.TickMs)
        for _, src in ipairs(exports.veyl_core:GetPlayers()) do
            if exports.veyl_core:IsSpawned(src) then
                applyDeltas(src, { hunger = -NeedsConfig.HungerPerTick, thirst = -NeedsConfig.ThirstPerTick, stress = NeedsConfig.StressPerTick })
            end
        end
    end
end)
