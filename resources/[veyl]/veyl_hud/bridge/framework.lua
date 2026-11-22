-- Framework bridge (VeylCore). The only file that knows VeylCore names.
--   Veyl.PlayerData            kept current by @veyl_core/modules/playerdata.lua ('VeylCore:Player:SetPlayerData')
--   LocalPlayer.state.isLoggedIn   set by veyl_core when a character is spawned
--   'VeylCore:Client:OnPlayerUnload'  character logout / switch
-- Money and needs are read only; the HUD never writes framework state.

Bridge = Bridge or {}
Bridge.Framework = {}

function Bridge.Framework.IsReady()
    return LocalPlayer.state.isLoggedIn == true and Veyl.PlayerData ~= nil and Veyl.PlayerData.citizenid ~= nil
end

--- { cash, bank } or nils when unknown (hidden, never shown as 0).
function Bridge.Framework.Money()
    local m = (Veyl.PlayerData or {}).money
    if type(m) ~= 'table' then return nil, nil end
    return tonumber(m.cash), tonumber(m.bank)
end

--- Needs from metadata, already 0-100 in VeylCore. nil = not provided by this framework.
function Bridge.Framework.Needs()
    local meta = (Veyl.PlayerData or {}).metadata
    if type(meta) ~= 'table' then return nil end
    return { hunger = tonumber(meta.hunger), thirst = tonumber(meta.thirst), stress = tonumber(meta.stress) }
end

--- 'down' | 'dead' | nil (veyl_medical state bag).
function Bridge.Framework.MedicalState() return LocalPlayer.state.medical end

function Bridge.Framework.OnUnload(fn) RegisterNetEvent('VeylCore:Client:OnPlayerUnload', fn) end
