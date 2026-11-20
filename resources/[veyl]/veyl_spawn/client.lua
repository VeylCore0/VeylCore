-- veyl_spawn client: deterministic, bounded spawn stages. Every failure falls back and fades back in.

local spawning = false
local isDead = false

local function stage(text)
    -- Observable stage for debugging the "stuck on black screen" class of problems.
    print(('[veyl_spawn] %s'):format(text))
end

local function placePlayer(x, y, z, heading)
    local ped = PlayerPedId()
    RequestCollisionAtCoord(x, y, z)
    SetEntityCoordsNoOffset(ped, x, y, z, false, false, false)
    local deadline = GetGameTimer() + SpawnConfig.CollisionTimeoutMs
    while not HasCollisionLoadedAroundEntity(ped) and GetGameTimer() < deadline do
        RequestCollisionAtCoord(x, y, z)
        Wait(50)
    end
    NetworkResurrectLocalPlayer(x, y, z, heading, true, true, false)
    ped = PlayerPedId()
    SetEntityHeading(ped, heading)
    ClearPedTasksImmediately(ped)
    ClearPlayerWantedLevel(PlayerId())
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
end

local function finishSpawn()
    local ped = PlayerPedId()
    SetEntityVisible(ped, true, false)
    SetEntityInvincible(ped, false)
    FreezeEntityPosition(ped, false)
    SetPlayerControl(PlayerId(), true, 0)
    DoScreenFadeIn(600)
end

local function runSpawn(character)
    if spawning then return end
    spawning = true
    isDead = false
    DoScreenFadeOut(300)
    Wait(350)

    stage('appearance')
    local ok = false
    local res = Veyl.Callback('veyl_appearance', 'get')
    local hasAppearance = res.ok and res.data ~= nil
    if hasAppearance then
        ok = Veyl.Await('veyl_appearance', 'Apply', 15000, res.data) == true
    end
    if not ok then
        ok = Veyl.Await('veyl_appearance', 'ApplyDefault', 15000, character and character.sex) == true
        if not ok then Veyl.Notify('Could not load your appearance; using a default model.', 'warning') end
    end

    stage('position')
    local spawn = Veyl.Callback('veyl_spawn', 'getSpawn')
    local d = SpawnConfig.DefaultSpawn
    local pos = (spawn.ok and spawn.data) or { x = d.x, y = d.y, z = d.z, heading = d.w, isNew = false }
    if not spawn.ok then Veyl.Notify('Spawn location unavailable; using the default spawn.', 'warning') end
    placePlayer(pos.x, pos.y, pos.z, pos.heading)

    stage('finish')
    finishSpawn()
    spawning = false
    TriggerServerEvent('veyl_spawn:spawned')
    TriggerEvent('veyl:playerSpawned')

    if not hasAppearance then
        Wait(800)
        exports.veyl_appearance:OpenEditor(character and character.sex, false, function() end)
    end
    if pos.isNew then
        Veyl.Notify('Welcome to VeylCore! Head to the GoPostal depot (map marker) to earn your first paycheck.', 'info', 10000)
    end
end

RegisterNetEvent('veyl:characterLoaded', function(character)
    CreateThread(function()
        local ok, err = pcall(runSpawn, character)
        if not ok then
            print(('^1[veyl_spawn] spawn failed: %s^7'):format(tostring(err)))
            spawning = false
            local dft = SpawnConfig.DefaultSpawn
            pcall(placePlayer, dft.x, dft.y, dft.z, dft.w)
            finishSpawn()
            TriggerServerEvent('veyl_spawn:spawned')
            Veyl.Notify('Spawn hit an error; placed you at the default spawn.', 'error')
        end
    end)
end)

RegisterNetEvent('veyl:characterUnloaded', function()
    isDead = false
end)

---------------------------------------------------------------------------
-- Basic death handling (until veyl_medical exists): timer, then hospital respawn
---------------------------------------------------------------------------
CreateThread(function()
    while true do
        local sleep = 500
        if Veyl.IsLoaded() and not spawning then
            local ped = PlayerPedId()
            if IsEntityDead(ped) and not isDead then
                isDead = true
                local respawnAt = GetGameTimer() + SpawnConfig.RespawnDelaySeconds * 1000
                CreateThread(function()
                    while isDead do
                        local remaining = math.ceil((respawnAt - GetGameTimer()) / 1000)
                        if remaining > 0 then
                            Veyl.HelpText(('You are incapacitated. Respawn available in %ds'):format(remaining))
                        else
                            Veyl.HelpText('Press ~INPUT_CONTEXT~ to respawn at the hospital')
                            if IsControlJustPressed(0, 38) then
                                DoScreenFadeOut(400)
                                Wait(450)
                                local h = SpawnConfig.HospitalSpawn
                                placePlayer(h.x, h.y, h.z, h.w)
                                finishSpawn()
                                isDead = false
                                TriggerServerEvent('veyl_spawn:respawned')
                            end
                        end
                        if not IsEntityDead(PlayerPedId()) then isDead = false end
                        Wait(0)
                    end
                end)
            end
        end
        Wait(sleep)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then DoScreenFadeIn(0) end
end)
