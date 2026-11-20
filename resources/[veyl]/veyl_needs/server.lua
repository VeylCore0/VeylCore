-- veyl_needs server: authoritative hunger/thirst/stress for loaded characters.

local loaded = {} -- [charId] = { src, hunger, thirst, stress }

Veyl.Startup({ 'veyl_core' }, function()
    return Veyl.Migrate({
        {
            id = '001_needs',
            sql = {
                [[CREATE TABLE IF NOT EXISTS veyl_needs (
                    character_id INT UNSIGNED NOT NULL,
                    hunger TINYINT UNSIGNED NOT NULL DEFAULT 100,
                    thirst TINYINT UNSIGNED NOT NULL DEFAULT 100,
                    stress TINYINT UNSIGNED NOT NULL DEFAULT 0,
                    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                    PRIMARY KEY (character_id)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            },
        },
    })
end)

local function clamp(v) return math.max(0, math.min(100, v)) end

local function push(charId)
    local n = loaded[charId]
    if not n or not GetPlayerName(n.src) then return end
    Player(n.src).state:set('veylNeeds', {
        hunger = math.floor(n.hunger + 0.5), thirst = math.floor(n.thirst + 0.5), stress = math.floor(n.stress + 0.5),
    }, true)
end

local function save(charId)
    local n = loaded[charId]
    if not n then return end
    MySQL.query([[INSERT INTO veyl_needs (character_id, hunger, thirst, stress) VALUES (?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE hunger = VALUES(hunger), thirst = VALUES(thirst), stress = VALUES(stress)]],
        { charId, math.floor(n.hunger + 0.5), math.floor(n.thirst + 0.5), math.floor(n.stress + 0.5) })
end

AddEventHandler('veyl:characterLoaded', function(src, charId)
    CreateThread(function()
        local row = MySQL.single.await('SELECT hunger, thirst, stress FROM veyl_needs WHERE character_id = ?', { charId })
        if Veyl.GetCharacterId(src) ~= charId then return end -- switched while loading
        loaded[charId] = {
            src = src,
            hunger = row and row.hunger or 100, thirst = row and row.thirst or 100, stress = row and row.stress or 0,
        }
        push(charId)
    end)
end)

AddEventHandler('veyl:characterUnloading', function(src, charId)
    save(charId)
    loaded[charId] = nil
    if GetPlayerName(src) then Player(src).state:set('veylNeeds', nil, true) end
end)

AddEventHandler('veyl_inventory:itemUsed', function(src, charId, item, def)
    local n = loaded[charId]
    if not n or type(def) ~= 'table' or type(def.consume) ~= 'table' then return end
    n.hunger = clamp(n.hunger + (tonumber(def.consume.hunger) or 0))
    n.thirst = clamp(n.thirst + (tonumber(def.consume.thirst) or 0))
    n.stress = clamp(n.stress + (tonumber(def.consume.stress) or 0))
    push(charId)
end)

AddEventHandler('veyl:playerRespawned', function(src, charId)
    local n = loaded[charId]
    if not n then return end
    n.hunger = math.max(n.hunger, NeedsConfig.RespawnMinimum)
    n.thirst = math.max(n.thirst, NeedsConfig.RespawnMinimum)
    push(charId)
end)

--- AddStress(characterId, amount) for activities (bounded to +/-25 per call).
exports('AddStress', function(charId, amount)
    local n = loaded[charId]
    amount = tonumber(amount)
    if not n or not amount then return false end
    n.stress = clamp(n.stress + math.max(-25, math.min(25, amount)))
    push(charId)
    return true
end)

exports('GetNeeds', function(charId)
    local n = loaded[charId]
    return n and { hunger = n.hunger, thirst = n.thirst, stress = n.stress } or nil
end)

CreateThread(function()
    local tick = 0
    while true do
        Wait(NeedsConfig.TickMs)
        tick = tick + 1
        for charId, n in pairs(loaded) do
            if Veyl.GetCharacterId(n.src) ~= charId then
                loaded[charId] = nil
            else
                n.hunger = clamp(n.hunger - NeedsConfig.HungerPerTick)
                n.thirst = clamp(n.thirst - NeedsConfig.ThirstPerTick)
                n.stress = clamp(n.stress + NeedsConfig.StressPerTick)
                push(charId)
                if tick % NeedsConfig.SaveEveryTicks == 0 then save(charId) end
            end
        end
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for charId in pairs(loaded) do save(charId) end
end)
