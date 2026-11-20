-- veyl_ui routing: one provider, one open modal at a time, cleanup when the owning resource stops.
-- Exports take a trailing callback; call them with Veyl.UI.* from @veyl_core/lib/client.lua.

local P = UIConfig.Provider == 'veyl' and ProviderVeyl or ProviderVlib
local modal = nil     -- { owner }
local progress = nil  -- { owner }

local function runModal(kind, opts, cb)
    if modal then return cb(nil) end
    modal = { owner = GetInvokingResource() }
    CreateThread(function()
        local ok, result = pcall(P[kind], opts or {})
        modal = nil
        if not ok then
            print(('^1[veyl_ui] %s failed: %s^7'):format(kind, tostring(result)))
            result = nil
        end
        if kind == 'confirm' then result = result == true end
        pcall(cb, result)
    end)
end

exports('Confirm', function(opts, cb) runModal('confirm', opts, cb) end)
exports('Input', function(opts, cb) runModal('input', opts, cb) end)
exports('Menu', function(opts, cb) runModal('menu', opts, cb) end)
exports('IsModalOpen', function() return modal ~= nil end)

local function notify(data)
    if type(data) ~= 'table' or type(data.message) ~= 'string' then return end
    P.notify({ message = data.message:sub(1, 300), type = data.type or 'info', duration = tonumber(data.duration) or 4500 })
end

RegisterNetEvent('veyl_ui:notify', notify)
exports('Notify', function(message, kind, duration) notify({ message = message, type = kind, duration = duration }) end)

--- Progress({ label, duration, canCancel, disableMovement, anim = { dict, clip, flag } }, cb(bool))
exports('Progress', function(opts, cb)
    if progress then return cb(false) end
    opts = opts or {}
    opts.duration = math.max(250, math.min(tonumber(opts.duration) or 3000, 120000))
    opts.label = opts.label or 'Working...'
    progress = { owner = GetInvokingResource() }
    CreateThread(function()
        local ok, result = pcall(P.progress, opts)
        progress = nil
        pcall(cb, ok and result == true)
    end)
end)

exports('CancelProgress', function() if progress then P.cancelProgress() end end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        SetNuiFocus(false, false)
        return
    end
    if modal and modal.owner == res then P.closeModal() end
    if progress and progress.owner == res then P.cancelProgress() end
end)

AddEventHandler('onClientResourceStart', function(res)
    if res == GetCurrentResourceName() then SetNuiFocus(false, false) end
end)
