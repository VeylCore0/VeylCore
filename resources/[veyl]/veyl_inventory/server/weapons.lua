-- Weapons (server): using a weapon item draws or holsters it; ammo is the player's ammo items and is used up as they
-- shoot. Every 2 s the server checks the drawn weapon is still in their pockets (dropped, given away, searched,
-- confiscated -> taken out of their hands) and keeps the ammo in the gun equal to the ammo items they carry.

local equipped = {}  -- [src] = item name
local lastAmmo = {}  -- [src] = ammo count last sent

local function count(src, item) return exports[GetCurrentResourceName()]:GetItemCount(src, item) or 0 end

local function send(src, name)
    local w = name and WeaponDefs and WeaponDefs[name]
    if not w then
        equipped[src], lastAmmo[src] = nil, nil
        TriggerClientEvent('veyl_inventory:weapon', src, nil)
        return
    end
    local ammo = w.ammo and count(src, w.ammo) or 0
    equipped[src], lastAmmo[src] = name, ammo
    TriggerClientEvent('veyl_inventory:weapon', src, { item = name, hash = w.hash, ammo = ammo, ammoItem = w.ammo, label = w.label })
end

Use.RegisterHandler('weapon', function(ctx)
    local src = ctx.source
    if equipped[src] == ctx.item then return send(src, nil) end
    local st = Player(src).state
    if st.medical or st.cuffed then return end
    if GetVehiclePedIsIn(GetPlayerPed(src), false) ~= 0 and not (WeaponDefs[ctx.item] and WeaponDefs[ctx.item].ammo) then return end
    send(src, ctx.item)
end, GetCurrentResourceName())

RegisterNetEvent('veyl_inventory:weapon:fired', function(n)
    local src = source
    local name = equipped[src]
    local w = name and WeaponDefs[name]
    if not w or not w.ammo then return end
    n = math.floor(tonumber(n) or 0)
    if n < 1 then return end
    n = math.min(n, 120, count(src, w.ammo))
    if n > 0 then exports[GetCurrentResourceName()]:RemoveItem(src, w.ammo, n) end
end)

RegisterNetEvent('veyl_inventory:weapon:holster', function()
    local src = source
    if equipped[src] then send(src, nil) end
end)

CreateThread(function()
    while true do
        Wait(2000)
        for src, name in pairs(equipped) do
            if not GetPlayerName(src) then
                equipped[src], lastAmmo[src] = nil, nil
            elseif count(src, name) < 1 then
                send(src, nil)
            else
                local w = WeaponDefs[name]
                if w.ammo then
                    local n = count(src, w.ammo)
                    if n ~= lastAmmo[src] then
                        lastAmmo[src] = n
                        TriggerClientEvent('veyl_inventory:weapon:ammo', src, n)
                    end
                end
            end
        end
    end
end)

AddEventHandler('playerDropped', function() equipped[source], lastAmmo[source] = nil, nil end)
exports('GetEquippedWeapon', function(src) return equipped[tonumber(src)] end)
