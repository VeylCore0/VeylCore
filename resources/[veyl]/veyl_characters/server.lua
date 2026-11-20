-- veyl_characters server: owns character records; asks veyl_core to activate a verified character.

local NAME_PATTERN = "^[A-Za-z][A-Za-z' %-]+$"

Veyl.Startup({ 'veyl_core' }, function()
    return Veyl.Migrate({
        {
            id = '001_characters',
            sql = {
                [[CREATE TABLE IF NOT EXISTS veyl_characters (
                    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                    account_id INT UNSIGNED NOT NULL,
                    firstname VARCHAR(24) NOT NULL,
                    lastname VARCHAR(24) NOT NULL,
                    dob DATE NOT NULL,
                    sex ENUM('m','f') NOT NULL,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    last_played TIMESTAMP NULL DEFAULT NULL,
                    deleted_at TIMESTAMP NULL DEFAULT NULL,
                    PRIMARY KEY (id),
                    KEY idx_account (account_id, deleted_at)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            },
        },
    })
end)

local function getAccount(src)
    local p = Veyl.GetPlayer(src)
    if not p or not p.accountId then return nil end
    return p
end

local function rowToPublic(r)
    return {
        id = r.id, firstname = r.firstname, lastname = r.lastname,
        dob = r.dob_text, sex = r.sex, lastPlayed = r.last_played_text,
    }
end

local function listCharacters(accountId)
    local rows = MySQL.query.await([[SELECT id, firstname, lastname, DATE_FORMAT(dob, '%Y-%m-%d') AS dob_text, sex,
        DATE_FORMAT(last_played, '%Y-%m-%d %H:%i') AS last_played_text
        FROM veyl_characters WHERE account_id = ? AND deleted_at IS NULL ORDER BY id]], { accountId }) or {}
    local list = {}
    for i, r in ipairs(rows) do list[i] = rowToPublic(r) end
    return list
end

Veyl.RegisterCallback('list', function(src)
    local p = getAccount(src)
    if not p then return Veyl.Err('NOT_READY', 'Session not ready') end
    return Veyl.Ok({ characters = listCharacters(p.accountId), maxCharacters = p.maxCharacters })
end, { requireCharacter = false, cooldown = 500 })

local function validDob(dob)
    if not Veyl.Validate.str(dob, 10, 10, '^%d%d%d%d%-%d%d%-%d%d$') then return false end
    local y, m, d = dob:match('^(%d+)%-(%d+)%-(%d+)$')
    y, m, d = tonumber(y), tonumber(m), tonumber(d)
    if y < CharactersConfig.MinBirthYear or y > CharactersConfig.MaxBirthYear then return false end
    if m < 1 or m > 12 or d < 1 or d > 31 then return false end
    return true
end

Veyl.RegisterCallback('create', function(src, _, data)
    local p = getAccount(src)
    if not p then return Veyl.Err('NOT_READY', 'Session not ready') end
    if p.characterId then return Veyl.Err('INVALID_STATE', 'Log out of your current character first') end
    if type(data) ~= 'table' then return Veyl.Err('INVALID_INPUT', 'Missing details') end
    local first, last, dob, sex = data.firstname, data.lastname, data.dob, data.sex
    if not Veyl.Validate.str(first, 2, 24, NAME_PATTERN) or not Veyl.Validate.str(last, 2, 24, NAME_PATTERN) then
        return Veyl.Err('INVALID_INPUT', 'Names must be 2-24 letters (spaces, apostrophes and hyphens allowed)')
    end
    if not validDob(dob) then
        return Veyl.Err('INVALID_INPUT', ('Date of birth must be YYYY-MM-DD between %d and %d')
            :format(CharactersConfig.MinBirthYear, CharactersConfig.MaxBirthYear))
    end
    if sex ~= 'm' and sex ~= 'f' then return Veyl.Err('INVALID_INPUT', 'Choose a body type') end

    return Veyl.WithLock('account:' .. p.accountId, function()
        local count = MySQL.scalar.await('SELECT COUNT(*) FROM veyl_characters WHERE account_id = ? AND deleted_at IS NULL',
            { p.accountId })
        if count >= p.maxCharacters then return Veyl.Err('INVALID_STATE', 'All character slots are in use') end
        local id = MySQL.insert.await('INSERT INTO veyl_characters (account_id, firstname, lastname, dob, sex) VALUES (?, ?, ?, ?, ?)',
            { p.accountId, first, last, dob, sex })
        if not id then return Veyl.Err('DATABASE_ERROR', 'Could not save character') end
        Veyl.Audit(src, 'character_created', { characterId = id, name = first .. ' ' .. last })
        return Veyl.Ok({ id = id, characters = listCharacters(p.accountId) }, 'Character created')
    end)
end, { requireCharacter = false, cooldown = 1500 })

Veyl.RegisterCallback('select', function(src, _, charId)
    local p = getAccount(src)
    if not p then return Veyl.Err('NOT_READY', 'Session not ready') end
    if not Veyl.Validate.int(charId, 1) then return Veyl.Err('INVALID_INPUT', 'Invalid character') end
    if p.characterId == charId then return Veyl.Err('INVALID_STATE', 'Character already active') end

    local row = MySQL.single.await([[SELECT id, account_id, firstname, lastname, DATE_FORMAT(dob, '%Y-%m-%d') AS dob, sex
        FROM veyl_characters WHERE id = ? AND deleted_at IS NULL]], { charId })
    -- Ownership check: never trust the client-provided id alone.
    if not row or row.account_id ~= p.accountId then
        Veyl.Audit(src, 'character_select_denied', { characterId = charId })
        return Veyl.Err('NOT_FOUND', 'Character not found')
    end
    if Veyl.GetSourceByCharacter(charId) then
        return Veyl.Err('BUSY', 'That character is already loaded')
    end
    if not exports.veyl_core:SetActiveCharacter(src, row) then
        return Veyl.Err('INVALID_STATE', 'Could not activate character')
    end
    MySQL.update('UPDATE veyl_characters SET last_played = CURRENT_TIMESTAMP WHERE id = ?', { charId })
    return Veyl.Ok({ id = charId })
end, { requireCharacter = false, cooldown = 1500 })

Veyl.RegisterCallback('delete', function(src, _, charId, confirmName)
    local p = getAccount(src)
    if not p then return Veyl.Err('NOT_READY', 'Session not ready') end
    if not Veyl.Validate.int(charId, 1) or type(confirmName) ~= 'string' then
        return Veyl.Err('INVALID_INPUT', 'Invalid request')
    end
    if p.characterId == charId or Veyl.GetSourceByCharacter(charId) then
        return Veyl.Err('INVALID_STATE', 'You cannot delete an active character')
    end
    local row = MySQL.single.await('SELECT id, account_id, firstname, lastname FROM veyl_characters WHERE id = ? AND deleted_at IS NULL',
        { charId })
    if not row or row.account_id ~= p.accountId then return Veyl.Err('NOT_FOUND', 'Character not found') end
    local fullName = row.firstname .. ' ' .. row.lastname
    if confirmName:lower() ~= fullName:lower() then
        return Veyl.Err('INVALID_INPUT', 'Type the full character name to confirm deletion')
    end
    -- Soft delete keeps the record for staff recovery and keeps ledger/inventory history consistent.
    MySQL.update.await('UPDATE veyl_characters SET deleted_at = CURRENT_TIMESTAMP WHERE id = ? AND account_id = ?',
        { charId, p.accountId })
    Veyl.Audit(src, 'character_deleted', { characterId = charId, name = fullName })
    return Veyl.Ok({ characters = listCharacters(p.accountId) }, 'Character deleted')
end, { requireCharacter = false, cooldown = 2000 })

RegisterNetEvent('veyl_characters:quit', function()
    local src = source
    if not Veyl.GetCharacterId(src) then DropPlayer(src, 'Left from character selection') end
end)

--- Server-side lookup for other resources (sync: reads nothing from the DB).
exports('GetActiveCharacterInfo', function(src)
    local p = Veyl.GetPlayer(src)
    return p and p.character or nil
end)
