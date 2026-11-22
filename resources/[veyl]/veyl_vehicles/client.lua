-- veyl_vehicles client: reads and applies saved vehicle properties (cosmetics) and condition for owned vehicles.

local function getProps(veh)
    local p = {}
    p.color1, p.color2 = GetVehicleColours(veh)
    p.pearl, p.wheelColor = GetVehicleExtraColours(veh)
    p.wheelType = GetVehicleWheelType(veh)
    p.windowTint = GetVehicleWindowTint(veh)
    p.plateIndex = GetVehicleNumberPlateTextIndex(veh)
    p.livery = GetVehicleLivery(veh)
    p.dirt = math.floor(GetVehicleDirtLevel(veh))
    p.mods = {}
    for i = 0, 49 do p.mods[tostring(i)] = GetVehicleMod(veh, i) end
    p.toggles = { ['18'] = IsToggleModOn(veh, 18), ['20'] = IsToggleModOn(veh, 20), ['22'] = IsToggleModOn(veh, 22) }
    p.neon = {}
    for i = 0, 3 do p.neon[tostring(i)] = IsVehicleNeonLightEnabled(veh, i) end
    local r, g, b = GetVehicleNeonLightsColour(veh)
    p.neonColor = { r = r, g = g, b = b }
    r, g, b = GetVehicleTyreSmokeColor(veh)
    p.tyreSmoke = { r = r, g = g, b = b }
    p.extras = {}
    for i = 1, 14 do if DoesExtraExist(veh, i) then p.extras[tostring(i)] = IsVehicleExtraTurnedOn(veh, i) end end
    -- v2: custom RGB paint (the indexed colour keeps defining the finish), custom tyres, interior/dashboard, xenon colour.
    if GetIsVehiclePrimaryColourCustom(veh) then local r, g, b = GetVehicleCustomPrimaryColour(veh) p.customPrimary = { r = r, g = g, b = b } end
    if GetIsVehicleSecondaryColourCustom(veh) then local r, g, b = GetVehicleCustomSecondaryColour(veh) p.customSecondary = { r = r, g = g, b = b } end
    p.customTyres = GetVehicleModVariation(veh, 23)
    p.interiorColor = GetVehicleInteriorColor(veh)
    p.dashboardColor = GetVehicleDashboardColor(veh)
    p.xenonColor = GetVehicleXenonLightsColour(veh)
    return p
end

local function setProps(veh, p)
    if type(p) ~= 'table' then return end
    SetVehicleModKit(veh, 0)
    if p.color1 and p.color2 then SetVehicleColours(veh, p.color1, p.color2) end
    if type(p.customPrimary) == 'table' and p.customPrimary.r then SetVehicleCustomPrimaryColour(veh, p.customPrimary.r, p.customPrimary.g, p.customPrimary.b)
    elseif p.color1 then ClearVehicleCustomPrimaryColour(veh) end
    if type(p.customSecondary) == 'table' and p.customSecondary.r then SetVehicleCustomSecondaryColour(veh, p.customSecondary.r, p.customSecondary.g, p.customSecondary.b)
    elseif p.color2 then ClearVehicleCustomSecondaryColour(veh) end
    if type(p.interiorColor) == 'number' then SetVehicleInteriorColor(veh, p.interiorColor) end
    if type(p.dashboardColor) == 'number' then SetVehicleDashboardColor(veh, p.dashboardColor) end
    if type(p.xenonColor) == 'number' then SetVehicleXenonLightsColour(veh, p.xenonColor) end
    if p.pearl and p.wheelColor then SetVehicleExtraColours(veh, p.pearl, p.wheelColor) end
    if p.wheelType then SetVehicleWheelType(veh, p.wheelType) end
    if p.windowTint then SetVehicleWindowTint(veh, p.windowTint) end
    if p.plateIndex then SetVehicleNumberPlateTextIndex(veh, p.plateIndex) end
    if p.livery and p.livery >= 0 then SetVehicleLivery(veh, p.livery) end
    if p.dirt then SetVehicleDirtLevel(veh, p.dirt + 0.0) end
    for k, v in pairs(p.mods or {}) do
        local i = tonumber(k)
        if i and type(v) == 'number' then
            -- -1 = stock: remove the mod (restoring a factory part must actually restore it).
            if v >= 0 then SetVehicleMod(veh, i, v, (i == 23 or i == 24) and p.customTyres == true) else RemoveVehicleMod(veh, i) end
        end
    end
    for k, v in pairs(p.toggles or {}) do
        local i = tonumber(k)
        if i then ToggleVehicleMod(veh, i, v == true) end
    end
    for k, v in pairs(p.neon or {}) do
        local i = tonumber(k)
        if i then SetVehicleNeonLightEnabled(veh, i, v == true) end
    end
    if type(p.neonColor) == 'table' and p.neonColor.r then SetVehicleNeonLightsColour(veh, p.neonColor.r, p.neonColor.g, p.neonColor.b) end
    if type(p.tyreSmoke) == 'table' and p.tyreSmoke.r then SetVehicleTyreSmokeColor(veh, p.tyreSmoke.r, p.tyreSmoke.g, p.tyreSmoke.b) end
    for k, v in pairs(p.extras or {}) do
        local i = tonumber(k)
        if i and DoesExtraExist(veh, i) then SetVehicleExtra(veh, i, v ~= true) end -- native: true = disabled
    end
end

exports('GetVehicleProperties', function(veh) return veh and DoesEntityExist(veh) and getProps(veh) or nil end)
exports('SetVehicleProperties', function(veh, props) if veh and DoesEntityExist(veh) then setProps(veh, props) end end)

--- Sent to the player who took the vehicle out: apply saved looks and condition once the entity exists here.
RegisterNetEvent('veyl_vehicles:applyOwned', function(netId, props, engine, body)
    local deadline = GetGameTimer() + 10000
    while not NetworkDoesNetworkIdExist(netId) and GetGameTimer() < deadline do Wait(50) end
    if not NetworkDoesNetworkIdExist(netId) then return end
    local veh = NetToVeh(netId)
    deadline = GetGameTimer() + 3000
    NetworkRequestControlOfEntity(veh)
    while not NetworkHasControlOfEntity(veh) and GetGameTimer() < deadline do Wait(25) NetworkRequestControlOfEntity(veh) end
    setProps(veh, props)
    if tonumber(engine) then SetVehicleEngineHealth(veh, math.max(100.0, engine + 0.0)) end
    if tonumber(body) then SetVehicleBodyHealth(veh, math.max(100.0, body + 0.0)) end
end)
