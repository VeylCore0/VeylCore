-- vlib streaming (client): bounded asset requests with per-resource cleanup.
--   local hash = vlib.requestModel('prop_cs_cardbox_01', 5000)   -> hash | nil, err
--   vlib.requestAnimDict(dict, timeoutMs) -> true | nil, err
--   vlib.requestPtfx(asset, timeoutMs) -> true | nil, err

local models, dicts = {}, {}

local function wait(check, timeout)
    local deadline = GetGameTimer() + (tonumber(timeout) or 10000)
    while not check() do
        if GetGameTimer() > deadline then return false end
        Wait(10)
    end
    return true
end

local M = {}

function M.requestModel(model, timeout)
    local hash = type(model) == 'number' and model or (type(model) == 'string' and joaat(model)) or nil
    if not hash or not IsModelInCdimage(hash) then return nil, ('invalid model %s'):format(tostring(model)) end
    if HasModelLoaded(hash) then return hash end
    RequestModel(hash)
    if not wait(function() return HasModelLoaded(hash) end, timeout) then return nil, 'timeout' end
    models[hash] = true
    return hash
end

function M.requestAnimDict(dict, timeout)
    if type(dict) ~= 'string' or not DoesAnimDictExist(dict) then return nil, ('invalid anim dict %s'):format(tostring(dict)) end
    if HasAnimDictLoaded(dict) then return true end
    RequestAnimDict(dict)
    if not wait(function() return HasAnimDictLoaded(dict) end, timeout) then return nil, 'timeout' end
    dicts[dict] = true
    return true
end

function M.requestPtfx(asset, timeout)
    if type(asset) ~= 'string' then return nil, 'invalid asset' end
    RequestNamedPtfxAsset(asset)
    if not wait(function() return HasNamedPtfxAssetLoaded(asset) end, timeout) then return nil, 'timeout' end
    return true
end

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for hash in pairs(models) do SetModelAsNoLongerNeeded(hash) end
    for dict in pairs(dicts) do RemoveAnimDict(dict) end
end)

return M
