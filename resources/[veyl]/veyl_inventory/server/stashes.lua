-- Stash registration and access rules (checked on the server for every open AND every mutation).

Stashes = {}

--- RegisterStash({ id, label, slots, maxWeight, owner = true|false|'<citizenid>', coords?, radius?, groups?,
---                 authorize? = { resource, export } })
--- authorize: the named server export is called as export(src, citizenid, stashId) -> allowed, code before every
--- open and mutation, so the owning resource decides access from its own live rules (e.g. apartment keys).
function Stashes.Register(def, registrant)
    assert(type(def) == 'table' and type(def.id) == 'string' and def.id:match('^[%w_%-]+$'),
        ('veyl_inventory: RegisterStash from %s needs an id of letters, digits, _ or -'):format(tostring(registrant)))
    assert(vlib.validate.int(def.slots, 1, 200), ('veyl_inventory: stash %s slots must be 1-200'):format(def.id))
    assert(vlib.validate.int(def.maxWeight, 1, 10000000), ('veyl_inventory: stash %s maxWeight must be an integer'):format(def.id))
    Stashes[def.id] = {
        id = def.id, label = def.label or def.id, slots = def.slots, maxWeight = def.maxWeight, owner = def.owner,
        coords = def.coords and vector3(def.coords.x, def.coords.y, def.coords.z) or nil, radius = tonumber(def.radius) or 2.0,
        groups = def.groups, registrant = registrant,
        -- keyed = true: opened as '<id>@<key>' (e.g. a vehicle's network id); the authorize export turns the key into a
        -- stable storage key (e.g. 'own12' or a plate), so every vehicle gets its own trunk under one definition.
        keyed = def.keyed == true,
        -- Optional: show an existing player inventory (e.g. police searching someone). Requires an authorize export.
        inventory = type(def.inventory) == 'string' and def.inventory:match('^player:[%w]+$') and def.authorize and def.inventory or nil,
        authorize = type(def.authorize) == 'table' and type(def.authorize.resource) == 'string' and type(def.authorize.export) == 'string'
            and { resource = def.authorize.resource, export = def.authorize.export } or nil,
    }
end

--- Resolves the concrete inventory id for a character and checks access. Returns inventoryId, def or nil, code.
function Stashes.Resolve(src, citizenid, stashId)
    local baseId, key = stashId, nil
    if type(stashId) == 'string' and stashId:find('@', 1, true) then baseId, key = stashId:match('^([%w_%-]+)@([%w_%-]+)$') end
    local def = baseId and Stashes[baseId]
    if not def then return nil, 'NOT_FOUND' end
    if def.keyed ~= (key ~= nil) or (def.keyed and not def.authorize) then return nil, 'NOT_FOUND' end
    if def.groups and not exports.veyl_core:HasGroup(src, def.groups) then return nil, 'NO_PERMISSION' end
    if def.coords then
        local ped = GetPlayerPed(src)
        if ped == 0 or #(GetEntityCoords(ped) - def.coords) > def.radius + 2.0 then return nil, 'TOO_FAR' end
    end
    if def.authorize then
        if GetResourceState(def.authorize.resource) ~= 'started' then return nil, 'NOT_READY' end
        local ok, allowed, code, storeKey = pcall(function() return exports[def.authorize.resource][def.authorize.export](nil, src, citizenid, baseId, key) end)
        if not ok or allowed ~= true then return nil, (ok and type(code) == 'string') and code or 'NO_PERMISSION' end
        if def.keyed then
            if type(storeKey) ~= 'string' or not storeKey:match('^[%w_%-]+$') or #storeKey > 32 then return nil, 'NOT_FOUND' end
            return ('stash:%s:%s'):format(def.id, storeKey), def, nil
        end
    end
    if def.inventory then return def.inventory, def, nil end
    local owner
    if def.owner == true then owner = citizenid
    elseif type(def.owner) == 'string' then
        if def.owner ~= citizenid then return nil, 'NO_PERMISSION' end
        owner = def.owner
    end
    return owner and ('stash:%s:%s'):format(def.id, owner) or ('stash:' .. def.id), def, owner
end
