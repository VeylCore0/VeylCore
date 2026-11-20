-- veyl_spawn server: owns last-known position per character.

local spawned = {} -- [src] = characterId once the client has finished spawning

Veyl.Startup({ 'veyl_core' }, function()
    return Veyl.Migrate({
        {
            id = '001_positions',
            sql = {
                [[CREATE TABLE IF NOT EXISTS veyl_positions (
                    character_id INT UNSIGNED NOT NULL,
                    x FLOAT NOT NULL, y FLOAT NOT NULL, z FLOAT NOT NULL, heading FLOAT NOT NULL DEFAULT 0,
                    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                    PRIMARY KEY (character_id)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            },
        },
    })
end)

local function validPosition(c)
    return c and math.abs(c.x) < 10000 and math.abs(c.y) < 10000 and c.z > -100 and c.z < 2000
        and not (math.abs(c.x) < 1 and math.abs(c.y) < 1)
end

local function savePosition(src, charId)
    if not charId or spawned[src] ~= charId then return end -- never save the holding position from selection
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return end
    local c = GetEntityCoords(ped)
    if not validPosition(c) then return end
    MySQL.query([[INSERT INTO veyl_positions (character_id, x, y, z, heading) VALUES (?, ?, ?, ?, ?)
        ON DUPLICATE KEY UPDATE x = VALUES(x), y = VALUES(y), z = VALUES(z), heading = VALUES(heading)]],
        { charId, c.x, c.y, c.z, GetEntityHeading(ped) })
end

Veyl.RegisterCallback('getSpawn', function(src, charId)
    spawned[src] = nil
    local row = MySQL.single.await('SELECT x, y, z, heading FROM veyl_positions WHERE character_id = ?', { charId })
    if row and validPosition(row) then
        return Veyl.Ok({ x = row.x, y = row.y, z = row.z, heading = row.heading, isNew = false })
    end
    local d = SpawnConfig.DefaultSpawn
    return Veyl.Ok({ x = d.x, y = d.y, z = d.z, heading = d.w, isNew = row == nil })
end, { cooldown = 1000 })

RegisterNetEvent('veyl_spawn:spawned', function()
    local src = source
    local charId = Veyl.GetCharacterId(src)
    if charId then
        spawned[src] = charId
        TriggerEvent('veyl:playerSpawned', src, charId)
    end
end)

RegisterNetEvent('veyl_spawn:respawned', function()
    local src = source
    local charId = Veyl.GetCharacterId(src)
    if charId and spawned[src] == charId then
        TriggerEvent('veyl:playerRespawned', src, charId)
    end
end)

AddEventHandler('veyl:characterUnloading', function(src, charId)
    savePosition(src, charId)
    spawned[src] = nil
end)

CreateThread(function()
    while true do
        Wait(SpawnConfig.SaveIntervalMs)
        for src, charId in pairs(spawned) do
            if Veyl.GetCharacterId(src) == charId then savePosition(src, charId) else spawned[src] = nil end
        end
    end
end)

exports('IsSpawned', function(src) return spawned[tonumber(src)] ~= nil end)
