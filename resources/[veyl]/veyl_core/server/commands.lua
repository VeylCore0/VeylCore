-- Player-facing core commands.

RegisterCommand('logout', function(src)
    if src == 0 then return end
    if not exports.veyl_core:GetCharacterId(src) then return end
    exports.veyl_core:UnloadCharacter(src, 'logout')
end, false)

-- Console / admin diagnostics: lists sessions.
RegisterCommand('veyl_sessions', function(src)
    if src ~= 0 and not exports.veyl_core:HasPermission(src, 'admin') then return end
    local players = exports.veyl_core:GetPlayers()
    local lines = { ('VeylCore sessions: %d'):format(#players) }
    for _, p in ipairs(players) do
        lines[#lines + 1] = ('  [%s] %s  account=%s  character=%s (%s)'):format(
            p.source, p.name, p.accountId, tostring(p.characterId), tostring(p.characterName))
    end
    local text = table.concat(lines, '\n')
    if src == 0 then print(text) else TriggerClientEvent('chat:addMessage', src, { args = { 'VeylCore', text } }) end
end, false)
