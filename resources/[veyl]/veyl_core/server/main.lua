-- veyl_core server: accounts, sessions, active character ownership, permissions and audit.

local Sessions = {}        -- [source] = session
local CharToSource = {}    -- [characterId] = source

local function copySession(s)
    if not s then return nil end
    return {
        source = s.source,
        sessionId = s.sessionId,
        accountId = s.accountId,
        license = s.license,
        name = s.name,
        maxCharacters = s.maxCharacters,
        characterId = s.characterId,
        character = s.character,
        generation = s.generation,
    }
end

---------------------------------------------------------------------------
-- Startup & migrations
---------------------------------------------------------------------------
Veyl.Startup({}, function()
    return Veyl.Migrate({
        {
            id = '001_accounts_audit',
            sql = {
                [[CREATE TABLE IF NOT EXISTS veyl_accounts (
                    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                    license VARCHAR(64) NOT NULL,
                    name VARCHAR(64) NOT NULL DEFAULT '',
                    max_characters TINYINT UNSIGNED NOT NULL DEFAULT 3,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    last_seen TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (id),
                    UNIQUE KEY uq_license (license)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
                [[CREATE TABLE IF NOT EXISTS veyl_audit (
                    id BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    account_id INT UNSIGNED NULL,
                    character_id INT UNSIGNED NULL,
                    resource VARCHAR(64) NOT NULL,
                    action VARCHAR(64) NOT NULL,
                    data LONGTEXT NULL,
                    PRIMARY KEY (id),
                    KEY idx_action (action),
                    KEY idx_character (character_id)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            },
        },
    })
end)

---------------------------------------------------------------------------
-- Accounts
---------------------------------------------------------------------------
local function getAccountIdentifier(src)
    return GetPlayerIdentifierByType(src, VeylConfig.AccountIdentifier)
end

local function upsertAccount(license, name)
    MySQL.insert.await([[INSERT INTO veyl_accounts (license, name, max_characters) VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE name = VALUES(name), last_seen = CURRENT_TIMESTAMP]],
        { license, name or '', VeylConfig.DefaultMaxCharacters })
    return MySQL.single.await('SELECT id, max_characters FROM veyl_accounts WHERE license = ?', { license })
end

AddEventHandler('playerConnecting', function(name, _, deferrals)
    local src = source
    deferrals.defer()
    Wait(0)
    deferrals.update('VeylCore: checking your account...')
    if not Veyl.IsReady() then
        return deferrals.done('VeylCore is still starting. Please try again in a moment.')
    end
    local license = getAccountIdentifier(src)
    if not license then
        return deferrals.done('VeylCore requires a Rockstar license identifier. Restart FiveM and try again.')
    end
    local ok, account = pcall(upsertAccount, license, name)
    if not ok or not account then
        print(('^1[veyl_core] account lookup failed for %s: %s^7'):format(name, tostring(account)))
        return deferrals.done('VeylCore could not load your account (database error). Please try again.')
    end
    deferrals.done()
end)

---------------------------------------------------------------------------
-- Sessions
---------------------------------------------------------------------------
RegisterNetEvent('veyl_core:clientReady', function()
    local src = source
    if Sessions[src] and Sessions[src].pending then return end
    if Sessions[src] then
        -- Already have a session (client resource restarted): re-send state.
        local s = Sessions[src]
        TriggerClientEvent('veyl_core:sessionReady', src, { accountId = s.accountId, maxCharacters = s.maxCharacters })
        return
    end
    if not Veyl.IsReady() then
        TriggerClientEvent('veyl_core:sessionFailed', src, { code = 'NOT_READY', stage = 'core' })
        return
    end
    local license = getAccountIdentifier(src)
    if not license then
        return DropPlayer(src, 'VeylCore: missing license identifier')
    end
    Sessions[src] = { source = src, pending = true }
    local ok, account = pcall(upsertAccount, license, GetPlayerName(src))
    if not ok or not account then
        Sessions[src] = nil
        print(('^1[veyl_core] session creation failed for %s: %s^7'):format(src, tostring(account)))
        TriggerClientEvent('veyl_core:sessionFailed', src, { code = 'DATABASE_ERROR', stage = 'account' })
        return
    end
    if not GetPlayerName(src) then
        Sessions[src] = nil -- dropped while we were waiting on the database
        return
    end
    Sessions[src] = {
        source = src,
        sessionId = Veyl.NewId('sess'),
        accountId = account.id,
        license = license,
        name = GetPlayerName(src),
        maxCharacters = account.max_characters,
        characterId = nil,
        character = nil,
        generation = 0,
    }
    Player(src).state:set('veylAccountId', account.id, true)
    TriggerEvent('veyl:sessionStarted', src, account.id)
    TriggerClientEvent('veyl_core:sessionReady', src, { accountId = account.id, maxCharacters = account.max_characters })
end)

local function unloadCharacter(src, reason)
    local s = Sessions[src]
    if not s or not s.characterId then return false end
    local charId = s.characterId
    -- Listeners save their state synchronously from cached data before we clear the mapping.
    TriggerEvent('veyl:characterUnloading', src, charId, reason or 'logout')
    s.characterId = nil
    s.character = nil
    s.generation = s.generation + 1
    if CharToSource[charId] == src then CharToSource[charId] = nil end
    if GetPlayerName(src) then
        Player(src).state:set('veylCharId', nil, true)
        Player(src).state:set('veylCharName', nil, true)
        TriggerClientEvent('veyl:characterUnloaded', src, reason or 'logout')
    end
    TriggerEvent('veyl:characterUnloaded', src, charId, reason or 'logout')
    return true
end

AddEventHandler('playerDropped', function(reason)
    local src = source
    local s = Sessions[src]
    if not s then return end
    if s.characterId then unloadCharacter(src, 'dropped') end
    Sessions[src] = nil
    TriggerEvent('veyl:sessionEnded', src)
end)

---------------------------------------------------------------------------
-- Exports
---------------------------------------------------------------------------
exports('GetPlayer', function(src)
    return copySession(Sessions[tonumber(src)])
end)

exports('GetCharacterId', function(src)
    local s = Sessions[tonumber(src)]
    return s and s.characterId or nil
end)

exports('GetSourceByCharacter', function(charId)
    return CharToSource[tonumber(charId)]
end)

exports('GetPlayers', function()
    local list = {}
    for src, s in pairs(Sessions) do
        if s.accountId then
            list[#list + 1] = {
                source = src, accountId = s.accountId, name = s.name, characterId = s.characterId,
                characterName = s.character and (s.character.firstname .. ' ' .. s.character.lastname) or nil,
            }
        end
    end
    return list
end)

--- Permission check backed by ACE: HasPermission(src, 'admin') checks 'veyl.admin'.
exports('HasPermission', function(src, permission)
    src = tonumber(src)
    if src == 0 then return true end -- server console
    if not src or type(permission) ~= 'string' then return false end
    return IsPlayerAceAllowed(src, 'veyl.' .. permission)
end)

exports('Audit', function(src, resource, action, data)
    local s = src and Sessions[tonumber(src)]
    local encoded = data ~= nil and json.encode(data) or nil
    MySQL.insert('INSERT INTO veyl_audit (account_id, character_id, resource, action, data) VALUES (?, ?, ?, ?, ?)',
        { s and s.accountId or nil, s and s.characterId or nil, tostring(resource or '?'), tostring(action), encoded })
end)

--- Only veyl_characters may change the active character (it verifies ownership first).
exports('SetActiveCharacter', function(src, character)
    src = tonumber(src)
    local invoker = GetInvokingResource()
    if invoker ~= 'veyl_characters' then
        print(('^1[veyl_core] SetActiveCharacter refused from %s^7'):format(tostring(invoker)))
        return false
    end
    local s = Sessions[src]
    if not s or not s.accountId or type(character) ~= 'table' or not character.id then return false end
    if character.account_id ~= s.accountId then return false end
    local existing = CharToSource[character.id]
    if existing and existing ~= src then return false end -- loaded elsewhere
    if s.characterId then unloadCharacter(src, 'switch') end

    s.characterId = character.id
    s.character = {
        id = character.id, firstname = character.firstname, lastname = character.lastname,
        dob = character.dob, sex = character.sex,
    }
    s.generation = s.generation + 1
    CharToSource[character.id] = src
    Player(src).state:set('veylCharId', character.id, true)
    Player(src).state:set('veylCharName', character.firstname .. ' ' .. character.lastname, true)
    TriggerEvent('veyl:characterLoaded', src, character.id, s.character)
    TriggerClientEvent('veyl:characterLoaded', src, s.character)
    return true
end)

exports('UnloadCharacter', function(src, reason)
    return unloadCharacter(tonumber(src), reason)
end)

-- Resource restarts: tell clients so they can rebuild state cleanly.
AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for src in pairs(Sessions) do
        TriggerClientEvent('veyl_core:coreStopped', src)
    end
end)
