-- veyl_migrate: imports characters from a QBCore or QBox database (the same database, tables `players` and
-- `player_vehicles`) into VeylCore. Console only.
--
--   veylmigrate            dry run: reads everything, changes nothing, prints what would happen
--   veylmigrate apply      imports. Characters whose citizenid already exists in VeylCore are skipped,
--                          so running it twice never duplicates anything.
--
-- Imported per character: account (Rockstar licence), name and details, cash / bank / crypto, job and gang with grade
-- (when that job / gang exists in VeylCore), licences, hunger / thirst / stress, callsign, last position, inventory
-- items that exist in veyl_inventory (both the qb-inventory and ox_inventory layouts), and owned vehicles.

local function decode(v, fallback)
    if type(v) == 'table' then return v end
    if type(v) ~= 'string' or v == '' then return fallback end
    local ok, t = pcall(json.decode, v)
    return ok and t or fallback
end

local function tableExists(name)
    return MySQL.scalar.await('SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ?', { name }) > 0
end

local function columns(name)
    local set = {}
    for _, r in ipairs(MySQL.query.await('SELECT column_name AS c FROM information_schema.columns WHERE table_schema = DATABASE() AND table_name = ?', { name }) or {}) do
        set[r.c] = true
    end
    return set
end

local function say(fmt, ...) print(('^5[veyl_migrate]^7 ' .. fmt):format(...)) end

