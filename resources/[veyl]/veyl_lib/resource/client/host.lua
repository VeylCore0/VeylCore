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
local progress = nil     -- the running action (see Actions below)
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
    -- Theme, placement and limits for notifications and progress (resource/client/ui_config.lua).
    SendNUIMessage({ action = 'ui:config', data = VlibUIConfig })
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
-- Passive UI: notifications (never take focus), text prompt
---------------------------------------------------------------------------
local NC = VlibUIConfig.Notifications
local notifySeq = 0
local TYPES = { info = true, success = true, warning = true, error = true }
local LAYOUTS = { standard = true, compact = true, payment = true }

local function str(v, max) return type(v) == 'string' and v ~= '' and v:sub(1, max) or nil end

--- Cleans notification options (shared by Notify and UpdateNotification).
local function cleanNotify(data, partial)
    local out = {}
    if data.type ~= nil or not partial then out.type = TYPES[data.type] and data.type or (not partial and 'info' or nil) end
    out.title = str(data.title, 80)
    -- Old calls pass `message`; new calls may use `description`.
    out.description = str(data.description, 400) or str(data.message, 400)
    out.icon = str(data.icon, 32)
    if data.duration ~= nil or not partial then
        out.duration = math.floor(math.max(NC.minDuration, math.min(NC.maxDuration, tonumber(data.duration) or NC.defaultDuration)))
    end
    if data.amount ~= nil then
        local a = tonumber(data.amount)
        out.amount = a and math.floor(a) or str(data.amount, 24)
    end
    if data.layout ~= nil or not partial then
        out.layout = LAYOUTS[data.layout] and data.layout or (out.amount and 'payment') or ((out.title and out.description) and 'standard') or 'compact'
    end
    if data.sound ~= nil then out.sound = data.sound ~= false end
    if data.showDuration ~= nil then out.showDuration = data.showDuration ~= false end
    return out
end

--- Notify({ id?, type, title?, description? | message?, icon?, duration?, layout?, amount?, sound?, showDuration? }) -> id
--- Same id (or identical type + title + text, with duplicates = 'merge') updates the card and counts it (×2, ×3).
exports('Notify', function(data)
    if type(data) == 'string' then data = { message = data } end
    if type(data) ~= 'table' then return nil end
    local n = cleanNotify(data, false)
    if not n.title and not n.description then return nil end
    local id = str(data.id, 64)
    if not id then
        notifySeq = notifySeq + 1
        id = ('n%d'):format(notifySeq)
        n.autoId = true
    end
    n.id = id
    SendNUIMessage({ action = 'notify', data = n })
    return id
end)

--- UpdateNotification(id, changes): change a visible / queued card (e.g. a running counter). Returns nothing.
exports('UpdateNotification', function(id, changes)
    if type(id) ~= 'string' or type(changes) ~= 'table' then return end
    local n = cleanNotify(changes, true)
    n.id = id
    SendNUIMessage({ action = 'notify:update', data = n })
end)

exports('DismissNotification', function(id)
    if type(id) == 'string' then SendNUIMessage({ action = 'notify:dismiss', data = { id = id } }) end
end)
exports('DismissAllNotifications', function() SendNUIMessage({ action = 'notify:clear' }) end)

RegisterNetEvent('veyl_lib:notify', function(data) exports.veyl_lib:Notify(data) end)

