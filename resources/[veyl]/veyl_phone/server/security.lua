-- Phone security: the account (email + password, like an Apple ID) and the 4-digit PIN lock.
--
--  * A phone with a PIN is LOCKED each time it is opened (after a short grace period): the server then refuses every
--    request except answering calls until the PIN is entered. The UI cannot get around this.
--  * Wrong guesses are limited (PhoneConfig.Lock) and the lockout is stored in the database, so a restart does not reset it.
--  * The account's password can reset a forgotten PIN. Without an account, staff can: /phonepinreset <citizenid>.
--  * Passwords and PINs are salted and hashed (crypto.lua); nothing readable is stored.

Security = {}
local A, L = PhoneConfig.Account, PhoneConfig.Lock
local RESERVED = { admin = true, administrator = true, support = true, staff = true, police = true, ems = true, veyl = true, system = true, noreply = true, postmaster = true, abuse = true, root = true, help = true }

local COLS = 'email, pass_hash, pin_hash, pin_fails, pin_locked_until, pass_fails, pass_locked_until, setup_done'
local function row(cid) return MySQL.single.await(('SELECT %s FROM veyl_ph_accounts WHERE citizenid = ?'):format(COLS), { cid }) end

local function waitText(sec)
    if sec >= 120 then return ('%d minutes'):format(math.ceil(sec / 60)) end
    return ('%d seconds'):format(math.max(1, sec))
end

--- Checks a PIN ('pin') or password ('pass') with the attempt limit. Returns true, or false + an error response.
local function verify(kind, cid, secret)
    local r = row(cid)
    if not r then return false, Veyl.Err('NOT_FOUND', 'No account') end
    local wait = (r[kind .. '_locked_until'] or 0) - os.time()
    if wait > 0 then return false, Veyl.Err('LOCKED_OUT', ('Too many attempts. Try again in %s.'):format(waitText(wait)), { seconds = wait }) end
    local hash = r[kind .. '_hash']
    if type(hash) ~= 'string' or hash == '' then return false, Veyl.Err('NOT_SET', kind == 'pin' and 'No PIN is set' or 'No account is set up') end
    if Crypto.Verify(secret, hash) then
        if (r[kind .. '_fails'] or 0) > 0 then MySQL.update.await(('UPDATE veyl_ph_accounts SET %s_fails = 0 WHERE citizenid = ?'):format(kind), { cid }) end
        return true
    end
    local fails = (r[kind .. '_fails'] or 0) + 1
    if fails >= L.MaxAttempts then
        MySQL.update.await(('UPDATE veyl_ph_accounts SET %s_fails = 0, %s_locked_until = ? WHERE citizenid = ?'):format(kind, kind), { os.time() + L.LockoutSeconds, cid })
        return false, Veyl.Err('LOCKED_OUT', ('Too many attempts. Try again in %s.'):format(waitText(L.LockoutSeconds)), { seconds = L.LockoutSeconds })
    end
    MySQL.update.await(('UPDATE veyl_ph_accounts SET %s_fails = ? WHERE citizenid = ?'):format(kind), { fails, cid })
    return false, Veyl.Err(kind == 'pin' and 'WRONG_PIN' or 'WRONG_PASSWORD', kind == 'pin' and 'Wrong PIN' or 'Wrong password', { left = L.MaxAttempts - fails })
end

local function validPin(pin) return type(pin) == 'string' and pin:match('^%d%d%d%d$') ~= nil end
local function validPassword(pw, username)
    if type(pw) ~= 'string' or #pw < A.PasswordMin or #pw > 64 or pw:find('%c') then
        return false, ('Use %d to 64 characters for your password'):format(A.PasswordMin)
    end
    if username and pw:lower() == username then return false, 'Your password cannot be your email name' end
    return true
end

--- Normalises and validates the part before the @. Returns name, or nil + reason.
local function cleanUsername(u)
    if type(u) ~= 'string' then return nil, 'Enter a name for your email' end
    u = u:lower():gsub('%s+', '')
    if #u < A.UsernameMin or #u > A.UsernameMax then return nil, ('Use %d to %d characters'):format(A.UsernameMin, A.UsernameMax) end
    if not u:match('^[a-z0-9][a-z0-9._]*[a-z0-9]$') or u:find('%.%.') or u:find('__') then return nil, 'Use letters, numbers, dots and underscores' end
    if RESERVED[u] then return nil, 'That name is not available' end
    return u
