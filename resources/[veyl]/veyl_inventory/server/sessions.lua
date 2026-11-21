-- Sessions and the network surface. Clients send only: session-relative refs ('primary'/'secondary'),
-- slot numbers, counts, expected revisions and an operation id. Everything else is resolved on the server.

Players = {}   -- [src] = { citizenid, generation, invId }
Sessions = {}  -- [src] = { token, citizenid, generation, secondary = { invId, stashId } }

local function err(code, message) return Ops.err(code, message) end

function PlayerInventoryId(citizenid) return 'player:' .. citizenid end

local function playerDefaults(citizenid, label)
    return { type = 'player', owner = citizenid, label = label or 'Pockets', slots = InventoryConfig.PlayerSlots, maxWeight = InventoryConfig.PlayerMaxWeight }
end

--- Called by the framework adapter when a character becomes active.
function Inventory_OnCharacterLoaded(src, citizenid, generation, label)
    local inv = Store.Get(PlayerInventoryId(citizenid), playerDefaults(citizenid, label))
    if not inv then
        print(('^1[veyl_inventory] could not load inventory for %s^7'):format(citizenid))
        TriggerClientEvent('veyl_inventory:unavailable', src)
        return
    end
    Players[src] = { citizenid = citizenid, generation = generation, invId = inv.id }
    inv.viewers[src] = 'primary'
    TriggerClientEvent('veyl_inventory:init', src, { primary = Store.View(inv, 'primary'), items = ClientItemDefs(), imagePath = InventoryConfig.ImagePath })
end

function Inventory_OnCharacterUnloaded(src)
    Use.CancelFor(src)
    local s = Sessions[src]
    if s and s.secondary then
        local sec = Store.Get(s.secondary.invId)
        if sec then sec.viewers[src] = nil Store.Unload(sec.id) end
    end
    Sessions[src] = nil
    local p = Players[src]
    Players[src] = nil
    if p then
        local inv = Store.Get(p.invId)
        if inv then
            inv.viewers[src] = nil
            -- Evict once pending writes finish (unload refuses while locked or reserved).
            SetTimeout(5000, function() if not Players[src] then Store.Unload(p.invId) end end)
        end
    end
    if GetPlayerName(src) then TriggerClientEvent('veyl_inventory:closed', src, 'unloaded') end
end

--- Current actor context, or nil if the character/session changed.
local function actor(src)
    if not Ready then return nil end
    local p = Players[src]
    if not p then return nil end
    if exports.veyl_core:GetCitizenId(src) ~= p.citizenid then return nil end
    if exports.veyl_core:GetSessionGeneration(src) ~= p.generation then return nil end
    return p
end

--- Resolves a session ref to an inventory and re-checks access (distance/groups/ownership) every time.
local function resolveRef(src, p, ref)
    if ref == 'primary' then return Store.Get(p.invId) end
    if ref == 'secondary' then
        local s = Sessions[src]
        if not s or not s.secondary then return nil, 'NO_SESSION' end
        local invId, def = Stashes.Resolve(src, p.citizenid, s.secondary.stashId)
        if not invId then
            local lostId = s.secondary.invId
            vlib.print.info(('closing %s for %s: %s'):format(s.secondary.stashId, src, tostring(def)))
            s.secondary = nil
            local sec = Store.Get(lostId)
            if sec then sec.viewers[src] = nil end
            TriggerClientEvent('veyl_inventory:closed', src, 'access_lost')
            return nil, def
        end
        if invId ~= s.secondary.invId then return nil, 'NO_SESSION' end
        return Store.Get(invId)
    end
    return nil, 'INVALID_INPUT'
end

