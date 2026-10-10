-- ======================================================================
-- GTS SCHWARM-AGENT v5.1 - Turtle-Client       (CC: Tweaked, MC 1.21.1)
-- Gegenstueck zu GTS OS v7.1 - als startup.lua auf jede Turtle.
-- ======================================================================
-- Der Agent bleibt dauerhaft auf der Turtle. Er
--   - funkt verschluesselt mit dem OS (Schwarm-Passwort wie am OS),
--   - zaehlt die Position mit (oder nutzt GPS, wenn vorhanden),
--   - nimmt Programme vom OS an (DD, CHUNK, TEST) und fuehrt sie aus,
--   - kann sich selbst per Funk aktualisieren (Button UPDATE am OS).
-- Programme liegen am OS in LUA APPS > turtle und werden beim Druck auf
-- DD, CHUNK oder T automatisch uebertragen, wenn die Turtle sie noch
-- nicht oder in einer alten Fassung hat.
--
-- Ausruestung: Spitzhacke + Wireless/Ender Modem (bleibt immer dran).
-- Weitere Werkzeuge einfach ins Inventar legen (Geo Scanner, Environment
-- Detector, Kompass, Chunky ...): sie werden fuer einen Befehl kurz gegen
-- die Spitzhacke getauscht, das Modem bleibt stecken.
--
-- Aufbau:
--   [1] Konfiguration      [7]  Inventar
--   [2] Verschluesselung   [8]  Scanner
--   [3] Position, Daten    [9]  Programme und ihre Schnittstelle T
--   [4] Zustand            [10] Auftraege
--   [5] Navigation         [11] Funk und Ablauf
--   [6] Welt und Funde     [12] Bildschirm und Start
-- ======================================================================

local VERSION = "5.2"

-- ======================================================================
-- [1] KONFIGURATION
-- ======================================================================
local CONFIG = {
    heartbeat    = 2,       -- Sek. zwischen Status-Meldungen
    chunkyEvery  = 240,     -- Chunky spaetestens alle x Sek. kurz anlegen (AP haelt den Chunk 600 s)
    chunkySteps  = 12,      -- ohne Welt-Koordinaten: nach so vielen Schritten waagerecht
    gpsIdle      = 30,      -- GPS-Kontrolle alle x Sek. im Stand ...
    gpsWork      = 20,      -- ... und waehrend eines Auftrags
    gpsRetry     = 120,     -- ohne GPS-Antwort erst nach x Sek. wieder fragen
    refuelTarget = 5000,    -- TANK fuellt bis zu diesem Stand
    dropSide     = "down",  -- Muell werfen nach: "front", "down" oder "up"
    unloadSide   = "front", -- Kiste fuer die Beute an der Basis (bei Blick wie beim Setzen)
    maxQueue     = 8,
    trashAt      = 13,      -- ab so vielen belegten Slots Muell abwerfen
    fuelReserve  = 60,      -- Tank-Reserve zusaetzlich zum Heimweg

    stateFile    = "/.gts_turtle",      -- Position (bei jedem Schritt)
    dataFile     = "/.gts_turtle_data", -- Programm, Funde, Basis-Koordinaten
    keyFile      = "/.gts_schluessel",  -- Funk-Schluessel (aus dem Passwort)
    progDir      = "/gts/prog",         -- vom OS uebertragene Programme
}

-- Wird weggeworfen. Alles mit "_ore" im Namen bleibt immer an Bord.
local TRASH = {
    ["minecraft:cobblestone"] = true, ["minecraft:cobbled_deepslate"] = true,
    ["minecraft:stone"] = true,       ["minecraft:deepslate"] = true,
    ["minecraft:diorite"] = true,     ["minecraft:andesite"] = true,
    ["minecraft:granite"] = true,     ["minecraft:tuff"] = true,
    ["minecraft:calcite"] = true,     ["minecraft:dripstone_block"] = true,
    ["minecraft:pointed_dripstone"] = true, ["minecraft:smooth_basalt"] = true,
    ["minecraft:basalt"] = true,      ["minecraft:dirt"] = true,
    ["minecraft:coarse_dirt"] = true, ["minecraft:rooted_dirt"] = true,
    ["minecraft:grass_block"] = true, ["minecraft:gravel"] = true,
    ["minecraft:flint"] = true,       ["minecraft:sand"] = true,
    ["minecraft:sandstone"] = true,   ["minecraft:clay_ball"] = true,
    ["minecraft:mud"] = true,         ["minecraft:moss_block"] = true,
    ["minecraft:sculk"] = true,       ["minecraft:sculk_vein"] = true,
    ["minecraft:netherrack"] = true,  ["minecraft:gray_wool"] = true,
    ["minecraft:red_sand"] = true,    ["minecraft:terracotta"] = true,
}
-- Zusaetzlich alles, dessen Name einen dieser Teile enthaelt (Ancient-City-Baustoffe).
local TRASH_PARTS = { "deepslate_brick", "deepslate_tile", "polished_deepslate", "cobbled_deepslate", "polished_basalt" }

-- Nur das wird verbrannt (kein Holz, keine Werkzeuge).
local FUEL = {
    ["minecraft:coal"] = true, ["minecraft:charcoal"] = true, ["minecraft:coal_block"] = true,
    ["minecraft:lava_bucket"] = true, ["minecraft:blaze_rod"] = true,
}

-- Bleibt immer an Bord (wird weder weggeworfen noch entladen).
local KEEP_PARTS = { "geo_scanner", "modem", "pickaxe", "chunk_controller", "minecraft:compass",
                     "environment_detector", "player_detector", "chat_box", "computercraft:speaker" }

-- Diese Bloecke baut die Turtle nie ab: andere Turtles, Computer, Lager,
-- Lootr-Kisten und Suspicious Clay/Gravel (Abbauen zerstoert den Inhalt).
local PROTECTED = { "computercraft:", "chest", "barrel", "shulker", "hopper", "furnace", "lootr:", "suspicious", "spawner" }

