-- Marketplace: classified listings. Listings show the seller's phone number so buyers can message or call;
-- no money changes hands here. Listings expire after ListingDays; sellers can remove theirs, staff can remove any.

local M = PhoneConfig.Market
local CATS = {}
for _, c in ipairs(M.Categories) do CATS[c] = true end

local function isStaff(src)
    local ok, yes = pcall(function() return exports.veyl_core:HasPermission(src, 'admin') end)
    return ok and yes == true
end

local function shape(rows, citizenid, staff)
    local out = {}
    for i, r in ipairs(rows or {}) do
        out[i] = { id = r.id, title = r.title, body = r.body, price = r.price, category = r.category, number = r.number,
            display = PhoneUtil.Format(r.number), seller = r.seller, at = r.at, expires = r.expires,
            mine = r.citizenid == citizenid, canDelete = r.citizenid == citizenid or staff }
    end
    return out
end

local COLS = [[m.id, m.citizenid, m.number, m.title, m.body, m.price, m.category, UNIX_TIMESTAMP(m.created_at) AS at,
    UNIX_TIMESTAMP(m.expires_at) AS expires, a.display_name AS seller]]

--- marketList(category|'all'|'mine', beforeId?)
Veyl.RegisterCallback('marketList', function(src, citizenid, category, beforeId)
    if not Phone.Session(src) then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    local before = Veyl.Validate.int(beforeId, 1) and beforeId or 2147483647
    local where, params = 'm.deleted = 0 AND m.expires_at > CURRENT_TIMESTAMP AND m.id < ?', { before }
    if category == 'mine' then where = where .. ' AND m.citizenid = ?' params[#params + 1] = citizenid
    elseif CATS[category] then where = where .. ' AND m.category = ?' params[#params + 1] = category end
    params[#params + 1] = M.PageSize
    local rows = MySQL.query.await(('SELECT %s FROM veyl_phone_market m LEFT JOIN veyl_ph_accounts a ON a.citizenid = m.citizenid WHERE %s ORDER BY m.id DESC LIMIT ?')
        :format(COLS, where), params) or {}
    return Veyl.Ok({ items = shape(rows, citizenid, isStaff(src)), nextBefore = #rows == M.PageSize and rows[#rows].id or nil, categories = M.Categories })
end, { cooldown = 250 })

--- marketPost({ title, body, price, category, clientOp }) -> Ok(listing)
Veyl.RegisterCallback('marketPost', function(src, citizenid, input)
    local s = Phone.Session(src)
    if not s then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    if type(input) ~= 'table' or not Veyl.Validate.str(input.clientOp, 6, 64, '^[%w%-]+$') then return Veyl.Err('INVALID_INPUT', 'Invalid listing') end
    local function fetch(id)
        local r = MySQL.query.await(('SELECT %s FROM veyl_phone_market m LEFT JOIN veyl_ph_accounts a ON a.citizenid = m.citizenid WHERE m.id = ?'):format(COLS), { id })
        return shape(r, citizenid, false)[1]
    end
    local existing = MySQL.scalar.await('SELECT id FROM veyl_phone_market WHERE citizenid = ? AND client_op = ?', { citizenid, input.clientOp })
    if existing then return Veyl.Ok(fetch(existing)) end
    local title = PhoneUtil.Clean(input.title, M.TitleLength)
    local body = PhoneUtil.Clean(input.body, M.BodyLength) or ''
    if not title then return Veyl.Err('INVALID_INPUT', 'Give your listing a title') end
    if not Veyl.Validate.int(input.price, 0, M.MaxPrice) then return Veyl.Err('INVALID_INPUT', ('Price must be $0 to $%d'):format(M.MaxPrice)) end
    if not CATS[input.category] then return Veyl.Err('INVALID_INPUT', 'Pick a category') end
    if not Phone.Rate(src, 'marketPost', 10000) then return Veyl.Err('RATE_LIMITED', 'Wait a moment before posting again') end
    local active = MySQL.scalar.await('SELECT COUNT(*) FROM veyl_phone_market WHERE citizenid = ? AND deleted = 0 AND expires_at > CURRENT_TIMESTAMP', { citizenid }) or 0
    if active >= M.MaxActive then return Veyl.Err('LIMIT', ('You can have %d active listings. Remove one first.'):format(M.MaxActive)) end
    local id = MySQL.insert.await([[INSERT INTO veyl_phone_market (citizenid, number, title, body, price, category, client_op, expires_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, DATE_ADD(CURRENT_TIMESTAMP, INTERVAL ? DAY))]], { citizenid, s.number, title, body, input.price, input.category, input.clientOp, M.ListingDays })
    if not id then return Veyl.Err('DATABASE_ERROR', 'Could not post the listing') end
    return Veyl.Ok(fetch(id), 'Listing posted')
end)

Veyl.RegisterCallback('marketDelete', function(src, citizenid, id)
    if not Phone.Session(src) then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    if not Veyl.Validate.int(id, 1) then return Veyl.Err('INVALID_INPUT', 'Invalid listing') end
    local owner = MySQL.scalar.await('SELECT citizenid FROM veyl_phone_market WHERE id = ? AND deleted = 0', { id })
    if not owner then return Veyl.Err('NOT_FOUND', 'Listing not found') end
    local staff = owner ~= citizenid and isStaff(src)
    if owner ~= citizenid and not staff then return Veyl.Err('NO_PERMISSION', 'You can only remove your own listings') end
    MySQL.update.await('UPDATE veyl_phone_market SET deleted = 1 WHERE id = ?', { id })
    if staff then Veyl.Audit(src, 'market_remove', { listing = id, seller = owner }) end
    return Veyl.Ok(nil, 'Listing removed')
end, { cooldown = 300 })
