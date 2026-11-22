-- Voice bridge. pma-voice publishes (verified in pma-voice client/commands.lua and client/module/radio.lua):
--   LocalPlayer.state.proximity = { index, distance, mode }   mode 'Whisper' | 'Normal' | 'Shouting' | 'Custom'
--   LocalPlayer.state.radioActive = true while transmitting on the radio
-- No exports are called, so a missing or stopped pma-voice cannot break the HUD.

Bridge = Bridge or {}
Bridge.Voice = { provider = 'native' }

function Bridge.Voice.Detect()
    local want = HudConfig.Voice
    if (want == 'auto' or want == 'pma-voice') and GetResourceState('pma-voice') == 'started' then
        Bridge.Voice.provider = 'pma-voice'
    else
        Bridge.Voice.provider = 'native'
    end
end

--- { talking, mode = label or nil, level = 1-3 or nil, radio = bool or nil, available = range known }
function Bridge.Voice.State()
    local talking = NetworkIsPlayerTalking(PlayerId())
    if Bridge.Voice.provider == 'pma-voice' and GetResourceState('pma-voice') == 'started' then
        local prox = LocalPlayer.state.proximity
        local index = type(prox) == 'table' and tonumber(prox.index) or nil
        local mode = type(prox) == 'table' and prox.mode or nil
        local level = index and math.max(1, math.min(3, index)) or nil
        if mode == 'Custom' then level = 1 end -- an override (e.g. downed) is shown as the lowest level
        return { talking = talking, mode = mode, level = level, radio = LocalPlayer.state.radioActive == true, available = index ~= nil }
    end
    return { talking = talking, available = false }
end
