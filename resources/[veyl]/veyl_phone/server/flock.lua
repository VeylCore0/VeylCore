-- Flock: short public posts. A Flock account (@handle + password) is made with sign up and used with log in / log out; a character is logged in to
-- one account at a time (stored, so it stays until they log out). Posts, replies, likes, follows and @mentions belong to the account, not the character.
-- Counts are recomputed from the rows they summarise, so they can never drift. Staff (core 'admin' permission)
-- may remove any post.

local F = PhoneConfig.Flock
local A = PhoneConfig.Account
local LOCK = { Max = 5, Seconds = 300 }
local fails = {}   -- [character] = { n, lockedUntil }

--- The account (profile key) this character is logged in to, or nil.
local function acct(character)
    return MySQL.scalar.await('SELECT s.account FROM veyl_phone_flock_sessions s JOIN veyl_phone_flock_profiles p ON p.citizenid = s.account WHERE s.citizenid = ?', { character })
end

--- Registers a callback that needs a logged-in Flock account; the handler receives the account key where it used to get the citizenid.
local function Account(name, fn, opts)
    Veyl.RegisterCallback(name, function(src, character, ...)
        if not Phone.Session(src) then return Veyl.Err('NO_SESSION', 'Open your phone first') end
        local key = acct(character)
        if not key then return Veyl.Err('NOT_LOGGED_IN', 'Log in to Flock first') end
        return fn(src, key, ...)
    end, opts)
end

--- Tells every character currently logged in to an account.
local function notifyAccount(key, payload)
    for _, r in ipairs(MySQL.query.await('SELECT citizenid FROM veyl_phone_flock_sessions WHERE account = ?', { key }) or {}) do Notify.Send(r.citizenid, payload) end
end

local function newKey()
    for _ = 1, 20 do
        local t = { 'F' }
        for i = 2, 16 do t[i] = ('%x'):format(math.random(0, 15)) end
        local k = table.concat(t)
        if not MySQL.scalar.await('SELECT 1 FROM veyl_phone_flock_profiles WHERE citizenid = ?', { k }) then return k end
    end
end

local function validPassword(pw)
    if type(pw) ~= 'string' or #pw < A.PasswordMin or #pw > 64 or pw:find('%c') then
        return false, ('Use %d to 64 characters for your password'):format(A.PasswordMin)
    end
    return true
end

local function cleanHandle(handle)
    handle = type(handle) == 'string' and handle:gsub('^@', ''):lower() or ''
    if not handle:match('^[%w_]+$') or #handle < 3 or #handle > 15 then return nil end
    return handle
end

local function profileOf(citizenid)
    return MySQL.single.await('SELECT citizenid, handle, display_name, bio FROM veyl_phone_flock_profiles WHERE citizenid = ?', { citizenid })
end

local function isStaff(src)
    local ok, yes = pcall(function() return exports.veyl_core:HasPermission(src, 'admin') end)
    return ok and yes == true
end

local POST_COLS = [[p.id, p.body, p.reply_to AS replyTo, p.likes, p.replies, UNIX_TIMESTAMP(p.created_at) AS at, p.citizenid AS cid,
    f.handle, f.display_name AS display, (SELECT 1 FROM veyl_phone_flock_likes l WHERE l.post_id = p.id AND l.citizenid = ?) AS liked]]

local function shape(rows, citizenid, staff)
    local out = {}
    for i, r in ipairs(rows or {}) do
        out[i] = { id = r.id, body = r.body, replyTo = r.replyTo, likes = r.likes, replies = r.replies, at = r.at,
            handle = r.handle, display = r.display, liked = r.liked ~= nil, mine = r.cid == citizenid, canDelete = r.cid == citizenid or staff }
    end
    return out
end

local function counts(citizenid)
    return {
        posts = MySQL.scalar.await('SELECT COUNT(*) FROM veyl_phone_flock_posts WHERE citizenid = ? AND deleted = 0 AND reply_to IS NULL', { citizenid }) or 0,
        followers = MySQL.scalar.await('SELECT COUNT(*) FROM veyl_phone_flock_follows WHERE followee = ?', { citizenid }) or 0,
        following = MySQL.scalar.await('SELECT COUNT(*) FROM veyl_phone_flock_follows WHERE follower = ?', { citizenid }) or 0,
    }
end

local function before(id) return Veyl.Validate.int(id, 1) and id or 9007199254740991 end

