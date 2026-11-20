-- Stash registration and access rules (checked on the server for every open AND every mutation).

Stashes = {}

--- RegisterStash({ id, label, slots, maxWeight, owner = true|false|'<citizenid>', coords?, radius?, groups? })
function Stashes.Register(def, registrant)
    assert(type(def) == 'table' and type(def.id) == 'string' and def.id:match('^[%w_%-]+$'),
        ('veyl_inventory: RegisterStash from %s needs an id of letters, digits, _ or -'):format(tostring(registrant)))
    assert(vlib.validate.int(def.slots, 1, 200), ('veyl_inventory: stash %s slots must be 1-200'):format(def.id))
    assert(vlib.validate.int(def.maxWeight, 1, 10000000), ('veyl_inventory: stash %s maxWeight must be an integer'):format(def.id))
    Stashes[def.id] = {
        id = def.id, label = def.label or def.id, slots = def.slots, maxWeight = def.maxWeight, owner = def.owner,
        coords = def.coords and vector3(def.coords.x, def.coords.y, def.coords.z) or nil, radius = tonumber(def.radius) or 2.0,
        groups = def.groups, registrant = registrant,
    }
end

--- Resolves the concrete inventory id for a character and checks access. Returns inventoryId, def or nil, code.
function Stashes.Resolve(src, citizenid, stashId)
    local def = Stashes[stashId]
    if not def then return nil, 'NOT_FOUND' end
    if def.groups and not exports.veyl_core:HasGroup(src, def.groups) then return nil, 'NO_PERMISSION' end
    if def.coords then
        local ped = GetPlayerPed(src)
        if ped == 0 or #(GetEntityCoords(ped) - def.coords) > def.radius + 2.0 then return nil, 'TOO_FAR' end
    end
    local owner
    if def.owner == true then owner = citizenid
    elseif type(def.owner) == 'string' then
        if def.owner ~= citizenid then return nil, 'NO_PERMISSION' end
        owner = def.owner
    end
    return owner and ('stash:%s:%s'):format(def.id, owner) or ('stash:' .. def.id), def, owner
end
