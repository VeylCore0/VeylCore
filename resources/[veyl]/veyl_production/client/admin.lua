-- /drugadmin: the staff menu for farms. Everything is stored and checked on the server (it re-checks the permission on every request);
-- this only shows menus and sends what you pick. Farms you add appear for everyone at once.

local function call(name, ...) return Veyl.CallbackTimeout('veyl_production', name, 15000, ...) end

local state
local openMain, openFarm, openRewards, openPlayers, openPlayer

local function reload()
    local r = call('adminState')
    if not r.ok then Veyl.NotifyResult(r) return false end
    state = r.data
    return true
end

local function find(id) for _, f in ipairs(state.farms) do if f.id == id then return f end end end

local function itemOptions()
    local out = {}
    for _, i in ipairs(state.items) do out[#out + 1] = { value = i.item, label = i.label } end
    return out
end

local function labelOf(item) for _, i in ipairs(state.items) do if i.item == item then return i.label end end return item end

local function createFarm()
    local opts = {}
    for _, p in ipairs(state.presets) do opts[#opts + 1] = { value = p.kind, label = ('%s (%s)'):format(p.label, p.branch) } end
    local v = vlib.inputDialog('New farm at your position', {
        { name = 'kind', label = 'Kind', type = 'select', required = true, options = opts, default = opts[1] and opts[1].value },
        { name = 'label', label = 'Name (optional)', type = 'text', maxLength = 40, placeholder = 'Leave empty for the default name' },
    }, { submitLabel = 'Create here' })
    if not v then return openMain() end
    local r = call('farmCreate', v.kind, v.label or '')
    Veyl.NotifyResult(r)
    if r.ok then openFarm(r.data.id) else openMain() end
end

local function removePoint(f)
    local me = GetEntityCoords(PlayerPedId())
    local opts = {}
    for i, p in ipairs(f.points) do
        opts[#opts + 1] = { value = tostring(i), label = ('#%d  (%.0f m away)'):format(i, #(me - vector3(p.x, p.y, p.z))) }
    end
    local v = vlib.inputDialog('Remove which point?', { { name = 'index', label = 'Point', type = 'select', required = true, options = opts, default = opts[#opts].value } }, { submitLabel = 'Remove' })
    if v then Veyl.NotifyResult(call('farmRemovePoint', f.id, tonumber(v.index))) end
    openFarm(f.id)
end

local function settings(f)
    local v = vlib.inputDialog(f.label, {
        { name = 'label', label = 'Name', type = 'text', required = true, maxLength = 40, default = f.label },
        { name = 'level', label = ('Level needed (1 to %d)'):format(#ProductionConfig.LevelNames), type = 'number', required = true, min = 1, max = #ProductionConfig.LevelNames, default = f.level },
        { name = 'respawn', label = 'Point respawns for everyone after (minutes)', type = 'number', required = true, min = 1, max = 1440, default = f.respawn },
        { name = 'cooldown', label = 'Same player can search a point again after (minutes)', type = 'number', required = true, min = 1, max = 1440, default = f.cooldown },
        { name = 'prop', label = 'Prop model shown at each point', type = 'text', required = true, maxLength = 64, default = f.prop },
    }, { submitLabel = 'Save' })
    if v then
        Veyl.NotifyResult(call('farmUpdate', f.id, { label = v.label, level = tonumber(v.level), respawn = tonumber(v.respawn), cooldown = tonumber(v.cooldown), prop = v.prop }))
    end
    openFarm(f.id)
end

local function rewardDialog(f, idx)
    local r = idx and f.rewards[idx] or { item = state.items[1] and state.items[1].item, chance = 0.2, min = 1, max = 1 }
    local fields = {
        { name = 'item', label = 'Item', type = 'select', required = true, options = itemOptions(), default = r.item },
        { name = 'chance', label = 'Chance per search (percent, 1 to 100)', type = 'number', required = true, min = 1, max = 100, default = math.floor(r.chance * 100 + 0.5) },
        { name = 'min', label = 'Least you can find', type = 'number', required = true, min = 1, max = 50, default = r.min },
        { name = 'max', label = 'Most you can find', type = 'number', required = true, min = 1, max = 50, default = r.max },
        { name = 'level', label = 'Branch level needed for this reward (0 = none)', type = 'number', min = 0, max = #ProductionConfig.LevelNames, default = r.level or 0 },
    }
    if idx then fields[#fields + 1] = { name = 'remove', label = 'Remove this reward', type = 'checkbox' } end
    local v = vlib.inputDialog(idx and 'Edit reward' or 'Add a reward', fields, { submitLabel = 'Save' })
    if not v then return openRewards(f.id) end
    local list = {}
    for i, x in ipairs(f.rewards) do list[i] = { item = x.item, chance = x.chance, min = x.min, max = x.max, level = x.level } end
    if idx and v.remove then
        table.remove(list, idx)
    else
        local lv = tonumber(v.level)
        local entry = { item = v.item, chance = (tonumber(v.chance) or 1) / 100, min = tonumber(v.min), max = tonumber(v.max), level = (lv and lv > 0) and lv or nil }
        if idx then list[idx] = entry else list[#list + 1] = entry end
    end
    Veyl.NotifyResult(call('farmRewards', f.id, list))
    openRewards(f.id)
end

function openRewards(id)
    if not reload() then return end
    local f = find(id)
    if not f then return openMain() end
    local opts = { { id = 'add', label = 'Add a reward', icon = 'plus', onSelect = function() CreateThread(function() rewardDialog(f) end) end } }
    for i, r in ipairs(f.rewards) do
        opts[#opts + 1] = { id = 'r' .. i, label = ('%s  x%d-%d'):format(labelOf(r.item), r.min, r.max), description = r.level and ('Needs level %d'):format(r.level) or nil,
            right = ('%d%%'):format(math.floor(r.chance * 100 + 0.5)), onSelect = function() CreateThread(function() rewardDialog(f, i) end) end }
    end
    vlib.registerMenu({ id = 'prodadmin:rewards', title = 'Rewards', subtitle = f.label .. '. The first reward always pays.', parent = 'prodadmin:farm', options = opts })
    vlib.showMenu('prodadmin:rewards')
end

function openFarm(id)
    if not reload() then return end
    local f = find(id)
    if not f then return openMain() end
    local first = f.points[1]
    local opts = {
        { id = 'add', label = 'Add a point here', description = 'The spot you are standing on becomes another place to search', icon = 'plus',
            onSelect = function() CreateThread(function() Veyl.NotifyResult(call('farmAddPoint', f.id)) openFarm(f.id) end) end },
        { id = 'remove', label = 'Remove a point', disabled = #f.points <= 1, disabledReason = 'A farm needs one point', onSelect = function() CreateThread(function() removePoint(f) end) end },
        { id = 'rewards', label = 'Rewards', description = 'What a search can give', right = tostring(#f.rewards), onSelect = function() CreateThread(function() openRewards(f.id) end) end },
        { id = 'settings', label = 'Name, level and timings', onSelect = function() CreateThread(function() settings(f) end) end },
        { id = 'gps', label = 'Set GPS to the first point', onSelect = function() SetNewWaypoint(first.x + 0.0, first.y + 0.0) Veyl.Notify('GPS set', 'success') CreateThread(function() openFarm(f.id) end) end },
        { id = 'goto', label = 'Teleport to the first point', onSelect = function()
            local ped = PlayerPedId()
            SetEntityCoords(ped, first.x + 0.0, first.y + 0.0, first.z + 1.0, false, false, false, false)
        end },
        { id = 'delete', label = 'Delete this farm', description = 'Its points disappear for everyone', icon = 'trash', onSelect = function() CreateThread(function()
            if vlib.alertDialog({ title = 'Delete ' .. f.label .. '?', message = 'This removes the farm and all of its points.', confirmLabel = 'Delete', destructive = true }) == 'confirm' then
                Veyl.NotifyResult(call('farmDelete', f.id))
                return openMain()
            end
            openFarm(f.id)
        end) end },
    }
    vlib.registerMenu({ id = 'prodadmin:farm', title = f.label, subtitle = ('%s · level %d · %d points · respawn %d min · cooldown %d min'):format(f.kind, f.level, #f.points, f.respawn, f.cooldown),
        parent = 'prodadmin:main', options = opts })
    vlib.showMenu('prodadmin:farm')
end

local function ago(at) local s = math.max(0, GetCloudTimeAsInt() - at) return s < 3600 and ('%d min ago'):format(s // 60) or ('%d h ago'):format(s // 3600) end

local function showLog(title, target)
    local r = call('adminLog', target)
    if not r.ok then return Veyl.NotifyResult(r) end
    local opts = {}
    for i, l in ipairs(r.data) do opts[#opts + 1] = { id = 'l' .. i, label = l.text, description = ('%s · %s · %s'):format(l.kind, l.citizenid, ago(l.at)) } end
    if #opts == 0 then opts[1] = { id = 'none', label = 'Nothing logged yet', disabled = true } end
    vlib.registerMenu({ id = 'prodadmin:log', title = title, subtitle = 'Latest 25', parent = target and 'prodadmin:player' or 'prodadmin:main', options = opts })
    vlib.showMenu('prodadmin:log')
end

function openPlayer(cid)
    local r = call('adminPlayer', cid)
    if not r.ok then Veyl.NotifyResult(r) return openPlayers() end
    local d = r.data
    local opts = {}
    for _, b in ipairs(d.branches) do opts[#opts + 1] = { id = 'b' .. b.id, label = b.label, right = ('level %d · %d XP'):format(b.level, b.xp), disabled = true } end
    opts[#opts + 1] = { id = 'plants', label = ('Plants (%d)'):format(#d.plants), description = ('%d benches. Pick one to remove it'):format(d.benches), menu = nil, onSelect = function() CreateThread(function()
        if #d.plants == 0 then Veyl.Notify('They have no plants', 'info') return openPlayer(cid) end
        local list = {}
        for _, p in ipairs(d.plants) do list[#list + 1] = { value = tostring(p.id), label = ('#%d %s (%s%s)'):format(p.id, p.label, p.state, p.lab and ', in a lab' or '') } end
        local v = vlib.inputDialog('Remove which plant?', { { name = 'id', label = 'Plant', type = 'select', required = true, options = list, default = list[1].value } }, { submitLabel = 'Remove' })
        if v then Veyl.NotifyResult(call('adminRemovePlant', tonumber(v.id))) end
        openPlayer(cid)
    end) end }
    opts[#opts + 1] = { id = 'xp', label = 'Give or take XP', onSelect = function() CreateThread(function()
        local bo = {}
        for _, b in ipairs(d.branches) do bo[#bo + 1] = { value = b.id, label = b.label } end
        local v = vlib.inputDialog('XP for ' .. d.name, {
            { name = 'branch', label = 'Branch', type = 'select', required = true, options = bo, default = bo[1].value },
            { name = 'amount', label = 'Amount (negative takes XP away)', type = 'number', required = true, min = -100000, max = 100000, default = 100 },
        }, { submitLabel = 'Apply' })
        if v then Veyl.NotifyResult(call('adminGiveXp', cid, v.branch, tonumber(v.amount))) end
        openPlayer(cid)
    end) end }
    opts[#opts + 1] = { id = 'cool', label = 'Reset their cooldowns', description = 'Searches, harvests, runs, purchases', onSelect = function() CreateThread(function() Veyl.NotifyResult(call('adminResetCooldowns', cid)) openPlayer(cid) end) end }
    opts[#opts + 1] = { id = 'log', label = 'Their log', onSelect = function() CreateThread(function() showLog(d.name, cid) end) end }
    vlib.registerMenu({ id = 'prodadmin:player', title = d.name, subtitle = d.crew and ('Crew: ' .. d.crew) or 'No crew', parent = 'prodadmin:players', options = opts })
    vlib.showMenu('prodadmin:player')
end

function openPlayers()
    local r = call('adminPlayers')
    if not r.ok then return Veyl.NotifyResult(r) end
    local opts = {}
    for _, p in ipairs(r.data) do opts[#opts + 1] = { id = 'p' .. p.cid, label = p.name, right = ('id %d'):format(p.id), onSelect = function() CreateThread(function() openPlayer(p.cid) end) end } end
    vlib.registerMenu({ id = 'prodadmin:players', title = 'Players online', subtitle = ('%d online'):format(#opts), parent = 'prodadmin:main', options = opts })
    vlib.showMenu('prodadmin:players')
end

function openMain()
    if not reload() then return end
    local opts = {
        { id = 'new', label = 'Add a farm here', description = 'Weed, coke, mushroom or custom, starting at your position', icon = 'plus', onSelect = function() CreateThread(createFarm) end },
        { id = 'players', label = 'Players', description = 'Plants, XP, cooldowns and logs of who is online', icon = 'users', onSelect = function() CreateThread(openPlayers) end },
        { id = 'log', label = 'Recent activity', description = 'Everything players did, newest first', onSelect = function() CreateThread(function() showLog('Recent activity') end) end },
    }
    for _, f in ipairs(state.farms) do
        opts[#opts + 1] = { id = 'f' .. f.id, label = f.label, description = ('%s · level %d'):format(f.kind, f.level), right = ('%d points'):format(#f.points),
            onSelect = function() CreateThread(function() openFarm(f.id) end) end }
    end
    vlib.registerMenu({ id = 'prodadmin:main', title = 'Drug admin', subtitle = ('%d of %d farms'):format(#state.farms, state.max.farms), options = opts })
    vlib.showMenu('prodadmin:main')
end

RegisterCommand('drugadmin', function()
    if not Veyl.IsLoaded() then return end
    CreateThread(openMain)
end, false)