--- flockMe() -> Ok({ profile|nil, counts, legacy? }). No profile means not logged in; legacy is an old account of this character that still needs a password.
Veyl.RegisterCallback('flockMe', function(src, character)
    if not Phone.Session(src) then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    local key = acct(character)
    local p = key and profileOf(key)
    if p then return Veyl.Ok({ profile = { handle = p.handle, display = p.display_name, bio = p.bio }, counts = counts(key) }) end
    local old = MySQL.single.await('SELECT handle, display_name FROM veyl_phone_flock_profiles WHERE citizenid = ? AND pass_hash IS NULL', { character })
    return Veyl.Ok({ profile = nil, legacy = old and { handle = old.handle, display = old.display_name } or nil })
end, { cooldown = 200 })

local function logIn(character, key)
    MySQL.query.await('INSERT INTO veyl_phone_flock_sessions (citizenid, account) VALUES (?, ?) ON DUPLICATE KEY UPDATE account = VALUES(account), since = CURRENT_TIMESTAMP', { character, key })
end

--- flockSignup(handle, displayName, password): makes a new account and logs this character in.
Veyl.RegisterCallback('flockSignup', function(src, character, handle, display, password)
    local s = Phone.Session(src)
    if not s then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    if not Phone.Rate(src, 'flockSignup', 2000) then return Veyl.Err('RATE_LIMITED', 'Slow down') end
    handle = cleanHandle(handle)
    if not handle then return Veyl.Err('INVALID_INPUT', 'Handles are 3-15 letters, numbers or _') end
    local okPw, why = validPassword(password)
    if not okPw then return Veyl.Err('INVALID_INPUT', why) end
    if password:lower() == handle then return Veyl.Err('INVALID_INPUT', 'Your password cannot be your handle') end
    display = PhoneUtil.Clean(display, 32) or s.name
    if MySQL.scalar.await('SELECT 1 FROM veyl_phone_flock_profiles WHERE handle = ?', { handle }) then return Veyl.Err('DUPLICATE', '@' .. handle .. ' is taken') end
    -- A character with no account of its own keeps the old rule (account key = citizenid); further accounts get a key of their own.
    local key = MySQL.scalar.await('SELECT 1 FROM veyl_phone_flock_profiles WHERE citizenid = ?', { character }) and newKey() or character
    if not key then return Veyl.Err('DATABASE_ERROR', 'Could not create the account') end
    local ok = pcall(MySQL.query.await, 'INSERT INTO veyl_phone_flock_profiles (citizenid, handle, display_name, pass_hash) VALUES (?, ?, ?, ?)', { key, handle, display, Crypto.Hash(password) })
    if not ok then return Veyl.Err('DUPLICATE', '@' .. handle .. ' is taken') end
    logIn(character, key)
    return Veyl.Ok({ profile = { handle = handle, display = display }, counts = counts(key) }, 'Welcome to Flock')
end)

--- flockLogin(handle, password): logs this character in to an existing account.
Veyl.RegisterCallback('flockLogin', function(src, character, handle, password)
    if not Phone.Session(src) then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    if not Phone.Rate(src, 'flockLogin', 1000) then return Veyl.Err('RATE_LIMITED', 'Slow down') end
    local f = fails[character]
    if f and f.lockedUntil and f.lockedUntil > os.time() then return Veyl.Err('LOCKED_OUT', ('Too many tries. Wait %d seconds.'):format(f.lockedUntil - os.time())) end
    handle = cleanHandle(handle)
    if not handle or type(password) ~= 'string' or #password > 64 then return Veyl.Err('INVALID_INPUT', 'Enter your handle and password') end
    local p = MySQL.single.await('SELECT citizenid, handle, display_name, bio, pass_hash FROM veyl_phone_flock_profiles WHERE handle = ?', { handle })
    local good = p and type(p.pass_hash) == 'string' and p.pass_hash ~= '' and Crypto.Verify(password, p.pass_hash)
    if not good then
        f = f or { n = 0 }
        f.n = f.n + 1
        if f.n >= LOCK.Max then f.n, f.lockedUntil = 0, os.time() + LOCK.Seconds end
        fails[character] = f
        -- The same answer for "no such handle" and "wrong password", so handles cannot be probed.
        return Veyl.Err('WRONG_LOGIN', 'Wrong handle or password')
    end
    fails[character] = nil
    logIn(character, p.citizenid)
    return Veyl.Ok({ profile = { handle = p.handle, display = p.display_name, bio = p.bio }, counts = counts(p.citizenid) }, 'Logged in as @' .. p.handle)
end)

--- flockLogout(): this character leaves the account; the account and its posts stay.
Veyl.RegisterCallback('flockLogout', function(src, character)
    if not Phone.Session(src) then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    MySQL.update.await('DELETE FROM veyl_phone_flock_sessions WHERE citizenid = ?', { character })
    return Veyl.Ok(nil, 'Logged out')
end, { cooldown = 400 })

