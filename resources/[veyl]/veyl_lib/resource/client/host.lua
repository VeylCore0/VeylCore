-- veyl_lib client host: the ONE modal focus broker, the NUI page for utility UI, and progress execution.
--
-- Focus rules (plan §3):
--   * Only one full modal owns keyboard/mouse input. Conflicting requests are rejected with reason 'busy'.
--   * A resource receives an ownership token and applies SetNuiFocus to ITS OWN page (Cfx focus is per resource).
--   * Passive UI (notify, text prompts, progress) never takes focus.
--   * Owner resource stop / explicit release / broker restart clears ownership and restores controls.

local uiReady = false
local uiDeadline = nil
local UI_TIMEOUT_MS = 10000

local focus = nil        -- { token, owner, kind }
local hostModal = nil    -- { token, cb, owner, kind } for modals rendered by veyl_lib itself
local progress = nil     -- { owner, cancelled, cb }
local textUIOwner = nil
local tokenSeq = 0

local function newToken(owner)
    tokenSeq = tokenSeq + 1
    return ('%s:%d:%d'):format(owner or '?', GetGameTimer(), tokenSeq)
end

---------------------------------------------------------------------------
-- Focus broker
---------------------------------------------------------------------------
local function releaseFocus(token, reason)
    if not focus or focus.token ~= token then return false end
    local f = focus
    focus = nil
    if f.owner == GetCurrentResourceName() then SetNuiFocus(false, false) end
    TriggerEvent('veyl_lib:focusReleased', f.token, f.owner, reason or 'released')
    return true
end

--- RequestFocus(kind?) -> token | nil, reason. The caller must SetNuiFocus on its own page after success.
local function requestFocus(owner, kind)
    if focus then return nil, 'busy' end
    focus = { token = newToken(owner), owner = owner, kind = kind or 'modal' }
    return focus.token
end

exports('RequestFocus', function(kind)
    return requestFocus(GetInvokingResource() or GetCurrentResourceName(), kind)
end)

exports('ReleaseFocus', function(token) return releaseFocus(token, 'released') end)
exports('IsModalOpen', function() return focus ~= nil end)
exports('GetFocusOwner', function() return focus and focus.owner or nil end)

---------------------------------------------------------------------------
-- NUI page lifecycle (bounded readiness)
---------------------------------------------------------------------------
RegisterNUICallback('ui:ready', function(_, cb)
    uiReady = true
    cb({ ok = true })
end)

local function ensureUI()
    if uiReady then return true end
    uiDeadline = uiDeadline or (GetGameTimer() + UI_TIMEOUT_MS)
    while not uiReady and GetGameTimer() < uiDeadline do Wait(50) end
    if not uiReady then
        print('^1[veyl_lib] UI page did not load (web/dist missing or failed). Modal requests are being rejected.^7')
    end
    return uiReady
end