---------------------------------------------------------------------------
-- Callbacks
---------------------------------------------------------------------------
vlib.callback.register('veyl_inventory:open', function(src, stashId)
    local p = actor(src)
    if not p then return err('NO_CHARACTER', 'No character loaded') end
    local inv = Store.Get(p.invId)
    if not inv then return err('NOT_READY', 'Inventory unavailable') end
    local s = { token = tostring(GetGameTimer()) .. ':' .. src, citizenid = p.citizenid, generation = p.generation }
    local secondaryView
    if stashId ~= nil then
        if not vlib.validate.str(stashId, 1, 64) then return err('INVALID_INPUT', 'Bad stash') end
        local invId, def, owner = Stashes.Resolve(src, p.citizenid, stashId)
        if not invId then return err(def, def == 'TOO_FAR' and 'You are too far away' or 'You cannot open that') end
        local sec = Store.Get(invId, { type = 'stash', owner = owner, label = def.label, slots = def.slots, maxWeight = def.maxWeight })
        if not sec then return err('NOT_READY', 'Stash unavailable') end
        sec.viewers[src] = 'secondary'
        s.secondary = { invId = invId, stashId = stashId }
        secondaryView = Store.View(sec, 'secondary')
    end
    -- Close any previous secondary.
    local old = Sessions[src]
    if old and old.secondary and (not s.secondary or old.secondary.invId ~= s.secondary.invId) then
        local prev = Store.Get(old.secondary.invId)
        if prev then prev.viewers[src] = nil Store.Unload(prev.id) end
    end
    Sessions[src] = s
    return Ops.ok({ primary = Store.View(inv, 'primary'), secondary = secondaryView, items = ClientItemDefs(), imagePath = InventoryConfig.ImagePath })
end, { cooldownMs = 300 })

vlib.callback.register('veyl_inventory:close', function(src)
    local s = Sessions[src]
    if s and s.secondary then
        local sec = Store.Get(s.secondary.invId)
        if sec then sec.viewers[src] = nil Store.Unload(sec.id) end
    end
    Sessions[src] = nil
    return Ops.ok()
end)

vlib.callback.register('veyl_inventory:move', function(src, req)
    local p = actor(src)
    if not p then return err('NO_CHARACTER', 'No character loaded') end
    if type(req) ~= 'table' or type(req.from) ~= 'table' or type(req.to) ~= 'table' then return err('INVALID_INPUT', 'Bad request') end
    local from, e1 = resolveRef(src, p, req.from.ref)
    if not from then return err(e1 or 'NOT_FOUND', 'Inventory not available') end
    local to, e2 = resolveRef(src, p, req.to.ref)
    if not to then return err(e2 or 'NOT_FOUND', 'Inventory not available') end
    local revisions = {}
    if type(req.revisions) == 'table' then
        if req.revisions[req.from.ref] then revisions[from.id] = tonumber(req.revisions[req.from.ref]) end
        if req.revisions[req.to.ref] then revisions[to.id] = tonumber(req.revisions[req.to.ref]) end
    end
    local res = Ops.Transfer({
        opId = req.opId, actor = p.citizenid, from = from, fromSlot = req.from.slot, to = to, toSlot = req.to.slot,
        count = req.count, revisions = revisions,
    })
    if res.code == 'STALE' then
        Store.Snapshot(from, src)
        if to ~= from then Store.Snapshot(to, src) end
    end
    return res
end, { cooldownMs = 0 })

vlib.callback.register('veyl_inventory:useStart', function(src, slot)
    local p = actor(src)
    if not p then return err('NO_CHARACTER', 'No character loaded') end
    local inv = Store.Get(p.invId)
    if not inv then return err('NOT_READY', 'Inventory unavailable') end
    return Use.Start(src, p.citizenid, p.generation, inv, slot)
end, { cooldownMs = 500 })

vlib.callback.register('veyl_inventory:useComplete', function(src, useId)
    local p = actor(src)
    if not p then return err('NO_CHARACTER', 'No character loaded') end
    if not vlib.validate.str(useId, 1, 64) then return err('INVALID_INPUT', 'Bad use id') end
    return Use.Complete(src, p.citizenid, p.generation, useId)
end)

vlib.callback.register('veyl_inventory:useCancel', function(src, useId)
    return Use.Cancel(src, useId)
end)

vlib.callback.register('veyl_inventory:refresh', function(src)
    local p = actor(src)
    if not p then return err('NO_CHARACTER', 'No character loaded') end
    local inv = Store.Get(p.invId)
    if inv then Store.Snapshot(inv, src) end
    local s = Sessions[src]
    if s and s.secondary then
        local sec = Store.Get(s.secondary.invId)
        if sec then Store.Snapshot(sec, src) end
    end
    return Ops.ok()
end, { cooldownMs = 1000 })