local function run(apply)
    if not tableExists('players') then return say('No `players` table in this database: nothing to import.') end
    if not tableExists('veyl_players') then return say('VeylCore tables are missing. Start veyl_core once first.') end
    local items = exports.veyl_inventory:Items() or {}
    local jobs, gangs = exports.veyl_core:GetJobs(), exports.veyl_core:GetGangs()
    local pcols = columns('players')
    local rows = MySQL.query.await('SELECT * FROM players') or {}
    local stats = { characters = 0, skipped = 0, accounts = 0, items = 0, unknownItems = {}, unknownJobs = {}, vehicles = 0, vehicleSkips = 0, money = 0 }
    say('%s: %d characters found in `players`%s.', apply and 'IMPORT' or 'DRY RUN', #rows, pcols.inventory and '' or ' (no inventory column)')

    for _, r in ipairs(rows) do
        local cid = r.citizenid
        if type(cid) ~= 'string' or cid == '' or MySQL.scalar.await('SELECT 1 FROM veyl_players WHERE citizenid = ?', { cid }) then
            stats.skipped = stats.skipped + 1
        else
            stats.characters = stats.characters + 1
            local ci = decode(r.charinfo, {})
            local money = decode(r.money, {})
            local job, gang = decode(r.job, {}), decode(r.gang, {})
            local meta = decode(r.metadata, {})
            local pos = decode(r.position, nil)
            local jobName = type(job.name) == 'string' and job.name or 'unemployed'
            local jobGrade = tonumber(type(job.grade) == 'table' and job.grade.level or job.grade) or 0
            local gangName = type(gang.name) == 'string' and gang.name or 'none'
            local gangGrade = tonumber(type(gang.grade) == 'table' and gang.grade.level or gang.grade) or 0
            if jobName ~= 'unemployed' and not jobs[jobName] then stats.unknownJobs[jobName] = true jobName = 'unemployed' end
            if gangName ~= 'none' and not gangs[gangName] then stats.unknownJobs['gang:' .. gangName] = true gangName = 'none' end
            local charinfo = {
                firstname = ci.firstname, lastname = ci.lastname, birthdate = ci.birthdate, gender = tonumber(ci.gender) == 1 and 1 or 0,
                nationality = ci.nationality, phone = ci.phone and tostring(ci.phone) or nil, account = ci.account, cid = tonumber(r.cid) or 1,
            }
            local metadata = {
                hunger = tonumber(meta.hunger) or 100, thirst = tonumber(meta.thirst) or 100, stress = tonumber(meta.stress) or 0,
                isdead = false, inlaststand = false, ishandcuffed = meta.ishandcuffed == true,
                licences = type(meta.licences) == 'table' and meta.licences or { driver = true, weapon = false, business = false },
                callsign = type(meta.callsign) == 'string' and meta.callsign or 'NO CALLSIGN',
            }
            local position = type(pos) == 'table' and pos.x and json.encode({ x = pos.x, y = pos.y, z = pos.z, w = pos.w or pos.heading or 0.0 }) or nil

            -- Inventory: qb-inventory [{ name, amount, info, slot }] or ox_inventory [{ name, count, metadata, slot }]
            local inv = {}
            for _, it in pairs(decode(r.inventory, {}) or {}) do
                if type(it) == 'table' and type(it.name) == 'string' then
                    if items[it.name] then
                        inv[#inv + 1] = { slot = tonumber(it.slot) or (#inv + 1), name = it.name, count = math.max(1, math.floor(tonumber(it.amount or it.count) or 1)),
                            metadata = type(it.info) == 'table' and it.info or (type(it.metadata) == 'table' and it.metadata or {}) }
                    else
                        stats.unknownItems[it.name] = (stats.unknownItems[it.name] or 0) + 1
                    end
                end
            end
            stats.items = stats.items + #inv
            stats.money = stats.money + (tonumber(money.cash) or 0) + (tonumber(money.bank) or 0)

            if apply then
                local license = type(r.license) == 'string' and r.license or ('migrated:' .. cid)
                MySQL.insert.await([[INSERT INTO veyl_accounts (license, name) VALUES (?, ?) ON DUPLICATE KEY UPDATE last_seen = last_seen]], { license, r.name or '' })
                local accountId = MySQL.scalar.await('SELECT id FROM veyl_accounts WHERE license = ?', { license })
                local slot = tonumber(r.cid) or 1
                while MySQL.scalar.await('SELECT 1 FROM veyl_players WHERE account_id = ? AND cid = ? AND deleted_at IS NULL', { accountId, slot }) do slot = slot + 1 end
                charinfo.cid = slot
                MySQL.insert.await([[INSERT INTO veyl_players (citizenid, account_id, cid, license, charinfo, metadata, position, job, gang)
                    VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)]], { cid, accountId, slot, license, json.encode(charinfo), json.encode(metadata), position, jobName, gangName })
                if jobName ~= 'unemployed' then
                    MySQL.insert.await('INSERT IGNORE INTO veyl_player_groups (citizenid, group_type, name, grade) VALUES (?, ?, ?, ?)', { cid, 'job', jobName, jobGrade })
                end
                if gangName ~= 'none' then
                    MySQL.insert.await('INSERT IGNORE INTO veyl_player_groups (citizenid, group_type, name, grade) VALUES (?, ?, ?, ?)', { cid, 'gang', gangName, gangGrade })
                end
                for _, t in ipairs({ 'cash', 'bank', 'crypto' }) do
                    MySQL.insert.await('INSERT INTO veyl_money (citizenid, type, balance) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE balance = VALUES(balance)',
                        { cid, t, math.max(0, math.floor(tonumber(money[t]) or 0)) })
                end
                if #inv > 0 then
                    local invId = 'player:' .. cid
                    MySQL.insert.await('INSERT IGNORE INTO veyl_inventories (id, type, owner, label, slots, max_weight) VALUES (?, ?, ?, ?, ?, ?)',
                        { invId, 'player', cid, 'Pockets', InventoryConfigSlots(), InventoryConfigWeight() })
                    local used = {}
                    for _, it in ipairs(inv) do
                        local s = it.slot
                        while used[s] do s = s + 1 end
                        used[s] = true
                        MySQL.insert.await('INSERT IGNORE INTO veyl_inventory_slots (inventory_id, slot, item, count, metadata) VALUES (?, ?, ?, ?, ?)',
                            { invId, s, it.name, it.count, json.encode(it.metadata) })
                    end
                end
            end
        end
    end

    if tableExists('player_vehicles') then
        local vrows = MySQL.query.await('SELECT * FROM player_vehicles') or {}
        for _, v in ipairs(vrows) do
            local plate = type(v.plate) == 'string' and v.plate:gsub('^%s+', ''):gsub('%s+$', ''):upper():sub(1, 8) or nil
            local model = v.vehicle or v.model
            local owned = v.citizenid and MySQL.scalar.await('SELECT 1 FROM veyl_players WHERE citizenid = ?', { v.citizenid })
            if not plate or not model or (not owned and apply) or MySQL.scalar.await('SELECT 1 FROM veyl_player_vehicles WHERE plate = ?', { plate }) then
                stats.vehicleSkips = stats.vehicleSkips + 1
            else
                stats.vehicles = stats.vehicles + 1
                if apply then
                    local state = tonumber(v.state) == 2 and 'impound' or 'garaged'
                    MySQL.insert.await([[INSERT IGNORE INTO veyl_player_vehicles (citizenid, model, plate, props, state, garage, fuel, engine, body)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)]], { v.citizenid, tostring(model), plate, v.mods, state, v.garage,
                        tonumber(v.fuel) or 100, tonumber(v.engine) or 1000, tonumber(v.body) or 1000 })
                end
            end
        end
    end

    say('Characters %s: %d (already in VeylCore, skipped: %d)', apply and 'imported' or 'to import', stats.characters, stats.skipped)
    say('Inventory items: %d · Vehicles: %d (skipped %d: plate taken or owner missing) · Cash + bank: $%d', stats.items, stats.vehicles, stats.vehicleSkips, stats.money)
    local unknown = {}
    for name, n in pairs(stats.unknownItems) do unknown[#unknown + 1] = ('%s x%d'):format(name, n) end
    if #unknown > 0 then say('^3Items that do not exist in veyl_inventory (not imported): %s^7', table.concat(unknown, ', ')) end
    local uj = {}
    for name in pairs(stats.unknownJobs) do uj[#uj + 1] = name end
    if #uj > 0 then say('^3Jobs / gangs not defined in VeylCore (characters set to unemployed / none): %s^7', table.concat(uj, ', ')) end
    if not apply then say('Nothing was changed. Back up the database, then run: veylmigrate apply') end
end

-- Inventory sizes come from veyl_inventory's config when it is readable; otherwise its defaults.
function InventoryConfigSlots() return tonumber(GetConvar('veyl_migrate:slots', '30')) end
function InventoryConfigWeight() return tonumber(GetConvar('veyl_migrate:weight', '30000')) end

RegisterCommand('veylmigrate', function(src, args)
    if src ~= 0 then return print('[veyl_migrate] console only') end
    local apply = args[1] == 'apply'
    CreateThread(function()
        local ok, err = pcall(run, apply)
        if not ok then say('^1Failed: %s^7', tostring(err)) end
    end)
end, true)

say('Loaded. Run "veylmigrate" in the server console for a dry run.')
