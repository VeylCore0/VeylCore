-- VeylCore server library. Import after shared.lua and (when using the DB helpers) @oxmysql/lib/MySQL.lua:
--   server_scripts { '@oxmysql/lib/MySQL.lua', '@veyl_core/lib/server.lua', ... }
Veyl = Veyl or {}
local RES = GetCurrentResourceName()

---------------------------------------------------------------------------
-- Player/session helpers (veyl_core is the only owner of session state)
---------------------------------------------------------------------------
--- Plain PlayerData snapshot (no functions) or nil. Use exports.veyl_core:GetPlayer(src) for the player object.
function Veyl.GetPlayerData(src)
    return exports.veyl_core:GetPlayerData(src)
end

--- The active character's citizenid for an online source, or nil.
function Veyl.GetCitizenId(src)
    return exports.veyl_core:GetCitizenId(src)
end

function Veyl.GetSourceByCitizenId(citizenid)
    return exports.veyl_core:GetSourceByCitizenId(citizenid)
end

--- Session generation: changes every login/logout, so long-running work can detect a character switch.
function Veyl.GetSessionGeneration(src)
    return exports.veyl_core:GetSessionGeneration(src)
end

function Veyl.HasPermission(src, permission)
    return exports.veyl_core:HasPermission(src, permission)
end

function Veyl.Audit(src, action, data)
    exports.veyl_core:Audit(src, RES, action, data)
end

function Veyl.Notify(src, message, kind, durationMs)
    TriggerClientEvent('veyl_ui:notify', src, { message = message, type = kind or 'info', duration = durationMs })
end

function Veyl.GetPlayerCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

---------------------------------------------------------------------------
-- Bounded client -> server request handling
---------------------------------------------------------------------------
local lastCall, inflight = {}, {}

--- Register a callback the client can invoke with Veyl.Callback('<this resource>', name, ...).
--- handler(src, citizenid, ...) must return a Veyl.Ok/Veyl.Err table.
--- opts.cooldown (ms, default 250), opts.requireCharacter (default true), opts.permission (string)
function Veyl.RegisterCallback(name, handler, opts)
    opts = opts or {}
    local cooldown = opts.cooldown or 250
    local requireCharacter = opts.requireCharacter ~= false
    RegisterNetEvent(('veyl:cb:%s:%s'):format(RES, name), function(reqId, ...)
        local src = source
        if type(reqId) ~= 'string' or #reqId > 96 then return end
        local function reply(res) TriggerClientEvent('veyl:cbr', src, reqId, res) end

        if GlobalState['veyl:ready:' .. RES] ~= true then
            return reply(Veyl.Err('NOT_READY', RES .. ' is still starting'))
        end
        local key = src .. '|' .. name
        if inflight[key] then return reply(Veyl.Err('BUSY', 'Previous request still running')) end
        local now = GetGameTimer()
        if lastCall[key] and now - lastCall[key] < cooldown then
            return reply(Veyl.Err('RATE_LIMITED', 'Too many requests'))
        end
        lastCall[key] = now

        local citizenid = nil
        if requireCharacter then
            citizenid = Veyl.GetCitizenId(src)
            if not citizenid then return reply(Veyl.Err('NO_CHARACTER', 'No character loaded')) end
        end
        if opts.permission and not Veyl.HasPermission(src, opts.permission) then
            Veyl.Audit(src, 'denied_callback', { callback = name, permission = opts.permission })
            return reply(Veyl.Err('NO_PERMISSION', 'You are not allowed to do that'))
        end

        inflight[key] = true
        local ok, res = pcall(handler, src, citizenid, ...)
        inflight[key] = nil
        if not ok then
            print(('^1[%s] callback %s error: %s^7'):format(RES, name, tostring(res)))
            res = Veyl.Err('INTERNAL', 'Internal error')
        elseif type(res) ~= 'table' then
            res = Veyl.Err('INTERNAL', 'Handler returned no response')
        end
        reply(res)
    end)
end

AddEventHandler('playerDropped', function()
    local src = tostring(source)
    local prefix = src .. '|'
    for k in pairs(lastCall) do
        if k:sub(1, #prefix) == prefix then lastCall[k] = nil end
    end
end)

---------------------------------------------------------------------------
-- Database migrations (each resource owns and migrates its own tables)
---------------------------------------------------------------------------
--- migrations = { { id = '001_init', sql = { 'CREATE TABLE ...', ... } }, ... }
function Veyl.Migrate(migrations)
    local ok, err = pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS veyl_migrations (
                resource VARCHAR(64) NOT NULL,
                id VARCHAR(128) NOT NULL,
                applied_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (resource, id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4
        ]])
        for _, m in ipairs(migrations) do
            local done = MySQL.scalar.await('SELECT 1 FROM veyl_migrations WHERE resource = ? AND id = ?', { RES, m.id })
            if not done then
                for _, statement in ipairs(m.sql) do
                    MySQL.query.await(statement)
                end
                MySQL.insert.await('INSERT INTO veyl_migrations (resource, id) VALUES (?, ?)', { RES, m.id })
                print(('^2[%s] applied migration %s^7'):format(RES, m.id))
            end
        end
    end)
    if not ok then
        print(('^1[%s] MIGRATION FAILED: %s^7'):format(RES, tostring(err)))
        return false
    end
    return true
end

---------------------------------------------------------------------------
-- Startup / readiness
---------------------------------------------------------------------------
--- Runs fn after the database is reachable and all `requires` services are ready, then marks this
--- resource ready. If anything fails the resource stays NOT_READY and prints the failed stage.
function Veyl.Startup(requires, fn)
    GlobalState['veyl:ready:' .. RES] = false
    Citizen.CreateThread(function()
        if MySQL then
            local okDb = pcall(MySQL.ready.await)
            if not okDb then
                print(('^1[%s] NOT READY: database connection unavailable^7'):format(RES))
                return
            end
        end
        for _, dep in ipairs(requires or {}) do
            if not Veyl.WaitForService(dep, 30000) then
                print(('^1[%s] NOT READY: required service %s did not become ready (state: %s)^7')
                    :format(RES, dep, GetResourceState(dep)))
                return
            end
        end
        local ok, err = pcall(fn)
        if ok and err ~= false then
            GlobalState['veyl:ready:' .. RES] = true
            print(('^5[%s] ready^7'):format(RES))
        else
            print(('^1[%s] NOT READY: startup failed: %s^7'):format(RES, tostring(err)))
        end
    end)
end

AddEventHandler('onResourceStop', function(res)
    if res == RES then GlobalState['veyl:ready:' .. RES] = false end
end)

--- Fails a request early when this resource has not finished startup.
function Veyl.IsReady()
    return GlobalState['veyl:ready:' .. RES] == true
end
