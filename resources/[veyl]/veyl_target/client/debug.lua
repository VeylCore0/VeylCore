-- Developer mode: `setr veyl_target:debug true` draws nearby zones. Visual aid only (no permissions granted).
if GetConvar('veyl_target:debug', 'false') ~= 'true' then return end

CreateThread(function()
    while true do
        local pos = GetEntityCoords(PlayerPedId())
        for _, z in pairs(Registry.zones) do
            local zone = z.zone
            if #(pos - zone.coords) < 50.0 then
                if zone.kind == 'sphere' then
                    DrawMarker(28, zone.coords.x, zone.coords.y, zone.coords.z, 0, 0, 0, 0, 0, 0,
                        zone.radius, zone.radius, zone.radius, 139, 92, 246, 60, false, false, 2, false, nil, nil, false)
                else
                    DrawMarker(43, zone.coords.x, zone.coords.y, zone.coords.z - zone.half.z, 0, 0, 0, 0, 0, zone.rotation,
                        zone.size.x, zone.size.y, zone.size.z, 139, 92, 246, 60, false, false, 2, false, nil, nil, false)
                end
            end
        end
        Wait(0)
    end
end)