---------------------------------------------------------------------------
-- Host-rendered modals: menu, form, alert
---------------------------------------------------------------------------
local function closeHostModal(result)
    local m = hostModal
    if not m then return end
    hostModal = nil
    SendNUIMessage({ action = 'modal:close' })
    -- Host modals are rendered on veyl_lib's own page, so veyl_lib must drop NUI focus itself
    -- (the focus record's owner is the requesting resource, not veyl_lib).
    SetNuiFocus(false, false)
    releaseFocus(m.token, 'closed')
    if m.cb then
        local ok, err = pcall(m.cb, result)
        if not ok then print(('^1[veyl_lib] %s result callback failed: %s^7'):format(m.kind, tostring(err))) end
    end
end

local function openHostModal(kind, payload, cb, owner)
    CreateThread(function()
        if not ensureUI() then return cb({ type = 'error', code = 'UI_UNAVAILABLE' }) end
        -- Re-showing a menu while the same owner's menu is open (refresh) reuses the session.
        if hostModal and hostModal.owner == owner and hostModal.kind == 'menu' and kind == 'menu' then
            local old = hostModal.cb
            hostModal.cb = cb
            payload.token = hostModal.token
            SendNUIMessage({ action = 'menu:open', data = payload })
            if old then pcall(old, { type = 'replaced' }) end
            return
        end
        local token, reason = requestFocus(owner, kind)
        if not token then return cb({ type = 'rejected', reason = reason }) end
        hostModal = { token = token, cb = cb, owner = owner, kind = kind }
        payload.token = token
        SetNuiFocus(true, true)
        SendNUIMessage({ action = kind .. ':open', data = payload })
    end)
end

exports('OpenMenu', function(payload, cb) openHostModal('menu', payload, cb, GetInvokingResource()) end)
exports('OpenForm', function(payload, cb) openHostModal('form', payload, cb, GetInvokingResource()) end)
exports('OpenAlert', function(payload, cb) openHostModal('alert', payload, cb, GetInvokingResource()) end)
exports('CloseModal', function()
    if hostModal and hostModal.owner == GetInvokingResource() then closeHostModal({ type = 'close' }) end
end)

RegisterNUICallback('modal:result', function(data, cb)
    cb({ ok = true }) -- always resolve the NUI request
    if not hostModal or type(data) ~= 'table' or data.token ~= hostModal.token then return end
    local result = { type = tostring(data.type) }
    if result.type == 'select' then
        result.optionId = tostring(data.optionId or '')
    elseif result.type == 'submit' then
        result.values = type(data.values) == 'table' and data.values or {}
    end
    -- Every result closes the modal and releases focus BEFORE the consumer runs, so a submenu, form or
    -- dialog opened from the selection is a fresh request rather than a conflict.
    closeHostModal(result)
end)

---------------------------------------------------------------------------
-- Passive UI: notifications, text prompt
---------------------------------------------------------------------------
local notifySeq = 0
local TYPES = { info = true, success = true, warning = true, error = true }

exports('Notify', function(data)
    if type(data) ~= 'table' or type(data.message) ~= 'string' then return end
    notifySeq = notifySeq + 1
    SendNUIMessage({ action = 'notify', data = {
        id = tostring(notifySeq), title = type(data.title) == 'string' and data.title:sub(1, 80) or nil,
        message = data.message:sub(1, 300), type = TYPES[data.type] and data.type or 'info',
        duration = math.floor(tonumber(data.duration) or 4500),
    } })
end)

RegisterNetEvent('veyl_lib:notify', function(data) exports.veyl_lib:Notify(data) end)

exports('ShowTextUI', function(text, key)
    textUIOwner = GetInvokingResource()
    SendNUIMessage({ action = 'textui:show', data = { text = tostring(text):sub(1, 120), key = key } })
end)
exports('HideTextUI', function()
    textUIOwner = nil
    SendNUIMessage({ action = 'textui:hide' })
end)
exports('IsTextUIOpen', function() return textUIOwner ~= nil end)

---------------------------------------------------------------------------
-- Progress: one at a time; owns its animation, prop and control lock; always cleans up.
---------------------------------------------------------------------------
local function loadDict(dict)
    RequestAnimDict(dict)
    local deadline = GetGameTimer() + 3000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < deadline do Wait(10) end
    return HasAnimDictLoaded(dict)
end

local function attachProp(ped, prop)
    local hash = type(prop.model) == 'number' and prop.model or joaat(prop.model)
    if not IsModelInCdimage(hash) then return nil end
    RequestModel(hash)
    local deadline = GetGameTimer() + 3000
    while not HasModelLoaded(hash) and GetGameTimer() < deadline do Wait(10) end
    if not HasModelLoaded(hash) then return nil end
    local c = GetEntityCoords(ped)
    local obj = CreateObject(hash, c.x, c.y, c.z, true, true, false)
    local pos, rot = prop.pos or vector3(0.0, 0.0, 0.0), prop.rot or vector3(0.0, 0.0, 0.0)
    AttachEntityToEntity(obj, ped, GetPedBoneIndex(ped, prop.bone or 60309), pos.x, pos.y, pos.z, rot.x, rot.y, rot.z, true, true, false, true, 1, true)
    SetModelAsNoLongerNeeded(hash)
    return obj
end

--- StartProgress({ label, duration, canCancel, disable = { move, car, combat }, anim = { dict, clip, flag }, prop = { model, bone, pos, rot } }, cb(bool))
exports('StartProgress', function(opts, cb)
    if progress then return cb(false) end
    opts = type(opts) == 'table' and opts or {}
    local duration = math.max(250, math.min(math.floor(tonumber(opts.duration) or 3000), 120000))
    progress = { owner = GetInvokingResource(), cancelled = false, cb = cb }
    local p = progress
    CreateThread(function()
        local ped = PlayerPedId()
        local anim, propObj = opts.anim, nil
        if anim and anim.dict and loadDict(anim.dict) then
            TaskPlayAnim(ped, anim.dict, anim.clip, 3.0, 3.0, -1, anim.flag or 49, 0, false, false, false)
        end
        if opts.prop and opts.prop.model then propObj = attachProp(ped, opts.prop) end
        SendNUIMessage({ action = 'progress:start', data = { label = tostring(opts.label or 'Working...'), duration = duration, canCancel = opts.canCancel ~= false } })
        local disable = opts.disable or {}
        local finishAt = GetGameTimer() + duration
        while GetGameTimer() < finishAt and not p.cancelled do
            if disable.move then
                DisableControlAction(0, 30, true) DisableControlAction(0, 31, true)
                DisableControlAction(0, 21, true) DisableControlAction(0, 22, true)
            end
            if disable.car then DisableControlAction(0, 71, true) DisableControlAction(0, 72, true) end
            if disable.combat ~= false then DisableControlAction(0, 24, true) DisableControlAction(0, 25, true) DisablePlayerFiring(PlayerId(), true) end
            if opts.canCancel ~= false and IsControlJustPressed(0, 73) then p.cancelled = true end
            if IsEntityDead(ped) then p.cancelled = true end
            Wait(0)
        end
        if anim and anim.dict then StopAnimTask(ped, anim.dict, anim.clip, 1.0) end
        if propObj and DoesEntityExist(propObj) then DeleteEntity(propObj) end
        SendNUIMessage({ action = 'progress:stop' })
        if progress == p then progress = nil end
        pcall(p.cb, not p.cancelled)
    end)
end)

exports('CancelProgress', function() if progress then progress.cancelled = true end end)
exports('IsProgressActive', function() return progress ~= nil end)

---------------------------------------------------------------------------
-- Cleanup
---------------------------------------------------------------------------
AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        SetNuiFocus(false, false)
        return
    end
    if hostModal and hostModal.owner == res then closeHostModal(nil) end
    if focus and focus.owner == res then
        local token = focus.token
        focus = nil
        TriggerEvent('veyl_lib:focusRevoked', token, res)
    end
    if progress and progress.owner == res then progress.cancelled = true end
    if textUIOwner == res then exports.veyl_lib:HideTextUI() end
end)

-- Broker (re)start: clear stale state everywhere before any new focus is granted.
CreateThread(function()
    SetNuiFocus(false, false)
    TriggerEvent('veyl_lib:brokerReset')
    SendNUIMessage({ action = 'reset' })
end)
