-- veyl_appearance server: owns saved appearance and outfits per character, and charges for store changes.
--
-- save      : free full save. Only for character creation (no saved look yet), or /appearance when allowed.
-- checkout  : clothing store / barber. The server checks you're at that store, takes ONLY the categories that store
--             may change from your request, keeps everything else from your saved look, prices the changes itself
--             and charges once per operation id (DebitOnce) before saving.

local function core(name, ...) return Veyl.Await('veyl_core', name, 15000, ...) end

Veyl.Startup({ 'veyl_core' }, function()
    return Veyl.Migrate({
        {
            id = '001_appearance_citizenid',
            sql = {
                [[CREATE TABLE IF NOT EXISTS veyl_appearance (
                    citizenid VARCHAR(16) NOT NULL,
                    model VARCHAR(32) NOT NULL,
                    data LONGTEXT NOT NULL,
                    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                    PRIMARY KEY (citizenid)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            },
        },
        {
            id = '002_outfits',
            sql = {
                [[CREATE TABLE IF NOT EXISTS veyl_outfits (
                    id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                    citizenid VARCHAR(16) NOT NULL,
                    model VARCHAR(32) NOT NULL,
                    name VARCHAR(32) NOT NULL,
                    data LONGTEXT NOT NULL,
                    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                    PRIMARY KEY (id),
                    KEY idx_citizen (citizenid)
                ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            },
        },
    })
end)

local allowedModels = {}
for _, m in pairs(AppearanceConfig.Models) do allowedModels[m] = true end

---------------------------------------------------------------------------
-- Validation
---------------------------------------------------------------------------
local V = Veyl.Validate
local function int(v, min, max, default) return V.int(v, min, max) and v or default end

local function cleanList(list, maxId, extra)
    local out, seen = {}, {}
    if type(list) ~= 'table' then return out end
    for _, e in ipairs(list) do
        if #out >= 20 then break end
        if type(e) == 'table' and V.int(e.id, 0, maxId) and not seen[e.id] and V.int(e.d, -1, 1000) then
            seen[e.id] = true
            local entry = { id = e.id, d = e.d, t = int(e.t, 0, 255, 0) }
            if extra then extra(entry, e) end
            out[#out + 1] = entry
        end
    end
    return out
end

local function cleanAppearance(input)
    if type(input) ~= 'table' or not allowedModels[input.model] then return nil end
    local hb = type(input.headBlend) == 'table' and input.headBlend or {}
    local hair = type(input.hair) == 'table' and input.hair or {}
    local features = {}
    for i = 1, Appearance.FEATURE_COUNT do
        features[i] = int(type(input.faceFeatures) == 'table' and input.faceFeatures[i] or 0, -100, 100, 0)
    end
    return Appearance.normalise({
        model = input.model,
        components = cleanList(input.components, 11),
        props = cleanList(input.props, 7),
        overlays = cleanList(input.overlays, 12, function(entry, e)
            entry.t = nil
            entry.d = math.min(entry.d, 80)
            entry.opacity = int(e.opacity, 0, 100, 100)
            entry.color = int(e.color, 0, 63, 0)
        end),
        headBlend = {
            mother = int(hb.mother, 0, 45, 21), father = int(hb.father, 0, 45, 0),
            shapeMix = int(hb.shapeMix, 0, 100, 50), skinMix = int(hb.skinMix, 0, 100, 50),
        },
        hair = { color = int(hair.color, 0, 63, 0), highlight = int(hair.highlight, 0, 63, 0) },
        faceFeatures = features,
        eyeColor = int(input.eyeColor, 0, 31, 0),
    })
end

---------------------------------------------------------------------------
-- Storage
---------------------------------------------------------------------------
local function load(citizenid)
    local row = MySQL.single.await('SELECT model, data FROM veyl_appearance WHERE citizenid = ?', { citizenid })
    if not row then return nil end
    local ok, data = pcall(json.decode, row.data)
    if not ok or type(data) ~= 'table' then return nil end
    data.model = row.model
    return Appearance.normalise(data)
end

local function store(citizenid, a)
    local data = json.decode(json.encode(a))
    local model = data.model
    data.model = nil
    local ok, res = pcall(MySQL.query.await, [[INSERT INTO veyl_appearance (citizenid, model, data) VALUES (?, ?, ?)
        ON DUPLICATE KEY UPDATE model = VALUES(model), data = VALUES(data)]], { citizenid, model, json.encode(data) })
    -- Other resources (the inventory's hat, glasses and mask slots) follow the saved look.
    if ok then TriggerEvent('veyl_appearance:saved', citizenid) end
    return ok, res
end

local function outfitsOf(citizenid, model)
    local rows = MySQL.query.await('SELECT id, name, data FROM veyl_outfits WHERE citizenid = ? AND model = ? ORDER BY id DESC',
        { citizenid, model }) or {}
    local list = {}
    for _, r in ipairs(rows) do
        local ok, slots = pcall(json.decode, r.data)
        if ok and type(slots) == 'table' then list[#list + 1] = { id = r.id, name = r.name, slots = slots } end
    end
    return list
end

local function balancesOf(src)
    local pd = Veyl.GetPlayerData(src)
    return { cash = pd and pd.money.cash or 0, bank = pd and pd.money.bank or 0 }
end

local function canUseCommand(src)
    local mode = AppearanceConfig.AllowCommand
    if mode == true then return true end
    return mode == 'admin' and Veyl.HasPermission(src, 'admin')
end

local function storeAt(src, storeType, index)
    local s = AppearanceConfig.Stores[storeType]
    local loc = s and V.int(index, 1, #s.locations) and s.locations[index]
    if not loc then return nil, Veyl.Err('NOT_FOUND', 'Unknown store') end
    local pc = Veyl.GetPlayerCoords(src)
    if not pc or #(pc - loc) > s.radius + 4.0 then return nil, Veyl.Err('TOO_FAR', 'You need to be in the store') end
    return s
end

---------------------------------------------------------------------------
-- Callbacks
---------------------------------------------------------------------------
Veyl.RegisterCallback('get', function(_, citizenid)
    return Veyl.Ok(load(citizenid))
end, { cooldown = 500 })

Veyl.RegisterCallback('canEditFree', function(src, citizenid)
    return Veyl.Ok({ allowed = load(citizenid) == nil or canUseCommand(src) })
end, { cooldown = 500 })

--- Free full save: character creation (nothing saved yet) or /appearance when AllowCommand permits it.
Veyl.RegisterCallback('save', function(src, citizenid, input)
    local data = cleanAppearance(input)
    if not data then return Veyl.Err('INVALID_INPUT', 'Invalid appearance data') end
    if load(citizenid) ~= nil and not canUseCommand(src) then
        return Veyl.Err('NO_PERMISSION', 'Visit a clothing store or barber to change your look')
    end
    if not store(citizenid, data) then return Veyl.Err('DATABASE_ERROR', 'Could not save your appearance') end
    return Veyl.Ok(nil, 'Appearance saved')
end, { cooldown = 2000 })

--- Store screen data: prices, balances and (clothing stores) saved outfits.
Veyl.RegisterCallback('storeContext', function(src, citizenid, storeType, index)
    local s, err = storeAt(src, storeType, index)
    if not s then return err end
    local saved = load(citizenid)
    if not saved then return Veyl.Err('NOT_FOUND', 'Create your character first') end
    local prices = {}
    for _, key in ipairs(Appearance.allowedKeys(storeType)) do prices[key] = AppearanceConfig.Prices[key] or 0 end
    return Veyl.Ok({
        title = s.label, subtitle = s.subtitle, prices = prices, balances = balancesOf(src),
        methods = AppearanceConfig.PaymentMethods, outfits = storeType == 'clothing' and outfitsOf(citizenid, saved.model) or nil,
    })
end, { cooldown = 500 })

--- Price of moving from `saved` to `next` in one store. A slot matching a saved outfit is free.
local function priceOf(storeType, saved, next, outfits)
    local total, lines = 0, {}
    for _, key in ipairs(Appearance.allowedKeys(storeType)) do
        local cat = Appearance.byKey[key]
        local before, after = Appearance.getSlot(saved, cat), Appearance.getSlot(next, cat)
        if not Appearance.sameSlot(before, after) then
            local price = AppearanceConfig.Prices[key] or 0
            for _, o in ipairs(outfits or {}) do
                if Appearance.sameSlot(o.slots[key], after) then price = 0 break end
            end
            total = total + price
            lines[#lines + 1] = { key = key, price = price }
        end
    end
    return total, lines
end

--- checkout({ store, index, appearance, method, opId, expectedTotal })
Veyl.RegisterCallback('checkout', function(src, citizenid, req)
    if type(req) ~= 'table' then return Veyl.Err('INVALID_INPUT', 'Invalid request') end
    local s, err = storeAt(src, req.store, req.index)
    if not s then return err end
    if not V.str(req.opId, 8, 64, '^[%w%-]+$') then return Veyl.Err('INVALID_INPUT', 'Missing operation id') end
    if not V.oneOf(req.method, AppearanceConfig.PaymentMethods) then return Veyl.Err('INVALID_INPUT', 'Choose cash or bank') end
    local saved = load(citizenid)
    if not saved then return Veyl.Err('NOT_FOUND', 'Create your character first') end
    local submitted = cleanAppearance(req.appearance)
    if not submitted or submitted.model ~= saved.model then return Veyl.Err('INVALID_INPUT', 'Invalid appearance data') end

    -- Start from the saved look and take only what this store may change.
    local next = json.decode(json.encode(saved))
    for _, key in ipairs(Appearance.allowedKeys(req.store)) do
        local cat = Appearance.byKey[key]
        Appearance.setSlot(next, cat, Appearance.getSlot(submitted, cat))
    end
    Appearance.normalise(next)

    local outfits = req.store == 'clothing' and outfitsOf(citizenid, saved.model) or nil
    local total = priceOf(req.store, saved, next, outfits)
    if tonumber(req.expectedTotal) ~= total then
        return Veyl.Err('PRICE_CHANGED', ('The total is now $%d'):format(total), { total = total })
    end

    local opId = ('appearance:%s:%s'):format(citizenid, req.opId)
    if total > 0 then
        local pay = core('DebitOnce', citizenid, req.method, total, s.label, opId)
        if not pay.ok and pay.code ~= 'DUPLICATE_OPERATION' then
            if pay.code == 'TIMEOUT' then return Veyl.Err('PENDING', 'Payment is being verified. Press Pay again to check.') end
            return pay
        end
    end
    if not store(citizenid, next) then
        if total > 0 then core('CreditOnce', citizenid, req.method, total, s.label .. ' refund', opId .. ':refund') end
        return Veyl.Err('DATABASE_ERROR', 'Could not save your new look; you were not charged')
    end
    Veyl.Audit(src, 'appearance_checkout', { store = req.store, total = total })
    return Veyl.Ok({ total = total, balances = balancesOf(src), appearance = next },
        total > 0 and ('Paid $%d'):format(total) or 'Saved')
end, { cooldown = 1500 })

---------------------------------------------------------------------------
-- Outfits (clothing stores). An outfit is a copy of what you have already paid for (your SAVED look).
---------------------------------------------------------------------------
Veyl.RegisterCallback('saveOutfit', function(src, citizenid, storeIndex, name)
    local s, err = storeAt(src, 'clothing', storeIndex)
    if not s then return err end
    if not V.str(name, 1, 32) or name:find('[%c<>]') then return Veyl.Err('INVALID_INPUT', 'Give the outfit a name (max 32 characters)') end
    local saved = load(citizenid)
    if not saved then return Veyl.Err('NOT_FOUND', 'Create your character first') end
    local count = MySQL.scalar.await('SELECT COUNT(*) FROM veyl_outfits WHERE citizenid = ?', { citizenid }) or 0
    if count >= AppearanceConfig.MaxOutfits then
        return Veyl.Err('LIMIT', ('You can keep %d outfits; delete one first'):format(AppearanceConfig.MaxOutfits))
    end
    local slots = {}
    for _, key in ipairs(Appearance.allowedKeys('clothing')) do slots[key] = Appearance.getSlot(saved, Appearance.byKey[key]) end
    MySQL.insert.await('INSERT INTO veyl_outfits (citizenid, model, name, data) VALUES (?, ?, ?, ?)',
        { citizenid, saved.model, name, json.encode(slots) })
    return Veyl.Ok(outfitsOf(citizenid, saved.model), 'Outfit saved')
end, { cooldown = 1500 })

Veyl.RegisterCallback('deleteOutfit', function(_, citizenid, id)
    if not V.int(id, 1) then return Veyl.Err('INVALID_INPUT', 'Unknown outfit') end
    MySQL.update.await('DELETE FROM veyl_outfits WHERE id = ? AND citizenid = ?', { id, citizenid })
    local saved = load(citizenid)
    return Veyl.Ok(saved and outfitsOf(citizenid, saved.model) or {}, 'Outfit deleted')
end, { cooldown = 1000 })

---------------------------------------------------------------------------
-- Outfit exports for other resources (e.g. the veyl_apartments wardrobe). The CALLER checks where the player is and
-- whether they may use that wardrobe; these only act on the given character's own outfits and SAVED appearance.
--   Veyl.Await('veyl_appearance', 'GetOutfits', t, citizenid)            -> Ok({ outfits = { {id,name} }, max })
--   Veyl.Await('veyl_appearance', 'SaveCurrentOutfit', t, citizenid, name) -> Ok(outfits)
--   Veyl.Await('veyl_appearance', 'RenameOutfit', t, citizenid, id, name)  -> Ok(outfits)
--   Veyl.Await('veyl_appearance', 'DeleteOutfit', t, citizenid, id)        -> Ok(outfits)
--   Veyl.Await('veyl_appearance', 'WearOutfit', t, citizenid, id)          -> Ok({ appearance, outfits }) (saved; apply client-side)
---------------------------------------------------------------------------
local function outfitList(citizenid)
    local saved = load(citizenid)
    if not saved then return {} end
    local out = {}
    for _, o in ipairs(outfitsOf(citizenid, saved.model)) do out[#out + 1] = { id = o.id, name = o.name } end
    return out
end
local function validName(name) return V.str(name, 1, 32) and not name:find('[%c<>]') end

Veyl.AsyncExport('GetOutfits', function(citizenid)
    if type(citizenid) ~= 'string' then return Veyl.Err('INVALID_INPUT', 'Invalid') end
    return Veyl.Ok({ outfits = outfitList(citizenid), max = AppearanceConfig.MaxOutfits })
end)

Veyl.AsyncExport('SaveCurrentOutfit', function(citizenid, name)
    if not validName(name) then return Veyl.Err('INVALID_INPUT', 'Give the outfit a name (max 32 characters)') end
    local saved = load(citizenid)
    if not saved then return Veyl.Err('NOT_FOUND', 'Create your character first') end
    local count = MySQL.scalar.await('SELECT COUNT(*) FROM veyl_outfits WHERE citizenid = ?', { citizenid }) or 0
    if count >= AppearanceConfig.MaxOutfits then return Veyl.Err('LIMIT', ('You can keep %d outfits; delete one first'):format(AppearanceConfig.MaxOutfits)) end
    local slots = {}
    for _, key in ipairs(Appearance.allowedKeys('clothing')) do slots[key] = Appearance.getSlot(saved, Appearance.byKey[key]) end
    MySQL.insert.await('INSERT INTO veyl_outfits (citizenid, model, name, data) VALUES (?, ?, ?, ?)', { citizenid, saved.model, name, json.encode(slots) })
    return Veyl.Ok({ outfits = outfitList(citizenid) }, 'Outfit saved')
end)

Veyl.AsyncExport('RenameOutfit', function(citizenid, id, name)
    if not V.int(id, 1) or not validName(name) then return Veyl.Err('INVALID_INPUT', 'Give the outfit a name (max 32 characters)') end
    local n = MySQL.update.await('UPDATE veyl_outfits SET name = ? WHERE id = ? AND citizenid = ?', { name, id, citizenid })
    if n ~= 1 and not MySQL.scalar.await('SELECT 1 FROM veyl_outfits WHERE id = ? AND citizenid = ?', { id, citizenid }) then return Veyl.Err('NOT_FOUND', 'Outfit not found') end
    return Veyl.Ok({ outfits = outfitList(citizenid) }, 'Outfit renamed')
end)

Veyl.AsyncExport('DeleteOutfit', function(citizenid, id)
    if not V.int(id, 1) then return Veyl.Err('INVALID_INPUT', 'Unknown outfit') end
    local n = MySQL.update.await('DELETE FROM veyl_outfits WHERE id = ? AND citizenid = ?', { id, citizenid })
    if n ~= 1 then return Veyl.Err('NOT_FOUND', 'Outfit not found') end
    return Veyl.Ok({ outfits = outfitList(citizenid) }, 'Outfit deleted')
end)

--- Wearing an outfit changes the SAVED look to those clothing pieces (they were already paid for when saved).
Veyl.AsyncExport('WearOutfit', function(citizenid, id)
    if not V.int(id, 1) then return Veyl.Err('INVALID_INPUT', 'Unknown outfit') end
    local saved = load(citizenid)
    if not saved then return Veyl.Err('NOT_FOUND', 'Create your character first') end
    local row = MySQL.single.await('SELECT data FROM veyl_outfits WHERE id = ? AND citizenid = ? AND model = ?', { id, citizenid, saved.model })
    if not row then return Veyl.Err('NOT_FOUND', 'Outfit not found (or made for another character model)') end
    local ok, slots = pcall(json.decode, row.data)
    if not ok or type(slots) ~= 'table' then return Veyl.Err('INVALID_STATE', 'That outfit is damaged') end
    local allowed = {}
    for _, key in ipairs(Appearance.allowedKeys('clothing')) do allowed[key] = true end
    for key, slot in pairs(slots) do
        local cat = Appearance.byKey[key]
        if allowed[key] and cat and (cat.kind == 'component' or cat.kind == 'prop') and type(slot) == 'table' and slot.d ~= nil then
            Appearance.setSlot(saved, cat, slot)
        end
    end
    local next = Appearance.normalise(saved)
    if not store(citizenid, next) then return Veyl.Err('DATABASE_ERROR', 'Could not save your look') end
    return Veyl.Ok({ appearance = next, outfits = outfitList(citizenid) }, 'Outfit changed')
end)

---------------------------------------------------------------------------
-- Worn pieces: hat, glasses and mask are also inventory items (veyl_inventory keeps the slots in step with the saved look).
--   exports.veyl_appearance:GetWorn(citizenid) -> { hat = { d, t }?, glasses = { d, t }?, mask = { d, t }? } or nil (no saved look yet)
--   exports.veyl_appearance:SetWorn(citizenid, key, d, t) -> true | false, reason   (d = -1 takes it off; the change is saved and shown at once)
---------------------------------------------------------------------------
local WORN = { hat = true, glasses = true, mask = true }

exports('GetWorn', function(citizenid)
    if type(citizenid) ~= 'string' then return nil end
    local saved = load(citizenid)
    if not saved then return nil end
    local out = {}
    for key in pairs(WORN) do
        local s = Appearance.getSlot(saved, Appearance.byKey[key])
        -- A prop is worn when d >= 0; the mask is a component where 0 means none.
        local worn = s.d ~= nil and (Appearance.byKey[key].kind == 'prop' and s.d >= 0 or s.d > 0)
        if worn then out[key] = { d = s.d, t = s.t or 0 } end
    end
    return out
end)

exports('SetWorn', function(citizenid, key, d, t)
    if type(citizenid) ~= 'string' or not WORN[key] or not V.int(d, -1, 1000) or not V.int(t or 0, 0, 63) then return false, 'invalid' end
    local cat = Appearance.byKey[key]
    local saved = load(citizenid)
    if not saved then return false, 'no saved look' end
    local none = cat.kind == 'prop' and -1 or 0
    if d < 0 then d = none end
    local before = Appearance.getSlot(saved, cat)
    if before.d == d and (before.t or 0) == (t or 0) then return true end
    Appearance.setSlot(saved, cat, { d = d, t = d == none and 0 or (t or 0) })
    if not store(citizenid, saved) then return false, 'could not save' end
    local src = exports.veyl_core:GetSourceByCitizenId(citizenid)
    if src then TriggerClientEvent('veyl_appearance:worn', src, key, d, d == none and 0 or (t or 0)) end
    return true
end)
