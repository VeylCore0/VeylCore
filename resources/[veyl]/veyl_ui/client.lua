-- veyl_ui: the single owner of shared modal UI focus.
-- Modals (confirm/input/menu) are exclusive; a second request while one is open returns nil.
-- Every path that opens focus has a matching close: result, Escape, owner resource stop, own stop.

local modal = nil      -- { kind, cb, owner }
local progress = nil   -- { cb, owner, cancelled }

local function closeModal(value)
    if not modal then return end
    local m = modal
    modal = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'modal:close' })
    local ok, err = pcall(m.cb, value)
    if not ok then print(('^1[veyl_ui] modal callback error: %s^7'):format(tostring(err))) end
end

local function openModal(kind, opts, cb)
    if modal then
        cb(nil)
        return
    end
    modal = { kind = kind, cb = cb, owner = GetInvokingResource() }
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'modal:open', kind = kind, data = opts or {} })
end

RegisterNUICallback('modal:result', function(data, nuiCb)
    nuiCb({})
    if not modal then return end
    if modal.kind == 'confirm' then
        closeModal(data and data.value == true)
    else
        closeModal(data and data.value or nil)
    end
end)

RegisterNUICallback('modal:cancel', function(_, nuiCb)
    nuiCb({})
    if not modal then return end
    closeModal(modal.kind == 'confirm' and false or nil)
end)

exports('Confirm', function(opts, cb) openModal('confirm', opts, cb) end)
exports('Input', function(opts, cb) openModal('input', opts, cb) end)
exports('Menu', function(opts, cb) openModal('menu', opts, cb) end)
exports('IsModalOpen', function() return modal ~= nil end)

---------------------------------------------------------------------------
-- Notifications
---------------------------------------------------------------------------
local function notify(data)
    if type(data) ~= 'table' or type(data.message) ~= 'string' then return end
    SendNUIMessage({
        action = 'notify',
        message = data.message:sub(1, 300),
        type = data.type or 'info',
        duration = tonumber(data.duration) or 4500,
    })
end

RegisterNetEvent('veyl_ui:notify', notify)
exports('Notify', function(message, kind, duration) notify({ message = message, type = kind, duration = duration }) end)

---------------------------------------------------------------------------
-- Progress bar: Progress({ label, duration, canCancel, disableMovement, anim = { dict, clip, flag } }, cb)
---------------------------------------------------------------------------
exports('Progress', function(opts, cb)
    if progress then cb(false) return end
    opts = opts or {}
    local duration = math.max(250, math.min(tonumber(opts.duration) or 3000, 120000))
    progress = { cb = cb, owner = GetInvokingResource(), cancelled = false }
    SendNUIMessage({ action = 'progress:start', label = opts.label or 'Working...', duration = duration })

    CreateThread(function()
        local ped = PlayerPedId()
        local anim = opts.anim
        if anim and anim.dict and Veyl.LoadAnimDict(anim.dict) then
            TaskPlayAnim(ped, anim.dict, anim.clip, 3.0, 3.0, -1, anim.flag or 49, 0, false, false, false)
        end
        local finishAt = GetGameTimer() + duration
        while progress and not progress.cancelled and GetGameTimer() < finishAt do
            if opts.disableMovement then
                DisableControlAction(0, 30, true) DisableControlAction(0, 31, true)
                DisableControlAction(0, 21, true) DisableControlAction(0, 22, true)
            end
            DisableControlAction(0, 24, true) DisableControlAction(0, 25, true)
            if opts.canCancel ~= false and IsControlJustPressed(0, 73) then -- X
                progress.cancelled = true
            end
            if IsEntityDead(ped) then progress.cancelled = true end
            Wait(0)
        end
        if anim and anim.dict then StopAnimTask(ped, anim.dict, anim.clip, 1.0) end
        local p = progress
        progress = nil
        SendNUIMessage({ action = 'progress:stop' })
        if p then pcall(p.cb, not p.cancelled) end
    end)
end)

exports('CancelProgress', function()
    if progress then progress.cancelled = true end
end)

---------------------------------------------------------------------------
-- Cleanup: never leave focus or a bar behind
---------------------------------------------------------------------------
AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        SetNuiFocus(false, false)
        return
    end
    if modal and modal.owner == res then closeModal(nil) end
    if progress and progress.owner == res then progress.cancelled = true end
end)

AddEventHandler('onClientResourceStart', function(res)
    if res == GetCurrentResourceName() then SetNuiFocus(false, false) end
end)
