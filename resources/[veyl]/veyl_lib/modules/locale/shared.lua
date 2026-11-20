-- vlib.locale() loads locales/<lang>.json from the CALLING resource (convar `veyl:locale`, fallback 'en').
-- vlib.t('key.path', { name = 'x' }) -> string with %{name} substitutions; missing keys return the key.
local RES = GetCurrentResourceName()
local phrases, fallback = {}, {}

local function flatten(tbl, prefix, out)
    for k, v in pairs(tbl or {}) do
        local key = prefix and (prefix .. '.' .. k) or k
        if type(v) == 'table' then flatten(v, key, out) else out[key] = tostring(v) end
    end
    return out
end

local function loadLang(lang)
    local raw = LoadResourceFile(RES, ('locales/%s.json'):format(lang))
    if not raw then return {} end
    local ok, data = pcall(json.decode, raw)
    return ok and flatten(data, nil, {}) or {}
end

return {
    locale = function(lang)
        lang = lang or GetConvar('veyl:locale', 'en')
        phrases = loadLang(lang)
        fallback = lang ~= 'en' and loadLang('en') or {}
    end,
    t = function(key, subs)
        local s = phrases[key] or fallback[key]
        if not s then return key end
        for k, v in pairs(subs or {}) do s = s:gsub('%%{' .. k .. '}', tostring(v)) end
        return s
    end,
}
