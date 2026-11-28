-- veyl_admin server. Every staff command is checked server-side against the 'veyl.admin' ACE and audited.

Veyl.Startup({ 'veyl_core' }, function()
    return Veyl.Migrate({
        {
            id = '001_reports_v2',
            sql = {
                [[CREATE TABLE IF NOT EXISTS veyl_reports (
                    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                    citizenid VARCHAR(16) NULL,
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
        {
            id = '002_menu',
            sql = {
                [[CREATE TABLE IF NOT EXISTS veyl_admin_bans (
                    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                    license VARCHAR(80) NOT NULL,
                    name VARCHAR(64) NOT NULL,
                    reason VARCHAR(200) NOT NULL,
                    banned_by VARCHAR(64) NOT NULL,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    expires_at TIMESTAMP NULL DEFAULT NULL,
                    PRIMARY KEY (id),
                    KEY idx_license (license)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
                [[CREATE TABLE IF NOT EXISTS veyl_admin_warnings (
                    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                    citizenid VARCHAR(16) NOT NULL,
                    reason VARCHAR(200) NOT NULL,
                    issued_by VARCHAR(64) NOT NULL,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (id),
                    KEY idx_citizen (citizenid)
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
    for _, s in ipairs(exports.veyl_core:GetSessions()) do
        if Veyl.HasPermission(s.source, 'admin') then Veyl.Notify(s.source, msg, 'warning', 10000) end
    end
end

local function citizenOf(src, t)
    local cid = Veyl.GetCitizenId(t)
    if not cid then reply(src, 'That player has no character loaded.', 'error') end
    return cid
end

staffCommand('vplayers', function(src)
    local list = exports.veyl_core:GetSessions()
    local lines = {}
    for _, s in ipairs(list) do
        lines[#lines + 1] = ('[%d] %s - %s %s'):format(s.source, s.name, s.characterName or 'selecting', s.citizenid and ('(' .. s.citizenid .. ')') or '')
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
    exports.veyl_core:SetMetadataMany(t, { isdead = false, inlaststand = false })
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

-- Economy tools: always require a reason; durable, operation-keyed core money (never a silent legacy write).
local function moneyCommand(src, args, sign)
    local t = targetOf(src, args[1]); if not t then return end
    local kind, amount, reason = args[2], tonumber(args[3]), table.concat(args, ' ', 4)
    if (kind ~= 'cash' and kind ~= 'bank' and kind ~= 'crypto') or not amount or amount < 1 or amount % 1 ~= 0 or reason == '' then
        return reply(src, ('Usage: /%s [id] [cash|bank|crypto] [amount] [reason]'):format(sign > 0 and 'vgivemoney' or 'vtakemoney'), 'error')
    end
    local cid = citizenOf(src, t); if not cid then return end
    local res = Veyl.Await('veyl_core', sign > 0 and 'CreditOnce' or 'DebitOnce', 15000, cid, kind, amount,
        'Staff adjustment: ' .. reason:sub(1, 100), Veyl.NewId('admin'))
    Veyl.Audit(src, 'admin_money', { target = cid, kind = kind, amount = sign * amount, reason = reason, ok = res.ok, code = res.code })
    reply(src, res.ok and ('Done. New %s balance: $%d'):format(kind, res.data.balance) or ('Failed: ' .. tostring(res.message or res.code)),
        res.ok and 'success' or 'error')
end

staffCommand('vgivemoney', function(src, args) moneyCommand(src, args, 1) end)
staffCommand('vtakemoney', function(src, args) moneyCommand(src, args, -1) end)

-- /vsetjob [id] [job] [grade]  (QB SetJob semantics: replaces the previous primary job)
staffCommand('vsetjob', function(src, args)
    local t = targetOf(src, args[1]); if not t then return end
    if not citizenOf(src, t) then return end
    local ok = exports.veyl_core:SetJob(t, tostring(args[2]), tonumber(args[3]) or 0)
    Veyl.Audit(src, 'admin_setjob', { target = t, job = args[2], grade = args[3], ok = ok })
    reply(src, ok and 'Job set' or 'Unknown job or grade', ok and 'success' or 'error')
end)

-- /vaddjob [id] [job] [grade]  (adds a membership without changing the primary job)
staffCommand('vaddjob', function(src, args)
    local t = targetOf(src, args[1]); if not t then return end
    local cid = citizenOf(src, t); if not cid then return end
    local ok = exports.veyl_core:AddPlayerToJob(cid, tostring(args[2]), tonumber(args[3]) or 0)
    Veyl.Audit(src, 'admin_addjob', { target = cid, job = args[2], grade = args[3], ok = ok })
    reply(src, ok and 'Membership added' or 'Unknown job or grade', ok and 'success' or 'error')
end)

staffCommand('vremovejob', function(src, args)
    local t = targetOf(src, args[1]); if not t then return end
    local cid = citizenOf(src, t); if not cid then return end
    local ok = exports.veyl_core:RemovePlayerFromJob(cid, tostring(args[2]))
    Veyl.Audit(src, 'admin_removejob', { target = cid, job = args[2], ok = ok })
    reply(src, ok and 'Membership removed' or 'Not a member', ok and 'success' or 'error')
end)

staffCommand('vsetgang', function(src, args)
    local t = targetOf(src, args[1]); if not t then return end
    if not citizenOf(src, t) then return end
    local ok = exports.veyl_core:SetGang(t, tostring(args[2]), tonumber(args[3]) or 0)
    Veyl.Audit(src, 'admin_setgang', { target = t, gang = args[2], grade = args[3], ok = ok })
    reply(src, ok and 'Gang set' or 'Unknown gang or grade', ok and 'success' or 'error')
end)

staffCommand('vgiveitem', function(src, args)
    local t = targetOf(src, args[1]); if not t then return end
    local cid = citizenOf(src, t); if not cid then return end
    local count = tonumber(args[3]) or 1
    local res = Veyl.Await('veyl_inventory', 'GiveItem', 10000, cid, tostring(args[2]), count, nil, Veyl.NewId('admin:item'))
    Veyl.Audit(src, 'admin_giveitem', { target = cid, item = args[2], count = count, ok = res.ok })
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
    local cid = Veyl.GetCitizenId(src)
    CreateThread(function()
        local id = MySQL.insert.await('INSERT INTO veyl_reports (citizenid, player_name, message) VALUES (?, ?, ?)',
            { cid, GetPlayerName(src) or '?', msg:sub(1, 500) })
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
