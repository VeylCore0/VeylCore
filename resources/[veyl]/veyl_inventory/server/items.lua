-- Item definitions: loaded from data/items.lua (server only) and validated at startup.

ItemDefs = {}

local function loadDefinitions()
    local code = LoadResourceFile(GetCurrentResourceName(), 'data/items.lua')
    if not code then error('veyl_inventory: data/items.lua is missing') end
    local chunk, err = load(code, '@@veyl_inventory/data/items.lua', 't')
    if not chunk then error('veyl_inventory: data/items.lua: ' .. err) end
    local defs = chunk()
    for name, d in pairs(defs) do
        assert(type(name) == 'string' and name:match('^[%w_]+$'), ('veyl_inventory: invalid item name %s'):format(tostring(name)))
        assert(type(d.label) == 'string', ('veyl_inventory: item %s needs a label'):format(name))
        assert(vlib.validate.int(d.weight, 0, 1000000), ('veyl_inventory: item %s weight must be an integer (grams)'):format(name))
        d.name = name
        d.stack = d.stack ~= false
        d.maxStack = d.stack and (tonumber(d.maxStack) or 100) or 1
        if d.use then
            d.use.durationMs = math.max(0, math.floor(tonumber(d.use.durationMs) or 0))
            d.use.consumeCount = math.max(0, math.floor(tonumber(d.use.consumeCount) or 1))
        end
        d.usable = d.use ~= nil or d.usable == true
    end
    return defs
end

ItemDefs = loadDefinitions()

--- Client-safe definition view (no handlers, no server effects).
function ClientItemDefs()
    local out = {}
    for name, d in pairs(ItemDefs) do
        out[name] = {
            name = name, label = d.label, description = d.description, image = d.image or (name .. '.png'),
            weight = d.weight, stack = d.stack, maxStack = d.maxStack, usable = d.usable,
        }
    end
    return out
end

-- Metadata schemas: allowed keys and types. Keys starting with '_' are private (never sent to clients).
MetadataSchemas = {
    identity_card = { firstname = 'string', lastname = 'string', citizenid = 'string', birthdate = 'string' },
    licence_card = { firstname = 'string', lastname = 'string', citizenid = 'string', birthdate = 'string', issued = 'string' },
    -- veyl_drugs
    drug_seed = { variety = 'string', varietyLabel = 'string' },
    drug_batch = { product = 'string', variety = 'string', varietyLabel = 'string', grade = 'string', quality = 'number', batch = 'string' },
    -- veyl_doorlocks: a physical key for one registered door
    door_key = { door = 'number', label = 'string', rev = 'number' },
}

--- Validates and normalises metadata for an item. Returns clean table or nil, error.
function CleanMetadata(itemName, metadata)
    if metadata == nil then return {} end
    if type(metadata) ~= 'table' then return nil, 'metadata must be a table' end
    if vlib.validate.size(metadata) > InventoryConfig.MaxMetadataBytes then return nil, 'metadata too large' end
    local schema = ItemDefs[itemName] and ItemDefs[itemName].metadataSchema and MetadataSchemas[ItemDefs[itemName].metadataSchema]
    local out = {}
    for k, v in pairs(metadata) do
        if type(k) ~= 'string' then return nil, 'metadata keys must be strings' end
        if schema and not k:match('^_') and schema[k] == nil then return nil, ('metadata key %s is not allowed for %s'):format(k, itemName) end
        if schema and schema[k] and type(v) ~= schema[k] then return nil, ('metadata %s must be a %s'):format(k, schema[k]) end
        local t = type(v)
        if t ~= 'string' and t ~= 'number' and t ~= 'boolean' and t ~= 'table' then return nil, 'unsupported metadata value' end
        out[k] = v
    end
    return out
end

--- Metadata view for clients: private keys removed.
function PublicMetadata(metadata)
    if type(metadata) ~= 'table' then return nil end
    local out, any = {}, false
    for k, v in pairs(metadata) do
        if not (type(k) == 'string' and k:sub(1, 1) == '_') then out[k] = v any = true end
    end
    return any and out or nil
end
