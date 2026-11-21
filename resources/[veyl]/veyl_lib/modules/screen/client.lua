-- vlib.createScreen: lifecycle for a resource that owns a full-screen NUI page (inventory, shop, bank, ...).
--   local screen = vlib.createScreen({ name = 'shop', onClose = function(reason) end, closeOnDeath = true })
--   screen:open('shop:open', data) -> true | false, reason   -- requests a focus token from veyl_lib first
--   screen:send(action, data)                                -- envelope { action, session, data }
--   screen:close(reason) / screen:isOpen() / screen:session()
-- Registers the page's 'ui:ready' and 'close' NUI callbacks. Focus is ALWAYS released on close, Escape, revoke,
-- broker reset, death (optional), logout and resource stop.

local M = {}

function M.createScreen(opts)
    opts = opts or {}
    local name = opts.name or GetCurrentResourceName()
    local self = { visible = false, token = nil, ready = false, sessionId = nil, seq = 0 }

    local function release()
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
        SetNuiFocus(true, true)
        self:send(action, data)
        return true
    end

    RegisterNUICallback('ui:ready', function(_, cb)
        self.ready = true
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