end
local function taken(email) return MySQL.scalar.await('SELECT 1 FROM veyl_ph_accounts WHERE email = ?', { email }) ~= nil end

local function session(src)
    local s = Phone.Session(src)
    if not s then return nil, Veyl.Err('NO_SESSION', 'Open your phone first') end
    return s
end

---------------------------------------------------------------------------
-- Lock / unlock
---------------------------------------------------------------------------
--- unlock(pin) -> the full `hello` data
Veyl.RegisterCallback('unlock', function(src, citizenid, pin)
    local s, err = session(src)
    if not s then return err end
    if not s.hasPin then s.locked = false return Veyl.Ok(Phone.HelloFor(src)) end
    if not validPin(pin) then return Veyl.Err('INVALID_INPUT', 'Enter your 4-digit PIN') end
    local ok, e = verify('pin', citizenid, pin)
    if not ok then return e end
    s.locked, s.unlockedUntil = false, os.time() + 86400 * 365
    return Veyl.Ok(Phone.HelloFor(src))
end, { cooldown = 300 })

--- lock(): the client calls this when the phone is put away. With a PIN, the next open asks for it (after the grace period).
Veyl.RegisterCallback('lock', function(src)
    local s = Phone.Session(src)
    if not s or not s.hasPin then return Veyl.Ok(nil) end
    s.unlockedUntil = os.time() + L.GraceSeconds
    if L.GraceSeconds <= 0 then s.locked = true end
    return Veyl.Ok(nil)
end, { cooldown = 100 })

---------------------------------------------------------------------------
-- PIN
---------------------------------------------------------------------------
local function savePin(cid, pin)
    MySQL.update.await('UPDATE veyl_ph_accounts SET pin_hash = ?, pin_fails = 0, pin_locked_until = 0 WHERE citizenid = ?', { pin and Crypto.Hash(pin) or nil, cid })
end

--- pinSet({ pin, current? }): set a PIN, or change it (current PIN required when one is set)
Veyl.RegisterCallback('pinSet', function(src, citizenid, input)
    local s, err = session(src)
    if not s then return err end
    input = type(input) == 'table' and input or {}
    if not validPin(input.pin) then return Veyl.Err('INVALID_INPUT', 'A PIN is 4 digits') end
    if s.hasPin then
        local ok, e = verify('pin', citizenid, input.current)
        if not ok then return e end
    end
    savePin(citizenid, input.pin)
    s.hasPin, s.locked, s.unlockedUntil = true, false, os.time() + 86400 * 365
    return Veyl.Ok({ hasPin = true }, 'PIN saved')
end, { cooldown = 500 })

--- pinRemove(current)
Veyl.RegisterCallback('pinRemove', function(src, citizenid, current)
    local s, err = session(src)
    if not s then return err end
    if not s.hasPin then return Veyl.Ok({ hasPin = false }) end
    local ok, e = verify('pin', citizenid, current)
    if not ok then return e end
    savePin(citizenid, nil)
    s.hasPin, s.locked, s.unlockedUntil = false, false, nil
    return Veyl.Ok({ hasPin = false }, 'PIN turned off')
end, { cooldown = 500 })

--- pinReset({ password, pin }): forgot the PIN. The account password proves it is you; sets a new PIN and unlocks.
Veyl.RegisterCallback('pinReset', function(src, citizenid, input)
    local s, err = session(src)
    if not s then return err end
    input = type(input) == 'table' and input or {}
    if not s.email then return Veyl.Err('NO_ACCOUNT', 'This phone has no account. Ask staff to reset your PIN.') end
    if not validPin(input.pin) then return Veyl.Err('INVALID_INPUT', 'A PIN is 4 digits') end
    local ok, e = verify('pass', citizenid, input.password)
    if not ok then return e end
    savePin(citizenid, input.pin)
    s.hasPin, s.locked, s.unlockedUntil = true, false, os.time() + 86400 * 365
    return Veyl.Ok(Phone.HelloFor(src), 'PIN reset')
end, { cooldown = 800 })

