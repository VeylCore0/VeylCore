-- VeylCore library bootstrap. Import with:  shared_script '@veyl_lib/init.lua'
-- Creates `vlib` (modules, loaded lazily into THIS resource's environment) and, on the client, `vcache`.
-- It never defines or overwrites `lib`, `cache` or the global `require`, so it can run beside ox_lib.

if vlib ~= nil then return end

local LIB = 'veyl_lib'
local RESOURCE = GetCurrentResourceName()
local CONTEXT = IsDuplicityVersion() and 'server' or 'client'

if RESOURCE ~= LIB and GetResourceState(LIB) ~= 'started' and GetResourceState(LIB) ~= 'starting' then
    error(('^1%s requires veyl_lib to be started first (state: %s)^7'):format(RESOURCE, GetResourceState(LIB)), 0)
end

-- Function name -> module that provides it.
local ALIASES = {
    registerMenu = 'menu', showMenu = 'menu', hideMenu = 'menu', getOpenMenu = 'menu',
    inputDialog = 'dialog', alertDialog = 'dialog',
    notify = 'notify',
    showTextUI = 'textui', hideTextUI = 'textui', isTextUIOpen = 'textui',
    progress = 'progress', progressActive = 'progress', cancelProgress = 'progress',
    requestModel = 'streaming', requestAnimDict = 'streaming', requestPtfx = 'streaming',
    addKeybind = 'keybind', addCommand = 'command',
    onCache = 'cache',
    locale = 'locale', t = 'locale',
}
-- Table modules accessed by their own name (no aliasing): vlib.callback, vlib.points, vlib.zones,
-- vlib.print, vlib.validate, vlib.table, vlib.math.

local loaded = {}

local function loadModule(self, key)
    local moduleName = ALIASES[key] or key
    if loaded[moduleName] then return rawget(self, key) end
    local candidates = {
        ('modules/%s/%s.lua'):format(moduleName, CONTEXT),
        ('modules/%s/shared.lua'):format(moduleName),
    }
    for _, path in ipairs(candidates) do
        local code = LoadResourceFile(LIB, path)
        if code then
            local chunk, err = load(code, ('@@%s/%s'):format(LIB, path), 't')
            if not chunk then error(('vlib: failed to load %s: %s'):format(path, err), 2) end
            loaded[moduleName] = true
            local result = chunk()
            if type(result) == 'table' and ALIASES[key] then
                -- Multi-function module: expose each member on vlib.
                for name, fn in pairs(result) do rawset(self, name, fn) end
            else
                -- Single value (table or function): reachable by module name AND by the alias that was requested
                -- (e.g. module 'keybind' returns the function exposed as vlib.addKeybind).
                rawset(self, moduleName, result)
                if key ~= moduleName then rawset(self, key, result) end
            end
            return rawget(self, key)
        end
    end
    return nil
end

vlib = setmetatable({
    name = LIB,
    version = '0.3.0',
    context = CONTEXT,
    resource = RESOURCE,
}, { __index = loadModule })

if CONTEXT == 'client' then
    -- vcache: current player context, updated on change (consumers read instead of calling natives repeatedly).
    vcache = { resource = RESOURCE, playerId = PlayerId(), serverId = GetPlayerServerId(PlayerId()) }
    local handlers = {}
    vcache.__handlers = handlers

    local function set(key, value)
        local old = vcache[key]
        if old == value then return end
        vcache[key] = value
        local list = handlers[key]
        if list then
            for i = 1, #list do
                local ok, err = pcall(list[i], value, old)
                if not ok then print(('^1[vlib] vcache handler for %s failed: %s^7'):format(key, err)) end
            end
        end
    end

    CreateThread(function()
        while true do
            local ped = PlayerPedId()
            set('ped', ped)
            local veh = GetVehiclePedIsIn(ped, false)
            set('vehicle', veh ~= 0 and veh or false)
            local seat = false
            if veh ~= 0 then
                for s = -1, GetVehicleMaxNumberOfPassengers(veh) - 1 do
                    if GetPedInVehicleSeat(veh, s) == ped then seat = s break end
                end
            end
            set('seat', seat)
            set('weapon', GetSelectedPedWeapon(ped))
            Wait(100)
        end
    end)
end
