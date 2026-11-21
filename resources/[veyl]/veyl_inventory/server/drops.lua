-- Ground drops: temporary inventories at a world position. They use the same durable transfer path as every other
-- inventory (locks, revisions, operation records), are removed when emptied, expire after DropLifetimeMinutes and
-- never survive a restart (cleared at startup).

Drops = { list = {} } -- [id] = { id, invId, coords, bucket, createdAt }

local seq = 0

local function defaults()
    return { type = 'drop', label = 'Ground', slots = InventoryConfig.DropSlots, maxWeight = InventoryConfig.DropMaxWeight }
end

--- View used while no drop exists yet at the player's position (the "Ground" box is empty until something is dropped).
function Drops.PendingView()
    return { ref = 'secondary', id = 'ground', label = 'Ground', type = 'drop', slots = InventoryConfig.DropSlots,
        maxWeight = InventoryConfig.DropMaxWeight, weight = 0, revision = 0, items = {} }
end

function Drops.Inv(d) return Store.Get(d.invId, defaults()) end

local function publicDrop(d) return { id = d.id, coords = d.coords, bucket = d.bucket } end

--- Nearest drop within reach of the player (same routing bucket), or nil.
function Drops.Nearest(src)
    local ped = GetPlayerPed(src)
    if ped == 0 then return nil end
    local pos, bucket = GetEntityCoords(ped), GetPlayerRoutingBucket(src)
    local best, bestDist = nil, InventoryConfig.DropDistance
    for _, d in pairs(Drops.list) do
        if d.bucket == bucket then
            local dist = #(pos - d.coords)
            if dist <= bestDist then best, bestDist = d, dist end
        end
    end
    return best
end

--- True while the player can still reach this drop.
function Drops.CanAccess(src, id)
    local d = Drops.list[id]
    if not d then return false end
    local ped = GetPlayerPed(src)
    if ped == 0 or GetPlayerRoutingBucket(src) ~= d.bucket then return false end
    return #(GetEntityCoords(ped) - d.coords) <= InventoryConfig.DropDistance + 1.5
end

--- Creates an empty drop at the player's feet.
function Drops.Create(src)
    local ped = GetPlayerPed(src)
    if ped == 0 then return nil end
    seq = seq + 1
    local id = ('%x%x%04x'):format(os.time(), seq, math.random(0, 0xffff))
    local c = GetEntityCoords(ped)
    local d = { id = id, invId = 'drop:' .. id, coords = vector3(c.x, c.y, c.z - 0.95), bucket = GetPlayerRoutingBucket(src), createdAt = os.time() }
    if not Drops.Inv(d) then return nil end
    Drops.list[id] = d
    TriggerClientEvent('veyl_inventory:drops:add', -1, publicDrop(d))
    return d
end

--- Removes a drop: viewers fall back to an empty Ground box, then the rows are deleted.
--- reason nil = "it became empty" (re-checked under the lock: if something was dropped in meanwhile, it stays).
function Drops.Remove(id, reason)
    local d = Drops.list[id]
    if not d or d.removing then return end
    d.removing = true
    CreateThread(function()
        Store.WithLocks({ d.invId }, function()
            local inv = Store.inventories[d.invId]
            if not reason and inv and next(inv.items) then d.removing = nil return end
            Drops.list[id] = nil
            TriggerClientEvent('veyl_inventory:drops:remove', -1, id)
            if inv then
                inv.dead = true -- any transfer still holding this inventory is refused (see Ops.Transfer)
                for src in pairs(inv.viewers) do
                    local s = Sessions[src]
                    if s and s.secondary and s.secondary.dropId == id then
                        s.secondary = { ground = true }
                        if GetPlayerName(src) then TriggerClientEvent('veyl_inventory:snapshot', src, Drops.PendingView()) end
                    end
                end
                inv.viewers = {}
                if next(inv.items) and reason then
                    print(('^3[veyl_inventory] drop %s removed (%s) with items still in it^7'):format(id, reason))
                end
                Store.inventories[d.invId] = nil
            end
            MySQL.query.await('DELETE FROM veyl_inventory_slots WHERE inventory_id = ?', { d.invId })
            MySQL.query.await('DELETE FROM veyl_inventories WHERE id = ?', { d.invId })
        end, 'drop')
    end)
end

--- Called after every committed change: an emptied drop disappears.
AddEventHandler('veyl_inventory:changed', function(invId)
    if type(invId) ~= 'string' or invId:sub(1, 5) ~= 'drop:' then return end
    local id = invId:sub(6)
    local inv = Store.inventories[invId]
    if Drops.list[id] and inv and next(inv.items) == nil then
        SetTimeout(250, function()
            local again = Store.inventories[invId]
            if Drops.list[id] and (not again or next(again.items) == nil) then Drops.Remove(id) end
        end)
    end
end)

--- Startup: ground items never survive a restart.
function Drops.ClearAll()
    MySQL.query.await([[DELETE s FROM veyl_inventory_slots s JOIN veyl_inventories i ON i.id = s.inventory_id WHERE i.type = 'drop']])
    MySQL.query.await("DELETE FROM veyl_inventories WHERE type = 'drop'")
end

--- Players that load in get the current list (for the bag props / target zones).
function Drops.Sync(src)
    local list = {}
    for _, d in pairs(Drops.list) do list[#list + 1] = publicDrop(d) end
    TriggerClientEvent('veyl_inventory:drops:sync', src, list)
end

-- Expiry.
CreateThread(function()
    while true do
        Wait(60000)
        local cutoff = os.time() - InventoryConfig.DropLifetimeMinutes * 60
        for id, d in pairs(Drops.list) do
            if d.createdAt < cutoff then Drops.Remove(id, 'expired') end
        end
    end
end)
