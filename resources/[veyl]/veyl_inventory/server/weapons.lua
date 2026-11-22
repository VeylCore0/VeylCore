-- Weapons (server): using a weapon item draws or holsters it; ammo is the player's ammo items and is used up as they
-- shoot. Every 2 s the server checks the drawn weapon is still in their pockets (dropped, given away, searched,
-- confiscated -> taken out of their hands) and keeps the ammo in the gun equal to the ammo items they carry.

local equipped = {}  -- [src] = item name
local lastAmmo = {}  -- [src] = ammo count last sent
local equippedMeta = {} -- [src] = metadata of the drawn weapon item (serial, attachments)

local function notify(src, msg, kind) TriggerClientEvent('veyl_ui:notify', src, { message = msg, type = kind or 'info' }) end
local function count(src, item) return exports[GetCurrentResourceName()]:GetItemCount(src, item) or 0 end

local function send(src, name, meta)
    local w = name and WeaponDefs and WeaponDefs[name]
    if not w then
        equipped[src], lastAmmo[src], equippedMeta[src] = nil, nil, nil
        TriggerClientEvent('veyl_inventory:weapon', src, nil)
        return
    end
    local ammo = w.ammo and count(src, w.ammo) or 0
    equipped[src], lastAmmo[src], equippedMeta[src] = name, ammo, meta or {}
    local atts = {}
    for _, a in ipairs(type(meta) == 'table' and type(meta.attachments) == 'table' and meta.attachments or {}) do
        local def = AttachmentDefs and AttachmentDefs[a]
        if def then atts[#atts + 1] = { name = a, components = def.components, perWeapon = def.perWeapon } end
    end
    TriggerClientEvent('veyl_inventory:weapon', src, { item = name, hash = w.hash, ammo = ammo, ammoItem = w.ammo, label = w.label,
        serial = type(meta) == 'table' and meta.serial or nil, attachments = atts })
end

Use.RegisterHandler('weapon', function(ctx)
    local src = ctx.source
    if equipped[src] == ctx.item then return send(src, nil) end
    local st = Player(src).state
    if st.medical or st.cuffed then return end
    if GetVehiclePedIsIn(GetPlayerPed(src), false) ~= 0 and not (WeaponDefs[ctx.item] and WeaponDefs[ctx.item].ammo) then return end
    send(src, ctx.item, ctx.metadata)
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

---------------------------------------------------------------------------
-- Attachments: stored on the weapon item (metadata.attachments), fitted every time it is drawn
---------------------------------------------------------------------------
local function setWeaponMeta(src, name, old, new)
    if not exports[GetCurrentResourceName()]:RemoveItem(src, name, 1, old) then return false end
    if exports[GetCurrentResourceName()]:AddItem(src, name, 1, new) then return true end
    exports[GetCurrentResourceName()]:AddItem(src, name, 1, old) -- put it back as it was
    return false
end

Use.RegisterHandler('weapon_attachment', function(ctx)
    local src = ctx.source
    if not equipped[src] then return notify(src, 'Draw the weapon you want to fit it to first', 'error') end
    local def = AttachmentDefs[ctx.item]
    if not def then return end
    TriggerClientEvent('veyl_inventory:weapon:tryAttach', src, ctx.item, { components = def.components, perWeapon = def.perWeapon })
end, GetCurrentResourceName())

-- The client confirms the drawn weapon accepts the attachment (only the client can check components).
RegisterNetEvent('veyl_inventory:weapon:attach', function(att)
    local src = source
    local name, meta = equipped[src], equippedMeta[src]
    if not name or type(att) ~= 'string' or not AttachmentDefs[att] then return end
    if count(src, att) < 1 then return end
    local list = type(meta.attachments) == 'table' and meta.attachments or {}
    for _, a in ipairs(list) do if a == att then return notify(src, 'It already has one', 'error') end end
    local new = {}
    for k, v in pairs(meta) do new[k] = v end
    new.attachments = { table.unpack(list) }
    new.attachments[#new.attachments + 1] = att
    if not exports[GetCurrentResourceName()]:RemoveItem(src, att, 1) then return end
    if not setWeaponMeta(src, name, meta, new) then
        exports[GetCurrentResourceName()]:AddItem(src, att, 1)
        return notify(src, 'Could not fit it', 'error')
    end
    send(src, name, new)
    notify(src, ('%s fitted'):format(AttachmentDefs[att].label), 'success')
end)

-- /removeattachments: take every attachment off the drawn weapon (back into your pockets).
RegisterCommand('removeattachments', function(src)
    local name, meta = equipped[src], equippedMeta[src]
    if not name or type(meta.attachments) ~= 'table' or #meta.attachments == 0 then
        return notify(src, 'Draw a weapon with attachments first', 'error')
    end
    local new = {}
    for k, v in pairs(meta) do if k ~= 'attachments' then new[k] = v end end
    if not setWeaponMeta(src, name, meta, new) then return end
    for _, a in ipairs(meta.attachments) do exports[GetCurrentResourceName()]:AddItem(src, a, 1) end
    send(src, name, new)
    notify(src, 'Attachments removed', 'success')
end, false)
