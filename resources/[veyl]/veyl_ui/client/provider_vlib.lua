-- veyl_lib provider: forwards the legacy veyl_ui API to veyl_lib (one focus broker, one visual system).
ProviderVlib = {}

function ProviderVlib.notify(data)
    vlib.notify({ message = data.message, type = data.type, duration = data.duration })
end

function ProviderVlib.confirm(opts)
    return vlib.alertDialog({ title = opts.title, message = opts.message, confirmLabel = opts.confirmLabel,
        cancelLabel = opts.cancelLabel, destructive = opts.destructive }) == 'confirm'
end

function ProviderVlib.input(opts)
    return vlib.inputDialog(opts.title or 'Enter details', opts.fields or {}, { submitLabel = opts.submitLabel })
end

local menuSeq = 0

function ProviderVlib.menu(opts)
    menuSeq = menuSeq + 1
    local id = ('veyl_ui:menu:%d'):format(menuSeq)
    local p = promise.new()
    local done = false
    local function finish(v) if not done then done = true p:resolve(v) end end
    local values, options = {}, {}
    for i, item in ipairs(opts.items or {}) do
        local optId = 'o' .. i
        values[optId] = item.value
        options[i] = { id = optId, label = item.label or '', description = item.description,
            right = item.right, disabled = item.disabled == true }
    end
    vlib.registerMenu({ id = id, title = opts.title or 'Menu', subtitle = opts.subtitle, options = options,
        onClose = function() finish(nil) end }, function(optionId) finish(values[optionId]) end)
    vlib.showMenu(id)
    -- If the menu could not open (rejected/busy) or was closed by another path, resolve instead of hanging.
    CreateThread(function()
        Wait(300)
        while not done do
            if vlib.getOpenMenu() ~= id then finish(nil) end
            Wait(250)
        end
    end)
    return Citizen.Await(p)
end

function ProviderVlib.closeModal() vlib.hideMenu() end

function ProviderVlib.progress(opts)
    return vlib.progress({
        label = opts.label, duration = opts.duration, canCancel = opts.canCancel ~= false,
        disable = { move = opts.disableMovement == true, car = true, combat = true }, anim = opts.anim,
    })
end

function ProviderVlib.cancelProgress() vlib.cancelProgress() end
