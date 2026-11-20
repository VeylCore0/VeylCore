-- VeylCore NUI provider (web/). Every function yields until the user answers; main.lua owns exclusivity.
ProviderVeyl = {}

local pendingModal = nil -- promise for the open modal

RegisterNUICallback('modal:result', function(data, cb)
    cb({})
    local p = pendingModal
    if not p then return end
    pendingModal = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'modal:close' })
    p:resolve({ ok = true, value = data and data.value })
end)

RegisterNUICallback('modal:cancel', function(_, cb)
    cb({})
    local p = pendingModal
    if not p then return end
    pendingModal = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'modal:close' })
    p:resolve({ ok = false })
end)

local function modal(kind, opts)
    pendingModal = promise.new()
    local p = pendingModal
    SetNuiFocus(true, true)
    SendNUIMessage({ action = 'modal:open', kind = kind, data = opts or {} })
    return Citizen.Await(p)
end

function ProviderVeyl.closeModal()
    local p = pendingModal
    pendingModal = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'modal:close' })
    if p then p:resolve({ ok = false }) end
end

function ProviderVeyl.notify(data)
    SendNUIMessage({ action = 'notify', message = data.message, type = data.type, duration = data.duration })
end

function ProviderVeyl.confirm(opts)
    local r = modal('confirm', opts)
    return r.ok and r.value == true
end

function ProviderVeyl.input(opts)
    local r = modal('input', opts)
    return r.ok and r.value or nil
end

function ProviderVeyl.menu(opts)
    local r = modal('menu', opts)
    return r.ok and r.value or nil
end

local progressCancel = false

function ProviderVeyl.progress(opts)
    progressCancel = false
    SendNUIMessage({ action = 'progress:start', label = opts.label, duration = opts.duration })
    local ped = PlayerPedId()
    local anim = opts.anim
    if anim and anim.dict and Veyl.LoadAnimDict(anim.dict) then
        TaskPlayAnim(ped, anim.dict, anim.clip, 3.0, 3.0, -1, anim.flag or 49, 0, false, false, false)
    end
    local finishAt = GetGameTimer() + opts.duration
    local cancelled = false
    while GetGameTimer() < finishAt do
        if opts.disableMovement then
            DisableControlAction(0, 30, true) DisableControlAction(0, 31, true)
            DisableControlAction(0, 21, true) DisableControlAction(0, 22, true)
        end
        DisableControlAction(0, 24, true) DisableControlAction(0, 25, true)
        if (opts.canCancel ~= false and IsControlJustPressed(0, 73)) or progressCancel or IsEntityDead(ped) then
            cancelled = true
            break
        end
        Wait(0)
    end
    if anim and anim.dict then StopAnimTask(ped, anim.dict, anim.clip, 1.0) end
    SendNUIMessage({ action = 'progress:stop' })
    return not cancelled
end

function ProviderVeyl.cancelProgress() progressCancel = true end
