-- vlib.showTextUI(text, key?) / vlib.hideTextUI() / vlib.isTextUIOpen(). Updates only when content changes.
local current = nil

return {
    showTextUI = function(text, key)
        local sig = tostring(text) .. '|' .. tostring(key)
        if current == sig then return end
        current = sig
        exports.veyl_lib:ShowTextUI(text, key)
    end,
    hideTextUI = function()
        if not current then return end
        current = nil
        exports.veyl_lib:HideTextUI()
    end,
    isTextUIOpen = function() return current ~= nil end,
}
