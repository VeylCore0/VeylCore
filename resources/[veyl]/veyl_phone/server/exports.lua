-- Server API for other resources. Every export is safe to call for offline characters and before the phone is ready
-- (it returns nil/false instead of failing). Signatures are stable; see docs/PHONE.md.

local function ready() return Phone.ready end

--- exports.veyl_phone:Notify(citizenid, { app, title, body?, route?, dedupe? }) -> id | nil
exports('Notify', function(citizenid, n) if not ready() then return nil end return Notify.Send(citizenid, n) end)

--- exports.veyl_phone:SetBadge(citizenid, app, count) -> boolean
exports('SetBadge', function(citizenid, app, count) if not ready() then return false end return Notify.SetBadge(citizenid, app, count) end)

--- exports.veyl_phone:SendMail(citizenid, from, subject, body) -> id | nil
exports('SendMail', function(citizenid, from, subject, body) if not ready() then return nil end return Mail.Send(citizenid, from, subject, body) end)

--- exports.veyl_phone:GetCitizenByNumber('555-1234') -> citizenid | nil
exports('GetCitizenByNumber', function(number) if not ready() then return nil end return Phone.CidByNumber(number) end)

--- exports.veyl_phone:GetNumber(citizenid) -> '5551234' | nil (the account is created on first phone use)
exports('GetNumber', function(citizenid) if not ready() or type(citizenid) ~= 'string' then return nil end return Phone.NumberOf(citizenid) end)

--- exports.veyl_phone:IsReachable(citizenid) -> boolean (online with a phone, not in airplane mode)
exports('IsReachable', function(citizenid)
    local s = ready() and Phone.byCid[citizenid]
    return s and Phone.SessionByNumber(s.number) ~= nil and not s.settings.airplane or false
end)

--- exports.veyl_phone:IsInCall(source) -> boolean
exports('IsInCall', function(src) return Calls.bySrc[tonumber(src) or -1] ~= nil end)

--- exports.veyl_phone:EndCall(source) -> nil (hangs up the player's call, e.g. when cuffed or knocked out)
exports('EndCall', function(src) Calls.EndFor(tonumber(src) or -1, 'hangup') end)

--- exports.veyl_phone:SendSystemMessage(toNumber, body) -> boolean
--- A text from a service (e.g. "Taxi: your driver is on the way"). It arrives in a direct chat with the reserved
--- number 0000000 (no player ever has it), so a reply never reaches a real person.
exports('SendSystemMessage', function(toNumber, body)
    if not ready() then return false end
    toNumber = PhoneUtil.Normalize(toNumber)
    body = PhoneUtil.CleanBody(body, PhoneConfig.Limits.MessageLength)
    if not toNumber or not body or not Phone.CidByNumber(toNumber) then return false end
    local key = toNumber > '0000000' and ('0000000-' .. toNumber) or (toNumber .. '-0000000')
    MySQL.query.await("INSERT IGNORE INTO veyl_ph_conversations (kind, direct_key, created_by) VALUES ('direct', ?, '0000000')", { key })
    local conv = MySQL.single.await('SELECT * FROM veyl_ph_conversations WHERE direct_key = ?', { key })
    for _, n in ipairs({ '0000000', toNumber }) do
        MySQL.query.await('INSERT INTO veyl_ph_members (conversation_id, number) VALUES (?, ?) ON DUPLICATE KEY UPDATE left_at = NULL', { conv.id, n })
    end
    Messages.Post(conv, '0000000', 'text', body, nil, nil)
    return true
end)
