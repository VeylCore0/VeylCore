-- veyl_spawn server: chooses the spawn point from core PlayerData and tracks death state in core metadata.
-- Position persistence itself is owned by veyl_core (PlayerData.position).

Veyl.Startup({ 'veyl_core' }, function() return true end)

local function validPosition(c)
    return type(c) == 'table' and tonumber(c.x) and tonumber(c.y) and tonumber(c.z)
        and math.abs(c.x) < 10000 and math.abs(c.y) < 10000 and c.z > -100 and c.z < 2000
end

--- Optional: veyl_apartments decides where a character who logged out inside a home comes back (inside again if they
--- still have access, otherwise at that room's door). Returns nil when it has no opinion.
local function apartmentSpawn(src, position, mode)
    if GetResourceState('veyl_apartments') ~= 'started' then return nil end
    local ok, res = pcall(function() return exports.veyl_apartments:ResolveSpawn(src, position, mode) end)
    if ok and type(res) == 'table' and validPosition(res) then return res end
    return nil
end

Veyl.RegisterCallback('getSpawn', function(src)
    local pd = Veyl.GetPlayerData(src)
    if not pd then return Veyl.Err('NO_CHARACTER', 'No character loaded') end
    -- Configured rule: a character that logged out dead/downed comes back at the hospital.
    if pd.metadata.isdead or pd.metadata.inlaststand then
        local h = SpawnConfig.HospitalSpawn
        exports.veyl_core:SetMetadataMany(src, { isdead = false, inlaststand = false })
        apartmentSpawn(src, pd.position, 'hospital') -- clears any "inside a home" record
        return Veyl.Ok({ x = h.x, y = h.y, z = h.z, heading = h.w, isNew = false, reason = 'hospital' })
    end
    local apt = apartmentSpawn(src, pd.position, 'normal')
    if apt then return Veyl.Ok({ x = apt.x, y = apt.y, z = apt.z, heading = apt.heading or 0.0, isNew = false, reason = apt.reason }) end
    if validPosition(pd.position) then
        return Veyl.Ok({ x = pd.position.x, y = pd.position.y, z = pd.position.z, heading = pd.position.w or 0.0, isNew = false })
    end
    local d = SpawnConfig.DefaultSpawn
    return Veyl.Ok({ x = d.x, y = d.y, z = d.z, heading = d.w, isNew = true })
end, { cooldown = 1000 })

-- Death is reported by the client but confirmed against the server-side ped health.
RegisterNetEvent('veyl_spawn:died', function()
    local src = source
    if not Veyl.GetCitizenId(src) then return end
    local ped = GetPlayerPed(src)
    if ped ~= 0 and GetEntityHealth(ped) <= 0 then
        exports.veyl_core:SetMetadata(src, 'isdead', true)
    end
end)

RegisterNetEvent('veyl_spawn:respawned', function()
    local src = source
    local citizenid = Veyl.GetCitizenId(src)
    if not citizenid then return end
    local pd = Veyl.GetPlayerData(src)
    if not pd or not pd.metadata.isdead then return end -- only a recorded death can be "respawned"
    exports.veyl_core:SetMetadata(src, 'isdead', false)
    TriggerEvent('veyl:playerRespawned', src, citizenid)
end)
