-- veyl_customs server: sessions, server-side pricing, self-service checkout, mechanic work orders, parts, dashboard,
-- saved builds. The client only ever says which options it wants; prices, money, ownership and roles are decided here.

local C, Cat = CustomsConfig, CustomsCatalog
local sessions, byVehicle = {}, {}   -- [src] = session ; [ownedId] = src
local SHOPS = {}
for _, s in ipairs(C.Shops) do SHOPS[s.id] = s end
local settings = {}                  -- [shop] = { price_multiplier, labor_rate } (manager overrides)

---------------------------------------------------------------------------
-- Database
---------------------------------------------------------------------------
Veyl.Startup({ 'veyl_core', 'veyl_vehicles' }, function()
    local ok = Veyl.Migrate({
        { id = '001_customs', sql = {
            [[CREATE TABLE IF NOT EXISTS customs_orders (
                id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                shop VARCHAR(32) NOT NULL,
                owned_id INT UNSIGNED NOT NULL,
                model VARCHAR(64) NOT NULL,
                plate VARCHAR(8) NOT NULL,
                customer_cid VARCHAR(16) NOT NULL,
                customer_name VARCHAR(64) NOT NULL,
                mechanic_cid VARCHAR(16) NULL,
                mechanic_name VARCHAR(64) NULL,
                bay VARCHAR(8) NULL,
                kind ENUM('self','mechanic') NOT NULL DEFAULT 'mechanic',
                status ENUM('draft','sent','approved','in_progress','completed','rejected','expired','cancelled') NOT NULL DEFAULT 'draft',
                version INT UNSIGNED NOT NULL DEFAULT 1,
                note VARCHAR(200) NULL,
                subtotal INT UNSIGNED NOT NULL DEFAULT 0,
                labor INT UNSIGNED NOT NULL DEFAULT 0,
                tax INT UNSIGNED NOT NULL DEFAULT 0,
                total INT UNSIGNED NOT NULL DEFAULT 0,
                paid INT UNSIGNED NOT NULL DEFAULT 0,
                refunded INT UNSIGNED NOT NULL DEFAULT 0,
                labor_rate DECIMAL(5,3) NOT NULL DEFAULT 0,
                tax_rate DECIMAL(5,3) NOT NULL DEFAULT 0,
                expires_at DATETIME NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (id), KEY idx_shop (shop, status), KEY idx_customer (customer_cid), KEY idx_vehicle (owned_id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS customs_order_lines (
                id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                order_id INT UNSIGNED NOT NULL,
                version INT UNSIGNED NOT NULL,
                k VARCHAR(32) NOT NULL,
                cat VARCHAR(16) NOT NULL,
                label VARCHAR(80) NOT NULL,
                value LONGTEXT NOT NULL,
                price INT UNSIGNED NOT NULL,
                part VARCHAR(32) NULL,
                installed TINYINT(1) NOT NULL DEFAULT 0,
                installed_by VARCHAR(16) NULL,
                installed_at TIMESTAMP NULL,
                PRIMARY KEY (id), KEY idx_order (order_id, version)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS customs_stock (
                shop VARCHAR(32) NOT NULL, part VARCHAR(32) NOT NULL,
                qty INT NOT NULL DEFAULT 0, reserved INT NOT NULL DEFAULT 0, reorder_at INT NOT NULL DEFAULT 2,
                PRIMARY KEY (shop, part), CONSTRAINT chk_stock CHECK (qty >= 0 AND reserved >= 0)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS customs_part_orders (
                id INT UNSIGNED NOT NULL AUTO_INCREMENT, shop VARCHAR(32) NOT NULL, part VARCHAR(32) NOT NULL,
                qty INT UNSIGNED NOT NULL, cost INT UNSIGNED NOT NULL, ordered_by VARCHAR(64) NOT NULL,
                status ENUM('ordered','delivered') NOT NULL DEFAULT 'ordered', arrives_at DATETIME NOT NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (id), KEY idx_due (status, arrives_at)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS customs_tx (
                id INT UNSIGNED NOT NULL AUTO_INCREMENT, op_id VARCHAR(90) NOT NULL, kind ENUM('self','order','refund') NOT NULL,
                ref INT UNSIGNED NULL, owned_id INT UNSIGNED NULL, citizenid VARCHAR(16) NOT NULL, amount INT UNSIGNED NOT NULL,
                props_version INT UNSIGNED NULL, props LONGTEXT NULL, shop VARCHAR(32) NOT NULL,
                status ENUM('pending','charged','completed','refunded','failed') NOT NULL DEFAULT 'pending',
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (id), UNIQUE KEY uq_op (op_id), KEY idx_status (status)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS customs_builds (
                id INT UNSIGNED NOT NULL AUTO_INCREMENT, citizenid VARCHAR(16) NOT NULL, name VARCHAR(40) NOT NULL,
                model VARCHAR(64) NOT NULL, data LONGTEXT NOT NULL, share_code VARCHAR(10) NOT NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (id), UNIQUE KEY uq_code (share_code), KEY idx_owner (citizenid)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS customs_shop_settings (
                shop VARCHAR(32) NOT NULL, price_multiplier DECIMAL(4,2) NULL, labor_rate DECIMAL(4,3) NULL, PRIMARY KEY (shop)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
            [[CREATE TABLE IF NOT EXISTS customs_audit (
                id INT UNSIGNED NOT NULL AUTO_INCREMENT, shop VARCHAR(32) NOT NULL, order_id INT UNSIGNED NULL,
                actor VARCHAR(64) NOT NULL, action VARCHAR(32) NOT NULL, detail VARCHAR(200) NULL,
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                PRIMARY KEY (id), KEY idx_shop (shop, id)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        } },
    })
    if not ok then return false end
    for id, s in pairs(SHOPS) do
        if s.stock then
            for part in pairs(C.Parts) do MySQL.insert.await('INSERT IGNORE INTO customs_stock (shop, part, qty) VALUES (?, ?, 5)', { id, part }) end
        end
    end
    for _, r in ipairs(MySQL.query.await('SELECT * FROM customs_shop_settings') or {}) do settings[r.shop] = r end
    Recover()
    return true
end)

local function audit(shop, orderId, actor, action, detail)
    MySQL.insert('INSERT INTO customs_audit (shop, order_id, actor, action, detail) VALUES (?, ?, ?, ?, ?)',
        { shop, orderId, tostring(actor):sub(1, 64), action, detail and tostring(detail):sub(1, 200) or nil })
end

---------------------------------------------------------------------------
-- Pricing (server only)
---------------------------------------------------------------------------
local function rates(shop)
    local s = settings[shop.id] or {}
    return tonumber(s.price_multiplier) or shop.priceMultiplier or 1.0, tonumber(s.labor_rate) or shop.laborRate or 0, shop.taxRate or 0
end

--- Price of one cart line, or nil when the option is not sold here.
local function priceOf(shop, key, value)
    local o = Cat.ByKey[key]
    if not o or not shop.categories[o.cat] then return nil end
    local P, mult = C.Prices, rates(shop)
    local p
    if o.kind == 'mod' then
        if value == -1 then p = P.stock
        elseif o.cat == 'performance' then
            local cap = C.Performance[o.slot]
            local list = P.perf[o.slot]
            if not list or (cap and value > cap) or not list[value + 1] then return nil end
            p = list[value + 1]
        else
            local c = P.cosmetic
            p = math.min(c.max, (P.slotBase[o.slot] or c.base) + value * c.perIndex)
        end
    elseif key == 'toggle:18' then p = value and P.turbo or P.stock
    elseif key == 'toggle:20' then p = value and P.tyreSmokeToggle or P.stock
    elseif key == 'toggle:22' then p = value and P.xenon or P.stock
    elseif key == 'customTyres' then p = value and P.customTyres or P.stock
    elseif key == 'paint:primary' then p = P.paintPrimary + (value.rgb and P.paintCustomExtra or 0)
    elseif key == 'paint:secondary' then p = P.paintSecondary + (value.rgb and P.paintCustomExtra or 0)
    elseif key == 'neon' then p = (value.l or value.r or value.f or value.b) and P.neon or P.stock
    elseif o.kind == 'extra' then p = P.extra
    else p = P[key] end
    if type(p) ~= 'number' then return nil end
    return math.floor(p * mult + 0.5)
end

local function labelOf(key, value)
    local o = Cat.ByKey[key]
    local v
    if o.kind == 'mod' then
        if value == -1 then v = 'Stock'
        elseif o.cat == 'performance' then v = ('Level %d'):format(value + 1)
        else v = ('Option %d'):format(value + 1) end
    elseif o.kind == 'toggle' or o.kind == 'extra' then v = value and 'On' or 'Off'
    elseif o.kind == 'paint' then v = value.rgb and ('#%02X%02X%02X'):format(value.rgb.r, value.rgb.g, value.rgb.b) or ('Colour %d'):format(value.index)
    elseif o.kind == 'rgb' then v = ('#%02X%02X%02X'):format(value.r, value.g, value.b)
    elseif key == 'wheelType' then v = Cat.WheelTypes[value] or tostring(value)
    elseif key == 'windowTint' then v = Cat.WindowTints[value] or tostring(value)
    elseif key == 'plateIndex' then v = Cat.PlateStyles[value] or tostring(value)
    elseif key == 'xenonColor' then v = Cat.XenonColors[value] or tostring(value)
    elseif key == 'neon' then
        local on = {}
        for side, name in pairs({ l = 'L', r = 'R', f = 'F', b = 'B' }) do if value[side] then on[#on + 1] = name end end
        table.sort(on)
        v = #on > 0 and table.concat(on, '') or 'Off'
    else v = tostring(value) end
    return ('%s: %s'):format(o.label, v)
end

--- Builds priced lines from a client selection against the saved looks. Unchanged keys are dropped (no charge).
local function buildLines(shop, selections, saved)
    if type(selections) ~= 'table' then return nil, 'INVALID_INPUT' end
    local lines, n = {}, 0
    for key, raw in pairs(selections) do
        n = n + 1
        if n > 80 then return nil, 'INVALID_INPUT' end
        local o = Cat.ByKey[key]
        if not o then return nil, 'INVALID_INPUT' end
        local v = Cat.Clean(key, raw)
        if v == nil then return nil, 'INVALID_INPUT' end
        local orig = Cat.FromProps(saved, key)
        if orig == nil or not Cat.Same(orig, v) then
            local price = priceOf(shop, key, v)
            if not price then return nil, 'NOT_SOLD' end
            lines[#lines + 1] = { key = key, cat = o.cat, label = labelOf(key, v), value = v, price = price, part = (v ~= -1 and v ~= false) and o.part or nil }
        end
    end
    table.sort(lines, function(a, b) return a.key < b.key end)
    return lines
end

local function totals(shop, lines)
    local _, laborRate, taxRate = rates(shop)
    local sub = 0
    for _, l in ipairs(lines) do sub = sub + l.price end
    local labor = math.floor(sub * laborRate + 0.5)
    local tax = math.floor((sub + labor) * taxRate + 0.5)
    return sub, labor, tax, sub + labor + tax, laborRate, taxRate
end

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function entityFromNet(netId)
    local e = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if not e or e == 0 or not DoesEntityExist(e) or GetEntityType(e) ~= 2 then return nil end
    return e
end
local function dist(src, pos) local pc = Veyl.GetPlayerCoords(src) return pc and #(pc - vector3(pos.x, pos.y, pos.z)) or math.huge end

--- Live entity of an owned vehicle that is out (or nil).
local function liveEntity(ownedId, netIdHint)
    local e = netIdHint and entityFromNet(netIdHint)
    if e and Bridge.OwnedIdFromEntity(e) == ownedId then return e end
    for _, v in ipairs(GetAllVehicles()) do if Bridge.OwnedIdFromEntity(v) == ownedId then return v end end
end

--- Push the saved looks onto the live entity (its network owner applies them).
local function pushProps(ownedId, props, netIdHint)
    local e = liveEntity(ownedId, netIdHint)
    if not e then return end
    local owner = NetworkGetEntityOwner(e)
    TriggerClientEvent('veyl_customs:applyProps', owner and owner > 0 and owner or -1, NetworkGetNetworkIdFromEntity(e), props)
end

local function shopStaffOnDuty(shop)
    for _, s in ipairs(GetPlayers()) do
        local st = Bridge.Staff(tonumber(s), shop)
        if st and st.onduty then return true end
    end
    return false
end

---------------------------------------------------------------------------
-- Sessions (one per player, one per vehicle)
---------------------------------------------------------------------------
local function closeSession(src, reason)
    local s = sessions[src]
    if not s then return end
    sessions[src] = nil
    if byVehicle[s.ownedId] == src then byVehicle[s.ownedId] = nil end
    if reason and GetPlayerName(src) then TriggerClientEvent('veyl_customs:sessionClosed', src, reason) end
end

local function getSession(src, id)
    local s = sessions[src]
    if not s or s.id ~= id then return nil end
    if os.time() > s.expires then closeSession(src, 'expired') return nil end
    s.expires = os.time() + C.SessionMinutes * 60
    return s
end

--- start(shopId, netId, mode = 'self'|'quote', orderId?)
Veyl.RegisterCallback('start', function(src, citizenid, shopId, netId, mode, orderId)
    local shop = SHOPS[shopId]
    if not shop then return Veyl.Err('NOT_FOUND', 'Unknown shop') end
    if dist(src, shop.coords) > shop.radius then return Veyl.Err('TOO_FAR', 'Bring the vehicle into the shop') end
    if sessions[src] then closeSession(src) end
    local entity = entityFromNet(netId)
    if not entity or #(GetEntityCoords(entity) - shop.coords) > shop.radius then return Veyl.Err('NOT_FOUND', 'The vehicle must be in the shop') end
    local ownedId = Bridge.OwnedIdFromEntity(entity)
    if not ownedId then return Veyl.Err('NO_PERMISSION', 'Only registered (owned) vehicles can be customised') end
    if byVehicle[ownedId] and byVehicle[ownedId] ~= src and sessions[byVehicle[ownedId]] then return Veyl.Err('BUSY', 'Someone is already working on this vehicle') end
    local info = Bridge.GetOwnedProps(ownedId)
    if not info.ok then return info end
    if info.data.state ~= 'out' then return Veyl.Err('INVALID_STATE', 'The vehicle is not out') end
    local order
    if mode == 'quote' then
        local st = Bridge.Staff(src, shop)
        if shop.mode == 'self' or not st or not st.onduty then return Veyl.Err('NO_PERMISSION', 'Clock in at this shop to write quotes') end
        if orderId then
            order = MySQL.single.await("SELECT * FROM customs_orders WHERE id = ? AND shop = ? AND status IN ('draft','sent')", { tonumber(orderId) or 0, shop.id })
            if not order or order.owned_id ~= ownedId then return Veyl.Err('NOT_FOUND', 'That order is not open for this vehicle') end
        end
    else
        mode = 'self'
        if info.data.citizenid ~= citizenid then return Veyl.Err('NO_PERMISSION', 'Only the owner can customise this vehicle') end
        if shop.mode == 'mechanic' and not (shop.selfFallback and not shopStaffOnDuty(shop)) then
            return Veyl.Err('NO_PERMISSION', 'Ask a mechanic for a quote here')
        end
    end
    local s = { id = Veyl.NewId(), shop = shop.id, ownedId = ownedId, netId = tonumber(netId), model = info.data.model, plate = info.data.plate,
        owner = info.data.citizenid, mode = mode, orderId = order and order.id or nil, version = info.data.version,
        saved = info.data.props or {}, quoteSeq = 0, expires = os.time() + C.SessionMinutes * 60 }
    sessions[src], byVehicle[ownedId] = s, src
    local preload
    if order then
        preload = {}
        for _, l in ipairs(MySQL.query.await('SELECT k, value FROM customs_order_lines WHERE order_id = ? AND version = ?', { order.id, order.version }) or {}) do
            local ok, v = pcall(json.decode, l.value)
            if ok then preload[l.k] = v end
        end
    end
    local mult, laborRate, taxRate = rates(shop)
    return Veyl.Ok({ session = s.id, mode = mode, model = s.model, plate = s.plate, label = info.data.label, saved = s.saved, preload = preload,
        orderId = s.orderId, shop = { id = shop.id, label = shop.label, sub = shop.sub, categories = shop.categories, preview = shop.preview,
        laborRate = laborRate, taxRate = taxRate, multiplier = mult }, prices = C.Prices, performance = C.Performance })
end, { cooldown = 1500 })

Veyl.RegisterCallback('close', function(src, _, id)
    if sessions[src] and sessions[src].id == id then closeSession(src) end
    return Veyl.Ok()
end, { cooldown = 100 })

--- Price preview: the server prices the whole cart (the client shows these numbers, never its own).
Veyl.RegisterCallback('price', function(src, _, id, selections)
    local s = getSession(src, id)
    if not s then return Veyl.Err('INVALID_STATE', 'Session ended') end
    local shop = SHOPS[s.shop]
    local lines, code = buildLines(shop, selections, s.saved)
    if not lines then return Veyl.Err(code, code == 'NOT_SOLD' and 'One of these options is not sold here' or 'Invalid selection') end
    local sub, labor, tax, total = totals(shop, lines)
    local out = {}
    for i, l in ipairs(lines) do out[i] = { key = l.key, label = l.label, price = l.price } end
    return Veyl.Ok({ lines = out, subtotal = sub, labor = labor, tax = tax, total = total })
end, { cooldown = 150 })

--- Prices of individual option values for the menu rows (what each row would cost on its own).
Veyl.RegisterCallback('rowPrices', function(src, _, id, items)
    local s = getSession(src, id)
    if not s or type(items) ~= 'table' or #items > 200 then return Veyl.Err('INVALID_INPUT', 'Bad request') end
    local shop = SHOPS[s.shop]
    local out = {}
    for i, it in ipairs(items) do
        local v = type(it) == 'table' and Cat.Clean(it.key, it.value)
        out[i] = v ~= nil and priceOf(shop, it.key, v) or nil
        if out[i] == nil then out[i] = -1 end
    end
    return Veyl.Ok(out)
end, { cooldown = 100 })

---------------------------------------------------------------------------
-- Self-service: quote -> checkout (durable workflow: pending -> charged -> completed | refunded)
---------------------------------------------------------------------------
Veyl.RegisterCallback('quote', function(src, _, id, selections)
    local s = getSession(src, id)
    if not s or s.mode ~= 'self' then return Veyl.Err('INVALID_STATE', 'Session ended') end
    local shop = SHOPS[s.shop]
    local lines, code = buildLines(shop, selections, s.saved)
    if not lines then return Veyl.Err(code, 'Invalid selection') end
    if #lines == 0 then return Veyl.Err('INVALID_INPUT', 'Nothing to buy: the build matches your vehicle') end
    local sub, labor, tax, total = totals(shop, lines)
    s.quoteSeq = s.quoteSeq + 1
    s.quote = { version = s.quoteSeq, lines = lines, subtotal = sub, labor = labor, tax = tax, total = total, expires = os.time() + C.QuoteMinutes * 60 }
    local out = {}
    for i, l in ipairs(lines) do out[i] = { key = l.key, label = l.label, price = l.price } end
    return Veyl.Ok({ version = s.quoteSeq, lines = out, subtotal = sub, labor = labor, tax = tax, total = total, expiresIn = C.QuoteMinutes * 60, methods = C.PaymentMethods })
end, { cooldown = 800 })

Veyl.RegisterCallback('checkout', function(src, citizenid, id, quoteVersion, method)
    local s = getSession(src, id)
    if not s or s.mode ~= 'self' then return Veyl.Err('INVALID_STATE', 'Session ended') end
    local q = s.quote
    if not q or q.version ~= tonumber(quoteVersion) then return Veyl.Err('STALE', 'The quote changed. Review it again.') end
    if os.time() > q.expires then s.quote = nil return Veyl.Err('EXPIRED', 'The quote expired. Review it again.') end
    if s.paying then return Veyl.Err('BUSY', 'Payment in progress') end
    method = method == 'cash' and 'cash' or 'bank'
    local shop = SHOPS[s.shop]
    local entity = liveEntity(s.ownedId, s.netId)
    if not entity or #(GetEntityCoords(entity) - shop.coords) > shop.radius then return Veyl.Err('NOT_FOUND', 'The vehicle left the shop') end
    s.paying = true
    -- Final looks = saved looks + the purchased lines only (nothing else from the client is persisted).
    local final = json.decode(json.encode(s.saved or {}))
    for _, l in ipairs(q.lines) do Cat.ApplyToProps(final, l.key, l.value) end
    local opId = ('customs:self:%s:%d'):format(s.id, q.version)
    local txId = MySQL.insert.await([[INSERT IGNORE INTO customs_tx (op_id, kind, owned_id, citizenid, amount, props_version, props, shop) VALUES (?, 'self', ?, ?, ?, ?, ?, ?)]],
        { opId, s.ownedId, citizenid, q.total, s.version, json.encode(final), shop.id })
    if not txId or txId == 0 then s.paying = false return Veyl.Err('DUPLICATE_OPERATION', 'Already paid') end
    local pay = Bridge.Debit(citizenid, method, q.total, ('%s: vehicle customisation'):format(shop.label), opId)
    if not pay.ok and pay.code ~= 'DUPLICATE_OPERATION' then
        MySQL.update.await("UPDATE customs_tx SET status = 'failed' WHERE id = ?", { txId })
        s.paying = false
        return Veyl.Err(pay.code or 'INSUFFICIENT_FUNDS', ('You need $%d (%s)'):format(q.total, method))
    end
    MySQL.update.await("UPDATE customs_tx SET status = 'charged' WHERE id = ?", { txId })
    local saved = Bridge.ApplyOwnedProps(s.ownedId, final, s.version)
    if not saved.ok then
        -- Could not persist (e.g. the vehicle was changed elsewhere): give the money back.
        local r = Bridge.Credit(citizenid, method, q.total, ('%s: refund'):format(shop.label), opId .. ':refund')
        MySQL.update.await("UPDATE customs_tx SET status = ? WHERE id = ?", { (r.ok or r.code == 'DUPLICATE_OPERATION') and 'refunded' or 'charged', txId })
        s.paying = false
        return Veyl.Err(saved.code or 'STALE', 'The vehicle changed while you were shopping. You were refunded.')
    end
    MySQL.update.await("UPDATE customs_tx SET status = 'completed' WHERE id = ?", { txId })
    s.version, s.saved, s.quote, s.paying = saved.data.version, final, nil, false
    -- History: a completed self-service order with its lines.
    local pd = Bridge.Player(src)
    local orderId = MySQL.insert.await([[INSERT INTO customs_orders (shop, owned_id, model, plate, customer_cid, customer_name, kind, status, subtotal, labor, tax, total, paid)
        VALUES (?, ?, ?, ?, ?, ?, 'self', 'completed', ?, ?, ?, ?, ?)]], { shop.id, s.ownedId, s.model, s.plate, citizenid, Bridge.Name(pd), q.subtotal, q.labor, q.tax, q.total, q.total })
    for _, l in ipairs(q.lines) do
        MySQL.insert.await('INSERT INTO customs_order_lines (order_id, version, k, cat, label, value, price, installed) VALUES (?, 1, ?, ?, ?, ?, ?, 1)',
            { orderId, l.key, l.cat, l.label, json.encode(l.value), l.price })
    end
    MySQL.update.await('UPDATE customs_tx SET ref = ? WHERE id = ?', { orderId, txId })
    Bridge.BusinessCredit(shop.business, q.total, ('Self-service order #%d'):format(orderId), Bridge.Name(pd))
    audit(shop.id, orderId, Bridge.Name(pd), 'self_checkout', ('$%d, %d items'):format(q.total, #q.lines))
    pushProps(s.ownedId, final, s.netId)
    return Veyl.Ok({ props = final, orderId = orderId, total = q.total }, ('Paid $%d. Your vehicle is ready.'):format(q.total))
end, { cooldown = 2000 })

---------------------------------------------------------------------------
-- Mechanic work orders
---------------------------------------------------------------------------
-- draft -> sent -> approved -> in_progress -> completed ; sent -> rejected | expired ; draft/sent/approved/in_progress -> cancelled
local function order(id) return MySQL.single.await('SELECT * FROM customs_orders WHERE id = ?', { tonumber(id) or 0 }) end
local function lines(o, version)
    return MySQL.query.await('SELECT id, k, cat, label, value, price, part, installed FROM customs_order_lines WHERE order_id = ? AND version = ? ORDER BY id', { o.id, version or o.version }) or {}
end
local function setStatus(o, from, to, extra)
    local sql, args = 'UPDATE customs_orders SET status = ?', { to }
    -- false = set the column to NULL
    for k, v in pairs(extra or {}) do
        if v == false then sql = sql .. (', %s = NULL'):format(k) else sql = sql .. (', %s = ?'):format(k) args[#args + 1] = v end
    end
    sql = sql .. ' WHERE id = ? AND status = ?'
    args[#args + 1] = o.id
    args[#args + 1] = from
    return MySQL.update.await(sql, args) == 1
end

--- Staff saves the cart of a quote session as an order (new draft, or a new version of a draft/sent order).
Veyl.RegisterCallback('saveOrder', function(src, citizenid, id, selections, note)
    local s = getSession(src, id)
    if not s or s.mode ~= 'quote' then return Veyl.Err('INVALID_STATE', 'Session ended') end
    local shop = SHOPS[s.shop]
    local st = Bridge.Staff(src, shop)
    if not st or not st.onduty then return Veyl.Err('NO_PERMISSION', 'Clock in first') end
    local ls, code = buildLines(shop, selections, s.saved)
    if not ls then return Veyl.Err(code, 'Invalid selection') end
    if #ls == 0 then return Veyl.Err('INVALID_INPUT', 'Add at least one change') end
    local sub, labor, tax, total, laborRate, taxRate = totals(shop, ls)
    local pd = Bridge.Player(src)
    local orderId, version
    note = type(note) == 'string' and note:gsub('%c', ''):sub(1, 200) or nil
    if s.orderId then
        local o = order(s.orderId)
        if not o or (o.status ~= 'draft' and o.status ~= 'sent') then return Veyl.Err('INVALID_STATE', 'This order can no longer be edited') end
        version = o.version + 1
        -- Editing a sent quote makes a new version that has to be sent and approved again.
        if MySQL.update.await([[UPDATE customs_orders SET version = ?, status = 'draft', subtotal = ?, labor = ?, tax = ?, total = ?, labor_rate = ?, tax_rate = ?,
            note = COALESCE(?, note), mechanic_cid = COALESCE(mechanic_cid, ?), mechanic_name = COALESCE(mechanic_name, ?), expires_at = NULL
            WHERE id = ? AND version = ? AND status IN ('draft','sent')]], { version, sub, labor, tax, total, laborRate, taxRate, note, citizenid, Bridge.Name(pd), o.id, o.version }) ~= 1 then
            return Veyl.Err('STALE', 'The order changed. Open it again.')
        end
        orderId = o.id
    else
        local owner = MySQL.single.await('SELECT charinfo FROM veyl_players WHERE citizenid = ?', { s.owner })
        local okc, ci = pcall(json.decode, owner and owner.charinfo or '{}')
        ci = okc and type(ci) == 'table' and ci or {}
        version = 1
        orderId = MySQL.insert.await([[INSERT INTO customs_orders (shop, owned_id, model, plate, customer_cid, customer_name, mechanic_cid, mechanic_name, status, version, note,
            subtotal, labor, tax, total, labor_rate, tax_rate) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'draft', 1, ?, ?, ?, ?, ?, ?, ?)]],
            { shop.id, s.ownedId, s.model, s.plate, s.owner, ('%s %s'):format(ci.firstname or '?', ci.lastname or ''), citizenid, Bridge.Name(pd), note,
              sub, labor, tax, total, laborRate, taxRate })
        s.orderId = orderId
    end
    for _, l in ipairs(ls) do
        MySQL.insert.await('INSERT INTO customs_order_lines (order_id, version, k, cat, label, value, price, part) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
            { orderId, version, l.key, l.cat, l.label, json.encode(l.value), l.price, shop.stock and l.part or nil })
    end
    audit(shop.id, orderId, Bridge.Name(pd), 'quote_saved', ('v%d $%d'):format(version, total))
    return Veyl.Ok({ orderId = orderId, version = version, total = total }, ('Quote #%d saved (v%d). Send it from the dashboard.'):format(orderId, version))
end, { cooldown = 1500 })

--- Customer asks for service at the desk (creates an unassigned draft with their note).
Veyl.RegisterCallback('request', function(src, citizenid, shopId, netId, note)
    local shop = SHOPS[shopId]
    if not shop or shop.mode == 'self' or not shop.desk or dist(src, shop.desk) > 4.0 then return Veyl.Err('TOO_FAR', 'Ask at the desk') end
    local entity = entityFromNet(netId)
    local ownedId = entity and Bridge.OwnedIdFromEntity(entity)
    if not ownedId or #(GetEntityCoords(entity) - shop.coords) > shop.radius then return Veyl.Err('NOT_FOUND', 'Bring your vehicle into the shop') end
    local info = Bridge.GetOwnedProps(ownedId)
    if not info.ok or info.data.citizenid ~= citizenid then return Veyl.Err('NO_PERMISSION', 'Only the owner can request work') end
    if MySQL.scalar.await("SELECT 1 FROM customs_orders WHERE owned_id = ? AND status IN ('draft','sent','approved','in_progress')", { ownedId }) then
        return Veyl.Err('INVALID_STATE', 'This vehicle already has an open order')
    end
    note = type(note) == 'string' and note:gsub('%c', ''):sub(1, 200) or ''
    local pd = Bridge.Player(src)
    local id = MySQL.insert.await([[INSERT INTO customs_orders (shop, owned_id, model, plate, customer_cid, customer_name, status, note) VALUES (?, ?, ?, ?, ?, ?, 'draft', ?)]],
        { shop.id, ownedId, info.data.model, info.data.plate, citizenid, Bridge.Name(pd), note })
    audit(shop.id, id, Bridge.Name(pd), 'request', note)
    for _, p in ipairs(GetPlayers()) do
        local st = Bridge.Staff(tonumber(p), shop)
        if st and st.onduty then Bridge.Notify(tonumber(p), ('New customer request #%d: %s'):format(id, note ~= '' and note or info.data.plate), 'info') end
    end
    return Veyl.Ok({ orderId = id }, 'Request sent. A mechanic will prepare a quote.')
end, { cooldown = 5000 })

local function lineViews(o, version)
    local out = {}
    for i, l in ipairs(lines(o, version)) do out[i] = { id = l.id, key = l.k, cat = l.cat, label = l.label, price = l.price, part = l.part, installed = l.installed == 1 } end
    return out
end

local function orderView(o)
    return { id = o.id, shop = o.shop, model = o.model, plate = o.plate, customer = o.customer_name, customerCid = o.customer_cid, mechanic = o.mechanic_name,
        mechanicCid = o.mechanic_cid, bay = o.bay, kind = o.kind, status = o.status, version = o.version, note = o.note,
        subtotal = o.subtotal, labor = o.labor, tax = o.tax, total = o.total, paid = o.paid, refunded = o.refunded, lines = lineViews(o) }
end

local function freeBay(shop)
    local used = {}
    for _, r in ipairs(MySQL.query.await("SELECT bay FROM customs_orders WHERE shop = ? AND bay IS NOT NULL AND status IN ('approved','in_progress')", { shop.id }) or {}) do used[r.bay] = true end
    for _, b in ipairs(shop.bays or {}) do if not used[b.id] then return b.id end end
end

local function reserveParts(shop, o, ls)
    if not shop.stock then return true end
    local need = {}
    for _, l in ipairs(ls) do if l.part and l.installed ~= 1 then need[l.part] = (need[l.part] or 0) + 1 end end
    local done = {}
    for part, n in pairs(need) do
        if MySQL.update.await('UPDATE customs_stock SET reserved = reserved + ? WHERE shop = ? AND part = ? AND qty - reserved >= ?', { n, shop.id, part, n }) ~= 1 then
            for p2, n2 in pairs(done) do MySQL.update.await('UPDATE customs_stock SET reserved = GREATEST(reserved - ?, 0) WHERE shop = ? AND part = ?', { n2, shop.id, p2 }) end
            return false, part
        end
        done[part] = n
    end
    return true
end

local function releaseParts(shop, o)
    if not shop.stock then return end
    for _, l in ipairs(lines(o)) do
        if l.part and l.installed ~= 1 then MySQL.update.await('UPDATE customs_stock SET reserved = GREATEST(reserved - 1, 0) WHERE shop = ? AND part = ?', { shop.id, l.part }) end
    end
end

--- Refund policy: the customer gets back the price of every line that was not installed, plus its share of labour and tax.
local function refundUninstalled(o, reason)
    if o.paid <= 0 then return 0 end
    local installedSub = 0
    for _, l in ipairs(lines(o)) do if l.installed == 1 then installedSub = installedSub + l.price end end
    local kept = math.floor(installedSub * (1 + tonumber(o.labor_rate)) * (1 + tonumber(o.tax_rate)) + 0.5)
    local refund = math.max(0, o.paid - o.refunded - kept)
    if refund > 0 then
        local op = ('customs:order:%d:refund'):format(o.id)
        local r = Bridge.Credit(o.customer_cid, 'bank', refund, ('Customs order #%d refund (%s)'):format(o.id, reason), op)
        if r.ok or r.code == 'DUPLICATE_OPERATION' then
            MySQL.update.await('UPDATE customs_orders SET refunded = refunded + ? WHERE id = ?', { refund, o.id })
            MySQL.insert.await("INSERT IGNORE INTO customs_tx (op_id, kind, ref, owned_id, citizenid, amount, shop, status) VALUES (?, 'refund', ?, ?, ?, ?, ?, 'completed')",
                { op, o.id, o.owned_id, o.customer_cid, refund, o.shop })
        end
    end
    return refund, kept
end

--- Customer approves the exact version they were shown (and pays, with PaymentTiming = 'on_approval').
Veyl.RegisterCallback('approve', function(src, citizenid, orderId, version, method)
    local o = order(orderId)
    if not o or o.customer_cid ~= citizenid then return Veyl.Err('NOT_FOUND', 'Not your order') end
    if o.status ~= 'sent' or o.version ~= tonumber(version) then return Veyl.Err('STALE', 'This quote changed or is no longer open') end
    if o.expires_at and MySQL.scalar.await('SELECT expires_at < NOW() FROM customs_orders WHERE id = ?', { o.id }) == 1 then
        setStatus(o, 'sent', 'expired')
        return Veyl.Err('EXPIRED', 'This quote expired')
    end
    local shop = SHOPS[o.shop]
    local ls = lines(o)
    local okParts, missing = reserveParts(shop, o, ls)
    if not okParts then return Veyl.Err('NO_ITEM', ('The shop is out of %s. Ask the mechanic.'):format((C.Parts[missing] or {}).label or missing)) end
    method = method == 'cash' and 'cash' or 'bank'
    local op = ('customs:order:%d:v%d'):format(o.id, o.version)
    MySQL.insert.await("INSERT IGNORE INTO customs_tx (op_id, kind, ref, owned_id, citizenid, amount, shop) VALUES (?, 'order', ?, ?, ?, ?, ?)",
        { op, o.id, o.owned_id, citizenid, o.total, o.shop })
    local pay = Bridge.Debit(citizenid, method, o.total, ('%s order #%d'):format(shop.label, o.id), op)
    if not pay.ok and pay.code ~= 'DUPLICATE_OPERATION' then
        releaseParts(shop, o)
        MySQL.update.await("UPDATE customs_tx SET status = 'failed' WHERE op_id = ?", { op })
        return Veyl.Err(pay.code or 'INSUFFICIENT_FUNDS', ('You need $%d (%s)'):format(o.total, method))
    end
    MySQL.update.await("UPDATE customs_tx SET status = 'charged' WHERE op_id = ?", { op })
    if not setStatus(o, 'sent', 'approved', { paid = o.total, bay = freeBay(shop) or false }) then
        -- Lost a race (edited / cancelled meanwhile): refund and release.
        Bridge.Credit(citizenid, method, o.total, 'Customs order refund', op .. ':refund')
        MySQL.update.await("UPDATE customs_tx SET status = 'refunded' WHERE op_id = ?", { op })
        releaseParts(shop, o)
        return Veyl.Err('STALE', 'The quote changed. You were refunded.')
    end
    MySQL.update.await("UPDATE customs_tx SET status = 'completed' WHERE op_id = ?", { op })
    audit(o.shop, o.id, Bridge.Name(Bridge.Player(src)), 'approved', ('v%d $%d'):format(o.version, o.total))
    local mech = o.mechanic_cid and Bridge.SrcByCitizen(o.mechanic_cid)
    if mech then Bridge.Notify(mech, ('Order #%d approved and paid. Start the work.'):format(o.id), 'success') end
    return Veyl.Ok(nil, ('Approved and paid $%d. Unfinished work is refunded if the order is cancelled.'):format(o.total))
end, { cooldown = 2000 })

Veyl.RegisterCallback('reject', function(src, citizenid, orderId, version)
    local o = order(orderId)
    if not o or o.customer_cid ~= citizenid or o.status ~= 'sent' or o.version ~= tonumber(version) then return Veyl.Err('STALE', 'This quote is no longer open') end
    setStatus(o, 'sent', 'rejected')
    audit(o.shop, o.id, Bridge.Name(Bridge.Player(src)), 'rejected', ('v%d'):format(o.version))
    local mech = o.mechanic_cid and Bridge.SrcByCitizen(o.mechanic_cid)
    if mech then Bridge.Notify(mech, ('Order #%d was rejected by the customer.'):format(o.id), 'warning') end
    return Veyl.Ok(nil, 'Quote rejected')
end, { cooldown = 1000 })

--- The customer's open quotes waiting for approval (shown in their approval screen).
Veyl.RegisterCallback('myQuotes', function(src, citizenid)
    local out = {}
    for _, o in ipairs(MySQL.query.await("SELECT * FROM customs_orders WHERE customer_cid = ? AND status = 'sent' ORDER BY id DESC LIMIT 5", { citizenid }) or {}) do
        local v = orderView(o)
        v.shopLabel = SHOPS[o.shop] and SHOPS[o.shop].label or o.shop
        out[#out + 1] = v
    end
    return Veyl.Ok({ quotes = out, methods = C.PaymentMethods })
end, { cooldown = 500 })

--- Staff actions on an order: send, cancel, assign, start, setBay.
Veyl.RegisterCallback('orderAction', function(src, citizenid, orderId, action, arg)
    local o = order(orderId)
    if not o then return Veyl.Err('NOT_FOUND', 'Unknown order') end
    local shop = SHOPS[o.shop]
    local st = Bridge.Staff(src, shop)
    if not st or not st.onduty then return Veyl.Err('NO_PERMISSION', 'Clock in at this shop') end
    local me = Bridge.Name(Bridge.Player(src))
    local mine = o.mechanic_cid == citizenid
    if action == 'assign' then
        local target = (st.manager and type(arg) == 'string' and arg ~= '') and arg or citizenid
        if not (o.status == 'draft' or o.status == 'sent' or o.status == 'approved' or o.status == 'in_progress') then return Veyl.Err('INVALID_STATE', 'Closed order') end
        if not st.manager and o.mechanic_cid and not mine then return Veyl.Err('NO_PERMISSION', 'Already assigned') end
        local tsrc = Bridge.SrcByCitizen(target)
        local tname = tsrc and Bridge.Name(Bridge.Player(tsrc)) or me
        MySQL.update.await('UPDATE customs_orders SET mechanic_cid = ?, mechanic_name = ? WHERE id = ?', { target, tname, o.id })
        audit(o.shop, o.id, me, 'assigned', tname)
        return Veyl.Ok(nil, ('Assigned to %s'):format(tname))
    end
    if not mine and not st.manager then return Veyl.Err('NO_PERMISSION', 'Only the assigned mechanic or a manager can do that') end
    if action == 'send' then
        if o.status ~= 'draft' or o.total <= 0 then return Veyl.Err('INVALID_STATE', 'Only a draft with items can be sent') end
        if not setStatus(o, 'draft', 'sent', { expires_at = os.date('%Y-%m-%d %H:%M:%S', os.time() + C.SentQuoteHours * 3600) }) then return Veyl.Err('STALE', 'Order changed') end
        audit(o.shop, o.id, me, 'sent', ('v%d $%d'):format(o.version, o.total))
        local cs = Bridge.SrcByCitizen(o.customer_cid)
        if cs then TriggerClientEvent('veyl_customs:quoteReceived', cs, o.id) end
        return Veyl.Ok(nil, cs and 'Quote sent to the customer' or 'Quote sent. The customer will see it next time they ask (/customsquote).')
    elseif action == 'start' then
        if o.status ~= 'approved' then return Veyl.Err('INVALID_STATE', 'The customer has not approved it yet') end
        local bay = o.bay or freeBay(shop)
        if #(shop.bays or {}) > 0 and not bay then return Veyl.Err('BUSY', 'No free service bay') end
        if not setStatus(o, 'approved', 'in_progress', { bay = bay, mechanic_cid = o.mechanic_cid or citizenid, mechanic_name = o.mechanic_name or me }) then return Veyl.Err('STALE', 'Order changed') end
        audit(o.shop, o.id, me, 'started', bay and ('bay ' .. bay) or nil)
        return Veyl.Ok(nil, bay and ('Work started in bay %s. Install each item at the vehicle.'):format(bay) or 'Work started. Install each item at the vehicle.')
    elseif action == 'cancel' then
        if o.status == 'completed' or o.status == 'cancelled' or o.status == 'rejected' or o.status == 'expired' then return Veyl.Err('INVALID_STATE', 'Already closed') end
        if not setStatus(o, o.status, 'cancelled', { bay = false }) then return Veyl.Err('STALE', 'Order changed') end
        releaseParts(shop, o)
        local refund, kept = refundUninstalled(o, 'cancelled')
        if kept > 0 then Bridge.BusinessCredit(shop.business, kept, ('Order #%d (partly done)'):format(o.id), me) end
        audit(o.shop, o.id, me, 'cancelled', ('refund $%d, kept $%d'):format(refund, kept))
        local cs = Bridge.SrcByCitizen(o.customer_cid)
        if cs and refund > 0 then Bridge.Notify(cs, ('Order #%d was cancelled. $%d refunded to your bank.'):format(o.id, refund), 'info') end
        return Veyl.Ok(nil, refund > 0 and ('Cancelled. $%d refunded for unfinished work.'):format(refund) or 'Cancelled')
    end
    return Veyl.Err('INVALID_INPUT', 'Unknown action')
end, { cooldown = 800 })

--- Install one approved line (after the client's short work interaction). The server checks everything again.
local installing = {}
Veyl.RegisterCallback('installStart', function(src, citizenid, orderId, lineId)
    local o = order(orderId)
    if not o or o.status ~= 'in_progress' then return Veyl.Err('INVALID_STATE', 'Start the order first') end
    local shop = SHOPS[o.shop]
    local st = Bridge.Staff(src, shop)
    if not st or not st.onduty then return Veyl.Err('NO_PERMISSION', 'Clock in at this shop') end
    if o.mechanic_cid ~= citizenid and not st.manager then return Veyl.Err('NO_PERMISSION', 'This order is assigned to someone else') end
    local line = MySQL.single.await('SELECT * FROM customs_order_lines WHERE id = ? AND order_id = ? AND version = ? AND installed = 0', { tonumber(lineId) or 0, o.id, o.version })
    if not line then return Veyl.Err('NOT_FOUND', 'Nothing to install') end
    local e = liveEntity(o.owned_id)
    if not e or #(GetEntityCoords(e) - shop.coords) > shop.radius then return Veyl.Err('NOT_FOUND', 'The vehicle is not in the shop') end
    if dist(src, GetEntityCoords(e)) > 4.0 then return Veyl.Err('TOO_FAR', 'Work at the vehicle') end
    local token = Veyl.NewId()
    installing[src] = { token = token, orderId = o.id, lineId = line.id, at = GetGameTimer(), seconds = C.InstallSeconds[line.cat] or 6 }
    return Veyl.Ok({ token = token, seconds = installing[src].seconds, label = line.label })
end, { cooldown = 800 })

Veyl.RegisterCallback('installFinish', function(src, citizenid, token)
    local w = installing[src]
    installing[src] = nil
    if not w or w.token ~= token then return Veyl.Err('INVALID_STATE', 'Start again') end
    if GetGameTimer() - w.at < w.seconds * 1000 - 600 then return Veyl.Err('TOO_FAST', 'You stopped too early') end
    local o = order(w.orderId)
    if not o or o.status ~= 'in_progress' then return Veyl.Err('INVALID_STATE', 'The order changed') end
    local shop = SHOPS[o.shop]
    local st = Bridge.Staff(src, shop)
    if not st or not st.onduty then return Veyl.Err('NO_PERMISSION', 'Clock in at this shop') end
    local e = liveEntity(o.owned_id)
    if not e or dist(src, GetEntityCoords(e)) > 5.0 then return Veyl.Err('TOO_FAR', 'Stay at the vehicle') end
    local line = MySQL.single.await('SELECT * FROM customs_order_lines WHERE id = ? AND order_id = ? AND installed = 0', { w.lineId, o.id })
    if not line then return Veyl.Err('NOT_FOUND', 'Already installed') end
    if shop.stock and line.part and MySQL.update.await('UPDATE customs_stock SET qty = qty - 1, reserved = GREATEST(reserved - 1, 0) WHERE shop = ? AND part = ? AND qty >= 1', { shop.id, line.part }) ~= 1 then
        return Veyl.Err('NO_ITEM', 'Out of stock for this part')
    end
    local info = Bridge.GetOwnedProps(o.owned_id)
    if not info.ok then return info end
    local props = info.data.props or {}
    Cat.ApplyToProps(props, line.k, json.decode(line.value))
    local saved = Bridge.ApplyOwnedProps(o.owned_id, props, info.data.version)
    if not saved.ok then
        if shop.stock and line.part then MySQL.update.await('UPDATE customs_stock SET qty = qty + 1, reserved = reserved + 1 WHERE shop = ? AND part = ?', { shop.id, line.part }) end
        return Veyl.Err(saved.code or 'STALE', 'Could not save the change. Try again.')
    end
    MySQL.update.await('UPDATE customs_order_lines SET installed = 1, installed_by = ?, installed_at = NOW() WHERE id = ?', { citizenid, line.id })
    pushProps(o.owned_id, props)
    local left = MySQL.scalar.await('SELECT COUNT(*) FROM customs_order_lines WHERE order_id = ? AND version = ? AND installed = 0', { o.id, o.version })
    local me = Bridge.Name(Bridge.Player(src))
    audit(o.shop, o.id, me, 'installed', line.label)
    if left == 0 and setStatus(o, 'in_progress', 'completed', { bay = false }) then
        Bridge.BusinessCredit(shop.business, o.paid - o.refunded, ('Order #%d completed'):format(o.id), me)
        audit(o.shop, o.id, me, 'completed', ('$%d'):format(o.total))
        local cs = Bridge.SrcByCitizen(o.customer_cid)
        if cs then Bridge.Notify(cs, ('Your vehicle (%s) is ready. Order #%d completed.'):format(o.plate, o.id), 'success') end
        return Veyl.Ok({ completed = true }, 'All work done. Order completed.')
    end
    return Veyl.Ok({ completed = false, left = left }, ('Installed: %s (%d left)'):format(line.label, left))
end, { cooldown = 500 })

--- In-progress orders whose vehicle is next to the mechanic (for the work menu at the vehicle).
Veyl.RegisterCallback('workAt', function(src, citizenid, netId)
    local e = entityFromNet(netId)
    local ownedId = e and Bridge.OwnedIdFromEntity(e)
    if not ownedId then return Veyl.Ok(nil) end
    local o = MySQL.single.await("SELECT * FROM customs_orders WHERE owned_id = ? AND status = 'in_progress' LIMIT 1", { ownedId })
    if not o then return Veyl.Ok(nil) end
    local st = Bridge.Staff(src, SHOPS[o.shop])
    if not st or not st.onduty then return Veyl.Ok(nil) end
    return Veyl.Ok(orderView(o))
end, { cooldown = 500 })

---------------------------------------------------------------------------
-- Dashboard
---------------------------------------------------------------------------
local function staffShop(src, shopId)
    local shop = SHOPS[shopId]
    local st = shop and Bridge.Staff(src, shop)
    if not st then return nil end
    return shop, st
end

Veyl.RegisterCallback('dashboard', function(src, citizenid, shopId)
    local shop, st = staffShop(src, shopId)
    if not shop then return Veyl.Err('NO_PERMISSION', 'Staff only') end
    if shop.desk and dist(src, shop.desk) > 6.0 and dist(src, shop.coords) > shop.radius then return Veyl.Err('TOO_FAR', 'Use the dashboard at the workshop') end
    local orders = {}
    for _, o in ipairs(MySQL.query.await([[SELECT * FROM customs_orders WHERE shop = ? AND (status IN ('draft','sent','approved','in_progress') OR updated_at > NOW() - INTERVAL 1 DAY)
        ORDER BY FIELD(status,'in_progress','approved','sent','draft') DESC, id DESC LIMIT 60]], { shop.id }) or {}) do orders[#orders + 1] = orderView(o) end
    local active = MySQL.scalar.await("SELECT COUNT(*) FROM customs_orders WHERE shop = ? AND status IN ('approved','in_progress')", { shop.id }) or 0
    -- Revenue today = money kept by the shop for orders completed since local midnight (self-service + finished mechanic work).
    local revenue = MySQL.scalar.await("SELECT COALESCE(SUM(paid - refunded), 0) FROM customs_orders WHERE shop = ? AND status = 'completed' AND updated_at >= CURDATE()", { shop.id }) or 0
    local occupied = {}
    for _, o in ipairs(orders) do if o.bay and (o.status == 'approved' or o.status == 'in_progress') then occupied[o.bay] = o end end
    local bays = {}
    for _, b in ipairs(shop.bays or {}) do
        local o = occupied[b.id]
        bays[#bays + 1] = { id = b.id, state = o and (o.status == 'in_progress' and 'occupied' or 'reserved') or 'available', orderId = o and o.id, plate = o and o.plate }
    end
    local free = 0
    for _, b in ipairs(bays) do if b.state == 'available' then free = free + 1 end end
    local parts = {}
    if shop.stock then
        for _, r in ipairs(MySQL.query.await('SELECT part, qty, reserved, reorder_at FROM customs_stock WHERE shop = ? ORDER BY part', { shop.id }) or {}) do
            local p = C.Parts[r.part]
            if p then
                local incoming = MySQL.scalar.await("SELECT COALESCE(SUM(qty), 0) FROM customs_part_orders WHERE shop = ? AND part = ? AND status = 'ordered'", { shop.id, r.part }) or 0
                parts[#parts + 1] = { part = r.part, label = p.label, qty = r.qty, reserved = r.reserved, reorderAt = r.reorder_at, cost = p.cost, delivery = p.deliveryMinutes, incoming = incoming }
            end
        end
    end
    local partOrders = MySQL.query.await("SELECT id, part, qty, cost, ordered_by, status, UNIX_TIMESTAMP(arrives_at) AS arrives FROM customs_part_orders WHERE shop = ? ORDER BY id DESC LIMIT 15", { shop.id }) or {}
    local team = {}
    local def = Bridge.JobDef(shop.job)
    for _, s in ipairs(GetPlayers()) do
        local id = tonumber(s)
        local pd = Bridge.Player(id)
        local g = pd and pd.jobs and pd.jobs[shop.job]
        if g ~= nil then
            local gd = def and def.grades[tostring(g)]
            local active = MySQL.scalar.await("SELECT COUNT(*) FROM customs_orders WHERE shop = ? AND mechanic_cid = ? AND status IN ('approved','in_progress')", { shop.id, pd.citizenid }) or 0
            team[#team + 1] = { cid = pd.citizenid, name = Bridge.Name(pd), grade = gd and gd.name or tostring(g), onduty = pd.job.name == shop.job and pd.job.onduty == true, active = active }
        end
    end
    local history = MySQL.query.await([[SELECT id, model, plate, customer_name, mechanic_name, kind, status, total, paid, refunded, UNIX_TIMESTAMP(updated_at) AS at
        FROM customs_orders WHERE shop = ? AND status IN ('completed','cancelled','rejected','expired') ORDER BY updated_at DESC LIMIT 40]], { shop.id }) or {}
    local log = st.manager and (MySQL.query.await('SELECT order_id, actor, action, detail, UNIX_TIMESTAMP(created_at) AS at FROM customs_audit WHERE shop = ? ORDER BY id DESC LIMIT 40', { shop.id }) or {}) or {}
    local mult, laborRate = rates(shop)
    local pd = Bridge.Player(src)
    return Veyl.Ok({
        shop = { id = shop.id, label = shop.label, sub = shop.sub, stock = shop.stock == true, business = shop.business },
        me = { cid = citizenid, name = Bridge.Name(pd), onduty = st.onduty, manager = st.manager },
        metrics = { active = active, freeBays = free, totalBays = #bays, revenueToday = revenue },
        orders = orders, bays = bays, parts = parts, partOrders = partOrders, team = team, history = history, log = log,
        pricing = { multiplier = mult, laborRate = laborRate },
    })
end, { cooldown = 600 })

Veyl.RegisterCallback('partsOrder', function(src, citizenid, shopId, part, qty)
    local shop, st = staffShop(src, shopId)
    if not shop or not st.manager then return Veyl.Err('NO_PERMISSION', 'Managers only') end
    local p = C.Parts[part]
    qty = math.floor(tonumber(qty) or 0)
    if not shop.stock or not p or qty < 1 or qty > 50 then return Veyl.Err('INVALID_INPUT', 'Order 1 - 50') end
    local cost = p.cost * qty
    local me = Bridge.Name(Bridge.Player(src))
    local paid
    if shop.business then paid = Bridge.BusinessDebit(shop.business, cost, ('Parts: %dx %s'):format(qty, p.label), me)
    else paid = Bridge.Debit(citizenid, 'bank', cost, ('Parts: %dx %s'):format(qty, p.label), ('customs:parts:%s:%s'):format(shop.id, Veyl.NewId())) end
    if not paid.ok then return Veyl.Err(paid.code or 'INSUFFICIENT_FUNDS', ('Parts cost $%d'):format(cost)) end
    MySQL.insert.await('INSERT INTO customs_part_orders (shop, part, qty, cost, ordered_by, arrives_at) VALUES (?, ?, ?, ?, ?, NOW() + INTERVAL ? MINUTE)',
        { shop.id, part, qty, cost, me, p.deliveryMinutes })
    audit(shop.id, nil, me, 'parts_order', ('%dx %s $%d'):format(qty, part, cost))
    return Veyl.Ok(nil, ('Ordered %dx %s ($%d). Arrives in %d min.'):format(qty, p.label, cost, p.deliveryMinutes))
end, { cooldown = 1500 })

Veyl.RegisterCallback('partsThreshold', function(src, _, shopId, part, value)
    local shop, st = staffShop(src, shopId)
    if not shop or not st.manager then return Veyl.Err('NO_PERMISSION', 'Managers only') end
    value = math.floor(tonumber(value) or -1)
    if not C.Parts[part] or value < 0 or value > 100 then return Veyl.Err('INVALID_INPUT', 'Threshold 0 - 100') end
    MySQL.update.await('UPDATE customs_stock SET reorder_at = ? WHERE shop = ? AND part = ?', { value, shop.id, part })
    return Veyl.Ok(nil, 'Saved')
end, { cooldown = 500 })

Veyl.RegisterCallback('pricing', function(src, _, shopId, multiplier, laborRate)
    local shop, st = staffShop(src, shopId)
    if not shop or not st.manager then return Veyl.Err('NO_PERMISSION', 'Managers only') end
    multiplier, laborRate = tonumber(multiplier), tonumber(laborRate)
    if not multiplier or multiplier < 0.8 or multiplier > 2.0 or not laborRate or laborRate < 0 or laborRate > 0.3 then return Veyl.Err('INVALID_INPUT', 'Multiplier 0.8 - 2.0, labour 0 - 30 %') end
    MySQL.update.await('INSERT INTO customs_shop_settings (shop, price_multiplier, labor_rate) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE price_multiplier = VALUES(price_multiplier), labor_rate = VALUES(labor_rate)',
        { shop.id, multiplier, laborRate })
    settings[shop.id] = { price_multiplier = multiplier, labor_rate = laborRate }
    audit(shop.id, nil, Bridge.Name(Bridge.Player(src)), 'pricing', ('x%.2f labour %.0f%%'):format(multiplier, laborRate * 100))
    return Veyl.Ok(nil, 'Pricing updated (new quotes only)')
end, { cooldown = 1500 })

---------------------------------------------------------------------------
-- Saved builds and colours (per character)
---------------------------------------------------------------------------
local CODE_CHARS = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'
local function newCode()
    local t = {}
    for i = 1, 8 do local n = math.random(1, #CODE_CHARS) t[i] = CODE_CHARS:sub(n, n) end
    return table.concat(t)
end
local function cleanSelections(sel)
    if type(sel) ~= 'table' then return nil end
    local out, n = {}, 0
    for k, v in pairs(sel) do
        n = n + 1
        if n > 80 then return nil end
        local c = Cat.Clean(k, v)
        if c == nil then return nil end
        out[k] = c
    end
    return out
end

Veyl.RegisterCallback('builds', function(src, citizenid, model)
    local rows = MySQL.query.await('SELECT id, name, model, share_code, data FROM customs_builds WHERE citizenid = ? ORDER BY id DESC', { citizenid }) or {}
    local out = {}
    for _, r in ipairs(rows) do
        local ok, d = pcall(json.decode, r.data)
        out[#out + 1] = { id = r.id, name = r.name, model = r.model, code = r.share_code, compatible = r.model == model, data = ok and d or {} }
    end
    return Veyl.Ok(out)
end, { cooldown = 400 })

Veyl.RegisterCallback('buildSave', function(src, citizenid, name, model, selections)
    name = type(name) == 'string' and name:gsub('%c', ''):sub(1, 40) or ''
    local sel = cleanSelections(selections)
    if #name < 1 or type(model) ~= 'string' or not model:match('^[%w_]+$') or not sel then return Veyl.Err('INVALID_INPUT', 'Name the build') end
    if (MySQL.scalar.await('SELECT COUNT(*) FROM customs_builds WHERE citizenid = ?', { citizenid }) or 0) >= C.MaxBuilds then return Veyl.Err('LIMIT', 'Too many saved builds') end
    for _ = 1, 5 do
        local ok = pcall(MySQL.insert.await, 'INSERT INTO customs_builds (citizenid, name, model, data, share_code) VALUES (?, ?, ?, ?, ?)', { citizenid, name, model:lower(), json.encode(sel), newCode() })
        if ok then return Veyl.Ok(nil, 'Build saved') end
    end
    return Veyl.Err('INTERNAL', 'Could not save')
end, { cooldown = 1500 })

Veyl.RegisterCallback('buildDelete', function(src, citizenid, id)
    MySQL.update.await('DELETE FROM customs_builds WHERE id = ? AND citizenid = ?', { tonumber(id) or 0, citizenid })
    return Veyl.Ok()
end, { cooldown = 400 })

Veyl.RegisterCallback('buildDuplicate', function(src, citizenid, id)
    local r = MySQL.single.await('SELECT name, model, data FROM customs_builds WHERE id = ? AND citizenid = ?', { tonumber(id) or 0, citizenid })
    if not r then return Veyl.Err('NOT_FOUND', 'Unknown build') end
    if (MySQL.scalar.await('SELECT COUNT(*) FROM customs_builds WHERE citizenid = ?', { citizenid }) or 0) >= C.MaxBuilds then return Veyl.Err('LIMIT', 'Too many saved builds') end
    MySQL.insert.await('INSERT INTO customs_builds (citizenid, name, model, data, share_code) VALUES (?, ?, ?, ?, ?)', { citizenid, (r.name .. ' (copy)'):sub(1, 40), r.model, r.data, newCode() })
    return Veyl.Ok(nil, 'Duplicated')
end, { cooldown = 800 })

--- Share codes carry only the model and the options (no owner data). Importing copies them into your own builds.
Veyl.RegisterCallback('buildImport', function(src, citizenid, code)
    code = type(code) == 'string' and code:upper():gsub('[^A-Z0-9]', '') or ''
    local r = #code == 8 and MySQL.single.await('SELECT name, model, data FROM customs_builds WHERE share_code = ?', { code })
    if not r then return Veyl.Err('NOT_FOUND', 'No build with that code') end
    if (MySQL.scalar.await('SELECT COUNT(*) FROM customs_builds WHERE citizenid = ?', { citizenid }) or 0) >= C.MaxBuilds then return Veyl.Err('LIMIT', 'Too many saved builds') end
    MySQL.insert.await('INSERT INTO customs_builds (citizenid, name, model, data, share_code) VALUES (?, ?, ?, ?, ?)', { citizenid, r.name:sub(1, 40), r.model, r.data, newCode() })
    return Veyl.Ok(nil, ('Imported "%s"'):format(r.name))
end, { cooldown = 1500 })

Veyl.RegisterCallback('swatches', function(src, _, list)
    if list == nil then
        local s = Bridge.GetMeta(src, 'customsSwatches')
        return Veyl.Ok(type(s) == 'table' and s or {})
    end
    if type(list) ~= 'table' or #list > C.MaxSwatches then return Veyl.Err('INVALID_INPUT', 'Too many colours') end
    local clean = {}
    for i, h in ipairs(list) do
        if type(h) ~= 'string' or not h:match('^#%x%x%x%x%x%x$') then return Veyl.Err('INVALID_INPUT', 'Bad colour') end
        clean[i] = h:upper()
    end
    Bridge.SetMeta(src, 'customsSwatches', clean)
    return Veyl.Ok(clean)
end, { cooldown = 300 })

---------------------------------------------------------------------------
-- Background: parts deliveries, quote expiry, session expiry, recovery
---------------------------------------------------------------------------
CreateThread(function()
    while true do
        Wait(30000)
        for _, r in ipairs(MySQL.query.await("SELECT id, shop, part, qty FROM customs_part_orders WHERE status = 'ordered' AND arrives_at <= NOW() LIMIT 50") or {}) do
            if MySQL.update.await("UPDATE customs_part_orders SET status = 'delivered' WHERE id = ? AND status = 'ordered'", { r.id }) == 1 then
                MySQL.update.await('INSERT INTO customs_stock (shop, part, qty) VALUES (?, ?, ?) ON DUPLICATE KEY UPDATE qty = qty + VALUES(qty)', { r.shop, r.part, r.qty })
                audit(r.shop, nil, 'supplier', 'parts_delivered', ('%dx %s'):format(r.qty, r.part))
            end
        end
        MySQL.update.await("UPDATE customs_orders SET status = 'expired' WHERE status = 'sent' AND expires_at IS NOT NULL AND expires_at < NOW()")
        local now = os.time()
        for src, s in pairs(sessions) do if now > s.expires then closeSession(src, 'expired') end end
    end
end)

--- Reconcile interrupted payments after a restart / crash.
function Recover()
    for _, t in ipairs(MySQL.query.await("SELECT * FROM customs_tx WHERE status = 'charged'") or {}) do
        if t.kind == 'self' then
            local v = MySQL.scalar.await('SELECT props_version FROM veyl_player_vehicles WHERE id = ?', { t.owned_id })
            if v and t.props_version and v > t.props_version then
                MySQL.update.await("UPDATE customs_tx SET status = 'completed' WHERE id = ?", { t.id })
            else
                local r = Bridge.Credit(t.citizenid, 'bank', t.amount, 'Customs: refund for an interrupted purchase', t.op_id .. ':refund')
                if r.ok or r.code == 'DUPLICATE_OPERATION' then MySQL.update.await("UPDATE customs_tx SET status = 'refunded' WHERE id = ?", { t.id }) end
            end
        elseif t.kind == 'order' then
            -- The customer paid: make sure the order shows it (approval finishes), so the money is never lost.
            MySQL.update.await("UPDATE customs_orders SET status = 'approved', paid = ? WHERE id = ? AND status = 'sent'", { t.amount, t.ref })
            MySQL.update.await("UPDATE customs_tx SET status = 'completed' WHERE id = ?", { t.id })
        end
    end
end

AddEventHandler('playerDropped', function()
    local src = source
    closeSession(src)
    installing[src] = nil
end)
AddEventHandler('VeylCore:Server:OnPlayerUnload', function(src) closeSession(src) installing[src] = nil end)
AddEventHandler('veyl_vehicles:removed', function(vehicleId)
    for src, s in pairs(sessions) do
        local e = entityFromNet(s.netId)
        if not e then closeSession(src, 'vehicle_gone') end
    end
end)

-- Debug (staff only, Config.Debug): list sessions and locks.
if C.Debug then
    RegisterCommand('customsdebug', function(src)
        if src ~= 0 and not IsPlayerAceAllowed(src, 'veyl.customs.debug') then return end
        for s, v in pairs(sessions) do print(('[veyl_customs] session %s src=%d owned=%d mode=%s'):format(v.id, s, v.ownedId, v.mode)) end
    end, true)
end
