-- ox_lib provider: maps VeylCore UI requests onto ox_lib so the whole server shares one UI system.
ProviderOx = {}

local KIND = { success = 'success', error = 'error', warning = 'warning', info = 'inform' }

function ProviderOx.notify(data)
    lib.notify({ description = data.message, type = KIND[data.type] or 'inform', duration = data.duration or 4500, position = 'top-right' })
end

function ProviderOx.confirm(opts)
    local r = lib.alertDialog({
        header = opts.title or 'Are you sure?', content = opts.message or '', centered = true, cancel = true,
        labels = { confirm = opts.confirmLabel or 'Confirm', cancel = opts.cancelLabel or 'Cancel' },
    })
    return r == 'confirm'
end

function ProviderOx.input(opts)
    local fields = opts.fields or {}
    local rows = {}
    for i, f in ipairs(fields) do
        local row = { label = f.label or f.name, required = f.required == true, default = f.default, placeholder = f.placeholder }
        if f.type == 'number' then
            row.type, row.min, row.max = 'number', f.min, f.max
        elseif f.type == 'select' then
            row.type, row.options = 'select', f.options
        elseif f.type == 'date' then
            row.type, row.format = 'date', 'YYYY-MM-DD'
        else
            row.type, row.max = 'input', f.maxLength
        end
        rows[i] = row
    end
    local result = lib.inputDialog(opts.title or 'Enter details', rows)
    if not result then return nil end
    local values = {}
    for i, f in ipairs(fields) do values[f.name] = result[i] end
    return values
end

local menuSeq = 0

function ProviderOx.menu(opts)
    menuSeq = menuSeq + 1
    local id = ('veyl_ui_menu_%d'):format(menuSeq)
    local p = promise.new()
    local done = false
    local function finish(v)
        if done then return end
        done = true
        p:resolve(v)
    end
    local options = {}
    for i, item in ipairs(opts.items or {}) do
        local desc = item.description
        if item.right then desc = desc and (('%s  •  %s'):format(item.right, desc)) or tostring(item.right) end
        options[i] = {
            title = item.label or '', description = desc, disabled = item.disabled == true,
            onSelect = function() finish(item.value) end,
        }
    end
    if #options == 0 then options[1] = { title = opts.emptyText or 'Nothing here yet.', disabled = true } end
    lib.registerContext({ id = id, title = opts.subtitle and (('%s — %s'):format(opts.title or 'Menu', opts.subtitle)) or (opts.title or 'Menu'),
        options = options, onExit = function() finish(nil) end })
    lib.showContext(id)
    -- Guard: if the menu is closed by another resource without onExit, resolve when it is no longer open.
    CreateThread(function()
        Wait(250)
        while not done do
            if lib.getOpenContextMenu() ~= id then finish(nil) end
            Wait(250)
        end
    end)
    return Citizen.Await(p)
end

function ProviderOx.closeModal()
    lib.hideContext(false)
    lib.closeInputDialog()
    lib.closeAlertDialog()
end

function ProviderOx.progress(opts)
    return lib.progressBar({
        duration = opts.duration, label = opts.label, useWhileDead = false, canCancel = opts.canCancel ~= false,
        disable = { move = opts.disableMovement == true, car = true, combat = true },
        anim = opts.anim and opts.anim.dict and { dict = opts.anim.dict, clip = opts.anim.clip, flag = opts.anim.flag or 49 } or nil,
    }) == true
end

function ProviderOx.cancelProgress()
    if lib.progressActive() then lib.cancelProgress() end
end
