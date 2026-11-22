-- Postal bridge. Off unless HudConfig.Postal.provider = 'file' and the dataset exists in this resource.
-- Dataset: JSON array of { "code": "8042", "x": 0.0, "y": 0.0 } (the format most postal maps ship). Never invents codes.

Bridge = Bridge or {}
Bridge.Postal = { list = nil }

function Bridge.Postal.Load()
    Bridge.Postal.list = nil
    local cfg = HudConfig.Postal or {}
    if cfg.provider ~= 'file' then return end
    local raw = LoadResourceFile(GetCurrentResourceName(), cfg.file or 'data/postals.json')
    if not raw then print(('^3[veyl_hud] postal file %s not found: postals hidden^7'):format(cfg.file)) return end
    local ok, data = pcall(json.decode, raw)
    if not ok or type(data) ~= 'table' then print('^3[veyl_hud] postal file is not valid JSON: postals hidden^7') return end
    local list = {}
    for _, p in ipairs(data) do
        local code = p.code or p.postal
        if code and tonumber(p.x) and tonumber(p.y) then list[#list + 1] = { code = tostring(code), x = tonumber(p.x), y = tonumber(p.y) } end
    end
    if #list > 0 then Bridge.Postal.list = list end
end

function Bridge.Postal.Available() return Bridge.Postal.list ~= nil end

--- Nearest postal code to a position, or nil.
function Bridge.Postal.Nearest(x, y)
    local list = Bridge.Postal.list
    if not list then return nil end
    local best, bestD = nil, math.huge
    for i = 1, #list do
        local p = list[i]
        local dx, dy = p.x - x, p.y - y
        local d = dx * dx + dy * dy
        if d < bestD then best, bestD = p.code, d end
    end
    return best
end
