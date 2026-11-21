-- vlib.createScreen: lifecycle for a resource that owns a full-screen NUI page (inventory, shop, bank, ...).
--   local screen = vlib.createScreen({ name = 'shop', onClose = function(reason) end, closeOnDeath = true })
--   screen:open('shop:open', data) -> true | false, reason   -- requests a focus token from veyl_lib first
--   screen:send(action, data)                                -- envelope { action, session, data }
--   screen:close(reason) / screen:isOpen() / screen:session()
-- Registers the page's 'ui:ready' and 'close' NUI callbacks. Focus is ALWAYS released on close, Escape, revoke,
-- broker reset, death (optional), logout and resource stop.
-- keepInput = true: the player can still walk while the screen is open (camera look, combat and the pause menu are
-- blocked; movement is blocked too while the page reports a focused text field through the 'ui:typing' callback).

local M = {}

function M.createScreen(opts)
    opts = opts or {}
    local name = opts.name or GetCurrentResourceName()
    local self = { visible = false, token = nil, ready = false, sessionId = nil, seq = 0, typing = false }

    local function release()
        if opts.keepInput then SetNuiFocusKeepInput(false) end
        SetNuiFocus(false, false)
        if self.token then
            exports.veyl_lib:ReleaseFocus(self.token)
            self.token = nil
        end
    end

    function self:isOpen() return self.visible end
    function self:session() return self.sessionId end

    function self:send(action, data)
        SendNUIMessage({ action = action, session = self.sessionId, data = data })
    end

    function self:close(reason)
        if not self.visible then release() return end
        self.visible = false
        self:send(name .. ':close')
        release()
        self.sessionId = nil
        if opts.onClose then
            local ok, err = pcall(opts.onClose, reason or 'closed')
            if not ok then print(('^1[vlib] screen %s onClose failed: %s^7'):format(name, tostring(err))) end
        end
    end

    --- Opens the page. Returns false, reason if focus is busy or the page never loaded.
    function self:open(action, data)
        if self.visible then self:send(action, data) return true end
        if IsPauseMenuActive() then return false, 'paused' end
        local token, reason = exports.veyl_lib:RequestFocus(name)
        if not token then return false, reason or 'busy' end
        self.token = token
        local deadline = GetGameTimer() + (opts.readyTimeoutMs or 5000)
        while not self.ready and GetGameTimer() < deadline do Wait(25) end
        if not self.ready then
            release()
            print(('^1[vlib] screen %s: UI page did not load (web/dist missing or failed)^7'):format(name))
            return false, 'ui_unavailable'
        end
        if self.token ~= token then return false, 'revoked' end
        self.seq = self.seq + 1
        self.sessionId = ('%s:%d:%d'):format(name, GetGameTimer(), self.seq)
        self.visible = true
        self.typing = false
        SetNuiFocus(true, true)
        if opts.keepInput then
            SetNuiFocusKeepInput(true)
            CreateThread(function()
                while self.visible do
                    DisableControlAction(0, 1, true) DisableControlAction(0, 2, true)       -- look
                    DisableControlAction(0, 24, true) DisableControlAction(0, 25, true)     -- attack / aim
                    DisableControlAction(0, 140, true) DisableControlAction(0, 141, true)   -- melee
                    DisableControlAction(0, 142, true) DisableControlAction(0, 257, true)
                    DisableControlAction(0, 263, true) DisableControlAction(0, 264, true)
                    DisableControlAction(0, 37, true) DisableControlAction(0, 44, true)     -- weapon wheel / cover (Q)
                    DisableControlAction(0, 199, true) DisableControlAction(0, 200, true)   -- pause menu (Esc closes the page)
                    DisableControlAction(0, 245, true) DisableControlAction(0, 75, true)    -- chat / exit vehicle
                    DisableControlAction(0, 16, true) DisableControlAction(0, 17, true)     -- weapon scroll
                    DisablePlayerFiring(PlayerId(), true)
                    if self.typing then
                        DisableControlAction(0, 30, true) DisableControlAction(0, 31, true) -- move
                        DisableControlAction(0, 21, true) DisableControlAction(0, 22, true) -- sprint / jump
                        DisableControlAction(0, 23, true) DisableControlAction(0, 36, true) -- enter vehicle / duck
                    end
                    Wait(0)
                end
            end)
        end
        self:send(action, data)
        return true
    end

    RegisterNUICallback('ui:ready', function(_, cb)
        self.ready = true
        cb({ ok = true })
    end)

    RegisterNUICallback('ui:typing', function(data, cb)
        self.typing = type(data) == 'table' and data.typing == true
        cb({ ok = true })
    end)

    RegisterNUICallback('close', function(_, cb)
        cb({ ok = true })
        self:close('player')
    end)

    AddEventHandler('veyl_lib:focusRevoked', function(token) if token == self.token then self.token = nil self:close('revoked') end end)
    AddEventHandler('veyl_lib:brokerReset', function() self.token = nil self:close('broker_reset') end)
    RegisterNetEvent('VeylCore:Client:OnPlayerUnload', function() self:close('logout') end)
    AddEventHandler('onResourceStop', function(res) if res == GetCurrentResourceName() then release() end end)

    if opts.closeOnDeath ~= false then
        CreateThread(function()
            while true do
                if self.visible and IsEntityDead(PlayerPedId()) then self:close('death') end
                Wait(500)
            end
        end)
    end

    return self
end

return M
