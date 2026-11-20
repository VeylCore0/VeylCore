-- veyl_core characters: slots, creation, ownership-checked login, soft deletion.
-- The selection UI (veyl_characters) asks; the core validates and decides.

Characters = {}

local NAME_PATTERN = "^[A-Za-z][A-Za-z' %-]+$"

local function session(src)
    local s = Core.Sessions[tonumber(src)]
    if not s or s.pending or not s.accountId then return nil end
    return s
end

local function decode(text, fallback)
    if type(text) ~= 'string' then return fallback end
    local ok, v = pcall(json.decode, text)
    return ok and v or fallback
end

function Characters.List(src)
    local s = session(src)
    if not s then return Veyl.Err('NOT_READY', 'Session not ready') end
    local rows = MySQL.query.await([[SELECT citizenid, cid, charinfo, job, DATE_FORMAT(last_played, '%Y-%m-%d %H:%i') AS last_played
        FROM veyl_players WHERE account_id = ? AND deleted_at IS NULL ORDER BY cid]], { s.accountId }) or {}
    local list = {}
    for i, r in ipairs(rows) do
        local ci = decode(r.charinfo, {})
        local job = VeylShared.Jobs[r.job]
        list[i] = {
            citizenid = r.citizenid, cid = r.cid, firstname = ci.firstname, lastname = ci.lastname,
            birthdate = ci.birthdate, gender = ci.gender, job = job and job.label or r.job, lastPlayed = r.last_played,
        }
    end
    return Veyl.Ok({ characters = list, maxCharacters = s.maxCharacters })
end

