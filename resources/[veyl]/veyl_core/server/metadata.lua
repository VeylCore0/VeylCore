-- veyl_core metadata: validated persistent status. Schema lives in config/server.lua (VeylServerConfig.Metadata).

Metadata = {}

local schema = VeylServerConfig.Metadata

--- Fills missing keys with defaults (new optional data gets safe values for older characters).
function Metadata.ApplyDefaults(meta)
    meta = type(meta) == 'table' and meta or {}
    for key, rule in pairs(schema) do
        if meta[key] == nil then meta[key] = Core.DeepCopy(rule.default) end
    end
    return meta
end

local function validate(key, value)
    if type(key) ~= 'string' or #key > 64 then return false, nil end
    local rule = schema[key]
    if not rule then
        local t = type(value)
        if t == 'string' or t == 'number' or t == 'boolean' or t == 'table' or value == nil then return true, value end
        return false, nil
    end
    if type(value) ~= rule.type then return false, nil end
    if rule.type == 'number' then
        if value ~= value then return false, nil end
        if rule.min and value < rule.min then value = rule.min end
        if rule.max and value > rule.max then value = rule.max end
    elseif rule.type == 'string' and #value > 256 then
        return false, nil
    end
    return true, value
end

function Metadata.Get(src, key)
    local p = Core.Players[tonumber(src)]
    if not p then return nil end
    return Core.DeepCopy(p.metadata[key])
end

--- Sets one key. Numbers are clamped to the schema range. Returns true on success.
function Metadata.Set(src, key, value)
    local p = Core.Players[tonumber(src)]
    if not p then return false end
    local ok, clean = validate(key, value)
    if not ok then
        print(('^3[veyl_core] rejected metadata %s=%s from %s^7'):format(tostring(key), tostring(value), tostring(GetInvokingResource())))
        return false
    end
    p.metadata[key] = clean
    TriggerEvent('VeylCore:Server:OnMetadataChange', p.source, key, clean)
    Core.SyncPlayer(p)
    return true
end

--- Sets several keys with one client sync.
function Metadata.SetMany(src, values)
    local p = Core.Players[tonumber(src)]
    if not p or type(values) ~= 'table' then return false end
    local all = true
    for key, value in pairs(values) do
        local ok, clean = validate(key, value)
        if ok then
            p.metadata[key] = clean
            TriggerEvent('VeylCore:Server:OnMetadataChange', p.source, key, clean)
        else
            all = false
        end
    end
    Core.SyncPlayer(p)
    return all
end
