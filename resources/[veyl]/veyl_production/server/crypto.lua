-- Hashing for account passwords and PINs. Pure Lua 5.4 SHA-256, salted and stretched. Nothing readable is ever stored.
-- (A 4-digit PIN can always be guessed offline; the real protection is the attempt limit in security.lua.)

Crypto = {}

local K = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}
local M = 0xffffffff
local function rr(x, n) return ((x >> n) | (x << (32 - n))) & M end

--- SHA-256 of a string, as 64 lowercase hex characters.
function Crypto.Sha256(msg)
    local h0, h1, h2, h3, h4, h5, h6, h7 = 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    local len = #msg
    msg = msg .. '\128' .. string.rep('\0', (55 - len) % 64) .. string.pack('>I8', len * 8)
    for i = 1, #msg, 64 do
        local w = { string.unpack('>I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4', msg, i) }
        for t = 17, 64 do
            local x, y = w[t - 15], w[t - 2]
            local s0 = rr(x, 7) ~ rr(x, 18) ~ (x >> 3)
            local s1 = rr(y, 17) ~ rr(y, 19) ~ (y >> 10)
            w[t] = (w[t - 16] + s0 + w[t - 7] + s1) & M
        end
        local a, b, c, d, e, f, g, h = h0, h1, h2, h3, h4, h5, h6, h7
        for t = 1, 64 do
            local S1 = rr(e, 6) ~ rr(e, 11) ~ rr(e, 25)
            local ch = (e & f) ~ ((~e & M) & g)
            local t1 = (h + S1 + ch + K[t] + w[t]) & M
            local S0 = rr(a, 2) ~ rr(a, 13) ~ rr(a, 22)
            local maj = (a & b) ~ (a & c) ~ (b & c)
            local t2 = (S0 + maj) & M
            h, g, f, e, d, c, b, a = g, f, e, (d + t1) & M, c, b, a, (t1 + t2) & M
        end
        h0, h1, h2, h3 = (h0 + a) & M, (h1 + b) & M, (h2 + c) & M, (h3 + d) & M
        h4, h5, h6, h7 = (h4 + e) & M, (h5 + f) & M, (h6 + g) & M, (h7 + h) & M
    end
    return ('%08x%08x%08x%08x%08x%08x%08x%08x'):format(h0, h1, h2, h3, h4, h5, h6, h7)
end

local ROUNDS = 1000
local function stretch(secret, salt, rounds)
    local h = Crypto.Sha256(salt .. ':' .. secret)
    for _ = 2, rounds do h = Crypto.Sha256(h .. salt .. secret) end
    return h
end

math.randomseed(os.time() + (GetGameTimer and GetGameTimer() or 0))
local function salt()
    local t = {}
    for i = 1, 24 do t[i] = ('%x'):format(math.random(0, 15)) end
    return table.concat(t)
end

--- 's1$rounds$salt$hash' for a secret (password or PIN).
function Crypto.Hash(secret)
    local s = salt()
    return ('s1$%d$%s$%s'):format(ROUNDS, s, stretch(secret, s, ROUNDS))
end

local function same(a, b)
    if #a ~= #b then return false end
    local diff = 0
    for i = 1, #a do diff = diff | (a:byte(i) ~ b:byte(i)) end
    return diff == 0
end

function Crypto.Verify(secret, stored)
    if type(secret) ~= 'string' or type(stored) ~= 'string' then return false end
    local rounds, s, hex = stored:match('^s1%$(%d+)%$(%x+)%$(%x+)$')
    if not rounds then return false end
    return same(stretch(secret, s, tonumber(rounds)), hex)
end
