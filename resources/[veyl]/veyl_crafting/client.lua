-- veyl_crafting client: bench menus and the crafting progress. The server checks materials, level and time.

local C = CraftingConfig
local function cb(name, ...) return Veyl.CallbackTimeout('veyl_crafting', name, 15000, ...) end

local function open(id)
    local res = cb('bench', id)
    if not res.ok then return Veyl.NotifyResult(res) end
    local d = res.data
    local defs = exports.veyl_inventory:Items() or {}
    local function name(item) return defs[item] and defs[item].label or item:gsub('_', ' ') end
    local items = {}
    for i, rc in ipairs(d.recipes) do
        local parts = {}
        for item, n in pairs(rc.inputs) do parts[#parts + 1] = ('%dx %s'):format(n, name(item)) end
        table.sort(parts)
        items[#items + 1] = { value = tostring(i), disabled = rc.locked,
            label = ('%s%s'):format(rc.count > 1 and (rc.count .. 'x ') or '', name(rc.output)),
            description = rc.locked and ('Needs crafting level %d'):format(rc.level) or table.concat(parts, ', '),
            right = rc.locked and 'Locked' or (rc.can and ('%ds'):format(rc.seconds) or 'Missing') }
    end
    local pick = Veyl.UI.Menu({ title = d.label, subtitle = ('Crafting level %d · %d / %d xp'):format(d.level, d.xp, d.next), items = items })
    if not pick then return end
    local start = cb('start', id, tonumber(pick))
    if not start.ok then return Veyl.NotifyResult(start) end
    local b = C.Benches[id]
    if b.scenario then TaskStartScenarioInPlace(PlayerPedId(), b.scenario, 0, true) end
    local ok = vlib.progress({ label = 'Crafting', duration = start.data.seconds * 1000, canCancel = true, disable = { move = true, car = true, combat = true } })
    ClearPedTasks(PlayerPedId())
    if not ok then return Veyl.Notify('Stopped', 'info') end
    Veyl.NotifyResult(cb('finish', start.data.token))
end

AddEventHandler('veyl_crafting:open', function(a) CreateThread(function() open(a.id) end) end)

CreateThread(function()
    while GetResourceState('veyl_interact') ~= 'started' do Wait(250) end
    for id, b in pairs(C.Benches) do
        exports.veyl_interact:AddZone({ id = 'veyl_craft_' .. id, coords = b.coords, radius = 1.6, title = b.label,
            options = { { label = 'Use ' .. b.label:lower(), icon = 'wrench', event = 'veyl_crafting:open', args = { id = id }, groups = b.groups } } })
        if b.blip then
            local bl = AddBlipForCoord(b.coords.x, b.coords.y, b.coords.z)
            SetBlipSprite(bl, b.blip.sprite) SetBlipColour(bl, b.blip.colour) SetBlipScale(bl, 0.7) SetBlipAsShortRange(bl, true)
            BeginTextCommandSetBlipName('STRING') AddTextComponentSubstringPlayerName(b.label) EndTextCommandSetBlipName(bl)
        end
    end
end)