--- flockClaim(password): an account made before passwords existed gets one, and this character is logged in.
Veyl.RegisterCallback('flockClaim', function(src, character, password)
    if not Phone.Session(src) then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    local okPw, why = validPassword(password)
    if not okPw then return Veyl.Err('INVALID_INPUT', why) end
    local p = MySQL.single.await('SELECT citizenid, handle, display_name, bio FROM veyl_phone_flock_profiles WHERE citizenid = ? AND pass_hash IS NULL', { character })
    if not p then return Veyl.Err('NOT_FOUND', 'No old account to protect') end
    if password:lower() == p.handle then return Veyl.Err('INVALID_INPUT', 'Your password cannot be your handle') end
    MySQL.update.await('UPDATE veyl_phone_flock_profiles SET pass_hash = ? WHERE citizenid = ? AND pass_hash IS NULL', { Crypto.Hash(password), character })
    logIn(character, character)
    return Veyl.Ok({ profile = { handle = p.handle, display = p.display_name, bio = p.bio }, counts = counts(character) }, 'Account protected')
end)

--- flockSetup(handle, displayName, bio?) edits the logged-in account's profile. Handles: 3-15 letters, numbers or _.
Account('flockSetup', function(src, key, handle, display, bio)
    if not Phone.Rate(src, 'flockSetup', 2000) then return Veyl.Err('RATE_LIMITED', 'Slow down') end
    handle = cleanHandle(handle)
    if not handle then return Veyl.Err('INVALID_INPUT', 'Handles are 3-15 letters, numbers or _') end
    local me = profileOf(key)
    display = PhoneUtil.Clean(display, 32) or me.display_name
    bio = PhoneUtil.Clean(bio, 120)
    local taken = MySQL.scalar.await('SELECT citizenid FROM veyl_phone_flock_profiles WHERE handle = ?', { handle })
    if taken and taken ~= key then return Veyl.Err('DUPLICATE', '@' .. handle .. ' is taken') end
    local ok = pcall(MySQL.query.await, 'UPDATE veyl_phone_flock_profiles SET handle = ?, display_name = ?, bio = ? WHERE citizenid = ?', { handle, display, bio, key })
    if not ok then return Veyl.Err('DUPLICATE', '@' .. handle .. ' is taken') end
    return Veyl.Ok({ handle = handle, display = display, bio = bio }, 'Profile saved')
end)

