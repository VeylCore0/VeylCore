-- veyl_doctor: one console command that checks a VeylCore server after a restart, an update or a clean install.
--   veylcheck   resources started and ready, database tables and migrations, server settings, item pictures

local function line(ok, text) print((ok == true and '^2  OK   ^7' or ok == false and '^1  FAIL ^7' or '^3  WARN ^7') .. text) end

local EXPECTED_TABLES = {
    veyl_core = { 'veyl_accounts', 'veyl_players', 'veyl_player_groups', 'veyl_money', 'veyl_money_ledger', 'veyl_audit' },
    veyl_inventory = { 'veyl_inventories', 'veyl_inventory_slots', 'veyl_inventory_operations' },
    veyl_vehicles = { 'veyl_player_vehicles' },
    veyl_police = { 'veyl_police_citations' },
    veyl_mdt = { 'veyl_mdt_reports', 'veyl_mdt_warrants', 'veyl_mdt_vehicle_flags', 'veyl_mdt_profiles' },
    veyl_prison = { 'veyl_prison_sentences', 'veyl_prison_history' },
    veyl_business = { 'veyl_businesses', 'veyl_business_ledger' },
}

local function check()
    print('^5==== VeylCore check ====^7')
    local fails, warns = 0, 0
    local function fail(t) fails = fails + 1 line(false, t) end
    local function warn(t) warns = warns + 1 line(nil, t) end

    -- Resources
    print('^5Resources^7')
    local started = {}
    for i = 0, GetNumResources() - 1 do
        local name = GetResourceByFindIndex(i)
        if name and name:sub(1, 5) == 'veyl_' and name ~= 'veyl_weedprops' then
            local state = GetResourceState(name)
            if state == 'started' then
                started[name] = true
                local ready = GlobalState['veyl:ready:' .. name]
                if ready == false then fail(('%s is started but NOT READY (see its startup messages)'):format(name))
                else line(true, name .. (ready and ' (ready)' or '')) end
            elseif state ~= 'missing' and name ~= 'veyl_qbexample' and name ~= 'veyl_migrate' then
                warn(('%s is %s (not in server.cfg?)'):format(name, state))
            end
        end
    end
    for _, dep in ipairs({ 'oxmysql', 'pma-voice' }) do
        if GetResourceState(dep) == 'started' then line(true, dep) else (dep == 'oxmysql' and fail or warn)(dep .. ' is not started') end
    end

    -- Database
    print('^5Database^7')
    local okDb, tables = pcall(function()
        local set = {}
        for _, r in ipairs(MySQL.query.await('SELECT table_name AS t FROM information_schema.tables WHERE table_schema = DATABASE()') or {}) do set[r.t] = true end
        return set
    end)
    if not okDb then
        fail('Database unreachable: ' .. tostring(tables))
    else
        for res, list in pairs(EXPECTED_TABLES) do
            if started[res] then
                local missing = {}
                for _, t in ipairs(list) do if not tables[t] then missing[#missing + 1] = t end end
                if #missing > 0 then fail(('%s tables missing: %s'):format(res, table.concat(missing, ', '))) else line(true, res .. ' tables') end
            end
        end
        local n = MySQL.scalar.await('SELECT COUNT(*) FROM veyl_migrations') or 0
        line(true, ('%d migrations applied'):format(n))
        local chars = MySQL.scalar.await('SELECT COUNT(*) FROM veyl_players WHERE deleted_at IS NULL') or 0
        line(true, ('%d characters'):format(chars))
    end

    -- Server settings
    print('^5Settings^7')
    local onesync = GetConvar('onesync', 'off')
    if onesync == 'on' or onesync == 'legacy' then line(true, 'OneSync ' .. onesync) else fail('OneSync is off (needed for voice, routing buckets and server-side positions)') end
    local build = GetConvar('sv_enforceGameBuild', '')
    if build ~= '' then line(true, 'Game build ' .. build) else warn('sv_enforceGameBuild is not set (VeylCore targets 3751)') end
    if GetResourceState('pma-voice') == 'started' and GetConvar('voice_enableUi', '1') ~= '0' then warn('pma-voice overlay is on: set "setr voice_enableUi 0" (the HUD shows voice)') end
    if GetResourceState('spawnmanager') == 'started' then fail('spawnmanager is running: veyl_spawn owns spawning, remove it') end

    -- Item pictures
    if started.veyl_inventory then
        print('^5Item pictures^7')
        local missing = {}
        for name, def in pairs(exports.veyl_inventory:Items() or {}) do
            local img = def.image or (name .. '.png')
            if not LoadResourceFile('veyl_inventory', 'web/images/' .. img) then missing[#missing + 1] = img end
        end
        table.sort(missing)
        if #missing == 0 then line(true, 'every item has a picture')
        else warn(('%d items show the placeholder icon. Add these to veyl_inventory/web/images: %s'):format(#missing, table.concat(missing, ', '))) end
    end

    print(('^5==== %s: %d failure%s, %d warning%s ====^7'):format(fails == 0 and 'Healthy' or 'Needs attention', fails, fails == 1 and '' or 's', warns, warns == 1 and '' or 's'))
end

RegisterCommand('veylcheck', function(src)
    if src ~= 0 then return end
    CreateThread(function()
        local ok, err = pcall(check)
        if not ok then print('^1[veyl_doctor] check failed: ' .. tostring(err) .. '^7') end
    end)
end, true)

-- Runs once a minute after start, when everything had time to come up.
CreateThread(function()
    Wait(60000)
    pcall(check)
end)
