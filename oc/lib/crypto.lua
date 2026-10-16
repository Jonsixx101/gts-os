-- ======================================================================
-- GTS OS (OpenComputers) - crypto: SHA-256 und Pruefsummen
-- ======================================================================
-- Die Data Card rechnet SHA-256 schnell, kostet aber Strom aus dem
-- Puffer des Rechners (6 + 0,1 je Byte). Ein Rechner ohne Capacitor hat
-- nur 500 im Puffer - eine 45-KB-Datei kostet ~4500 und die Karte wirft
-- "not enough energy". Darum: Karte versuchen, sonst dasselbe in Lua.
-- Beide Wege liefern dasselbe Ergebnis (echtes SHA-256).
-- Laeuft auch auf Knoten (ohne OpenOS): darum component/require vorsichtig.
return function()
local component = component or require("component")
local Cr = { card = 0, lua = 0, fails = 0, why = nil }

local bit = bit32
if not bit and require then local ok, b = pcall(require, "bit32") if ok then bit = b end end
local band, bor, bxor, bnot, rshift, rrot
if bit then
    band, bor, bxor, bnot, rshift, rrot = bit.band, bit.bor, bit.bxor, bit.bnot, bit.rshift, bit.rrotate
else
    -- Lua 5.3 ohne bit32: native Operatoren (als Text, damit 5.2 den Code lesen kann)
    local f = load([[
        local M = 0xffffffff
        return function(a, b) return a & b end, function(a, b) return a | b end,
            function(a, b, c) if c then return a ~ b ~ c end return a ~ b end,
            function(a) return ~a & M end, function(a, n) return (a & M) >> n end,
            function(a, n) a = a & M return ((a >> n) | (a << (32 - n))) & M end]])
    band, bor, bxor, bnot, rshift, rrot = f()
end

local KT = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}
local M32 = 4294967296

local function be32(v)
    return string.char(band(rshift(v, 24), 255), band(rshift(v, 16), 255), band(rshift(v, 8), 255), band(v, 255))
end

-- reines Lua-SHA-256 (Ergebnis: 32 Byte)
function Cr.luaSha256(msg)
    local ml = #msg
    local bits = ml * 8
    msg = msg .. "\128" .. string.rep("\0", (55 - ml) % 64)
        .. be32(math.floor(bits / M32)) .. be32(bits % M32)
    local h1, h2, h3, h4 = 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a
    local h5, h6, h7, h8 = 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19
    local w = {}
    for p = 1, #msg, 64 do
        for i = 0, 15 do
            local a, b, c, d = msg:byte(p + i * 4, p + i * 4 + 3)
            w[i] = ((a * 256 + b) * 256 + c) * 256 + d
        end
        for i = 16, 63 do
            local x, y = w[i - 15], w[i - 2]
            local s0 = bxor(rrot(x, 7), rrot(x, 18), rshift(x, 3))
            local s1 = bxor(rrot(y, 17), rrot(y, 19), rshift(y, 10))
            w[i] = (w[i - 16] + s0 + w[i - 7] + s1) % M32
        end
        local a, b, c, d, e, f, g, hh = h1, h2, h3, h4, h5, h6, h7, h8
        for i = 0, 63 do
            local S1 = bxor(rrot(e, 6), rrot(e, 11), rrot(e, 25))
            local ch = bxor(band(e, f), band(bnot(e), g))
            local t1 = (hh + S1 + ch + KT[i + 1] + w[i]) % M32
            local S0 = bxor(rrot(a, 2), rrot(a, 13), rrot(a, 22))
            local maj = bxor(band(a, b), band(a, c), band(b, c))
            hh, g, f, e, d, c, b, a = g, f, e, (d + t1) % M32, c, b, a, (t1 + S0 + maj) % M32
        end
        h1, h2, h3, h4 = (h1 + a) % M32, (h2 + b) % M32, (h3 + c) % M32, (h4 + d) % M32
        h5, h6, h7, h8 = (h5 + e) % M32, (h6 + f) % M32, (h7 + g) % M32, (h8 + hh) % M32
    end
    return be32(h1) .. be32(h2) .. be32(h3) .. be32(h4) .. be32(h5) .. be32(h6) .. be32(h7) .. be32(h8)
end

-- Ausgabe der Karte vereinheitlichen (Text mit 32 Byte; Byte-Tabelle wird zu Text)
local function normal(h)
    if type(h) == "string" and #h == 32 then return h end
    if type(h) == "table" and #h == 32 then
        local ok, s = pcall(function()
            local t = {}
            for i = 1, 32 do t[i] = string.char(h[i] % 256) end
            return table.concat(t)
        end)
        if ok then return s end
    end
end

local cardAddr, cardProxy
local function card()
    if Cr.off then return nil end
    local addr = component.list("data")()
    if addr ~= cardAddr then cardAddr, cardProxy = addr, addr and component.proxy(addr) end
    return cardProxy
end

-- SHA-256: erst die Data Card, sonst Lua. Ergebnis: 32 Byte
function Cr.sha256(s)
    s = tostring(s)
    local d = card()
    if d and #s <= 8192 then
        local ok, h = pcall(d.sha256, s)
        local r = ok and normal(h)
        if r then Cr.card = Cr.card + 1 return r end
        Cr.fails = Cr.fails + 1
        Cr.why = ok and ("Antwort: " .. type(h)) or tostring(h)
    end
    Cr.lua = Cr.lua + 1
    return Cr.luaSha256(s)
end

local HEX = {}
for i = 0, 255 do HEX[string.char(i)] = string.format("%02x", i) end
function Cr.hex(s) return (s:gsub(".", HEX)) end
function Cr.unhex(h) return (h:gsub("%x%x", function(x) return string.char(tonumber(x, 16)) end)) end
function Cr.sha256hex(s) return Cr.hex(Cr.sha256(s)) end

-- Adler-32 (Pruefsumme fuer Downloads; schnell, ohne Data Card)
function Cr.adler(s)
    local a, b = 1, 0
    local n = #s
    for i = 1, n, 2048 do
        local j = math.min(n, i + 2047)
        for k = i, j do
            a = a + s:byte(k)
            b = b + a
        end
        a, b = a % 65521, b % 65521
    end
    return string.format("%08x", b * 65536 + a)
end

-- Selbsttest: Karte und Lua gegen bekannte Werte
local ABC = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
function Cr.selftest()
    local r = { lua = Cr.hex(Cr.luaSha256("abc")) == ABC }
    local d = card()
    if not d then r.card = "fehlt"
    else
        local ok, h = pcall(d.sha256, "abc")
        local n = ok and normal(h)
        if not ok then r.card = "Fehler: " .. tostring(h)
        elseif not n then r.card = "liefert " .. type(h)
        elseif Cr.hex(n) ~= ABC then r.card = "falsches Ergebnis"
        else r.card = "ok" end
    end
    Cr.test = r
    return r
end

return Cr
end