---------------------------------------------------------------------------
-- Give to a nearby player
---------------------------------------------------------------------------
local function nearbyPlayers(src)
    local ped = GetPlayerPed(src)
    if ped == 0 then return {} end
    local pos, bucket = GetEntityCoords(ped), GetPlayerRoutingBucket(src)
    local list = {}
    for target, p in pairs(Players) do
        if target ~= src and GetPlayerName(target) and GetPlayerRoutingBucket(target) == bucket then
            local tped = GetPlayerPed(target)
            local d = tped ~= 0 and #(GetEntityCoords(tped) - pos) or math.huge
            if d <= InventoryConfig.GiveDistance then
                local pd = exports.veyl_core:GetPlayerData(target)
                local name = pd and ('%s %s.'):format(pd.charinfo.firstname or '?', (pd.charinfo.lastname or ''):sub(1, 1)) or ('Citizen #' .. target)
                list[#list + 1] = { id = target, name = name, distance = math.floor(d * 10 + 0.5) / 10, citizenid = p.citizenid }
            end
        end
    end
    table.sort(list, function(a, b) return a.distance < b.distance end)
    return list
end

vlib.callback.register('veyl_inventory:nearby', function(src)
    if not actor(src) then return err('NO_CHARACTER', 'No character loaded') end
    local out = {}
    for i, p in ipairs(nearbyPlayers(src)) do out[i] = { id = p.id, name = p.name, distance = p.distance } end
    return Ops.ok(out)
end, { cooldownMs = 500 })

--- First slot that can take `item` (matching stack with room, else empty), or nil.
local function destinationSlot(inv, it, count)
    local def = ItemDefs[it.name]
    if def.stack then
        for s = 1, inv.slots do
            local d = inv.items[s]
            if d and Store.CanStack(d, it) and d.count + count <= def.maxStack then return s end
        end
    end
    for s = 1, inv.slots do if not inv.items[s] then return s end end
    return nil
end

vlib.callback.register('veyl_inventory:give', function(src, req)
    local p = actor(src)
    if not p then return err('NO_CHARACTER', 'No character loaded') end
    if type(req) ~= 'table' or not vlib.validate.int(req.target, 1, 65535) then return err('INVALID_INPUT', 'Choose a player') end
    -- Re-validate the recipient on the server: online, loaded, same bucket, within range.
    local target
    for _, n in ipairs(nearbyPlayers(src)) do if n.id == req.target then target = n break end end
    if not target or not Players[req.target] then return err('TOO_FAR', 'That player is no longer nearby') end
    local from = Store.Get(p.invId)
    local to = Store.Get(Players[req.target].invId)
    if not from or not to then return err('NOT_READY', 'Inventory unavailable') end
    local it = vlib.validate.int(req.slot, 1, from.slots) and from.items[req.slot] or nil
    if not it then return err('NOT_FOUND', 'Nothing in that slot') end
    local count = vlib.validate.int(req.count, 1, it.count) and req.count or it.count
    local toSlot = destinationSlot(to, it, count)
    if not toSlot then return err('INVENTORY_FULL', 'Their inventory is full') end
    local revisions = {}
    if req.revision then revisions[from.id] = tonumber(req.revision) end
    local res = Ops.Transfer({ opId = req.opId, actor = p.citizenid, from = from, fromSlot = req.slot, to = to, toSlot = toSlot,
        count = count, revisions = revisions })
    if res.ok then
        local def = ItemDefs[it.name]
        vlib.notify(req.target, { message = ('You received %dx %s'):format(count, def.label), type = 'success' })
        res.message = ('Gave %dx %s'):format(count, def.label)
    elseif res.code == 'STALE' then
        Store.Snapshot(from, src)
    end
    return res
end, { cooldownMs = 750 })

AddEventHandler('playerDropped', function()
    local src = source
    if Players[src] or Sessions[src] then Inventory_OnCharacterUnloaded(src) end
end)
