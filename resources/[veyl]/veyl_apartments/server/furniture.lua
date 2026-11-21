-- Furniture: catalog purchases, placement, moving, storing and selling back.
-- Positions are stored in the room's LOCAL space (lx, ly, lz, heading), so they stay valid whatever the bucket.
-- Ownership: the character who paid owns the piece (owner_cid). While they live in a home it belongs to that home
-- (lease_id). When a lease ends, or a roommate leaves, their pieces are stored (lease_id = NULL) and come with them to
-- their next home; they can also be sold back from the Apartments app. A piece is sold at most once.

Furniture = {}
local F = AptConfig.Furniture

local function count(leaseId)
    return MySQL.scalar.await("SELECT COUNT(*) FROM veyl_apartment_furniture WHERE lease_id = ? AND state = 'placed'", { leaseId }) or 0
end

local function shape(r)
    local def = AptFurniture[r.item]
    return { id = r.id, item = r.item, label = def and def.label or r.item, model = def and def.model or nil,
        x = r.lx, y = r.ly, z = r.lz, heading = r.heading, owner = r.owner_cid, price = r.price, state = r.state }
end

function Furniture.PlacedFor(leaseId)
    local out = {}
    for _, r in ipairs(MySQL.query.await("SELECT * FROM veyl_apartment_furniture WHERE lease_id = ? AND state = 'placed' ORDER BY id", { leaseId }) or {}) do
        if AptFurniture[r.item] then out[#out + 1] = shape(r) end
    end
    return out
end

--- Pushes the current furniture to everyone inside the home.
local function broadcast(leaseId)
    local list = Furniture.PlacedFor(leaseId)
    for _, src in ipairs(Presence.Occupants(leaseId)) do TriggerClientEvent('veyl_apartments:furniture', src, list) end
end
Furniture.Broadcast = broadcast

function Furniture.AttachStored(cid, leaseId)
    MySQL.update.await("UPDATE veyl_apartment_furniture SET lease_id = ? WHERE owner_cid = ? AND lease_id IS NULL AND state = 'stored'", { leaseId, cid })
end

function Furniture.DetachOnEnd(leaseId)
    MySQL.update.await("UPDATE veyl_apartment_furniture SET state = 'stored', lease_id = NULL WHERE lease_id = ? AND state IN ('placed','stored')", { leaseId })
end

function Furniture.DetachOwner(leaseId, cid)
    MySQL.update.await("UPDATE veyl_apartment_furniture SET state = 'stored', lease_id = NULL WHERE lease_id = ? AND owner_cid = ? AND state IN ('placed','stored')", { leaseId, cid })
    broadcast(leaseId)
end

--- The home the player is standing in, with the 'furniture' permission.
local function homeFor(src, citizenid)
    local p = Presence.Of(src)
    if not p or p.kind ~= 'home' then return nil, Veyl.Err('NOT_INSIDE', 'You need to be inside your home') end
    local lease = Access.Lease(p.leaseId)
    if not Access.Can(lease, citizenid, 'furniture') then return nil, Veyl.Err('NO_PERMISSION', 'You cannot change the furniture here') end
    return lease
end

--- Validates a local transform for a lease (bounds, door clearance, spacing to other pieces).
local function check(lease, t, ignoreId)
    if type(t) ~= 'table' then return 'Invalid position' end
    local why = AptGeometry.FurnitureProblem(vector3(tonumber(t.x) or 0 / 0, tonumber(t.y) or 0 / 0, tonumber(t.z) or 0 / 0), tonumber(t.heading))
    if why then return why end
    for _, r in ipairs(MySQL.query.await("SELECT id, lx, ly, lz FROM veyl_apartment_furniture WHERE lease_id = ? AND state = 'placed'", { lease.id }) or {}) do
        if r.id ~= ignoreId then
            local dx, dy, dz = r.lx - t.x, r.ly - t.y, r.lz - t.z
            if math.sqrt(dx * dx + dy * dy + dz * dz) < F.MinSpacing then return 'Too close to another piece' end
        end
    end
    return nil
end

Veyl.RegisterCallback('furnitureCatalog', function(src, citizenid)
    local p = Presence.Of(src)
    local lease = p and p.kind == 'home' and Access.Lease(p.leaseId)
    local unit = lease and Apt.Unit(lease.unit_id)
    local stored = {}
    if lease then
        for _, r in ipairs(MySQL.query.await("SELECT * FROM veyl_apartment_furniture WHERE lease_id = ? AND state = 'stored' ORDER BY id DESC", { lease.id }) or {}) do
            local s = shape(r)
            s.mine = r.owner_cid == citizenid
            stored[#stored + 1] = s
        end
    end
    local items = {}
    for key, def in pairs(AptFurniture) do items[#items + 1] = { key = key, label = def.label, model = def.model, category = def.category, price = def.price } end
    table.sort(items, function(a, b) return a.price < b.price end)
    local pd = Veyl.GetPlayerData(src)
    return Veyl.Ok({
        categories = AptFurnitureCategories, items = items, stored = stored, canEdit = lease and Access.Can(lease, citizenid, 'furniture') or false,
        placed = lease and count(lease.id) or 0, limit = unit and Apt.Type(unit).furnitureLimit or 0,
        sellRate = F.SellBackRate, balances = { bank = pd and pd.money.bank or 0 },
    })
end, { cooldown = 300 })

--- place({ item?|id?, x, y, z, heading, clientOp }) — buys (item) or places a stored piece (id). Validates BEFORE charging.
Veyl.RegisterCallback('furniturePlace', function(src, citizenid, req)
    local lease, err = homeFor(src, citizenid)
    if not lease then return err end
    if type(req) ~= 'table' or not Apt.ValidOp(req.clientOp) then return Veyl.Err('INVALID_INPUT', 'Invalid request') end
    return Apt.WithLock('furn:' .. lease.id, function()
        local unit = Apt.Unit(lease.unit_id)
        local limit = Apt.Type(unit).furnitureLimit
        local t = { x = tonumber(req.x), y = tonumber(req.y), z = tonumber(req.z), heading = tonumber(req.heading) }
        if req.id then
            local row = Veyl.Validate.int(req.id, 1) and MySQL.single.await("SELECT * FROM veyl_apartment_furniture WHERE id = ? AND lease_id = ? AND state = 'stored'", { req.id, lease.id })
            if not row then return Veyl.Err('NOT_FOUND', 'That piece is not in storage') end
            if count(lease.id) >= limit then return Veyl.Err('LIMIT', ('This room holds up to %d pieces'):format(limit)) end
            local why = check(lease, t)
            if why then return Veyl.Err('INVALID_POSITION', why) end
            MySQL.update.await("UPDATE veyl_apartment_furniture SET state = 'placed', lx = ?, ly = ?, lz = ?, heading = ? WHERE id = ? AND state = 'stored'",
                { t.x, t.y, t.z, t.heading, row.id })
            broadcast(lease.id)
            return Veyl.Ok(nil, 'Placed')
        end
        local def = type(req.item) == 'string' and AptFurniture[req.item]
        if not def then return Veyl.Err('NOT_FOUND', 'Unknown item') end
        local op = ('apt:furn:%s:%s'):format(citizenid, req.clientOp)
        local existing = MySQL.single.await('SELECT * FROM veyl_apartment_furniture WHERE op_id = ?', { op })
        if existing and existing.state == 'placed' then return Veyl.Ok(nil, 'Placed') end
        if not existing then
            if count(lease.id) >= limit then return Veyl.Err('LIMIT', ('This room holds up to %d pieces'):format(limit)) end
            local why = check(lease, t)
            if why then return Veyl.Err('INVALID_POSITION', why) end
            -- Reserve the row first (state 'pending') so a crash between charge and placement is recoverable.
            MySQL.insert.await([[INSERT INTO veyl_apartment_furniture (owner_cid, lease_id, item, price, state, lx, ly, lz, heading, op_id)
                VALUES (?, NULL, ?, ?, 'pending', ?, ?, ?, ?, ?)]], { citizenid, req.item, def.price, t.x, t.y, t.z, t.heading, op })
            existing = MySQL.single.await('SELECT * FROM veyl_apartment_furniture WHERE op_id = ?', { op })
        end
        local pay = Apt.Core('DebitOnce', citizenid, 'bank', def.price, ('Furniture: %s'):format(def.label), op)
        if pay.ok or pay.code == 'DUPLICATE_OPERATION' then
            MySQL.update.await("UPDATE veyl_apartment_furniture SET state = 'placed', lease_id = ? WHERE id = ? AND state = 'pending'", { lease.id, existing.id })
            broadcast(lease.id)
            Apt.Audit(src, 'furniture_bought', { lease = lease.id, item = req.item, price = def.price })
            return Veyl.Ok(nil, ('Bought %s for $%d'):format(def.label, def.price))
        end
        if pay.code == 'TIMEOUT' then return Veyl.Err('PENDING', 'Payment is being confirmed. You will not be charged twice.') end
        MySQL.update.await("DELETE FROM veyl_apartment_furniture WHERE id = ? AND state = 'pending'", { existing.id })
        if pay.code == 'INSUFFICIENT_FUNDS' then return Veyl.Err('INSUFFICIENT_FUNDS', ('You need $%d in your bank account'):format(def.price)) end
        return pay
    end)
end)

--- A purchase whose payment outcome was unknown (crash/timeout): resolve it from the ledger.
function Furniture.Reconcile()
    for _, r in ipairs(MySQL.query.await([[SELECT * FROM veyl_apartment_furniture WHERE state = 'pending'
        AND created_at < DATE_SUB(NOW(), INTERVAL 2 MINUTE) AND op_id LIKE 'apt:furn:%' LIMIT 25]]) or {}) do
        local op = Apt.Core('GetMoneyOperation', r.op_id)
        if op.ok and op.data then
            -- Paid but never placed: give it to the buyer as a stored piece (in their home if they still have one).
            local home = Access.LeaseOf(r.owner_cid)
            MySQL.update.await("UPDATE veyl_apartment_furniture SET state = 'stored', lease_id = ? WHERE id = ? AND state = 'pending'", { home and home.id or nil, r.id })
        elseif op.ok then
            MySQL.update.await("DELETE FROM veyl_apartment_furniture WHERE id = ? AND state = 'pending'", { r.id })
        end
    end
end
AddEventHandler('veyl_apartments:ready', function() SetTimeout(5000, Furniture.Reconcile) end)

Veyl.RegisterCallback('furnitureMove', function(src, citizenid, id, t)
    local lease, err = homeFor(src, citizenid)
    if not lease then return err end
    if not Veyl.Validate.int(id, 1) then return Veyl.Err('INVALID_INPUT', 'Invalid') end
    return Apt.WithLock('furn:' .. lease.id, function()
        local row = MySQL.single.await("SELECT * FROM veyl_apartment_furniture WHERE id = ? AND lease_id = ? AND state = 'placed'", { id, lease.id })
        if not row then return Veyl.Err('NOT_FOUND', 'Piece not found') end
        local tt = { x = tonumber(t and t.x), y = tonumber(t and t.y), z = tonumber(t and t.z), heading = tonumber(t and t.heading) }
        local why = check(lease, tt, row.id)
        if why then return Veyl.Err('INVALID_POSITION', why) end
        MySQL.update.await('UPDATE veyl_apartment_furniture SET lx = ?, ly = ?, lz = ?, heading = ? WHERE id = ?', { tt.x, tt.y, tt.z, tt.heading, id })
        broadcast(lease.id)
        return Veyl.Ok(nil, 'Moved')
    end)
end)

Veyl.RegisterCallback('furnitureStore', function(src, citizenid, id)
    local lease, err = homeFor(src, citizenid)
    if not lease then return err end
    local n = Veyl.Validate.int(id, 1) and MySQL.update.await("UPDATE veyl_apartment_furniture SET state = 'stored' WHERE id = ? AND lease_id = ? AND state = 'placed'", { id, lease.id })
    if n ~= 1 then return Veyl.Err('NOT_FOUND', 'Piece not found') end
    broadcast(lease.id)
    return Veyl.Ok(nil, 'Moved to storage')
end, { cooldown = 400 })

--- Sell back at the configured rate. Only the buyer can sell; a piece can be sold once (state guard).
Veyl.RegisterCallback('furnitureSell', function(src, citizenid, id)
    if not Veyl.Validate.int(id, 1) then return Veyl.Err('INVALID_INPUT', 'Invalid') end
    return Apt.WithLock('furnsell:' .. id, function()
        local row = MySQL.single.await("SELECT * FROM veyl_apartment_furniture WHERE id = ? AND state IN ('placed','stored')", { id })
        if not row then return Veyl.Err('NOT_FOUND', 'Already sold') end
        if row.owner_cid ~= citizenid then return Veyl.Err('NO_PERMISSION', 'Only the person who bought it can sell it') end
        if row.state == 'placed' then
            local lease, err = homeFor(src, citizenid)
            if not lease or lease.id ~= row.lease_id then return err or Veyl.Err('NOT_INSIDE', 'Store it first, or sell it from inside the home') end
        end
        local n = MySQL.update.await("UPDATE veyl_apartment_furniture SET state = 'sold' WHERE id = ? AND state IN ('placed','stored')", { id })
        if n ~= 1 then return Veyl.Err('NOT_FOUND', 'Already sold') end
        local refund = math.floor(row.price * F.SellBackRate)
        if refund > 0 then
            local res = Apt.Core('CreditOnce', citizenid, 'bank', refund, ('Furniture sold: %s'):format(AptFurniture[row.item] and AptFurniture[row.item].label or row.item),
                'apt:sell:' .. id)
            if not res.ok and res.code ~= 'DUPLICATE_OPERATION' and res.code ~= 'TIMEOUT' then
                MySQL.update.await("UPDATE veyl_apartment_furniture SET state = ? WHERE id = ? AND state = 'sold'", { row.state, id })
                return Veyl.Err('FAILED', 'The refund failed, so the piece was not sold')
            end
        end
        if row.lease_id then broadcast(row.lease_id) end
        Apt.Audit(src, 'furniture_sold', { id = id, refund = refund })
        return Veyl.Ok({ refund = refund }, ('Sold for $%d'):format(refund))
    end)
end)

--- Stored pieces a character owns outside any home (after moving out), for the app.
Veyl.RegisterCallback('furnitureOwned', function(_, citizenid)
    local out = {}
    for _, r in ipairs(MySQL.query.await("SELECT * FROM veyl_apartment_furniture WHERE owner_cid = ? AND state IN ('placed','stored') ORDER BY id DESC LIMIT 100", { citizenid }) or {}) do
        out[#out + 1] = shape(r)
    end
    return Veyl.Ok({ items = out, sellRate = F.SellBackRate })
end, { cooldown = 400 })
