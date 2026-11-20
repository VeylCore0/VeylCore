-- veyl_inventory client: menu-based inventory, item use animations and stashes.

local using = false

local ANIMS = {
    drink = { dict = 'mp_player_intdrink', clip = 'loop_bottle', flag = 49 },
    eat = { dict = 'mp_player_inteat@burger', clip = 'mp_player_int_eat_burger', flag = 49 },
    bandage = { dict = 'missheistdockssetup1clipboard@idle_a', clip = 'idle_a', flag = 49 },
}

local function kg(g) return ('%.1fkg'):format((g or 0) / 1000) end

exports('GetItemDefinition', function(item) return Items[item] end)

local function useItem(item)
    if using then return end
    local def = Items[item]
    if not def or not def.usable then return end
    using = true
    local done = Veyl.UI.Progress({ label = 'Using ' .. def.label, duration = def.useTime or 2500, anim = ANIMS[def.anim], canCancel = true })
    if done then Veyl.NotifyResult(Veyl.Callback('veyl_inventory', 'use', item)) end
    using = false
end

local function openInventory()
    if not Veyl.IsLoaded() or using then return end
    while true do
        local res = Veyl.Callback('veyl_inventory', 'list')
        if not res.ok then return Veyl.NotifyResult(res) end
        local items = {}
        for _, it in ipairs(res.data.items) do
            items[#items + 1] = { label = it.label, description = kg(it.weight * it.count), right = 'x' .. it.count, value = it.name }
        end
        local choice = Veyl.UI.Menu({
            title = 'Inventory', subtitle = ('%s / %s'):format(kg(res.data.weight), kg(res.data.maxWeight)),
            items = items, emptyText = 'Your pockets are empty.',
        })
        if not choice then return end
        local def = Items[choice]
        local actions = {}
        if def.usable then actions[#actions + 1] = { label = 'Use', value = 'use' } end
        actions[#actions + 1] = { label = 'Give to player', description = 'Hand items to a nearby player by server ID', value = 'give' }
        local action = Veyl.UI.Menu({ title = def.label, items = actions })
        if action == 'use' then
            useItem(choice)
            return
        elseif action == 'give' then
            local v = Veyl.UI.Input({
                title = 'Give ' .. def.label,
                fields = {
                    { name = 'target', label = 'Player server ID', type = 'number', min = 1, required = true },
                    { name = 'count', label = 'Amount', type = 'number', min = 1, max = 50, default = 1, required = true },
                },
            })
            if v then Veyl.NotifyResult(Veyl.Callback('veyl_inventory', 'give', math.floor(v.target), choice, math.floor(v.count))) end
        end
    end
end

RegisterCommand('inventory', function() CreateThread(openInventory) end, false)
RegisterKeyMapping('inventory', 'Open inventory', 'keyboard', 'F2')

RegisterNetEvent('veyl_inventory:heal', function(amount)
    local ped = PlayerPedId()
    local amt = math.min(tonumber(amount) or 0, 100)
    SetEntityHealth(ped, math.min(GetEntityMaxHealth(ped), GetEntityHealth(ped) + amt))
end)

---------------------------------------------------------------------------
-- Stashes
---------------------------------------------------------------------------
local function openStash(stashId)
    while true do
        local res = Veyl.Callback('veyl_inventory', 'stashList', stashId)
        if not res.ok then return Veyl.NotifyResult(res) end
        local d = res.data
        local dir = Veyl.UI.Menu({
            title = d.label, subtitle = ('Stash %s / %s'):format(kg(d.stash.weight), kg(d.stash.maxWeight)),
            items = { { label = 'Store items', value = 'in' }, { label = 'Take items', value = 'out' } },
        })
        if not dir then return end
        local source = dir == 'in' and d.player.items or d.stash.items
        local items = {}
        for _, it in ipairs(source) do items[#items + 1] = { label = it.label, right = 'x' .. it.count, value = it.name } end
        local item = Veyl.UI.Menu({ title = dir == 'in' and 'Store which item?' or 'Take which item?', items = items, emptyText = 'Nothing to move.' })
        if item then
            local v = Veyl.UI.Input({ title = 'How many?', fields = { { name = 'count', label = 'Amount', type = 'number', min = 1, max = 50, default = 1, required = true } } })
            if v then Veyl.NotifyResult(Veyl.Callback('veyl_inventory', 'stashMove', stashId, dir, item, math.floor(v.count)), 'Done') end
        end
    end
end

AddEventHandler('veyl_inventory:openStash', function(args)
    if Veyl.IsLoaded() and args and args.id then openStash(args.id) end
end)

CreateThread(function()
    while GetResourceState('veyl_interact') ~= 'started' do Wait(200) end
    for _, s in ipairs(InventoryConfig.Stashes) do
        exports.veyl_interact:AddZone({
            id = 'stash_' .. s.id, coords = s.coords, radius = s.radius or 2.0,
            label = 'Open ' .. s.label, event = 'veyl_inventory:openStash', args = { id = s.id },
        })
    end
end)