---------------------------------------------------------------------------
-- Account
---------------------------------------------------------------------------
--- accountCheck(name) -> { ok, email, reason? }  (live feedback while typing)
Veyl.RegisterCallback('accountCheck', function(src, _, name)
    if not session(src) then return Veyl.Err('NO_SESSION', 'Open your phone first') end
    local u, why = cleanUsername(name)
    if not u then return Veyl.Ok({ available = false, reason = why }) end
    local email = u .. '@' .. A.Domain
    if taken(email) then return Veyl.Ok({ available = false, email = email, reason = 'That email is taken' }) end
    return Veyl.Ok({ available = true, email = email })
end, { cooldown = 250 })

--- accountCreate({ username, password }) -> { email }
Veyl.RegisterCallback('accountCreate', function(src, citizenid, input)
    local s, err = session(src)
    if not s then return err end
    if s.email then return Veyl.Err('ALREADY_EXISTS', 'This phone already has an account') end
    input = type(input) == 'table' and input or {}
    local u, why = cleanUsername(input.username)
    if not u then return Veyl.Err('INVALID_INPUT', why) end
    local okPw, whyPw = validPassword(input.password, u)
    if not okPw then return Veyl.Err('INVALID_INPUT', whyPw) end
    if not Phone.Rate(src, 'account', 2000) then return Veyl.Err('RATE_LIMITED', 'Slow down') end
    local email = u .. '@' .. A.Domain
    local done = pcall(function()
        MySQL.update.await('UPDATE veyl_ph_accounts SET email = ?, pass_hash = ?, pass_fails = 0, pass_locked_until = 0 WHERE citizenid = ? AND email IS NULL', { email, Crypto.Hash(input.password), citizenid })
    end)
    if not done or row(citizenid).email ~= email then return Veyl.Err('ALREADY_EXISTS', 'That email is taken') end
    s.email = email
    if Mail and Mail.Send then
        Mail.Send(citizenid, 'Veyl ID', 'Welcome to your Veyl ID', ('Your account is ready.\n\nEmail: %s\n\nUse your password to reset your PIN if you ever forget it. Keep it safe: nobody, including staff, can read it.'):format(email))
    end
    return Veyl.Ok({ email = email }, 'Account created')
end, { cooldown = 800 })

--- passwordChange({ current, new })
Veyl.RegisterCallback('passwordChange', function(src, citizenid, input)
    local s, err = session(src)
    if not s then return err end
    if not s.email then return Veyl.Err('NO_ACCOUNT', 'Create an account first') end
    input = type(input) == 'table' and input or {}
    local okPw, whyPw = validPassword(input.new, s.email:match('^[^@]+'))
    if not okPw then return Veyl.Err('INVALID_INPUT', whyPw) end
    local ok, e = verify('pass', citizenid, input.current)
    if not ok then return e end
    MySQL.update.await('UPDATE veyl_ph_accounts SET pass_hash = ? WHERE citizenid = ?', { Crypto.Hash(input.new), citizenid })
    return Veyl.Ok(nil, 'Password changed')
end, { cooldown = 800 })

--- setupFinish(): the first-run setup was completed or skipped; it is not shown again.
Veyl.RegisterCallback('setupFinish', function(src, citizenid)
    local s, err = session(src)
    if not s then return err end
    MySQL.update.await('UPDATE veyl_ph_accounts SET setup_done = 1 WHERE citizenid = ?', { citizenid })
    s.setupDone = true
    return Veyl.Ok(nil)
end, { cooldown = 300 })

---------------------------------------------------------------------------
-- Staff: reset a forgotten PIN when the character has no account to recover with
---------------------------------------------------------------------------
RegisterCommand('phonepinreset', function(src, args)
    if src ~= 0 and not Veyl.HasPermission(src, 'phone.admin') then return end
    local cid = args[1]
    local say = function(m) if src == 0 then print(m) else Veyl.Notify(src, m) end end
    if not cid then return say('Usage: phonepinreset <citizenid>') end
    local n = MySQL.update.await('UPDATE veyl_ph_accounts SET pin_hash = NULL, pin_fails = 0, pin_locked_until = 0 WHERE citizenid = ?', { cid })
    local s = Phone.byCid[cid]
    if s then s.hasPin, s.locked, s.unlockedUntil = false, false, nil end
    if n > 0 then Veyl.Audit(src, 'phone_pin_reset', { target = cid }) end
    say(n > 0 and ('PIN removed for %s'):format(cid) or 'No phone account for that citizen')
end, true)