--- flockFeed(mode 'all'|'following', beforeId?) -> top-level posts, newest first.
Account('flockFeed', function(src, citizenid, mode, beforeId)
    local rows
    if mode == 'following' then
        rows = MySQL.query.await(('SELECT %s FROM veyl_phone_flock_posts p JOIN veyl_phone_flock_profiles f ON f.citizenid = p.citizenid '):format(POST_COLS) ..
            [[WHERE p.reply_to IS NULL AND p.deleted = 0 AND p.id < ? AND (p.citizenid = ? OR p.citizenid IN
              (SELECT followee FROM veyl_phone_flock_follows WHERE follower = ?)) ORDER BY p.id DESC LIMIT ?]],
            { citizenid, before(beforeId), citizenid, citizenid, F.PageSize })
    else
        rows = MySQL.query.await(('SELECT %s FROM veyl_phone_flock_posts p JOIN veyl_phone_flock_profiles f ON f.citizenid = p.citizenid '):format(POST_COLS) ..
            'WHERE p.reply_to IS NULL AND p.deleted = 0 AND p.id < ? ORDER BY p.id DESC LIMIT ?', { citizenid, before(beforeId), F.PageSize })
    end
    rows = rows or {}
    return Veyl.Ok({ items = shape(rows, citizenid, isStaff(src)), nextBefore = #rows == F.PageSize and rows[#rows].id or nil })
end, { cooldown = 250 })

--- flockThread(postId) -> the post and its replies (oldest first).
Account('flockThread', function(src, citizenid, postId)
    if not Veyl.Validate.int(postId, 1) then return Veyl.Err('INVALID_INPUT', 'Invalid post') end
    local base = ('SELECT %s FROM veyl_phone_flock_posts p JOIN veyl_phone_flock_profiles f ON f.citizenid = p.citizenid '):format(POST_COLS)
    local post = MySQL.query.await(base .. 'WHERE p.id = ? AND p.deleted = 0', { citizenid, postId })
    if not post or not post[1] then return Veyl.Err('NOT_FOUND', 'This post was removed') end
    local replies = MySQL.query.await(base .. 'WHERE p.reply_to = ? AND p.deleted = 0 ORDER BY p.id ASC LIMIT 100', { citizenid, postId }) or {}
    local staff = isStaff(src)
    return Veyl.Ok({ post = shape(post, citizenid, staff)[1], replies = shape(replies, citizenid, staff) })
end, { cooldown = 200 })

--- flockUser(handle, beforeId?) -> profile, counts, whether I follow them, their posts.
Account('flockUser', function(src, citizenid, handle, beforeId)
    if type(handle) ~= 'string' or not handle:match('^[%w_]+$') then return Veyl.Err('INVALID_INPUT', 'Invalid handle') end
    local p = MySQL.single.await('SELECT citizenid, handle, display_name, bio FROM veyl_phone_flock_profiles WHERE handle = ?', { handle:lower() })
    if not p then return Veyl.Err('NOT_FOUND', 'No one is using @' .. handle) end
    local rows = MySQL.query.await(('SELECT %s FROM veyl_phone_flock_posts p JOIN veyl_phone_flock_profiles f ON f.citizenid = p.citizenid '):format(POST_COLS) ..
        'WHERE p.citizenid = ? AND p.reply_to IS NULL AND p.deleted = 0 AND p.id < ? ORDER BY p.id DESC LIMIT ?', { citizenid, p.citizenid, before(beforeId), F.PageSize }) or {}
    local following = MySQL.scalar.await('SELECT 1 FROM veyl_phone_flock_follows WHERE follower = ? AND followee = ?', { citizenid, p.citizenid }) ~= nil
    return Veyl.Ok({
        profile = { handle = p.handle, display = p.display_name, bio = p.bio }, counts = counts(p.citizenid),
        me = p.citizenid == citizenid, following = following,
        items = shape(rows, citizenid, isStaff(src)), nextBefore = #rows == F.PageSize and rows[#rows].id or nil,
    })
end, { cooldown = 250 })

--- flockPost({ body, replyTo?, clientOp }) -> Ok(post). A retried clientOp returns the stored post.
Account('flockPost', function(src, citizenid, input)
    if type(input) ~= 'table' or not Veyl.Validate.str(input.clientOp, 6, 64, '^[%w%-]+$') then return Veyl.Err('INVALID_INPUT', 'Invalid post') end
    local me = profileOf(citizenid)
    if not me then return Veyl.Err('NO_PROFILE', 'Pick a handle first') end
    local existing = MySQL.single.await('SELECT id FROM veyl_phone_flock_posts WHERE citizenid = ? AND client_op = ?', { citizenid, input.clientOp })
    local function fetch(id)
        local r = MySQL.query.await(('SELECT %s FROM veyl_phone_flock_posts p JOIN veyl_phone_flock_profiles f ON f.citizenid = p.citizenid WHERE p.id = ?'):format(POST_COLS), { citizenid, id })
        return shape(r, citizenid, false)[1]
    end
    if existing then return Veyl.Ok(fetch(existing.id)) end
    local body = PhoneUtil.Clean(input.body, F.PostLength)
    if not body then return Veyl.Err('INVALID_INPUT', 'Write something first') end
    if not Phone.Rate(src, 'flockPost', F.PostCooldownMs) then return Veyl.Err('RATE_LIMITED', 'You are posting too fast') end
    local parent
    if input.replyTo ~= nil then
        if not Veyl.Validate.int(input.replyTo, 1) then return Veyl.Err('INVALID_INPUT', 'Invalid reply') end
        parent = MySQL.single.await('SELECT id, citizenid, reply_to FROM veyl_phone_flock_posts WHERE id = ? AND deleted = 0', { input.replyTo })
        if not parent then return Veyl.Err('NOT_FOUND', 'That post was removed') end
        if parent.reply_to then return Veyl.Err('INVALID_INPUT', 'Reply to the original post') end
    end
    local id = MySQL.insert.await('INSERT INTO veyl_phone_flock_posts (citizenid, body, reply_to, client_op) VALUES (?, ?, ?, ?)',
        { citizenid, body, parent and parent.id or nil, input.clientOp })
    if not id then return Veyl.Err('DATABASE_ERROR', 'Could not post') end
    local notified = {}
    if parent then
        MySQL.update.await([[UPDATE veyl_phone_flock_posts SET replies = (SELECT COUNT(*) FROM (SELECT id FROM veyl_phone_flock_posts
            WHERE reply_to = ? AND deleted = 0) t) WHERE id = ?]], { parent.id, parent.id })
        if parent.citizenid ~= citizenid then
            notified[parent.citizenid] = true
            notifyAccount(parent.citizenid, { app = 'flock', title = ('@%s replied'):format(me.handle), body = body, route = 'flock/p' .. parent.id, dedupe = 'flock:r' .. id })
        end
    end
    -- @mentions (existing handles only, a few per post).
    local n = 0
    for handle in body:gmatch('@([%w_]+)') do
        if n >= F.MaxMentions then break end
        n = n + 1
        local cid = MySQL.scalar.await('SELECT citizenid FROM veyl_phone_flock_profiles WHERE handle = ?', { handle:lower() })
        if cid and cid ~= citizenid and not notified[cid] then
            notified[cid] = true
            notifyAccount(cid, { app = 'flock', title = ('@%s mentioned you'):format(me.handle), body = body,
                route = 'flock/p' .. (parent and parent.id or id), dedupe = 'flock:m' .. id })
        end
    end
    return Veyl.Ok(fetch(id))
end)

--- flockLike(postId, on) -> Ok({ likes, liked })
Account('flockLike', function(src, citizenid, postId, on)
    if not Veyl.Validate.int(postId, 1) then return Veyl.Err('INVALID_INPUT', 'Invalid post') end
    if not MySQL.scalar.await('SELECT 1 FROM veyl_phone_flock_posts WHERE id = ? AND deleted = 0', { postId }) then return Veyl.Err('NOT_FOUND', 'This post was removed') end
    if on then MySQL.query.await('INSERT IGNORE INTO veyl_phone_flock_likes (post_id, citizenid) VALUES (?, ?)', { postId, citizenid })
    else MySQL.update.await('DELETE FROM veyl_phone_flock_likes WHERE post_id = ? AND citizenid = ?', { postId, citizenid }) end
    MySQL.update.await('UPDATE veyl_phone_flock_posts SET likes = (SELECT COUNT(*) FROM veyl_phone_flock_likes WHERE post_id = ?) WHERE id = ?', { postId, postId })
    local likes = MySQL.scalar.await('SELECT likes FROM veyl_phone_flock_posts WHERE id = ?', { postId }) or 0
    return Veyl.Ok({ likes = likes, liked = on == true })
end, { cooldown = 150 })

--- flockDelete(postId): your own post, or any post for staff.
Account('flockDelete', function(src, citizenid, postId)
    if not Veyl.Validate.int(postId, 1) then return Veyl.Err('INVALID_INPUT', 'Invalid post') end
    local p = MySQL.single.await('SELECT citizenid, reply_to FROM veyl_phone_flock_posts WHERE id = ? AND deleted = 0', { postId })
    if not p then return Veyl.Err('NOT_FOUND', 'Post not found') end
    local staff = p.citizenid ~= citizenid and isStaff(src)
    if p.citizenid ~= citizenid and not staff then return Veyl.Err('NO_PERMISSION', 'You can only delete your own posts') end
    MySQL.update.await('UPDATE veyl_phone_flock_posts SET deleted = 1 WHERE id = ?', { postId })
    if p.reply_to then
        MySQL.update.await([[UPDATE veyl_phone_flock_posts SET replies = (SELECT COUNT(*) FROM (SELECT id FROM veyl_phone_flock_posts
            WHERE reply_to = ? AND deleted = 0) t) WHERE id = ?]], { p.reply_to, p.reply_to })
    end
    if staff then Veyl.Audit(src, 'flock_remove', { post = postId, author = p.citizenid }) end
    return Veyl.Ok(nil, 'Post deleted')
end, { cooldown = 300 })

--- flockFollow(handle, on)
Account('flockFollow', function(src, citizenid, handle, on)
    if not profileOf(citizenid) then return Veyl.Err('NO_PROFILE', 'Pick a handle first') end
    if type(handle) ~= 'string' or not handle:match('^[%w_]+$') then return Veyl.Err('INVALID_INPUT', 'Invalid handle') end
    local target = MySQL.scalar.await('SELECT citizenid FROM veyl_phone_flock_profiles WHERE handle = ?', { handle:lower() })
    if not target then return Veyl.Err('NOT_FOUND', 'No one is using @' .. handle) end
    if target == citizenid then return Veyl.Err('INVALID_INPUT', 'You cannot follow yourself') end
    if on then
        MySQL.query.await('INSERT IGNORE INTO veyl_phone_flock_follows (follower, followee) VALUES (?, ?)', { citizenid, target })
    else
        MySQL.update.await('DELETE FROM veyl_phone_flock_follows WHERE follower = ? AND followee = ?', { citizenid, target })
    end
    return Veyl.Ok({ following = on == true, counts = counts(target) })
end, { cooldown = 300 })
