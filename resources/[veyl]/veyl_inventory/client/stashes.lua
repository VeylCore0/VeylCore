-- Stash access points. veyl_target is optional: without it, a vlib point shows an E prompt (ordinary open path).

local function openStash(id) CreateThread(function() OpenInventory(id) end) end

CreateThread(function()
    local useTarget = GetResourceState('veyl_target') == 'started'
    for _, s in ipairs(InventoryConfig.Stashes) do
        if useTarget then
            exports.veyl_target:addSphereZone({
                name = 'stash_' .. s.id, coords = s.coords, radius = s.radius or 1.5,
                options = { { name = 'open_' .. s.id, label = 'Open ' .. s.label, icon = 'box', distance = (s.radius or 1.5) + 1.0,
                    onSelect = function() openStash(s.id) end } },
            })
        else
            vlib.points.new({
                coords = s.coords, distance = s.radius or 1.5,
                onExit = function() vlib.hideTextUI() end,
                nearby = function()
                    if exports.veyl_inventory:IsOpen() then return vlib.hideTextUI() end
                    vlib.showTextUI('Open ' .. s.label, 'E')
                    if IsControlJustReleased(0, 38) then openStash(s.id) end
                end,
            })
        end
    end
end)
