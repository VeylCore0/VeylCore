-- veyl_admin server. Every staff command is checked server-side against the 'veyl.admin' ACE and audited.

Veyl.Startup({ 'veyl_core' }, function()
    return Veyl.Migrate({
        {
            id = '001_reports',
            sql = {
                [[CREATE TABLE IF NOT EXISTS veyl_reports (
                    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                    account_id INT UNSIGNED NULL,
                    character_id INT UNSIGNED NULL,
                    player_name VARCHAR(64) NOT NULL,
                    message VARCHAR(500) NOT NULL,
                    status ENUM('open','closed') NOT NULL DEFAULT 'open',
                    handled_by VARCHAR(64) NULL,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (id),
                    KEY idx_status (status)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            },
        },
    })
end)

local function reply(src, msg, kind)
    if src == 0 then print('[veyl_admin] ' .. msg) else Veyl.Notify(src, msg, kind or 'info', 7000) end
end

local function staffCommand(name, handler)
    RegisterCommand(name, function(src, args, raw)
        if not Veyl.HasPermission(src, 'admin') then
            Veyl.Audit(src, 'admin_denied', { command = name, raw = raw:sub(1, 200) })
            return reply(src, 'You do not have permission to use this command.', 'error')
        end
        CreateThread(function()
            local ok, err = pcall(handler, src, args, raw)
            if not ok then
                print(('^1[veyl_admin] /%s error: %s^7'):format(name, tostring(err)))
                reply(src, 'Command failed: ' .. tostring(err), 'error')
            end
        end)
    end, false)
end

local function targetOf(src, arg)
    local id = tonumber(arg)
    if not id or not GetPlayerName(id) then
        reply(src, 'Player ' .. tostring(arg) .. ' is not online.', 'error')
        return nil
    end
    return id
end

local function staffNotify(msg)
    for _, p in ipairs(exports.veyl_core:GetPlayers()) do
        if Veyl.HasPermission(p.source, 'admin') then Veyl.Notify(p.source, msg, 'warning', 10000) end
    end
end

staffCommand('vplayers', function(src)
    local list = exports.veyl_core:GetPlayers()
    local lines = {}
    for _, p in ipairs(list) do
        lines[#lines + 1] = ('[%d] %s - %s'):format(p.source, p.name, p.characterName or 'selecting')
    end
    if src == 0 then
        print(('Players (%d):\n%s'):format(#list, table.concat(lines, '\n')))
    else
        TriggerClientEvent('veyl_admin:list', src, ('Players (%d)'):format(#list), lines)
    end
end)

staffCommand('vtp', function(src, args)
    if src == 0 then return end
    local t = targetOf(src, args[1]); if not t then return end
    local c = GetEntityCoords(GetPlayerPed(t))
    SetEntityCoords(GetPlayerPed(src), c.x, c.y, c.z + 1.0, false, false, false, false)
    Veyl.Audit(src, 'admin_tp', { target = t })
end)

staffCommand('vbring', function(src, args)
    if src == 0 then return end
    local t = targetOf(src, args[1]); if not t then return end
    local c = GetEntityCoords(GetPlayerPed(src))
    SetEntityCoords(GetPlayerPed(t), c.x + 1.0, c.y, c.z + 0.5, false, false, false, false)
    Veyl.Audit(src, 'admin_bring', { target = t })
end)

staffCommand('vtpm', function(src)
    if src == 0 then return end
    Veyl.Audit(src, 'admin_tpm', nil)
    TriggerClientEvent('veyl_admin:tpm', src)
end)

staffCommand('vcoords', function(src)
    if src ~= 0 then TriggerClientEvent('veyl_admin:coords', src) end
end)

staffCommand('vrevive', function(src, args)
    local t = args[1] and targetOf(src, args[1]) or src
    if not t or t == 0 then return end
    TriggerClientEvent('veyl_admin:revive', t)
    Veyl.Audit(src, 'admin_revive', { target = t })
    reply(src, 'Revived ' .. GetPlayerName(t), 'success')
end)

staffCommand('vkick', function(src, args)
    local t = targetOf(src, args[1]); if not t then return end
    local reason = table.concat(args, ' ', 2)
    if reason == '' then return reply(src, 'Usage: /vkick [id] [reason]', 'error') end
    Veyl.Audit(src, 'admin_kick', { target = t, name = GetPlayerName(t), reason = reason })
    DropPlayer(t, 'Kicked by staff: ' .. reason)
end)

-- Economy tools: always require a reason; all movements go through veyl_banking's ledger.
local function moneyCommand(src, args, sign)
    local t = targetOf(src, args[1]); if not t then return end
    local kind, amount, reason = args[2], tonumber(args[3]), table.concat(args, ' ', 4)
    if (kind ~= 'cash' and kind ~= 'bank') or not amount or amount < 1 or amount % 1 ~= 0 or reason == '' then
        return reply(src, ('Usage: /%s [id] [cash|bank] [amount] [reason]'):format(sign > 0 and 'vgivemoney' or 'vtakemoney'), 'error')
    end
    local charId = Veyl.GetCharacterId(t)
    if not charId then return reply(src, 'That player has no character loaded.', 'error') end
    local opId = Veyl.NewId('admin')
    local res = Veyl.Await('veyl_banking', sign > 0 and 'Credit' or 'TryDebit', 15000, charId, kind, amount,
        'Staff adjustment: ' .. reason:sub(1, 100), opId)
    Veyl.Audit(src, 'admin_money', { target = charId, kind = kind, amount = sign * amount, reason = reason, ok = res.ok, code = res.code })
    reply(src, res.ok and ('Done. New %s balance: $%d'):format(kind, res.data.balance) or ('Failed: ' .. tostring(res.message or res.code)),
        res.ok and 'success' or 'error')
end

staffCommand('vgivemoney', function(src, args) moneyCommand(src, args, 1) end)
staffCommand('vtakemoney', function(src, args) moneyCommand(src, args, -1) end)

staffCommand('vsetjob', function(src, args)
    local t = targetOf(src, args[1]); if not t then return end
    local charId = Veyl.GetCharacterId(t)
    if not charId then return reply(src, 'That player has no character loaded.', 'error') end
    local res = Veyl.Await('veyl_jobs', 'SetJob', 10000, charId, tostring(args[2]), tonumber(args[3]) or 0, 'staff')
    Veyl.Audit(src, 'admin_setjob', { target = charId, job = args[2], grade = args[3], ok = res.ok })
    reply(src, res.ok and ('Job set to %s (%s)'):format(res.data.label, res.data.gradeLabel) or ('Failed: ' .. tostring(res.message)),
        res.ok and 'success' or 'error')
end)

staffCommand('vgiveitem', function(src, args)
    local t = targetOf(src, args[1]); if not t then return end
    local charId = Veyl.GetCharacterId(t)
    if not charId then return reply(src, 'That player has no character loaded.', 'error') end
    local count = tonumber(args[3]) or 1
    local res = Veyl.Await('veyl_inventory', 'GiveItem', 10000, charId, tostring(args[2]), count, nil, Veyl.NewId('admin:item'))
    Veyl.Audit(src, 'admin_giveitem', { target = charId, item = args[2], count = count, ok = res.ok })
    reply(src, res.ok and 'Item given' or ('Failed: ' .. tostring(res.message or res.code)), res.ok and 'success' or 'error')
end)

---------------------------------------------------------------------------
-- Reports
---------------------------------------------------------------------------
local lastReport = {}

RegisterCommand('report', function(src, args)
    if src == 0 then return end
    local msg = table.concat(args, ' ')
    if #msg < 5 then return reply(src, 'Usage: /report [what happened]', 'error') end
    if lastReport[src] and os.time() - lastReport[src] < 60 then return reply(src, 'Please wait before sending another report.', 'error') end
    lastReport[src] = os.time()
    local p = Veyl.GetPlayer(src)
    CreateThread(function()
        local id = MySQL.insert.await('INSERT INTO veyl_reports (account_id, character_id, player_name, message) VALUES (?, ?, ?, ?)',
            { p and p.accountId, p and p.characterId, GetPlayerName(src) or '?', msg:sub(1, 500) })
        reply(src, ('Report #%s sent. Staff have been notified.'):format(tostring(id)), 'success')
        staffNotify(('Report #%s from [%d] %s: %s'):format(tostring(id), src, GetPlayerName(src) or '?', msg:sub(1, 140)))
    end)
end, false)

staffCommand('vreports', function(src)
    local rows = MySQL.query.await([[SELECT id, player_name, message, DATE_FORMAT(created_at, '%H:%i') AS at
        FROM veyl_reports WHERE status = 'open' ORDER BY id DESC LIMIT 20]]) or {}
    local lines = {}
    for _, r in ipairs(rows) do lines[#lines + 1] = ('#%d %s (%s): %s'):format(r.id, r.player_name, r.at, r.message) end
    if src == 0 then print(table.concat(lines, '\n')) else TriggerClientEvent('veyl_admin:list', src, 'Open reports', lines) end
end)

staffCommand('vclosereport', function(src, args)
    local id = tonumber(args[1])
    if not id then return reply(src, 'Usage: /vclosereport [id]', 'error') end
    local n = MySQL.update.await("UPDATE veyl_reports SET status = 'closed', handled_by = ? WHERE id = ? AND status = 'open'",
        { src == 0 and 'console' or GetPlayerName(src), id })
    Veyl.Audit(src, 'report_closed', { report = id })
    reply(src, n > 0 and ('Report #%d closed'):format(id) or 'Report not found or already closed', n > 0 and 'success' or 'error')
end)

AddEventHandler('playerDropped', function() lastReport[source] = nil end)
