-- Lab looks: the interior is dressed to match its upgrades, like the GTA Online biker businesses. Each Biker DLC interior has "entity sets"
-- (equipment, plants, lights, hoses, security, tables) that can be switched on and off; every level you buy turns more of them on.
-- The server only sends the four upgrade levels; this decides which sets to show. It is local to the player, so each lab shows its own level.
--
--   Weed farm (biker_warehouse): storage -> weed on the tables, chairs, drying racks; benches -> 3, 5, 7, 9 grow rooms with lamps and hoses;
--                                equipment -> standard then upgraded kit, brighter lights, fans; security -> cameras then the steel door.
--   Meth lab (biker_field):      benches / equipment -> empty room, basic kit, upgraded kit; storage -> product; security -> steel door.
--   Cocaine lockup (biker_supplier): equipment -> basic then upgraded presses and tables; benches -> production line; storage -> cut coke;
--                                security -> low then high.

local C = ProductionConfig
local P = C.Properties
local LETTERS = { 'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i' }

---------------------------------------------------------------------------
-- What to show for each interior: returns every set it controls, and the ones that should be on
---------------------------------------------------------------------------
local function weed(l)
    local all, on = {}, {}
    local function set(name, state) all[#all + 1] = name if state then on[name] = true end end
    set('weed_standard_equip', l.equipment == 0)
    set('weed_upgrade_equip', l.equipment >= 1)
    set('weed_set_up', l.equipment >= 3)
    set('weed_production', l.storage >= 1)
    set('weed_chairs', l.storage >= 2)
    set('weed_drying', l.storage >= 3)
    set('weed_low_security', l.security >= 1 and l.security < 3)
    set('weed_security_upgrade', l.security >= 3)
    local plants = math.min(#LETTERS, 3 + 2 * l.benches)
    for i, x in ipairs(LETTERS) do
        local has = i <= plants
        local full = i % 2 == 1
        set(('weed_growth%s_stage1'):format(x), false)
        set(('weed_growth%s_stage2'):format(x), has and not full)
        set(('weed_growth%s_stage3'):format(x), has and full)
        set(('light_growth%s_stage23_standard'):format(x), has and l.equipment < 2)
        set(('light_growth%s_stage23_upgrade'):format(x), has and l.equipment >= 2)
        set(('weed_hose%s'):format(x), has)
    end
    return all, on
end

local function meth(l)
    local all, on = {}, {}
    local function set(name, state) all[#all + 1] = name if state then on[name] = true end end
    local built = l.equipment + l.benches
    set('meth_lab_empty', built == 0)
    set('meth_lab_basic', built >= 1 and l.equipment < 2)
    set('meth_lab_upgrade', l.equipment >= 2)
    set('meth_lab_setup', built >= 1)
    set('meth_lab_production', l.storage >= 1)
    set('meth_lab_security_high', l.security >= 2)
    return all, on
end

local function cocaine(l)
    local all, on = {}, {}
    local function set(name, state) all[#all + 1] = name if state then on[name] = true end end
    local up = l.equipment >= 2
    set('set_up', true)
    set('equipment_basic', not up) set('equipment_upgrade', up)
    set('coke_press_basic', not up) set('coke_press_upgrade', up)
    set('table_equipment', not up) set('table_equipment_upgrade', up)
    set('production_basic', l.benches >= 1 and l.equipment < 3)
    set('production_upgrade', l.benches >= 1 and l.equipment >= 3)
    for _, n in ipairs({ 'coke_cut_01', 'coke_cut_02', 'coke_cut_03' }) do set(n, l.storage >= 1 and not up) end
    for _, n in ipairs({ 'coke_cut_04', 'coke_cut_05' }) do set(n, l.storage >= 1 and up) end
    set('security_low', l.security >= 1 and l.security < 3)
    set('security_high', l.security >= 3)
    return all, on
end

local BUILD = { biker_warehouse = weed, biker_field = meth, biker_supplier = cocaine }

---------------------------------------------------------------------------
-- Applying it
---------------------------------------------------------------------------
local function levels(looks)
    looks = type(looks) == 'table' and looks or {}
    local function n(v) return math.max(0, math.min(3, math.floor(tonumber(v) or 0))) end
    return { storage = n(looks.storage), benches = n(looks.benches), equipment = n(looks.equipment), security = n(looks.security) }
end

--- Switches the entity sets of the interior at `spawn` to match `looks`. Safe to call again at any time.
function ProdClient.dressLab(interiorKey, looks, spawn)
    if P.Visuals == false then return end
    local build = BUILD[interiorKey]
    if not build or not spawn then return end
    local interior = GetInteriorAtCoords(spawn.x + 0.0, spawn.y + 0.0, spawn.z + 0.0)
    if not interior or interior == 0 then return end
    PinInteriorInMemory(interior)
    local deadline = GetGameTimer() + 4000
    while not IsInteriorReady(interior) and GetGameTimer() < deadline do Wait(25) end
    local all, on = build(levels(looks))
    for _, name in ipairs(all) do
        local active = IsInteriorEntitySetActive(interior, name)
        if on[name] and not active then ActivateInteriorEntitySet(interior, name)
        elseif not on[name] and active then DeactivateInteriorEntitySet(interior, name) end
    end
    RefreshInterior(interior)
end

--- An upgrade was bought while someone is inside: fade, dress the room, fade back, say what arrived.
local NEW = {
    storage = 'New storage racks and product are in', benches = 'More grow and work space has been built',
    equipment = 'Better equipment has been installed', security = 'The security system has been fitted',
}
RegisterNetEvent('veyl_production:looks', function(id, looks, key)
    if ProdClient.inside ~= id or not ProdClient.interior then return end
    CreateThread(function()
        local interior = ProdClient.interior
        local key_ = nil
        for _, d in ipairs(C.Properties.Catalogue) do if d.id == id then key_ = d.interior end end
        if not key_ then return end
        DoScreenFadeOut(350)
        while not IsScreenFadedOut() do Wait(10) end
        ProdClient.dressLab(key_, looks, interior.spawn)
        Wait(250)
        DoScreenFadeIn(600)
        if NEW[key] then Veyl.Notify(NEW[key], 'success', 6000) end
    end)
end)