-- The page asks to close a card (only possible while veyl_lib's own menu/dialog has the cursor).
RegisterNUICallback('notify:closed', function(_, cb) cb({ ok = true }) end)

-- Optional key to dismiss the newest card (no cursor needed).
RegisterCommand('+veyl_dismiss_notify', function() SendNUIMessage({ action = 'notify:dismissNewest' }) end, false)
RegisterCommand('-veyl_dismiss_notify', function() end, false)
RegisterKeyMapping('+veyl_dismiss_notify', 'Dismiss newest notification', 'keyboard', NC.dismissKey or '')

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
-- Actions: timed progress and hold-to-interact. One at a time; each owns its animation, props and control lock and
-- always cleans up. States: idle -> running -> completed | cancelled. The result is delivered exactly once.
-- The page only draws (it animates from the start time); Lua measures elapsed time with GetGameTimer.
---------------------------------------------------------------------------
local PC, HC = VlibUIConfig.Progress, VlibUIConfig.Hold
local actionSeq = 0

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

local function clamp(v, lo, hi, def) v = tonumber(v) if not v then return def end return math.max(lo, math.min(hi, v)) end
local function color(v) return type(v) == 'string' and v:match('^#%x%x%x%x%x%x$') and v or nil end

--- Ends the running action once: stops its animation / scenario, deletes its props, tells the page, calls back.
local function endAction(p, completed, reason)
    if p.ended then return end
    p.ended = true
    if progress == p then progress = nil end
    local ped = PlayerPedId()
    if p.anim and p.anim.dict then StopAnimTask(ped, p.anim.dict, p.anim.clip, 1.0) end
    if p.scenario then ClearPedTasks(ped) end
    for _, obj in ipairs(p.props) do if DoesEntityExist(obj) then DeleteEntity(obj) end end
    SendNUIMessage({ action = 'progress:end', data = { id = p.id, completed = completed, reason = reason } })
    pcall(p.cb, completed, reason)
end

--- Cancels the current action (reason recorded). Safe to call any time.
local function cancelAction(reason)
    if progress and not progress.ended then progress.cancelReason = progress.cancelReason or reason or 'cancelled' end
end

local function blockControls(disable)
    if disable.move then
        DisableControlAction(0, 30, true) DisableControlAction(0, 31, true)
        DisableControlAction(0, 21, true) DisableControlAction(0, 22, true) DisableControlAction(0, 36, true)
    end
    if disable.car then
        DisableControlAction(0, 71, true) DisableControlAction(0, 72, true) DisableControlAction(0, 59, true)
        DisableControlAction(0, 75, true) DisableControlAction(0, 23, true) -- exit / enter vehicle
    end
    if disable.combat ~= false then
        DisableControlAction(0, 24, true) DisableControlAction(0, 25, true) DisableControlAction(0, 140, true)
        DisableControlAction(0, 141, true) DisableControlAction(0, 142, true) DisableControlAction(0, 257, true)
        DisablePlayerFiring(PlayerId(), true)
    end
end

--- Starts an action. kind = 'timed' | 'hold'. Returns false + reason if busy (and replace not requested).
local function startAction(kind, opts, cb, owner)
    opts = type(opts) == 'table' and opts or {}
    if progress and not progress.ended then
        if opts.replace ~= true then return cb(false, 'busy') end
        cancelAction('replaced')
        local old = progress
        local t = GetGameTimer() + 1000
        while not old.ended and GetGameTimer() < t do Wait(0) end
        endAction(old, false, 'replaced')
    end
    actionSeq = actionSeq + 1
    local duration = math.floor(clamp(opts.duration, PC.minDuration, PC.maxDuration, 3000))
    local p = {
        id = ('%s:%d'):format(type(opts.id) == 'string' and opts.id:sub(1, 40) or kind, actionSeq), kind = kind, owner = owner, cb = cb,
        duration = duration, canCancel = opts.canCancel ~= false, props = {}, disable = type(opts.disable) == 'table' and opts.disable or {},
        anim = type(opts.anim) == 'table' and opts.anim or nil, scenario = type(opts.scenario) == 'string' and opts.scenario or nil,
        cancelControl = math.floor(clamp(opts.cancelControl, 0, 400, PC.cancelControl)),
        holdControl = math.floor(clamp(opts.control, 0, 400, HC.control)), decay = tonumber(opts.decay),
    }
    if kind == 'hold' then p.canCancel = false end
    progress = p
    CreateThread(function()
        local ped = PlayerPedId()
        local startedInVehicle = IsPedInAnyVehicle(ped, false)
        if p.anim and p.anim.dict and loadDict(p.anim.dict) then TaskPlayAnim(ped, p.anim.dict, p.anim.clip, 3.0, 3.0, -1, p.anim.flag or 49, 0, false, false, false) end
        if p.scenario then TaskStartScenarioInPlace(ped, p.scenario, 0, true) end
        local propList = opts.prop and (opts.prop.model and { opts.prop } or opts.prop) or {}
        for i = 1, math.min(#propList, 3) do
            local o = type(propList[i]) == 'table' and propList[i].model and attachProp(ped, propList[i])
            if o then p.props[#p.props + 1] = o end
        end
        SendNUIMessage({ action = kind == 'hold' and 'hold:start' or 'progress:start', data = {
            id = p.id, label = tostring(opts.label or (kind == 'hold' and 'Hold to interact' or 'Working…')):sub(1, 60),
            icon = type(opts.icon) == 'string' and opts.icon:sub(1, 24) or nil, duration = duration, color = color(opts.color),
            canCancel = p.canCancel, cancelLabel = tostring(opts.cancelLabel or PC.cancelLabel):sub(1, 6),
            keyLabel = tostring(opts.keyLabel or HC.label):sub(1, 6), subLabel = opts.subLabel ~= false and tostring(opts.subLabel or HC.releaseText):sub(1, 40) or nil,
            completeLabel = type(opts.completeLabel) == 'string' and opts.completeLabel:sub(1, 60) or nil, showComplete = opts.showComplete ~= false,
        } })
        local startAt, held, lastSent, lastTick, pressedOnce = GetGameTimer(), 0, -1, GetGameTimer(), false
        while not p.ended do
            local now = GetGameTimer()
            blockControls(p.disable)
            if p.canCancel then DisableControlAction(0, p.cancelControl, true) end
            -- Cancellation sources
            if p.canCancel and IsDisabledControlJustPressed(0, p.cancelControl) then cancelAction('cancelled') end
            if IsEntityDead(ped) or IsPedDeadOrDying(ped, true) then cancelAction('dead') end
            if p.disable.car and IsPedInAnyVehicle(ped, false) ~= startedInVehicle then cancelAction('vehicle') end
            if p.disable.move and not startedInVehicle and GetEntitySpeed(ped) > 2.5 then cancelAction('moved') end
            if p.cancelReason then break end
            if kind == 'timed' then
                if now - startAt >= duration then break end
            else
                local dt = now - lastTick
                local down = IsControlPressed(0, p.holdControl) or IsDisabledControlPressed(0, p.holdControl)
                if down then pressedOnce = true held = held + dt
                elseif pressedOnce or now - startAt > 400 then
                    if p.decay and p.decay > 0 then held = math.max(0, held - dt * p.decay) else cancelAction('released') end
                end
                if held >= duration then break end
                -- The page interpolates between these (no per-frame messages).
                local frac = math.floor(held / duration * 100)
                if frac ~= lastSent and now - (p.sentAt or 0) > 90 then
                    lastSent, p.sentAt = frac, now
                    SendNUIMessage({ action = 'hold:update', data = { id = p.id, progress = held / duration } })
                end
            end
            lastTick = now
            Wait(0)
        end
        if p.cancelReason then endAction(p, false, p.cancelReason) else endAction(p, true, 'completed') end
    end)
end

--- StartProgress({ id?, label, icon?, duration, color?, canCancel = true, cancelControl?, cancelLabel?, disable = { move, car, combat },
---   anim = { dict, clip, flag }?, scenario?, prop = { model, bone, pos, rot } | { ... }?, completeLabel?, showComplete = true, replace? }, cb(completed, reason))
exports('StartProgress', function(opts, cb) startAction('timed', opts, type(cb) == 'function' and cb or function() end, GetInvokingResource()) end)

--- StartHoldProgress({ id?, label, subLabel? | false, keyLabel?, control?, duration, decay? (0 = reset on release), disable?, anim?, replace? }, cb(completed, reason))
exports('StartHoldProgress', function(opts, cb) startAction('hold', opts, type(cb) == 'function' and cb or function() end, GetInvokingResource()) end)

--- CancelProgress(id?): cancels the running action (or only the one with that id).
exports('CancelProgress', function(id)
    if progress and (id == nil or (type(id) == 'string' and progress.id:sub(1, #id) == id)) then cancelAction('cancelled') end
end)
exports('IsProgressActive', function() return progress ~= nil and not progress.ended end)
exports('GetProgressId', function() return progress and not progress.ended and progress.id or nil end)

RegisterNetEvent('VeylCore:Client:OnPlayerUnload', function() cancelAction('logout') end)

---------------------------------------------------------------------------
-- Cleanup
---------------------------------------------------------------------------
AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then
        SetNuiFocus(false, false)
        -- Our threads stop with us: undo the running action's animation and props right now.
        if progress and not progress.ended then
            local ped = PlayerPedId()
            if progress.anim and progress.anim.dict then StopAnimTask(ped, progress.anim.dict, progress.anim.clip, 1.0) end
            if progress.scenario then ClearPedTasks(ped) end
            for _, obj in ipairs(progress.props or {}) do if DoesEntityExist(obj) then DeleteEntity(obj) end end
        end
        return
    end
    if hostModal and hostModal.owner == res then closeHostModal(nil) end
    if focus and focus.owner == res then
        local token = focus.token
        focus = nil
        TriggerEvent('veyl_lib:focusRevoked', token, res)
    end
    if progress and progress.owner == res then cancelAction('caller_stopped') end
    if textUIOwner == res then exports.veyl_lib:HideTextUI() end
end)

-- Broker (re)start: clear stale state everywhere before any new focus is granted.
CreateThread(function()
    SetNuiFocus(false, false)
    TriggerEvent('veyl_lib:brokerReset')
    SendNUIMessage({ action = 'reset' })
end)
