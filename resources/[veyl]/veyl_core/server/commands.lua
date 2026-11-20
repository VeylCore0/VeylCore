-- Core commands.

Commands.Add('logout', 'Return to character selection', {}, false, function(src)
    if src > 0 then Core.Logout(src, 'logout') end
end)

Commands.Add('veyl_sessions', 'List sessions (staff)', {}, false, function(src)
    local lines = {}
    for _, s in ipairs(exports.veyl_core:GetSessions()) do
        lines[#lines + 1] = ('  [%s] %s  account=%s  citizenid=%s (%s)'):format(
            s.source, s.name, s.accountId, tostring(s.citizenid), tostring(s.characterName))
    end
    local text = ('VeylCore sessions: %d\n%s\n  queued writes: %d'):format(#lines, table.concat(lines, '\n'), CoreQueueDepth())
    if src == 0 then print(text) else TriggerClientEvent('chat:addMessage', src, { args = { 'VeylCore', text } }) end
end, 'admin')