local function randomCitizenId()
    local letters, out = 'ABCDEFGHJKLMNPQRSTUVWXYZ', {}
    for i = 1, 3 do local n = math.random(1, #letters) out[i] = letters:sub(n, n) end
    return table.concat(out) .. ('%05d'):format(math.random(0, 99999))
end

local function uniqueValue(generator, sql)
    for _ = 1, 20 do
        local v = generator()
        if not MySQL.scalar.await(sql, { v }) then return v end
    end
    error('could not generate a unique value')
end

local function validBirthdate(d)
    if type(d) ~= 'string' or not d:match('^%d%d%d%d%-%d%d%-%d%d$') then return false end
    local y, m, day = d:match('^(%d+)%-(%d+)%-(%d+)$')
    y, m, day = tonumber(y), tonumber(m), tonumber(day)
    return y >= VeylServerConfig.MinBirthYear and y <= VeylServerConfig.MaxBirthYear and m >= 1 and m <= 12 and day >= 1 and day <= 31
end

--- data = { firstname, lastname, birthdate = 'YYYY-MM-DD', gender = 0|1, nationality? }
function Characters.Create(src, data)
    local s = session(src)
    if not s then return Veyl.Err('NOT_READY', 'Session not ready') end
    if Core.Players[tonumber(src)] then return Veyl.Err('INVALID_STATE', 'Log out of your current character first') end
    if type(data) ~= 'table' then return Veyl.Err('INVALID_INPUT', 'Missing details') end
    local first, last = data.firstname, data.lastname
    if not Veyl.Validate.str(first, 2, 24, NAME_PATTERN) or not Veyl.Validate.str(last, 2, 24, NAME_PATTERN) then
        return Veyl.Err('INVALID_INPUT', 'Names must be 2-24 letters (spaces, apostrophes and hyphens allowed)')
    end
    if not validBirthdate(data.birthdate) then
        return Veyl.Err('INVALID_INPUT', ('Birthdate must be YYYY-MM-DD between %d and %d')
            :format(VeylServerConfig.MinBirthYear, VeylServerConfig.MaxBirthYear))
    end
    local gender = tonumber(data.gender)
    if gender ~= 0 and gender ~= 1 then return Veyl.Err('INVALID_INPUT', 'Choose a body type') end
    local nationality = Veyl.Validate.str(data.nationality, 2, 32, '^[%a %-]+$') and data.nationality or VeylServerConfig.StartingNationality

    return Veyl.WithLock('account:' .. s.accountId, function()
        local used = MySQL.query.await('SELECT cid FROM veyl_players WHERE account_id = ? AND deleted_at IS NULL', { s.accountId }) or {}
        if #used >= s.maxCharacters then return Veyl.Err('INVALID_STATE', 'All character slots are in use') end
        local taken = {}
        for _, r in ipairs(used) do taken[r.cid] = true end
        local cid = 1
        while taken[cid] do cid = cid + 1 end

        local citizenid = uniqueValue(randomCitizenId, 'SELECT 1 FROM veyl_players WHERE citizenid = ?')
        local phone = uniqueValue(function() return tostring(math.random(200, 999)) .. ('%07d'):format(math.random(0, 9999999)) end,
            "SELECT 1 FROM veyl_players WHERE JSON_UNQUOTE(JSON_EXTRACT(charinfo, '$.phone')) = ?")
        local charinfo = {
            firstname = first, lastname = last, birthdate = data.birthdate, gender = gender, nationality = nationality,
            phone = phone, account = ('US0%d%s'):format(math.random(1, 9), ('%09d'):format(math.random(0, 999999999))), cid = cid,
        }
        local metadata = Metadata.ApplyDefaults({})

        local queries = {
            { query = [[INSERT INTO veyl_players (citizenid, account_id, cid, license, charinfo, metadata, job, gang)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?)]],
              values = { citizenid, s.accountId, cid, s.license, json.encode(charinfo), json.encode(metadata),
                  VeylConfig.DefaultJob, VeylConfig.DefaultGang } },
        }
        for _, t in ipairs(VeylConfig.MoneyTypes) do
            local start = math.floor(tonumber(VeylServerConfig.StartingMoney[t]) or 0)
            queries[#queries + 1] = { query = 'INSERT INTO veyl_money (citizenid, type, balance) VALUES (?, ?, ?)', values = { citizenid, t, start } }
            if start > 0 then
                queries[#queries + 1] = {
                    query = [[INSERT INTO veyl_money_ledger (op_id, citizenid, type, delta, balance_after, reason, actor)
                        VALUES (?, ?, ?, ?, ?, 'Starting balance', 'veyl_core')]],
                    values = { ('open:%s:%s'):format(citizenid, t), citizenid, t, start, start },
                }
            end
        end
        if not MySQL.transaction.await(queries) then return Veyl.Err('DATABASE_ERROR', 'Could not save character') end
        exports.veyl_core:Audit(src, 'veyl_core', 'character_created', { citizenid = citizenid, name = first .. ' ' .. last })
        return Veyl.Ok({ citizenid = citizenid }, 'Character created')
    end)
end

function Characters.Delete(src, citizenid, confirmName)
    local s = session(src)
    if not s then return Veyl.Err('NOT_READY', 'Session not ready') end
    if type(citizenid) ~= 'string' or type(confirmName) ~= 'string' then return Veyl.Err('INVALID_INPUT', 'Invalid request') end
    if Core.ByCitizen[citizenid] then return Veyl.Err('INVALID_STATE', 'You cannot delete an active character') end
    local row = MySQL.single.await('SELECT account_id, charinfo FROM veyl_players WHERE citizenid = ? AND deleted_at IS NULL', { citizenid })
    if not row or row.account_id ~= s.accountId then return Veyl.Err('NOT_FOUND', 'Character not found') end
    local ci = decode(row.charinfo, {})
    local fullName = ('%s %s'):format(ci.firstname or '', ci.lastname or '')
    if confirmName:lower() ~= fullName:lower() then
        return Veyl.Err('INVALID_INPUT', 'Type the full character name to confirm deletion')
    end
    -- Soft delete: keeps ledger/inventory history and allows staff recovery.
    MySQL.update.await('UPDATE veyl_players SET deleted_at = CURRENT_TIMESTAMP WHERE citizenid = ? AND account_id = ?', { citizenid, s.accountId })
    exports.veyl_core:Audit(src, 'veyl_core', 'character_deleted', { citizenid = citizenid, name = fullName })
    return Veyl.Ok(nil, 'Character deleted')
end

local function decodePosition(text)
    local pos = decode(text, nil)
    if type(pos) == 'table' and tonumber(pos.x) and tonumber(pos.y) and tonumber(pos.z) then
        return { x = pos.x + 0.0, y = pos.y + 0.0, z = pos.z + 0.0, w = (tonumber(pos.w) or 0.0) + 0.0 }
    end
    return nil
end

--- Authenticates and loads a character for the session. Ownership is checked against the session's account.
function Characters.Login(src, citizenid)
    src = tonumber(src)
    local s = session(src)
    if not s then return Veyl.Err('NOT_READY', 'Session not ready') end
    if type(citizenid) ~= 'string' or #citizenid > 16 then return Veyl.Err('INVALID_INPUT', 'Invalid character') end
    local current = Core.Players[src]
    if current and current.citizenid == citizenid then return Veyl.Err('INVALID_STATE', 'Character already active') end
    local other = Core.ByCitizen[citizenid]
    if other and other ~= src then return Veyl.Err('BUSY', 'That character is already loaded') end

    local row = MySQL.single.await([[SELECT citizenid, account_id, cid, license, charinfo, metadata, position, job, gang
        FROM veyl_players WHERE citizenid = ? AND deleted_at IS NULL]], { citizenid })
    if not row or row.account_id ~= s.accountId then
        exports.veyl_core:Audit(src, 'veyl_core', 'login_denied', { citizenid = citizenid })
        return Veyl.Err('NOT_FOUND', 'Character not found')
    end
    if current then Core.Logout(src, 'switch') end
    local generation = s.generation

    local money = Money.Load(citizenid)
    local jobs, gangs = Groups.Load(citizenid)
    if not GetPlayerName(src) or not Core.Sessions[src] or Core.Sessions[src].generation ~= generation then
        return Veyl.Err('INVALID_STATE', 'Session changed while loading')
    end
    if Core.ByCitizen[citizenid] then return Veyl.Err('BUSY', 'That character is already loaded') end

    local job = row.job
    if job ~= VeylConfig.DefaultJob and jobs[job] == nil then job = VeylConfig.DefaultJob end
    local gang = row.gang
    if gang ~= VeylConfig.DefaultGang and gangs[gang] == nil then gang = VeylConfig.DefaultGang end

    local p = {
        citizenid = citizenid, cid = row.cid, accountId = row.account_id, license = row.license,
        charinfo = decode(row.charinfo, {}), metadata = Metadata.ApplyDefaults(decode(row.metadata, {})),
        position = decodePosition(row.position), money = money,
        job = job, gang = gang, jobs = jobs, gangs = gangs,
    }
    p.onduty = (VeylShared.Jobs[job] and VeylShared.Jobs[job].defaultDuty) == true
    MySQL.update('UPDATE veyl_players SET last_played = CURRENT_TIMESTAMP WHERE citizenid = ?', { citizenid })
    Core.Activate(src, p)
    return Veyl.Ok({ citizenid = citizenid })
end
