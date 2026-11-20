-- Minimal implementation of QBCore's Locale class for resources that import '@qb-core/shared/locale.lua'.
-- Supports Locale:new({ phrases = {...}, warnOnMissing = bool, fallbackLang = Locale }), :t(key, subs), :has, :extend.
Locale = {}
Locale.__index = Locale

local function flatten(phrases, prefix, out)
    out = out or {}
    for k, v in pairs(phrases or {}) do
        local key = prefix and (prefix .. '.' .. k) or k
        if type(v) == 'table' then flatten(v, key, out) else out[key] = v end
    end
    return out
end

function Locale.new(_, opts)
    opts = opts or {}
    local self = setmetatable({}, Locale)
    self.phrases = flatten(opts.phrases)
    self.warnOnMissing = opts.warnOnMissing ~= false
    self.fallback = opts.fallbackLang
    return self
end

function Locale:extend(phrases) for k, v in pairs(flatten(phrases)) do self.phrases[k] = v end end
function Locale:has(key) return self.phrases[key] ~= nil end
function Locale:clear() self.phrases = {} end
function Locale:replace(phrases) self.phrases = flatten(phrases) end
function Locale:locale(_) return self end

function Locale:t(key, subs)
    local phrase = self.phrases[key]
    if not phrase and self.fallback then return self.fallback:t(key, subs) end
    if not phrase then
        if self.warnOnMissing then print(('^3[Locale] missing phrase "%s"^7'):format(tostring(key))) end
        return key
    end
    for k, v in pairs(subs or {}) do
        phrase = phrase:gsub('%%{' .. k .. '}', tostring(v))
    end
    return phrase
end