-- ======================================================================
-- [2] VERSCHLUESSELUNG
-- ======================================================================
-- @@CRYPTO-BEGIN
-- Eingebettet: ccryptolib (github.com/migeyel/ccryptolib), MIT-Lizenz,
-- Copyright (c) 2023 Miguel Oliveira. Unveraendert bis auf die Lade-Huelle.
-- Verwendet: ChaCha20-Poly1305 (Verschluesselung + Echtheit), SHA-256, PBKDF2.
local Crypto = (function()
    local mods, loaded = {}, {}
    local function require(name)
        if name == "cc.expect" then return { expect = function(_, v) return v end } end
        if loaded[name] == nil then loaded[name] = mods[name]() end
        return loaded[name]
    end
    mods["ccryptolib.internal.hw"] = function() return { sha256 = function() return false end } end
    mods["ccryptolib.internal.util"] = function()
        local function lassert(val, err, level)
            if not val then error(err, level + 1) end
            return val
        end

        --- Converts a little-endian array from one power-of-two base to another.
        --- @param a number[] The array to convert, in little-endian.
        --- @param base1 number The base to convert from. Must be a power of 2.
        --- @param base2 number The base to convert to. Must be a power of 2.
        --- @return number[]
        local function rebaseLE(a, base1, base2) -- TODO Write contract properly.
            local out = {}
            local outlen = 1
            local acc = 0
            local mul = 1
            for i = 1, #a do
                acc = acc + a[i] * mul
                mul = mul * base1
                while mul >= base2 do
                    local rem = acc % base2
                    acc = (acc - rem) / base2
                    mul = mul / base2
                    out[outlen] = rem
                    outlen = outlen + 1
                end
            end
            if mul > 0 then
                out[outlen] = acc
            end
            return out
        end

        --- Decodes bits with X25519/Ed25519 exponent clamping.
        --- @param str string The 32-byte encoded exponent.
        --- @return number[] bits The decoded clamped bits.
        local function bits(str)
            -- Decode.
            local bytes = {str:byte(1, 32)}
            local out = {}
            for i = 1, 32 do
                local byte = bytes[i]
                for j = -7, 0 do
                    local bit = byte % 2
                    out[8 * i + j] = bit
                    byte = (byte - bit) / 2
                end
            end

            -- Clamp.
            out[1] = 0
            out[2] = 0
            out[3] = 0
            out[255] = 1
            out[256] = 0

            return out
        end

        --- Decodes bits with X25519/Ed25519 exponent clamping and division by 8.
        --- @param str string The 32-byte encoded exponent.
        --- @return number[] bits The decoded clamped bits, divided by 8.
        local function bits8(str)
            return {unpack(bits(str), 4)}
        end

        return {
            lassert = lassert,
            rebaseLE = rebaseLE,
            bits = bits,
            bits8 = bits8,
        }
    end
    mods["ccryptolib.internal.packing"] = function()
        --- High-performance binary packing of integers.
        ---
        --- Remark (and warning):
        --- For performance reasons, **the generated functions do not check types,
        --- lengths, nor ranges**. You must ensure that the passed arguments are
        --- well-formed and respect the format string yourself.

        local fmt = string.format

        local function mkPack(words, BE)
            local out = "local C=string.char return function(_,"
            local nb = 0
            for i = 1, #words do
                out = out .. fmt("n%d,", i)
                nb = nb + words[i]
            end
            out = out:sub(1, -2) .. ")local "
            for i = 1, nb do
                out = out .. fmt("b%d,", i)
            end
            out = out:sub(1, -2) .. " "
            local bi = 1
            for i = 1, #words do
                for _ = 1, words[i] - 1 do
                    out = out .. fmt("b%d=n%d%%2^8 n%d=(n%d-b%d)*2^-8 ", bi, i, i, i, bi)
                    bi = bi + 1
                end
                bi = bi + 1
            end
            out = out .. "return C("
            bi = 1
            if not BE then
                for i = 1, #words do
                    for _ = 1, words[i] - 1 do
                        out = out .. fmt("b%d,", bi)
                        bi = bi + 1
                    end
                    out = out .. fmt("n%d%%2^8,", i)
                    bi = bi + 1
                end
            else
                for i = 1, #words do
                    out = out .. fmt("n%d%%2^8,", i)
                    bi = bi + words[i] - 2
                    for _ = 1, words[i] - 1 do
                        out = out .. fmt("b%d,", bi)
                        bi = bi - 1
                    end
                    bi = bi + words[i] + 1
                end
            end
            out = out:sub(1, -2) .. ")end"
            return load(out)()
        end

        local function mkUnpack(words, BE)
            local out = "local B=string.byte return function(_,s,i)local "
            local bi = 1
            if not BE then
                for i = 1, #words do
                    for _ = 1, words[i] do
                        out = out .. fmt("b%d,", bi)
                        bi = bi + 1
                    end
                end
            else
                for i = 1, #words do
                    bi = bi + words[i] - 1
                    for _ = 1, words[i] do
                        out = out .. fmt("b%d,", bi)
                        bi = bi - 1
                    end
                    bi = bi + words[i] + 1
                end
            end
            out = out:sub(1, -2) .. fmt("=B(s,i,i+%d)return ", bi - 2)
            bi = 1
            for i = 1, #words do
                out = out .. fmt("b%d", bi)
                bi = bi + 1
                for j = 2, words[i] do
                    out = out .. fmt("+b%d*2^%d", bi, 8 * j - 8)
                    bi = bi + 1
                end
                out = out .. ","
            end
            out = out .. fmt("i+%d end", bi - 1)
            return load(out)()
        end

        -- Check whether string.pack is implemented in a high-speed language.
        if not string.pack or pcall(string.dump, string.pack) then
            local function compile(fmt, fn)
                local e = assert(fmt:match("^([><])I[I%d]+$"), "invalid format string")
                local w = {}
                for i in fmt:gmatch("I([%d]+)") do
                    local n = tonumber(i) or 4
                    assert(n > 0 and n <= 16, "integral size out of limits")
                    w[#w + 1] = n
                end
                return fn(w, e == ">")
            end

            local packCache = {}
            local unpackCache = {}

            -- I CAN'T EVEN WITH THIS EXTENSION, WHY CAN'T IT HANDLE MORE THAN A SINGLE
            -- LINE OF RETURN DESCRIPTION? LOOK AT IT!!! THE COMMENT GOES OVER THERE ------------------------------------------------------------------> look! ? ? ?

            --- (string.pack is nil) Compiles a binary packing function.
            ---
            --- Errors if the format string is invalid or has an invalid integral size,
            --- or if the compiled function turns out too large.
            ---
            --- @param fmt string A string matched by `^([><])I[I%d]+$`.
            --- @return fun(_ignored: any, ...: any): string pack A function that behaves like an unsafe version of `string.pack` for the given format string.
            --- @return string fmt
            local function compilePack(fmt)
                if not packCache[fmt] then
                    packCache[fmt] = compile(fmt, mkPack)
                end
                return packCache[fmt], fmt
            end

            --- (string.pack is nil) Compiles a binary unpacking function.
            ---
            --- Errors if the format string is invalid or has an invalid integral size,
            --- or if the compiled function turns out too large.
            ---
            --- @param fmt string A string matched by `^([><])I[I%d]+$`.
            --- @return fun(_ignored: any, str: string, pos: number) unpack A function that behaves like an unsafe version of `string.unpack` for the given format string. Note that the third argument isn't optional.
            --- @return string fmt
            local function compileUnpack(fmt)
                if not unpackCache[fmt] then
                    unpackCache[fmt] = compile(fmt, mkUnpack)
                end
                return unpackCache[fmt], fmt
            end

            return {
                compilePack = compilePack,
                compileUnpack = compileUnpack,
            }
        else
            --- (string.pack isn't nil) It's string.pack! It returns string.pack!
            --- @param fmt string
            --- @return fun(fmt: string, ...: any): string pack string.pack!
            --- @return string fmt
            local function compilePack(fmt) return string.pack, fmt end

            --- (string.pack isn't nil) It's string.unpack! It returns string.unpack!
            --- @param fmt string
            --- @return fun(fmt: string, str: string, pos: number) unpack string.unpack!
            --- @return string fmt
            local function compileUnpack(fmt) return string.unpack, fmt end

            return {
                compilePack = compilePack,
                compileUnpack = compileUnpack,
            }
        end
    end
    mods["ccryptolib.sha256"] = function()
        --- The SHA256 cryptographic hash function.

        local expect = require "cc.expect".expect
        local lassert = require "ccryptolib.internal.util".lassert
        local packing = require "ccryptolib.internal.packing"
        local hw = require "ccryptolib.internal.hw"

        local rol = bit32.lrotate
        local shr = bit32.rshift
        local bxor = bit32.bxor
        local bnot = bit32.bnot
        local band = bit32.band
        local unpack = unpack or table.unpack
        local p1x8, fmt1x8 = packing.compilePack(">I8")
        local p16x4, fmt16x4 = packing.compilePack(">I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4")
        local u16x4 = packing.compileUnpack(fmt16x4)
        local p8x4, fmt8x4 = packing.compilePack(">I4I4I4I4I4I4I4I4")
        local u8x4 = packing.compileUnpack(fmt8x4)

        local function primes(n, exp)
            local out = {}
            local p = 2
            for i = 1, n do
                out[i] = bxor(math.floor(p ^ exp % 1 * 2 ^ 32))
                repeat
                    p = p + 1
                    local prime = true
                    for q = 2, math.floor(math.sqrt(p)) do if p % q == 0 then prime = false break end end
                until prime
            end
            return out
        end

        local K = primes(64, 1 / 3)

        local h0 = primes(8, 1 / 2)

        local function compress(h, w)
            local h0, h1, h2, h3, h4, h5, h6, h7 = unpack(h)
            local K = K

            -- Message schedule.
            for j = 17, 64 do
                local wf = w[j - 15]
                local w2 = w[j - 2]
                local s0 = bxor(rol(wf, 25), rol(wf, 14), shr(wf, 3))
                local s1 = bxor(rol(w2, 15), rol(w2, 13), shr(w2, 10))
                w[j] = w[j - 16] + s0 + w[j - 7] + s1
            end

            -- Block.
            local a, b, c, d, e, f, g, h = h0, h1, h2, h3, h4, h5, h6, h7
            for j = 1, 64 do
                local s1 = bxor(rol(e, 26), rol(e, 21), rol(e, 7))
                local ch = bxor(band(e, f), band(bnot(e), g))
                local temp1 = h + s1 + ch + K[j] + w[j]
                local s0 = bxor(rol(a, 30), rol(a, 19), rol(a, 10))
                local maj = bxor(band(a, b), band(a, c), band(b, c))
                local temp2 = s0 + maj

                h = g
                g = f
                f = e
                e = d + temp1
                d = c
                c = b
                b = a
                a = temp1 + temp2
            end

            return {
                (h0 + a) % 2 ^ 32,
                (h1 + b) % 2 ^ 32,
                (h2 + c) % 2 ^ 32,
                (h3 + d) % 2 ^ 32,
                (h4 + e) % 2 ^ 32,
                (h5 + f) % 2 ^ 32,
                (h6 + g) % 2 ^ 32,
                (h7 + h) % 2 ^ 32,
            }
        end

        --- Hashes data using SHA256.
        --- @param data string Input bytes.
        --- @return string hash The 32-byte hash value.
        local function digest(data)
            expect(1, data, "string")
            local ok, out = hw.sha256(data)
            if ok then return out end

            -- Pad input.
            local bitlen = #data * 8
            local padlen = -(#data + 9) % 64
            data = data .. "\x80" .. ("\0"):rep(padlen) .. p1x8(fmt1x8, bitlen)

            -- Digest.
            local h = h0
            for i = 1, #data, 64 do
                h = compress(h, {u16x4(fmt16x4, data, i)})
            end

            return p8x4(fmt8x4, unpack(h))
        end

        -- Reports once every ~10ms on a standard CCEmuX emulator.
        local PBKDF2_CB_ITERATIONS = 50

        --- Hashes a password using PBKDF2-HMAC-SHA256.
        --- @param password string The password to hash.
        --- @param salt string The password's salt.
        --- @param iter number The number of iterations to perform.
        --- @param progress fun(iter: number)? An optional function to periodically call with the current iteration number as argument.
        --- @return string dk The 32-byte derived key.
        local function pbkdf2(password, salt, iter, progress)
            expect(1, password, "string")
            expect(2, salt, "string")
            expect(3, iter, "number")
            lassert(iter % 1 == 0, "iteration number must be an integer", 2)
            lassert(iter > 0, "iteration number must be positive", 2)
            expect(4, progress, "function", "nil")

            -- Pad password.
            if #password > 64 then password = digest(password) end
            password = {u16x4(fmt16x4, password .. ("\0"):rep(64), 1)}

            -- Compute password blocks.
            local ikp = {}
            local okp = {}
            for i = 1, 16 do
                ikp[i] = bxor(password[i], 0x36363636)
                okp[i] = bxor(password[i], 0x5c5c5c5c)
            end

            local hikp = compress(h0, ikp)
            local hokp = compress(h0, okp)

            -- 96-byte padding.
            local pad96 = {2 ^ 31, 0, 0, 0, 0, 0, 0, 0x300}

            -- First iteration.
            local pre = p16x4(fmt16x4, unpack(ikp))
            local hs = {u8x4(fmt8x4, digest(pre .. salt .. "\0\0\0\1"), 1)}
            for i = 1, 8 do hs[i + 8] = pad96[i] end
            hs = compress(hokp, hs)

            -- Second iteration onwards.
            local out = {unpack(hs)}
            for i = 2, iter do
                for j = 1, 8 do hs[j + 8] = pad96[j] end
                hs = compress(hikp, hs)
                for j = 1, 8 do hs[j + 8] = pad96[j] end
                hs = compress(hokp, hs)
                for j = 1, 8 do out[j] = bxor(out[j], hs[j]) end
                if progress and i % PBKDF2_CB_ITERATIONS == 0 then progress(i) end
            end

            return p8x4(fmt8x4, unpack(out))
        end

        return {
            digest = digest,
            pbkdf2 = pbkdf2,
        }
    end
    mods["ccryptolib.chacha20"] = function()
        --- The ChaCha20 stream cipher.

        local expect  = require "cc.expect".expect
        local lassert = require "ccryptolib.internal.util".lassert
        local packing = require "ccryptolib.internal.packing"

        local bxor = bit32.bxor
        local rol = bit32.lrotate
        local u8x4, fmt8x4 = packing.compileUnpack("<I4I4I4I4I4I4I4I4")
        local u3x4, fmt3x4 = packing.compileUnpack("<I4I4I4")
        local p16x4, fmt16x4 = packing.compilePack("<I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4I4")
        local u16x4 = packing.compileUnpack(fmt16x4)

        --- Encrypts/Decrypts data using ChaCha20.
        --- @param key string A 32-byte random key.
        --- @param nonce string A 12-byte per-message unique nonce.
        --- @param message string A plaintext or ciphertext.
        --- @param rounds number? The number of ChaCha20 rounds to use. Defaults to 20.
        --- @param offset number? The block offset to generate the keystream at. Defaults to 1.
        --- @return string out The resulting ciphertext or plaintext.
        local function crypt(key, nonce, message, rounds, offset)
            expect(1, key, "string")
            lassert(#key == 32, "key length must be 32", 2)
            expect(2, nonce, "string")
            lassert(#nonce == 12, "nonce length must be 12", 2)
            expect(3, message, "string")
            rounds = expect(4, rounds, "number", "nil") or 20
            lassert(rounds % 2 == 0, "round number must be even", 2)
            lassert(rounds >= 8, "round number must be no smaller than 8", 2)
            lassert(rounds <= 20, "round number must be no larger than 20", 2)
            offset = expect(5, offset, "number", "nil") or 1
            lassert(offset % 1 == 0, "offset must be an integer", 2)
            lassert(offset >= 0, "offset must be nonnegative", 2)
            lassert(#message + 64 * offset <= 2 ^ 38, "offset too large", 2)

            -- Build the state block.
            local i0, i1, i2, i3 = 0x61707865, 0x3320646e, 0x79622d32, 0x6b206574
            local k0, k1, k2, k3, k4, k5, k6, k7 = u8x4(fmt8x4, key, 1)
            local cr, n0, n1, n2 = offset, u3x4(fmt3x4, nonce, 1)

            -- Pad the message.
            local padded = message .. ("\0"):rep(-#message % 64)

            -- Expand and combine.
            local out = {}
            local idx = 1
            for i = 1, #padded / 64 do
                -- Copy the block.
                local s00, s01, s02, s03 = i0, i1, i2, i3
                local s04, s05, s06, s07 = k0, k1, k2, k3
                local s08, s09, s10, s11 = k4, k5, k6, k7
                local s12, s13, s14, s15 = cr, n0, n1, n2

                -- Iterate.
                for _ = 1, rounds, 2 do
                    s00 = s00 + s04 s12 = rol(bxor(s12, s00), 16)
                    s08 = s08 + s12 s04 = rol(bxor(s04, s08), 12)
                    s00 = s00 + s04 s12 = rol(bxor(s12, s00), 8)
                    s08 = s08 + s12 s04 = rol(bxor(s04, s08), 7)

                    s01 = s01 + s05 s13 = rol(bxor(s13, s01), 16)
                    s09 = s09 + s13 s05 = rol(bxor(s05, s09), 12)
                    s01 = s01 + s05 s13 = rol(bxor(s13, s01), 8)
                    s09 = s09 + s13 s05 = rol(bxor(s05, s09), 7)

                    s02 = s02 + s06 s14 = rol(bxor(s14, s02), 16)
                    s10 = s10 + s14 s06 = rol(bxor(s06, s10), 12)
                    s02 = s02 + s06 s14 = rol(bxor(s14, s02), 8)
                    s10 = s10 + s14 s06 = rol(bxor(s06, s10), 7)

                    s03 = s03 + s07 s15 = rol(bxor(s15, s03), 16)
                    s11 = s11 + s15 s07 = rol(bxor(s07, s11), 12)
                    s03 = s03 + s07 s15 = rol(bxor(s15, s03), 8)
                    s11 = s11 + s15 s07 = rol(bxor(s07, s11), 7)

                    s00 = s00 + s05 s15 = rol(bxor(s15, s00), 16)
                    s10 = s10 + s15 s05 = rol(bxor(s05, s10), 12)
                    s00 = s00 + s05 s15 = rol(bxor(s15, s00), 8)
                    s10 = s10 + s15 s05 = rol(bxor(s05, s10), 7)

                    s01 = s01 + s06 s12 = rol(bxor(s12, s01), 16)
                    s11 = s11 + s12 s06 = rol(bxor(s06, s11), 12)
                    s01 = s01 + s06 s12 = rol(bxor(s12, s01), 8)
                    s11 = s11 + s12 s06 = rol(bxor(s06, s11), 7)

                    s02 = s02 + s07 s13 = rol(bxor(s13, s02), 16)
                    s08 = s08 + s13 s07 = rol(bxor(s07, s08), 12)
                    s02 = s02 + s07 s13 = rol(bxor(s13, s02), 8)
                    s08 = s08 + s13 s07 = rol(bxor(s07, s08), 7)

                    s03 = s03 + s04 s14 = rol(bxor(s14, s03), 16)
                    s09 = s09 + s14 s04 = rol(bxor(s04, s09), 12)
                    s03 = s03 + s04 s14 = rol(bxor(s14, s03), 8)
                    s09 = s09 + s14 s04 = rol(bxor(s04, s09), 7)
                end

                -- Decode message block.
                local m00, m01, m02, m03, m04, m05, m06, m07
                local m08, m09, m10, m11, m12, m13, m14, m15

                m00, m01, m02, m03, m04, m05, m06, m07,
                m08, m09, m10, m11, m12, m13, m14, m15, idx =
                    u16x4(fmt16x4, padded, idx)

                -- Feed-forward and combine.
                out[i] = p16x4(fmt16x4,
                    bxor(m00, s00 + i0), bxor(m01, s01 + i1),
                    bxor(m02, s02 + i2), bxor(m03, s03 + i3),
                    bxor(m04, s04 + k0), bxor(m05, s05 + k1),
                    bxor(m06, s06 + k2), bxor(m07, s07 + k3),
                    bxor(m08, s08 + k4), bxor(m09, s09 + k5),
                    bxor(m10, s10 + k6), bxor(m11, s11 + k7),
                    bxor(m12, s12 + cr), bxor(m13, s13 + n0),
                    bxor(m14, s14 + n1), bxor(m15, s15 + n2)
                )

                -- Increment counter.
                cr = cr + 1
            end

            return table.concat(out):sub(1, #message)
        end

        return {
            crypt = crypt,
        }
    end
    mods["ccryptolib.poly1305"] = function()
        --- The Poly1305 one-time authenticator.

        local expect  = require "cc.expect".expect
        local lassert = require "ccryptolib.internal.util".lassert
        local packing = require "ccryptolib.internal.packing"

        local u4x4, fmt4x4 = packing.compileUnpack("<I4I4I4I4")
        local p4x4 = packing.compilePack(fmt4x4)

        --- Computes a Poly1305 message authentication code.
        --- @param key string A 32-byte single-use random key.
        --- @param message string The message to authenticate.
        --- @return string tag The 16-byte authentication tag.
        local function mac(key, message)
            expect(1, key, "string")
            lassert(#key == 32, "key length must be 32", 2)
            expect(2, message, "string")

            -- Pad message.
            local pbplen = #message - 15
            if #message % 16 ~= 0 or #message == 0 then
                message = message .. "\1"
                message = message .. ("\0"):rep(-#message % 16)
            end

            -- Decode r.
            local R0, R1, R2, R3 = u4x4(fmt4x4, key, 1)

            -- Clamp and shift.
            R0 = R0 % 2 ^ 28
            R1 = (R1 - R1 % 4) % 2 ^ 28 * 2 ^ 32
            R2 = (R2 - R2 % 4) % 2 ^ 28 * 2 ^ 64
            R3 = (R3 - R3 % 4) % 2 ^ 28 * 2 ^ 96

            -- Split.
            local r0 = R0 % 2 ^ 18   local r1 = R0 - r0
            local r2 = R1 % 2 ^ 50   local r3 = R1 - r2
            local r4 = R2 % 2 ^ 82   local r5 = R2 - r4
            local r6 = R3 % 2 ^ 112  local r7 = R3 - r6

            -- Generate scaled key.
            local S1 = 5 / 2 ^ 130 * R1
            local S2 = 5 / 2 ^ 130 * R2
            local S3 = 5 / 2 ^ 130 * R3

            -- Split.
            local s2 = S1 % 2 ^ -80  local s3 = S1 - s2
            local s4 = S2 % 2 ^ -48  local s5 = S2 - s4
            local s6 = S3 % 2 ^ -16  local s7 = S3 - s6

            local h0, h1, h2, h3, h4, h5, h6, h7 = 0, 0, 0, 0, 0, 0, 0, 0

            for i = 1, #message, 16 do
                -- Decode message block.
                local m0, m1, m2, m3 = u4x4(fmt4x4, message, i)

                -- Shift message and add.
                local x0 = h0 + h1 + m0
                local x2 = h2 + h3 + m1 * 2 ^ 32
                local x4 = h4 + h5 + m2 * 2 ^ 64
                local x6 = h6 + h7 + m3 * 2 ^ 96

                -- Apply per-block padding when applicable.
                if i <= pbplen then x6 = x6 + 2 ^ 128 end

                -- Multiply
                h0 = x0 * r0 + x2 * s6 + x4 * s4 + x6 * s2
                h1 = x0 * r1 + x2 * s7 + x4 * s5 + x6 * s3
                h2 = x0 * r2 + x2 * r0 + x4 * s6 + x6 * s4
                h3 = x0 * r3 + x2 * r1 + x4 * s7 + x6 * s5
                h4 = x0 * r4 + x2 * r2 + x4 * r0 + x6 * s6
                h5 = x0 * r5 + x2 * r3 + x4 * r1 + x6 * s7
                h6 = x0 * r6 + x2 * r4 + x4 * r2 + x6 * r0
                h7 = x0 * r7 + x2 * r5 + x4 * r3 + x6 * r1

                -- Carry.
                local y0 = h0 + 3 * 2 ^ 69  - 3 * 2 ^ 69   h0 = h0 - y0  h1 = h1 + y0
                local y1 = h1 + 3 * 2 ^ 83  - 3 * 2 ^ 83   h1 = h1 - y1  h2 = h2 + y1
                local y2 = h2 + 3 * 2 ^ 101 - 3 * 2 ^ 101  h2 = h2 - y2  h3 = h3 + y2
                local y3 = h3 + 3 * 2 ^ 115 - 3 * 2 ^ 115  h3 = h3 - y3  h4 = h4 + y3
                local y4 = h4 + 3 * 2 ^ 133 - 3 * 2 ^ 133  h4 = h4 - y4  h5 = h5 + y4
                local y5 = h5 + 3 * 2 ^ 147 - 3 * 2 ^ 147  h5 = h5 - y5  h6 = h6 + y5
                local y6 = h6 + 3 * 2 ^ 163 - 3 * 2 ^ 163  h6 = h6 - y6  h7 = h7 + y6
                local y7 = h7 + 3 * 2 ^ 181 - 3 * 2 ^ 181  h7 = h7 - y7

                -- Reduce carry overflow into first limb.
                h0 = h0 + 5 / 2 ^ 130 * y7
            end

            -- Carry canonically.
            local c0 = h0 % 2 ^ 16   h1 = h0 - c0 + h1
            local c1 = h1 % 2 ^ 32   h2 = h1 - c1 + h2
            local c2 = h2 % 2 ^ 48   h3 = h2 - c2 + h3
            local c3 = h3 % 2 ^ 64   h4 = h3 - c3 + h4
            local c4 = h4 % 2 ^ 80   h5 = h4 - c4 + h5
            local c5 = h5 % 2 ^ 96   h6 = h5 - c5 + h6
            local c6 = h6 % 2 ^ 112  h7 = h6 - c6 + h7
            local c7 = h7 % 2 ^ 130

            -- Reduce carry overflow.
            h0 = c0 + 5 / 2 ^ 130 * (h7 - c7)
            c0 = h0 % 2 ^ 16
            c1 = h0 - c0 + c1

            -- Canonicalize.
            if      c7 == 0x3ffff * 2 ^ 112
                and c6 == 0xffff * 2 ^ 96
                and c5 == 0xffff * 2 ^ 80
                and c4 == 0xffff * 2 ^ 64
                and c3 == 0xffff * 2 ^ 48
                and c2 == 0xffff * 2 ^ 32
                and c1 == 0xffff * 2 ^ 16
                and c0 >= 0xfffb
            then
                c7, c6, c5, c4, c3, c2, c1, c0 = 0, 0, 0, 0, 0, 0, 0, c0 - 0xfffb
            end

            -- Decode s.
            local s0, s1, s2, s3 = u4x4(fmt4x4, key, 17)

            -- Add.
            local t0 =           s0          + c0 + c1  local u0 = t0 % 2 ^ 32
            local t1 = t0 - u0 + s1 * 2 ^ 32 + c2 + c3  local u1 = t1 % 2 ^ 64
            local t2 = t1 - u1 + s2 * 2 ^ 64 + c4 + c5  local u2 = t2 % 2 ^ 96
            local t3 = t2 - u2 + s3 * 2 ^ 96 + c6 + c7  local u3 = t3 % 2 ^ 128

            -- Encode.
            return p4x4(fmt4x4, u0, u1 / 2 ^ 32, u2 / 2 ^ 64, u3 / 2 ^ 96)
        end

        return {
            mac = mac,
        }
    end
    mods["ccryptolib.aead"] = function()
        --- The ChaCha20Poly1305AEAD authenticated encryption with associated data (AEAD) construction.

        local expect   = require "cc.expect".expect
        local lassert = require "ccryptolib.internal.util".lassert
        local packing  = require "ccryptolib.internal.packing"
        local chacha20 = require "ccryptolib.chacha20"
        local poly1305 = require "ccryptolib.poly1305"

        local p8x1, fmt8x1 = packing.compilePack("<I8")
        local u4x4, fmt4x4 = packing.compileUnpack("<I4I4I4I4")
        local bxor = bit32.bxor

        --- Encrypts a message.
        --- @param key string A 32-byte random key.
        --- @param nonce string A 12-byte per-message unique nonce.
        --- @param message string The message to be encrypted.
        --- @param aad string aad Arbitrary associated data to also authenticate.
        --- @param rounds number? The number of ChaCha20 rounds to use. Defaults to 20.
        --- @return string ctx The ciphertext.
        --- @return string tag The 16-byte authentication tag.
        local function encrypt(key, nonce, message, aad, rounds)
            expect(1, key, "string")
            lassert(#key == 32, "key length must be 32", 2)
            expect(2, nonce, "string")
            lassert(#nonce == 12, "nonce length must be 12", 2)
            expect(3, message, "string")
            expect(4, aad, "string")
            rounds = expect(5, rounds, "number", "nil") or 20
            lassert(rounds % 2 == 0, "round number must be even", 2)
            lassert(rounds >= 8, "round number must be no smaller than 8", 2)
            lassert(rounds <= 20, "round number must be no larger than 20", 2)

            -- Generate auth key and encrypt.
            local msgLong = ("\0"):rep(64) .. message
            local ctxLong = chacha20.crypt(key, nonce, msgLong, rounds, 0)
            local authKey = ctxLong:sub(1, 32)
            local ciphertext = ctxLong:sub(65)

            -- Authenticate.
            local pad1 = ("\0"):rep(-#aad % 16)
            local pad2 = ("\0"):rep(-#ciphertext % 16)
            local aadLen = p8x1("<I8", #aad)
            local ctxLen = p8x1("<I8", #ciphertext)
            local combined = aad .. pad1 .. ciphertext .. pad2 .. aadLen .. ctxLen
            local tag = poly1305.mac(authKey, combined)

            return ciphertext, tag
        end

        --- Decrypts a message.
        --- @param key string The key used on encryption.
        --- @param nonce string The nonce used on encryption.
        --- @param tag string The authentication tag returned on encryption.
        --- @param ciphertext string The ciphertext to be decrypted.
        --- @param aad string The arbitrary associated data used on encryption.
        --- @param rounds number The number of rounds used on encryption.
        --- @return string? msg The decrypted plaintext. Or nil on auth failure.
        local function decrypt(key, nonce, tag, ciphertext, aad, rounds)
            expect(1, key, "string")
            lassert(#key == 32, "key length must be 32", 2)
            expect(2, nonce, "string")
            lassert(#nonce == 12, "nonce length must be 12", 2)
            expect(3, tag, "string")
            lassert(#tag == 16, "tag length must be 16", 2)
            expect(4, ciphertext, "string")
            expect(5, aad, "string")
            rounds = expect(6, rounds, "number", "nil") or 20
            lassert(rounds % 2 == 0, "round number must be even", 2)
            lassert(rounds >= 8, "round number must be no smaller than 8", 2)
            lassert(rounds <= 20, "round number must be no larger than 20", 2)

            -- Generate auth key.
            local authKey = chacha20.crypt(key, nonce, ("\0"):rep(32), rounds, 0)

            -- Check tag.
            local pad1 = ("\0"):rep(-#aad % 16)
            local pad2 = ("\0"):rep(-#ciphertext % 16)
            local aadLen = p8x1(fmt8x1, #aad)
            local ctxLen = p8x1(fmt8x1, #ciphertext)
            local combined = aad .. pad1 .. ciphertext .. pad2 .. aadLen .. ctxLen
            local t1, t2, t3, t4 = u4x4(fmt4x4, tag, 1)
            local u1, u2, u3, u4 = u4x4(fmt4x4, poly1305.mac(authKey, combined), 1)
            local eq = bxor(t1, u1) + bxor(t2, u2) + bxor(t3, u3) + bxor(t4, u4)
            if eq ~= 0 then return nil end

            -- Decrypt
            return chacha20.crypt(key, nonce, ciphertext, rounds)
        end

        return {
            encrypt = encrypt,
            decrypt = decrypt,
        }
    end
    return { aead = require("ccryptolib.aead"), sha256 = require("ccryptolib.sha256") }
end)()
-- @@CRYPTO-END
-- @@NET-BEGIN
-- ---------- Sicherer Funk (gleicher Code in OS, Pocket und Turtle) ----------
-- Jede Nachricht wird mit ChaCha20-Poly1305 verschluesselt und signiert.
-- Wer mithoert, sieht nur { n = Nonce, c = Zeichensalat, t = Pruefsumme }
-- unter einem Protokollnamen, der aus dem Schluessel abgeleitet ist.
-- Gefaelschte oder veraenderte Nachrichten fallen bei der Pruefsumme durch,
-- wiederholte (abgefangene) Nachrichten am Zaehler in der Nonce.
-- Schluessel = PBKDF2(Schwarm-Passwort); alle Geraete brauchen dasselbe.
local Net = {
    key = nil, proto = nil, isDefault = true,
    since = 0,          -- Zeitpunkt (os.epoch) des Passworts: neuere Disketten gewinnen
    last = {},          -- hoechster Zaehler je Absender (gegen Wiederholung)
    lastOwn = 0,        -- eigener Zaehler
    window = 60000,     -- ms: so alt darf die erste Nachricht eines Absenders sein
    salt = "GTS-SCHWARM-1", iterations = 1000,
}

local function toHex(s) return (s:gsub(".", function(c) return string.format("%02x", c:byte()) end)) end
local function fromHex(h)
    if type(h) ~= "string" or #h % 2 ~= 0 or h:find("[^%x]") then return nil end
    return (h:gsub("..", function(b) return string.char(tonumber(b, 16)) end))
end
-- Zahl -> len Bytes (big endian) und zurueck; exakt bis 2^53.
local function packNum(n, len)
    local out = {}
    for i = len, 1, -1 do
        out[i] = string.char(n % 256)
        n = math.floor(n / 256)
    end
    return table.concat(out)
end
local function unpackNum(s)
    local n = 0
    for i = 1, #s do n = n * 256 + s:byte(i) end
    return n
end

Net.toHex, Net.fromHex = toHex, fromHex

-- Leitet den Schluessel aus einem Passwort ab (dauert im Spiel 1-2 Sekunden).
function Net.derive(password)
    return Crypto.sha256.pbkdf2(tostring(password), Net.salt, Net.iterations)
end

function Net.setKey(key, isDefault, since)
    Net.key, Net.isDefault = key, isDefault and true or false
    Net.since = tonumber(since) or 0
    Net.proto = Net.protoFor(key)
    Net.last = {}
end

-- Schluessel aus der Datei laden (sonst Standard-Passwort "gts").
function Net.load(path)
    local h = fs.exists(path) and fs.open(path, "r")
    if h then
        local t = textutils.unserialize(h.readAll() or "")
        h.close()
        local key = type(t) == "table" and fromHex(t.key)
        if key and #key == 32 then
            Net.setKey(key, t.default, t.since)
            return true
        end
    end
    Net.setKey(Net.derive("gts"), true)
    return false
end

function Net.save(path)
    pcall(function()
        local h = fs.open(path, "w")
        if h then
            h.write(textutils.serialize({ key = toHex(Net.key), default = Net.isDefault, since = Net.since }))
            h.close()
        end
    end)
end

local function serialize(t)
    local ok, s = pcall(textutils.serialize, t, { compact = true })
    if ok and type(s) == "string" then return s end
    return textutils.serialize(t)
end

-- Verpackt eine Nachricht (Tabelle) fuer den Funk (mit einem bestimmten Schluessel).
function Net.sealWith(key, payload)
    local ctr = os.epoch("utc") * 1000
    if ctr <= Net.lastOwn then ctr = Net.lastOwn + 1 end
    Net.lastOwn = ctr
    local nonce = packNum(os.getComputerID() % 4294967296, 4) .. packNum(ctr, 8)
    local ct, tag = Crypto.aead.encrypt(key, nonce, serialize(payload), "GTS1")
    return { n = nonce, c = ct, t = tag }
end

function Net.seal(payload) return Net.sealWith(Net.key, payload) end

-- Protokollname zu einem Schluessel (z.B. fuer das Handy-Passwort).
function Net.protoFor(key)
    return "g" .. toHex(Crypto.sha256.digest("GTS-PROTO" .. key):sub(1, 5))
end

-- Entpackt eine empfangene Nachricht. Rueckgabe: Tabelle und Absender-ID
-- (aus der signierten Nonce, nicht faelschbar) oder nil.
function Net.open(msg)
    if type(msg) ~= "table" or type(msg.n) ~= "string" or #msg.n ~= 12
       or type(msg.c) ~= "string" or type(msg.t) ~= "string" or #msg.t ~= 16 or #msg.c > 200000 then
        return nil
    end
    local id, ctr = unpackNum(msg.n:sub(1, 4)), unpackNum(msg.n:sub(5, 12))
    local last = Net.last[id]
    if last then
        if ctr <= last then return nil end
    elseif math.abs(ctr / 1000 - os.epoch("utc")) > Net.window then
        return nil
    end
    local ok, plain = pcall(Crypto.aead.decrypt, Net.key, msg.n, msg.t, msg.c, "GTS1")
    if not ok or type(plain) ~= "string" then return nil end
    Net.last[id] = ctr
    local payload = textutils.unserialize(plain)
    if type(payload) ~= "table" then return nil end
    return payload, id
end

function Net.send(id, payload)
    if Net.key then rednet.send(id, Net.seal(payload), Net.proto) end
end

function Net.broadcast(payload)
    if Net.key then rednet.broadcast(Net.seal(payload), Net.proto) end
end

-- Kurzer Pruefwert (z.B. fuer Programm-Versionen).
function Net.hash(text)
    return toHex(Crypto.sha256.digest(text):sub(1, 6))
end
-- @@NET-END

-- ---------- Werkzeuge: Grundlage (mehr in [8]) ----------
-- Eine Seite traegt FEST das Funk-Modem (Wireless oder Ender Modem): der
-- Funk zum OS reisst nie ab. Die andere Seite ist die ARBEITSSEITE, dort
-- steckt die Spitzhacke. Alle anderen Werkzeuge liegen im Inventar und
-- werden fuer einen Befehl kurz an die Arbeitsseite gelegt (Geo Scanner,
-- Environment Detector, Kompass, Chunky ...); danach kommt sofort die
-- Spitzhacke zurueck. Abbauen und Angreifen holen sie notfalls selbst.
local TOOLS = {
    modem   = { ptype = "modem",                label = "Modem",
                items = { "computercraft:wireless_modem_normal", "computercraft:wireless_modem_advanced" } },
    chunky  = { ptype = "chunky",               label = "Chunky",   items = { "advancedperipherals:chunk_controller" } },
    scanner = { ptype = "geo_scanner",          label = "Scanner",  items = { "advancedperipherals:geo_scanner" } },
    compass = { ptype = "compass",              label = "Kompass",  items = { "minecraft:compass" } },
    env     = { ptype = "environment_detector", label = "Umgebung", items = { "advancedperipherals:environment_detector" } },
    player  = { ptype = "player_detector",      label = "Spieler",  items = { "advancedperipherals:player_detector" } },
    chat    = { ptype = "chat_box",             label = "Chat",     items = { "advancedperipherals:chat_box" } },
    speaker = { ptype = "speaker",              label = "Ton",      items = { "computercraft:speaker" } },
}
local TOOL_ORDER = { "chunky", "modem", "scanner", "compass", "env", "player", "chat", "speaker" }

-- Welches Werkzeug steckt an dieser Seite? (Ein Wired Modem zaehlt nicht,
-- eine Spitzhacke ist kein Peripheriegeraet: nil.)
local function toolAtSide(side)
    local t = peripheral.getType(side)
    if not t then return nil end
    if t == "modem" then
        local ok, wireless = pcall(peripheral.call, side, "isWireless")
        return (not ok or wireless) and "modem" or nil
    end
    for kind, def in pairs(TOOLS) do
        if def.ptype == t then return kind end
    end
    return nil
end

local function toolOfItem(name)
    for kind, def in pairs(TOOLS) do
        for _, n in ipairs(def.items) do
            if n == name then return kind end
        end
    end
end

-- Abbau-Werkzeug (Spitzhacke, auch aus Mods)?
local function isDigItem(name)
    return type(name) == "string" and name:find("pickaxe", 1, true) ~= nil
end

local function findToolSlot(kind)
    for slot = 1, 16 do
        local it = turtle.getItemDetail(slot)
        if it and toolOfItem(it.name) == kind then return slot end
    end
end

-- Zustand der Werkzeuge. busy/owner = gerade wird getauscht (nur einer zur Zeit).
local tool = {
    radio = nil,      -- Seite mit dem Modem (bleibt immer dran)
    work = nil,       -- Arbeitsseite (Spitzhacke)
    workKind = nil,   -- welches geliehene Werkzeug gerade an der Arbeitsseite steckt (nil = keins)
    digItem = nil,    -- Name der Spitzhacke (gelernt beim Tauschen)
    lastSlot = nil, displaced = nil,   -- letzter Tausch: Slot und was dabei hineinkam
    busy = false, owner = nil, depth = 0, want = 0,
    have = {},
}

local function findDigSlot()
    for slot = 1, 16 do
        local it = turtle.getItemDetail(slot)
        if it and (it.name == tool.digItem or isDigItem(it.name)) then return slot end
    end
end

local function emptySlot()
    for slot = 1, 16 do
        if turtle.getItemCount(slot) == 0 then return slot end
    end
end

local function otherSide(side) return (side == "left") and "right" or "left" end

-- Was steckt an einer Seite? Nur mit turtle.getEquippedLeft/Right (neuere
-- CC: Tweaked). Rueckgabe: Name oder nil, und ob die Antwort sicher ist.
local function equippedName(side)
    local fn = (side == "left") and turtle.getEquippedLeft or turtle.getEquippedRight
    if not fn then return nil, false end
    local ok, it = pcall(fn)
    if not ok then return nil, false end
    return (type(it) == "table") and it.name or nil, true
end

-- Bis zu 1 s warten, bis an der Seite das erwartete Werkzeug erkannt wird
-- (kind = nil: kein Peripheriegeraet mehr, z.B. Spitzhacke).
local function waitSide(side, kind)
    for _ = 1, 20 do
        if toolAtSide(side) == kind then return true end
        os.sleep(0.05)
    end
    return false
end

-- Legt den Inhalt eines Slots an eine Seite; was dort steckte, kommt in den
-- Slot. Liegen mehrere gleiche Werkzeuge im Slot, wird erst eins abgeteilt:
-- sonst haette das alte Werkzeug keinen Platz (und faellt bei vollem
-- Inventar auf den Boden).
local function equipFrom(side, slot)
    local sel = turtle.getSelectedSlot and turtle.getSelectedSlot() or 1
    local n = turtle.getItemCount(slot)
    if n > 1 then
        local free
        for s2 = 1, 16 do
            if s2 ~= slot and turtle.getItemCount(s2) == 0 then free = s2 break end
        end
        if not free then return false, "Inventar voll" end
        turtle.select(slot)
        turtle.transferTo(free, n - 1)
        if turtle.getItemCount(slot) ~= 1 then turtle.select(sel) return false, "Stapel nicht teilbar" end
    end
    turtle.select(slot)
    local ok = (side == "left") and turtle.equipLeft() or turtle.equipRight()
    turtle.select(sel)
    return ok
end

local function lockTools()
    local me = coroutine.running()
    if tool.owner == me then tool.depth = tool.depth + 1 return end
    tool.want = tool.want + 1
    while tool.busy do os.pullEvent("gts_tool") end
    tool.want = tool.want - 1
    tool.busy, tool.owner, tool.depth = true, me, 1
end

local function unlockTools()
    tool.depth = tool.depth - 1
    if tool.depth > 0 then return end
    tool.busy, tool.owner = false, nil
    if tool.want > 0 then os.queueEvent("gts_tool") end   -- nur wenn jemand wartet
end

local function openRadio(side)
    if side and not rednet.isOpen(side) then pcall(rednet.open, side) end
end

-- Seite mit Funk-Modem (Funk wird geoeffnet) oder nil.
local function radioSide()
    if tool.radio and toolAtSide(tool.radio) == "modem" then openRadio(tool.radio) return tool.radio end
    for _, side in ipairs({ "right", "left" }) do
        if toolAtSide(side) == "modem" then
            tool.radio, tool.work = side, otherSide(side)
            openRadio(side)
            return side
        end
    end
    return nil
end

-- Leiht ein Werkzeug aus dem Inventar an die Arbeitsseite. Nur mit lockTools.
local function equipWork(kind)
    local side = tool.work
    if not side then return false end
    if toolAtSide(side) == kind then tool.workKind = kind return true end
    local slot = findToolSlot(kind)
    if not slot then return false end
    if not equipFrom(side, slot) then return false end
    local it = turtle.getItemDetail(slot)
    tool.lastSlot, tool.displaced, tool.workKind = slot, it and it.name or false, kind
    if it and isDigItem(it.name) then tool.digItem = it.name end
    local ok = waitSide(side, kind)
    if ok and kind == "modem" then openRadio(side) end
    return ok
end

-- Spitzhacke zurueck an die Arbeitsseite. Ohne Spitzhacke wird der letzte
-- Tausch rueckgaengig gemacht. Nur mit lockTools.
local function restoreDig()
    local side = tool.work
    if not side then return false end
    if toolAtSide(side) == nil then tool.workKind = nil return true end
    -- Kandidaten: Slot vom letzten Tausch, dieselbe Spitzhacke, andere Spitzhacken
    local tries, seenSlot = {}, {}
    local function add(slot) if slot and not seenSlot[slot] then seenSlot[slot] = true tries[#tries + 1] = slot end end
    local last = tool.lastSlot and turtle.getItemDetail(tool.lastSlot)
    if last and (last.name == tool.digItem or isDigItem(last.name)) then add(tool.lastSlot) end
    for slot = 1, 16 do
        local it = turtle.getItemDetail(slot)
        if it and tool.digItem and it.name == tool.digItem then add(slot) end
    end
    for slot = 1, 16 do
        local it = turtle.getItemDetail(slot)
        if it and isDigItem(it.name) then add(slot) end
    end
    -- keine (passende) Spitzhacke: den Tausch rueckgaengig machen, sonst abnehmen
    if tool.lastSlot and ((last and last.name) or false) == tool.displaced then add(tool.lastSlot) end
    add(emptySlot())
    for _, slot in ipairs(tries) do
        local it = turtle.getItemDetail(slot)
        local expect = it and toolOfItem(it.name) or nil
        if equipFrom(side, slot) then
            tool.workKind = nil
            if it and isDigItem(it.name) then tool.digItem = it.name end
            return waitSide(side, expect)
        end
    end
    return false
end

-- Welche Werkzeuge sind da (angelegt oder im Inventar)? have.pick = Spitzhacke.
local function refreshTools()
    local have = {}
    for _, side in ipairs({ "left", "right" }) do
        local k = toolAtSide(side)
        if k then have[k] = true end
        local name, known = equippedName(side)
        if isDigItem(name) then have.pick = true tool.digItem = name end
        if side == tool.work and not k and not known then have.pick = true end   -- vermutlich die Spitzhacke
    end
    for slot = 1, 16 do
        local it = turtle.getItemDetail(slot)
        if it then
            local k = toolOfItem(it.name)
            if k then have[k] = true end
            if isDigItem(it.name) then have.pick = true end
        end
    end
    tool.have = have
    return have
end

-- Beim Start: Modem fest anlegen (falls es im Inventar liegt), Spitzhacke
-- an die andere Seite. Auch nach einem Neustart mitten im Tauschen.
local function setupTools()
    if not radioSide() then
        local slot = findToolSlot("modem")
        if slot then
            -- an eine Seite ohne Spitzhacke: erst eine mit Peripheriegeraet, dann eine leere
            local target
            for _, side in ipairs({ "right", "left" }) do
                if not target and toolAtSide(side) then target = side end
            end
            for _, side in ipairs({ "right", "left" }) do
                local name, known = equippedName(side)
                if not target and known and not name then target = side end
            end
            target = target or "right"
            equipFrom(target, slot)
            -- dabei die Spitzhacke erwischt? Dann kommt sie an die andere Seite.
            local it = turtle.getItemDetail(slot)
            if it and isDigItem(it.name) then
                tool.digItem = it.name
                equipFrom(otherSide(target), slot)
            end
            waitSide(target, "modem")
            radioSide()
        end
    end
    if not tool.radio then return false end
    tool.work = otherSide(tool.radio)
    local name = equippedName(tool.work)
    if isDigItem(name) then tool.digItem = name end
    local kind = toolAtSide(tool.work)
    local slot = findDigSlot()
    -- Spitzhacke aus dem Inventar an die Arbeitsseite: wenn dort ein
    -- Peripheriegeraet steckt oder (laut getEquipped) keine Spitzhacke.
    local known
    name, known = equippedName(tool.work)
    tool.lastSlot, tool.displaced = nil, nil
    if slot and kind then
        tool.workKind = kind
        restoreDig()
    elseif slot and not (known and isDigItem(name)) then
        -- (ohne getEquipped: einfach anlegen - steckte schon eine dran, liegt sie danach im Inventar)
        local it = turtle.getItemDetail(slot)
        if equipFrom(tool.work, slot) and it then tool.digItem = it.name end
    end
    tool.workKind = nil
    return true
end

refreshTools()
setupTools()
refreshTools()
if not radioSide() then
    print("FEHLER: Kein Modem gefunden!")
    print("Wireless oder Ender Modem anbauen")
    print("(oder ins Inventar legen).")
    return
end

-- ======================================================================
-- [3] POSITION UND DATEN
-- ======================================================================
-- Koordinaten relativ zur Basis: Basis = 0,0,0. f = Blickrichtung 0..3,
-- 0 = Blick wie beim Setzen der Basis, +1 = eine Rechtsdrehung.
-- x waechst nach vorn, z nach rechts, y nach oben.
local pos     = { x = 0, y = 0, z = 0, f = 0 }
local posOk   = true   -- false = Position nicht mehr vertrauenswuerdig
local homeGps = nil    -- GPS-Position der Basis (nur zur Kontrolle)

-- Selten geaenderte Daten (eigene Datei, damit das Speichern je Schritt klein bleibt):
--   world    = { x, y, z }  Welt-Koordinaten der Basis (F3 oder GPS), optional
--   compass  = 0..3         Himmelsrichtung von f = 0 (0 = Nord, 1 = Ost, 2 = Sued, 3 = West)
--   program  = { name, args, state }  laufendes Programm (wird nach Neustart fortgesetzt)
--   route    = Achsen-Reihenfolge fuer den Heimweg durch den eigenen Tunnel
--   finds    = noch nicht vom OS bestaetigte Funde
local data = { finds = {}, findN = 0, unbreakable = {} }

local DX = { [0] = 1, [1] = 0, [2] = -1, [3] = 0 }
local DZ = { [0] = 0, [1] = 1, [2] = 0, [3] = -1 }

local function saveState()
    local f = fs.open(CONFIG.stateFile, "w")
    if not f then return end
    f.write(textutils.serialize({ pos = pos, posOk = posOk, homeGps = homeGps }))
    f.close()
end

local function saveData()
    local f = fs.open(CONFIG.dataFile, "w")
    if not f then return end
    f.write(textutils.serialize(data))
    f.close()
end

local function readTable(path)
    if not fs.exists(path) then return nil end
    local f = fs.open(path, "r")
    if not f then return nil end
    local s = textutils.unserialize(f.readAll() or "")
    f.close()
    return type(s) == "table" and s or nil
end

-- GPS-Position oder nil (ohne GPS-Netz einfach nil).
local function gpsFix()
    if not gps then return nil end
    local ok, x, y, z = pcall(gps.locate, 1)
    if ok and type(x) == "number" then
        return { x = math.floor(x + 0.5), y = math.floor(y + 0.5), z = math.floor(z + 0.5) }
    end
end

-- Laedt alles. Rueckgabe: true beim allerersten Start.
local function loadState()
    local first = false
    local s = readTable(CONFIG.stateFile)
    if s and type(s.pos) == "table" then
        for _, k in ipairs({ "x", "y", "z", "f" }) do
            if type(s.pos[k]) == "number" then pos[k] = s.pos[k] end
        end
        posOk, homeGps = (s.posOk ~= false), s.homeGps
    else
        first = true
    end
    local d = readTable(CONFIG.dataFile)
    if d then
        data = d
        data.finds = type(data.finds) == "table" and data.finds or {}
        data.findN = type(data.findN) == "number" and data.findN or 0
        data.unbreakable = type(data.unbreakable) == "table" and data.unbreakable or {}
        -- alte Mission aus v4 nicht fortsetzen
        data.mission = nil
        -- Daten aus v5.0: woher stammen Basis-Koordinaten und Richtung?
        if type(data.world) == "table" and data.worldSrc == nil then
            local h = homeGps
            data.worldSrc = (type(h) == "table" and h.x == data.world.x and h.y == data.world.y and h.z == data.world.z)
                            and "gps" or "hand"
        end
        if data.compass ~= nil and data.compassSrc == nil then
            data.compassSrc = (data.worldSrc == "gps") and "gps" or "hand"
        end
    end
    -- Mit GPS pruefen, ob die gespeicherte Position noch stimmen kann:
    -- Hoehe und Entfernung zur Basis muessen passen (die Drehung ist egal).
    if not first and type(homeGps) == "table" then
        local fix = gpsFix()
        if fix then
            local dx, dy, dz = fix.x - homeGps.x, fix.y - homeGps.y, fix.z - homeGps.z
            if dy ~= pos.y or (dx * dx + dz * dz) ~= (pos.x * pos.x + pos.z * pos.z) then
                posOk = false
            end
        end
    end
    saveState()
    return first
end

-- Die Bewegungs-Funktionen der Turtle werden ersetzt, damit JEDES Programm
-- mitgezaehlt wird - auch eigene Skripte, die nichts vom Agenten wissen.
if not turtle._gtsRaw then
    turtle._gtsRaw = {
        forward = turtle.forward, back = turtle.back, up = turtle.up, down = turtle.down,
        turnLeft = turtle.turnLeft, turnRight = turtle.turnRight,
    }
end
local raw = turtle._gtsRaw

local agentOn = true   -- false nach dem Beenden: die Turtle-Funktionen verhalten sich wieder normal
local afterMove   -- siehe [8]: Chunky auffrischen nach dem Betreten eines neuen Chunks
-- flat: waagerechte Bewegung (kann in einen anderen Chunk fuehren).
local function track(name, apply, flat)
    turtle[name] = function(...)
        local ok, err = raw[name](...)
        if ok then
            apply()
            saveState()
            if flat and afterMove and agentOn then afterMove() end
        end
        return ok, err
    end
end
track("forward",   function() pos.x = pos.x + DX[pos.f] pos.z = pos.z + DZ[pos.f] end, true)
track("back",      function() pos.x = pos.x - DX[pos.f] pos.z = pos.z - DZ[pos.f] end, true)
track("up",        function() pos.y = pos.y + 1 end)
track("down",      function() pos.y = pos.y - 1 end)
track("turnLeft",  function() pos.f = (pos.f + 3) % 4 end)
track("turnRight", function() pos.f = (pos.f + 1) % 4 end)

-- Abbauen und Angreifen brauchen die Spitzhacke: steckt gerade ein
-- geliehenes Werkzeug an der Arbeitsseite, kommt sie vorher zurueck.
for _, name in ipairs({ "dig", "digUp", "digDown", "attack", "attackUp", "attackDown" }) do
    raw[name] = raw[name] or turtle[name]
    turtle[name] = function(...)
        if not agentOn or not tool.work then return raw[name](...) end
        lockTools()                      -- waehrend des Abbauens tauscht niemand
        if tool.workKind ~= nil or toolAtSide(tool.work) ~= nil then restoreDig() end
        local r = table.pack(pcall(raw[name], ...))
        unlockTools()
        if not r[1] then error(r[2], 0) end
        return table.unpack(r, 2, r.n)
    end
end

-- ======================================================================
-- [4] ZUSTAND
-- ======================================================================
local status  = "Bereit"
local last    = nil    -- Rueckmeldung zum letzten Befehl: { seq, state, msg }
local queue   = {}
local busy    = false
local current = nil    -- Name des laufenden Auftrags
local note    = "-"
local abort   = false  -- wird von STOP und BASIS gesetzt
local seen    = {}     -- schon gemeldete Funde dieses Programms
local events  = {}     -- letzte Ereignisse fuers OS
local osId    = nil    -- ID des OS, das zuletzt einen Befehl geschickt hat

local push  -- weiter unten definiert

local onCheck   -- [8]: Chunky auffrischen und GPS-Kontrolle waehrend eines Auftrags
-- Wird von allen laengeren Ablaeufen oft aufgerufen: Abbruch pruefen und
-- ab und zu den Chunky auffrischen bzw. die Position per GPS pruefen.
local function checkAbort()
    if onCheck then onCheck() end
    if abort then error("STOP", 0) end
end

local function setStatus(text)
    status = text
    push()
end

local function logEvent(text)
    events[#events + 1] = { t = os.epoch("utc"), text = tostring(text):sub(1, 60) }
    while #events > 6 do table.remove(events, 1) end
end

local function hasPart(name, list)
    for _, part in ipairs(list) do
        if name:find(part, 1, true) then return true end
    end
    return false
end

local function shortName(name)
    return (name:gsub("^.-:", ""))
end

-- ======================================================================
-- [5] NAVIGATION
-- ======================================================================
local DIRS = {
    fwd  = { move = function() return turtle.forward() end, detect = turtle.detect,
             dig = turtle.dig, attack = turtle.attack, inspect = turtle.inspect, suck = turtle.suck },
    up   = { move = function() return turtle.up() end, detect = turtle.detectUp,
             dig = turtle.digUp, attack = turtle.attackUp, inspect = turtle.inspectUp, suck = turtle.suckUp },
    down = { move = function() return turtle.down() end, detect = turtle.detectDown,
             dig = turtle.digDown, attack = turtle.attackDown, inspect = turtle.inspectDown, suck = turtle.suckDown },
}

-- Name des Blocks in einer Richtung (nil = Luft).
local function blockAt(dir)
    local ok, block = DIRS[dir].inspect()
    if ok and type(block) == "table" and type(block.name) == "string" then return block.name end
    return nil
end

-- Abbauen ohne geschuetzte Bloecke. Rueckgabe: true, wenn danach frei.
local function digSafe(dir)
    local name = blockAt(dir)
    if not name then return true end
    if hasPart(name, PROTECTED) then return false, "geschuetzt: " .. shortName(name) end
    for _ = 1, 20 do              -- Kies und Sand fallen nach
        if not DIRS[dir].dig() then
            if blockAt(dir) then return false, "nicht abbaubar: " .. shortName(name) end
            return true
        end
        if not DIRS[dir].detect() then return true end
        os.sleep(0.25)
    end
    return false, "blockiert"
end

-- Ein Schritt. Hindernisse: abbauen, Mobs angreifen. Geschuetzte Bloecke
-- bleiben stehen; vor einer anderen Turtle wird kurz gewartet.
local function step(dir)
    local d, waited = DIRS[dir], 0
    for _ = 1, 30 do
        checkAbort()
        if d.move() then return true end
        if turtle.getFuelLevel() == 0 then return false, "Tank leer" end
        if d.detect() then
            local name = blockAt(dir) or "?"
            if hasPart(name, PROTECTED) then
                waited = waited + 1
                if waited > 6 or not name:find("computercraft:", 1, true) then
                    return false, "Blockiert: " .. shortName(name)
                end
                os.sleep(0.5)
            elseif not d.dig() then
                return false, "Nicht abbaubar: " .. shortName(name)
            end
        else
            d.attack()
            os.sleep(0.3)
        end
    end
    return false, "Blockiert"
end

-- Erlaubtes Feld eines Programms (z.B. CHUNK): Ausweichen nie nach draussen.
local function inFence(x, z)
    local f = data.fence
    if type(f) ~= "table" then return true end
    return x >= f[1] and x <= f[2] and z >= f[3] and z <= f[4]
end

local function face(target)
    local diff = (target - pos.f) % 4
    if diff == 1 then turtle.turnRight()
    elseif diff == 2 then turtle.turnRight() turtle.turnRight()
    elseif diff == 3 then turtle.turnLeft() end
end

-- Faehrt zu x,y,z. order = Reihenfolge der Achsen, z.B. "xzy" (Standard:
-- erst waagerecht, dann senkrecht). Kein echtes Pathfinding: geht es nicht
-- weiter, weicht sie bis zu 8-mal aus (waagerecht: drueber oder drunter,
-- senkrecht: einen Block zur Seite) und korrigiert am Ende.
local function goTo(tx, ty, tz, order)
    local target = { x = tx, y = ty, z = tz }
    local detours, lastErr = 0, "Ziel nicht erreicht"
    for _ = 1, 4 do
        for axis in (order or "xzy"):gmatch(".") do
            while pos[axis] ~= target[axis] do
                checkAbort()
                local ok, err
                if axis == "y" then
                    ok, err = step(pos.y < ty and "up" or "down")
                    if not ok then
                        detours, lastErr = detours + 1, err
                        if detours > 8 then return false, err end
                        -- einen Block zur Seite (nur innerhalb des erlaubten Felds)
                        local moved = false
                        for i = 0, 3 do
                            local f = (pos.f + i) % 4
                            if inFence(pos.x + DX[f], pos.z + DZ[f]) then
                                face(f)
                                if step("fwd") then moved = true break end
                            end
                        end
                        if not moved then return false, err end
                    end
                else
                    if axis == "x" then face(pos.x < tx and 0 or 2) else face(pos.z < tz and 1 or 3) end
                    ok, err = step("fwd")
                    if not ok then
                        detours, lastErr = detours + 1, err
                        if detours > 8 then return false, err end
                        if not step("up") and not step("down") then return false, err end
                    end
                end
            end
        end
        if pos.x == tx and pos.y == ty and pos.z == tz then return true end
    end
    return false, lastErr
end

-- Faehrt neben einen Block (ohne ihn zu betreten) und liefert die Richtung,
-- in der er dann liegt: "fwd", "up" oder "down".
local function reach(tx, ty, tz)
    for _ = 1, 80 do
        checkAbort()
        local dx, dy, dz = tx - pos.x, ty - pos.y, tz - pos.z
        local dist = math.abs(dx) + math.abs(dy) + math.abs(dz)
        if dist == 0 then return nil, "Ziel ist frei" end
        if dist == 1 then
            if dy == 1 then return "up" elseif dy == -1 then return "down" end
            face(dx == 1 and 0 or dx == -1 and 2 or dz == 1 and 1 or 3)
            return "fwd"
        end
        local moved = false
        if dx ~= 0 and not moved then
            face(dx > 0 and 0 or 2)
            moved = step("fwd")
        end
        if dz ~= 0 and not moved then
            face(dz > 0 and 1 or 3)
            moved = step("fwd")
        end
        if dy ~= 0 and not moved then
            moved = step(dy > 0 and "up" or "down")
        end
        if not moved then return nil, "Weg blockiert" end
    end
    return nil, "zu weit"
end

local function distHome()
    return math.abs(pos.x) + math.abs(pos.y) + math.abs(pos.z)
end

-- ======================================================================
-- [6] WELT UND FUNDE
-- ======================================================================
-- Himmelsrichtungen als (x, z) in Welt-Koordinaten: Nord, Ost, Sued, West.
local CV = { [0] = { 0, -1 }, [1] = { 1, 0 }, [2] = { 0, 1 }, [3] = { -1, 0 } }
local COMPASS = { [0] = "N", [1] = "O", [2] = "S", [3] = "W" }

local function worldOk()
    local w = data.world
    return type(w) == "table" and type(w.x) == "number" and type(w.y) == "number" and type(w.z) == "number"
           and CV[data.compass] ~= nil
end

local function relToWorld(x, y, z)
    if not worldOk() then return nil end
    local f, r = CV[data.compass], CV[(data.compass + 1) % 4]
    return data.world.x + x * f[1] + z * r[1], data.world.y + y, data.world.z + x * f[2] + z * r[2]
end

-- Versatz in Welt-Achsen (so liefert ihn der Geo Scanner) -> Versatz relativ zur Basis.
local function offsetToRel(dx, dy, dz)
    local f, r = CV[data.compass], CV[(data.compass + 1) % 4]
    return dx * f[1] + dz * f[2], dy, dx * r[1] + dz * r[2]
end

-- Welt-Koordinaten -> relativ zur Basis (Umkehrung von relToWorld).
local function worldToRel(wx, wy, wz)
    if not worldOk() then return nil end
    local f, r = CV[data.compass], CV[(data.compass + 1) % 4]
    local dx, dy, dz = wx - data.world.x, wy - data.world.y, wz - data.world.z
    return dx * f[1] + dz * f[2], dy, dx * r[1] + dz * r[2]
end

-- Chunk, in dem die Turtle steht ("cx,cz"), oder nil ohne Welt-Koordinaten.
local function chunkKey()
    local wx, _, wz = relToWorld(pos.x, pos.y, pos.z)
    if not wx then return nil end
    return math.floor(wx / 16) .. "," .. math.floor(wz / 16)
end

-- "120 64 -340 n" -> world, compass
local function parseWorld(text)
    local x, y, z, rest = tostring(text):match("^%s*(-?%d+)[%s,;]+(-?%d+)[%s,;]+(-?%d+)(.*)$")
    if not x then return nil end
    local d = rest:match("^[%s,;]*(%a)")
    local compass = d and ({ n = 0, e = 1, o = 1, s = 2, w = 3 })[d:lower()]
    if d and not compass then return nil end
    return { x = tonumber(x), y = tonumber(y), z = tonumber(z) }, compass   -- Richtung darf fehlen (Kompass)
end

-- Merkt einen Fund und meldet ihn ans OS, bis es ihn bestaetigt.
-- kind: "ERZ", "KISTE", "LEHM", "CITY" oder "DARK". Rueckgabe: true wenn neu.
local function addFind(kind, name, x, y, z)
    local key = kind .. ":" .. x .. "," .. y .. "," .. z
    if kind == "DARK" then key = "DARK"
    elseif kind == "CITY" then key = "CITY:" .. math.floor(x / 48) .. "," .. math.floor(z / 48) end
    if seen[key] then return false end
    seen[key] = true
    data.findN = data.findN + 1
    local wx, wy, wz = relToWorld(x, y, z)
    data.finds[#data.finds + 1] = {
        n = data.findN, kind = kind, name = shortName(name),
        x = wx or x, y = wy or y, z = wz or z, world = (wx ~= nil),
    }
    while #data.finds > 200 do table.remove(data.finds, 1) end
    saveData()
    return true
end

-- ======================================================================
-- [7] INVENTAR
-- ======================================================================
local function usedSlots()
    local used = 0
    for slot = 1, 16 do
        if turtle.getItemCount(slot) > 0 then used = used + 1 end
    end
    return used
end

local function itemTotal()
    local n = 0
    for slot = 1, 16 do n = n + turtle.getItemCount(slot) end
    return n
end

local function isTrash(name)
    if name:find("_ore", 1, true) or hasPart(name, KEEP_PARTS) then return false end
    return TRASH[name] == true or hasPart(name, TRASH_PARTS)
end

local function dropFn(side)
    return ({ front = turtle.drop, down = turtle.dropDown, up = turtle.dropUp })[side] or turtle.dropDown
end

-- Wirft allen Muell weg. Rueckgabe: Anzahl Items, true wenn etwas klemmte.
local function dropTrash(side)
    local drop, dropped, stuck = dropFn(side or CONFIG.dropSide), 0, false
    for slot = 1, 16 do
        checkAbort()
        local item = turtle.getItemDetail(slot)
        if item and isTrash(item.name) then
            turtle.select(slot)
            if drop() then dropped = dropped + item.count else stuck = true end
        end
    end
    turtle.select(1)
    return dropped, stuck
end

local function refuelTo(target)
    local level = turtle.getFuelLevel()
    if level == "unlimited" then return 0 end
    for slot = 1, 16 do
        if turtle.getFuelLevel() >= target then break end
        local item = turtle.getItemDetail(slot)
        if item and FUEL[item.name] then
            turtle.select(slot)
            while turtle.getFuelLevel() < target and turtle.getItemCount(slot) > 0 do
                checkAbort()
                if not turtle.refuel(1) then break end
            end
        end
    end
    turtle.select(1)
    return turtle.getFuelLevel() - level
end

-- Steht auf dieser Seite ein Lager?
local function hasInventory(dir)
    local side = ({ fwd = "front", up = "top", down = "bottom" })[dir]
    if peripheral.hasType and peripheral.hasType(side, "inventory") then return true end
    local name = blockAt(dir)
    return name ~= nil and hasPart(name, { "chest", "barrel", "shulker", "drawer", "crate", "storage" })
end

-- Laedt alles in das Lager auf dieser Seite ("fwd", "up", "down").
-- Eine Ladung Brennstoff, Scanner und Modem bleiben. Rueckgabe: Anzahl Items
-- (nil = kein Lager gefunden), true wenn das Lager voll ist.
local function unloadTo(dir)
    if not hasInventory(dir) then return nil end
    local drop = dropFn(({ fwd = "front", up = "up", down = "down" })[dir])
    local n, full, fuelKept = 0, false, false
    for slot = 1, 16 do
        local item = turtle.getItemDetail(slot)
        local keep = item and hasPart(item.name, KEEP_PARTS)
        if item and FUEL[item.name] and not fuelKept then keep, fuelKept = true, true end  -- eine Ladung Brennstoff bleibt
        if item and not keep then
            turtle.select(slot)
            drop()
            local left = turtle.getItemCount(slot)
            n = n + item.count - left
            if left > 0 then full = true break end     -- Kiste voll (auch wenn nur ein Teil passte)
        end
    end
    turtle.select(1)
    return n, full
end

-- Laedt an der Basis ab. Die Kiste darf vor (DD), hinter (CHUNK), ueber
-- oder unter der Turtle stehen. Danach Blick wie beim Setzen der Basis.
local function unload()
    if CONFIG.unloadSide == "none" then return nil end
    face(0)
    local first = ({ front = "fwd", up = "up", down = "down" })[CONFIG.unloadSide] or "fwd"
    if hasInventory(first) then return unloadTo(first) end
    face(2)
    if hasInventory("fwd") then
        local n, full = unloadTo("fwd")
        face(0)
        return n, full
    end
    face(0)
    for _, dir in ipairs({ "down", "up" }) do
        if dir ~= first and hasInventory(dir) then return unloadTo(dir) end
    end
    return nil
end

-- Leert einen Behaelter. Rueckgabe: Anzahl erbeuteter Items.
local function loot(dir)
    local before = itemTotal()
    for _ = 1, 64 do
        checkAbort()
        if usedSlots() >= 16 then
            dropTrash()
            if usedSlots() >= 16 then break end
        end
        if not DIRS[dir].suck() then break end
    end
    return itemTotal() - before
end

-- ======================================================================
-- [8] WERKZEUGE (Tauschen, Chunky, GPS, Scanner, Kompass, Chat ...)
-- ======================================================================
local function sideWith(kind)
    for _, side in ipairs({ "left", "right" }) do
        if toolAtSide(side) == kind then return side end
    end
end

-- Benutzt ein Werkzeug: fn(peripheral) laeuft, solange es angelegt ist,
-- danach kommt die Spitzhacke zurueck. Rueckgabe: was fn liefert, oder
-- nil und ein Fehlertext ("kein Scanner", ...).
local function withTool(kind, fn)
    local def = TOOLS[kind]
    if not def then return nil, "unbekanntes Werkzeug" end
    local direct = sideWith(kind)
    if direct and direct ~= tool.work then          -- z.B. das Modem an der Funkseite
        local ok, a, b = pcall(fn, peripheral.wrap(direct))
        if ok then return a, b end
        return nil, a
    end
    if not direct and not (tool.work and findToolSlot(kind)) then return nil, "kein " .. def.label end
    lockTools()
    local a, b
    if equipWork(kind) then
        local ok, x, y = pcall(fn, peripheral.wrap(tool.work))
        if ok then a, b = x, y else a, b = nil, x end
    else
        a, b = nil, def.label .. " nicht erkannt"
    end
    restoreDig()
    unlockTools()
    return a, b
end

-- ---------- Chunky: Chunk geladen halten ----------
-- Advanced Peripherals laedt den Chunk, sobald der Chunky angelegt ist, und
-- haelt ihn danach noch 10 Minuten. Die Turtle legt ihn darum nur kurz an:
-- gleich nach dem Betreten eines neuen Chunks (die Nachbarn eines geladenen
-- Chunks laufen noch mit) und spaetestens alle chunkyEvery Sekunden.
local chunky = { t = -1e9, key = nil, steps = 0, n = 0 }

local function chunkyRefresh()
    if not tool.have.chunky then return false end
    local ok, err = withTool("chunky", function() os.sleep(0.1) return true end)
    chunky.fail = err
    if ok then
        chunky.t, chunky.key, chunky.steps, chunky.n = os.clock(), chunkKey(), 0, chunky.n + 1
    else
        -- klappt nicht (z.B. Inventar voll): in 30 s wieder versuchen, nicht bei jedem Schritt
        chunky.t, chunky.key, chunky.steps = os.clock() - CONFIG.chunkyEvery + 30, chunkKey(), 0
        logEvent("Chunky: " .. tostring(chunky.fail or "nicht angelegt"))
    end
    return ok
end

local function chunkyDue()
    if not tool.have.chunky then return false end
    if os.clock() - chunky.t >= CONFIG.chunkyEvery then return true end
    local key = chunkKey()
    if key then return key ~= chunky.key end
    return chunky.steps >= CONFIG.chunkySteps
end

-- ---------- GPS: Position pruefen und korrigieren ----------
-- Die Turtle zaehlt ihre Schritte mit. Mit GPS prueft sie das ab und zu:
--   - Blickrichtung: aus zwei Messungen mit Fahrt dazwischen,
--   - Basis-Koordinaten nachtragen, wenn die Basis ohne gesetzt wurde,
--   - Position korrigieren (auch nach einem Neustart mitten im Fahren).
local gpsState = { t = -1e9, failT = -1e9, ok = nil, prev = nil, fixes = 0 }

local function gpsDue(every)
    if not gps then return false end
    if os.clock() - gpsState.failT < CONFIG.gpsRetry then return false end
    return os.clock() - gpsState.t >= every
end

local function gpsCheck()
    gpsState.t = os.clock()
    local before = pos.x .. "," .. pos.y .. "," .. pos.z .. "," .. pos.f
    local fix = gpsFix()
    if not fix then
        gpsState.failT, gpsState.ok = os.clock(), false
        return nil
    end
    -- gps.locate wartet kurz: ist die Turtle inzwischen gefahren, ist die Messung alt
    if before ~= pos.x .. "," .. pos.y .. "," .. pos.z .. "," .. pos.f then return nil end
    gpsState.ok, gpsState.fixes = true, gpsState.fixes + 1
    local changed = false
    -- 1. Blickrichtung aus der Fahrt seit der letzten Messung
    local p = gpsState.prev
    if p and posOk then
        local rx, rz = pos.x - p.rx, pos.z - p.rz
        local wx, wz = fix.x - p.wx, fix.z - p.wz
        if rx ~= 0 or rz ~= 0 then
            for c = 0, 3 do
                local f, r = CV[c], CV[(c + 1) % 4]
                if rx * f[1] + rz * r[1] == wx and rx * f[2] + rz * r[2] == wz and c ~= data.compass then
                    if data.compass ~= nil and data.compassSrc ~= "hand" and data.compassSrc ~= nil and data.world then
                        -- Richtung der Basis ist sicher (GPS/Kompass): dann hat sich die
                        -- Turtle verzaehlt (Drehung verloren) - Blick korrigieren.
                        pos.f = (pos.f + c - data.compass) % 4
                        logEvent("Blickrichtung per GPS korrigiert")
                    else
                        data.compass, data.compassSrc = c, "gps"
                        if data.world and data.worldSrc == "gps-weg" then data.world = nil end
                        logEvent("Himmelsrichtung per GPS: " .. COMPASS[c])
                    end
                    changed = true
                    break
                end
            end
        end
    end
    -- 2. Basis-Koordinaten nachtragen (Welt = GPS minus gefahrener Weg)
    if CV[data.compass] and not data.world and posOk then
        local f, r = CV[data.compass], CV[(data.compass + 1) % 4]
        data.world = { x = fix.x - (pos.x * f[1] + pos.z * r[1]), y = fix.y - pos.y,
                       z = fix.z - (pos.x * f[2] + pos.z * r[2]) }
        data.worldSrc = "gps-weg"
        logEvent("Basis-Koordinaten per GPS")
        changed = true
    end
    -- 3. Position pruefen und korrigieren
    if worldOk() then
        local ex, ey, ez = relToWorld(pos.x, pos.y, pos.z)
        if (ex ~= fix.x or ey ~= fix.y or ez ~= fix.z) and posOk and data.worldSrc == "hand" then
            -- von Hand eingegebene Basis (F3) passt nicht: eher ein Tippfehler als
            -- ein Zaehlfehler - die Basis aus GPS und gefahrenem Weg berichtigen.
            local f, r = CV[data.compass], CV[(data.compass + 1) % 4]
            data.world = { x = fix.x - (pos.x * f[1] + pos.z * r[1]), y = fix.y - pos.y,
                           z = fix.z - (pos.x * f[2] + pos.z * r[2]) }
            data.worldSrc = "gps-weg"
            logEvent("Basis-Koordinaten per GPS berichtigt")
            changed = true
        elseif ex ~= fix.x or ey ~= fix.y or ez ~= fix.z or not posOk then
            local x, y, z = worldToRel(fix.x, fix.y, fix.z)
            logEvent(posOk and ("GPS: Position korrigiert (" .. (math.abs(x - pos.x) + math.abs(y - pos.y) + math.abs(z - pos.z)) .. " Bl.)")
                     or "GPS: Position wiederhergestellt")
            pos.x, pos.y, pos.z, posOk = x, y, z, true
            saveState()
        end
    end
    gpsState.prev = { rx = pos.x, rz = pos.z, wx = fix.x, wz = fix.z }
    if changed then saveData() end
    return fix
end

-- Nach jedem Schritt waagerecht: neuer Chunk -> Chunky kurz anlegen.
afterMove = function()
    chunky.steps = chunky.steps + 1
    if chunkyDue() then chunkyRefresh() end
end

-- Aus checkAbort (also nur im laufenden Auftrag, im Stand): Chunky nach
-- Zeit auffrischen, Position per GPS pruefen.
onCheck = function()
    if not busy or coroutine.running() == nil then return end
    if chunkyDue() then chunkyRefresh() end
    if gpsDue(CONFIG.gpsWork) then gpsCheck() end
end

-- ---------- Geo Scanner ----------
local function scan(radius) return withTool("scanner", function(p) return p.scan(radius) end) end
-- Erz-Zaehlung des ganzen Chunks, in dem die Turtle steht.
local function chunkAnalyze() return withTool("scanner", function(p) return p.chunkAnalyze() end) end

-- ---------- Kompass (Advanced Peripherals "Compass Turtle") ----------
local FACING = { north = 0, east = 1, south = 2, west = 3 }
-- Himmelsrichtung, in die die Turtle gerade schaut (0 = Nord ... 3 = West).
local function compassFacing()
    local f, err = withTool("compass", function(p) return p.getFacing() end)
    local c = FACING[tostring(f):lower()]
    if c then return c end
    return nil, err or "Kompass: unklare Antwort"
end

-- Der Scanner liefert Versaetze in Welt-Achsen. Kennt die Turtle ihre
-- Himmelsrichtung nicht, nimmt sie den Kompass oder liest sie aus dem Scan:
-- hinter ihr liegt der eigene Tunnel - genau eine Richtung mit 3 freien
-- Bloecken am Stueck.
local function calibrate(list)
    local c = compassFacing()
    if c then
        data.compass = (c - pos.f) % 4
        saveData()
        return true
    end
    if type(list) ~= "table" then return false end
    local solid = {}
    for _, b in ipairs(list) do
        if type(b) == "table" and b.y == 0 and type(b.name) == "string" and not b.name:find("air", 1, true) then
            solid[b.x .. "," .. b.z] = true
        end
    end
    local found, count = nil, 0
    for c2 = 0, 3 do
        local free = true
        for i = 1, 3 do
            if solid[(CV[c2][1] * i) .. "," .. (CV[c2][2] * i)] then free = false end
        end
        if free then found, count = c2, count + 1 end
    end
    if count ~= 1 then return false end
    data.compass = (found - pos.f - 2) % 4   -- found = Richtung "hinter mir"
    saveData()
    return true
end

-- ---------- Chat Box: Nachricht direkt an den Besitzer ----------
-- (Erreicht ihn auch, wenn der Funk nicht bis zum OS reicht.)
local function tell(text)
    if not (tool.have.chat and data.owner) then return false end
    local ok = withTool("chat", function(p)
        return p.sendMessageToPlayer(tostring(text):sub(1, 200), data.owner, "GTS")
    end)
    return ok and true or false
end

-- ======================================================================
-- [9] PROGRAMME
-- ======================================================================
-- Ein Programm ist eine Lua-Datei, die das OS schickt. Es bekommt die
-- Schnittstelle T und seine Argumente: local T, args = ...
-- Es liefert ok, text (und optional "pause": dann merkt sich die Turtle
-- den Stand und macht beim naechsten Start desselben Programms weiter).
-- Den eigenen Stand legt es in T.state ab und sichert ihn mit T.save().
local Progs = { hashes = {}, incoming = {} }

function Progs.path(name) return fs.combine(CONFIG.progDir, name .. ".lua") end

function Progs.scan()
    Progs.hashes = {}
    if not fs.isDir(CONFIG.progDir) then return end
    for _, file in ipairs(fs.list(CONFIG.progDir)) do
        local name = file:match("^([%w_%-]+)%.lua$")
        if name then
            local h = fs.open(fs.combine(CONFIG.progDir, file), "r")
            if h then
                Progs.hashes[name] = Net.hash(h.readAll() or "")
                h.close()
            end
        end
    end
end

-- Teil einer Uebertragung (Programm oder Agent). Rueckgabe: Code, wenn komplett.
function Progs.receive(msg)
    local key = tostring(msg.name) .. "/" .. tostring(msg.hash)
    local buf = Progs.incoming[key]
    if not buf then
        local count = 0
        for k, b in pairs(Progs.incoming) do
            count = count + 1
            if os.clock() - b.t > 120 then Progs.incoming[k] = nil end   -- Reste alter Uebertragungen
        end
        if count >= 4 then Progs.incoming = {} end
        buf = { parts = math.max(1, math.min(64, math.floor(tonumber(msg.parts) or 1))), got = {}, n = 0, t = os.clock() }
        Progs.incoming[key] = buf
    end
    local i = math.floor(tonumber(msg.part) or 0)
    if i < 1 or i > buf.parts or type(msg.data) ~= "string" then return nil end
    if not buf.got[i] then buf.got[i], buf.n = msg.data, buf.n + 1 end
    if buf.n < buf.parts then return nil end
    Progs.incoming[key] = nil
    local code = table.concat(buf.got)
    if Net.hash(code) ~= msg.hash then return nil, "Pruefsumme falsch" end
    return code
end

function Progs.install(name, code)
    if not tostring(name):find("^[%w_%-]+$") then return false end
    fs.makeDir(CONFIG.progDir)
    local h = fs.open(Progs.path(name), "w")
    if not h then return false end
    h.write(code)
    h.close()
    Progs.hashes[name] = Net.hash(code)
    return true
end

-- Schnittstelle fuer Programme.
local T = {
    VERSION = VERSION, config = CONFIG, pos = pos, DX = DX, DZ = DZ, COMPASS = COMPASS,
    check = checkAbort, status = setStatus, log = logEvent,
    step = step, face = face, goTo = goTo, reach = reach, blockAt = blockAt, digSafe = digSafe,
    distHome = distHome,
    dig = function(dir) return DIRS[dir].dig() end,
    inspect = function(dir) return DIRS[dir].inspect() end,
    usedSlots = usedSlots, itemTotal = itemTotal, isTrash = isTrash, dropTrash = dropTrash,
    refuelTo = refuelTo, unload = unload, unloadTo = unloadTo, loot = loot, hasInventory = hasInventory,
    scan = scan, chunkAnalyze = chunkAnalyze, calibrate = calibrate,
    offsetToRel = offsetToRel, relToWorld = relToWorld, addFind = addFind,
    gps = gpsFix, shortName = shortName, hasPart = hasPart,
    fuel = function() return turtle.getFuelLevel(), turtle.getFuelLimit() end,
    use = withTool, facing = compassFacing, tell = tell,
}
-- Welche Werkzeuge hat die Turtle? { scanner = true, compass = true, ... }
function T.tools()
    local out = {}
    for k, v in pairs(tool.have) do out[k] = v end
    return out
end
function T.world() return data.world, data.compass end
function T.unbreakable() return data.unbreakable end
function T.save() saveData() end
function T.setRoute(order) data.route = order saveData() end
-- Feld, aus dem die Turtle beim Ausweichen nicht hinaus darf (nil = keins).
function T.setFence(x1, x2, z1, z2)
    data.fence = x1 and { math.min(x1, x2), math.max(x1, x2), math.min(z1, z2), math.max(z1, z2) } or nil
    saveData()
end
-- Reicht der Tank fuer den Heimweg plus extra? Tankt notfalls aus dem Inventar.
function T.fuelOk(extra)
    local fuel = turtle.getFuelLevel()
    if fuel == "unlimited" then return true end
    local need = distHome() + CONFIG.fuelReserve + (extra or 0)
    if fuel < need then refuelTo(need + 200) end
    return turtle.getFuelLevel() >= need
end
-- Zurueck zur Basis (durch den eigenen Weg) und Blick wie beim Setzen.
function T.home(order)
    local ok, err = goTo(0, 0, 0, order or data.route or "xzy")
    -- versperrt: andere Reihenfolgen versuchen (z.B. erst senkrecht hoch)
    if not ok then ok = goTo(0, 0, 0, "yxz") end
    if not ok then ok = goTo(0, 0, 0, "xzy") end
    if ok then face(0) end
    return ok, err
end

function Progs.run(name, args, resume)
    local path = Progs.path(name)
    if not fs.exists(path) then return false, "Programm " .. name .. " fehlt" end
    local h = fs.open(path, "r")
    local code = h.readAll() or ""
    h.close()
    local env = setmetatable({ T = T }, { __index = _ENV or getfenv() })
    local fn, err = load(code, "=" .. name, "t", env)
    if not fn then return false, "Programmfehler: " .. tostring(err) end
    local p = data.program
    if not (resume and p and p.name == name) then
        p = { name = name, args = args or {}, state = {} }
        data.program, data.route, data.fence = p, nil, nil
        seen = {}
    elseif type(args) == "table" and next(args) then
        p.args = args              -- z.B. Muell-Schalter geaendert
    end
    p.paused = nil
    T.state, T.args, T.resume = p.state, p.args, resume and true or false
    saveData()
    local ok, res, msg, mode = pcall(fn, T, p.args)
    if not ok then
        if res == "STOP" then error("STOP", 0) end
        data.program, data.fence = nil, nil
        saveData()
        return false, "Fehler: " .. tostring(res):sub(1, 50)
    end
    if mode == "pause" then p.paused = true else data.program, data.route, data.fence = nil, nil, nil end
    saveData()
    return res ~= false, msg
end

-- ======================================================================
-- [10] AUFTRAEGE
-- ======================================================================
-- Eingebaute Auftraege. run() liefert true/false und einen kurzen Text.
local Jobs = {}

Jobs.DROP = { status = "Entleere", run = function()
    local dropped, stuck = dropTrash()
    if stuck then return false, "Ablage voll (" .. dropped .. " entsorgt)" end
    if dropped == 0 then return true, "Kein Muell im Inventar" end
    return true, dropped .. " Items entsorgt"
end }

Jobs.REFUEL = { status = "Tanke", run = function()
    local level = turtle.getFuelLevel()
    if level == "unlimited" then return true, "Tank unbegrenzt" end
    local target = math.min(CONFIG.refuelTarget, turtle.getFuelLimit())
    if level >= target then return true, "Tank reicht (" .. level .. ")" end
    local gained = refuelTo(target)
    if gained == 0 then return false, "Kein Brennstoff im Inventar" end
    return true, "+" .. gained .. " (Tank " .. turtle.getFuelLevel() .. ")"
end }

Jobs.HOME = { status = "Heimweg", run = function()
    if not posOk then return false, "Position unbekannt: [H] an Turtle" end
    local dist = distHome()
    local level = turtle.getFuelLevel()
    if level ~= "unlimited" and level < dist then
        refuelTo(dist + 20)
        level = turtle.getFuelLevel()
        if level < dist then return false, "Tank reicht nicht (" .. level .. "/" .. dist .. ")" end
    end
    local ok, err = T.home()
    if not ok then return false, err end
    local text = (dist == 0) and "Schon an der Basis" or ("Basis erreicht (" .. dist .. " Bl.)")
    if data.route then
        dropTrash()
        local n = unload()
        if n and n > 0 then text = text .. ", " .. n .. " entladen" end
    end
    if data.program then
        data.program.paused = true
        text = text .. ", " .. data.program.name:upper() .. " pausiert"
    end
    data.route = nil
    saveData()
    return true, text
end }

-- Basis hier setzen. Mit GPS werden Koordinaten und Himmelsrichtung von
-- selbst ermittelt (ein Schritt vor und zurueck - oder zur Seite), sonst aus args.world.
local function gpsCalibrate()
    local a = gpsFix()
    if not a then return nil end
    -- Richtung eines Schritts aus zwei GPS-Messungen
    local function dirOf(b, sign)
        if not b then return nil end
        local dx, dz = (b.x - a.x) * sign, (b.z - a.z) * sign
        for c = 0, 3 do
            if CV[c][1] == dx and CV[c][2] == dz then return c end
        end
    end
    if raw.forward() then
        local b = gpsFix()
        raw.back()
        local c = dirOf(b, 1)
        if c then return a, c end
    end
    if raw.back() then                    -- vorne steht z.B. die Kiste
        local b = gpsFix()
        raw.forward()
        local c = dirOf(b, -1)
        if c then return a, c end
    end
    for _, k in ipairs({ 1, 3 }) do       -- seitlich: drehen, Schritt, zurueck, zurueckdrehen
        for _ = 1, k do raw.turnRight() end
        local c
        if raw.forward() then
            local b = gpsFix()
            raw.back()
            c = dirOf(b, 1)
        end
        for _ = 1, k do raw.turnLeft() end
        if c then return a, (c - k) % 4 end
    end
    return a, nil
end

Jobs.SETHOME = { status = "Setze Basis", run = function(args)
    pos.x, pos.y, pos.z, pos.f = 0, 0, 0, 0
    posOk = true
    data.world, data.compass, data.worldSrc, data.compassSrc = nil, nil, nil, nil
    data.program, data.route, data.fence = nil, nil, nil
    gpsState.prev, chunky.key = nil, nil
    local fix, compass = gpsCalibrate()
    homeGps = fix
    if type(args) == "table" and type(args.world) == "table" then
        data.world, data.compass, data.worldSrc = args.world, args.compass, "hand"
        if args.compass ~= nil then data.compassSrc = "hand" end
    elseif fix then
        data.world, data.compass, data.worldSrc = fix, compass, "gps"
        if compass ~= nil then data.compassSrc = "gps" end
    end
    -- Richtung fehlt: Kompass im Inventar fragen (Blick jetzt = Blick 0).
    local byCompass = false
    if data.compass == nil then
        local c = compassFacing()
        if c then data.compass, data.compassSrc, byCompass = c, "kompass", true end
    end
    if fix then gpsState.prev = { rx = 0, rz = 0, wx = fix.x, wz = fix.z } end
    saveState()
    saveData()
    if data.world and data.compass then
        return true, "Basis gesetzt: " .. data.world.x .. " " .. data.world.y .. " " .. data.world.z
                     .. " " .. COMPASS[data.compass] .. (data.worldSrc == "gps" and " (GPS)" or "")
                     .. (byCompass and " (Kompass)" or "")
    end
    if data.world then
        return true, "Basis gesetzt: " .. data.world.x .. " " .. data.world.y .. " " .. data.world.z
                     .. ", Richtung folgt per GPS beim Fahren"
    end
    if data.compass then return true, "Basis hier gesetzt, Blick " .. COMPASS[data.compass] .. " (Kompass)" end
    return true, "Basis hier gesetzt (ohne Koordinaten)"
end }

-- Programm starten: args = { name, hash, args }
Jobs.RUN = { status = "Startet", run = function(a)
    if not posOk then return false, "Position unbekannt: [H] an Turtle" end
    a = type(a) == "table" and a or {}
    local name = tostring(a.name)
    if type(a.owner) == "string" and a.owner:find("^[%w_]+$") then data.owner = a.owner:sub(1, 16) end
    if not Progs.hashes[name] then return false, "Programm " .. name .. " fehlt" end
    if a.hash and Progs.hashes[name] ~= a.hash then return false, "Programm " .. name .. " veraltet" end
    local resume = not a.fresh and (a.resume or (data.program and data.program.name == name))
    return Progs.run(name, a.args, resume)
end }

-- Einzelne Grundfunktion (Test-Panel am OS).
local FN = {
    vor = function() return step("fwd") end,
    zurueck = function() return turtle.back() end,
    hoch = function() return step("up") end,
    runter = function() return step("down") end,
    links = function() return turtle.turnLeft() end,
    rechts = function() return turtle.turnRight() end,
    graben = function()
        local name = blockAt("fwd")
        if not name then return false, "vorn ist Luft" end
        local ok, err = digSafe("fwd")
        return ok, ok and ("abgebaut: " .. shortName(name)) or err
    end,
    schauen = function()
        local parts = {}
        for _, d in ipairs({ "fwd", "up", "down" }) do
            parts[#parts + 1] = d .. "=" .. shortName(blockAt(d) or "luft")
        end
        return true, table.concat(parts, " ")
    end,
    scan = function()
        local list, err = scan(8)
        if type(list) ~= "table" then return false, "Scan: " .. tostring(err) end
        return true, "Scan: " .. #list .. " Bloecke im Umkreis 8"
    end,
    chunk = function()
        local t, err = chunkAnalyze()
        if type(t) ~= "table" then return false, "Chunk: " .. tostring(err) end
        local n, kinds = 0, 0
        for _, c in pairs(t) do n, kinds = n + c, kinds + 1 end
        return true, "Chunk: " .. n .. " Erze, " .. kinds .. " Sorten"
    end,
    gps = function()
        local fix = gpsFix()
        if not fix then return false, "kein GPS-Signal" end
        return true, "GPS: " .. fix.x .. " " .. fix.y .. " " .. fix.z
    end,
    inventar = function()
        local kinds, n = {}, 0
        for s = 1, 16 do
            local it = turtle.getItemDetail(s)
            if it then kinds[shortName(it.name)] = true n = n + it.count end
        end
        local c = 0
        for _ in pairs(kinds) do c = c + 1 end
        return true, n .. " Items, " .. c .. " Sorten, " .. usedSlots() .. "/16 Slots"
    end,
    abladen = function()
        local n, full = unload()
        if n == nil then return false, "keine Kiste an der Basis-Seite" end
        return not full, n .. " Items abgeladen" .. (full and " (Kiste voll)" or "")
    end,
    werkzeug = function()
        refreshTools()
        local list = {}
        if tool.have.pick then list[1] = "Hacke" end
        for _, k in ipairs(TOOL_ORDER) do
            if tool.have[k] and k ~= "modem" then list[#list + 1] = TOOLS[k].label end
        end
        local text = "Funk " .. tostring(tool.radio) .. ", Arbeit " .. tostring(tool.work) .. ": " .. table.concat(list, " ")
        if tool.have.chunky then text = text .. " | Chunky alle " .. math.floor(CONFIG.chunkyEvery / 60) .. " min" end
        return tool.radio ~= nil, text
    end,
    kompass = function()
        local c, err = compassFacing()
        if not c then return false, tostring(err) end
        data.compass, data.compassSrc = (c - pos.f) % 4, "kompass"
        saveData()
        return true, "Blick " .. COMPASS[c] .. ", Basis-Richtung gespeichert"
    end,
    umgebung = function()
        local t, err = withTool("env", function(p)
            return { biome = p.getBiome(), dim = p.getDimension(), slime = p.isSlimeChunk(), light = p.getBlockLightLevel() }
        end)
        if type(t) ~= "table" then return false, tostring(err) end
        return true, shortName(tostring(t.biome)) .. ", " .. shortName(tostring(t.dim)) .. ", Licht " .. tostring(t.light)
                     .. (t.slime and ", Slime-Chunk" or "")
    end,
    spieler = function()
        local list, err = withTool("player", function(p) return p.getPlayersInRange(48) end)
        if type(list) ~= "table" then return false, tostring(err) end
        if #list == 0 then return true, "niemand im Umkreis 48" end
        return true, #list .. " nah: " .. table.concat(list, ", ")
    end,
    chat = function()
        if not data.owner then return false, "Besitzer unbekannt (INFO > Besitzer am OS)" end
        if not tool.have.chat then return false, "kein Chat" end
        local ok = tell("Turtle #" .. os.getComputerID() .. " meldet sich (Test)")
        return ok, ok and ("an " .. data.owner .. " geschickt") or "Chat Box hat nicht geklappt"
    end,
    name = function(a)     -- Name vom OS (NAME in der Turtle-Ansicht)
        local n = tostring(a.label or ""):gsub("[^%w_%- ]", ""):sub(1, 12)
        os.setComputerLabel((n ~= "") and n or nil)
        return true, (n ~= "") and ("heisst jetzt " .. n) or "Name geloescht"
    end,
    ton = function()
        local ok, err = withTool("speaker", function(p)
            for i = 1, 3 do p.playNote("bell", 3, 12 + i * 4) os.sleep(0.25) end
            return true
        end)
        return ok and true or false, ok and "Piep! (hier bin ich)" or tostring(err)
    end,
}

Jobs.FN = { status = "Test", run = function(a)
    local name = type(a) == "table" and tostring(a.fn) or "?"
    local fn = FN[name]
    if not fn then return false, "Unbekannt: " .. name end
    local ok, msg = fn(a)
    if msg == nil then msg = ok and "OK" or "fehlgeschlagen" end
    return ok and true or false, name:upper() .. ": " .. tostring(msg) .. " (P " .. pos.x .. "," .. pos.y .. "," .. pos.z .. ")"
end }

-- ======================================================================
-- [11] FUNK UND ABLAUF
-- ======================================================================
local function toolList()
    local out = {}
    for _, k in ipairs(TOOL_ORDER) do if tool.have[k] then out[#out + 1] = k end end
    return out
end

local function payload()
    local finds = {}
    for i = 1, math.min(5, #data.finds) do finds[i] = data.finds[i] end
    local fuel = turtle.getFuelLevel()
    local wpos
    local wx, wy, wz = relToWorld(pos.x, pos.y, pos.z)
    if wx and posOk then wpos = { x = wx, y = wy, z = wz } end
    return {
        t = "UP", v = VERSION, status = status, fuel = fuel, fuelMax = turtle.getFuelLimit(),
        inv = usedSlots(), pos = { x = pos.x, y = pos.y, z = pos.z, f = pos.f }, posOk = posOk,
        label = os.getComputerLabel(), queue = #queue, last = last, finds = finds,
        prog = data.program and data.program.name or nil, paused = data.program and data.program.paused or nil,
        progs = Progs.hashes,
        world = data.world and true or false, compass = data.compass, gps = homeGps ~= nil,
        scanner = tool.have.scanner == true, events = events, tools = toolList(),
        -- Welt-Koordinaten (wenn bekannt): Turtle, Blick (0 = Nord) und Basis
        wpos = wpos, wf = data.compass and (data.compass + pos.f) % 4 or nil,
        base = data.world and { x = data.world.x, y = data.world.y, z = data.world.z } or nil,
        gpsOk = gpsState.ok, pick = tool.have.pick == true,
    }
end

-- Sendet den Status (das Modem ist immer angelegt).
function push()
    if radioSide() then Net.broadcast(payload()) end
    os.queueEvent("gts_ui")
end

local function enqueue(cmd, seq, args)
    if cmd == current and cmd == "RUN" and not abort then
        last = { seq = seq, state = "fail", msg = "Programm laeuft schon" }
        return
    end
    for _, job in ipairs(queue) do
        if job.cmd == cmd and cmd ~= "FN" then  -- derselbe Befehl wartet schon
            job.seq, job.args = seq, args
            last = { seq = seq, state = "queued" }
            return
        end
    end
    if #queue >= CONFIG.maxQueue then
        last = { seq = seq, state = "fail", msg = "Warteschlange voll" }
        return
    end
    queue[#queue + 1] = { cmd = cmd, seq = seq, args = args }
    last = { seq = seq, state = "queued" }
    os.queueEvent("gts_job")
end

local pendingReboot = false
local handled, handledList = {}, {}   -- zuletzt bearbeitete Befehls-Nummern

-- Nimmt Befehle an. Laeuft getrennt vom Arbeiter, darum geht kein Befehl
-- verloren, waehrend die Turtle faehrt. STOP und BASIS unterbrechen sofort.
local function handle(msg, from)
    if msg.t == "PROG" or msg.t == "AGENT" then
        osId = from
        local code, err = Progs.receive(msg)
        if err then
            last = { seq = msg.seq, state = "fail", msg = tostring(msg.name) .. ": " .. err }
        elseif code and msg.t == "PROG" then
            if Progs.install(msg.name, code) then
                logEvent("Programm " .. msg.name .. " erhalten")
            end
        elseif code then
            -- Neuer Agent: als startup schreiben, danach neu starten.
            local self = (shell and shell.getRunningProgram and shell.getRunningProgram()) or "startup.lua"
            local h = fs.open("/" .. self .. ".neu", "w")
            if h then
                h.write(code) h.close()
                if fs.exists("/" .. self) then fs.delete("/" .. self) end
                fs.move("/" .. self .. ".neu", "/" .. self)
                last = { seq = msg.seq, state = "ok", msg = "Update auf v" .. tostring(msg.ver) .. ", Neustart" }
                pendingReboot = true
                os.queueEvent("gts_job")
            end
        end
        push()
        return
    end
    if msg.t == "KEY" then
        local key = Net.fromHex(msg.key)
        if key and #key == 32 then
            Net.send(from, { t = "KEYOK" })   -- noch mit dem alten Schluessel
            Net.setKey(key, msg.default, msg.since)
            Net.save(CONFIG.keyFile)
            logEvent("Neues Schwarm-Passwort")
        end
        return
    end
    if msg.t ~= "CMD" or type(msg.cmd) ~= "string" then return end
    osId = from
    -- Das OS wiederholt Befehle ohne Antwort; doppelte nur beantworten.
    if type(msg.seq) == "number" then
        if handled[msg.seq] then push() return end
        handled[msg.seq] = true
        handledList[#handledList + 1] = msg.seq
        if #handledList > 32 then handled[table.remove(handledList, 1)] = nil end
    end
    if msg.cmd == "ACK" then
        -- Das OS hat Funde bis Nummer n gespeichert.
        local n = tonumber(msg.n) or 0
        while data.finds[1] and data.finds[1].n <= n do table.remove(data.finds, 1) end
        saveData()
    elseif msg.cmd == "STOP" then
        queue = {}
        if busy then abort = true end
        if data.program then data.program.paused = true end
        saveData()
        last = { seq = msg.seq, state = "ok", msg = "Gestoppt" }
        logEvent("STOP")
        push()
    elseif msg.cmd == "HOME" then
        queue = {}
        if busy then abort = true end
        if data.program then data.program.paused = true end
        enqueue("HOME", msg.seq)
        push()
    elseif Jobs[msg.cmd] then
        enqueue(msg.cmd, msg.seq, msg.args)
        push()
    else
        last = { seq = msg.seq, state = "fail", msg = "Unbekannt: " .. msg.cmd:sub(1, 12) }
        push()
    end
end

local function netLoop()
    while true do
        local _, _, msg, proto = os.pullEvent("rednet_message")
        if proto == Net.proto then
            local payload, from = Net.open(msg)
            if payload then
                local ok, err = pcall(handle, payload, from)
                if not ok then logEvent("Funkfehler: " .. tostring(err)) end
            end
        end
    end
end

-- Arbeitet die Warteschlange ab, immer ein Auftrag nach dem anderen.
local function workLoop()
    while true do
        -- erst warten, bis ein laufender Werkzeug-Tausch fertig ist - VOR dem
        -- Herausnehmen, damit STOP die Warteschlange noch leert
        while tool.busy do
            tool.want = tool.want + 1
            os.pullEvent("gts_tool")
            tool.want = tool.want - 1
        end
        local job = table.remove(queue, 1)
        if pendingReboot and not job then
            os.sleep(1)
            os.reboot()
        end
        if not job then
            os.pullEvent("gts_job")
        else
            local def = Jobs[job.cmd]
            abort, busy, current, status = false, true, job.cmd, def.status
            if job.cmd == "RUN" and type(job.args) == "table" then status = tostring(job.args.name):upper() end
            last = { seq = job.seq, state = "run" }
            push()
            local ok, res, msg = pcall(def.run, job.args)
            busy, current = false, nil
            pcall(turtle.select, 1)
            if not ok then
                msg = (res == "STOP") and "Gestoppt" or ("Fehler: " .. tostring(res))
            elseif res == false then
                ok = false
            end
            -- STOP/BASIS haben ihre eigene Rueckmeldung schon gesetzt; die bleibt stehen.
            if not (abort and last and last.seq ~= job.seq) then
                last = { seq = job.seq, state = ok and "ok" or "fail", msg = msg }
            end
            status, note = "Bereit", tostring(msg or "-")
            logEvent(note)
            push()
            -- Ergebnis eines Programms per Chat Box direkt an den Besitzer
            if job.cmd == "RUN" and tool.have.chat and data.owner then
                pcall(tell, "#" .. os.getComputerID() .. " " .. (os.getComputerLabel() or "") .. ": " .. note)
            end
        end
    end
end

-- Herzschlag: Status alle 2 s. Im Stand ausserdem Chunky auffrischen,
-- Position per GPS pruefen und die Spitzhacke zuruecklegen.
local function beatLoop()
    local refreshed = -100
    while true do
        if os.clock() - refreshed >= 2 and not tool.busy then
            refreshTools()
            refreshed = os.clock()
        end
        if not busy and not tool.busy then
            if not radioSide() and tool.have.modem then lockTools() setupTools() unlockTools() end
            if chunkyDue() then chunkyRefresh() end
            if not busy and gpsDue(CONFIG.gpsIdle) then gpsCheck() end
            if not busy and tool.workKind ~= nil and not tool.busy then
                lockTools() restoreDig() unlockTools()
            end
        end
        push()
        os.sleep(CONFIG.heartbeat)
    end
end

-- ======================================================================
-- [12] BILDSCHIRM UND START
-- ======================================================================
-- Gleiches Farbschema wie das OS (nur Advanced Turtles haben Farbe).
local THEME = {   -- wie GTS OS 8.0 (Grundton Graphit)
    [colors.white] = 0xF4F4F6, [colors.orange] = 0xFB923C, [colors.yellow] = 0xFACC15,
    [colors.lime] = 0xA3E635, [colors.gray] = 0x1C1D21, [colors.lightGray] = 0x9A9EA7,
    [colors.brown] = 0x2C2E34, [colors.green] = 0x65A30D, [colors.red] = 0xEF4444,
    [colors.black] = 0x101113,
}
local function applyTheme(on)
    if not (term.isColour and term.isColour() and term.setPaletteColour) then return end
    pcall(function()
        for c, v in pairs(THEME) do
            if on then term.setPaletteColour(c, v) else term.setPaletteColour(c, term.nativePaletteColour(c)) end
        end
    end)
end

local hits = {}
local function put(x, y, text, fg, bg)
    term.setCursorPos(x, y)
    term.setTextColor(fg or colors.white)
    term.setBackgroundColor(bg or colors.black)
    term.write(text)
end
local function band(y, bg)
    local w = term.getSize()
    put(1, y, string.rep(" ", w), colors.white, bg)
end
-- Balken mit halber Zeichenbreite als Aufloesung.
local function bar(x, y, w, frac, color)
    frac = math.max(0, math.min(1, frac))
    local halves = math.floor(frac * w * 2 + 0.5)
    local full = math.floor(halves / 2)
    put(x, y, string.rep(" ", full), colors.white, color)
    if halves % 2 == 1 then put(x + full, y, "\149", color, colors.brown) full = full + 1 end
    if full < w then put(x + full, y, string.rep(" ", w - full), colors.white, colors.brown) end
end
local function button(x, y, key, label, fn, primary)
    local bg = primary and colors.white or colors.brown
    put(x, y, " " .. key .. " ", primary and colors.black or colors.lightGray, bg)
    put(x + 3, y, label .. " ", primary and colors.black or colors.white, bg)
    hits[#hits + 1] = { x = x, y = y, w = #label + 4, fn = fn }
    return x + #label + 5
end

local function draw(actions)
    local w, h = term.getSize()
    hits = {}
    term.setBackgroundColor(colors.black)
    term.clear()
    -- Kopf
    band(1, colors.gray) band(2, colors.gray)
    put(2, 1, "GTS SCHWARM", colors.white, colors.gray)
    local who = "#" .. os.getComputerID() .. (os.getComputerLabel() and (" " .. os.getComputerLabel()) or "")
    who = who:sub(1, w - 16)
    put(w - #who, 1, who, colors.lightGray, colors.gray)
    put(2, 2, Net.isDefault and "Passwort: Standard!" or "Funk verschluesselt",
        Net.isDefault and colors.orange or colors.lightGray, colors.gray)
    put(w - #VERSION - 2, 2, "v" .. VERSION, colors.lightGray, colors.gray)

    local lx, vx = 2, 12
    local function row(y, label, text, color)
        if y > h - 2 then return end
        put(lx, y, label, colors.lightGray)
        put(vx, y, tostring(text):sub(1, w - vx), color or colors.white)
    end
    local y = 4
    local st = status .. ((#queue > 0) and (" (+" .. #queue .. ")") or "")
    put(lx, y, "STATUS", colors.lightGray)
    put(vx, y, "\7 ", busy and colors.yellow or colors.lime)
    put(vx + 2, y, st:sub(1, w - vx - 2), busy and colors.yellow or colors.lime)
    y = y + 1
    local fuel = turtle.getFuelLevel()
    put(lx, y, "TANK", colors.lightGray)
    if fuel == "unlimited" then
        put(vx, y, "unbegrenzt", colors.white)
    else
        local bw = math.max(4, w - vx - 7)
        bar(vx, y, bw, fuel / math.max(1, CONFIG.refuelTarget), (fuel < 500) and colors.red or colors.lime)
        put(vx + bw + 1, y, tostring(fuel):sub(1, w - vx - bw - 1), (fuel < 500) and colors.red or colors.white)
    end
    y = y + 1
    local used = usedSlots()
    put(lx, y, "INVENTAR", colors.lightGray)
    local bw = math.max(4, w - vx - 7)
    bar(vx, y, bw, used / 16, (used >= CONFIG.trashAt) and colors.orange or colors.green)
    put(vx + bw + 1, y, used .. "/16", colors.white)
    y = y + 1
    local facing = data.compass and COMPASS[(data.compass + pos.f) % 4] or tostring(pos.f)
    row(y, "POSITION", pos.x .. " " .. pos.y .. " " .. pos.z .. "  Blick " .. facing, posOk and colors.white or colors.red)
    y = y + 1
    local wx, wy, wz = relToWorld(pos.x, pos.y, pos.z)
    if wx then row(y, "WELT", wx .. " " .. wy .. " " .. wz .. (gpsState.ok and "  GPS" or ""))
    elseif data.world then row(y, "WELT", "Richtung folgt per GPS", colors.orange)
    else row(y, "WELT", "unbekannt - Basis setzen (H)", colors.orange) end
    y = y + 1
    -- Werkzeuge im Inventar (Modem und Spitzhacke stecken fest)
    local tl = {}
    for _, k in ipairs(TOOL_ORDER) do
        if tool.have[k] and k ~= "modem" then tl[#tl + 1] = TOOLS[k].label end
    end
    if #tl > 0 or not tool.have.pick then
        row(y, "WERKZEUG", tool.have.pick and table.concat(tl, " ") or ("KEINE HACKE! " .. table.concat(tl, " ")),
            tool.have.pick and colors.white or colors.red)
        y = y + 1
    end
    local progs = {}
    for name in pairs(Progs.hashes) do progs[#progs + 1] = name end
    table.sort(progs)
    row(y, "PROGRAMME", (#progs > 0) and table.concat(progs, " ") or "noch keine (kommen vom OS)",
        (#progs > 0) and colors.white or colors.lightGray)
    y = y + 1
    if data.program then
        row(y, "AUFTRAG", data.program.name:upper() .. (data.program.paused and " pausiert" or " laeuft"),
            data.program.paused and colors.orange or colors.yellow)
        y = y + 1
    end
    row(y, "LETZTE", note, colors.lightGray)
    y = y + 1
    if not posOk then row(y, "ACHTUNG", "Position unsicher!", colors.red)
    elseif #data.finds > 0 then row(y, "FUNDE", #data.finds .. " noch nicht gemeldet", colors.yellow) end

    -- Knoepfe (antippen oder Taste druecken)
    local by = h - 1
    local x = 2
    if not busy then x = button(x, by, "H", "BASIS", actions.home) end
    if not busy then x = button(x, by, "P", "PASSWORT", actions.password) end
    button(x, by, "Q", "ENDE", actions.quit)
end

local function prompt(title, lines, mask)
    local w = term.getSize()
    applyTheme(true)
    term.setBackgroundColor(colors.black)
    term.clear()
    band(1, colors.gray)
    put(2, 1, title, colors.white, colors.gray)
    for i, l in ipairs(lines) do put(2, 2 + i, l[1], l[2] or colors.white) end
    put(2, 11, string.rep(" ", w - 2), colors.white, colors.brown)
    term.setCursorPos(3, 11)
    term.setTextColor(colors.white)
    term.setBackgroundColor(colors.brown)
    local text = read(mask) or ""
    term.setBackgroundColor(colors.black)
    return text
end

-- Fragt das Schwarm-Passwort ab (wie am OS). Leer = Standard "gts".
local function askPassword()
    local text = prompt("SCHWARM-PASSWORT", {
        { "Dasselbe Passwort wie am OS" },
        { "(INFO > EINSTELLUNGEN)." },
        { "" },
        { "Damit ist der Funk verschluesselt:", colors.lightGray },
        { "Fremde sehen nur Zeichensalat.", colors.lightGray },
        { "" },
        { "Leer lassen = Standard (unsicher)", colors.orange },
    }, "*")
    put(2, 13, "Berechne Schluessel ...", colors.lightGray)
    if text == "" then
        Net.setKey(Net.derive("gts"), true, os.epoch("utc"))
    else
        Net.setKey(Net.derive(text), false, os.epoch("utc"))
    end
    Net.save(CONFIG.keyFile)
end

-- Fragt die Welt-Koordinaten der Basis ab (ohne GPS).
local function askWorld()
    local text = prompt("BASIS FESTLEGEN", {
        { "Koordinaten dieser Turtle und ihre" },
        { "Blickrichtung (F3), zum Beispiel:" },
        { "" },
        { "  120 64 -340 n", colors.lime },
        { "" },
        { "n/o/s/w = Nord, Ost, Sued, West", colors.lightGray },
        { "Leer lassen = ohne Welt-Koordinaten", colors.lightGray },
    })
    local world, compass = parseWorld(text)
    if not world and text:match("%S") then
        put(2, 13, "Nicht verstanden - uebersprungen.", colors.red)
        os.sleep(1.5)
    end
    return world, compass
end

-- Basis setzen: mit GPS automatisch, sonst Koordinaten abfragen.
local function setHome()
    if gpsFix() then
        enqueue("SETHOME", nil, {})
    else
        local world, compass = askWorld()
        enqueue("SETHOME", nil, { world = world, compass = compass })
    end
end

local function uiLoop()
    local done = false
    local actions = {
        home = function() if not busy then setHome() end end,
        password = function() if not busy then askPassword() end end,
        quit = function() done = true end,
    }
    applyTheme(true)
    draw(actions)
    while not done do
        local ev, a, b, c = os.pullEvent()
        if ev == "char" then
            local ch = a:lower()
            if ch == "h" then actions.home()
            elseif ch == "p" then actions.password()
            elseif ch == "q" then actions.quit() end
        elseif ev == "mouse_click" then
            for _, hit in ipairs(hits) do
                if c == hit.y and b >= hit.x and b < hit.x + hit.w then hit.fn() break end
            end
        elseif ev == "turtle_inventory" then
            if not tool.busy then refreshTools() end
        end
        if ev == "gts_ui" or ev == "char" or ev == "mouse_click" or ev == "term_resize" or ev == "turtle_inventory" then
            if not done then draw(actions) end
        end
    end
end

-- Start
local first = loadState()
if not Net.load(CONFIG.keyFile) then askPassword() end
fs.makeDir(CONFIG.progDir)
Progs.scan()
refreshTools()
if first then
    applyTheme(true)
    term.clear()
    put(2, 2, "Suche GPS ...", colors.lightGray)
    local job
    if gpsFix() then
        job = { world = nil }
    else
        local world, compass = askWorld()
        job = { world = world, compass = compass }
    end
    local ok, res, msg = pcall(Jobs.SETHOME.run, job)
    note = tostring(msg or res)
end
-- Nach einem Neustart: Position per GPS pruefen (korrigiert auch einen
-- Schritt, der beim Abschalten nicht mehr gespeichert wurde).
if not first then pcall(gpsCheck) end
-- Unterbrochenes Programm (Chunk entladen, Server-Neustart) fortsetzen.
if data.program and not data.program.paused and posOk then
    enqueue("RUN", nil, { name = data.program.name, resume = true })
end

parallel.waitForAny(uiLoop, netLoop, workLoop, beatLoop)

-- Beendet: Werkzeug-Sperre loesen, Spitzhacke zurueck, Turtle-Funktionen
-- verhalten sich fuer andere Programme wieder normal (Zaehlen bleibt).
agentOn = false
tool.busy, tool.owner, tool.depth, tool.want = false, nil, 0, 0
pcall(restoreDig)
afterMove, onCheck = nil, nil

applyTheme(false)
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
print("Schwarm-Agent beendet. Position wird weiter mitgezaehlt.")
