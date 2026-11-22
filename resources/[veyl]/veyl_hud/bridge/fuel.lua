-- Fuel bridge. veyl_fuel (server) publishes the level on the vehicle state bag `veylFuel` (0-100).
-- 'native' reads GTA's own fuel level (GetVehicleFuelLevel, 0-100 for most vehicles). Bicycles never show fuel.

Bridge = Bridge or {}
Bridge.Fuel = { provider = 'none' }

function Bridge.Fuel.Detect()
    local want = HudConfig.Fuel
    if want == 'none' then Bridge.Fuel.provider = 'none' return end
    if (want == 'auto' or want == 'veyl_fuel') and GetResourceState('veyl_fuel') == 'started' then
        Bridge.Fuel.provider = 'veyl_fuel'
    elseif want == 'auto' or want == 'native' then
        Bridge.Fuel.provider = 'native'
    else
        Bridge.Fuel.provider = 'none'
    end
end

--- 0-100 or nil (unknown: the fuel gauge hides).
function Bridge.Fuel.Level(veh)
    local p = Bridge.Fuel.provider
    if p == 'veyl_fuel' then
        if GetResourceState('veyl_fuel') ~= 'started' then Bridge.Fuel.Detect() return nil end
        local f = Entity(veh).state.veylFuel
        if f ~= nil then return math.max(0, math.min(100, tonumber(f) or 0)) end
        return nil -- not tracked by veyl_fuel (e.g. a vehicle it does not manage)
    elseif p == 'native' then
        local g = GetVehicleFuelLevel(veh)
        return g and math.max(0, math.min(100, g)) or nil
    end
    return nil
end
