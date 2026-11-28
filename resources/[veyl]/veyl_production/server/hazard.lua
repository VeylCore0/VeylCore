-- The fictional hazard around a working supplier station. Standing near a bench that is running a hazardous recipe builds an exposure
-- meter (0-100); protective gear cuts the build-up; at the threshold you take damage until you step away. The server does all of it: it
-- knows where the benches are, who is near them and what they carry. The page only shows the meter. A game mechanic, nothing real.

Prod = Prod or {}
Prod.Hazard = { exposure = {}, stations = {}, ticks = 0, warned = {}, sent = {} }
local H = Prod.Hazard
local C = ProductionConfig

local function cfg() return C.Supplier and C.Supplier.Hazard end

--- One step for every player. Safe to call by hand (tests do).
function H.tick()
    local h = cfg()
    if not h or not h.Enabled or not (C.Branches.supplier and C.Branches.supplier.enabled) then return end
    H.ticks = H.ticks + 1
    if H.ticks % 5 == 1 then H.stations = Prod.Ws.hazardous() end
    for _, s in ipairs(GetPlayers()) do
        local src = tonumber(s)
        local cid = Veyl.GetCitizenId(src)
        local pc = cid and Veyl.GetPlayerCoords(src)
        if pc then
            local near
            for _, st in ipairs(H.stations) do if ProdUtil.distance(pc, st) <= h.Radius then near = st break end end
            local e = H.exposure[src] or 0
            if near then
                local gain = h.GainPerTick
                if Prod.Inv.count(src, h.ProtectionItem) > 0 then gain = gain * (1 - h.ProtectionPercent) end
                e = math.min(100, e + gain)
            else
                e = math.max(0, e - h.DecayPerTick)
            end
            H.exposure[src] = e
            if e >= h.WarnAt and not H.warned[src] then
                H.warned[src] = true
                Veyl.Notify(src, 'The air around the station is getting to you. Step away or wear protection.', 'warning')
            elseif e < h.WarnAt then H.warned[src] = nil end
            if near and e >= h.Threshold then
                local ped = GetPlayerPed(src)
                SetEntityHealth(ped, math.max(1, GetEntityHealth(ped) - h.Damage))
                Prod.Police.maybeAlert(cid, 'hazard', near)
            end
            -- The page gets the meter when it changed enough to matter.
            local shown = math.floor(e)
            if math.abs(shown - (H.sent[src] or 0)) >= 4 or (shown == 0 and (H.sent[src] or 0) ~= 0) then
                H.sent[src] = shown
                TriggerClientEvent('veyl_production:hazard', src, shown)
            end
        end
    end
end

CreateThread(function()
    while true do
        local h = cfg()
        Wait(((h and h.TickSeconds) or 2) * 1000)
        if Prod.ready then
            local ok, err = pcall(H.tick)
            if not ok then print(('^1[veyl_production] hazard error: %s^7'):format(tostring(err))) end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    H.exposure[src], H.warned[src], H.sent[src] = nil, nil, nil
end)
