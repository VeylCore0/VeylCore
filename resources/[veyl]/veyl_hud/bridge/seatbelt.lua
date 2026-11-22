-- Seatbelt bridge. veyl_vehicles/seatbelt.lua owns the seatbelt (key B, ejection) and publishes
-- LocalPlayer.state.seatbelt = true/false. The HUD only reads it: no second seatbelt state, no keybind.

Bridge = Bridge or {}
Bridge.Seatbelt = {}

--- 'on' | 'off' | nil (no provider: the indicator hides).
function Bridge.Seatbelt.State()
    if HudConfig.Seatbelt ~= 'statebag' then return nil end
    local v = LocalPlayer.state.seatbelt
    if v == nil then return nil end
    return v and 'on' or 'off'
end
