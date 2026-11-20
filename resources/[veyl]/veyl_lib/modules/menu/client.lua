-- vlib menus (client). Runs inside the consumer resource; only plain data is sent to veyl_lib's NUI.
--
-- vlib.registerMenu({
--     id = 'delivery:depot', title = 'Delivery Depot', subtitle?, parent? = 'menu:id',
--     onClose? = function() end, onBack? = function() end,
--     options = { { id = 'start', label = 'Start shift', description?, icon?, right?, disabled?, disabledReason?,
--                   menu? = 'child:menu:id', onSelect? = function(args) end, args? } },
-- }, onSelect?(optionId, args))
-- vlib.showMenu(id) / vlib.hideMenu() / vlib.getOpenMenu()

local menus = {}
local openId = nil

local function displayOptions(def)
    local list = {}
    for i, o in ipairs(def.options or {}) do
        list[i] = {
            id = o.id, label = tostring(o.label or o.id), description = o.description, icon = o.icon,
            right = o.right ~= nil and tostring(o.right) or nil, disabled = o.disabled == true,
            disabledReason = o.disabledReason, hasChildren = o.menu ~= nil,
        }
    end
    return list
end

local function breadcrumb(def)
    local trail, cur, guard = {}, def, 0
    while cur and cur.parent and guard < 8 do
        cur = menus[cur.parent] and menus[cur.parent].def
        if cur then table.insert(trail, 1, cur.title) end
        guard = guard + 1
    end
    return trail
end

local M = {}

function M.registerMenu(def, onSelect)
    if type(def) ~= 'table' or type(def.id) ~= 'string' or def.id == '' then
        error(('vlib.registerMenu: menu needs a string id (resource %s)'):format(GetCurrentResourceName()), 2)
    end
    local seen = {}
    for i, o in ipairs(def.options or {}) do
        if type(o.id) ~= 'string' or o.id == '' then
            error(('vlib.registerMenu(%s): option %d needs a stable string id'):format(def.id, i), 2)
        end
        if seen[o.id] then error(('vlib.registerMenu(%s): duplicate option id %s'):format(def.id, o.id), 2) end
        seen[o.id] = true
    end
    menus[def.id] = { def = def, onSelect = onSelect }
end

function M.showMenu(id)
    local entry = menus[id]
    if not entry then error(('vlib.showMenu: unknown menu %s'):format(tostring(id)), 2) end
    local def = entry.def
    openId = id
    exports.veyl_lib:OpenMenu({
        id = def.id, title = def.title or def.id, subtitle = def.subtitle,
        breadcrumb = breadcrumb(def), options = displayOptions(def), canGoBack = def.parent ~= nil,
    }, function(result)
        if openId == id then openId = nil end
        if type(result) ~= 'table' then return end
        if result.type == 'select' then
            local opt
            for _, o in ipairs(def.options or {}) do if o.id == result.optionId then opt = o break end end
            if not opt or opt.disabled then return end
            if opt.menu then return M.showMenu(opt.menu) end
            if opt.onSelect then
                local ok, err = pcall(opt.onSelect, opt.args)
                if not ok then print(('^1[vlib] menu %s option %s failed: %s^7'):format(id, opt.id, err)) end
            end
            if entry.onSelect then
                local ok, err = pcall(entry.onSelect, opt.id, opt.args)
                if not ok then print(('^1[vlib] menu %s handler failed: %s^7'):format(id, err)) end
            end
        elseif result.type == 'back' then
            if def.onBack then pcall(def.onBack) end
            if def.parent and menus[def.parent] then M.showMenu(def.parent) end
        elseif result.type == 'close' then
            if def.onClose then pcall(def.onClose) end
        elseif result.type == 'rejected' or result.type == 'error' then
            print(('^3[vlib] menu %s could not open: %s^7'):format(id, tostring(result.reason or result.code)))
        end
    end)
end

function M.hideMenu()
    if openId then
        openId = nil
        exports.veyl_lib:CloseModal()
    end
end

function M.getOpenMenu() return openId end

return M
