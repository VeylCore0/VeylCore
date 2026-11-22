-- Weapons (client): the drawn weapon comes only from the inventory. Shots are reported so ammo items are used up;
-- weapons from anywhere else (pickups, spawned by the game) are taken away.

local current = nil -- { item, hash, ammo, ammoItem, label }
local UNARMED = `WEAPON_UNARMED`

RegisterNetEvent('veyl_inventory:weapon', function(w)
    local ped = PlayerPedId()
    RemoveAllPedWeapons(ped, true)
    current = w
    if not w then return end
    local hash = joaat(w.hash)
    GiveWeaponToPed(ped, hash, w.ammoItem and (w.ammo or 0) or 1, false, true)
    if w.ammoItem then SetPedAmmo(ped, hash, w.ammo or 0) end
    for _, a in ipairs(w.attachments or {}) do
        local comp = ResolveComponent(hash, w.hash, a)
        if comp then GiveWeaponComponentToPed(ped, hash, comp) end
    end
    SetCurrentPedWeapon(ped, hash, true)
    if w.ammoItem and (w.ammo or 0) == 0 then vlib.notify({ message = ('%s drawn, but you have no ammo for it'):format(w.label), type = 'warning' }) end
end)

RegisterNetEvent('veyl_inventory:weapon:ammo', function(n)
    if not current or not current.ammoItem then return end
    current.ammo = n
    SetPedAmmo(PlayerPedId(), joaat(current.hash), tonumber(n) or 0)
end)

-- Shots: counted every frame while a gun is drawn, reported every 1.5 s.
CreateThread(function()
    local pending, lastSend = 0, 0
    while true do
        if current and current.ammoItem then
            local ped = PlayerPedId()
            if IsPedShooting(ped) then pending = pending + 1 end
            if pending > 0 and GetGameTimer() - lastSend > 1500 then
                TriggerServerEvent('veyl_inventory:weapon:fired', pending)
                pending, lastSend = 0, GetGameTimer()
            end
            Wait(0)
        else
            if pending > 0 then TriggerServerEvent('veyl_inventory:weapon:fired', pending) pending = 0 end
            Wait(250)
        end
    end
end)

-- Housekeeping: holster when downed or cuffed; remove weapons that did not come from the inventory.
CreateThread(function()
    while true do
        Wait(1000)
        local ped = PlayerPedId()
        local st = LocalPlayer.state
        if current and (st.medical or st.cuffed or IsEntityDead(ped)) then
            current = nil
            RemoveAllPedWeapons(ped, true)
            TriggerServerEvent('veyl_inventory:weapon:holster')
        else
            local sel = GetSelectedPedWeapon(ped)
            if sel ~= UNARMED and (not current or sel ~= joaat(current.hash)) and LocalPlayer.state.isLoggedIn then
                RemoveWeaponFromPed(ped, sel)
            end
        end
    end
end)

RegisterNetEvent('VeylCore:Client:OnPlayerUnload', function()
    current = nil
    RemoveAllPedWeapons(PlayerPedId(), true)
end)

exports('GetCurrentWeapon', function() return current end)

--- The first component of an attachment this weapon accepts (or nil).
function ResolveComponent(hash, weaponName, att)
    local list = {}
    for _, c in ipairs(att.components or {}) do list[#list + 1] = c end
    if att.perWeapon then list[#list + 1] = att.perWeapon:format(weaponName:upper():gsub('^WEAPON_', '')) end
    for _, c in ipairs(list) do
        local ch = joaat(c)
        if DoesWeaponTakeWeaponComponent(hash, ch) then return ch end
    end
    return nil
end

RegisterNetEvent('veyl_inventory:weapon:tryAttach', function(item, att)
    if not current then return end
    if ResolveComponent(joaat(current.hash), current.hash, att) then
        TriggerServerEvent('veyl_inventory:weapon:attach', item)
    else
        vlib.notify({ message = ('That does not fit your %s'):format(current.label), type = 'error' })
    end
end)
