-- veyl_target registry: validated registrations with owner tracking and named-option removal.

Registry = {
    zones = {},          -- [id] = { id, owner, zone, options, order }
    entities = {},       -- [netId] = { [key] = option }
    localEntities = {},  -- [handle] = { [key] = option }
    models = {},         -- [hash] = { [key] = option }
    globals = { ped = {}, vehicle = {}, object = {}, player = {} },
}

local orderSeq = 0
local zoneSeq = 0
local ACTIONS = { 'onSelect', 'export', 'event', 'serverEvent', 'command' } -- precedence for legacy data

local function fail(owner, what, field)
    error(('veyl_target: %s from resource "%s" has an invalid %s'):format(what, tostring(owner), field), 3)
end

--- Normalises one option. Exactly one action is used (precedence onSelect > export > event > serverEvent > command).
local function normaliseOption(owner, o, i)
    if type(o) ~= 'table' then fail(owner, ('option #%d'):format(i), 'definition (expected table)') end
    if type(o.name) ~= 'string' or o.name == '' then fail(owner, ('option #%d'):format(i), '"name" (stable string id required)') end
    if type(o.label) ~= 'string' then fail(owner, ('option "%s"'):format(o.name), '"label"') end
    local action
    for _, a in ipairs(ACTIONS) do
        if o[a] ~= nil then action = a break end
    end
    if not action then fail(owner, ('option "%s"'):format(o.name), 'action (need onSelect, export, event, serverEvent or command)') end
    if o.distance ~= nil and (type(o.distance) ~= 'number' or o.distance <= 0 or o.distance > 25) then
        fail(owner, ('option "%s"'):format(o.name), '"distance" (0-25)')
    end
    orderSeq = orderSeq + 1
    return {
        key = owner .. ':' .. o.name, owner = owner, name = o.name, label = o.label, icon = o.icon,
        distance = o.distance or TargetConfig.DefaultOptionDistance, priority = tonumber(o.priority) or 0, order = orderSeq,
        groups = o.groups, items = o.items, canInteract = o.canInteract, bones = o.bones, offset = o.offset,
        action = action, handler = o[action], args = o.args,
    }
end

local function normaliseOptions(owner, options)
    if type(options) ~= 'table' then fail(owner, 'registration', '"options"') end
    if options.name then options = { options } end -- single option shorthand
    local list = {}
    for i, o in ipairs(options) do list[i] = normaliseOption(owner, o, i) end
    return list
end

local function addTo(bucket, owner, options)
    for _, opt in ipairs(normaliseOptions(owner, options)) do bucket[opt.key] = opt end
end

local function removeFrom(bucket, owner, names)
    if bucket == nil then return end
    if names == nil then
        for key, opt in pairs(bucket) do if opt.owner == owner then bucket[key] = nil end end
        return
    end
    if type(names) == 'string' then names = { names } end
    for _, n in ipairs(names) do bucket[owner .. ':' .. n] = nil end
end

local function asList(v) return type(v) == 'table' and v or { v } end

function Registry.addZone(owner, kind, data)
    if type(data) ~= 'table' then fail(owner, kind .. ' zone', 'definition') end
    local ok, zone = pcall(kind == 'sphere' and vlib.zones.sphere or vlib.zones.box, data, owner)
    if not ok then error(('veyl_target: %s zone from "%s": %s'):format(kind, owner, tostring(zone)), 2) end
    zoneSeq = zoneSeq + 1
    orderSeq = orderSeq + 1
    local id = data.name and (owner .. ':' .. data.name) or (owner .. ':zone' .. zoneSeq)
    local options = {}
    for _, opt in ipairs(normaliseOptions(owner, data.options)) do options[opt.key] = opt end
    Registry.zones[id] = { id = id, owner = owner, zone = zone, options = options, order = orderSeq, debug = data.debug,
        title = type(data.title) == 'string' and data.title:sub(1, 24) or nil }
    return id
end

function Registry.removeZone(id) Registry.zones[id] = nil end

function Registry.addEntity(owner, netIds, options)
    for _, netId in ipairs(asList(netIds)) do
        if type(netId) ~= 'number' then fail(owner, 'addEntity', 'network id (number expected)') end
        Registry.entities[netId] = Registry.entities[netId] or {}
        addTo(Registry.entities[netId], owner, options)
    end
end

function Registry.removeEntity(owner, netIds, names)
    for _, netId in ipairs(asList(netIds)) do
        removeFrom(Registry.entities[netId], owner, names)
        if Registry.entities[netId] and next(Registry.entities[netId]) == nil then Registry.entities[netId] = nil end
    end
end

function Registry.addLocalEntity(owner, handles, options)
    for _, h in ipairs(asList(handles)) do
        if type(h) ~= 'number' or not DoesEntityExist(h) then fail(owner, 'addLocalEntity', 'entity handle') end
        Registry.localEntities[h] = Registry.localEntities[h] or {}
        addTo(Registry.localEntities[h], owner, options)
    end
end

function Registry.removeLocalEntity(owner, handles, names)
    for _, h in ipairs(asList(handles)) do
        removeFrom(Registry.localEntities[h], owner, names)
        if Registry.localEntities[h] and next(Registry.localEntities[h]) == nil then Registry.localEntities[h] = nil end
    end
end

function Registry.addModel(owner, models, options)
    for _, m in ipairs(asList(models)) do
        local hash = type(m) == 'string' and joaat(m) or m
        if type(hash) ~= 'number' then fail(owner, 'addModel', 'model') end
        Registry.models[hash] = Registry.models[hash] or {}
        addTo(Registry.models[hash], owner, options)
    end
end

function Registry.removeModel(owner, models, names)
    for _, m in ipairs(asList(models)) do
        local hash = type(m) == 'string' and joaat(m) or m
        removeFrom(Registry.models[hash], owner, names)
    end
end

function Registry.addGlobal(owner, kind, options) addTo(Registry.globals[kind], owner, options) end
function Registry.removeGlobal(owner, kind, names) removeFrom(Registry.globals[kind], owner, names) end

--- Removes everything a stopped resource registered.
function Registry.removeOwner(owner)
    for id, z in pairs(Registry.zones) do if z.owner == owner then Registry.zones[id] = nil end end
    for _, bucketMap in ipairs({ Registry.entities, Registry.localEntities, Registry.models }) do
        for k, bucket in pairs(bucketMap) do
            removeFrom(bucket, owner, nil)
            if next(bucket) == nil then bucketMap[k] = nil end
        end
    end
    for _, bucket in pairs(Registry.globals) do removeFrom(bucket, owner, nil) end
end
