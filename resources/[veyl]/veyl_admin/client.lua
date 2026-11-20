-- veyl_admin client: executes staff actions the server has already authorised.

RegisterNetEvent('veyl_admin:list', function(title, lines)
    local items = {}
    for i, l in ipairs(lines or {}) do items[i] = { label = l, value = i } end
    Veyl.UI.Menu({ title = title, items = items, emptyText = 'Nothing to show.' })
end)

RegisterNetEvent('veyl_admin:tpm', function()
    local blip = GetFirstBlipInfoId(8)
    if not DoesBlipExist(blip) then return Veyl.Notify('Set a waypoint first', 'error') end
    local c = GetBlipInfoIdCoord(blip)
    local ped = PlayerPedId()
    local ent = IsPedInAnyVehicle(ped, false) and GetVehiclePedIsIn(ped, false) or ped
    DoScreenFadeOut(250)
    Wait(260)
    for z = 1000.0, 0.0, -25.0 do
        SetEntityCoordsNoOffset(ent, c.x, c.y, z, false, false, false)
        RequestCollisionAtCoord(c.x, c.y, z)
        Wait(20)
        local found, groundZ = GetGroundZFor_3dCoord(c.x, c.y, z, false)
        if found then
            SetEntityCoordsNoOffset(ent, c.x, c.y, groundZ + 1.0, false, false, false)
            break
        end
    end
    DoScreenFadeIn(250)
end)

RegisterNetEvent('veyl_admin:coords', function()
    local ped = PlayerPedId()
    local c, h = GetEntityCoords(ped), GetEntityHeading(ped)
    local text = ('vector4(%.2f, %.2f, %.2f, %.2f)'):format(c.x, c.y, c.z, h)
    print('[veyl_admin] ' .. text)
    Veyl.Notify(text .. '  (also printed to F8 console)', 'info', 10000)
end)

RegisterNetEvent('veyl_admin:revive', function()
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    NetworkResurrectLocalPlayer(c.x, c.y, c.z, GetEntityHeading(ped), true, false)
    ped = PlayerPedId()
    SetEntityHealth(ped, GetEntityMaxHealth(ped))
    ClearPedBloodDamage(ped)
    ClearPedTasksImmediately(ped)
end)
