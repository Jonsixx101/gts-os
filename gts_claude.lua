-- ======================================================================
-- GTS OS Claude 1.2.1 - Kernel, UI und Apps            (CC: Tweaked, MC 1.21.1)
-- by Jonsi
-- ======================================================================
-- Laeuft auf dem Advanced Computer, am liebsten mit Advanced Monitor
-- (5x2 Bloecke = 100x24 Zeichen, Touch). Fuer den Advanced Pocket
-- Computer gibt es eigene Fassungen: gts_pocket.lua (Fortschritts-Tablet),
-- gts_phone.lua (Handy fuer Freunde) und gts_claude.lua (Claude-Fernbedienung).
--
-- Aufbau (angelehnt an den Opus-Kernel):
--   [1] Konfiguration, Farbschema, Verschluesselung, Einstellungen
--   [2] Kernel    Routinen, Log, Hardware, Codesperre
--   [3] UI        Zeichnen, Taskleiste, Kopfzeilen, Buttons, Listen
--   [4] Apps      Registry + Plugin-Ordner /gts/apps
--   [5] Home / Boot
--   [6] Notizen + Editor + Bildschirmtastatur + Drucken
--   [7] Flotten   Schwarm (Turtles), Turtle-Programme, Funde, P. Craft
--        Claude   Begleit-Droide (eigene App, Programm "claude" auf einer Turtle)
--   [8] Daten     Disketten sichern, Notizen und OS auf Diskette
--   [9] Web       Textbrowser (Wikis, Dokus, Pastebin)
--   [10] Rechner  Taschenrechner mit Prozent und Stacks
--   [11] Shell    CraftOS-Shell im Fenster (edit, delete, eigene Programme)
--   [12] Lua Apps Dateien und Ordner in /scripts (mit dem Ordner games)
--   [13] Games    Snake, Runner, Dino, Pong
--   [14] Lager    Storage-System ueber Wired Modems (wie ein ME-System)
--        Extras   Player Detector, Chat Box, Speaker (wenn vorhanden)
--   [15] System   Hilfe, Papierkorb, Backup, Update, System-Check,
--                 Absturz-Bildschirm, sicherer Modus; danach INFO
--   [16] Dienste und Start
-- ======================================================================

-- Version: RELEASE wird angezeigt (1.1.0 = erstes Update der Vollversion,
-- 1.2.0 = Claude, 1.2.1 = Claude-Wegfindung neu und AUFRAEUMEN).
-- VERSION ist die interne Update-Nummer: steigt mit jeder Fassung und muss
-- groesser als "8.0" sein (so hiess die erste Vollversion), sonst findet ein
-- dort installiertes OS das Update nicht. Nirgends angezeigt.
local VERSION = "8.3"
local RELEASE = "1.2.1"
local EDITION = "claude" -- "pc" in gts_os.lua
local READONLY = (EDITION ~= "pc")      -- Pocket/Handy: nur anzeigen, keine Befehle
local PHONE = (EDITION == "phone")      -- GTS Phone: Handy fuer Freunde (Lager, Notizen, Rechner ...)

-- ======================================================================
-- [1] KONFIGURATION
-- ======================================================================
local CONFIG = {
    exploreDist  = settings.get("gts.dist", 96),   -- Tunnel-Laenge bei DD
    minW         = 51,    -- kleinste nutzbare Breite
    minH         = 19,    -- kleinste nutzbare Hoehe
    offlineAfter = 8,     -- Sek. ohne Signal -> OFFLINE
    forgetAfter  = 3600,  -- Sek. ohne Signal -> aus Liste entfernt
    maxUnits     = 200,   -- Obergrenze je Flotte (Schutz vor Funk-Spam)
    notesDir     = "/notes",
    backupDir    = "/backups",
    logFile      = "/sys/logs/gts.log",
    appDir       = "/gts/apps",      -- Erweiterungen fuer das OS selbst
    scriptDir    = "/scripts",       -- eigene Programme (Reiter LUA APPS)
    dbFile       = "/gts/schwarm.db",  -- Funde und Richtungs-Zuteilung
    diskNotes    = "gts_notizen",   -- Ordner fuer Notizen auf der Diskette
    diskOS       = "gts_os.lua",    -- Sicherung von /startup.lua auf der Diskette
    keyFile      = "/gts/.schluessel",      -- abgeleiteter Funk-Schluessel
    settingsFile = "/gts/einstellungen.db",
    progDir      = "/scripts/turtle",       -- Turtle-Programme (DD, CHUNK, TEST, Agent)
    itemsDb      = "/gts/items.db",         -- gelernte Items (Lager)
    lagerDb      = "/gts/lager.db",         -- Lager: Kisten-Rollen
    phonePassword = "1234",                 -- Standard-Handy-Passwort (GTS Phone: nur Lager-Daten)
    netherDb     = "/gts/nether.db",        -- NETHER-Rechner: letzte Umrechnungen
}

-- Farbschema: die 16 Farben von ComputerCraft bekommen modernere Toene.
-- Die Farbnamen behalten ihre Bedeutung, vier werden zu Flaechen/Schrift:
--   black = Hintergrund, gray = Flaeche (Leisten, Karten),
--   brown = erhoehte Flaeche (Buttons, Eingabefelder),
--   white = Schrift, lightGray = Nebenschrift,
--   lime  = AKZENT (sparsam: aktiver Reiter, Status, Fortschritt).
-- Grundton und Akzent sind in INFO > EINSTELLUNGEN waehlbar (v8.0).
local THEMES = {
    { id = "graphit",     name = "Graphit",     bg = 0x101113, surface = 0x1C1D21, raised = 0x2C2E34, dim = 0x9A9EA7, text = 0xF4F4F6 },
    { id = "mitternacht", name = "Mitternacht", bg = 0x0B1020, surface = 0x151B2E, raised = 0x242C44, dim = 0x96A2C0, text = 0xF1F4FA },
    { id = "wald",        name = "Wald",        bg = 0x0E1110, surface = 0x1F2621, raised = 0x333D35, dim = 0x8D998F, text = 0xF0F4EE },
}
local ACCENTS = {
    { id = "gruen", name = "Gruen", rgb = 0xA3E635 }, { id = "blau", name = "Blau", rgb = 0x60A5FA },
    { id = "tuerkis", name = "Tuerkis", rgb = 0x2DD4BF }, { id = "orange", name = "Orange", rgb = 0xFB923C },
    { id = "lila", name = "Lila", rgb = 0xC084FC }, { id = "rosa", name = "Rosa", rgb = 0xF472B6 },
    { id = "weiss", name = "Weiss", rgb = 0xE5E7EB },
}
local THEME = {
    [colors.white]  = 0xF4F4F6, [colors.orange]    = 0xFB923C, [colors.magenta] = 0xE879F9,
    [colors.lightBlue] = 0x7DD3FC, [colors.yellow] = 0xFACC15, [colors.lime]    = 0xA3E635,
    [colors.pink]   = 0xF472B6, [colors.gray]      = 0x1C1D21, [colors.lightGray] = 0x9A9EA7,
    [colors.cyan]   = 0x22D3EE, [colors.purple]    = 0xA78BFA, [colors.blue]    = 0x3B82F6,
    [colors.brown]  = 0x2C2E34, [colors.green]     = 0x65A30D, [colors.red]     = 0xEF4444,
    [colors.black]  = 0x101113,
}

-- Grundton + Akzent in die Palette uebernehmen (wirkt ab dem naechsten Bild).
local function setTheme(themeId, accentId)
    local t, a = THEMES[1], ACCENTS[1]
    for _, x in ipairs(THEMES) do if x.id == themeId then t = x end end
    for _, x in ipairs(ACCENTS) do if x.id == accentId then a = x end end
    THEME[colors.black], THEME[colors.gray], THEME[colors.brown] = t.bg, t.surface, t.raised
    THEME[colors.lightGray], THEME[colors.white] = t.dim, t.text
    THEME[colors.lime] = a.rgb
    -- dunklere Fassung des Akzents (z.B. Balken-Hintergrund)
    local r, g, b = math.floor(a.rgb / 65536), math.floor(a.rgb / 256) % 256, a.rgb % 256
    THEME[colors.green] = math.floor(r * 0.6) * 65536 + math.floor(g * 0.6) * 256 + math.floor(b * 0.6)
end

-- Setzt das Farbschema (oder die Standardfarben) auf einem Bildschirm.
local function applyPalette(t, themed)
    if not (t and t.setPaletteColour) then return end
    pcall(function()
        for i = 0, 15 do
            local c = 2 ^ i
            if themed then
                t.setPaletteColour(c, THEME[c])
            elseif term.nativePaletteColour then
                t.setPaletteColour(c, term.nativePaletteColour(c))
            end
        end
    end)
end

local nativeTerm = term.current()

-- ======================================================================
-- VERSCHLUESSELUNG (ccryptolib) UND SICHERER FUNK
-- ======================================================================
-- @@CRYPTO-BEGIN
local CRYPTO_SRC = [===[
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
]===]
local Crypto = load(CRYPTO_SRC .. "\nreturn Crypto", "=crypto", "t", _ENV)()
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

-- ---------- Dateien: Tabellen laden und sicher speichern ----------
-- Speichern schreibt erst "<datei>.neu" und tauscht dann: ein Absturz
-- mitten im Schreiben laesst die alte Fassung heil. Mit backup = true
-- bleibt die vorige Fassung als "<datei>.bak" liegen und wird genommen,
-- wenn die Datei kaputt ist (Einstellungen, Kategorien ...).
Store = {}

function Store.read(path)
    if not fs.exists(path) or fs.isDir(path) then return nil end
    local h = fs.open(path, "r")
    if not h then return nil end
    local s = h.readAll()
    h.close()
    return s
end

function Store.write(path, text)
    local tmp = path .. ".neu"
    local ok = pcall(function()
        local dir = fs.getDir(path)
        if dir ~= "" and not fs.exists(dir) then fs.makeDir(dir) end
        local h = fs.open(tmp, "w")
        h.write(text)
        h.close()
    end)
    if not ok then pcall(fs.delete, tmp) return false end
    pcall(function()
        if fs.exists(path) then fs.delete(path) end
        fs.move(tmp, path)
    end)
    return fs.exists(path)
end

function Store.load(path)
    -- fehlt die Datei, aber "<datei>.neu" ist da, war das Speichern fast fertig
    local list = fs.exists(path) and { path, path .. ".bak" } or { path .. ".neu", path .. ".bak" }
    for _, p in ipairs(list) do
        local s = Store.read(p)
        local t = s and textutils.unserialize(s)
        if type(t) == "table" then return t end
    end
    return nil
end

function Store.save(path, t, backup)
    local ok, text = pcall(textutils.serialize, t, { compact = true })
    if not ok then ok, text = pcall(textutils.serialize, t) end
    if not ok then return false end
    if backup and fs.exists(path) then
        pcall(function()
            if fs.exists(path .. ".bak") then fs.delete(path .. ".bak") end
            fs.copy(path, path .. ".bak")
        end)
    end
    return Store.write(path, text)
end

-- ---------- Einstellungen (Datei /gts/einstellungen.db) ----------
local Settings = { data = {
    code       = nil,     -- Pruefwert des Sperrcodes (Standard 3344)
    autoLock   = 10,      -- Minuten ohne Bedienung bis zur Sperre (0 = aus)
    owner      = "",      -- Spielername fuer Chat-Meldungen
    trusted    = {},      -- Spieler, die keinen Alarm ausloesen
    alarmRadius = 24,     -- Player Detector: Radius in Bloecken
    chunkTrash = true,    -- CHUNK: Muell unterwegs wegwerfen
    ddDist     = 96,      -- DD: Tunnel-Laenge in Bloecken
} }

function Settings.load()
    local t = Store.load(CONFIG.settingsFile)
    if not t then return end
    for k, v in pairs(t) do
        if Settings.data[k] == nil or type(Settings.data[k]) == type(v) then Settings.data[k] = v end
    end
end

function Settings.save() Store.save(CONFIG.settingsFile, Settings.data, true) end

function Settings.get(k) return Settings.data[k] end
function Settings.set(k, v) Settings.data[k] = v Settings.save() end

-- Sperrcode: gespeichert wird nur ein Pruefwert.
function Settings.codeHash(code) return Net.hash("GTS-CODE:" .. tostring(code)) end
function Settings.checkCode(code)
    return Settings.codeHash(code) == (Settings.data.code or Settings.codeHash("3344"))
end

-- ======================================================================
-- [2] KERNEL
-- ======================================================================
local Kernel = {
    running  = true,
    routines = {},
    hw       = { modem = false, printer = nil, drives = {} },
    display  = nil,   -- { monitor, touch, target, name }
    screen   = nil,   -- gepuffertes Fenster, in das alles gezeichnet wird
    W = 0, H = 0,     -- ganzer Bildschirm
    w = 0, h = 0,     -- Bereich der Apps (ohne Taskleiste unten)
    app      = nil,
    menu     = false, -- App-Menue der Taskleiste offen
    clock    = "",    -- angezeigte Uhrzeit
    dirty    = false, -- Bildschirm muss neu gezeichnet werden
    wakeSent = false,
    toast    = nil,   -- Meldung ueber der Taskleiste
    armed    = nil,   -- Button, der auf Bestaetigung wartet
    seq      = 0,     -- laufende Befehlsnummer
    crash    = nil,
    locked   = true,  -- Codesperre: nach dem Start gesperrt
    popup    = nil,   -- offenes Code-Fenster { title, entered, onOk, err }
    fails    = 0,     -- falsche Code-Eingaben am Stueck
    lastInput = 0,    -- os.clock() der letzten Bedienung (Auto-Sperre)
    inbox    = {},    -- Mitteilungen (neueste zuerst), Uhr in der Taskleiste antippen
    panel    = false, -- Mitteilungen offen
    helpApp  = nil,   -- Hilfe-Karte "?" dieser App offen
}

local UI, Apps, Extras, Sys  -- weiter unten definiert
local Fleets = {}  -- Protokoll -> Flotten-App (in [7] gefuellt)

-- ---------- Log ----------
-- Schluessel fuer die GTS Phones (eigenes Handy-Passwort, Standard 1234).
-- Damit lesen Freunde nur die Lager-Uebersicht - nie den Turtle-Funk.
function Kernel.phoneKey()
    if READONLY then return nil end
    local hex = Settings.get("phoneKey")
    local key = type(hex) == "string" and Net.fromHex(hex)
    if key and #key == 32 then return key end
    key = Net.derive(CONFIG.phonePassword)
    Settings.set("phoneKey", Net.toHex(key))
    return key
end

function Kernel.log(level, text)
    local line = string.format("[%s] %-6s %s", os.date("%H:%M:%S"), level, tostring(text))
    pcall(function()
        if fs.exists(CONFIG.logFile) and fs.getSize(CONFIG.logFile) > 16000 then
            local old = CONFIG.logFile .. ".alt"
            if fs.exists(old) then fs.delete(old) end
            fs.move(CONFIG.logFile, old)
        end
        local f = fs.open(CONFIG.logFile, "a")
        if f then f.writeLine(line) f.close() end
    end)
    -- Laeuft die Oberflaeche auf dem Monitor, dient der PC-Schirm als Konsole.
    if Kernel.display and Kernel.display.monitor then print(line) end
end

-- Meldung: kurz ueber der Taskleiste und dauerhaft in den Mitteilungen.
-- Warnungen (rot/orange/gelb) und Meldungen mit Ziel-App zaehlen als neu
-- (roter Zaehler an der Uhr). app/arg: Antippen oeffnet Kernel.open(app, arg).
function Kernel.notify(text, color, app, arg)
    text, color = tostring(text), color or colors.lime
    Kernel.toast = { text = text, color = color, untilT = os.clock() + 4 }
    Kernel.log("INFO", text)
    local box, new = Kernel.inbox, (color == colors.red or color == colors.orange or color == colors.yellow or app ~= nil)
    if box[1] and box[1].text == text then
        box[1].n, box[1].time, box[1].new = (box[1].n or 1) + 1, os.date("%H:%M"), box[1].new or new
    else
        table.insert(box, 1, { text = text, color = color, time = os.date("%H:%M"), app = app, arg = arg, new = new })
        if #box > 40 then box[#box] = nil end
    end
    Kernel.invalidate()
end

function Kernel.unread()
    local n = 0
    for _, e in ipairs(Kernel.inbox) do if e.new then n = n + 1 end end
    return n
end

-- Mitteilungen schliessen: alles gilt als gelesen.
function Kernel.closePanel()
    Kernel.panel = false
    for _, e in ipairs(Kernel.inbox) do e.new = false end
    Kernel.invalidate()
end

-- Neuzeichnen anfordern. Viele Anforderungen ergeben nur EIN Neuzeichnen.
function Kernel.invalidate()
    Kernel.dirty = true
    if not Kernel.wakeSent then
        Kernel.wakeSent = true
        os.queueEvent("gts_redraw")
    end
end

-- ---------- Routinen (wie Opus: jede Routine hat ihren eigenen Event-Filter) ----------
function Kernel.resume(r, ev, ...)
    if r.dead then return end
    if r.filter and ev ~= r.filter then return end
    local ok, res = coroutine.resume(r.co, ev, ...)
    if not ok then
        Kernel.log("FEHLER", r.name .. ": " .. tostring(res))
        local now = os.clock()
        if now - (r.lastFail or -100) > 30 then r.fails = 0 end
        r.fails, r.lastFail = r.fails + 1, now
        if r.restart and r.fails <= 5 then
            r.co, r.filter = coroutine.create(r.fn), nil
            return Kernel.resume(r)
        end
        r.dead = true
        if r.critical then
            Kernel.crash = r.name .. ": " .. tostring(res)
            Kernel.running = false
        end
    elseif coroutine.status(r.co) == "dead" then
        r.dead = true
    else
        r.filter = res
    end
end

-- Funk-Warteschlange: Befehle und Programm-Teile gehen der Reihe nach raus,
-- mit einer kurzen Pause dazwischen. So bleibt das OS auch bei einer grossen
-- Uebertragung (Agent-Update an viele Turtles) bedienbar.
Kernel.outbox = {}
function Kernel.post(id, payload)
    if #Kernel.outbox >= 600 then return false end
    Kernel.outbox[#Kernel.outbox + 1] = { id = id, p = payload }
    os.queueEvent("gts_out")
    return true
end

function Kernel.spawn(name, fn, restart, critical)
    local r = { name = name, fn = fn, restart = restart, critical = critical,
                co = coroutine.create(fn), fails = 0 }
    table.insert(Kernel.routines, r)
    Kernel.resume(r)
    return r
end

-- ---------- Hardware ----------
function Kernel.scanHardware()
    local hw = { modem = false, printer = nil, drives = {}, modems = {}, monitors = {}, all = {}, inventories = {} }
    local names = peripheral.getNames()
    table.sort(names)
    for _, name in ipairs(names) do
        local kind = peripheral.getType(name)
        local okInv, inv = pcall(function() return peripheral.hasType and peripheral.hasType(name, "inventory") end)
        inv = okInv and inv == true
        hw.all[#hw.all + 1] = { name = name, kind = tostring(kind), inventory = inv }
        if inv then hw.inventories[#hw.inventories + 1] = name end
        if kind == "modem" then
            -- Funk nur ueber Wireless/Ender Modems; ein Wired Modem ist das
            -- Kabel fuers LAGER und zaehlt nicht als Funk.
            local ok, wireless = pcall(peripheral.call, name, "isWireless")
            wireless = (not ok) or wireless == true
            hw.modems[#hw.modems + 1] = { name = name, wireless = wireless }
            if wireless then
                if not rednet.isOpen(name) then pcall(rednet.open, name) end
                hw.modem = true
            end
        elseif kind == "printer" then
            if not hw.printer then hw.printer = peripheral.wrap(name) end
        elseif kind == "drive" then
            hw.drives[#hw.drives + 1] = name
        elseif kind == "monitor" then
            hw.monitors[#hw.monitors + 1] = name
        end
    end
    Kernel.hw = hw
end

-- Sucht einen Farbmonitor, auf den die Oberflaeche passt, und waehlt die
-- groesste Schrift, bei der mindestens 51x19 Zeichen Platz haben.
-- (3x2 Monitor: Schrift 1 = 29x12 -> zu klein, Schrift 0.5 = 57x24 -> passt)
function Kernel.initDisplay()
    local chosen
    for _, mon in ipairs({ peripheral.find("monitor") }) do
        if mon.isColour() then
            for _, scale in ipairs({ 1, 0.5 }) do
                mon.setTextScale(scale)
                local w, h = mon.getSize()
                if w >= CONFIG.minW and h >= CONFIG.minH then
                    chosen = { monitor = true, touch = true, target = mon, name = peripheral.getName(mon) }
                    break
                end
            end
        end
        if chosen then break end
    end
    Kernel.display = chosen or { monitor = false, touch = false, target = nativeTerm }
    if Kernel.display.monitor then Kernel.display.scale = Kernel.display.target.getTextScale() end
    -- Das Farbschema kommt vor dem Fenster auf den Bildschirm: Fenster
    -- uebernehmen beim Anlegen die Farben ihres Bildschirms.
    applyPalette(Kernel.display.target, true)
    Kernel.W, Kernel.H = Kernel.display.target.getSize()
    Kernel.w, Kernel.h = Kernel.W, Kernel.H - UI.barH()
    Kernel.screen = window.create(Kernel.display.target, 1, 1, Kernel.W, Kernel.H, false)
    UI.layoutCache = nil

    nativeTerm.setBackgroundColor(colors.black)
    nativeTerm.setTextColor(colors.white)
    nativeTerm.clear()
    nativeTerm.setCursorPos(1, 1)
    if Kernel.display.monitor then
        print("GTS OS " .. RELEASE .. " laeuft auf Monitor '" .. Kernel.display.name .. "'.")
        print("Tastatur hier aktiv. Strg+T beendet.")
        print("")
    end
    Kernel.log("INFO", "Anzeige: " .. (Kernel.display.monitor and "Monitor " or "PC ") .. Kernel.W .. "x" .. Kernel.H)
end

-- Reagiert auf an-/abgesteckte Geraete und Groessenaenderungen.
function Kernel.hardwareEvent(ev, side)
    local d = Kernel.display
    if ev == "monitor_resize" then
        if not (d.monitor and d.name == side) then return end
        local w, h = d.target.getSize()
        if w == Kernel.W and h == Kernel.H then return end
        Kernel.initDisplay()
    elseif ev == "term_resize" then
        if d.monitor then return end
        Kernel.initDisplay()
    else -- peripheral / peripheral_detach
        Kernel.scanHardware()
        local monitorGone = d.monitor and not peripheral.isPresent(d.name)
        local monitorNew = (not d.monitor) and peripheral.find("monitor") ~= nil
        if monitorGone or monitorNew then Kernel.initDisplay() end
    end
    Kernel.invalidate()
end

function Kernel.open(id, ...)
    local app = Apps.byId[id]
    if not app then return end
    if Kernel.locked and not app.public then
        -- Gesperrt: erst den Code abfragen, dann die App oeffnen.
        local args = table.pack(...)
        return Kernel.askCode("Entsperren", function()
            Kernel.locked = false
            Kernel.log("INFO", "Entsperrt")
            Kernel.open(id, table.unpack(args, 1, args.n))
        end)
    end
    local old = Kernel.app
    if old and old ~= app and old.onLeave then pcall(old.onLeave, old) end
    Kernel.app = app
    Kernel.armed, Kernel.menu, Kernel.helpApp = nil, false, nil
    if Kernel.panel then Kernel.closePanel() end
    if app.onEnter then
        local ok, err = pcall(app.onEnter, app, ...)
        if not ok then Kernel.log("FEHLER", id .. ".onEnter: " .. tostring(err)) end
    end
    Kernel.invalidate()
end

-- ---------- Codesperre ----------
-- Nach dem Start ist das OS gesperrt: Boot und Home sind frei, jede andere
-- App fragt einmal den Code ab (Standard 3344). Danach bleibt es offen, bis
-- jemand auf Home SPERREN tippt oder lange niemand bedient. Aktionen mit
-- Disketten fragen immer, Strg+T wirkt im gesperrten Zustand nicht.
function Kernel.askCode(title, onOk)
    Kernel.menu = false
    Kernel.popup = { title = title or "Code eingeben", entered = "", onOk = onOk }
    Kernel.invalidate()
end

-- Neuen Code eintippen lassen (ohne Pruefung): onOk(ziffern).
function Kernel.askNew(title, onOk)
    Kernel.menu = false
    Kernel.popup = { title = title, entered = "", onOk = onOk, new = true }
    Kernel.invalidate()
end

-- Eingabe ins Code-Fenster: "0".."9", "del", "ok" oder "cancel".
function Kernel.codeKey(k)
    local p = Kernel.popup
    if not p then return end
    Kernel.invalidate()
    if k == "cancel" then Kernel.popup = nil return end
    if p.lockUntil and os.clock() < p.lockUntil then return end
    if k == "del" then
        p.entered, p.err = p.entered:sub(1, -2), nil
    elseif k == "ok" then
        if p.entered == "" then return end
        if p.new then
            Kernel.popup = nil
            local ok, err = pcall(p.onOk, p.entered)
            if not ok then Kernel.notify("Fehler: " .. tostring(err), colors.red) end
        elseif Settings.checkCode(p.entered) then
            Kernel.popup, Kernel.fails, Kernel.lastInput = nil, 0, os.clock()
            local ok, err = pcall(p.onOk)
            if not ok then Kernel.notify("Fehler: " .. tostring(err), colors.red) end
        else
            Kernel.fails = Kernel.fails + 1
            p.entered, p.err = "", "Falscher Code"
            Kernel.log("WARN", "Falscher Sperrcode (" .. Kernel.fails .. ")")
            if Kernel.fails >= 5 then
                Kernel.fails, p.lockUntil, p.err = 0, os.clock() + 30, "Zu viele Versuche: 30 s warten"
            end
        end
    elseif k:find("^%d$") and #p.entered < 8 then
        p.entered, p.err = p.entered .. k, nil
    end
end

function Kernel.lock()
    Kernel.locked, Kernel.popup, Kernel.menu = true, nil, false
    Kernel.log("INFO", "Gesperrt")
    Kernel.open("boot")
end

-- Fuer Aktionen, die immer den Code brauchen (Disketten): liefert eine
-- Funktion fuer onClick.
function Kernel.guard(title, fn)
    return function() Kernel.askCode(title, fn) end
end

-- Ein Fenster liegt ueber der App (Menue oder Code): Eingaben nicht an die App.
function Kernel.modal() return Kernel.menu or Kernel.panel or Kernel.helpApp ~= nil or Kernel.popup ~= nil end

-- Ruft eine App-Funktion geschuetzt auf: ein Fehler in einer App
-- beendet nie das ganze System.
function Kernel.call(app, method, ...)
    local fn = app and app[method]
    if not fn then return end
    local ok, err = pcall(fn, app, ...)
    if not ok then
        Kernel.log("FEHLER", app.id .. "." .. method .. ": " .. tostring(err))
        Kernel.notify("Fehler: " .. tostring(err), colors.red)
    end
end

local function renderFrame()
    local s, app = Kernel.screen, Kernel.app
    s.setVisible(false)
    applyPalette(s, true)    -- ein Programm in der Shell kann die Farben verstellt haben
    UI.begin()
    local keep = #UI.hits
    local ok, err = pcall(app.draw, app)
    UI.surface = colors.black
    if not ok then
        Kernel.log("FEHLER", app.id .. ".draw: " .. tostring(err))
        for i = #UI.hits, keep + 1, -1 do UI.hits[i] = nil end
        UI.fill(1, 1, Kernel.w, app.fullscreen and Kernel.H or Kernel.h, colors.black)
        local y = UI.header("FEHLER", "in " .. app.title)
        for _, line in ipairs(UI.wrap(tostring(err), Kernel.w - 4)) do
            UI.text(3, y, line, colors.red)
            y = y + 1
        end
        UI.button{ x = 3, y = y + 1, text = "ZUR STARTSEITE", style = "primary",
                   onClick = function() Kernel.open("home") end }
    end
    if not app.fullscreen then
        UI.toast()
        UI.taskbar()
        if Kernel.menu then UI.appMenu() end
        if Kernel.panel then UI.inboxPanel() end
    end
    if Kernel.helpApp then UI.helpCard() end
    if Kernel.popup then UI.codePopup() end
    if app.cursor and not Kernel.modal() then pcall(app.cursor, app) end   -- z.B. Cursor der Shell
    s.setVisible(true)
end

function Kernel.render()
    Kernel.dirty = false
    local ok, err = pcall(renderFrame)
    if not ok then
        -- Meist: Monitor wurde abgebaut. Anzeige neu suchen und nochmal zeichnen.
        Kernel.log("FEHLER", "Anzeige: " .. tostring(err))
        Kernel.scanHardware()
        Kernel.initDisplay()
        renderFrame()
    end
end

-- ======================================================================
-- [3] UI
-- ======================================================================
-- Sofortmodus: jede App zeichnet bei jedem Bild alles neu und meldet
-- dabei ihre Touch-Flaechen an (UI.hit). Bausteine:
--   UI.header   Kopfzeile einer App mit Titel und Aktions-Buttons
--   UI.button   Button (Stile primary, secondary, danger, ghost)
--   UI.card     Flaeche fuer einen Listeneintrag oder Block
--   UI.list     blaetterbare Liste mit Seitenanzeige
--   UI.section, UI.chip, UI.bar, UI.input, UI.prompt, UI.empty, UI.pixels
UI = { hits = {}, surface = colors.black }

local HEX = {}
for i = 0, 15 do HEX[2 ^ i] = ("0123456789abcdef"):sub(i + 1, i + 1) end

-- Auf dem Touch-Monitor sind Buttons 2 Zeilen hoch (besser zu treffen).
function UI.bh() return Kernel.display.touch and 2 or 1 end
-- Schmale Bildschirme (Pocket: 26 Zeichen) bekommen ein kompaktes Layout.
function UI.narrow() return Kernel.w < CONFIG.minW end
-- Hoehe der Taskleiste (unten).
function UI.barH() return UI.bh() end
-- Erste Inhaltszeile unter einer einzeiligen Kopfzeile.
function UI.top() return UI.bh() + 2 end

function UI.begin()
    UI.hits, UI.surface = {}, colors.black
    local s = Kernel.screen
    s.setBackgroundColor(colors.black)
    s.setTextColor(colors.white)
    s.clear()
    s.setCursorBlink(false)
end

function UI.text(x, y, text, fg, bg)
    local s = Kernel.screen
    s.setCursorPos(x, y)
    s.setTextColor(fg or colors.white)
    s.setBackgroundColor(bg or UI.surface)
    s.write(text)
end

function UI.fill(x, y, w, h, bg)
    if w < 1 or h < 1 then return end
    local s = Kernel.screen
    s.setBackgroundColor(bg)
    local line = string.rep(" ", w)
    for row = y, y + h - 1 do
        s.setCursorPos(x, row)
        s.write(line)
    end
end

function UI.center(y, text, fg, bg)
    UI.text(math.floor((Kernel.w - #text) / 2) + 1, y, text, fg, bg)
end

function UI.right(y, text, fg, bg)
    UI.text(Kernel.w - #text, y, text, fg, bg)
end

-- Duenne Linie (ein Drittel Zeichenhoehe): pos = "top" | "mid" | "bottom".
function UI.line(x, y, w, color, pos, under)
    if w < 1 then return end
    under = under or UI.surface
    if pos == "bottom" then
        UI.text(x, y, string.rep("\143", w), under, color)
    else
        UI.text(x, y, string.rep(pos == "top" and "\131" or "\140", w), color, under)
    end
end

-- Touch-Flaeche. fn bekommt die Klick-Koordinaten.
function UI.hit(x, y, w, h, fn)
    UI.hits[#UI.hits + 1] = { x = x, y = y, w = w, h = h, fn = fn }
end

-- Button-Stile: { Flaeche, Schrift }
UI.styles = {
    primary   = { colors.white, colors.black },   -- Hauptaktion / gewaehlt (hell, ruhig)
    accent    = { colors.lime, colors.black },    -- selten: Akzent
    secondary = { colors.brown, colors.white },
    danger    = { colors.brown, colors.red },
    ghost     = { false, colors.lightGray },
}

-- Button. o = { x, y, w, h, text, style, bg, fg, onClick, disabled, confirm, solid }
-- confirm = "id": erster Druck schaerft den Button ("SICHER?"), zweiter fuehrt aus.
-- Zwei Zeilen hohe Buttons (Monitor) bekommen unten nur einen schmalen
-- Rand: die Schrift sitzt dann mittig, die Touch-Flaeche bleibt 2 Zeilen.
-- Rueckgabe: x-Position rechts neben dem Button.
function UI.button(o)
    local w, h = o.w or (#o.text + 2), o.h or UI.bh()
    local st = UI.styles[o.style or "secondary"] or UI.styles.secondary
    local under = UI.surface
    local bg, fg = o.bg or st[1] or under, o.fg or st[2]
    local text, fn = o.text, o.onClick
    if o.disabled then
        -- ausgegraut: gleiche Form, gedaempfte Schrift, keine Aktion
        fn = nil
        if bg ~= under then bg = colors.brown end
        fg = (bg == colors.brown) and colors.lightGray or colors.brown
    elseif o.confirm then
        local a = Kernel.armed
        if a and a.id == o.confirm and os.clock() < a.untilT then
            text, bg, fg = (w >= 9) and "SICHER?" or "OK?", colors.red, colors.white
            fn = function() Kernel.armed = nil o.onClick() end
        else
            fn = function() Kernel.armed = { id = o.confirm, untilT = os.clock() + 3 } end
        end
    end
    if #text > w then text = text:sub(1, w) end
    local tx = o.x + math.floor((w - #text) / 2)
    if h == 2 and not o.solid then
        UI.fill(o.x, o.y, w, 1, bg)
        UI.text(tx, o.y, text, fg, bg)
        if bg ~= under then UI.line(o.x, o.y + 1, w, bg, "top", under) end
    else
        UI.fill(o.x, o.y, w, h, bg)
        UI.text(tx, o.y + math.floor((h - 1) / 2), text, fg, bg)
    end
    if fn then UI.hit(o.x, o.y, w, h, fn) end
    return o.x + w
end

function UI.click(x, y)
    for i = #UI.hits, 1, -1 do
        local r = UI.hits[i]
        if x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h then
            local ok, err = pcall(r.fn, x, y)
            if not ok then
                Kernel.log("FEHLER", "Klick: " .. tostring(err))
                Kernel.notify("Fehler: " .. tostring(err), colors.red)
            end
            Kernel.invalidate()
            return true
        end
    end
    return false
end

-- Flaeche fuer Karten und Listeneintraege. Buttons darauf passen sich an.
function UI.card(x, y, w, h, color)
    UI.surface = color or colors.gray
    UI.fill(x, y, w, h, UI.surface)
end

-- Karte fuer einen Listeneintrag ueber die ganze Breite.
-- Rueckgabe: x fuer den Text, rechte Kante fuer Buttons.
function UI.rowCard(y, h)
    local narrow = UI.narrow()
    local x0, cw = narrow and 1 or 2, narrow and Kernel.w or (Kernel.w - 2)
    UI.card(x0, y, cw, h)
    return x0 + 2, x0 + cw - 2
end

-- Setzt Buttons nebeneinander, sodass der letzte bei xr endet.
-- Rueckgabe: x des ersten Buttons.
function UI.buttonsRight(list, y, xr, xl)
    local total = -1
    for _, b in ipairs(list) do
        b.w = b.w or (#b.text + 2)
        total = total + b.w + 1
    end
    -- zu breit (schmaler Schirm): erst den Rand in den Buttons weglassen
    xl = xl or 1
    if xr - total + 1 < xl then
        total = -1
        for _, b in ipairs(list) do
            if b.w == #b.text + 2 then b.w = #b.text end
            total = total + b.w + 1
        end
    end
    local x = math.max(xl, xr - total + 1)
    local left = x
    for _, b in ipairs(list) do
        b.x, b.y = x, y
        x = UI.button(b) + 1
    end
    return left
end

-- Setzt Buttons von links nach rechts und bricht um, wenn die Zeile voll ist.
-- Rueckgabe: erste Zeile unter den Buttons.
function UI.flow(list, x0, y, xMax)
    local bh, x = UI.bh(), x0
    for _, b in ipairs(list) do
        b.w = b.w or (#b.text + 2)
        if x > x0 and x + b.w - 1 > xMax then x, y = x0, y + bh + ((bh >= 2) and 0 or 1) end
        b.x, b.y = x, y
        x = UI.button(b) + 1
    end
    return y + bh
end

-- Hoehe (Zeilen), die UI.flow fuer diese Buttons braucht.
function UI.flowHeight(list, x0, xMax)
    local bh, x, rows = UI.bh(), x0, 1
    for _, b in ipairs(list) do
        local bw = b.w or (#b.text + 2)
        if x > x0 and x + bw - 1 > xMax then x, rows = x0, rows + 1 end
        x = x + bw + 1
    end
    return rows * bh + (rows - 1) * ((bh >= 2) and 0 or 1)
end

-- Kleines Etikett " text ". Rueckgabe: x rechts daneben.
function UI.chip(x, y, text, fg, bg)
    UI.text(x, y, " " .. text .. " ", fg or colors.white, bg or colors.brown)
    return x + #text + 2
end

-- Ueberschrift innerhalb einer App: "TEXT ------------"
function UI.section(x, y, text, w)
    w = w or (Kernel.w - x)
    UI.text(x, y, text, colors.lightGray)
    UI.line(x + #text + 1, y, w - #text - 1, colors.brown, "mid")
end

-- Fortschrittsbalken mit halber Zeichenbreite als Aufloesung.
function UI.bar(x, y, w, frac, color, track)
    track = track or colors.brown
    frac = math.max(0, math.min(1, frac or 0))
    local halves = math.floor(frac * w * 2 + 0.5)
    local full = math.floor(halves / 2)
    if full > 0 then UI.fill(x, y, full, 1, color) end
    if halves % 2 == 1 then UI.text(x + full, y, "\149", color, track) full = full + 1 end
    if full < w then UI.fill(x + full, y, w - full, 1, track) end
end

-- Eingabefeld mit Cursor am Ende.
function UI.input(x, y, w, text, focused)
    local shown = text
    if #shown > w - 2 then shown = shown:sub(#shown - w + 3) end
    UI.fill(x, y, w, 1, colors.brown)
    UI.text(x + 1, y, shown, colors.white, colors.brown)
    if focused ~= false then UI.text(x + 1 + #shown, y, " ", colors.black, colors.white) end
end

-- Leerer Zustand: Titel und Hinweis mittig.
function UI.empty(y, title, hint)
    UI.center(y, title, colors.white)
    if hint then
        for i, line in ipairs(UI.wrap(hint, Kernel.w - 4)) do UI.center(y + i, line, colors.lightGray) end
    end
end

-- Eingabe-Dialog (Name, Adresse, Suchbegriff). o = { y, title, text, hint,
-- err, maxW, onOk, onCancel }. Die Tastatur am Monitor zeichnet die App.
function UI.prompt(o)
    local w, bh = Kernel.w, UI.bh()
    local narrow = UI.narrow()
    local cw = narrow and w or math.min(w - 4, 60)
    local cx = math.floor((w - cw) / 2) + 1
    local y = o.y
    local title = UI.wrap(o.title, cw - 3)
    local extra = #title - 1
    local h = 5 + extra + bh + (narrow and 0 or 1)
    UI.card(cx, y, cw, h)
    for i, line in ipairs(title) do
        UI.text(cx + 2, y + i - 1, line, colors.white, colors.gray)
    end
    y = y + extra
    UI.input(cx + 2, y + 2, math.min(cw - 4, o.maxW or cw), o.text)
    UI.text(cx + 2, y + 3, (o.err or o.hint or ""):sub(1, cw - 4), o.err and colors.red or colors.lightGray, colors.gray)
    local by = y + 5
    local x = UI.button{ x = cx + 2, y = by, w = 8, text = "OK", style = "primary", onClick = o.onOk } + 1
    UI.button{ x = x, y = by, w = 11, text = "ABBRUCH", onClick = o.onCancel }
    UI.surface = colors.black
    return o.y + h
end

-- Pixelgrafik mit Teletext-Zeichen: ein Zeichen zeigt 2x3 Pixel in zwei
-- Farben. px(x, y) liefert die Farbe eines Pixels (1-basiert).
-- Rueckgabe: je Zeile { Zeichen, Schriftfarben, Hintergruende } fuer blit.
function UI.pixelRows(cols, rows, px)
    local out = {}
    for r = 0, rows - 1 do
        local ch, fgs, bgs = {}, {}, {}
        for c = 0, cols - 1 do
            local p, count = {}, {}
            for i = 0, 5 do
                local col = px(c * 2 + i % 2 + 1, r * 3 + math.floor(i / 2) + 1)
                p[i + 1] = col
                count[col] = (count[col] or 0) + 1
            end
            -- Unten rechts ist im Zeichensatz immer Hintergrund.
            local bg, fg, best = p[6], p[6], 0
            for col, n in pairs(count) do
                if col ~= bg and n > best then fg, best = col, n end
            end
            local bits = 0
            for i = 1, 5 do
                if p[i] == fg and fg ~= bg then bits = bits + 2 ^ (i - 1) end
            end
            ch[#ch + 1] = string.char(128 + bits)
            fgs[#fgs + 1] = HEX[fg]
            bgs[#bgs + 1] = HEX[bg]
        end
        out[#out + 1] = { table.concat(ch), table.concat(fgs), table.concat(bgs) }
    end
    return out
end

-- Zeichnet eine Pixelgrafik (cols x rows Zeichen) ab (cx, cy).
function UI.pixels(cx, cy, cols, rows, px)
    local s = Kernel.screen
    for i, r in ipairs(UI.pixelRows(cols, rows, px)) do
        s.setCursorPos(cx, cy + i - 1)
        s.blit(r[1], r[2], r[3])
    end
end

-- ---------- Taskleiste ----------
-- Unten wie bei Windows: HOME ganz links, dann ein Reiter je App, rechts
-- Schwarm-Anzeige, Uhr und Ausschalter. Passen nicht alle Reiter in die
-- Zeile (PC, Pocket, kleiner Monitor), gibt es den Button APPS mit Menue.
function UI.taskLayout()
    local W = Kernel.W
    local c = UI.layoutCache
    if c and c.W == W and c.n == #Apps.list then return c end
    local tabs, need = {}, 0
    for _, app in ipairs(Apps.list) do
        if app.tab ~= false and app.id ~= "home" then
            tabs[#tabs + 1] = app
            need = need + #app.title + 2
        end
    end
    local out = { W = W, n = #Apps.list, tabs = {}, list = tabs, homeW = (EDITION == "claude") and 8 or 6 }
    local tray = 3 + 7                      -- Ausschalter + Uhr
    local x = out.homeW + 2
    if x + need - 1 + 1 + tray <= W then
        out.mode = "tabs"
        for _, app in ipairs(tabs) do
            out.tabs[#out.tabs + 1] = { app = app, x = x, w = #app.title + 2 }
            x = x + #app.title + 2
        end
    else
        out.mode = "menu"
        out.menuW = (W >= 40) and 8 or 6
        x = x + out.menuW + 1
    end
    out.free = W - tray - x       -- Platz fuer Titel und Schwarm-Anzeige
    out.clock = W >= 30
    UI.layoutCache = out
    return out
end

-- Ein Reiter. Flach; der aktive bekommt eine Flaeche und einen lime Strich.
local function drawTab(x, y, w, label, active, fn)
    local bh = UI.bh()
    local bg = active and colors.brown or colors.gray
    UI.fill(x, y, w, bh, bg)
    UI.text(x + math.floor((w - #label) / 2), y, label, active and colors.white or colors.lightGray, bg)
    if active and bh >= 2 then UI.line(x + 1, y + bh - 1, w - 2, colors.lime, "bottom", bg) end
    UI.hit(x, y, w, bh, fn)
end

function UI.taskbar()
    local L = UI.taskLayout()
    local W, bh, y = Kernel.W, UI.bh(), Kernel.h + 1
    local app = Kernel.app
    UI.surface = colors.gray
    UI.fill(1, y, W, bh, colors.gray)
    local home = Apps.byId.home
    drawTab(1, y, L.homeW, (EDITION == "claude") and "CLAUDE" or "HOME", app == home, function() Kernel.open("home") end)
    local x = L.homeW + 2
    if L.mode == "tabs" then
        for _, t in ipairs(L.tabs) do
            drawTab(t.x, y, t.w, t.app.title, app == t.app, function() Kernel.open(t.app.id) end)
        end
        x = L.tabs[#L.tabs].x + L.tabs[#L.tabs].w + 1
    else
        drawTab(x, y, L.menuW, (L.menuW >= 8) and "APPS \30" or "APPS", Kernel.menu == true,
                function() Kernel.menu = not Kernel.menu end)
        x = x + L.menuW + 1
        if app.id ~= "home" and L.free >= 6 then
            UI.text(x, y, app.title:sub(1, L.free - 1), colors.white, colors.gray)
            x = x + math.min(#app.title, L.free - 1) + 1
        end
    end
    -- rechts: Ausschalter, Uhr, Schwarm
    local rx = W - 2
    UI.button{ x = rx, y = y, w = 3, text = "\215", style = "ghost", fg = colors.red,
               confirm = (not Kernel.locked) and "exit" or nil,
               onClick = function()
                   if Kernel.locked then
                       Kernel.askCode("Beenden", function() Kernel.running = false end)
                   else
                       Kernel.running = false
                   end
               end }
    -- Uhr antippen oeffnet die Mitteilungen (wie bei Windows)
    local function togglePanel()
        if Kernel.panel then Kernel.closePanel() else Kernel.panel, Kernel.menu = true, false end
    end
    if L.clock then
        rx = rx - 6
        UI.text(rx, y, Kernel.clock, colors.white, colors.gray)
        UI.hit(rx - 1, y, 7, bh, togglePanel)
    end
    local fleet = Fleets and Fleets.UP
    if fleet then
        local online, total = fleet:counts()
        local label = online .. "/" .. total
        local cw = #label + 4
        if rx - cw - 1 >= x then
            rx = rx - cw - 1
            UI.text(rx + 1, y, "\7", (online > 0) and colors.lime or colors.lightGray, colors.gray)
            UI.text(rx + 3, y, label, colors.white, colors.gray)
            UI.hit(rx, y, cw, bh, function() Kernel.open("swarm") end)
        end
    end
    -- Neue Mitteilungen: roter Zaehler (ohne Uhr auch ein Punkt fuer gelesene)
    local unread = Kernel.unread()
    local badge = (unread > 0) and (" " .. math.min(unread, 99) .. " ") or ((not L.clock and #Kernel.inbox > 0) and "  " or nil)
    if badge and rx - #badge - 1 >= x then
        rx = rx - #badge - 1
        UI.text(rx, y, badge, (unread > 0) and colors.white or colors.lightGray, (unread > 0) and colors.red or colors.gray)
        UI.hit(rx, y, #badge, bh, togglePanel)
    end
    UI.surface = colors.black
end

-- App-Menue (Button APPS): Liste aller Apps ueber der Taskleiste.
function UI.appMenu()
    local L = UI.taskLayout()
    local bh, W = UI.bh(), Kernel.W
    local list = L.list
    local itemW = 16
    local cols = (W >= itemW * 2 + 2) and 2 or 1
    local rows = math.ceil(#list / cols)
    local pw, ph = cols * itemW + 2, rows * bh + 3
    local x0, y0 = 1, Kernel.h - ph + 1
    -- Tippen ausserhalb schliesst das Menue.
    UI.hit(1, 1, W, Kernel.H, function() Kernel.menu = false end)
    UI.card(x0, y0, pw, ph)
    UI.line(x0, y0, pw, colors.brown, "top")
    UI.text(x0 + 1, y0 + 1, "APPS", colors.lightGray)
    for i, app in ipairs(list) do
        local cx = x0 + 1 + ((i - 1) % cols) * itemW
        local cy = y0 + 2 + math.floor((i - 1) / cols) * bh
        local active = (Kernel.app == app)
        UI.text(cx, cy, active and "\149" or " ", colors.lime)
        UI.text(cx + 1, cy, (" " .. app.title):sub(1, itemW - 2), colors.white)
        UI.hit(cx, cy, itemW, bh, function() Kernel.open(app.id) end)
    end
    UI.surface = colors.black
end

-- Mitteilungen: Karte ueber der Taskleiste rechts, neueste oben.
function UI.inboxPanel()
    local W, bh = Kernel.W, UI.bh()
    local box = Kernel.inbox
    local pw = math.min(W, 50)
    local rows = math.max(1, math.min(#box, Kernel.h - 5))
    local ph = rows + 3
    local x0, y0 = W - pw + 1, Kernel.h - ph + 1
    UI.hit(1, 1, W, Kernel.H, function() Kernel.closePanel() end)
    UI.card(x0, y0, pw, ph)
    UI.line(x0, y0, pw, colors.brown, "top")
    UI.text(x0 + 1, y0 + 1, "MITTEILUNGEN", colors.white)
    if #box == 0 then
        UI.text(x0 + 1, y0 + 2, ("Keine Mitteilungen"):sub(1, pw - 2), colors.lightGray)
    else
        UI.button{ x = x0 + pw - 9, y = y0 + 1, w = 8, h = 1, text = "LEEREN", style = "ghost",
                   onClick = function() Kernel.inbox = {} Kernel.closePanel() end }
    end
    for i = 1, rows do
        local e = box[i]
        if not e then break end
        local y = y0 + 1 + i
        local text = e.text .. (((e.n or 1) > 1) and (" (" .. e.n .. "x)") or "")
        UI.text(x0 + 1, y, e.time, colors.lightGray)
        UI.text(x0 + 7, y, "\7", e.color)
        UI.text(x0 + 9, y, text:sub(1, pw - 10 - (e.app and 2 or 0)), e.new and colors.white or colors.lightGray)
        if e.app then
            UI.text(x0 + pw - 2, y, "\16", colors.lightGray)
            UI.hit(x0, y, pw, 1, function() Kernel.closePanel() Kernel.open(e.app, e.arg) end)
        end
    end
    UI.surface = colors.black
end

-- Hilfe "?": ein paar Saetze zur offenen App (Sys.HELP oder app.help).
function UI.helpCard()
    local app = Kernel.helpApp
    local items = app and (app.help or (Sys and Sys.HELP[app.id]))
    if not items then Kernel.helpApp = nil return end
    local W, H = Kernel.W, Kernel.H
    local cw = math.min(W - 2, 64)
    local lines = {}
    for _, item in ipairs(items) do
        for i, part in ipairs(UI.wrap(item, cw - 6)) do lines[#lines + 1] = { part, i == 1 } end
    end
    local ch = math.min(H, #lines + 4)
    local x0, y0 = math.floor((W - cw) / 2) + 1, math.max(1, math.floor((H - ch) / 2) + 1)
    UI.hit(1, 1, W, H, function() Kernel.helpApp = nil end)
    UI.card(x0, y0, cw, ch)
    UI.text(x0 + 2, y0 + 1, "HILFE", colors.lightGray)
    UI.text(x0 + 8, y0 + 1, app.title:sub(1, cw - 18), colors.white)
    UI.button{ x = x0 + cw - 7, y = y0 + 1, w = 5, h = 1, text = "OK", style = "primary", onClick = function() Kernel.helpApp = nil end }
    for i, l in ipairs(lines) do
        if y0 + 2 + i > y0 + ch - 1 then break end
        if l[2] then UI.text(x0 + 2, y0 + 2 + i, "\7", colors.lime) end
        UI.text(x0 + 4, y0 + 2 + i, l[1], colors.white)
    end
    UI.surface = colors.black
end

-- ---------- Code-Fenster (Codesperre) ----------
-- Vorhaengeschloss als Teletext-Grafik (8 x 6 Pixel = 4 x 2 Zeichen).
UI.lockIcon = { "..####..", ".#....#.", ".#....#.", "########", "###..###", "########" }

function UI.lockGlyph(x, y, color, bg)
    UI.pixels(x, y, 4, 2, function(px, py)
        local row = UI.lockIcon[py]
        return (row and row:sub(px, px) == "#") and color or bg
    end)
end

function UI.codePopup()
    local p = Kernel.popup
    local W, H, bh = Kernel.W, Kernel.H, UI.bh()
    local kw = (bh >= 2) and 7 or 5
    local cw = math.min(W, kw * 3 + 2 + 6)
    local kyOff = 6 + ((bh >= 2) and 1 or 0)
    local ch = kyOff + 4 * bh + 2
    local x0, y0 = math.floor((W - cw) / 2) + 1, math.max(1, math.floor((H - ch) / 2) + 1)
    UI.hit(1, 1, W, H, function() end)        -- daneben tippen tut nichts
    UI.card(x0, y0, cw, ch)
    UI.lockGlyph(x0 + 2, y0 + 1, colors.white, colors.gray)
    UI.text(x0 + 7, y0 + 1, p.title:sub(1, cw - 8), colors.white)
    UI.text(x0 + 7, y0 + 2, p.new and "Neuer Code" or "Code eingeben", colors.lightGray)
    -- Eingabe als Punkte
    local slots = math.max(4, #p.entered)
    local sx = x0 + math.floor((cw - slots * 2 + 1) / 2)
    for i = 1, slots do
        UI.text(sx + (i - 1) * 2, y0 + 4, (i <= #p.entered) and "\7" or "\183",
                (i <= #p.entered) and colors.white or colors.lightGray)
    end
    local msg = p.err
    if p.lockUntil and os.clock() < p.lockUntil then
        msg = "Gesperrt: " .. math.ceil(p.lockUntil - os.clock()) .. " s"
    end
    if msg then UI.text(x0 + math.floor((cw - #msg) / 2), y0 + 5, msg:sub(1, cw), colors.red) end
    -- Ziffernfeld
    local keysRows = { { "1", "2", "3" }, { "4", "5", "6" }, { "7", "8", "9" }, { "\27", "0", "OK" } }
    local kx = x0 + math.floor((cw - (kw * 3 + 2)) / 2)
    local ky = y0 + kyOff
    for r, row in ipairs(keysRows) do
        for c, label in ipairs(row) do
            local action = (label == "\27") and "del" or ((label == "OK") and "ok" or label)
            UI.button{ x = kx + (c - 1) * (kw + 1), y = ky + (r - 1) * bh, w = kw, h = bh, text = label,
                       style = (label == "OK") and "primary" or nil, fg = (label == "\27") and colors.red or nil,
                       onClick = function() Kernel.codeKey(action) end }
        end
    end
    UI.button{ x = x0 + math.floor((cw - 9) / 2), y = y0 + ch - 1, w = 9, h = 1, text = "ABBRUCH", style = "ghost",
               onClick = function() Kernel.codeKey("cancel") end }
    UI.surface = colors.black
end

-- Meldung ueber der Taskleiste (verschwindet nach ein paar Sekunden).
function UI.toast()
    local t = Kernel.toast
    if not t or os.clock() >= t.untilT then return end
    local text = t.text:sub(1, Kernel.w - 5)
    UI.text(2, Kernel.h, "\149", t.color, colors.brown)
    UI.text(3, Kernel.h, " " .. text .. " ", colors.white, colors.brown)
end

-- ---------- Kopfzeile einer App ----------
-- Titel links (Untertitel darunter bzw. daneben), Aktionen rechts.
-- actions: Buttons wie bei UI.button, ohne x/y. Passen sie nicht neben den
-- Titel, kommen sie in eine zweite Leiste (ausser oneRow: dann wird der
-- Untertitel gekuerzt). Rueckgabe: erste Inhaltszeile.
function UI.header(title, sub, actions, subColor, oneRow)
    local w, bh = Kernel.w, UI.bh()
    actions = actions or {}
    -- Hilfe "?" in der Kopfzeile der App selbst (nicht in Unterseiten)
    local app = Kernel.app
    if app and title == app.title and (app.help or (Sys and Sys.HELP[app.id])) then
        local need, tw = 4, #title + 4                -- "?" passt in die Button-Zeile?
        for _, a in ipairs(actions) do need = need + (a.w or (a.label and #a.label or (#a.text + 2))) + 1 end
        if need <= w - 1 and (w >= CONFIG.minW or tw + need <= w) then
            local copy = { table.unpack(actions) }
            copy[#copy + 1] = { text = "?", w = 3, style = "ghost", onClick = function() Kernel.helpApp = app end }
            actions = copy
        end
    end
    local total = 0
    for _, a in ipairs(actions) do
        a.w = a.w or (a.label and #a.label or (#a.text + 2))
        total = total + a.w + 1
    end
    local titleW = #title + 4
    if bh == 1 and sub and sub ~= "" then titleW = titleW + #sub + 2 end
    local twoRows = total > 0 and titleW + total > w and not oneRow
    local rows = twoRows and (bh * 2) or bh
    UI.card(1, 1, w, rows)
    UI.text(2, 1, title:sub(1, w - 2), colors.white)
    -- Aktionen rechtsbuendig
    local ay = twoRows and (bh + 1) or 1
    local x = w - total + 1
    if twoRows then x = math.max(2, x) end
    for _, a in ipairs(actions) do
        if a.label then
            UI.text(x, ay, a.label, colors.lightGray)   -- Beschriftung statt Button
            x = x + a.w + 1
        else
            a.x, a.y = x, ay
            x = UI.button(a) + 1
        end
    end
    if sub and sub ~= "" then
        local limit = (twoRows and w or (w - total)) - 3
        if bh >= 2 then
            UI.text(2, 2, sub:sub(1, limit), subColor or colors.lightGray)
        elseif #title + 2 < limit then
            UI.text(4 + #title, 1, sub:sub(1, math.max(0, limit - #title - 2)), subColor or colors.lightGray)
        end
    end
    UI.surface = colors.black
    return rows + 2
end

-- ---------- Listen ----------
-- Blaetterbare Liste. state.page wird gepflegt. rowH = Zeilen je Eintrag
-- (inkl. 1 Leerzeile). drawRow(item, y, index) zeichnet einen Eintrag.
function UI.list(state, items, y0, rowH, drawRow)
    local bh = UI.bh()
    local bottom = Kernel.h - bh - 1
    local perPage = math.floor((bottom - y0 + 2) / rowH)
    if perPage < 1 then return end            -- kein Platz (sehr kleiner Bildschirm)
    local pages = math.max(1, math.ceil(#items / perPage))
    state.page = math.max(1, math.min(state.page or 1, pages))
    local first = (state.page - 1) * perPage
    for i = 1, perPage do
        local item = items[first + i]
        if not item then break end
        UI.surface = colors.black
        drawRow(item, y0 + (i - 1) * rowH, first + i)
    end
    UI.surface = colors.black
    if pages > 1 then UI.pager(state, pages) end
end

-- Seitenanzeige unten rechts:  [<]  2 / 5  [>]
function UI.pager(state, pages)
    local w, bh = Kernel.w, UI.bh()
    local y = Kernel.h - bh
    local label = state.page .. " / " .. pages
    local x = w - 5 - #label - 2 - 5
    x = UI.button{ x = x, y = y, w = 5, text = "\17", disabled = state.page <= 1,
                   onClick = function() state.page = state.page - 1 end }
    UI.text(x + 1, y, label, colors.lightGray)
    UI.button{ x = x + #label + 2, y = y, w = 5, text = "\16", disabled = state.page >= pages,
               onClick = function() state.page = state.page + 1 end }
end

-- Umbruch an Wortgrenzen (fuer Druck und Fehlermeldungen).
function UI.wrap(text, width)
    local out, line = {}, ""
    for space, word in text:gmatch("(%s*)(%S+)") do
        while #word > width do
            if line ~= "" then out[#out + 1] = line line = "" end
            out[#out + 1] = word:sub(1, width)
            word, space = word:sub(width + 1), ""
        end
        if line == "" then
            line = (#out == 0 and #space + #word <= width) and (space .. word) or word
        elseif #line + #space + #word <= width then
            line = line .. space .. word
        else
            out[#out + 1] = line
            line = word
        end
    end
    if line ~= "" or #out == 0 then out[#out + 1] = line end
    return out
end

local function fmtNum(n)
    if type(n) ~= "number" then return tostring(n or "?") end
    if n >= 10000 then return math.floor(n / 1000) .. "k" end
    return tostring(math.floor(n))
end

local function fmtSize(bytes)
    if type(bytes) ~= "number" then return tostring(bytes or "?") end
    if bytes >= 1024 then return math.floor(bytes / 1024 + 0.5) .. "K" end
    return bytes .. "B"
end

-- ======================================================================
-- [4] APPS
-- ======================================================================
-- Eine App ist eine Tabelle:
--   id, title, color, order      Pflicht: id und draw()
--   draw(self)                   zeichnet den Inhalt (jedes Mal komplett)
--   onEnter(self, ...)           beim Oeffnen
--   onChar/onKey/onPaste/onScroll, tick(self) -> true = neu zeichnen
--   service(self)                eigene Hintergrund-Routine (laeuft dauerhaft)
--   onLeave(self)                beim Verlassen des Reiters
--   onTerminate(self)            Strg+T trifft die App statt das OS
--   cursor(self)                 nach dem Zeichnen (eigenen Cursor setzen)
--   tab = false                  kein Reiter in der Taskleiste
--   fullscreen = true            ohne Taskleiste
Apps = { list = {}, byId = {} }

function Apps.register(app)
    assert(type(app) == "table" and type(app.id) == "string" and type(app.draw) == "function",
           "App braucht id und draw()")
    app.title = app.title or app.id:upper()
    app.color = app.color or colors.gray
    app.order = app.order or 100
    for i, other in ipairs(Apps.list) do
        if other.id == app.id then table.remove(Apps.list, i) break end
    end
    Apps.byId[app.id] = app
    table.insert(Apps.list, app)
    table.sort(Apps.list, function(a, b) return a.order < b.order end)
    return app
end

-- ======================================================================
-- [5] HOME / BOOT
-- ======================================================================
-- Logo im Stil des GTS-Wappens: metallische Buchstaben "GTS OS" in einem
-- feinen Rahmen mit abgeschraegten Ecken (v8.0: ruhig, ohne Streifen;
-- dahinter ein Sternenhimmel). Gezeichnet mit Teletext-Pixeln (2x3 je
-- Zeichen), dadurch feiner als Bloecke.
local Logo = {
    -- Buchstabe W x H Pixel, Strich t, Fase c, Abstand g, Wortluecke sp,
    -- Rahmenabstand fx/fy, Fase des Rahmens fc
    sizes = {
        { W = 16, H = 21, t = 4, c = 5, g = 3, sp = 9, fx = 8, fy = 5, fc = 7 },
        { W = 12, H = 15, t = 3, c = 4, g = 2, sp = 7, fx = 6, fy = 4, fc = 5 },
        { W = 7,  H = 9,  t = 2, c = 2, g = 2, sp = 4, fx = 3, fy = 3, fc = 3 },
    },
    cache = {},
}

-- Liegt (x, y) im Rechteck x0..x1 / y0..y1 mit abgeschraegten Ecken (Fase c)?
local function inBox(x, y, x0, y0, x1, y1, c)
    if x < x0 or x > x1 or y < y0 or y > y1 then return false end
    return (x - x0) + (y - y0) >= c and (x1 - x) + (y - y0) >= c
       and (x - x0) + (y1 - y) >= c and (x1 - x) + (y1 - y) >= c
end

-- Buchstaben als Formeln: true = Pixel (x, y) gehoert zum Buchstaben (0-basiert).
Logo.glyphs = {
    O = function(x, y, S)
        local W, H, t, c = S.W, S.H, S.t, S.c
        return inBox(x, y, 0, 0, W - 1, H - 1, c)
           and not inBox(x, y, t, t, W - 1 - t, H - 1 - t, math.max(0, c - t))
    end,
    G = function(x, y, S)
        local W, H, t = S.W, S.H, S.t
        local mid = math.floor((H - t) / 2)
        if x >= W - t and y >= t and y < mid then return false end           -- Oeffnung rechts oben
        if x >= math.floor(W / 2) and y >= mid and y < mid + t then          -- Querstrich
            return inBox(x, y, 0, 0, W - 1, H - 1, S.c)
        end
        return Logo.glyphs.O(x, y, S)
    end,
    T = function(x, y, S)
        local W, t = S.W, S.t
        if y < t then return inBox(x, y, 0, 0, W - 1, S.H - 1, math.floor(S.c / 2)) end
        local x0 = math.floor((W - t) / 2)
        return x >= x0 and x < x0 + t
    end,
    S = function(x, y, S)
        local W, H, t, c = S.W, S.H, S.t, S.c
        local mid = math.floor((H - t) / 2)
        if not inBox(x, y, 0, 0, W - 1, H - 1, c) then return false end
        if not (y < t or (y >= mid and y < mid + t) or y >= H - t
                or (x < t and y < mid + t) or (x >= W - t and y >= mid)) then return false end
        -- Fasen am Querstrich: links unten und rechts oben
        local yb, cj = mid + t - 1, math.max(1, c - 2)
        if y <= yb and x + (yb - y) < cj then return false end
        if y >= mid and (W - 1 - x) + (y - mid) < cj then return false end
        return true
    end,
}

-- Baut das Bild fuer einen Bereich von w x h Zeichen. opts.chips = Zeilen
-- Platz unter dem Rahmen. Rueckgabe: Zeilen fuer blit und die Lage von
-- Rahmen-Unterkante (Zeile) und Mitte.
function Logo.build(w, h, reserve)
    local key = w .. "x" .. h .. "/" .. reserve
    if Logo.cache[key] then return Logo.cache[key] end
    local PW, PH = w * 2, h * 3
    local S, ww
    for _, size in ipairs(Logo.sizes) do
        ww = 5 * size.W + 3 * size.g + size.sp
        local fw, fh = ww + 2 * size.fx + 2, size.H + 2 * size.fy + 2
        if fw + 4 <= PW and fh + reserve * 3 <= PH then S = size break end
    end
    S = S or Logo.sizes[#Logo.sizes]
    ww = 5 * S.W + 3 * S.g + S.sp
    local fw, fh = ww + 2 * S.fx + 2, S.H + 2 * S.fy + 2
    local framed = fw + 4 <= PW
    if not framed then fw, fh = ww, S.H + 2 * S.fy end
    -- senkrecht mittig; die Rahmen-Unterkante liegt im mittleren Drittel einer Zeile
    local fx0 = math.floor((PW - fw) / 2)
    local fy0 = math.floor((PH - fh - reserve * 3) / 2)
    local bottom = fy0 + fh - 1
    fy0 = fy0 + (1 - bottom % 3)
    bottom = fy0 + fh - 1
    local fx1 = fx0 + fw - 1
    local lx = fx0 + math.floor((fw - ww) / 2)
    local ly = fy0 + math.floor((fh - S.H) / 2)
    local split = math.ceil((ly + S.H * 0.45) / 3) * 3    -- oben weiss, unten grau (Metall)
    local word = { { "G", 0 }, { "T", S.W + S.g }, { "S", 2 * (S.W + S.g) },
                   { "O", 3 * (S.W + S.g) - S.g + S.sp }, { "S", 4 * (S.W + S.g) - S.g + S.sp } }
    -- Streifen: vier schraege Baender je Seite, parallel zur Innenkante;
    -- das Band am Rahmen ist lime, dann gruen, dann dunkel.
    local P, bw, nb = 9, 4, 4
    local ya, yb = fy0 + 3, bottom - 3
    local edgeL, edgeR = (fx0 - 4) - yb, (fx1 + 4) + yb
    local stripeColors = { [0] = colors.lime, colors.green, colors.brown, colors.brown }
    local wings = false                          -- v8.0: keine Streifen mehr (ruhiger)
    local function px(x, y)
        x, y = x - 1, y - 1
        -- Buchstaben
        if y >= ly and y < ly + S.H and x >= lx and x < lx + ww then
            for _, g in ipairs(word) do
                local gx = x - lx - g[2]
                if gx >= 0 and gx < S.W then
                    if Logo.glyphs[g[1]](gx, y - ly, S) then
                        return (y < split) and colors.white or colors.lightGray
                    end
                    break
                end
            end
        end
        if framed then
            -- Rahmen: 1 Pixel breit, Ecken abgeschraegt
            if inBox(x, y, fx0, fy0, fx1, bottom, S.fc)
               and not inBox(x, y, fx0 + 1, fy0 + 1, fx1 - 1, bottom - 1, S.fc) then
                return colors.brown
            end
            -- Streifen links und rechts, schraeg wie beim alten Logo
            if wings and y >= ya and y <= yb and x > 1 and x < PW - 2 then
                local d = (x < fx0) and (edgeL - (x - y)) or ((x > fx1) and ((x + y) - edgeR) or -1)
                if d >= 0 and d < P * (nb - 1) + bw and d % P < bw then
                    return stripeColors[math.floor(d / P)]
                end
            end
        end
        return colors.black
    end

    local rows = UI.pixelRows(w, h, px)
    local out = { rows = rows, bottom = math.floor(bottom / 3) + 1, framed = framed,
                  left = math.floor(fx0 / 2) + 1, right = math.floor(fx1 / 2) + 1 }
    Logo.cache = { [key] = out }
    return out
end

-- Zeichnet das Logo in die Zeilen y1..y2. Rueckgabe: Zeile der Rahmen-Unterkante.
function Logo.draw(y1, y2, reserve)
    local L = Logo.build(Kernel.w, y2 - y1 + 1, reserve or 3)
    local s = Kernel.screen
    for i, r in ipairs(L.rows) do
        s.setCursorPos(1, y1 + i - 1)
        s.blit(r[1], r[2], r[3])
    end
    Logo.last = { L = L, y1 = y1 }
    return y1 + L.bottom - 1
end

-- Ist an dieser Stelle (Zeichen) nichts vom Logo? (fuer die Sterne)
function Logo.free(x, y)
    local last = Logo.last
    if not last then return true end
    local r = last.L.rows[y - last.y1 + 1]
    if not r then return true end
    return r[1]:byte(x) == 128 and r[3]:sub(x, x) == HEX[colors.black]
end

-- Versions-Plakette auf der Rahmen-Unterkante: " * GTS OS 8.0 "
function Logo.version(y)
    local text = "  GTS OS " .. RELEASE .. " "
    local x = math.floor((Kernel.w - #text) / 2) + 1
    UI.text(x, y, text, colors.white, colors.gray)
    UI.text(x + 1, y, "\7", colors.lime, colors.gray)
end

-- ---------- Sternenhimmel (Startseite, Startbildschirm) ----------
-- Feste Positionen (aus x/y berechnet), wenige Sterne, die langsam
-- funkeln. free(x, y) = false: dort nicht zeichnen (Logo, Text).
local Stars = {}
function Stars.draw(y1, y2, free)
    local w = Kernel.w
    local tick = math.floor(os.clock() / 1.5)
    for y = y1, y2 do
        for x = 1, w do
            local hsh = (x * 7349 + y * 15887 + x * y * 31) % 1009
            if hsh < 24 and (not free or free(x, y)) then
                local ch, col = ".", colors.brown
                if hsh < 3 then ch, col = "+", colors.lightGray
                elseif hsh < 11 then ch, col = "\183", colors.lightGray end
                local tw = (hsh * 13 + tick) % 17
                if tw == 0 then col = colors.white elseif tw == 1 and ch ~= "." then col = colors.brown end
                UI.text(x, y, ch, col, colors.black)
            end
        end
    end
end

-- Begruessung nach Tageszeit (echte Uhr), mit Namen aus den Einstellungen.
local function greeting()
    local hr = tonumber(os.date("%H")) or 12
    local text = (hr >= 5 and hr < 11) and "Guten Morgen" or ((hr >= 11 and hr < 17) and "Hallo"
                 or ((hr >= 17 and hr < 23) and "Guten Abend" or "Gute Nacht"))
    local name = Settings.get("owner")
    if type(name) == "string" and name ~= "" then text = text .. ", " .. name end
    return text
end

local Notes, Finds, Shell -- weiter unten definiert

Apps.register{
    id = "boot", title = "BOOT", tab = false, fullscreen = true, public = true,
    onKey = function() Kernel.open("home") end,     -- am PC: eine Taste startet
    tick = function() return Kernel.app.id == "boot" end,   -- Sterne funkeln, Uhr laeuft
    draw = function()
        local w, h, bh = Kernel.w, Kernel.H, UI.bh()
        local bw, bhh = 15, (bh >= 2) and 3 or 1
        local y = Logo.draw(1, h - 1, bhh + 3)
        if Settings.get("stars") ~= false then Stars.draw(1, h, Logo.free) end
        Logo.version(y)
        UI.hit(1, 1, w, h, function() Kernel.open("home") end)
        local by = math.min(y + 2, h - bhh - 1)
        UI.button{ x = math.floor((w - bw) / 2) + 1, y = by, w = bw, h = bhh,
                   text = "STARTEN", style = "primary", onClick = function() Kernel.open("home") end }
        if by + bhh + 1 <= h - 1 then UI.center(by + bhh + 1, os.date("%H:%M"), colors.lightGray) end
        UI.right(h, "by Jonsi", colors.brown)
        -- unten links (nur PC): Neustart im sicheren Modus (ohne Erweiterungen).
        -- Pocket und Handy: nur ueber INFO > SYSTEM.
        if not READONLY then
            local label = Sys.safe and "SICHERER MODUS AN" or "SICHERER MODUS"
            UI.button{ x = 1, y = h, w = #label + 2, h = 1, text = label, style = "ghost", fg = Sys.safe and colors.orange or colors.brown,
                       confirm = "safe-boot", onClick = function() Sys.setSafe(not Sys.safe) os.reboot() end }
        end
    end,
}

-- Kacheln unter dem Logo: Schwarm, Funde, Lager, Notizen (+ Warnungen).
-- { label, value, dot, app, finds, alert }
local function homeCards()
    local cards = {}
    local fleet = Fleets and Fleets.UP
    if fleet then
        local online, total = fleet:counts()
        cards[#cards + 1] = { label = "SCHWARM", value = (total == 0) and "keine Turtles" or (online .. " von " .. total .. " online"),
                              short = online .. "/" .. total, dot = (online > 0) and colors.lime or colors.lightGray, app = "swarm" }
    end
    local cl = Apps.byId.claude
    local cu = cl and cl.unit and cl:unit()
    if cu then
        local run = cu.prog == "claude" and not cu.paused and cu.online
        local m = run and cu.ext and cu.ext.m
        cards[#cards + 1] = { label = "CLAUDE", value = (not cu.online) and "offline" or (run and ((cl.MODES and cl.MODES[m or ""]) or "an"):lower() or "aus"),
                              short = run and "an" or "aus", dot = run and colors.lime or colors.orange, app = "claude" }
    end
    if Finds and #Finds.list > 0 then
        cards[#cards + 1] = { label = "FUNDE", value = #Finds.list .. " offen", short = tostring(#Finds.list),
                              dot = colors.yellow, app = "swarm", finds = true }
    end
    local lager = Apps.byId.lager
    local ls = lager and (lager.stats or lager.remote)
    if ls and (ls.slots or 0) > 0 then
        local pct = math.floor(ls.used * 100 / ls.slots)
        cards[#cards + 1] = { label = "LAGER", value = pct .. " % voll", short = pct .. "%", dot = colors.cyan, app = "lager" }
    end
    if Apps.byId.notes then
        local n = #Notes.list()
        cards[#cards + 1] = { label = "NOTIZEN", value = (n == 1) and "1 Notiz" or (n .. " Notizen"), short = tostring(n),
                              dot = colors.magenta, app = "notes" }
    end
    if not Kernel.hw.modem then
        cards[#cards + 1] = { label = "FUNK", value = "kein Modem", dot = colors.red, alert = true }
    end
    -- v8.0: Einrichtung, Update, neue Mitteilungen
    if EDITION == "pc" and not Settings.get("setupDone") then
        cards[#cards + 1] = { label = "NEU HIER?", value = "Einrichten", dot = colors.lime, app = "info", arg = "setup" }
    end
    local u = Sys and Sys.upd
    if u and u.state == "found" then
        cards[#cards + 1] = { label = "UPDATE", value = Sys.rel(u.man) .. " bereit", dot = colors.yellow, app = "info", arg = "update" }
    end
    if Extras and Extras.alarm then
        cards[#cards + 1] = { label = "ALARM", value = Extras.alarm.name, dot = colors.white, alert = true }
    end
    return cards
end

Apps.register{
    id = "home", title = "HOME", order = 1, public = true,
    tick = function() return Kernel.app.id == "home" end,   -- Sterne funkeln
    draw = function()
        local w, h = Kernel.w, Kernel.h
        local narrow = UI.narrow()
        local cards = homeCards()
        -- Kachelbreite passt sich an: 18 Zeichen, auf kleinen Schirmen schmaler
        local cardW = math.min(18, math.floor((w - 2 - (#cards - 1)) / math.max(1, #cards)))
        local wide = not narrow and cardW >= 11
        local y = Logo.draw(1, h - 1, wide and 6 or 4)
        if Settings.get("stars") ~= false then Stars.draw(1, h, Logo.free) end
        Logo.version(y)
        UI.center(y + 2, greeting(), colors.lightGray, colors.black)
        local cy = y + 4
        if wide then
            -- Kacheln: oben die Beschriftung, darunter der Wert
            local x = math.floor((w - (#cards * (cardW + 1) - 1)) / 2) + 1
            for _, c in ipairs(cards) do
                UI.card(x, cy, cardW, 2, c.alert and colors.red or colors.gray)
                UI.text(x + 1, cy, "\7", c.alert and colors.white or c.dot)
                UI.text(x + 3, cy, c.label, c.alert and colors.white or colors.lightGray)
                local v = (#c.value <= cardW - 4) and c.value or (c.short or c.value)
                UI.text(x + 3, cy + 1, v:sub(1, cardW - 4), colors.white)
                if c.app or c.fn then
                    UI.hit(x, cy, cardW, 2, c.fn or function() Kernel.open(c.app, c.arg or (c.finds and "finds" or nil)) end)
                end
                x = x + cardW + 1
            end
            UI.surface = colors.black
        else
            -- schmal: eine Zeile, jeder Teil antippbar
            local parts, sep = {}, "  "
            for _, c in ipairs(cards) do parts[#parts + 1] = c.label:sub(1, 1) .. c.label:sub(2):lower() .. " " .. c.value end
            if #table.concat(parts, sep) > w then
                parts, sep = {}, " \183 "
                for _, c in ipairs(cards) do parts[#parts + 1] = c.value end
            end
            local line = table.concat(parts, sep)
            local x = math.max(1, math.floor((w - #line) / 2) + 1)
            UI.center(cy, line:sub(1, w), colors.lightGray, colors.black)
            for i, c in ipairs(cards) do
                if c.app and x <= w then
                    UI.hit(x, cy, #parts[i], 1, function() Kernel.open(c.app, c.arg or (c.finds and "finds" or nil)) end)
                end
                x = x + #parts[i] + #sep
            end
        end
        UI.right(h, "by Jonsi", colors.brown)
        if Sys.safe then UI.text(2, 1, " SICHERER MODUS ", colors.black, colors.orange) end
        -- Klein oben rechts: zurueck auf den Startbildschirm und sperren.
        local label = Kernel.locked and "GESPERRT" or "SPERREN"
        local lx = w - #label - 4
        UI.text(lx, 1, " \7 " .. label .. " ", colors.white, colors.gray)
        UI.text(lx + 1, 1, "\7", Kernel.locked and colors.lime or colors.lightGray, colors.gray)
        UI.hit(lx, 1, #label + 4, 1, function() Kernel.lock() end)
    end,
}

-- ======================================================================
-- [6] NOTIZEN
-- ======================================================================
Notes = {}

function Notes.path(name) return fs.combine(CONFIG.notesDir, name) end

function Notes.list()
    local out = {}
    for _, name in ipairs(fs.list(CONFIG.notesDir)) do
        if not fs.isDir(Notes.path(name)) then out[#out + 1] = name end
    end
    table.sort(out)
    return out
end

function Notes.read(name)
    local lines = {}
    local f = fs.open(Notes.path(name), "r")
    if f then
        local line = f.readLine()
        while line do
            lines[#lines + 1] = line
            line = f.readLine()
        end
        f.close()
    end
    if #lines == 0 then lines[1] = "" end
    return lines
end

function Notes.write(name, lines)
    local ok, err = pcall(function()
        local f = fs.open(Notes.path(name), "w")
        if not f then error("Datei nicht schreibbar", 0) end
        for _, line in ipairs(lines) do f.writeLine(line) end
        f.close()
    end)
    if not ok then return false, "Speichern fehlgeschlagen (Speicher voll?)" end
    return true
end

-- Druckt eine Notiz mit Wortumbruch ueber beliebig viele Seiten.
function Notes.print(name)
    local p = Kernel.hw.printer
    if not p then return false, "Kein Drucker gefunden" end
    if p.getPaperLevel() == 0 then return false, "Drucker: kein Papier" end
    if p.getInkLevel() == 0 then return false, "Drucker: keine Tinte" end
    if not p.newPage() then return false, "Drucker blockiert (Ausgabe voll?)" end
    local pw, ph = p.getPageSize()
    local out = {}
    for _, line in ipairs(Notes.read(name)) do
        for _, part in ipairs(UI.wrap(line, pw)) do out[#out + 1] = part end
    end
    local pages = math.max(1, math.ceil(#out / ph))
    for page = 1, pages do
        if page > 1 and not p.newPage() then
            return false, "Abbruch auf S." .. page .. ": Papier/Tinte leer"
        end
        p.setPageTitle(pages > 1 and (name .. " " .. page .. "/" .. pages) or name)
        for row = 1, ph do
            local line = out[(page - 1) * ph + row]
            if not line then break end
            p.setCursorPos(1, row)
            p.write(line)
        end
        if not p.endPage() then return false, "Drucker: Ausgabe voll" end
    end
    return true, name .. ": " .. pages .. " Seite(n) gedruckt"
end

Apps.register{
    id = "notes", title = "NOTIZEN", order = 2, page = 1,
    onScroll = function(self, dir) self.page = math.max(1, self.page + dir) end,
    draw = function(self)
        local bh, narrow = UI.bh(), UI.narrow()
        local files = Notes.list()
        local top = UI.header("NOTIZEN", (#files == 1) and "1 Notiz" or (#files .. " Notizen"), {
            { text = "NEU +", style = "primary", onClick = function() Kernel.open("editor") end },
        })
        if #files == 0 then
            UI.empty(top + 2, "Keine Notizen vorhanden.", "Mit NEU + legst du die erste an.")
            return
        end
        local ch = narrow and 2 or bh
        UI.list(self, files, top, ch + 1, function(file, y)
            local tx, xr = UI.rowCard(y, ch)
            local buttons = {
                { text = "EDIT", onClick = function() Kernel.open("editor", file) end },
            }
            if EDITION == "pc" then
                buttons[#buttons + 1] = { text = "DRUCK", disabled = not Kernel.hw.printer, onClick = function()
                    local ok, msg = Notes.print(file)
                    Kernel.notify(msg, ok and colors.lime or colors.red)
                end }
            end
            buttons[#buttons + 1] = { text = "DEL", style = "danger", confirm = "del:" .. file, onClick = function()
                local _, bin = Sys.delete(Notes.path(file))
                Kernel.notify(bin and ("Im Papierkorb: " .. file) or ("Geloescht: " .. file), colors.lightGray,
                              bin and "info" or nil, bin and "trash" or nil)
            end }
            local bx = UI.buttonsRight(buttons, narrow and (y + 1) or y, xr)
            local room = (narrow and xr or (bx - 2)) - tx + 1
            local size = fmtSize(fs.getSize(Notes.path(file)))
            UI.text(tx, y, file:sub(1, room), colors.white)
            if #file + 2 + #size <= room then UI.text(tx + #file + 2, y, size, colors.lightGray) end
        end)
    end,
}

-- ---------- Bildschirmtastatur (nur auf dem Touch-Monitor) ----------
local OSK = {
    normal = {
        { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "\223" },
        { "q", "w", "e", "r", "t", "z", "u", "i", "o", "p", "\252" },
        { "a", "s", "d", "f", "g", "h", "j", "k", "l", "\246", "\228" },
        { "y", "x", "c", "v", "b", "n", "m", ",", ".", "-", "+" },
    },
    shifted = {
        { "!", "\"", "\167", "$", "%", "&", "/", "(", ")", "=", "?" },
        { "Q", "W", "E", "R", "T", "Z", "U", "I", "O", "P", "\220" },
        { "A", "S", "D", "F", "G", "H", "J", "K", "L", "\214", "\196" },
        { "Y", "X", "C", "V", "B", "N", "M", ";", ":", "_", "*" },
    },
    -- Beschriftung, Breite in Tasten, Aktion
    bottom = {
        { "SHIFT", 2, "shift" }, { "LEER", 3, "space" },
        { "\27", 1, "left" }, { "\26", 1, "right" }, { "\24", 1, "up" }, { "\25", 1, "down" },
        { "DEL", 1, "backspace" }, { "ENT", 1, "enter" },
    },
}

function OSK.keyH() return (Kernel.H >= 22) and 2 or 1 end
function OSK.height() return 5 * OSK.keyH() end

-- target braucht :insert(text), :key(aktion) und das Feld shift.
function OSK.draw(y0, target)
    local w = Kernel.w
    local kw = math.max(3, math.min(7, math.floor(w / 11)))
    local kh = OSK.keyH()
    local x0 = math.floor((w - kw * 11) / 2) + 1
    UI.card(1, y0, w, 5 * kh, colors.black)
    local gap = (kw >= 5) and 1 or 0     -- Luecke zwischen den Tasten
    for r, row in ipairs(target.shift and OSK.shifted or OSK.normal) do
        for c, key in ipairs(row) do
            UI.button{ x = x0 + (c - 1) * kw, y = y0 + (r - 1) * kh, w = kw - gap, h = kh, text = key,
                       bg = (gap == 0 and (r + c) % 2 == 0) and colors.gray or nil,
                       onClick = function()
                           target:insert(key)
                           target.shift = false
                       end }
        end
    end
    local x, y = x0, y0 + 4 * kh
    for _, def in ipairs(OSK.bottom) do
        local label, cols, action = def[1], def[2], def[3]
        local o = { x = x, y = y, w = cols * kw - gap, h = kh, text = label }
        if action == "shift" then
            o.style = target.shift and "primary" or nil
        elseif action == "backspace" then o.style = "danger"
        elseif action == "enter" then o.style = "primary" end
        o.onClick = function()
            if action == "shift" then target.shift = not target.shift
            elseif action == "space" then target:insert(" ")
            else target:key(action) end
        end
        UI.button(o)
        x = x + cols * kw
    end
    UI.surface = colors.black
end

-- ---------- Texteingabe ----------
-- Dialog mit Eingabefeld (am Monitor mit Bildschirmtastatur) fuer Apps.
-- app.input = { title, text, hint, mask, maxLen, filter, onOk(text) }.
-- Die App leitet onChar/onKey/onPaste weiter und hat :insert/:key fuer OSK.
local Input = {}
function Input.open(app, o)
    o.text = o.text or ""
    app.input, app.shift = o, false
end
function Input.insert(app, text)
    local i = app.input
    if not i then return false end
    text = tostring(text):gsub("[%c]", "")
    if i.filter then text = text:gsub(i.filter, "") end
    i.text = (i.text .. text):sub(1, i.maxLen or 40)
    return true
end
function Input.key(app, action)
    local i = app.input
    if not i then return false end
    if action == "backspace" then
        i.text = i.text:sub(1, -2)
    elseif action == "enter" then
        app.input = nil
        local ok, err = pcall(i.onOk, i.text)
        if not ok then Kernel.notify("Fehler: " .. tostring(err), colors.red) end
    end
    return true
end
function Input.onKey(app, code)
    if not app.input then return false end
    if code == keys.enter or code == keys.numPadEnter then Input.key(app, "enter")
    elseif code == keys.backspace then Input.key(app, "backspace") end
    return true
end
function Input.draw(app)
    local i = app.input
    local top = UI.header(i.header or app.title)
    local shown = i.mask and string.rep("*", #i.text) or i.text
    UI.prompt{ y = top, title = i.title, text = shown, hint = i.hint, maxW = 32,
               onOk = function() Input.key(app, "enter") end, onCancel = function() app.input = nil end }
    if Kernel.display.touch then OSK.draw(Kernel.h - OSK.height(), app) end
end

-- ---------- Editor ----------
local Editor = { id = "editor", title = "EDITOR", tab = false, fullscreen = true }

function Editor:onEnter(name)
    self.shift, self.err, self.top, self.dirty = false, nil, 1, false
    if name then
        self.mode, self.name, self.lines = "edit", name, Notes.read(name)
        self.cy = #self.lines
        self.cx = #self.lines[self.cy]
    else
        self.mode, self.name, self.lines, self.cy, self.cx = "name", "", { "" }, 1, 0
    end
end

function Editor:textWidth() return Kernel.w - self:gutter() - 2 end

function Editor:insert(text)
    if self.mode == "name" then
        -- Nur sichere Zeichen: kein "/" oder "..", sonst koennte eine
        -- Notiz beliebige Dateien (z.B. startup.lua) ueberschreiben.
        text = text:gsub(" ", "_"):gsub("[^%w_%-]", "")
        self.name = (self.name .. text):sub(1, 20)
        self.err = nil
        return
    end
    text = text:gsub("\r\n?", "\n"):gsub("\t", "  "):gsub("[^\n\32-\255]", "")
    local first = true
    for part in (text .. "\n"):gmatch("([^\n]*)\n") do
        if not first then self:key("enter") end
        local line = self.lines[self.cy]
        self.lines[self.cy] = line:sub(1, self.cx) .. part .. line:sub(self.cx + 1)
        self.cx = self.cx + #part
        first = false
    end
    self.dirty = true
end

function Editor:key(action)
    if self.mode == "name" then
        if action == "backspace" then self.name = self.name:sub(1, -2) self.err = nil
        elseif action == "enter" then self:confirmName() end
        return
    end
    local lines, tw = self.lines, self:textWidth()
    local line = lines[self.cy]
    if action == "enter" then
        lines[self.cy] = line:sub(1, self.cx)
        table.insert(lines, self.cy + 1, line:sub(self.cx + 1))
        self.cy, self.cx, self.dirty = self.cy + 1, 0, true
    elseif action == "backspace" then
        if self.cx > 0 then
            lines[self.cy] = line:sub(1, self.cx - 1) .. line:sub(self.cx + 1)
            self.cx, self.dirty = self.cx - 1, true
        elseif self.cy > 1 then
            self.cx = #lines[self.cy - 1]
            lines[self.cy - 1] = lines[self.cy - 1] .. line
            table.remove(lines, self.cy)
            self.cy, self.dirty = self.cy - 1, true
        end
    elseif action == "delete" then
        if self.cx < #line then
            lines[self.cy] = line:sub(1, self.cx) .. line:sub(self.cx + 2)
            self.dirty = true
        elseif self.cy < #lines then
            lines[self.cy] = line .. lines[self.cy + 1]
            table.remove(lines, self.cy + 1)
            self.dirty = true
        end
    elseif action == "left" then
        if self.cx > 0 then self.cx = self.cx - 1
        elseif self.cy > 1 then self.cy = self.cy - 1 self.cx = #lines[self.cy] end
    elseif action == "right" then
        if self.cx < #line then self.cx = self.cx + 1
        elseif self.cy < #lines then self.cy, self.cx = self.cy + 1, 0 end
    elseif action == "up" then
        if self.cx >= tw then
            self.cx = self.cx - tw
        elseif self.cy > 1 then
            self.cy = self.cy - 1
            local len = #lines[self.cy]
            self.cx = math.min(len, math.floor(len / tw) * tw + self.cx)
        end
    elseif action == "down" then
        if math.floor(self.cx / tw) < math.floor(#line / tw) then
            self.cx = math.min(#line, self.cx + tw)
        elseif self.cy < #lines then
            self.cy = self.cy + 1
            self.cx = math.min(#lines[self.cy], self.cx % tw)
        end
    elseif action == "home" then
        self.cx = 0
    elseif action == "end" then
        self.cx = #line
    end
end

function Editor:confirmName()
    if self.name == "" then
        self.err = "Bitte einen Namen eingeben."
    elseif fs.exists(Notes.path(self.name)) then
        self.err = "Name existiert schon."
    else
        self.mode, self.dirty = "edit", true
    end
end

function Editor:save()
    local ok, err = Notes.write(self.name, self.lines)
    if ok then
        Kernel.open("notes")
        Kernel.notify("Gespeichert: " .. self.name)
    else
        self.err = err
    end
end

function Editor:onChar(ch) self:insert(ch) end
function Editor:onPaste(text) self:insert(text) end

function Editor:onKey(code)
    local map = {
        [keys.enter] = "enter", [keys.numPadEnter] = "enter", [keys.backspace] = "backspace",
        [keys.delete] = "delete", [keys.left] = "left", [keys.right] = "right",
        [keys.up] = "up", [keys.down] = "down", [keys.home] = "home", [keys["end"]] = "end",
    }
    if map[code] then self:key(map[code]) end
end

-- Breite der Zeilennummern (nur auf breiten Bildschirmen).
function Editor:gutter() return (Kernel.w >= CONFIG.minW) and 5 or 0 end

function Editor:draw()
    local w, h, bh = Kernel.w, Kernel.H, UI.bh()
    local touch = Kernel.display.touch
    local narrow = UI.narrow()
    local bottom = h - (touch and OSK.height() or 0)

    if self.mode == "name" then
        local top = UI.header("NEUE NOTIZ")
        UI.prompt{ y = top, title = "Name der Notiz", text = self.name, maxW = 24, err = self.err,
                   hint = narrow and "A-Z 0-9 - _ (max. 20)" or "A-Z, 0-9, - und _ (max. 20)",
                   onOk = function() self:confirmName() end,
                   onCancel = function() Kernel.open("notes") end }
    else
        local info = "Zeile " .. self.cy .. "/" .. #self.lines .. "  Spalte " .. (self.cx + 1)
        if narrow then info = "Z" .. self.cy .. " S" .. (self.cx + 1) end
        local hdr = UI.header(self.name .. (self.dirty and " *" or ""), self.err or info, {
            { text = narrow and "SICHERN" or "SPEICHERN", style = "primary", onClick = function() self:save() end },
            { text = narrow and "ABBR." or "ABBRUCH", confirm = self.dirty and "ed_cancel" or nil,
              w = narrow and 7 or 9, onClick = function() Kernel.open("notes") end },
        }, self.err and colors.red)

        -- Lange Zeilen werden auf mehrere Bildschirmzeilen umbrochen.
        local gw = self:gutter()
        local tw, top = self:textWidth(), narrow and (hdr - 1) or hdr
        local tx = gw + 2
        local rows = bottom - top + 1
        local vis, cursorRow = {}, 1
        for i, line in ipairs(self.lines) do
            for seg = 0, math.floor(#line / tw) do
                vis[#vis + 1] = { i, seg * tw }
                if i == self.cy and math.floor(self.cx / tw) == seg then cursorRow = #vis end
            end
        end
        if cursorRow < self.top then self.top = cursorRow end
        if cursorRow > self.top + rows - 1 then self.top = cursorRow - rows + 1 end
        self.top = math.max(1, math.min(self.top, math.max(1, #vis - rows + 1)))
        local first = self.top
        if gw > 0 then UI.fill(1, top, gw, rows, colors.gray) end
        for r = 0, rows - 1 do
            local v = vis[first + r]
            if not v then break end
            if gw > 0 and v[2] == 0 then
                local n = tostring(v[1])
                UI.text(gw - #n, top + r, n, (v[1] == self.cy) and colors.lime or colors.lightGray, colors.gray)
            end
            UI.text(tx, top + r, self.lines[v[1]]:sub(v[2] + 1, v[2] + tw), colors.white)
        end
        local col = self.cx % tw
        local under = self.lines[self.cy]:sub(self.cx + 1, self.cx + 1)
        UI.text(tx + col, top + cursorRow - first, under == "" and " " or under, colors.black, colors.lime)
        if first > 1 then UI.text(w, top, "\30", colors.lightGray) end
        if first + rows - 1 < #vis then UI.text(w, bottom, "\31", colors.lightGray) end

        -- Antippen setzt den Cursor.
        UI.hit(1, top, w, rows, function(cx, cy)
            local v = vis[first + cy - top] or vis[#vis]
            self.cy = v[1]
            self.cx = math.min(#self.lines[v[1]], v[2] + math.max(0, math.min(tw - 1, cx - tx)))
        end)
    end

    if touch then OSK.draw(bottom + 1, self) end
end

Apps.register(Editor)

-- ======================================================================
-- TURTLE-PROGRAMME (eingebettet)
-- ======================================================================
-- Das OS bringt die Programme fuer die Turtles mit und legt sie beim Start
-- in /scripts/turtle ab (LUA APPS > turtle). Dort kann man sie ansehen und
-- aendern. Die Buttons DD, CHUNK und T uebertragen sie an die Turtles.
-- gts_turtle.lua ist der Agent selbst: UPDATE spielt ihn auf alle Turtles,
-- TURTLE-DISK (DATEN) schreibt ihn als Installer auf eine Diskette.
local PROGRAM_FILES, TURTLE_INSTALLER, GPS_INSTALLER, LUA_APP_FILES = {}, "", "", {}   -- (Pocket: leer)
-- (nur in gts_os.lua)

-- ======================================================================
-- [7] FLOTTEN (Schwarm + P. Craft) UND FUNDE
-- ======================================================================
-- Funk-Protokoll (rednet), alle Nachrichten sind Tabellen mit key = Kennung:
--   Einheit -> OS  (updateProto):  { key, status, fuel|air, inv, pos={x,y,z},
--                                    posOk, label, queue, last={seq,state,msg},
--                                    finds={ {n,kind,name,x,y,z,world}, ... } }
--   OS -> Einheit  (cmdProto):     { key, cmd, seq, args }
--   last.state: "queued" | "run" | "ok" | "fail"  -> Rueckmeldung zum Befehl seq
--   Funde schickt die Turtle so lange mit, bis das OS sie mit
--   { cmd = "ACK", n = hoechste Nummer } bestaetigt.

local function clip(v, n)
    if type(v) ~= "string" then return nil end
    return (v:sub(1, n):gsub("[^\32-\126\160-\255]", "?"))
end

-- ---------- Funde ----------
-- Was die Turtles nicht selbst holen koennen, landet hier mit Koordinaten.
local KINDS = {
    ERZ   = { order = 1, color = colors.lime },     -- Allthemodium-Erz (nur von Hand abbaubar)
    LEHM  = { order = 2, color = colors.orange },   -- Suspicious Clay (Smithing Template, Pinsel)
    KISTE = { order = 3, color = colors.yellow },   -- Lootr-Kiste oder nicht geleerte Kiste
    CITY  = { order = 4, color = colors.magenta },  -- Reinforced Deepslate = Ancient City
    DARK  = { order = 5, color = colors.cyan },     -- erster Sculk = Deep Dark
}

Finds = {
    list = {}, keys = {},        -- offene Funde, keys = schon bekannt oder erledigt
    slots = {}, nextSlot = 0,    -- feste Richtung/Spur je Turtle
    counter = 0,
}

function Finds.key(f)
    return f.kind .. "|" .. f.x .. "|" .. f.y .. "|" .. f.z .. "|" .. (f.world and "w" or ("r" .. f.id))
end

local function coord(v)
    return type(v) == "number" and v == v and math.abs(v) < 30000000
end

function Finds.clean(id, f)
    if type(f) ~= "table" or not KINDS[f.kind] or type(id) ~= "number" then return nil end
    if not (coord(f.x) and coord(f.y) and coord(f.z)) then return nil end
    return { id = id, kind = f.kind, name = clip(f.name, 30) or "?", world = (f.world == true),
             x = math.floor(f.x), y = math.floor(f.y), z = math.floor(f.z) }
end

function Finds.sort()
    table.sort(Finds.list, function(a, b)
        local oa, ob = KINDS[a.kind].order, KINDS[b.kind].order
        if oa ~= ob then return oa < ob end
        return a.t > b.t
    end)
end

-- Nimmt einen Fund auf. Rueckgabe: der neue Eintrag oder nil (bekannt/ungueltig).
function Finds.add(id, f)
    local rec = Finds.clean(id, f)
    if not rec or #Finds.list >= 500 then return nil end
    local key = Finds.key(rec)
    if Finds.keys[key] then return nil end
    Finds.counter = Finds.counter + 1
    rec.t = Finds.counter
    Finds.keys[key] = true
    Finds.list[#Finds.list + 1] = rec
    Finds.sort()
    return rec
end

-- Erledigt: verschwindet aus der Liste und wird nicht noch einmal gemeldet.
function Finds.done(rec)
    for i, f in ipairs(Finds.list) do
        if f == rec then table.remove(Finds.list, i) break end
    end
    Finds.save()
end

function Finds.clear()
    Finds.list, Finds.keys = {}, {}
    Finds.save()
end

-- Feste Nummer je Turtle: daraus ergeben sich Richtung und Spur.
function Finds.slotFor(id)
    if not Finds.slots[id] then
        Finds.slots[id] = Finds.nextSlot
        Finds.nextSlot = Finds.nextSlot + 1
        Finds.save()
    end
    return Finds.slots[id]
end

function Finds.save()
    local done = {}
    for key in pairs(Finds.keys) do done[#done + 1] = key end
    Store.save(CONFIG.dbFile, { list = Finds.list, done = done, slots = Finds.slots, nextSlot = Finds.nextSlot }, true)
end

function Finds.load()
    local t = Store.load(CONFIG.dbFile)
    if not t then return end
    if type(t.done) == "table" then
        for _, key in ipairs(t.done) do
            if type(key) == "string" then Finds.keys[key] = true end
        end
    end
    if type(t.list) == "table" then
        for _, f in ipairs(t.list) do
            local rec = Finds.clean(type(f) == "table" and f.id, f)
            if rec then
                Finds.counter = Finds.counter + 1
                rec.t = Finds.counter
                Finds.keys[Finds.key(rec)] = true
                Finds.list[#Finds.list + 1] = rec
            end
        end
        Finds.sort()
    end
    if type(t.slots) == "table" then
        for id, slot in pairs(t.slots) do
            if type(id) == "number" and type(slot) == "number" then Finds.slots[id] = slot end
        end
    end
    Finds.nextSlot = type(t.nextSlot) == "number" and t.nextSlot or 0
end

function Finds.where(f)
    if f.world then return f.x .. " " .. f.y .. " " .. f.z end
    return "rel v" .. f.x .. " h" .. f.y .. " r" .. f.z   -- vor / hoch / rechts ab Basis der Turtle
end

-- ---------- Turtle-Programme (LUA APPS > turtle) ----------
-- Die Programme liegen als Dateien in /scripts/turtle und lassen sich dort
-- ansehen und aendern. Beim Start schreibt das OS die eingebauten Fassungen
-- dorthin, wenn sie fehlen oder eine hoehere Nummer haben (erste Zeile
-- "-- GTS-PROG name N"). Eigene Aenderungen bleiben also erhalten, solange
-- die Nummer nicht hochgezaehlt wird.
local TurtleProgs = { cache = {}, CHUNK = 6000 }

local function readAll(path)
    local h = fs.open(path, "r")
    if not h then return nil end
    local s = h.readAll()
    h.close()
    return s
end

local function writeAll(path, text)
    local h = fs.open(path, "w")
    if not h then return false end
    h.write(text)
    h.close()
    return true
end

-- "5.0" < "5.1" < "5.10"
local function verLess(a, b)
    if not a then return b ~= nil end
    if not b then return false end
    local pa, pb = {}, {}
    for n in tostring(a):gmatch("%d+") do pa[#pa + 1] = tonumber(n) end
    for n in tostring(b):gmatch("%d+") do pb[#pb + 1] = tonumber(n) end
    for i = 1, math.max(#pa, #pb) do
        local x, y = pa[i] or 0, pb[i] or 0
        if x ~= y then return x < y end
    end
    return false
end

function TurtleProgs.version(file, code)
    code = tostring(code or "")
    if file == "gts_turtle.lua" then return code:match('local VERSION%s*=%s*"([^"]+)"') end
    return code:match("^%-%- GTS%-PROG [%w_%-]+ (%d+)")
end

-- Der Agent liegt ohne Verschluesselungs-Teil im OS (der steht schon im OS
-- selbst, siehe CRYPTO_SRC) und wird bei Bedarf zusammengesetzt. Er kommt
-- nicht mehr nach /scripts/turtle (spart ~120 KB auf der Festplatte); eine
-- dort liegende eigene, NEUERE Fassung wird aber weiter benutzt.
function TurtleProgs.agentCode()
    if TurtleProgs.agentFull then return TurtleProgs.agentFull end
    local tpl = PROGRAM_FILES["gts_turtle.lua"]
    if not tpl then return nil end
    local mark = "-- @@CRYPTO-SRC@@\n"
    local i = tpl:find(mark, 1, true)
    if i and CRYPTO_SRC then tpl = tpl:sub(1, i - 1) .. CRYPTO_SRC .. tpl:sub(i + #mark) end
    TurtleProgs.agentFull = tpl
    return tpl
end

function TurtleProgs.install()
    -- Lua-Apps (z.B. APIproject.lua): einmal anlegen. Wer sie loescht, bekommt
    -- sie nicht wieder (Merker in /gts), eine eigene Fassung bleibt unangetastet.
    pcall(function()
        for file, code in pairs(LUA_APP_FILES) do
            local path, mark = fs.combine(CONFIG.scriptDir, file), "/gts/.app_" .. file
            if not fs.exists(mark) then
                if not fs.exists(path) then writeAll(path, code) end
                writeAll(mark, "1")
            end
        end
    end)
    pcall(function()
        fs.makeDir(CONFIG.progDir)
        for file, code in pairs(PROGRAM_FILES) do
            local path = fs.combine(CONFIG.progDir, file)
            local cur = fs.exists(path) and readAll(path) or nil
            if file == "gts_turtle.lua" or file == "claude.lua" then
                -- Agent und Claude bleiben nur im OS (spart Platz); eine eigene, NEUERE Kopie wird benutzt
                if cur and not verLess(TurtleProgs.version(file, code), TurtleProgs.version(file, cur)) then fs.delete(path) end
            elseif not cur or verLess(TurtleProgs.version(file, cur), TurtleProgs.version(file, code)) then
                if writeAll(path, code) and cur then Kernel.log("INFO", "Turtle-Programm aktualisiert: " .. file) end
            end
        end
    end)
end

-- Eigene Programme im Ordner (alles ausser den eingebauten und dem Agenten).
function TurtleProgs.custom()
    local out = {}
    if not fs.isDir(CONFIG.progDir) then return out end
    for _, file in ipairs(fs.list(CONFIG.progDir)) do
        local name = file:match("^([%w_%-]+)%.lua$")
        if name and name ~= "gts_turtle" and name ~= "dd" and name ~= "chunk" and name ~= "test" and name ~= "claude" and #out < 8 then
            out[#out + 1] = name
        end
    end
    table.sort(out)
    return out
end

-- Programm "dd", "chunk", "test" oder "agent". Rueckgabe { code, hash, ver }.
-- Die Datei wird hoechstens alle 3 Sekunden neu gelesen.
function TurtleProgs.get(name)
    local file = (name == "agent") and "gts_turtle.lua" or (name .. ".lua")
    local c = TurtleProgs.cache[name]
    if c and os.clock() - c.checked < 3 then return c end
    local path = fs.combine(CONFIG.progDir, file)
    local code = fs.exists(path) and readAll(path) or ((name == "agent") and TurtleProgs.agentCode() or PROGRAM_FILES[file])
    if not code then return nil end
    if not c or c.code ~= code then
        c = { code = code, hash = Net.hash(code), ver = TurtleProgs.version(file, code) }
        TurtleProgs.cache[name] = c
    end
    c.checked = os.clock()
    return c
end

-- ---------- Flotten ----------
-- Funk (verschluesselt, siehe [1b]): jede Nachricht ist eine Tabelle mit t = Typ.
--   Turtle -> OS  { t = "UP", v, status, fuel, fuelMax, inv, pos = {x,y,z,f}, posOk,
--                   label, queue, last = {seq,state,msg}, finds, prog, paused,
--                   progs = {name = hash}, world, compass, gps, scanner, events }
--   OS -> Turtle  { t = "CMD", cmd, seq, args }        Befehl
--                 { t = "PROG"/"AGENT", name, hash, part, parts, data, ver }
--                 { t = "KEY", key }                   neues Schwarm-Passwort
--   last.state: "queued" | "run" | "ok" | "fail"  -> Rueckmeldung zum Befehl seq
--   Funde schickt die Turtle so lange mit, bis das OS sie mit
--   { cmd = "ACK", n = hoechste Nummer } bestaetigt.
local legacy = {}   -- alte Turtles (v4, unverschluesselt): id -> Zeitpunkt

-- ---------- Wo bin ich? (Position des Computers bzw. Pockets) ----------
-- PC: GPS beim Start (INFO macht das im Hintergrund) oder von Hand in den
-- Einstellungen. Pocket: GPS, laufend erneuert, solange die Karte offen ist.
Geo = { gps = nil, asked = -100 }

function Geo.here()
    if (EDITION == "pocket" or EDITION == "claude") and os.clock() - Geo.asked > 10 then
        Geo.asked = os.clock()
        os.queueEvent("gts_gps")
    end
    local hand = Settings.get("pcPos")
    if EDITION == "pc" and type(hand) == "table" and coord(hand.x) and coord(hand.y) and coord(hand.z) then
        return { x = hand.x, y = hand.y, z = hand.z, src = "hand" }
    end
    if Geo.gps then return { x = Geo.gps.x, y = Geo.gps.y, z = Geo.gps.z, src = "gps" } end
    return nil
end

-- Himmelsrichtung (8 Teile) fuer einen Versatz in Welt-Achsen (z waechst nach Sueden).
function Geo.dir(dx, dz)
    local ax, az = math.abs(dx), math.abs(dz)
    if ax == 0 and az == 0 then return "" end
    if ax < az * 0.4142 then return (dz < 0) and "N" or "S" end
    if az < ax * 0.4142 then return (dx > 0) and "O" or "W" end
    return ((dz < 0) and "N" or "S") .. ((dx > 0) and "O" or "W")
end

-- "140 Bl. NO" (waagerechte Entfernung von hier) oder nil.
function Geo.from(here, p)
    if not (here and p) then return nil end
    local dx, dz = p.x - here.x, p.z - here.z
    local d = math.floor(math.sqrt(dx * dx + dz * dz) + 0.5)
    if d == 0 then return "hier" end
    return d .. " Bl. " .. Geo.dir(dx, dz)
end

local function num(v) return (type(v) == "number" and v == v) and v or nil end

local function makeFleet(def)
    local app = {
        id = def.id, title = def.title, color = def.color, order = def.order,
        short = def.short, page = 1, store = {}, count = 0,
        view = "units", findsPage = { page = 1 }, unit = nil, sub = "info",
    }

    -- Eigener Name und Farbe einer Turtle (am PC gemerkt; der Name geht
    -- ab Agent v5.2 auch an die Turtle, dann sieht ihn auch das Pocket).
    function app:nameOf(id, e)
        local t = (Settings.get("tnames") or {})[id]
        if type(t) == "table" and type(t.n) == "string" and t.n ~= "" then return t.n end
        e = e or self.store[id]
        return e and e.label
    end

    function app:colorOf(id)
        local t = (Settings.get("tnames") or {})[id]
        local c = type(t) == "table" and tonumber(t.c)
        if not c or c < 1 or c > 32768 then return nil end
        local v = 1
        while v < c do v = v * 2 end
        return (v == c) and c or nil
    end

    function app:setName(id, name, color)
        local all = Settings.get("tnames")
        if type(all) ~= "table" then all = {} end
        local t = type(all[id]) == "table" and all[id] or {}
        if name ~= nil then t.n = (name ~= "") and name or nil end
        if color ~= nil then t.c = (color ~= 0) and color or nil end
        all[id] = (t.n or t.c) and t or nil
        Settings.set("tnames", all)
    end

    function app:counts()
        local online = 0
        for _, e in pairs(self.store) do if e.online then online = online + 1 end end
        return online, self.count
    end

    -- Verarbeitet ein Status-Paket. Felder werden einzeln geprueft: ein
    -- kaputtes Paket kann die Anzeige nicht zum Absturz bringen.
    function app:receive(id, msg)
        local e = self.store[id]
        if not e then
            if self.count >= CONFIG.maxUnits then return false end
            e = { id = id }
            self.store[id] = e
            self.count = self.count + 1
            Kernel.log("INFO", def.title .. ": #" .. id .. " verbunden")
        end
        e.seen, e.online, e.keyOld = os.clock(), true, nil
        e.status = clip(msg.status, 14) or "?"
        e.label = clip(msg.label, 12)
        e.v = clip(msg.v, 8)
        local level = msg[def.levelField]
        e.level = (num(level) or level == "unlimited") and level or nil
        e.levelMax = num(msg.fuelMax)
        e.inv = num(msg.inv)
        e.queue = num(msg.queue) or 0
        e.posOk = msg.posOk ~= false
        local p = msg.pos
        if type(p) == "table" and num(p.x) and num(p.y) and num(p.z) then
            e.pos = { x = p.x, y = p.y, z = p.z, f = num(p.f) }
        else
            e.pos = nil
        end
        e.prog, e.paused = clip(msg.prog, 12), msg.paused == true
        e.world, e.gps, e.scanner = msg.world == true, msg.gps == true, msg.scanner == true
        e.compass = num(msg.compass)
        -- Welt-Koordinaten (Agent ab v5.1): Turtle, Blick und Basis
        local function wc(t)
            if type(t) == "table" and coord(t.x) and coord(t.y) and coord(t.z) then
                return { x = math.floor(t.x), y = math.floor(t.y), z = math.floor(t.z) }
            end
        end
        e.wpos, e.base = wc(msg.wpos), wc(msg.base)
        e.wf = num(msg.wf) and (math.floor(msg.wf) % 4) or nil
        e.gpsOk, e.pick = msg.gpsOk == true, msg.pick ~= false
        -- letzte GPS-Messung der Turtle (Agent ab v5.3): Alter in s und Ort
        e.gpsAge = (num(msg.gpsAge) and msg.gpsAge >= 0 and msg.gpsAge < 1e7) and msg.gpsAge or nil
        e.gpsFix = wc(msg.gpsFix)
        -- Chunky-Betrieb (Agent v5.0): die Turtle hoert nur in kurzen Funkfenstern (alle win Sek.)
        local win = num(msg.win)
        e.win = (win and win >= 1 and win <= 120) and win or nil
        e.tools, e.toolSet = {}, {}
        if type(msg.tools) == "table" then
            for i = 1, math.min(#msg.tools, 12) do
                local t = msg.tools[i]
                if type(t) == "string" and #t <= 12 then e.tools[#e.tools + 1] = t e.toolSet[t] = true end
            end
        end
        if type(msg.progs) == "table" then
            local progs, n = {}, 0
            for name, hash in pairs(msg.progs) do
                if type(name) == "string" and type(hash) == "string" and #name <= 16 and n < 20 then
                    progs[name], n = hash:sub(1, 16), n + 1
                end
            end
            e.progs = progs
        end
        if type(msg.events) == "table" then
            local ev = {}
            for i = 1, math.min(#msg.events, 6) do
                local x = msg.events[i]
                if type(x) == "table" then ev[#ev + 1] = { t = num(x.t) or 0, text = clip(x.text, 60) or "?" } end
            end
            e.events = ev
        end
        if e.pending and e.pending.label == "UPDATE" and def.drawUnit then
            local agent = TurtleProgs.get("agent")
            if agent and e.v == agent.ver then
                e.pending, e.note = nil, { text = "Update fertig: Agent v" .. e.v, ok = true, untilT = os.clock() + 12 }
                Kernel.notify("#" .. id .. ": " .. e.note.text, colors.lime)
            end
        end
        local last = msg.last
        if type(last) == "table" then
            -- Programm unterwegs verloren gegangen? Einmal neu senden.
            local pp = e.pending and e.pending.prog
            if pp and last.seq == e.pending.seq and last.state == "fail" and not e.pending.resent
               and type(last.msg) == "string" and (last.msg:find("fehlt") or last.msg:find("veraltet")) then
                local again = e.pending
                e.progs = nil
                local prog = TurtleProgs.get(pp.name)
                if prog then
                    self:pushCode(id, "PROG", pp.name, prog)
                    self:transmit(id, "RUN", again.label, { name = pp.name, hash = prog.hash, args = pp.args, fresh = pp.fresh })
                    e.pending.prog, e.pending.resent = pp, true
                    last = nil
                end
            end
            if e.pending and last and last.seq == e.pending.seq then
                if last.state == "ok" or last.state == "fail" then
                    local ok = (last.state == "ok")
                    e.note = { text = clip(last.msg, 80) or (ok and "OK" or "Fehler"), ok = ok, untilT = os.clock() + 12 }
                    if (e.pending.label == "DD" or e.pending.label == "CHUNK" or e.pending.label == "TEST")
                       and not (e.toolSet and e.toolSet.chat) then   -- mit eigener Chat Box meldet sie selbst
                        Extras.tell("#" .. id .. " " .. (e.label or "") .. ": " .. e.note.text)
                    end
                    e.pending = nil
                    Kernel.notify("#" .. id .. ": " .. e.note.text, ok and colors.lime or colors.red)
                else
                    e.pending.acked = true
                end
            end
            if last and (last.state == "ok" or last.state == "fail") then
                e.lastMsg, e.lastOk = clip(last.msg, 80), last.state == "ok"
            end
        end

        -- Briefkasten: die Turtle hat gerade ihr Funkfenster offen.
        if e.win then
            if e.mail and #e.mail > 0 then
                for _, p in ipairs(e.mail) do Kernel.post(id, p) end
                e.mail = nil
                if e.pending then e.pending.delivered = os.clock() end
            elseif e.pending and not e.pending.acked and e.pending.payload and e.pending.delivered
                   and os.clock() - e.pending.delivered > 1 then
                Kernel.post(id, e.pending.payload)       -- im letzten Fenster verpasst
                e.pending.delivered = os.clock()
            end
        elseif e.mail then
            for _, p in ipairs(e.mail) do Kernel.post(id, p) end   -- Chunky abgelegt: sofort
            e.mail = nil
        end

        -- Funde uebernehmen und bestaetigen (auch schon bekannte, damit die
        -- Turtle aufhoert, sie zu senden).
        local newFinds = 0
        if def.finds and type(msg.finds) == "table" then
            local top, newest
            for i = 1, math.min(#msg.finds, 10) do
                local f = msg.finds[i]
                if type(f) == "table" and type(f.n) == "number" then
                    if not top or f.n > top then top = f.n end
                    local rec = Finds.add(id, f)
                    if rec then newFinds, newest = newFinds + 1, rec end
                end
            end
            if top and Kernel.hw.modem then Net.send(id, { t = def.cmdType, cmd = "ACK", n = top }) end
            if newest then
                Finds.save()
                Kernel.notify("Fund #" .. id .. ": " .. newest.kind .. " " .. Finds.where(newest), KINDS[newest.kind].color, "swarm", "finds")
                Extras.tell("Fund " .. newest.kind .. " bei " .. Finds.where(newest) .. " (#" .. id .. ")")
                Extras.beep(false)
            end
        end

        if def.finds and not READONLY then self:watch(id, e) end

        -- Nur neu zeichnen, wenn sich etwas Sichtbares geaendert hat.
        local sig = table.concat({ e.status, tostring(e.label), tostring(e.level), tostring(e.inv),
            e.pos and (e.pos.x .. "," .. e.pos.y .. "," .. e.pos.z .. "," .. tostring(e.pos.f)) or "-",
            tostring(e.posOk), tostring(e.prog), tostring(e.paused), tostring(e.queue),
            e.note and e.note.text or "", e.pending and "p" or "", tostring(e.lastMsg),
            e.events and #e.events > 0 and e.events[#e.events].text or "" }, "|")
        local changed = (sig ~= e.sig) or newFinds > 0
        e.sig = sig
        return changed
    end

    -- Schickt einen Befehl an eine Einheit und merkt ihn als "wartet auf Antwort".
    -- Senden oder (Chunky-Turtle) bis zu ihrem naechsten Funkfenster aufheben.
    function app:deliver(id, payload)
        local e = self.store[id]
        if e and e.win and e.online then
            e.mail = e.mail or {}
            if #e.mail < 80 then e.mail[#e.mail + 1] = payload end
            return
        end
        Kernel.post(id, payload)
    end

    function app:transmit(id, cmd, label, args)
        Kernel.seq = Kernel.seq + 1
        local payload = { t = def.cmdType, cmd = cmd, seq = Kernel.seq, args = args }
        self:deliver(id, payload)
        local e = self.store[id]
        if e then e.pending, e.note = { seq = Kernel.seq, label = label, t = os.clock(), payload = payload }, nil end
        return Kernel.seq
    end

    -- Uebertraegt ein Programm in Teilen (die Turtle prueft die Pruefsumme).
    -- id = "*": ein Rundruf erreicht alle Turtles auf einmal.
    function app:pushCode(id, kind, name, prog)
        local size = TurtleProgs.CHUNK
        local parts = math.max(1, math.ceil(#prog.code / size))
        for i = 1, parts do
            local p = { t = kind, name = name, hash = prog.hash, part = i, parts = parts, ver = prog.ver,
                        data = prog.code:sub((i - 1) * size + 1, i * size) }
            if id == "*" then Kernel.post(id, p) else self:deliver(id, p) end
        end
        return parts
    end

    -- Startet ein Turtle-Programm. Fehlt es auf der Turtle oder ist es
    -- veraltet, wird es vorher uebertragen. Rueckgabe: Text fuer die Meldung.
    function app:runProgram(id, name, args, fresh)
        local e = self.store[id]
        local prog = TurtleProgs.get(name)
        if not prog then return "Programm " .. name .. " fehlt in LUA APPS", true end
        if not (e and e.progs) then return "Agent zu alt: TURTLE-DISK", true end
        local sent = ""
        if e.progs[name] ~= prog.hash then
            self:pushCode(id, "PROG", name, prog)
            sent = " (uebertragen)"
        end
        local owner = Settings.get("owner")
        self:transmit(id, "RUN", name:upper(), { name = name, hash = prog.hash, args = args, fresh = fresh,
                                                  owner = (owner ~= "") and owner or nil })
        if e.pending then e.pending.prog = { name = name, args = args, fresh = fresh } end
        return name:upper() .. sent
    end

    -- Neuer Agent per Funk: die Turtle schreibt ihn als startup und startet neu.
    -- all = true (ALLE): der Agent geht einmal per Rundruf an alle.
    function app:updateAgent(id, all)
        local prog = TurtleProgs.get("agent")
        if not prog then return "Agent fehlt", true end
        local e = self.store[id]
        if e and e.v == prog.ver then return "hat schon v" .. tostring(prog.ver), true end
        if not all or (e and e.win) then
            self:pushCode(id, "AGENT", "agent", prog)      -- einzeln (Chunky-Turtles hoeren den Rundruf nicht)
        elseif self.castHash ~= prog.hash or os.clock() - (self.castT or -99) > 10 then
            self:pushCode("*", "AGENT", "agent", prog)
            self.castHash, self.castT = prog.hash, os.clock()
        end
        if e then e.pending, e.note = { seq = -1, label = "UPDATE", t = os.clock(), acked = true }, nil end
        return "UPDATE v" .. tostring(prog.ver)
    end

    -- b = { label, cmd | run = function(app, id) -> Meldung }
    -- id = "*" schickt an alle Einheiten, die gerade online sind.
    function app:send(id, b)
        if not Kernel.hw.modem then
            Kernel.notify("Kein Modem angeschlossen", colors.red)
            return
        end
        local ids = {}
        if id == "*" then
            for uid, e in pairs(self.store) do
                if e.online then ids[#ids + 1] = uid end
            end
            table.sort(ids)
        else
            ids[1] = id
        end
        local text, failed
        for _, uid in ipairs(ids) do
            if b.run then
                text, failed = b.run(self, uid)
            else
                self:transmit(uid, b.cmd, b.name or b.label, b.args and b.args(uid) or nil)
                text = (b.name or b.label) .. (b.describe and (" " .. b.describe(b.args(uid))) or "")
            end
        end
        if id == "*" then
            Kernel.notify("ALLE (" .. #ids .. "): " .. (b.name or b.label) .. " gesendet")
        elseif failed then
            Kernel.notify("#" .. id .. ": " .. tostring(text), colors.red)
        elseif text then
            Kernel.notify("#" .. id .. ": " .. text .. " gesendet")
        end
    end

    function app:tick()
        local now, changed = os.clock(), false
        for id, e in pairs(self.store) do
            local age = now - e.seen
            if e.online and age > (e.win and (e.win * 2 + 8) or CONFIG.offlineAfter) then
                e.online, changed = false, true
                if e.pending and e.pending.label ~= "UPDATE" then e.pending = nil end
                Kernel.log("WARN", def.title .. ": #" .. id .. " offline")
                -- mitten in der Arbeit weg: melden (an der Basis offline ist normal)
                if def.finds and not READONLY and e.status ~= "Bereit" then self:warnUnit(id, e, "offline (war: " .. e.status .. ")") end
            end
            -- Keine Antwort: einmal wiederholen (die Turtle kann kurz ohne Funk
            -- sein, z.B. waehrend sie den Scanner anlegt), dann aufgeben.
            if e.pending and not e.pending.acked and e.pending.payload and not e.pending.retried
               and not e.win and e.online and now - e.pending.t > 4 then
                e.pending.retried = true
                Kernel.post(id, e.pending.payload)
            end
            if e.pending and not e.pending.acked and now - e.pending.t > (e.win and (e.win * 3 + 12) or 9) then
                e.note = { text = "Keine Antwort auf " .. e.pending.label, ok = false, untilT = now + 10 }
                e.pending, changed = nil, true
            end
            if e.pending and e.pending.label == "UPDATE" and now - e.pending.t > 60 then
                e.pending, changed = nil, true
            end
            if e.note and now > e.note.untilT then e.note, changed = nil, true end
            if not e.online then changed = true end -- "vor Xs" laeuft mit
            if age > CONFIG.forgetAfter then
                self.store[id] = nil
                self.count = self.count - 1
                if self.unit == id then self.view = "units" end
                changed = true
            end
        end
        return changed and (Kernel.app == self or Kernel.app.id == "home")
    end

    function app:onEnter(view)
        self.input = nil
        if type(view) == "number" and self.store[view] and def.drawUnit then return self:openUnit(view) end
        self.view = (view == "finds" or view == "map" or view == "plan") and view or "units"
    end

    function app:insert(text) return Input.insert(self, text) end
    function app:key(action) return Input.key(self, action) end
    function app:onChar(ch) Input.insert(self, ch) end
    function app:onPaste(text) Input.insert(self, text) end
    function app:onKey(code) Input.onKey(self, code) end

    -- Warnungen: Tank knapp, Inventar voll, keine Spitzhacke (einmal je Zustand)
    function app:warnUnit(id, e, text)
        local name = self:nameOf(id, e)
        local who = "#" .. id .. (name and (" " .. name) or "")
        Kernel.notify(who .. ": " .. text, colors.orange, def.id, id)
        if Settings.get("swarmChat") ~= false and Extras then Extras.tell(who .. ": " .. text, "GTS SCHWARM") end
    end

    function app:watch(id, e)
        local w = e.warn or {}
        e.warn = w
        local lvl = type(e.level) == "number" and e.level or nil
        local checks = {
            { "fuel", lvl and lvl < 500, not lvl or lvl > 1000, "Tank fast leer (" .. tostring(lvl) .. ")" },
            { "inv", (e.inv or 0) >= 16, (e.inv or 0) <= 13, "Inventar voll" },
            { "pick", e.pick == false, e.pick ~= false, "keine Spitzhacke im Inventar" },
        }
        for _, c in ipairs(checks) do
            if c[2] and not w[c[1]] then
                w[c[1]] = true
                self:warnUnit(id, e, c[4])
            elseif c[3] then
                w[c[1]] = nil
            end
        end
    end

    function app:onScroll(dir)
        if self.view == "map" then return self:zoom(dir) end
        local state = (self.view == "finds") and self.findsPage or self
        if self.view == "unit" then return end
        state.page = math.max(1, state.page + dir)
    end

    -- ---------- Karte: Draufsicht mit PC, Basen, Turtles und Funden ----------
    -- Norden ist oben. Ein Zeichen ist etwa 1,5-mal so hoch wie breit, darum
    -- zaehlt eine Zeile 1,5-mal so viele Bloecke wie eine Spalte.
    local MAP_SCALES = { 1, 2, 4, 8, 16, 32, 64, 128, 256, 512 }
    local ARROWS = { [0] = "\24", [1] = "\26", [2] = "\25", [3] = "\27" }

    function app:zoom(dir)
        local i = self.mapZoom or 4
        if self.mapAuto ~= false and self.mapFit then i = self.mapFit end
        self.mapZoom = math.max(1, math.min(#MAP_SCALES, i + dir))   -- runter = weiter weg
        self.mapAuto = false
    end

    -- Ausrichtung (INFO > EINSTELLUNGEN > Karte: oben): 0 = Norden oben,
    -- 1 = Osten, 2 = Sueden, 3 = Westen. Welt: x waechst nach Osten, z nach Sueden.
    -- Bildschirm-Achsen: r = nach rechts, d = nach unten.
    local function mapRot(up, x, z)
        if up == 1 then return z, -x elseif up == 2 then return -x, -z elseif up == 3 then return -z, x end
        return x, z
    end
    local function mapUnrot(up, r, d)
        if up == 1 then return -d, r elseif up == 2 then return -r, -d elseif up == 3 then return d, -r end
        return r, d
    end
    local function ageText(sec)
        sec = math.floor(sec)
        if sec < 60 then return sec .. " s" end
        if sec < 3600 then return math.floor(sec / 60) .. " min" end
        return math.floor(sec / 3600) .. " h"
    end

    function app:drawMap()
        local w, h, bh, narrow = Kernel.w, Kernel.h, UI.bh(), UI.narrow()
        local here = Geo.here()
        local up = tonumber(Settings.get("mapUp")) or 0
        if up ~= 1 and up ~= 2 and up ~= 3 then up = 0 end
        local gpsLayer = self.mapGps == true
        local ids = {}
        for id in pairs(self.store) do ids[#ids + 1] = id end
        table.sort(ids)
        -- Punkte: order = Zeichenreihenfolge (spaeter gezeichnet = obenauf)
        local pts, noPos, bases = {}, {}, {}
        local focus = self.mapFocus
        for _, f in ipairs(Finds.list) do
            if f.world then
                local on = (f == focus)
                pts[#pts + 1] = { x = f.x, z = f.z, ch = on and "\4" or "\7", fg = KINDS[f.kind].color, order = on and 4 or 0,
                                  label = on and f.kind or nil, keep = on, focus = on }
            end
        end
        for _, id in ipairs(ids) do
            local b = self.store[id].base
            if b and not bases[b.x .. "," .. b.z] then
                bases[b.x .. "," .. b.z] = true
                pts[#pts + 1] = { x = b.x, z = b.z, ch = "H", fg = colors.lightBlue, order = 1 }
            end
        end
        if here then
            pts[#pts + 1] = { x = here.x, z = here.z, ch = "\4", fg = colors.white, label = (EDITION == "pc") and "PC" or "DU", order = 2, keep = true }
        end
        for _, id in ipairs(ids) do
            local e = self.store[id]
            if e.wpos then
                local label = self:nameOf(id, e) or ("#" .. id)
                if gpsLayer then
                    -- GPS-Ebene: Alter der letzten GPS-Messung neben dem Namen
                    local age = e.gpsAge and (e.gpsAge + (os.clock() - e.seen))
                    label = label .. " " .. (age and ("GPS " .. ageText(age)) or (e.gpsOk and "GPS ok" or "kein GPS"))
                    if e.gpsFix and (e.gpsFix.x ~= e.wpos.x or e.gpsFix.z ~= e.wpos.z) then
                        pts[#pts + 1] = { x = e.gpsFix.x, z = e.gpsFix.z, ch = "+", fg = colors.yellow, order = 0.5 }
                    end
                end
                local dir = e.wf and ((e.wf - up) % 4)
                pts[#pts + 1] = { x = e.wpos.x, z = e.wpos.z, ch = dir and ARROWS[dir] or "\7",
                                  fg = e.online and (self:colorOf(id) or self.stateColor(e)) or colors.red,
                                  label = label, id = id, order = 3, keep = true }
            else
                noPos[#noPos + 1] = "#" .. id
            end
        end

        -- Kopf
        local actions = {
            { text = "-", onClick = function() self:zoom(1) end },
            { text = "+", onClick = function() self:zoom(-1) end },
            { text = "AUTO", style = (self.mapAuto ~= false) and "primary" or nil, onClick = function() self.mapAuto, self.mapFocus = true, nil end },
            { text = "GPS", style = gpsLayer and "primary" or nil, onClick = function()
                self.mapGps = not gpsLayer
                if self.mapGps then os.queueEvent("gts_gps") end        -- PC misst gleich neu
            end },
            { text = narrow and "\17" or (focus and "\17 FUNDE" or "\17 SCHWARM"), onClick = function()
                self.view, self.mapFocus = focus and "finds" or "units", nil
            end },
        }
        local top = UI.header("KARTE", nil, actions)
        local legendY = h - 1                  -- (letzte Zeile bleibt fuer Meldungen frei)
        local mx, my, mw, mh = 2, top, w - 2, legendY - top
        if mh < 3 or mw < 10 then return end

        -- Ausschnitt: AUTO = alles Wichtige passt hinein, sonst Zoom + Mitte
        local scale, cx, cz
        if #pts == 0 then
            UI.empty(top + 1, "Noch nichts auf der Karte.",
                     "Turtles mit Agent v5.1 und Basis-Koordinaten (GPS oder F3) erscheinen hier. PC-Position: GPS oder INFO > EINSTELLUNGEN.")
            return
        end
        if self.mapAuto ~= false then
            local r1, r2, d1, d2
            for _, p in ipairs(pts) do
                if p.keep or p.order == 1 then
                    local r, d = mapRot(up, p.x, p.z)
                    r1, r2 = math.min(r1 or r, r), math.max(r2 or r, r)
                    d1, d2 = math.min(d1 or d, d), math.max(d2 or d, d)
                end
            end
            if not r1 then r1, d1 = mapRot(up, pts[1].x, pts[1].z) r2, d2 = r1, d1 end
            cx, cz = mapUnrot(up, (r1 + r2) / 2, (d1 + d2) / 2)
            local fit = #MAP_SCALES
            for i, sc in ipairs(MAP_SCALES) do
                if (r2 - r1) / sc <= mw - 8 and (d2 - d1) / (sc * 1.5) <= mh - 2 then fit = i break end
            end
            self.mapFit, self.mapCx, self.mapCz = fit, cx, cz
            scale = MAP_SCALES[fit]
        else
            scale = MAP_SCALES[self.mapZoom or 4]
            cx, cz = self.mapCx or (here and here.x) or 0, self.mapCz or (here and here.z) or 0
        end
        local sx, sz = scale, scale * 1.5
        local ox, oy = mx + math.floor(mw / 2), my + math.floor(mh / 2)
        local function place(x, z)
            local r, d = mapRot(up, x - cx, z - cz)
            return ox + math.floor(r / sx + 0.5), oy + math.floor(d / sz + 0.5)
        end
        local function world(c, rr)          -- Bildschirm -> Welt
            local dx, dz = mapUnrot(up, (c - ox) * sx, (rr - oy) * sz)
            return cx + dx, cz + dz
        end
        local function inside(c, r) return c >= mx and c < mx + mw and r >= my and r < my + mh end

        -- Antippen der Flaeche: dorthin verschieben
        UI.hit(mx, my, mw, mh, function(x, y)
            self.mapCx, self.mapCz = world(x, y)
            self.mapZoom = self.mapZoom or (self.mapFit or 4)
            if self.mapAuto ~= false then self.mapZoom = self.mapFit or 4 end
            self.mapAuto = false
        end)

        -- Chunk-Raster: nah jeder Chunk, weiter weg nur jeder 2./4./8. ... (mind. 4 Zeichen Abstand)
        local k = 1
        while 16 * k / scale < 6 do k = k * 2 end
        local cell = 16 * k
        local function cellOf(c, rr)
            local x, z = world(c, rr)
            return math.floor(x / cell), math.floor(z / cell)
        end
        for c = mx + 1, mx + mw - 1 do
            local a1, b1 = cellOf(c - 1, oy)
            local a2, b2 = cellOf(c, oy)
            if a1 ~= a2 or b1 ~= b2 then
                for r = my, my + mh - 1 do UI.text(c, r, "\183", colors.brown) end
            end
        end
        for r = my + 1, my + mh - 1 do
            local a1, b1 = cellOf(ox, r - 1)
            local a2, b2 = cellOf(ox, r)
            if a1 ~= a2 or b1 ~= b2 then
                for c = mx, mx + mw - 1, 2 do UI.text(c, r, "\183", colors.brown) end
            end
        end
        -- Nordpfeil oben rechts (zeigt, wo Norden auf der gedrehten Karte liegt)
        UI.text(mx + mw - 3, my, "N" .. ARROWS[(0 - up) % 4], colors.lightGray)

        -- Punkte (Turtles und PC am Rand festhalten, wenn ausserhalb)
        table.sort(pts, function(a, b) return a.order < b.order end)
        local used = {}
        for _, p in ipairs(pts) do
            local c, r = place(p.x, p.z)
            local out = not inside(c, r)
            if out and p.keep then
                c = math.max(mx, math.min(mx + mw - 1, c))
                r = math.max(my, math.min(my + mh - 1, r))
            end
            if inside(c, r) then
                UI.text(c, r, p.ch, p.focus and colors.black or p.fg, p.focus and p.fg or (out and colors.gray or colors.black))
                used[c .. "," .. r] = true
                if p.label then
                    -- Beschriftung rechts daneben, am rechten Rand links davor
                    local lx = (c + #p.label < mx + mw) and (c + 1) or (c - #p.label)
                    local free = lx >= mx
                    for i = 0, #p.label - 1 do if used[(lx + i) .. "," .. r] then free = false end end
                    if free then
                        UI.text(lx, r, p.label, out and colors.lightGray or colors.white)
                        for i = 0, #p.label - 1 do used[(lx + i) .. "," .. r] = true end
                    end
                end
                if p.id then
                    local id = p.id
                    local lw = p.label and #p.label or 0
                    UI.hit(c - 1 - ((c + lw < mx + mw) and 0 or lw), r, lw + 2, 1, function() self:openUnit(id) end)
                end
            end
        end

        -- Fusszeile: Massstab, Raster, Legende, Turtles ohne Koordinaten
        local info = "1 Zeichen = " .. scale .. " Bl.  Raster " .. ((k == 1) and "1 Chunk" or (k .. " Chunks"))
        if gpsLayer then
            local g = Geo.gpsT and ((EDITION == "pc") and "PC" or "Du") .. "-GPS vor " .. ageText(os.clock() - Geo.gpsT)
            info = info .. "  " .. (g or ("PC-GPS: " .. ((Apps.byId.info and Apps.byId.info.gpsBusy) and "misst ..." or "keine Antwort")))
                   .. "  + letzte Turtle-Messung"
        else
            if not here then info = info .. "  PC-Position fehlt (GPS / INFO)" end
            if #noPos > 0 then info = info .. "  ohne Koord.: " .. table.concat(noPos, " ") end
            if not narrow and #info + 30 < w then info = info .. "   \4 " .. ((EDITION == "pc") and "PC" or "Du") .. "  H Basis  \26 Turtle  \7 Fund" end
        end
        if focus then
            local d = Geo.from(here, focus)
            info = "Fund " .. focus.kind .. " " .. Finds.where(focus) .. (d and ("  " .. d .. ((EDITION == "pc") and " vom PC" or " von dir")) or "")
                   .. "  #" .. focus.id .. " " .. tostring(focus.name)
        end
        UI.text(2, legendY, info:sub(1, w - 2), focus and colors.white or colors.lightGray)
    end

    function app:drawFinds()
        local w, bh, narrow = Kernel.w, UI.bh(), UI.narrow()
        local n = #Finds.list
        local top = UI.header("FUNDE", (n == 1) and "1 offener Fund" or (n .. " offene Funde"), {
            { text = narrow and "\17" or ("\17 " .. def.short:upper()), onClick = function() self.view = "units" end },
            { text = "NOTIZ", disabled = n == 0 or READONLY, onClick = function()
                local lines = { "GTS Funde (" .. #Finds.list .. ")", "" }
                for _, f in ipairs(Finds.list) do
                    lines[#lines + 1] = f.kind .. " " .. Finds.where(f) .. " #" .. f.id .. " " .. f.name
                end
                local ok, err = Notes.write("funde", lines)
                Kernel.notify(ok and "Notiz 'funde' gespeichert" or err, ok and colors.lime or colors.red)
            end },
            { text = "LEEREN", style = "danger", confirm = def.id .. ":clearfinds", disabled = n == 0, onClick = function()
                Finds.clear()
                Kernel.notify("Funde geleert", colors.orange)
            end },
        })
        if n == 0 then
            UI.empty(top + 2, "Noch keine Funde.", "Gemeldet werden Allthemodium-Erz, Kisten, Lehm, Ancient Citys und Sculk.")
            return
        end
        local ch = narrow and 2 or bh
        UI.list(self.findsPage, Finds.list, top, ch + 1, function(f, y)
            local tx, xr = UI.rowCard(y, ch)
            UI.text(tx - 2, y, "\149", KINDS[f.kind].color)
            local by = narrow and (y + 1) or y
            local bx = UI.button{ x = xr - 3, y = by, w = 4, text = "OK", fg = colors.lime,
                                  onClick = function() Finds.done(f) end } - 4
            UI.text(tx, y, f.kind, KINDS[f.kind].color)
            local where = Finds.where(f)
            local dist = f.world and Geo.from(Geo.here(), f)
            if dist and not narrow then where = where .. "  (" .. dist .. ")" end
            if f.world then
                UI.hit(tx - 2, y, bx - tx + 1, ch, function()
                    self.view, self.mapFocus, self.mapAuto = "map", f, false
                    self.mapCx, self.mapCz, self.mapZoom = f.x, f.z, 3
                end)
            end
            if narrow then
                UI.text(tx + 6, y, where:sub(1, xr - tx - 5), f.world and colors.white or colors.lightGray)
                UI.text(tx, y + 1, ("#" .. f.id .. " " .. f.name):sub(1, bx - tx - 1), colors.lightGray)
            else
                UI.text(tx + 7, y, where:sub(1, bx - tx - 8), f.world and colors.white or colors.lightGray)
                local who = "#" .. f.id .. " " .. f.name
                local wx = tx + 7 + ((w >= 70) and math.max(#where + 3, 24) or (#where + 2))
                if wx + 4 < bx then UI.text(wx, y, who:sub(1, bx - wx - 1), colors.lightGray) end
            end
        end)
    end

    -- Farbe des Streifens links an einer Einheit: Zustand auf einen Blick.
    local function stateColor(e)
        if not e.online then return colors.red end
        if e.pending or e.status ~= "Bereit" then return colors.yellow end
        if e.paused then return colors.orange end
        return colors.lime
    end
    app.stateColor = stateColor

    -- Zweite Zeile einer Einheit: das Wichtigste zuerst.
    function app:summary(e)
        local idle = (e.status == "Bereit")
        local level = def.levelLabel .. ":" .. fmtNum(e.level)
        if not e.online then
            local line = "OFFLINE seit " .. math.floor(os.clock() - e.seen) .. "s"
            if e.keyOld then line = line .. " (Passwort an der Turtle: P)"
            elseif not idle then line = line .. " (" .. e.status .. ")" end
            return line, colors.red
        elseif e.note then
            return e.note.text, e.note.ok and colors.lime or colors.red
        elseif e.pending and not e.pending.acked then
            return "> " .. e.pending.label .. (e.win and " ... (naechstes Funkfenster)" or " ..."), colors.yellow
        elseif not idle then
            local where = Geo.from(Geo.here(), e.wpos)
            return e.status .. " " .. level .. ((e.inv and (" I:" .. e.inv)) or "") .. (where and ("  " .. where) or ""), colors.lime
        elseif e.pending then
            return "> " .. e.pending.label .. " wartet", colors.yellow
        elseif e.paused and e.prog then
            return e.prog:upper() .. " pausiert: " .. tostring(e.lastMsg or "-"), colors.orange
        end
        local line = level
        if e.inv then line = line .. " I:" .. e.inv end
        local where = Geo.from(Geo.here(), e.wpos)
        if where then
            line = line .. "  " .. where
        elseif e.wpos then
            line = line .. " W:" .. e.wpos.x .. "," .. e.wpos.y .. "," .. e.wpos.z
        elseif e.pos then
            line = line .. " P:" .. e.pos.x .. "," .. e.pos.y .. "," .. e.pos.z .. (e.posOk and "" or "?")
        end
        return line, colors.lightGray
    end

    function app:openUnit(id)
        self.view, self.unit, self.sub = "unit", id, "info"
    end

    -- Planer: ein Auftrag fuer alle freien Turtles; DD verteilt Richtungen und Spuren.
    local LONG = { [0] = "Nord", [1] = "Ost", [2] = "Sued", [3] = "West" }
    function app:drawPlan()
        local w, h, bh, narrow = Kernel.w, Kernel.h, UI.bh(), UI.narrow()
        local job = (self.planJob == "chunk") and "chunk" or "dd"
        local plan = def.plan[job]
        local top = UI.header("PLANER", not narrow and "Ein Auftrag fuer alle freien Turtles" or nil, {
            { text = narrow and "\17" or "\17 SCHWARM", onClick = function() self.view = "units" end } })
        local ids, free = {}, {}
        for id, e in pairs(self.store) do if e.online then ids[#ids + 1] = id end end
        table.sort(ids)
        for _, id in ipairs(ids) do
            local e = self.store[id]
            if e.status == "Bereit" and not e.pending then free[#free + 1] = id end
        end
        local y = top
        local function choice(label, list)
            if not narrow then UI.text(2, y, label, colors.lightGray) end
            UI.flow(list, narrow and 2 or 12, y, w - 1)
            y = y + bh + ((bh == 1) and 1 or 0)
        end
        choice("Auftrag", {
            { text = "DD", h = 1, style = (job == "dd") and "primary" or nil, onClick = function() self.planJob = "dd" end },
            { text = "CHUNK", h = 1, style = (job == "chunk") and "primary" or nil, onClick = function() self.planJob = "chunk" end },
        })
        if job == "dd" then
            local list = {}
            for _, v in ipairs({ 64, 96, 128, 256 }) do
                list[#list + 1] = { text = tostring(v), h = 1, style = (CONFIG.exploreDist == v) and "primary" or nil,
                                    onClick = function() Settings.set("ddDist", v) CONFIG.exploreDist = v end }
            end
            choice("Tunnel", list)
        else
            local trash = Settings.get("chunkTrash") ~= false
            choice("Muell", {
                { text = "WEG", h = 1, style = trash and "primary" or nil, onClick = function() Settings.set("chunkTrash", true) end },
                { text = "BEHALTEN", h = 1, style = (not trash) and "primary" or nil, onClick = function() Settings.set("chunkTrash", false) end },
            })
        end
        UI.section(2, y, ((#free == 1) and "1 freie Turtle" or (#free .. " freie Turtles")) .. " von " .. #ids .. " online", w - 3)
        y = y + 1
        local isFree = {}
        for _, id in ipairs(free) do isFree[id] = true end
        local rowsLeft = h - bh * 2 - 2 - y
        for i, id in ipairs(ids) do
            if i > rowsLeft then
                UI.text(2, y, "... und " .. (#ids - i + 1) .. " weitere", colors.lightGray)
                y = y + 1
                break
            end
            local e = self.store[id]
            local name = self:nameOf(id, e)
            UI.text(2, y, "\7", isFree[id] and (self:colorOf(id) or colors.lime) or colors.yellow)
            UI.text(4, y, ("#" .. id .. (name and (" " .. name) or "")):sub(1, 18), colors.white)
            local what
            if not isFree[id] then
                what = e.pending and ("wartet auf " .. tostring(e.pending.label)) or ("arbeitet: " .. tostring(e.prog and e.prog:upper() or e.status))
            elseif job == "dd" then
                local a = plan.args(id)
                what = "\26 " .. LONG[a.dir] .. ", Spur " .. (a.lane + 1) .. ", " .. a.dist .. " Bloecke"
            else
                what = "\26 Chunk an ihrem Platz abbauen"
            end
            UI.text(narrow and 4 or 24, narrow and (y + 1) or y, what:sub(1, w - (narrow and 5 or 25)), isFree[id] and colors.lightGray or colors.yellow)
            y = y + (narrow and 2 or 1)
        end
        local label = "START: " .. job:upper() .. " AUF " .. #free .. ((#free == 1) and " TURTLE" or " TURTLES")
        UI.button{ x = 2, y = h - bh * 2, text = narrow and ("START (" .. #free .. ")") or label, style = "primary", confirm = "plan:" .. job,
                   disabled = #free == 0 or not Kernel.hw.modem, onClick = function()
            for _, id in ipairs(free) do self:runProgram(id, plan.name, plan.args(id)) end
            Kernel.notify("PLANER: " .. job:upper() .. " an " .. #free .. " Turtle(s) gesendet", colors.lime)
            self.view = "units"
        end }
    end

    function app:draw()
        if self.input then return Input.draw(self) end
        if self.view == "plan" and def.plan and not READONLY then return self:drawPlan() end
        if self.view == "finds" then return self:drawFinds() end
        if self.view == "map" and def.finds then return self:drawMap() end
        if self.view == "unit" and self.store[self.unit] and def.drawUnit then return def.drawUnit(self, self.store[self.unit]) end
        self.view = "units"
        local w, bh, narrow = Kernel.w, UI.bh(), UI.narrow()
        local online, total = self:counts()
        local actions = {}
        if def.finds then
            local n = #Finds.list
            actions[#actions + 1] = { text = "FUNDE " .. n, style = (n > 0) and "primary" or nil,
                                      onClick = function() self.view = "finds" end }
            actions[#actions + 1] = { text = "KARTE", onClick = function() self.view, self.mapFocus = "map", nil end }
            if not READONLY and def.plan then
                actions[#actions + 1] = { text = narrow and "PLAN" or "PLANER", onClick = function() self.view = "plan" end }
            end
        end
        local all = {}
        if not READONLY then
            for _, b in ipairs(def.all) do
                if not (b.show and not b.show(self)) then
                    local pad = narrow and 0 or 1
                    all[#all + 1] = { text = b.label, w = #b.label + 2 * pad, style = b.style and b.style(self), fg = b.fg,
                                      confirm = b.confirm and (def.id .. ":all:" .. b.label) or nil, disabled = online == 0,
                                      onClick = function() self:send("*", b) end }
                end
            end
        end
        -- Passen die ALLE-Buttons nicht mehr in die Kopfzeile, bekommen sie eine eigene Zeile.
        local function width(list)
            local t = 0
            for _, a in ipairs(list) do t = t + (a.w or (a.label and #a.label) or (#a.text + 2)) + 1 end
            return t
        end
        local allRow = narrow or (#all > 0 and width(actions) + 5 + width(all) > w - 6)
        if not allRow and #all > 0 then
            actions[#actions + 1] = { label = "ALLE" }
            for _, b in ipairs(all) do actions[#actions + 1] = b end
        end
        local top = UI.header(def.title, def.heading .. " " .. online .. "/" .. total, actions)
        if allRow and #all > 0 then
            for _, b in ipairs(all) do b.h = 1 end
            UI.text(2, top - 1, "ALLE", colors.lightGray)
            UI.buttonsRight(all, top - 1, w - 1)
            top = top + 1
        end

        -- Alte Turtles (v4) funken unverschluesselt: Hinweis zum Neu-Installieren.
        local old = 0
        if def.finds then
            for id, t in pairs(legacy) do
                if os.clock() - t < 30 then old = old + 1 else legacy[id] = nil end
            end
        end
        if old > 0 then
            UI.text(2, top, ("! " .. old .. " alte Turtle(s) v4: per TURTLE-DISK (DATEN) neu installieren"):sub(1, w - 2), colors.orange)
            top = top + 1
        end

        if total == 0 then
            local hint = def.hint
            if not Kernel.hw.modem then hint = "Kein Modem angeschlossen!"
            elseif READONLY then
                hint = "Am Pocket dasselbe Schwarm-Passwort wie am PC eingeben: INFO > SETUP."
            elseif not hint then
                hint = "Turtle einrichten: DATEN > TURTLE-DISK, Laufwerk neben die Turtle, Diskette rein, Turtle neu starten."
                if Net.isDefault then hint = hint .. " Tipp: in INFO ein eigenes Schwarm-Passwort setzen." end
            end
            UI.empty(top + 1, def.empty, hint)
            return
        end

        local ids = {}
        for id in pairs(self.store) do ids[#ids + 1] = id end
        table.sort(ids)

        local ch = (narrow and not READONLY) and 3 or 2
        UI.list(self, ids, top, ch + 1, function(id, y)
            local e = self.store[id]
            local tx, xr = UI.rowCard(y, ch)
            for r = 0, ch - 1 do UI.text(tx - 2, y + r, "\149", stateColor(e)) end
            local bx = xr + 2
            if not READONLY then
                local pad = (w >= 70) and 1 or 0
                local buttons = {}
                for _, b in ipairs(def.buttons) do
                    local style = b.style
                    local fg = b.fg
                    if b.prog and e.paused and e.prog == b.prog and style ~= "primary" then fg = colors.orange end
                    buttons[#buttons + 1] = { text = b.label, w = #b.label + 2 * pad, style = style, fg = fg,
                                              h = narrow and 1 or bh, disabled = not e.online,
                                              onClick = function() self:send(id, b) end }
                end
                if def.drawUnit then
                    table.insert(buttons, 1, { text = "\187", w = 1 + 2 * pad, h = narrow and 1 or bh, fg = colors.lightGray,
                                               onClick = function() self:openUnit(id) end })
                end
                bx = UI.buttonsRight(buttons, narrow and (y + 2) or y, narrow and (xr + 1) or xr)
            end
            local infoW = ((narrow or READONLY) and xr or (bx - 2)) - tx + 1
            if def.drawUnit then UI.hit(tx, y, infoW, 2, function() self:openUnit(id) end) end

            local idle = (e.status == "Bereit")
            local name, tc = self:nameOf(id, e), self:colorOf(id)
            local head = ("#" .. id .. (name and (" " .. name) or "")):sub(1, infoW)
            UI.text(tx, y, head, e.online and colors.white or colors.lightGray)
            if tc and e.online and #head > #tostring(id) + 2 then UI.text(tx + #tostring(id) + 2, y, head:sub(#tostring(id) + 3), tc) end
            local room = infoW - #head - 2
            if room >= 4 and e.online then
                local st = e.status
                if idle and e.paused and e.prog then st = e.prog:upper() .. " PAUSE" end
                UI.text(tx + #head + 2, y, st:sub(1, room), idle and (e.paused and colors.orange or colors.lime) or colors.yellow)
            end
            local line, color = self:summary(e)
            -- Am PC sind die Buttons nur eine Zeile hoch: Zeile 2 hat die volle Breite.
            UI.text(tx, y + 1, line:sub(1, (bh == 1 and not narrow) and (xr - tx + 1) or infoW), color)
        end)
    end

    Fleets[def.upType] = app
    app.hidden = def.hidden
    if def.hidden then return app end      -- versteckt: Funk laeuft, aber keine App
    return Apps.register(app)
end

-- DD: jede Turtle bekommt eine feste Richtung und Spur, damit sich der
-- Schwarm auffaechert. Turtle 1-4: N, O, S, W. Turtle 5-8: dieselben
-- Richtungen, eine Spur (16 Bloecke) daneben. Usw.
-- Kennt eine Turtle ihre Himmelsrichtung nicht, zaehlt sie ab ihrer
-- eigenen Blickrichtung an der Basis.
local COMPASS = { [0] = "N", [1] = "O", [2] = "S", [3] = "W" }
local function exploreArgs(id)
    local slot = Finds.slotFor(id)
    return { dir = slot % 4, lane = math.floor(slot / 4), dist = CONFIG.exploreDist }
end
local function chunkArgs() return { trash = Settings.get("chunkTrash") ~= false, size = 16 } end

-- Programm-Buttons: DD faechert auf, CHUNK baut den Chunk ab, T testet.
local function progButton(label, name, args, extra)
    local b = { label = label, prog = name, run = function(self, id)
        return self:runProgram(id, name, args and args(id) or nil)
    end }
    for k, v in pairs(extra or {}) do b[k] = v end
    return b
end

-- Grundfunktionen fuer das Test-Panel (Agent: FN).
local FN_BUTTONS = {
    { "STEUERN", { { "VOR", "vor" }, { "ZURUECK", "zurueck" }, { "HOCH", "hoch" }, { "RUNTER", "runter" },
                   { "\27 LINKS", "links" }, { "RECHTS \26", "rechts" } } },
    { "TESTEN",  { { "GRABEN", "graben" }, { "SCHAUEN", "schauen" }, { "SCAN", "scan" }, { "ERZE", "chunk" },
                   { "GPS", "gps" }, { "INVENTAR", "inventar" } } },
}

-- Werkzeuge der Turtle (Agent: tools) und ihre Test-Knoepfe.
local TOOL_LABEL = { chunky = "Chunky", modem = "Modem", scanner = "Scanner", compass = "Kompass",
                     env = "Umgebung", player = "Spieler", chat = "Chat", speaker = "Ton" }
local TOOL_BUTTONS = { { "compass", "KOMPASS", "kompass" }, { "env", "BIOM", "umgebung" },
                       { "player", "SPIELER", "spieler" }, { "chat", "CHAT", "chat" }, { "speaker", "PIEP", "ton" } }

-- Farben fuer Turtles (FARBE schaltet weiter; 0 = keine eigene Farbe)
local TURTLE_COLORS = { 0, colors.cyan, colors.orange, colors.magenta, colors.yellow, colors.lightBlue,
                        colors.pink, colors.purple, colors.blue, colors.white }

-- Detailansicht einer Turtle: Werte links, Test-Panel rechts.
local function drawTurtle(self, e)
    local w, h, bh, narrow = Kernel.w, Kernel.h, UI.bh(), UI.narrow()
    local id = e.id
    local wide = w >= 80
    local agent = TurtleProgs.get("agent")
    local actions = {}
    if not wide and not READONLY then
        actions[#actions + 1] = { text = "INFO", style = self.sub == "info" and "primary" or nil, onClick = function() self.sub = "info" end }
        actions[#actions + 1] = { text = "TESTEN", style = self.sub == "test" and "primary" or nil, onClick = function() self.sub = "test" end }
    end
    if not READONLY and not narrow then
        local tc = self:colorOf(id)
        actions[#actions + 1] = { text = "NAME", onClick = function()
            Input.open(self, { title = "Name fuer Turtle #" .. id, text = self:nameOf(id, e) or "", maxLen = 12, filter = "[^%w_%- ]",
                               hint = "Leer = ohne Namen. Ab Agent v5.2 bekommt ihn auch die Turtle.", onOk = function(t)
                self:setName(id, t)
                if e.online then
                    self:send(id, { label = "NAME", name = "NAME", cmd = "FN", args = function() return { fn = "name", label = t } end })
                end
            end })
        end }
        actions[#actions + 1] = { text = "FARBE", fg = tc, onClick = function()
            local cur = 1
            for i, c in ipairs(TURTLE_COLORS) do if c == (tc or 0) then cur = i end end
            self:setName(id, nil, TURTLE_COLORS[cur % #TURTLE_COLORS + 1])
        end }
    end
    actions[#actions + 1] = { text = narrow and "\17" or "\17 SCHWARM", onClick = function() self.view = "units" end }
    local sub = (e.online and e.status or "OFFLINE") .. (e.v and ("  Agent v" .. e.v) or "")
    local name = self:nameOf(id, e)
    local top = UI.header("#" .. id .. (name and (" " .. name) or ""), sub, actions,
                          e.online and (e.status == "Bereit" and colors.lime or colors.yellow) or colors.red)

    local showInfo = wide or READONLY or self.sub ~= "test"
    local showTest = not READONLY and (wide or self.sub == "test")
    local lw = wide and math.min(44, math.floor(w * 0.45)) or (w - 2)
    local bottom = h - bh - 1

    if showInfo then
        local x, vx, y = 2, narrow and 9 or 12, top
        local vw = lw - (vx - x)
        local function row(label, text, color)
            if y > bottom then return end
            UI.text(x, y, label, colors.lightGray)
            UI.text(vx, y, tostring(text):sub(1, vw), color or colors.white)
            y = y + 1
        end
        local line, color = self:summary(e)
        row("STATUS", line, color)
        if e.level == "unlimited" then row("TANK", "unbegrenzt")
        elseif e.level then
            local bw = math.max(4, vw - 7)
            if y <= bottom then
                UI.text(x, y, "TANK", colors.lightGray)
                local frac = e.level / math.max(1, math.min(e.levelMax or 20000, 20000))
                UI.bar(vx, y, bw, frac, (e.level < 500) and colors.red or colors.lime)
                UI.text(vx + bw + 1, y, fmtNum(e.level), (e.level < 500) and colors.red or colors.white)
                y = y + 1
            end
        end
        if e.inv and y <= bottom then
            local bw = math.max(4, vw - 7)
            UI.text(x, y, narrow and "INV" or "INVENTAR", colors.lightGray)
            UI.bar(vx, y, bw, e.inv / 16, (e.inv >= 13) and colors.orange or colors.green)
            UI.text(vx + bw + 1, y, e.inv .. "/16", colors.white)
            y = y + 1
        end
        if e.wpos then
            row("WELT", e.wpos.x .. " " .. e.wpos.y .. " " .. e.wpos.z .. "  Blick " .. (e.wf and COMPASS[e.wf] or "?")
                .. (e.gpsOk and "  GPS" or ""), e.posOk and colors.white or colors.red)
            local where = Geo.from(Geo.here(), e.wpos)
            if where then row(narrow and "ABST." or "ABSTAND", where .. ((EDITION == "pc") and " vom PC" or " von dir"), colors.lightGray) end
        end
        if e.pos then
            local facing = e.pos.f and (e.compass and COMPASS[(e.compass + e.pos.f) % 4] or tostring(e.pos.f)) or "?"
            row(narrow and "POS" or (e.wpos and "VON BASIS" or "POSITION"), e.pos.x .. " " .. e.pos.y .. " " .. e.pos.z
                .. (e.wpos and "" or ("  Blick " .. facing)), e.posOk and colors.white or colors.red)
        end
        if e.base then
            row("BASIS", e.base.x .. " " .. e.base.y .. " " .. e.base.z .. (e.compass and "" or "  (Richtung folgt)"), colors.white)
        else
            row("BASIS", e.world and ("Welt-Koordinaten" .. (e.gps and " (GPS)" or "")) or "ohne Koordinaten",
                e.world and colors.white or colors.lightGray)
        end
        if e.prog then row("AUFTRAG", e.prog:upper() .. (e.paused and " pausiert" or " laeuft"), e.paused and colors.orange or colors.yellow) end
        -- Programme: aktuell / wird beim Start uebertragen
        local parts, missing = {}, false
        for _, name in ipairs({ "dd", "chunk", "test" }) do
            local p = TurtleProgs.get(name)
            local have = e.progs and e.progs[name]
            local mark = (not have) and "-" or ((p and have == p.hash) and "ok" or "alt")
            parts[#parts + 1] = name:upper() .. " " .. mark
            if mark ~= "ok" then missing = true end
        end
        row(narrow and "PROG" or "PROGRAMME", table.concat(parts, "  "), colors.white)
        if missing and not narrow then row("", "(- = kommt beim Start mit)", colors.lightGray) end
        if agent and e.v then
            local fresh = (e.v == agent.ver)
            row("AGENT", "v" .. e.v .. (fresh and " aktuell" or (" -> v" .. tostring(agent.ver) .. " (UPDATE)")),
                fresh and colors.lightGray or colors.orange)
        end
        local tl = {}
        for _, t in ipairs(e.tools or {}) do
            if t ~= "modem" and (t ~= "chunky" or not e.win) then tl[#tl + 1] = TOOL_LABEL[t] or t end
        end
        if #tl == 0 and e.scanner then tl[1] = "Scanner" end
        if e.pick == false then
            row(narrow and "WERKZ" or "WERKZEUG", "KEINE SPITZHACKE! " .. table.concat(tl, " "), colors.red)
        else
            row(narrow and "WERKZ" or "WERKZEUG", "Hacke" .. (#tl > 0 and (" + " .. table.concat(tl, " ")) or ""), colors.lightGray)
        end
        if e.win then
            row("FUNK", "Chunky, Funk alle " .. e.win .. " s (Agent alt)", colors.orange)
        else
            row("FUNK", "Modem (immer)" .. ((e.toolSet and e.toolSet.chunky) and ", Chunky alle 4 min" or ""), colors.lightGray)
        end
        if e.lastMsg and y <= bottom then
            UI.text(x, y, narrow and "LETZT" or "ZULETZT", colors.lightGray)
            for i, l in ipairs(UI.wrap(e.lastMsg, vw)) do
                if y > bottom or i > 2 then break end
                UI.text(vx, y, l, e.lastOk and colors.lightGray or colors.red)
                y = y + 1
            end
        end
        if e.events and #e.events > 0 and y + 1 <= bottom then
            y = y + 1
            UI.section(x, y, "VERLAUF", lw - 1)
            y = y + 1
            for i = #e.events, 1, -1 do
                if y > bottom then break end
                UI.text(x, y, ("\183 " .. e.events[i].text):sub(1, lw), colors.lightGray)
                y = y + 1
            end
        end
    end

    if showTest then
        local x0 = wide and (lw + 4) or 2
        local xMax = w - 1
        local y = top
        local gap = (bh >= 2) and 0 or 1
        local function send(b) return function() self:send(id, b) end end
        local function fnButton(label, fn)
            return { text = label, disabled = not e.online, onClick = send({ label = label, name = label, cmd = "FN",
                     args = function() return { fn = fn } end }) }
        end
        UI.section(x0, y, "PROGRAMME", xMax - x0 + 1)
        y = y + 1
        local trash = Settings.get("chunkTrash") ~= false
        local customButtons = {}
        for _, name in ipairs(TurtleProgs.custom()) do
            customButtons[#customButtons + 1] = { text = name:upper():sub(1, 12), disabled = not e.online,
                                                  onClick = send(progButton(name:upper(), name)) }
        end
        local progList = {
            { text = "DD", style = "primary", disabled = not e.online, onClick = send(progButton("DD", "dd", exploreArgs)) },
            { text = "CHUNK", fg = (e.paused and e.prog == "chunk") and colors.orange or nil, disabled = not e.online,
              onClick = send(progButton("CHUNK", "chunk", chunkArgs)) },
            { text = "TEST", disabled = not e.online, onClick = send(progButton("TEST", "test")) },
        }
        for _, b in ipairs(customButtons) do progList[#progList + 1] = b end
        progList[#progList + 1] = { text = trash and "CHUNK-MUELL: WEG" or "CHUNK-MUELL: BEHALTEN", style = "ghost",
            fg = trash and colors.orange or colors.lightBlue, onClick = function()
                Settings.set("chunkTrash", not trash)
                Kernel.notify("CHUNK: Muell wird " .. (trash and "behalten (alles in die Kiste)" or "weggeworfen"))
            end }
        y = UI.flow(progList, x0, y, xMax) + gap
        local groups = { FN_BUTTONS[1], FN_BUTTONS[2] }
        local tb = { { "LISTE", "werkzeug" } }
        for _, t in ipairs(TOOL_BUTTONS) do
            if e.toolSet and e.toolSet[t[1]] then tb[#tb + 1] = { t[2], t[3] } end
        end
        groups[3] = { "WERKZEUG", tb }
        for _, group in ipairs(groups) do
            local list = {}
            for _, b in ipairs(group[2]) do list[#list + 1] = fnButton(b[1], b[2]) end
            if y + UI.flowHeight(list, x0, xMax) > h then break end
            UI.section(x0, y, group[1], xMax - x0 + 1)
            y = y + 1
            y = UI.flow(list, x0, y, xMax) + gap
        end
        local upd = agent and e.v and e.v ~= agent.ver
        local basis = {
            { text = "ABLADEN", disabled = not e.online, onClick = send({ label = "ABLADEN", cmd = "FN", args = function() return { fn = "abladen" } end }) },
            { text = "MUELL", disabled = not e.online, onClick = send({ label = "MUELL", cmd = "DROP" }) },
            { text = "TANK", fg = colors.yellow, disabled = not e.online, onClick = send({ label = "TANK", cmd = "REFUEL" }) },
            { text = "BASIS", fg = colors.lightBlue, disabled = not e.online, onClick = send({ label = "BASIS", cmd = "HOME" }) },
            { text = "STOP", style = "danger", disabled = not e.online, onClick = send({ label = "STOP", cmd = "STOP" }) },
            { text = "UPDATE", style = upd and "primary" or nil, disabled = not e.online, confirm = "upd:" .. id,
              onClick = send({ label = "UPDATE", run = function(app, uid) return app:updateAgent(uid) end }) },
        }
        if y + UI.flowHeight(basis, x0, xMax) <= h then
            UI.section(x0, y, "BASIS", xMax - x0 + 1)
            y = y + 1
            UI.flow(basis, x0, y, xMax)
        end
    end
end

makeFleet{
    id = "swarm", title = "SCHWARM", short = "Schwarm", heading = "Online",
    color = colors.red, order = 3, finds = true,
    upType = "UP", cmdType = "CMD",
    levelField = "fuel", levelLabel = "T",
    empty = "Keine Turtles gefunden.",
    drawUnit = drawTurtle,
    plan = { dd = { name = "dd", args = exploreArgs }, chunk = { name = "chunk", args = chunkArgs } },
    buttons = {
        progButton("DD", "dd", exploreArgs, { style = "primary" }),
        progButton("CHUNK", "chunk", chunkArgs),
        progButton("T", "test"),
        { label = "BASIS", cmd = "HOME", fg = colors.lightBlue },
        { label = "STOP",  cmd = "STOP", style = "danger" },
    },
    all = {
        progButton("DD", "dd", exploreArgs, { confirm = true, style = function() return "primary" end }),
        { label = "BASIS", cmd = "HOME", fg = colors.lightBlue, confirm = true },
        { label = "STOP",  cmd = "STOP", style = function() return "danger" end },
        { label = "UPDATE", confirm = true, run = function(app, id) return app:updateAgent(id, true) end,
          show = function(app)
              local agent = TurtleProgs.get("agent")
              for _, e in pairs(app.store) do
                  if e.online and agent and e.v ~= agent.ver then return true end
              end
              return false
          end },
    },
}

-- ######################################################################
-- ## FUER SPAETER (ATM10): P.CRAFT - PneumaticCraft-Drohnen             ##
-- ## Seit v8.0 VERSTECKT (hidden = true), aber vollstaendig erhalten.    ##
-- ## Die Drohnen funken nicht selbst per rednet: es braucht einen       ##
-- ## Bruecken-Computer am "Drone Interface", der dieses Protokoll       ##
-- ## spricht (Typen "DUP" und "DCMD", verschluesselt wie der Schwarm).  ##
-- ## Wieder einschalten: hidden = true unten entfernen.                ##
-- ######################################################################
makeFleet{
    id = "pcraft", title = "P.CRAFT", short = "Drohnen", heading = "Drohnen",
    hidden = true,   -- FUER SPAETER (ATM10), siehe Kasten oben
    color = colors.orange, order = 4,
    upType = "DUP", cmdType = "DCMD",
    levelField = "air", levelLabel = "L",
    empty = "Keine Drohnen gefunden.",
    hint = "Braucht Bruecken-PC am Drone Interface.",
    buttons = {
        { label = "SCOUT", cmd = "SCOUT" },
        { label = "ROUTE", cmd = "MANEUVER" },
        { label = "BASIS", cmd = "HOME",     fg = colors.lightBlue },
    },
    all = {
        { label = "BASIS", cmd = "HOME", fg = colors.lightBlue, confirm = true },
    },
}

-- ======================================================================
-- [7c] CLAUDE: der Begleit-Droide
-- ======================================================================
-- Eine Turtle mit dem Programm "claude" (Agent ab v5.4) meldet sich mit
-- role = "claude". Sie erscheint NICHT im Schwarm (also nie bei ALLE,
-- PLANER usw.), sondern hier. Befehle gehen als CMD "PMSG" direkt an das
-- laufende Programm, Antworten (Karte, Log, Einstellungen) kommen als "CLD".
-- Am PC hoert die Chat Box mit und reicht "$claude ..." weiter.
-- Die Fernbedienung (gts_claude.lua, EDITION "claude") ist dieselbe App.
local REMOTE = (EDITION == "claude")
local Claude = { id = "claude", title = "CLAUDE", order = 3.5, view = "status", units = {}, count = 0,
                 modePage = { page = 1 }, logPage = { page = 1 }, setupPage = { page = 1 }, group = "FREI",
                 zoom = 1, mapT = -99, logT = -99, cfgT = -99, relayT = -999 }

local CL_MODES = {
    idle = "FREI", stay = "BLEIBT", follow = "FOLGT", come = "KOMMT", home = "FLIEGT HEIM", patrol = "PATROUILLE",
    guard = "WACHE", build = "BAUT", craft = "CRAFTET", torch = "FACKEL", hide = "VERSTECKT SICH", seek = "SUCHT",
    nofuel = "TANK LEER",
}

Claude.MODES = CL_MODES
local function clNum(v) return (type(v) == "number" and v == v and math.abs(v) < 1e13) and v or nil end
local function clCell(t)
    if type(t) == "table" and clNum(t.x) and clNum(t.y) and clNum(t.z) then
        return { x = math.floor(t.x), y = math.floor(t.y), z = math.floor(t.z) }
    end
end
local function clText(v, n) return type(v) == "string" and (v:sub(1, n):gsub("[^\32-\126\160-\255]", "?")) or nil end

-- Herzschlag (UP mit role = "claude") und Antworten (CLD)
function Claude:receive(id, msg)
    if msg.t == "CLD" then return self:reply(id, msg) end
    local u = self.units[id]
    if not u then
        if self.count >= 4 then return false end
        u = { id = id }
        self.units[id] = u
        self.count = self.count + 1
        Kernel.log("INFO", "Claude #" .. id .. " verbunden")
        -- war bisher eine normale Schwarm-Turtle: dort austragen
        local sw = Fleets and Fleets.UP
        if sw and sw.store and sw.store[id] then
            sw.store[id] = nil
            sw.count = math.max(0, (sw.count or 1) - 1)
        end
    end
    u.seen, u.online = os.clock(), true
    u.status = clText(msg.status, 14) or "?"
    u.label = clText(msg.label, 12)
    u.v = clText(msg.v, 8)
    u.fuel = (clNum(msg.fuel) or msg.fuel == "unlimited") and msg.fuel or nil
    u.fuelMax = clNum(msg.fuelMax)
    u.inv = clNum(msg.inv)
    u.wpos = clCell(msg.wpos)
    u.wf = clNum(msg.wf) and (math.floor(msg.wf) % 4) or nil
    u.base = clCell(msg.base)
    u.prog, u.paused = clText(msg.prog, 12), msg.paused == true
    u.tools = {}
    if type(msg.tools) == "table" then
        for i = 1, math.min(#msg.tools, 12) do if type(msg.tools[i]) == "string" then u.tools[msg.tools[i]] = true end end
    end
    u.sword = msg.sword == true
    if type(msg.progs) == "table" and type(msg.progs.claude) == "string" then u.hash = msg.progs.claude:sub(1, 16) end
    local x = type(msg.ext) == "table" and msg.ext or nil
    if x then
        local e = { m = clText(x.m, 10), s = clText(x.s, 40), tg = clText(x.tg, 16), said = clText(x.said, 120),
                    saidT = clNum(x.saidT), mute = clNum(x.mute), kn = clNum(x.kn), kills = clNum(x.kills),
                    cv = clNum(x.cv), lv = clNum(x.lv), wp = clNum(x.wp), zn = clNum(x.zn), al = clText(x.al, 60),
                    torches = clNum(x.torches), spy = x.spy ~= false, scan = clText(x.scan, 40), near = {}, mobs = {},
                    sm = clText(x.sm, 4) }
        if type(x.b) == "table" then e.b = { d = clNum(x.b.d) or 0, n = clNum(x.b.n) or 0, k = clText(x.b.k, 8) } end
        for _, list in ipairs({ { "near", 6 }, { "mobs", 6 } }) do
            local src = x[list[1]]
            if type(src) == "table" then
                for i = 1, math.min(#src, list[2]) do
                    local p = src[i]
                    if type(p) == "table" and clCell(p) then
                        local c = clCell(p)
                        c.n, c.d = clText(p.n, 16) or "?", clNum(p.d)
                        e[list[1]][#e[list[1]] + 1] = c
                    end
                end
            end
        end
        if e.said and e.said ~= (u.ext and u.ext.said) and e.saidT ~= (u.ext and u.ext.saidT) then
            u.sayLog = u.sayLog or {}
            table.insert(u.sayLog, 1, { t = e.saidT, text = e.said })
            while #u.sayLog > 8 do table.remove(u.sayLog) end
        end
        if e.al and e.al ~= (u.ext and u.ext.al) then Kernel.notify("Claude: " .. e.al, colors.orange, "claude") end
        -- neue Einstellungen / neues Log: bei Bedarf nachladen
        if self.cfg and e.cv and e.cv ~= self.cfgV and self.sel == id then self.cfgT = -99 end
        if self.log and e.lv and e.lv ~= self.logV and self.sel == id then self.logT = -99 end
        u.ext = e
    else
        u.ext = nil
    end
    if not self.sel or not (self.units[self.sel] and self.units[self.sel].online) then self.sel = id end
    return Kernel.app == self or (REMOTE and Kernel.app.id == "home")
end

function Claude:reply(id, msg)
    if id ~= self.sel then return false end
    if msg.kind == "map" and type(msg.rows) == "table" then
        local rows = {}
        for i = 1, math.min(#msg.rows, 97) do rows[i] = clText(msg.rows[i], 97) or "" end
        local function cells(list, n)
            local out = {}
            for i = 1, math.min(type(list) == "table" and #list or 0, n) do
                local c = clCell(list[i])
                if c then out[#out + 1] = c end
            end
            return out
        end
        local zones = {}
        for i = 1, math.min(type(msg.zones) == "table" and #msg.zones or 0, 16) do
            local z = msg.zones[i]
            if type(z) == "table" and clNum(z.x1) and clNum(z.x2) and clNum(z.z1) and clNum(z.z2) then
                zones[#zones + 1] = { x1 = z.x1, x2 = z.x2, z1 = z.z1, z2 = z.z2 }
            end
        end
        self.map = { rows = rows, cx = clNum(msg.cx) or 0, cz = clNum(msg.cz) or 0, r = clNum(msg.r) or 0,
                     world = msg.world == true, wps = cells(msg.wps, 24), zones = zones, home = clCell(msg.home),
                     park = clCell(msg.park), center = clCell(msg.center), known = clNum(msg.known) }
        return Kernel.app == self or REMOTE
    elseif msg.kind == "log" then
        local function list(src, n, fn)
            local out = {}
            if type(src) ~= "table" then return out end
            for i = math.max(1, #src - n + 1), #src do
                local v = fn(src[i])
                if v then out[#out + 1] = v end
            end
            return out
        end
        self.log = {
            list = list(msg.list, 60, function(e) return type(e) == "table" and { t = clNum(e.t) or 0, k = clText(e.k, 8) or "", text = clText(e.text, 80) or "" } end),
            visits = list(msg.visits, 40, function(v) return type(v) == "table" and { n = clText(v.n, 16) or "?", a = clNum(v.a) or 0, d = clNum(v.d) } end),
            people = list(msg.people, 40, function(p) return type(p) == "table" and { n = clText(p.n, 16) or "?", first = clNum(p.first), last = clNum(p.last), visits = clNum(p.visits) or 0, here = p.here == true } end),
            kills = clNum(msg.kills) or 0,
        }
        self.logV = clNum(msg.v)
        return Kernel.app == self or REMOTE
    elseif msg.kind == "cfg" and type(msg.cfg) == "table" then
        self.cfg, self.cfgV = msg.cfg, clNum(msg.v)
        return Kernel.app == self or REMOTE
    end
    return false
end

function Claude:unit() return self.sel and self.units[self.sel] end
function Claude:owner()
    local o = Settings.get("owner")
    return (type(o) == "string" and o ~= "") and o or nil
end

-- An das laufende Programm (PMSG). Ohne Modem/Claude: Hinweis.
function Claude:send(args, id)
    id = id or self.sel
    local u = id and self.units[id]
    if not (u and Kernel.hw.modem) then
        Kernel.notify(Kernel.hw.modem and "Claude nicht in Reichweite" or "Kein Modem angeschlossen", colors.red)
        return false
    end
    Kernel.seq = Kernel.seq + 1
    Kernel.post(id, { t = "CMD", cmd = "PMSG", seq = Kernel.seq, args = args })
    return true
end
function Claude:cmd(text) return self:send({ op = "cmd", text = text, user = self:owner() }) end
function Claude:agentCmd(cmd, args)
    local u = self:unit()
    if not (u and Kernel.hw.modem) then return Kernel.notify("Claude nicht in Reichweite", colors.red) end
    Kernel.seq = Kernel.seq + 1
    Kernel.post(u.id, { t = "CMD", cmd = cmd, seq = Kernel.seq, args = args })
end

-- Neuigkeiten aus dem OS (Funde des Schwarms): Claude erzaehlt sie, wenn jemand da ist
function Claude:news(text)
    for id, u in pairs(self.units) do
        if u.online then self:send({ op = "news", text = tostring(text):sub(1, 100) }, id) end
    end
end

function Claude:tick()
    local now, changed = os.clock(), false
    for id, u in pairs(self.units) do
        if u.online and now - u.seen > CONFIG.offlineAfter then
            u.online, changed = false, true
            Kernel.log("WARN", "Claude #" .. id .. " offline")
        end
    end
    local u = self:unit()
    local open = Kernel.app == self or (REMOTE and Kernel.app.id == "home")
    if u and u.online and open then
        if self.view == "map" and now - self.mapT > 8 then self.mapT = now self:send({ op = "map", r = self:mapRadius() }) end
        if self.view == "log" and now - self.logT > 20 then self.logT = now self:send({ op = "log" }) end
        if (self.view == "modes" or not self.cfg) and now - self.cfgT > 30 then self.cfgT = now self:send({ op = "cfg" }) end
    end
    -- PC mit Chat Box: Claude sagen, dass Befehle von hier kommen (keine Doppelten)
    if not REMOTE and not READONLY and now - self.relayT > 300 and Extras.find("chat_box") then
        self.relayT = now
        for id, x in pairs(self.units) do if x.online then self:send({ op = "relay", on = true }, id) end end
    end
    return (changed or (open and now % 2 < 1)) and open
end

-- Chat-Weiterleitung (nur PC): "$claude ..." aus dem Spiel an Claude
function Claude:service()
    if REMOTE or READONLY then return end
    local start = os.clock()
    while true do
        local _, user, msg = os.pullEvent("chat")
        -- (die Chat Box liefert beim Start die letzte Nachricht noch einmal)
        if os.clock() - start > 3 and type(user) == "string" and type(msg) == "string" and msg:lower():find("^%s*@?claude") then
            for id, u in pairs(self.units) do
                if u.online then self:send({ op = "chat", user = user:sub(1, 16), msg = msg:sub(1, 120) }, id) end
            end
        end
    end
end

function Claude:onEnter(view)
    self.input, self.pick = nil, nil
    if view == "map" or view == "log" or view == "modes" or view == "status" then self.view = view end
    self.mapT, self.logT = -99, -99
end
function Claude:insert(text) return Input.insert(self, text) end
function Claude:key(action) return Input.key(self, action) end
function Claude:onChar(ch) Input.insert(self, ch) end
function Claude:onPaste(text) Input.insert(self, text) end
function Claude:onKey(code) Input.onKey(self, code) end
function Claude:onScroll(dir)
    if self.view == "map" then self.zoom = math.max(1, math.min(3, self.zoom + dir)) self.mapT = -99 return end
    local st = (self.view == "log") and self.logPage or ((self.view == "modes") and self.modePage or nil)
    if st then st.page = math.max(1, st.page + dir) end
end

-- ---------- Zeichnen ----------
local function clAgo(t)
    if not t then return "-" end
    local d = math.floor(os.epoch("utc") / 1000) - t
    if d < 60 then return "gerade" end
    if d < 3600 then return math.floor(d / 60) .. " min" end
    if d < 86400 then return math.floor(d / 3600) .. " h" end
    return math.floor(d / 86400) .. " d"
end

function Claude:tabs(top)
    local list = { { "status", "STATUS" }, { "map", "KARTE" }, { "modes", "MODI" }, { "log", "LOG" } }
    if Claude.compact() then table.insert(list, 2, { "pad", "STEUER" }) end
    local function open(v) self.view = v self.mapT, self.logT, self.cfgT, self.pick = -99, -99, -99, nil end
    if UI.narrow() then
        -- schmal (Pocket): < SEITE > zum Durchblaettern
        local w, idx = Kernel.w, 1
        for i, t in ipairs(list) do if t[1] == self.view then idx = i end end
        local function go(d) open(list[(idx - 1 + d) % #list + 1][1]) end
        UI.button{ x = 1, y = top, w = 4, h = 1, text = "\17", onClick = function() go(-1) end }
        UI.button{ x = 6, y = top, w = w - 10, h = 1, text = list[idx][2] .. " " .. idx .. "/" .. #list, style = "primary",
                   onClick = function() go(1) end }
        UI.button{ x = w - 3, y = top, w = 4, h = 1, text = "\16", onClick = function() go(1) end }
        return top + 2
    end
    local btns = {}
    for _, t in ipairs(list) do
        btns[#btns + 1] = { text = t[2], h = 1, style = (self.view == t[1]) and "primary" or nil, onClick = function() open(t[1]) end }
    end
    return UI.flow(btns, 2, top, Kernel.w - 1) + 1
end

-- kleine Bildschirme (PC ohne Monitor, Pocket): Steuerkreuz auf eigener Seite
function Claude.compact() return Kernel.h < 22 end

function Claude:draw()
    if self.input then return Input.draw(self) end
    local u = self:unit()
    if not u then return self:drawSetup() end
    if self.view == "pad" and not Claude.compact() then self.view = "status" end
    if self.view == "map" then return self:drawMap(u) end
    if self.view == "pad" then return self:drawPad(u) end
    if self.view == "modes" then return self:drawModes(u) end
    if self.view == "log" then return self:drawLog(u) end
    return self:drawStatus(u)
end

function Claude:header(u, sub)
    local narrow = UI.narrow()
    local run = u.prog == "claude" and not u.paused
    local acts = {}
    if not u.online then
        acts[1] = { text = "OFFLINE", style = "ghost", fg = colors.red }
    elseif run then
        acts[1] = { text = "STOP", style = "danger", confirm = "claude-stop", onClick = function() self:agentCmd("STOP") end }
    else
        acts[1] = { text = "START", style = "primary", onClick = function()
            self:agentCmd("RUN", { name = "claude", resume = true, owner = self:owner() })
        end }
    end
    -- neuer Agent im OS (nur PC): einzeln an Claude (Claude laeuft danach weiter)
    if not READONLY and u.online and TurtleProgs and TurtleProgs.get and Fleets.UP then
        local agent = TurtleProgs.get("agent")
        if agent and u.v and agent.ver and verLess(u.v, agent.ver) then
            table.insert(acts, 1, { text = "AGENT " .. agent.ver, style = "accent", onClick = function()
                Fleets.UP:pushCode(u.id, "AGENT", "agent", agent)
                Kernel.notify("Claude: Agent v" .. agent.ver .. " uebertragen", colors.lime, "claude")
            end })
        end
    end
    -- neue Programm-Fassung im OS (nur PC): einspielen
    if not READONLY and u.online and TurtleProgs and TurtleProgs.get then
        local prog = TurtleProgs.get("claude")
        if prog and u.hash and prog.hash ~= u.hash and Fleets.UP then
            table.insert(acts, 1, { text = (UI.bh() == 1) and "UPDATE" or "PROGRAMM-UPDATE", style = "accent", onClick = function()
                self:agentCmd("STOP")
                Fleets.UP:pushCode(u.id, "PROG", "claude", prog)
                self:agentCmd("RUN", { name = "claude", hash = prog.hash, resume = true, owner = self:owner() })
                u.hash = prog.hash
                Kernel.notify("Claude: neues Programm uebertragen", colors.lime, "claude")
            end })
        end
    end
    return UI.header("CLAUDE", sub, acts)
end

-- Ausruestung, die Claude benutzt (Name im Herzschlag, Anzeige)
local CL_GEAR = { { "scanner", "Geo Scanner" }, { "player", "Player Detector" }, { "env", "Env. Detector" },
                  { "chat", "Chat Box" }, { "compass", "Kompass" }, { "speaker", "Speaker" }, { "workbench", "Werkbank" } }

function Claude:drawStatus(u)
    local w, h, bh, narrow = Kernel.w, Kernel.h, UI.bh(), UI.narrow()
    local e = u.ext or {}
    local run = u.prog == "claude" and not u.paused
    local mode = run and (CL_MODES[e.m or ""] or tostring(e.m or "?"):upper()) or (u.paused and "ANGEHALTEN" or "PROGRAMM AUS")
    local compact = Claude.compact()
    local top = self:header(u, (not narrow and not compact) and ("#" .. u.id .. (u.label and (" " .. u.label) or "") .. (u.v and ("  Agent " .. u.v) or "")) or nil)
    top = self:tabs(top)
    local x0 = narrow and 1 or 2
    local y = top
    -- Modus, daneben/darunter was Claude gerade tut
    UI.text(x0, y, "\7 ", run and colors.lime or colors.orange)
    UI.text(x0 + 2, y, mode, colors.white)
    local doing = (run and (e.s or "") or (u.status or "")) .. (e.mute and "  (stumm)" or "")
    if compact and x0 + 4 + #mode + #doing <= w then
        UI.text(x0 + 4 + #mode, y, doing, colors.lightGray)
        y = y + 1
    else
        y = y + 1
        UI.text(x0 + 2, y, doing:sub(1, w - x0 - 3), colors.lightGray)
        y = y + 1
    end
    -- Tank
    local fuel = u.fuel
    if type(fuel) == "number" then
        local bw = math.min(narrow and (w - 12) or 30, w - 14)
        UI.text(x0, y, "TANK", colors.lightGray)
        UI.bar(x0 + 6, y, bw, fuel / 5000, (fuel < 400) and colors.red or colors.lime)
        UI.text(x0 + 7 + bw, y, tostring(fuel), (fuel < 400) and colors.red or colors.white)
        y = y + 1
    end
    local where = u.wpos and (u.wpos.x .. " " .. u.wpos.y .. " " .. u.wpos.z) or "?"
    local info = "BEI " .. where
    if not narrow and not compact then
        info = info .. "   KARTE " .. (e.kn or 0) .. " Felder   MONSTER " .. (e.kills or 0)
        if e.torches then info = info .. "   FACKELN " .. e.torches end
    end
    UI.text(x0, y, info:sub(1, w - x0), colors.lightGray)
    y = y + 1
    if e.b and e.b.n and e.b.n > 0 then
        UI.text(x0, y, ("BAU " .. (e.b.k or "") .. " " .. e.b.d .. "/" .. e.b.n):sub(1, w - x0), colors.yellow)
        y = y + 1
    end
    if run and e.al and e.al:find("^festgefahren") then
        UI.text(x0, y, ("! " .. e.al):sub(1, w - x0), colors.orange)
        y = y + 1
    end
    if e.spy == false then
        local t = (e.sm == "box") and "playerSpy aus: Claude ortet langsamer" or "playerSpy aus: Spieler nur in der Naehe"
        UI.text(x0, y, t:sub(1, w - x0), (e.sm == "box") and colors.lightGray or colors.orange)
        y = y + 1
    end
    if e.scan and e.scan ~= "" then UI.text(x0, y, ("Scanner: " .. e.scan):sub(1, w - x0), colors.orange) y = y + 1 end
    -- fehlende Ausruestung (Claude laeuft trotzdem, nur ohne das)
    if u.tools and run then
        local miss = {}
        if not u.sword then miss[1] = "Schwert" end
        for _, g in ipairs(CL_GEAR) do if not u.tools[g[1]] then miss[#miss + 1] = g[2] end end
        if #miss > 0 then UI.text(x0, y, ("FEHLT: " .. table.concat(miss, ", ")):sub(1, w - x0), colors.orange) y = y + 1 end
    end
    -- Wer ist in der Naehe (antippen = folgen)
    if #(e.near or {}) > 0 then
        -- eine Zeile; was nicht passt, steht als "+n" am Ende
        UI.text(x0, y, "NAH:", colors.lightGray)
        local x, n = x0 + 5, #e.near
        for i, p in ipairs(e.near) do
            local label = p.n .. (p.d and (" " .. p.d) or "")
            local room = w - ((i < n) and 3 or 0)
            if x + #label + 1 > room then
                UI.text(x, y, "+" .. (n - i + 1), colors.lightGray)
                break
            end
            x = UI.button{ x = x, y = y, h = 1, text = label, onClick = function()
                self:send({ op = "mode", mode = "follow", target = p.n })
            end } + 1
        end
        y = y + 2
    end
    -- Befehle
    local acts = {
        { text = "KOMM", onClick = function() self:come() end },
        { text = "FOLGEN", onClick = function() self:send({ op = "mode", mode = "follow", target = self:owner() }) end },
        { text = "BLEIB", onClick = function() self:send({ op = "mode", mode = "stay" }) end },
        { text = "FREI", onClick = function() self:send({ op = "mode", mode = "idle" }) end },
        { text = "HEIM", onClick = function() self:send({ op = "mode", mode = "home" }) end },
        { text = "WACHE", onClick = function() self:send({ op = "mode", mode = "guard" }) end },
        { text = "PATROUILLE", onClick = function() self:send({ op = "mode", mode = "patrol" }) end },
        { text = "SAG", onClick = function()
            Input.open(self, { title = "Claude sagt:", maxLen = 100, onOk = function(t)
                if t:find("%S") then self:send({ op = "say", text = t }) end
            end })
        end },
        { text = e.mute and "SPRICH" or "RUHE", onClick = function() self:cmd(e.mute and "sprich" or "ruhe") end },
    }
    -- Zuletzt gesagt (nur so viele Zeilen, dass die Befehle darunter noch passen)
    local gap = compact and 0 or 1
    local room = h - y - gap - UI.flowHeight(acts, x0, w - 1)
    if u.sayLog and #u.sayLog > 0 and room >= 1 then
        -- klein: der letzte Satz auf bis zu 2 Zeilen, gross: die letzten 3 je 1 Zeile
        local small = narrow or compact
        local width = w - x0
        for i = 1, math.min(small and 1 or 3, #u.sayLog, room) do
            local lines = UI.wrap("\"" .. u.sayLog[i].text .. "\"", width)
            local n = math.min(small and 2 or 1, room - i + 1)
            for j = 1, math.min(n, #lines) do
                local t = lines[j]
                if j == n and #lines > n then t = t:sub(1, width - 2) .. ".." end
                UI.text(x0, y, t:sub(1, width), (i == 1) and colors.white or colors.lightGray)
                y = y + 1
            end
        end
    end
    y = y + gap
    if y + UI.flowHeight(acts, x0, w - 1) <= h then
        y = UI.flow(acts, x0, y, w - 1) + 1
    end
    if not compact and y + bh <= h - 1 then self:padRow(x0, y) end
end

-- Steuerkreuz (nicht abbauen: Claude faehrt nur in freie Felder)
function Claude:padRow(x0, y)
    local w, narrow = Kernel.w, UI.narrow()
    local pad = { { "\24", "vor" }, { "\25", "zurueck" }, { "\27", "links" }, { "\26", "rechts" }, { "HOCH", "hoch" }, { "RUNTER", "runter" } }
    local list = {}
    for _, p in ipairs(pad) do
        list[#list + 1] = { text = p[1], w = (#p[1] == 1) and 3 or nil, onClick = function() self:send({ op = "move", dir = p[2] }) end }
    end
    if not narrow then UI.text(x0, y, "STEUERN", colors.lightGray) end
    return UI.flow(list, narrow and x0 or (x0 + 8), y, w - 1)
end

function Claude:drawPad(u)
    local w, narrow = Kernel.w, UI.narrow()
    local top = self:header(u, nil)
    top = self:tabs(top)
    local x0 = narrow and 1 or 2
    UI.text(x0, top, ("Vor/zurueck/links/rechts aus Claudes Sicht."):sub(1, w - x0), colors.lightGray)
    local y = self:padRow(x0, top + 2) + 1
    local more = {
        { text = "HIERHER", onClick = function() self:come() end },
        { text = "PARKPLATZ = HIER", onClick = function() self:send({ op = "park", here = true }) end },
        { text = "CRAFTEN", onClick = function() self:send({ op = "craft", n = 16 }) end },
    }
    UI.flow(more, x0, y + 1, w - 1)
end

-- KOMM: Fernbedienung mit GPS -> dorthin; sonst zum eigenen Spielernamen
function Claude:come()
    if REMOTE then
        local here = Geo.here()
        if here then return self:send({ op = "goto", x = here.x, y = here.y + 1, z = here.z }) end
    end
    if not self:owner() then
        return Kernel.notify(REMOTE and "Kein GPS: Spielername in MODI > FREI eintragen" or "Besitzer fehlt: INFO > EINSTELLUNGEN", colors.orange)
    end
    self:send({ op = "mode", mode = "come", target = self:owner() })
end

-- ---------- Karte ----------
local function clRot(up, x, z)
    if up == 1 then return z, -x elseif up == 2 then return -x, -z elseif up == 3 then return -z, x end
    return x, z
end
local function clUnrot(up, r, d)
    if up == 1 then return -d, r elseif up == 2 then return -r, -d elseif up == 3 then return d, -r end
    return r, d
end
local CL_ARROWS = { [0] = "\24", [1] = "\26", [2] = "\25", [3] = "\27" }
local CL_TILE = { [" "] = { " ", "0", "f" }, ["."] = { " ", "0", "c" }, ["#"] = { " ", "0", "8" },
                  ["~"] = { "\140", "3", "b" }, ["!"] = { "!", "0", "e" } }

function Claude:mapRadius()
    local w, h = Kernel.w, Kernel.h
    return math.min(48, math.ceil(math.max(w, h * 1.5) / 2 * self.zoom) + 1)
end

function Claude:drawMap(u)
    local w, h, bh, narrow = Kernel.w, Kernel.h, UI.bh(), UI.narrow()
    local top = self:header(u, nil)
    top = self:tabs(top)
    local m = self.map
    local legendY = h - 1
    local mx, my, mw, mh = 1, top, w, legendY - top
    if not m then
        UI.empty(top + 2, "Karte wird geladen ...", "Claude schickt, was er schon kennt. Er lernt die Basis mit dem Geo Scanner.")
        return
    end
    local up = tonumber(Settings.get("mapUp")) or 0
    if up ~= 1 and up ~= 2 and up ~= 3 then up = 0 end
    local scale = self.zoom
    local cx, cz = m.cx, m.cz
    if u.wpos then cx, cz = u.wpos.x, u.wpos.z end
    local ox, oy = mx + math.floor(mw / 2), my + math.floor(mh / 2)
    local function world(c, r)
        local dx, dz = clUnrot(up, (c - ox) * scale, (r - oy) * scale * 1.5)
        return math.floor(cx + dx + 0.5), math.floor(cz + dz + 0.5)
    end
    local function place(x, z)
        local r, d = clRot(up, x - cx, z - cz)
        return ox + math.floor(r / scale + 0.5), oy + math.floor(d / (scale * 1.5) + 0.5)
    end
    local function tileAt(x, z)
        local row = m.rows[z - (m.cz - m.r) + 1]
        if not row then return " " end
        local ch = row:sub(x - (m.cx - m.r) + 1, x - (m.cx - m.r) + 1)
        return (ch ~= "") and ch or " "
    end
    local s = Kernel.screen
    for r = my, my + mh - 1 do
        local chs, fgs, bgs = {}, {}, {}
        for c = mx, mx + mw - 1 do
            local x, z = world(c, r)
            local t = CL_TILE[tileAt(x, z)] or CL_TILE[" "]
            chs[#chs + 1], fgs[#fgs + 1], bgs[#bgs + 1] = t[1], t[2], t[3]
        end
        s.setCursorPos(mx, r)
        s.blit(table.concat(chs), table.concat(fgs), table.concat(bgs))
    end
    local function mark(p, ch, fg, bg)
        if not p then return end
        local c, r = place(p.x, p.z)
        if c >= mx and c < mx + mw and r >= my and r < my + mh then UI.text(c, r, ch, fg, bg or colors.black) return c, r end
    end
    for _, zn in ipairs(m.zones or {}) do
        for _, p in ipairs({ { x = zn.x1, z = zn.z1 }, { x = zn.x2, z = zn.z1 }, { x = zn.x1, z = zn.z2 }, { x = zn.x2, z = zn.z2 } }) do
            mark(p, "X", colors.orange)
        end
    end
    for i, p in ipairs(m.wps or {}) do mark(p, (i <= 9) and tostring(i) or "+", colors.black, colors.yellow) end
    mark(m.home, "H", colors.lightBlue)
    if m.park and not (m.home and m.park.x == m.home.x and m.park.z == m.home.z) then mark(m.park, "P", colors.lightBlue) end
    mark(m.center or (not REMOTE and Geo.here()) or nil, "\4", colors.white)
    for _, mob in ipairs((u.ext and u.ext.mobs) or {}) do mark(mob, "x", colors.red) end
    for _, p in ipairs((u.ext and u.ext.near) or {}) do
        local c, r = mark(p, "@", colors.yellow)
        if c and c + #p.n < mx + mw then UI.text(c + 1, r, p.n, colors.yellow) end
    end
    if REMOTE then mark(Geo.here(), "\7", colors.white) end
    if u.wpos then
        local c, r = mark(u.wpos, u.wf and CL_ARROWS[(u.wf - up) % 4] or "C", colors.black, colors.lime)
        if c and c + 7 < mx + mw then UI.text(c + 1, r, "Claude", colors.lime) end
    end
    UI.text(mx + mw - 3, my, "N" .. CL_ARROWS[(0 - up) % 4], colors.lightGray)
    -- Antippen: Menue fuer diese Stelle
    UI.hit(mx, my, mw, mh, function(c, r)
        local x, z = world(c, r)
        local y = (u.wpos and u.wpos.y) or 0
        self.pick = { x = x, y = y, z = z, c = c, r = r }
    end)
    -- Legende: unterste Zeile neben den Zoom-Knoepfen nimmt den Rest auf
    local lx, ly = 1, legendY
    if not narrow then UI.text(lx, ly, "1 Zeichen = " .. scale .. " Bl.", colors.lightGray) lx = lx + 18 end
    for _, l in ipairs({ { " Boden ", colors.brown }, { " Wand ", colors.lightGray }, { " Wasser ", colors.blue }, { " Create ", colors.red } }) do
        if ly == legendY and lx + #l[1] - 1 > w then lx, ly = 1, h end
        if ly == legendY or lx + #l[1] - 1 <= w - 8 then
            UI.text(lx, ly, l[1], (l[2] == colors.lightGray) and colors.black or colors.white, l[2])
            lx = lx + #l[1] + 1
        end
    end
    -- Aktionen unten rechts: Zoom, Punkte, Zonen
    local zb = { { text = "-", w = 3, h = 1, onClick = function() self:onScroll(1) end },
                 { text = "+", w = 3, h = 1, onClick = function() self:onScroll(-1) end } }
    UI.buttonsRight(zb, h, w)
    if self.pick then self:drawPick(u) end
end

-- Menue fuer eine angetippte Stelle der Karte
function Claude:drawPick(u)
    local p = self.pick
    local w, h, bh = Kernel.w, Kernel.h, UI.bh()
    local cw = math.min(w, 30)
    local items = {
        { text = "HIERHIN FLIEGEN", fn = function() self:send({ op = "goto", x = p.x, y = p.y, z = p.z }) end },
        { text = "WEGPUNKT", fn = function() self:send({ op = "wp", action = "add", x = p.x, y = p.y, z = p.z }) self.mapT = -99 end },
        { text = "PARKPLATZ", fn = function() self:send({ op = "park", x = p.x, y = p.y, z = p.z }) self.mapT = -99 end },
        { text = self.zoneA and "ZONE: 2. ECKE" or "SPERRZONE: 1. ECKE", fn = function()
            if self.zoneA then
                self:send({ op = "zone", action = "add", a = self.zoneA, b = { x = p.x, y = p.y, z = p.z } })
                self.zoneA, self.mapT = nil, -99
            else
                self.zoneA = { x = p.x, y = p.y, z = p.z }
                Kernel.notify("Jetzt die zweite Ecke der Sperrzone antippen", colors.lightGray)
            end
        end },
    }
    local ch = #items * bh + 3
    local x0 = math.max(1, math.min(w - cw + 1, p.c - math.floor(cw / 2)))
    local y0 = math.max(2, math.min(h - ch, p.r - math.floor(ch / 2)))
    UI.hit(1, 1, w, Kernel.H, function() self.pick = nil end)
    UI.card(x0, y0, cw, ch)
    UI.text(x0 + 1, y0, (p.x .. " " .. p.z):sub(1, cw - 6), colors.lightGray)
    UI.button{ x = x0 + cw - 4, y = y0, w = 3, h = 1, text = "X", style = "ghost", onClick = function() self.pick = nil end }
    for i, it in ipairs(items) do
        UI.button{ x = x0 + 1, y = y0 + 1 + (i - 1) * bh + ((bh == 1) and 1 or 0), w = cw - 2, text = it.text,
                   onClick = function() self.pick = nil it.fn() end }
    end
    UI.surface = colors.black
end

-- ---------- Modi (Einstellungen von Claude) ----------
Claude.GROUPS = { "FREI", "PATROUILLE", "WACHE", "KAMPF", "CRAFTEN", "STIMME", "SICHERHEIT" }
function Claude:setRows(c)
    local rows = {}
    local function opts(key, list)
        local out = {}
        for _, o in ipairs(list) do
            out[#out + 1] = { text = o[1], style = (c[key] == o[2]) and "primary" or nil, onClick = function()
                c[key] = o[2]
                self:send({ op = "set", key = key, value = o[2] })
            end }
        end
        return out
    end
    local function onoff(key) return opts(key, { { "AN", true }, { "AUS", false } }) end
    local function row(g, label, value, buttons, color) rows[#rows + 1] = { label, value, color, buttons, g = g } end
    local u = self:unit()
    local e = (u and u.ext) or {}
    row("FREI", "Wenn frei", ({ park = "parken", hover = "schweben und die Basis lernen", guard = "Wache am Parkplatz" })[c.idle] or "?",
        opts("idle", { { "PARKEN", "park" }, { "SCHWEBEN", "hover" }, { "WACHE", "guard" } }))
    row("FREI", "Schweb-Radius", tostring(c.hoverR) .. " Bloecke", opts("hoverR", { { "8", 8 }, { "12", 12 }, { "20", 20 }, { "32", 32 } }))
    row("FREI", "Nachts", c.nightHome and "zum Parkplatz" or "wie am Tag", onoff("nightHome"))
    row("FREI", "Parkplatz", c.park and "eigener (Karte)" or "Basis (Spind)", {
        { text = "BASIS", onClick = function() c.park = false self:send({ op = "set", key = "park", value = false }) end },
        { text = "HIER", onClick = function() self:send({ op = "park", here = true }) self.cfgT = -99 end } })
    row("PATROUILLE", "Wegpunkte", tostring(e.wp or 0) .. " (Karte antippen oder $claude punkt)", {
        { text = "LOESCHEN", style = "danger", confirm = "cl-wp", onClick = function() self:send({ op = "wp", action = "clear" }) self.mapT = -99 end } })
    row("PATROUILLE", "Pause je Punkt", tostring(c.patrolWait) .. " s", opts("patrolWait", { { "0", 0 }, { "5", 5 }, { "15", 15 }, { "30", 30 } }))
    row("PATROUILLE", "Starten", "", { { text = "PATROUILLE", style = "primary", onClick = function() self:send({ op = "mode", mode = "patrol" }) end } })
    row("WACHE", "Radius", tostring(c.guardR) .. " Bloecke um die Wache", opts("guardR", { { "6", 6 }, { "10", 10 }, { "16", 16 } }))
    row("WACHE", "Wache hier", "", { { text = "WACHE", style = "primary", onClick = function() self:send({ op = "mode", mode = "guard" }) end } })
    row("KAMPF", "Monster angreifen", c.mobs and "ja (Diamantschwert)" or "nein", onoff("mobs"))
    row("KAMPF", "Creeper", c.creepers and "auch" or "in Ruhe lassen", onoff("creepers"))
    row("KAMPF", "Folge-Abstand", tostring(c.followDist) .. " Bloecke", opts("followDist", { { "2", 2 }, { "3", 3 }, { "5", 5 } }))
    row("CRAFTEN", "Fackeln setzen", c.torches and "selbst, wenn es dunkel ist" or "nur anbieten", onoff("torches"))
    row("CRAFTEN", "Fackel-Vorrat", tostring(c.torchStock) .. (e.torches and ("  (hat " .. e.torches .. ")") or ""),
        opts("torchStock", { { "0", 0 }, { "16", 16 }, { "32", 32 }, { "64", 64 } }))
    row("CRAFTEN", "Selbst craften", c.autoCraft and "ja, im Leerlauf am Spind" or "nur auf Befehl", onoff("autoCraft"))
    row("CRAFTEN", "Spind", ({ down = "Kiste unter der Basis", up = "Kiste ueber der Basis", back = "Kiste hinter der Basis" })[c.locker] or "?",
        opts("locker", { { "UNTEN", "down" }, { "OBEN", "up" }, { "HINTEN", "back" } }))
    row("CRAFTEN", "Jetzt", "16 Fackeln aus Kohle + Stoecken/Brettern", { { text = "CRAFTEN", style = "primary", onClick = function() self:send({ op = "craft", n = 16 }) end } })
    row("STIMME", "Gespraechig", ({ [0] = "still", "wenig", "normal", "viel" })[c.talk] or "?",
        opts("talk", { { "STILL", 0 }, { "WENIG", 1 }, { "NORMAL", 2 }, { "VIEL", 3 } }))
    row("STIMME", "Begruessen", c.greet and "ja" or "nein", onoff("greet"))
    row("STIMME", "Stups", c.poke and ("selten: " .. table.concat(c.pokeTargets or {}, ", ")) or "aus", onoff("poke"))
    row("STIMME", "Stups-Chance", "1 von " .. tostring(c.pokeOdds) .. " Begegnungen (hoechstens 1x am Tag)",
        opts("pokeOdds", { { "1/20", 20 }, { "1/50", 50 }, { "1/150", 150 } }))
    row("SICHERHEIT", "Leine", tostring(c.leash) .. " Bloecke um " .. (c.center and "den PC" or "die Basis"),
        opts("leash", { { "32", 32 }, { "64", 64 }, { "100", 100 } }))
    if not REMOTE then
        local here = Geo.here()
        row("SICHERHEIT", "Mitte der Leine", c.center and "PC" or "Basis von Claude", {
            { text = "PC", disabled = not here, onClick = function() self:send({ op = "center", x = here.x, y = here.y, z = here.z }) self.cfgT = -99 end },
            { text = "BASIS", onClick = function() self:send({ op = "set", key = "center", value = false }) end } })
    end
    row("SICHERHEIT", "Create-Abstand", tostring(c.createGap) .. " Bloecke (Werkstationen erlaubt)", opts("createGap", { { "2", 2 }, { "3", 3 }, { "4", 4 } }))
    row("SICHERHEIT", "Sperrzonen", tostring(e.zn or 0) .. " (KARTE antippen)", {
        { text = "LOESCHEN", style = "danger", confirm = "cl-zn", onClick = function() self:send({ op = "zone", action = "clear" }) self.mapT = -99 end } })
    row("SICHERHEIT", "Karte", tostring(e.kn or 0) .. " bekannte Felder", {
        { text = "VERGESSEN", style = "danger", confirm = "cl-forget", onClick = function() self:send({ op = "forget" }) self.mapT = -99 end } })
    if REMOTE then
        row("FREI", "Dein Spielername", self:owner() or "fehlt (fuer KOMM ohne GPS und FOLGEN)", {
            { text = "AENDERN", onClick = function()
                Input.open(self, { title = "Dein Spielername:", text = self:owner() or "", maxLen = 16, filter = "[^%w_]", onOk = function(t)
                    Settings.set("owner", t)
                end })
            end } }, self:owner() and colors.lightGray or colors.orange)
    end
    return rows
end

function Claude:drawModes(u)
    local w, narrow = Kernel.w, UI.narrow()
    local top = self:header(u, nil)
    top = self:tabs(top)
    local c = self.cfg
    if not c then UI.empty(top + 2, "Einstellungen werden geladen ...", "Claude muss eingeschaltet und in Funkreichweite sein.") return end
    -- Gruppen
    local need = -1
    for _, g in ipairs(Claude.GROUPS) do need = need + #g + 3 end
    if need <= w - 2 then
        local list = {}
        for _, g in ipairs(Claude.GROUPS) do
            list[#list + 1] = { text = g, h = 1, style = (g == self.group) and "primary" or nil, onClick = function() self.group, self.modePage.page = g, 1 end }
        end
        top = UI.flow(list, narrow and 1 or 2, top, w - 1) + 1
    else
        UI.button{ x = 1, y = top, w = w, h = 1, text = self.group .. " \16", onClick = function()
            for i, g in ipairs(Claude.GROUPS) do
                if g == self.group then self.group = Claude.GROUPS[i % #Claude.GROUPS + 1] break end
            end
            self.modePage.page = 1
        end }
        top = top + 2
    end
    local rows = {}
    for _, r in ipairs(self:setRows(c)) do if r.g == self.group then rows[#rows + 1] = r end end
    UI.settingsList(self.modePage, rows, top)
end

-- ---------- Log: Besucher und Ereignisse ----------
function Claude:drawLog(u)
    local w, narrow = Kernel.w, UI.narrow()
    local top = self:header(u, nil)
    top = self:tabs(top)
    local log = self.log
    if not log then UI.empty(top + 2, "Log wird geladen ...") return end
    local items = {}
    for i = #log.visits, 1, -1 do
        local v = log.visits[i]
        local dur = v.d and (math.max(1, math.floor((v.d - v.a) / 60)) .. " min") or "noch da"
        items[#items + 1] = { t = v.a, text = v.n .. "  (" .. dur .. ")", color = v.d and colors.white or colors.lime, kind = "BESUCH" }
    end
    for i = #log.list, 1, -1 do
        local e = log.list[i]
        if e.k ~= "sagt" or self.showSaid then
            items[#items + 1] = { t = e.t, text = e.text, color = (e.k == "kampf") and colors.red or ((e.k == "sagt") and colors.lightGray or colors.white), kind = e.k:upper() }
        end
    end
    table.sort(items, function(a, b) return a.t > b.t end)
    local bw = narrow and 7 or 10
    local head = narrow and ("SPIELER " .. #log.people .. "  MOBS " .. log.kills) or ("SPIELER " .. #log.people .. "  MONSTER " .. log.kills)
    UI.text(narrow and 1 or 2, top, head:sub(1, w - bw - 2), colors.lightGray)
    UI.button{ x = w - bw, y = top, w = bw, h = 1, text = narrow and (self.showSaid and "-SAGT" or "+SAGT") or (self.showSaid and "OHNE SAGT" or "MIT SAGT"),
               style = "ghost", onClick = function() self.showSaid = not self.showSaid end }
    UI.list(self.logPage, items, top + 2, 1, function(it, y)
        local x0 = narrow and 1 or 2
        local when = clAgo(it.t)
        UI.text(x0, y, when, colors.lightGray)
        local tx = x0 + 7
        if not narrow then UI.text(tx, y, it.kind:sub(1, 7), colors.orange) tx = tx + 8 end
        UI.text(tx, y, it.text:sub(1, w - tx), it.color)
    end)
end

-- ---------- Einrichten: noch kein Claude ----------
function Claude:drawSetup()
    local w, h, bh, narrow = Kernel.w, Kernel.h, UI.bh(), UI.narrow()
    local top = UI.header("CLAUDE", not narrow and "Begleit-Droide" or nil)
    if REMOTE or READONLY then
        UI.empty(top + 2, "Kein Claude in Reichweite",
                 "Claude wird am PC eingerichtet (CLAUDE > Turtle waehlen). Danach meldet er sich hier von selbst.")
        return
    end
    local sw = Fleets and Fleets.UP
    local list = {}
    if sw then
        for id, e in pairs(sw.store) do if e.online then list[#list + 1] = { id = id, e = e } end end
        table.sort(list, function(a, b) return a.id < b.id end)
    end
    local y = top
    local intro = UI.wrap("Eine Turtle wird zu Claude: Agent 5.4, Ender Modem, Diamantschwert. Im Inventar Chat Box, Player Detector, " ..
                          "Environment Detector, Geo Scanner, Kompass, Speaker, Chunky, Werkbank und Kohle. Spind: Kiste unter der Basis.", w - 4)
    for _, l in ipairs(intro) do
        if y < h - 6 then UI.text(2, y, l, colors.lightGray) y = y + 1 end
    end
    y = y + 1
    if #list == 0 then
        UI.text(2, y, "Keine Turtle online (Basis mit GPS setzen, TURTLE-DISK).", colors.orange)
        return
    end
    UI.list(self.setupPage, list, y, bh + 1, function(it, ry)
        local tx, xr = UI.rowCard(ry, bh)
        local e = it.e
        local old = verLess(e.v, "5.4")
        local need = {}
        for _, t in ipairs({ "chat", "player", "env", "scanner" }) do if not (e.toolSet and e.toolSet[t]) then need[#need + 1] = t end end
        local bx = UI.buttonsRight({ { text = narrow and "CLAUDE" or "ZU CLAUDE MACHEN", style = "primary", confirm = "cl-make-" .. it.id,
            onClick = function()
                local text, failed = sw:runProgram(it.id, "claude", { owner = self:owner() }, true)
                Kernel.notify("#" .. it.id .. ": " .. tostring(text), failed and colors.red or colors.lime)
            end } }, ry, xr)
        local name = "#" .. it.id .. " " .. (sw:nameOf(it.id, e) or "")
        UI.text(tx, ry, name:sub(1, bx - tx - 1), colors.white)
        if not narrow then
            local hint = old and "Agent zu alt: erst SCHWARM > UPDATE" or ((#need > 0) and ("fehlt: " .. table.concat(need, ", ")) or ("Agent " .. tostring(e.v)))
            UI.text(tx + 14, ry, hint:sub(1, math.max(0, bx - tx - 16)), (old or #need > 0) and colors.orange or colors.lightGray)
        end
    end)
end

Apps.register(Claude)
Kernel.claude = Claude

-- ======================================================================
-- [8] DATEN
-- ======================================================================
local function treeSize(path)
    if not fs.isDir(path) then return fs.getSize(path) end
    local sum = 0
    for _, name in ipairs(fs.list(path)) do sum = sum + treeSize(fs.combine(path, name)) end
    return sum
end

-- Ersetzt dst durch eine Kopie von src. Die alte Version wird erst
-- geloescht, wenn die neue vollstaendig kopiert ist.
local function replaceTree(src, dst)
    local need = treeSize(src)
    local free = fs.getFreeSpace(fs.getDir(dst))
    if type(free) == "number" and need > free then
        return false, "Zu wenig Platz (" .. fmtSize(need - free) .. " fehlen)"
    end
    local tmp = dst .. ".neu"
    if fs.exists(tmp) then fs.delete(tmp) end
    local ok, err = pcall(fs.copy, src, tmp)
    if not ok then
        pcall(fs.delete, tmp)
        Kernel.log("FEHLER", "Kopieren " .. src .. ": " .. tostring(err))
        return false, "Kopieren fehlgeschlagen"
    end
    if fs.exists(dst) then fs.delete(dst) end
    fs.move(tmp, dst)
    return true, need
end

local Data = { id = "data", title = "DATEN", order = 5, backups = {},
               view = "disk", progPage = { page = 1 }, backupPage = { page = 1 } }

function Data:refresh()
    self.backups = {}
    for _, name in ipairs(fs.list(CONFIG.backupDir)) do
        local path = fs.combine(CONFIG.backupDir, name)
        self.backups[#self.backups + 1] = { name = name, size = treeSize(path) }
    end
    table.sort(self.backups, function(a, b) return a.name < b.name end)
end

function Data:onEnter() self:refresh() end

-- Liefert die erste eingelegte Diskette (nil, wenn keine Daten-Disk da ist).
function Data:findDisk()
    local other = false
    for _, drive in ipairs(Kernel.hw.drives) do
        if disk.isPresent(drive) then
            if disk.hasData(drive) then
                return { drive = drive, path = disk.getMountPath(drive),
                         label = disk.getLabel(drive), id = disk.getID(drive) }
            end
            other = true
        end
    end
    return nil, other
end

function Data:backupDisk(d)
    local label = d.label and d.label:gsub("[^%w_%-]", "_") or ""
    local name = (label ~= "" and (label .. "_") or "disk_") .. tostring(d.id or 0)
    local ok, res = replaceTree(d.path, fs.combine(CONFIG.backupDir, name))
    self:refresh()
    if ok then return true, "Gesichert: " .. name .. " (" .. fmtSize(res) .. ")" end
    return false, res
end

-- Sichert alle Notizen und das OS selbst (startup.lua) auf die Diskette.
function Data:pcToDisk(d)
    local ok, res = replaceTree(CONFIG.notesDir, fs.combine(d.path, CONFIG.diskNotes))
    if not ok then return false, res end
    local msg = #Notes.list() .. " Notizen"
    if fs.exists("/startup.lua") then
        ok, res = replaceTree("/startup.lua", fs.combine(d.path, CONFIG.diskOS))
        if not ok then return false, msg .. " kopiert, OS nicht: " .. res end
        msg = msg .. " + OS"
    end
    return true, msg .. " auf Disk gesichert"
end

function Data:notesFromDisk(d)
    local src, n = fs.combine(d.path, CONFIG.diskNotes), 0
    for _, name in ipairs(fs.list(src)) do
        local from, to = fs.combine(src, name), Notes.path(name)
        if not fs.isDir(from) then
            if fs.exists(to) then fs.delete(to) end
            if not pcall(fs.copy, from, to) then return false, "Abbruch nach " .. n .. " Notizen (Speicher voll?)" end
            n = n + 1
        end
    end
    return true, n .. " Notizen von Disk geladen"
end

-- Dateien direkt auf der Diskette (ohne Ordner): das sind ihre Programme.
function Data:programs(d)
    local out = {}
    for _, name in ipairs(fs.list(d.path)) do
        if not fs.isDir(fs.combine(d.path, name)) then out[#out + 1] = name end
    end
    table.sort(out)
    return out
end

function Data:copyProgram(d, name)
    local to = fs.combine(CONFIG.scriptDir, name)
    local ok = pcall(function()
        fs.makeDir(CONFIG.scriptDir)
        if fs.exists(to) then fs.delete(to) end
        fs.copy(fs.combine(d.path, name), to)
    end)
    if ok then return true, name .. " liegt jetzt in LUA APPS" end
    return false, "Kopieren fehlgeschlagen (Speicher voll?)"
end

-- Macht aus der Diskette einen Turtle-Installer: Diskettenlaufwerk neben
-- eine Turtle stellen, Diskette rein, Turtle neu starten (Strg+R).
-- Der Funk-Schluessel kommt mit auf die Diskette: die Turtle fragt dann
-- kein Passwort. (Diskette danach nicht herumliegen lassen.)
function Data:turtleDisk(d)
    local prog = TurtleProgs.get("agent")
    local agent = prog and prog.code or TurtleProgs.agentCode()
    if not agent then return false, "Agent fehlt" end
    local free = fs.getFreeSpace(d.path)
    local old = 0
    for _, f in ipairs({ "gts_turtle.lua", "startup.lua", "gts_schluessel" }) do
        local path = fs.combine(d.path, f)
        if fs.exists(path) then old = old + fs.getSize(path) end
    end
    if type(free) == "number" and free + old < #agent + #TURTLE_INSTALLER + 500 then return false, "Diskette zu voll" end
    local ok = pcall(function()
        local h = fs.open(fs.combine(d.path, "gts_turtle.lua"), "w")
        h.write(agent) h.close()
        h = fs.open(fs.combine(d.path, "startup.lua"), "w")
        h.write(TURTLE_INSTALLER) h.close()
        h = fs.open(fs.combine(d.path, "gts_schluessel"), "w")
        h.write(textutils.serialize({ key = Net.toHex(Net.key), default = Net.isDefault, since = Net.since })) h.close()
    end)
    pcall(function() if not disk.getLabel(d.drive) then disk.setLabel(d.drive, "GTS Turtle") end end)
    if not ok then return false, "Schreiben fehlgeschlagen" end
    return true, "Turtle-Disk fertig: Laufwerk neben die Turtle, Turtle neu starten"
end

-- Diskette fuer einen GPS-Sender (siehe GPS_INSTALLER).
function Data:gpsDisk(d)
    local ok = pcall(function()
        local h = fs.open(fs.combine(d.path, "startup.lua"), "w")
        h.write(GPS_INSTALLER) h.close()
    end)
    pcall(function() if not disk.getLabel(d.drive) then disk.setLabel(d.drive, "GTS GPS") end end)
    if not ok then return false, "Schreiben fehlgeschlagen" end
    return true, "GPS-Disk fertig: Laufwerk neben neuen Computer mit Funk-Modem"
end

function Data:drawBackups(top)
    local bh, narrow = UI.bh(), UI.narrow()
    if #self.backups == 0 then
        UI.empty(top + 1, "Noch keine Backups.", "DISK > PC sichert eine Diskette hier auf dem Computer.")
        return
    end
    local ch = narrow and 2 or bh
    UI.list(self.backupPage, self.backups, top, ch + 1, function(b, y)
        local tx, xr = UI.rowCard(y, ch)
        local bx = UI.button{ x = xr - 4, y = narrow and (y + 1) or y, w = 5, text = "DEL", style = "danger",
                              confirm = "bak:" .. b.name, onClick = function()
                                  fs.delete(fs.combine(CONFIG.backupDir, b.name))
                                  self:refresh()
                                  Kernel.notify("Backup geloescht: " .. b.name, colors.orange)
                              end } - 6
        local room = (narrow and xr or bx) - tx
        UI.text(tx, y, b.name:sub(1, room), colors.white)
        local size = fmtSize(b.size)
        if #b.name + 2 + #size <= room then UI.text(tx + #b.name + 2, y, size, colors.lightGray) end
    end)
end

function Data:draw()
    local w, bh, narrow = Kernel.w, UI.bh(), UI.narrow()
    local d, other = self:findDisk()
    local sub
    if #Kernel.hw.drives == 0 then sub = "Kein Laufwerk"
    elseif d then sub = "Disk: " .. (d.label or "ohne Name") .. " (#" .. tostring(d.id) .. ")"
    else sub = other and "Medium ohne Daten" or "Keine Diskette" end
    local onDisk = (self.view ~= "backups")
    local top = UI.header("DATEN", sub, {
        { text = "DISKETTE", style = onDisk and "primary" or nil, onClick = function() self.view = "disk" end },
        { text = "BACKUPS " .. #self.backups, style = (not onDisk) and "primary" or nil,
          onClick = function() self.view = "backups" end },
    })
    if not onDisk then return self:drawBackups(top) end

    if #Kernel.hw.drives == 0 then
        UI.empty(top + 1, "Kein Laufwerk gefunden.", "Ein Disk Drive an den Computer stellen.")
        return
    elseif not d then
        UI.empty(top + 1, other and "Medium ohne Daten (Musik-Disk?)." or "Keine Diskette eingelegt.",
                 "Diskette ins Laufwerk legen.")
        return
    end
    local y = top
    local x = 2
    if not narrow then UI.text(2, y, "Frei", colors.lightGray) x = 7 end
    local pcFree, diskFree = "PC " .. fmtSize(fs.getFreeSpace("/")), "Disk " .. fmtSize(fs.getFreeSpace(d.path))
    x = UI.chip(x, y, pcFree, colors.white, colors.gray) + 1
    if x + #diskFree + 1 <= w then UI.chip(x, y, diskFree, colors.white, colors.gray) end
    -- Jede Aktion mit der Diskette fragt den Sperrcode ab (auch entsperrt):
    -- fremde Disketten koennten Schadcode bringen oder Daten mitnehmen.
    local run = function(title, fn, ...)
        local args = { ... }
        return Kernel.guard(title, function()
            local ok, msg = fn(self, d, table.unpack(args))
            Kernel.notify(msg, ok and colors.lime or colors.red)
        end)
    end
    y = UI.flow({
        { w = 12, text = "DISK > PC", fg = colors.lightBlue, onClick = run("Disk sichern", self.backupDisk) },
        { w = 12, text = "PC > DISK", fg = colors.orange, onClick = run("Auf Disk schreiben", self.pcToDisk) },
        { w = 16, text = "DISK > NOTIZEN", fg = colors.magenta,
          disabled = not fs.isDir(fs.combine(d.path, CONFIG.diskNotes)),
          onClick = run("Notizen importieren", self.notesFromDisk) },
        { w = 14, text = "TURTLE-DISK", fg = colors.lime, onClick = run("Turtle-Disk", self.turtleDisk) },
        { w = 11, text = "GPS-DISK", fg = colors.cyan, onClick = run("GPS-Disk", self.gpsDisk) },
    }, 2, y + 2, w - 1)

    -- Programme auf der Diskette: erscheinen von selbst, sobald sie eingelegt ist.
    y = y + 1
    local progs = self:programs(d)
    if y > Kernel.h - 2 then return end
    UI.section(2, y, ((w < 40) and "AUF DISK (" or "PROGRAMME AUF DISK (") .. #progs .. ")", w - 3)
    if #progs == 0 then
        if y + 2 <= Kernel.h - 1 then UI.text(2, y + 2, ("Keine Dateien im Hauptordner."):sub(1, w - 2), colors.lightGray) end
        return
    end
    local ch = narrow and 2 or bh
    UI.list(self.progPage, progs, y + 2, ch + 1, function(name, py)
        local tx, xr = UI.rowCard(py, ch)
        local bx = UI.buttonsRight({
            { text = "START", style = "primary", onClick = Kernel.guard("Disk-Programm starten", function()
                Shell:launch(Shell.quote(fs.combine(d.path, name)))
            end) },
            { text = "AUF PC", onClick = run("Programm importieren", self.copyProgram, name),
              confirm = fs.exists(fs.combine(CONFIG.scriptDir, name)) and ("ow:" .. name) or nil },
            { text = "DEL", style = "danger", onClick = Kernel.guard("Von Disk loeschen", function()
                local ok = pcall(fs.delete, fs.combine(d.path, name))
                Kernel.notify(ok and ("Von Disk geloescht: " .. name) or "Loeschen fehlgeschlagen",
                              ok and colors.orange or colors.red)
            end) },
        }, narrow and (py + 1) or py, xr)
        UI.text(tx, py, name:sub(1, (narrow and xr or (bx - 2)) - tx + 1), colors.white)
    end)
end

function Data:onScroll(dir)
    local state = (self.view == "backups") and self.backupPage or self.progPage
    state.page = math.max(1, state.page + dir)
end

Apps.register(Data)

-- ======================================================================
-- [8b] LAGER (Kisten-Netzwerk wie ein ME-System)
-- ======================================================================
-- Alle Kisten am Kabel (Wired Modem + Networking Cable) bilden ein Lager.
-- Das OS liest sie regelmaessig aus und zeigt alles wie ein ME-Terminal:
-- Kategorien links, Suche, Mengen. Antippen -> Menge waehlen -> die Items
-- kommen in die EIN/AUS-Kiste am Computer. EINLAGERN bringt alles aus der
-- EIN/AUS-Kiste zurueck ins Lager (zuerst dorthin, wo es schon liegt).
--
-- Verkabelung: an JEDE Kiste (auch die EIN/AUS-Kiste) ein Wired Modem,
-- alle mit Networking Cable zum Wired Modem am Computer, jedes Modem
-- einmal rechtsklicken (es leuchtet rot = verbunden). Kisten direkt neben
-- dem Computer ohne Modem gehen nicht: Items wandern nur innerhalb eines
-- Kabel-Netzes.
-- Geht: Kisten, Doppelkisten, Faesser, Shulker, Sophisticated Storage,
-- Iron Chests, Schubladen-Controller, Mekanism-Kisten (Personal Chest nur
-- auf "Public" gestellt). Oefen, Maschinen usw. werden nicht befuellt.
--
-- Gelernt wird in /gts/items.db: Anzeigename, Stapelgroesse und Kategorie
-- jedes Items (aus Tags und Mod abgeleitet). Wird eine Kategorie von Hand
-- geaendert, merkt sich das OS das auch fuer die Mod.
local Lager = {
    id = "lager", title = "LAGER", order = 3.5, color = colors.cyan,
    view = "grid", cat = "ALLES", search = "", sort = "menge",
    page = 1, importPage = { page = 1 }, setupPage = { page = 1 },
    index = {}, list = {}, invInfo = {}, stats = nil, io = nil, ioList = {},
    scanned = -1000, busy = false, dirty = true, jobs = {}, learnQueue = {},
    db = { items = {}, mods = {} }, cfg = { io = nil, roles = {} }, dbDirty = false, dbSaved = 0,
    input = nil, shift = false, sel = nil, work = nil, remote = nil, lastSum = -1000, infoVer = 1,
}

Lager.CATS = {
    { id = "ERZE",     color = colors.orange,    long = "Erze & Rohstoffe" },
    { id = "BARREN",   color = colors.yellow,    long = "Barren & Edelsteine" },
    { id = "BAUEN",    color = colors.lightGray, long = "Bausteine" },
    { id = "NATUR",    color = colors.green,     long = "Natur & Pflanzen" },
    { id = "ESSEN",    color = colors.pink,      long = "Nahrung" },
    { id = "MOBS",     color = colors.purple,    long = "Mob-Drops" },
    { id = "WERKZEUG", color = colors.lightBlue, long = "Werkzeug & Ruestung" },
    { id = "REDSTONE", color = colors.red,       long = "Redstone" },
    { id = "TECHNIK",  color = colors.cyan,      long = "Technik" },
    { id = "MAGIE",    color = colors.magenta,   long = "Magie" },
    { id = "SONST",    color = colors.white,     long = "Sonstiges" },
}
Lager.CAT = {}
for i, c in ipairs(Lager.CATS) do c.n = i Lager.CAT[c.id] = c end

local TECH_MODS = {}
for m in ([[mekanism mekanismgenerators thermal thermal_expansion create ae2 appliedenergistics2 extendedae megacells
    ae2wtlib immersiveengineering industrialforegoing pneumaticcraft powah refinedstorage computercraft
    advancedperipherals rftoolsbase rftoolsbuilder rftoolspower rftoolsutility mininggadgets buildinggadgets2 laserio
    pipez functionalstorage modularrouters enderio xnet fluxnetworks justdirethings generatorgalore oritech
    ironfurnaces mekanism_extras integrateddynamics integratedtunnels elevatorid utilitix flux cyclic
    torchmaster storagedrawers sophisticatedstorage sophisticatedbackpacks toms_storage]]):gmatch("%S+") do TECH_MODS[m] = true end
local MAGIC_MODS = {}
for m in ([[ars_nouveau ars_elemental ars_additions ars_creo botania occultism irons_spellbooks forbidden_arcanus
    theurgy apotheosis evilcraft bloodmagic eidolon hexerei reliquary naturesaura mysticalagriculture
    mysticalagradditions enigmaticlegacy malum goety arsdelight iceandfire ars_ocultas twilightforest
    bloodmagic irons_jewelry]]):gmatch("%S+") do MAGIC_MODS[m] = true end

-- Leitet die Kategorie aus Name, Tags und Mod ab ("Schluesse ziehen").
function Lager.classify(name, d)
    local mod, path = tostring(name):match("^([^:]+):(.+)$")
    mod, path = mod or "minecraft", path or tostring(name)
    local tags = (d and type(d.tags) == "table") and d.tags or {}
    local function tag(prefix)
        for t in pairs(tags) do
            if type(t) == "string" and t:sub(1, #prefix) == prefix then return true end
        end
        return false
    end
    local function has(...)
        for _, s in ipairs({ ... }) do if path:find(s, 1, true) then return true end end
        return false
    end
    if tag("c:ores") or tag("c:raw_materials") or tag("minecraft:coal_ores") or path:find("_ore$") or path:find("^raw_")
       or has("ancient_debris", "_ore_") then return "ERZE" end
    if path == "redstone" or path == "redstone_block" or path == "redstone_torch" then return "REDSTONE" end
    if MAGIC_MODS[mod] then return "MAGIE" end
    if tag("c:ingots") or tag("c:gems") or tag("c:nuggets") or tag("c:storage_blocks") or tag("c:dusts")
       or has("_ingot", "_nugget", "_gem") or path == "diamond" or path == "emerald" or path == "lapis_lazuli"
       or path == "quartz" or path == "netherite_scrap" or path == "amethyst_shard" then return "BARREN" end
    if (d and tonumber(d.maxDamage) and d.maxDamage > 0) or tag("c:tools") or tag("c:armors") or tag("minecraft:enchantable")
       or tag("minecraft:swords") or tag("minecraft:pickaxes") or tag("minecraft:axes") or tag("minecraft:shovels")
       or has("_pickaxe", "_sword", "_shovel", "_hoe", "_helmet", "_chestplate", "_leggings", "_boots", "bow", "shield", "_axe")
       then return "WERKZEUG" end
    if tag("c:foods") or has("apple", "bread", "cooked_", "beef", "porkchop", "mutton", "chicken", "rabbit", "cod", "salmon",
       "potato", "carrot", "beetroot", "melon_slice", "cookie", "_pie", "stew", "soup", "berries", "honey_bottle", "cake")
       then return "ESSEN" end
    if tag("c:bones") or tag("c:strings") or tag("c:gunpowders") or tag("c:slime_balls") or tag("c:leathers")
       or tag("c:feathers") or tag("c:ender_pearls") or tag("c:rods/blaze")
       or has("bone", "string", "gunpowder", "rotten_flesh", "spider_eye", "ender_pearl", "blaze_rod", "blaze_powder",
              "slime_ball", "leather", "feather", "phantom_membrane", "ghast_tear", "shulker_shell", "ink_sac", "egg")
       then return "MOBS" end
    if tag("minecraft:rails") or has("redstone", "repeater", "comparator", "piston", "observer", "hopper", "dropper",
       "dispenser", "lever", "rail", "daylight_detector", "target", "tripwire", "pressure_plate", "note_block", "button")
       then return "REDSTONE" end
    if MAGIC_MODS[mod] or has("enchanted_book", "experience_bottle", "potion", "_rune", "mana", "spell", "essence") then return "MAGIE" end
    if TECH_MODS[mod] or tag("c:plates") or tag("c:gears") or tag("c:wires") or tag("c:rods")
       or has("circuit", "processor", "cable", "machine", "_plate", "_gear") then return "TECHNIK" end
    if tag("minecraft:logs") or tag("minecraft:leaves") or tag("minecraft:saplings") or tag("minecraft:flowers")
       or tag("c:crops") or tag("c:seeds") or tag("minecraft:small_flowers")
       or has("seeds", "sapling", "leaves", "_log", "_wood", "flower", "mushroom", "vine", "kelp", "wheat", "sugar_cane",
              "bamboo", "cactus", "moss", "dirt", "grass", "tulip", "orchid", "lily", "rose", "fern", "dandelion", "poppy")
       then return "NATUR" end
    if tag("c:stones") or tag("c:cobblestones") or tag("minecraft:planks") or tag("minecraft:stairs") or tag("minecraft:slabs")
       or tag("minecraft:walls") or tag("c:glass_blocks") or tag("minecraft:wool") or tag("minecraft:terracotta")
       or has("stone", "cobble", "deepslate", "planks", "brick", "glass", "sand", "gravel", "concrete", "terracotta",
              "_stairs", "_slab", "_wall", "andesite", "diorite", "granite", "tuff", "calcite", "basalt", "blackstone",
              "netherrack", "obsidian", "wool", "_fence", "clay", "mud", "prismarine", "purpur", "quartz_block")
       then return "BAUEN" end
    return "SONST"
end

-- "minecraft:iron_ingot" -> "Iron Ingot"
function Lager.pretty(name)
    local path = tostring(name):match(":(.+)$") or tostring(name)
    return (path:gsub("_", " "):gsub("(%a)([%w]*)", function(a, b) return a:upper() .. b end))
end

function Lager.fmtCount(n)
    n = tonumber(n) or 0
    if n >= 1000000 then return string.format("%.1fM", n / 1000000) end
    if n >= 10000 then return string.format("%.1fk", n / 1000) end
    return tostring(math.floor(n))
end

-- ---------- Kategorien (v8.0) ----------
-- Gespeichert in /gts/lager_kat.db. Reihenfolge der Zuordnung:
--   1. von Hand verschobenes Item  (items[name] = Kategorie)
--   2. Mod-Ordner: alle Items einer Mod (NIE Vanilla "minecraft:")
--   3. automatisch aus Name, Tags und Mod (Lager.classify)
-- Die 11 eingebauten Kategorien lassen sich umbenennen und umfaerben,
-- eigene Kategorien und Mod-Ordner anlegen, sortieren und loeschen.
-- Dazu: Favoriten, Mindestmengen, zuletzt geholte Items.
local Kat = { file = "/gts/lager_kat.db", ver = 1,
              data = { cats = {}, items = {}, fav = {}, min = {}, recent = {}, nextId = 1 } }
Lager.Kat = Kat
Kat.COLORS = { colors.white, colors.lightGray, colors.orange, colors.yellow, colors.lime, colors.green, colors.cyan,
               colors.lightBlue, colors.blue, colors.purple, colors.magenta, colors.pink, colors.red }

function Kat.load(itemsDb)
    local t = Store.load(Kat.file)
    local d = Kat.data
    if type(t) == "table" then
        for _, k in ipairs({ "items", "fav", "min" }) do if type(t[k]) == "table" then d[k] = t[k] end end
        if type(t.recent) == "table" then d.recent = t.recent end
        d.nextId = tonumber(t.nextId) or 1
        if type(t.cats) == "table" then
            for _, c in ipairs(t.cats) do
                if type(c) == "table" and type(c.id) == "string" and type(c.name) == "string" then
                    d.cats[#d.cats + 1] = { id = c.id, name = c.name:sub(1, 14), color = tonumber(c.color) or colors.white,
                                            builtin = c.builtin == true, mod = c.mod == true,
                                            mods = type(c.mods) == "table" and c.mods or {} }
                end
            end
        end
    end
    -- eingebaute Kategorien sind immer da (neue kommen hinten dazu)
    local have = {}
    for _, c in ipairs(d.cats) do have[c.id] = true end
    for _, b in ipairs(Lager.CATS) do
        if not have[b.id] then d.cats[#d.cats + 1] = { id = b.id, name = b.id, color = b.color, builtin = true, mods = {} } end
    end
    -- v7: von Hand gesetzte Kategorien uebernehmen (die alten Mod-"Stimmen" nicht mehr)
    if type(t) ~= "table" and itemsDb then
        for name, e in pairs(itemsDb) do
            if type(e) == "table" and e.man and e.c then d.items[name] = e.c end
        end
    end
    Kat.index()
end

function Kat.save() Store.save(Kat.file, Kat.data, true) Kat.ver = Kat.ver + 1 end

function Kat.index()
    Kat.byId, Kat.modOf = {}, {}
    for i, c in ipairs(Kat.data.cats) do
        c.n = i
        Kat.byId[c.id] = c
        if c.mod then for m in pairs(c.mods) do Kat.modOf[m] = c.id end end
    end
    Kat.ver = Kat.ver + 1
end

function Kat.get(id) return Kat.byId[id] or Kat.byId.SONST end

-- Kategorie eines Items; auto = automatische Einordnung.
function Kat.of(name, auto)
    local manual = Kat.data.items[name]
    if manual and Kat.byId[manual] then return manual end
    local mod = tostring(name):match("^([^:]+):") or "minecraft"
    if mod ~= "minecraft" and Kat.modOf[mod] then return Kat.modOf[mod] end
    return (auto and Kat.byId[auto]) and auto or "SONST"
end

local function modOf(name) return tostring(name):match("^([^:]+):") or "minecraft" end

-- Items in eine Kategorie schieben. Bei einem Mod-Ordner wandert die ganze
-- Mod mit - ausser Vanilla-Items, die immer einzeln wandern.
-- Rueckgabe: Text fuer die Meldung.
function Kat.move(names, id)
    local c = Kat.byId[id]
    if not c then return "Kategorie fehlt" end
    local mods, single = {}, 0
    for _, name in ipairs(names) do
        local mod = modOf(name)
        if c.mod and mod ~= "minecraft" then
            mods[mod] = true
            Kat.data.items[name] = nil          -- folgt jetzt dem Ordner
        else
            Kat.data.items[name] = id
            single = single + 1
        end
    end
    local list = {}
    for m in pairs(mods) do
        -- eine Mod gehoert immer nur in EINEN Ordner
        for _, other in ipairs(Kat.data.cats) do if other.mod then other.mods[m] = nil end end
        c.mods[m] = true
        list[#list + 1] = m
    end
    table.sort(list)
    Kat.index()
    Kat.save()
    local text = c.name .. ": "
    if #list > 0 then text = text .. "Mod " .. table.concat(list, ", ") .. " komplett" .. ((single > 0) and ", " or "") end
    if single > 0 then text = text .. single .. " Item" .. ((single == 1) and "" or "s") end
    if c.mod and single > 0 then text = text .. " (Vanilla einzeln)" end
    return text
end

function Kat.create(name, isMod)
    local d = Kat.data
    local used = {}
    for _, c in ipairs(d.cats) do used[c.color] = true end
    local color = colors.lightBlue
    for _, col in ipairs(Kat.COLORS) do if not used[col] then color = col break end end
    local id = "K" .. d.nextId
    d.nextId = d.nextId + 1
    d.cats[#d.cats + 1] = { id = id, name = tostring(name):sub(1, 14), color = color, mod = isMod == true, mods = {} }
    Kat.index()
    Kat.save()
    return id
end

function Kat.delete(id)
    local c = Kat.byId[id]
    if not c or c.builtin then return false end
    for i, x in ipairs(Kat.data.cats) do if x == c then table.remove(Kat.data.cats, i) break end end
    for name, cid in pairs(Kat.data.items) do if cid == id then Kat.data.items[name] = nil end end
    Kat.index()
    Kat.save()
    return true
end

function Kat.shift(id, dir)
    local cats = Kat.data.cats
    for i, c in ipairs(cats) do
        if c.id == id then
            local j = i + dir
            if j >= 1 and j <= #cats then cats[i], cats[j] = cats[j], cats[i] end
            break
        end
    end
    Kat.index()
    Kat.save()
end

function Kat.recolor(id)
    local c = Kat.byId[id]
    if not c then return end
    local idx = 1
    for i, col in ipairs(Kat.COLORS) do if col == c.color then idx = i end end
    c.color = Kat.COLORS[idx % #Kat.COLORS + 1]
    Kat.save()
end

function Kat.rename(id, name)
    local c = Kat.byId[id]
    if c and name ~= "" then c.name = name:sub(1, 14) Kat.save() end
end

function Kat.toggleFav(name)
    Kat.data.fav[name] = (not Kat.data.fav[name]) or nil
    Kat.save()
end

function Kat.touch(name)       -- zuletzt geholt
    local r = Kat.data.recent
    for i = #r, 1, -1 do if r[i] == name then table.remove(r, i) end end
    table.insert(r, 1, name)
    while #r > 8 do table.remove(r) end
    Kat.save()
end

-- ---------- Gelerntes ----------
function Lager:info(name)
    local e = self.db.items[name]
    local auto = e and e.c or Lager.classify(name, nil)
    if e and e.man then auto = Lager.classify(name, nil) end   -- v7-Handwert steckt jetzt in Kat
    return { d = (e and e.d) or Lager.pretty(name), m = (e and e.m) or 64, c = Kat.of(name, auto), mod = modOf(name),
             known = e ~= nil, t = e and e.t }
end

local loadTable = Store.load

function Lager:load()
    local db = loadTable(CONFIG.itemsDb)
    if db then
        self.db.items = type(db.items) == "table" and db.items or {}
        self.db.mods = type(db.mods) == "table" and db.mods or {}
    end
    local cfg = loadTable(CONFIG.lagerDb)
    if cfg then
        self.cfg.io = type(cfg.io) == "string" and cfg.io or nil
        self.cfg.roles = type(cfg.roles) == "table" and cfg.roles or {}
    end
    Kat.load(self.db.items)
end

function Lager:saveDb(force)
    if not self.dbDirty or (not force and os.clock() - self.dbSaved < 30) then return end
    Store.save(CONFIG.itemsDb, self.db)
    self.dbDirty, self.dbSaved = false, os.clock()
end

function Lager:saveCfg() Store.save(CONFIG.lagerDb, self.cfg, true) end

-- ---------- Kisten ----------
local SIDES = { top = true, bottom = true, left = true, right = true, front = true, back = true }
local STORAGE_HINTS = { "chest", "barrel", "shulker", "crate", "drawer", "storage", "bin", "cabinet", "vault", "safe", "box" }

-- Rolle einer Kiste: "io" (EIN/AUS), "lager" oder "aus".
function Lager:role(name)
    if name == self.cfg.io then return "io" end
    local r = self.cfg.roles[name]
    if r == "lager" or r == "aus" then return r end
    if SIDES[name] then return "aus" end        -- direkt am Computer: kein Tausch mit dem Netz moeglich
    local kind = tostring(peripheral.getType(name) or "")
    for _, hint in ipairs(STORAGE_HINTS) do
        if kind:find(hint, 1, true) then return "lager" end
    end
    return "aus"
end

function Lager:storageNames()
    local out = {}
    for _, name in ipairs(Kernel.hw.inventories or {}) do
        if self:role(name) == "lager" then out[#out + 1] = name end
    end
    return out
end

-- Liest alle Kisten (parallel, 16 auf einmal) und baut den Index.
function Lager:scan()
    local names = self:storageNames()
    local results = {}
    local fns = {}
    for i, name in ipairs(names) do
        fns[#fns + 1] = function()
            local ok, list = pcall(peripheral.call, name, "list")
            local okS, size = pcall(peripheral.call, name, "size")
            results[i] = { name = name, list = (ok and type(list) == "table") and list or nil, size = (okS and tonumber(size)) or 0 }
        end
    end
    for g = 1, #fns, 16 do parallel.waitForAll(table.unpack(fns, g, math.min(#fns, g + 15))) end

    -- Doppelkiste mit zwei Modems = zweimal dieselbe Kiste: nur einmal zaehlen.
    local sigs = {}
    for _, r in ipairs(results) do
        if r.list and next(r.list) then
            local parts = {}
            for slot, it in pairs(r.list) do
                if type(it) == "table" then parts[#parts + 1] = slot .. "=" .. tostring(it.name) .. "*" .. tostring(it.count) end
            end
            table.sort(parts)
            local sig = r.size .. ":" .. table.concat(parts, ",")
            if sigs[sig] then r.list, r.alias = nil, sigs[sig] else sigs[sig] = r.name end
        end
    end
    local index, list, invInfo = {}, {}, {}
    local stats = { invs = 0, slots = 0, used = 0, items = 0, kinds = 0, broken = 0, double = 0 }
    for _, r in ipairs(results) do
        if r.alias then
            stats.double = stats.double + 1
        elseif r.list then
            local used = 0
            for slot, it in pairs(r.list) do
                if type(it) == "table" and type(it.name) == "string" and tonumber(it.count) then
                    used = used + 1
                    local key = it.name .. "|" .. tostring(it.nbt or "")
                    local e = index[key]
                    if not e then
                        e = { key = key, name = it.name, nbt = it.nbt, count = 0, where = {} }
                        index[key], list[#list + 1] = e, e
                    end
                    e.count = e.count + it.count
                    e.where[#e.where + 1] = { inv = r.name, slot = slot, count = it.count }
                    if not self.db.items[it.name] and not self.learnQueue[it.name] then
                        self.learnQueue[it.name] = { inv = r.name, slot = slot }
                    end
                    stats.items = stats.items + it.count
                end
            end
            stats.invs, stats.slots, stats.used = stats.invs + 1, stats.slots + r.size, stats.used + used
            invInfo[r.name] = { size = r.size, used = used }
        else
            stats.broken = stats.broken + 1
        end
    end
    stats.kinds = #list
    self.index, self.list, self.invInfo, self.stats = index, list, invInfo, stats
    self.scanned, self.dirty = os.clock(), false
    self:readIo()
end

function Lager:readIo()
    local io = self.cfg.io
    self.io = nil
    if not io then return end
    local ok, list = pcall(peripheral.call, io, "list")
    if ok and type(list) == "table" then
        local out = {}
        for slot, it in pairs(list) do
            if type(it) == "table" and type(it.name) == "string" then
                out[#out + 1] = { slot = slot, name = it.name, nbt = it.nbt, count = it.count,
                                  key = it.name .. "|" .. tostring(it.nbt or "") }
                if not self.db.items[it.name] and not self.learnQueue[it.name] then
                    self.learnQueue[it.name] = { inv = io, slot = slot }
                end
            end
        end
        table.sort(out, function(a, b) return a.slot < b.slot end)
        self.io = out
    end
end

-- Lernt bis zu n unbekannte Items (Anzeigename, Stapel, Tags -> Kategorie).
function Lager:learn(n)
    local done = 0
    for name, at in pairs(self.learnQueue) do
        if done >= n then break end
        self.learnQueue[name] = nil
        local ok, d = pcall(peripheral.call, at.inv, "getItemDetail", at.slot)
        if ok and type(d) == "table" and d.name == name then
            self.db.items[name] = { d = tostring(d.displayName or Lager.pretty(name)):sub(1, 40),
                                    m = tonumber(d.maxCount) or 64, c = Lager.classify(name, d),
                                    t = math.floor(os.epoch("utc") / 1000) }
            self.dbDirty, self.infoVer = true, self.infoVer + 1
        end
        done = done + 1
    end
    self:saveDb()
end

-- Holt amount Stueck eines Eintrags in die EIN/AUS-Kiste. Jede Quell-Kiste
-- wird vorher frisch gelesen (es koennte jemand etwas herausgenommen haben).
function Lager:export(key, amount)
    local e, io = self.index[key], self.cfg.io
    if not io then return 0, "Keine EIN/AUS-Kiste eingerichtet" end
    if not e then return 0, "Nicht mehr im Lager" end
    local moved, fresh = 0, {}
    table.sort(e.where, function(a, b) return a.count < b.count end)   -- kleine Reste zuerst
    for _, w in ipairs(e.where) do
        if moved >= amount then break end
        if not fresh[w.inv] then
            local ok, list = pcall(peripheral.call, w.inv, "list")
            fresh[w.inv] = (ok and type(list) == "table") and list or {}
        end
        local it = fresh[w.inv][w.slot]
        if it and it.name == e.name and tostring(it.nbt or "") == tostring(e.nbt or "") then
            -- Ein pushItems bewegt hoechstens einen Stapel; Schubladen und
            -- grosse Lager haben mehr in einem Fach: so oft wie noetig.
            local left = math.min(it.count, amount - moved)
            while left > 0 do
                local ok, n = pcall(peripheral.call, w.inv, "pushItems", io, w.slot, left)
                n = ok and tonumber(n) or 0
                moved, left = moved + n, left - n
                w.count, e.count = w.count - n, e.count - n
                if n == 0 then
                    if not ok then return moved, "EIN/AUS-Kiste nicht im Netz?" end
                    return moved, "EIN/AUS-Kiste voll"
                end
            end
        end
    end
    self.dirty = true
    return moved
end

-- Ziele fuer ein Item: Kisten, in denen es schon liegt, dann Kisten mit Platz.
function Lager:targets(key)
    local out, seen = {}, {}
    local e = self.index[key]
    if e then
        for _, w in ipairs(e.where) do
            if not seen[w.inv] then seen[w.inv] = true out[#out + 1] = w.inv end
        end
    end
    local free = {}
    for name, inf in pairs(self.invInfo) do
        if not seen[name] then free[#free + 1] = { name = name, free = inf.size - inf.used } end
    end
    table.sort(free, function(a, b) if a.free ~= b.free then return a.free > b.free end return a.name < b.name end)
    for _, f in ipairs(free) do out[#out + 1] = f.name end
    return out
end

-- Raeumt die EIN/AUS-Kiste ins Lager (nur key: nur dieses Item, bis amount).
function Lager:import(onlyKey, amount)
    local io = self.cfg.io
    if not io then return 0, "Keine EIN/AUS-Kiste eingerichtet" end
    local ok, list = pcall(peripheral.call, io, "list")
    if not ok or type(list) ~= "table" then return 0, "EIN/AUS-Kiste nicht gefunden" end
    local moved, stuck = 0, false
    for slot, it in pairs(list) do
        local key = it.name .. "|" .. tostring(it.nbt or "")
        if not onlyKey or key == onlyKey then
            local left = it.count
            if amount then left = math.min(left, amount - moved) end
            for _, target in ipairs(self:targets(key)) do
                if left <= 0 then break end
                local okP, n = pcall(peripheral.call, io, "pushItems", target, slot, left)
                n = okP and tonumber(n) or 0
                left, moved = left - n, moved + n
                if n > 0 and self.invInfo[target] then
                    self.invInfo[target].used = self.invInfo[target].used + 1   -- grob: Platz wird knapper
                end
            end
            if left > 0 then stuck = true end
            if amount and moved >= amount then break end
        end
    end
    self.dirty = true
    if stuck then return moved, "Lager voll - nicht alles passte" end
    return moved
end

-- ---------- Auftraege (laufen im Dienst, nicht in der Oberflaeche) ----------
function Lager:job(j)
    if READONLY then return end
    self.jobs[#self.jobs + 1] = j
    self.work = j.label
    os.queueEvent("gts_lager")
end

function Lager:runJob(j)
    if j.kind == "export" then
        local info = self:info(j.name)
        local n, err = self:export(j.key, j.amount)
        if n == 0 then Kernel.notify(err or "Nichts geholt", colors.red)
        else
            Kat.touch(j.name)
            Kernel.notify(n .. "x " .. info.d .. " geholt" .. (err and (", " .. err) or ""), err and colors.orange or colors.lime)
        end
    elseif j.kind == "compact" then
        local merged = self:compact()
        Kernel.notify("Aufgeraeumt: " .. merged .. ((merged == 1) and " Fach" or " Faecher") .. " frei", colors.lime)
    elseif j.kind == "import" then
        local n, err = self:import(j.key, j.amount)
        Kernel.notify(n .. " Items eingelagert" .. (err and (" (" .. err .. ")") or ""), (n > 0 and not err) and colors.lime or colors.orange)
    elseif j.kind == "snap" then
        -- EIN/AUS-Kiste suchen: Zustand aller Kisten merken ...
        self.snap = {}
        for _, name in ipairs(Kernel.hw.inventories or {}) do
            local ok, list = pcall(peripheral.call, name, "list")
            local n = 0
            if ok and type(list) == "table" then for _, it in pairs(list) do n = n + (it.count or 0) end end
            self.snap[name] = n
        end
    elseif j.kind == "detect" then
        -- ... und schauen, welche sich veraendert hat.
        local changed = {}
        for name, before in pairs(self.snap or {}) do
            local ok, list = pcall(peripheral.call, name, "list")
            local n = 0
            if ok and type(list) == "table" then for _, it in pairs(list) do n = n + (it.count or 0) end end
            if n ~= before then changed[#changed + 1] = name end
        end
        if #changed == 1 then
            if SIDES[changed[1]] then
                Kernel.notify("Die Kiste haengt direkt am Computer: bitte mit Wired Modem ans Kabel", colors.red)
            else
                self.cfg.io = changed[1]
                self.cfg.roles[changed[1]] = nil
                self:saveCfg()
                self.wizard = nil
                Kernel.notify("EIN/AUS-Kiste gefunden: " .. changed[1], colors.lime)
            end
        else
            Kernel.notify((#changed == 0) and "Keine Kiste hat sich veraendert - Item hineingelegt?"
                          or "Mehrere Kisten veraendert - bitte nochmal", colors.orange)
            self.wizard = nil
        end
    end
    self.work = nil
    if j.kind == "export" or j.kind == "import" or j.kind == "compact" then self:scan() end
end

-- AUFRAEUMEN: halbe Stapel eines Items zusammenschieben (auch ueber Kisten
-- hinweg). Schubladen mit mehr als einem Stapel je Fach bleiben unberuehrt.
-- Rueckgabe: frei gewordene Faecher.
function Lager:compact()
    local merged, calls = 0, 0
    for _, e in ipairs(self.list) do
        local stack = self:info(e.name).m
        if #e.where >= 2 and stack > 1 then
            local parts = {}
            for _, wh in ipairs(e.where) do if wh.count < stack then parts[#parts + 1] = wh end end
            table.sort(parts, function(a, b) return a.count > b.count end)
            local i, k = 1, #parts
            while i < k and calls < 400 do
                local dst, src = parts[i], parts[k]
                local space = stack - dst.count
                if space <= 0 then
                    i = i + 1
                else
                    local ok, n = pcall(peripheral.call, src.inv, "pushItems", dst.inv, src.slot, math.min(space, src.count), dst.slot)
                    n = ok and tonumber(n) or 0
                    calls = calls + 1
                    if n <= 0 then
                        k = k - 1
                    else
                        dst.count, src.count = dst.count + n, src.count - n
                        if src.count <= 0 then k, merged = k - 1, merged + 1 end
                    end
                end
            end
        end
    end
    self.dirty = true
    return merged
end

-- Mindestmengen pruefen: Meldung (und Chat) einmal, wenn es knapp wird.
function Lager:checkMin()
    local mins = Kat.data.min
    if not next(mins) then self.low = nil return end
    local total = {}
    for _, e in ipairs(self.list) do total[e.name] = (total[e.name] or 0) + e.count end
    self.alerted = self.alerted or {}
    local low = {}
    for name, m in pairs(mins) do
        local n = total[name] or 0
        if n < m then
            low[#low + 1] = name
            if not self.alerted[name] then
                self.alerted[name] = true
                local d = self:info(name).d
                Kernel.notify("Lager: " .. d .. " knapp (" .. n .. "/" .. m .. ")", colors.orange, "lager")
                if Settings.get("lagerChat") ~= false and Extras then Extras.tell(d .. " nur noch " .. n .. " (Minimum " .. m .. ")", "GTS LAGER") end
            end
        else
            self.alerted[name] = nil
        end
    end
    self.low = low
end

-- Kurzfassung fuer das Pocket-Tablet (verschluesselt per Funk).
function Lager:summary()
    local s = self.stats
    if not s then return nil end
    local top = {}
    for _, e in ipairs(self.list) do top[#top + 1] = e end
    table.sort(top, function(a, b) return a.count > b.count end)
    -- die 60 haeufigsten, dazu je Kategorie bis zu 6 weitere (max. 100)
    local items, cats, perCat = {}, {}, {}
    for i, e in ipairs(top) do
        local inf = self:info(e.name)
        cats[inf.c] = (cats[inf.c] or 0) + e.count
        perCat[inf.c] = (perCat[inf.c] or 0) + 1
        if #items < 100 and (i <= 60 or perCat[inf.c] <= 6) then
            items[#items + 1] = { d = inf.d:sub(1, 24), n = e.count, c = inf.c }
        end
    end
    -- Namen, Farben und Reihenfolge der vorkommenden Kategorien (auch eigene)
    local kats = {}
    for i, c in ipairs(Kat.data.cats) do
        if cats[c.id] then kats[#kats + 1] = { id = c.id, name = c.name, color = c.color, n = i } end
    end
    return { t = "SUM", items = items, cats = cats, kats = kats, total = s.items, kinds = s.kinds, slots = s.slots, used = s.used, invs = s.invs }
end

function Lager:interval()
    if Kernel.app == self then return 10 end
    return 60
end

function Lager:service()
    self:load()
    if READONLY then return end
    os.sleep(0.5)
    while true do
        local j = table.remove(self.jobs, 1)
        if j then
            local ok, err = pcall(self.runJob, self, j)
            if not ok then Kernel.log("FEHLER", "Lager: " .. tostring(err)) self.work = nil end
            Kernel.invalidate()
        else
            local have = #(Kernel.hw.inventories or {}) > 0
            if have and (self.dirty or os.clock() - self.scanned >= self:interval()) then
                local ok, err = pcall(self.scan, self)
                if not ok then Kernel.log("FEHLER", "Lager-Scan: " .. tostring(err)) end
                pcall(self.learn, self, 16)
                pcall(self.checkMin, self)
                if Kernel.hw.modem and os.clock() - self.lastSum >= 30 then
                    local sum = self:summary()
                    if sum then
                        Net.broadcast(sum)
                        -- dasselbe fuer die Handys (eigenes Handy-Passwort, siehe INFO)
                        local pk = Kernel.phoneKey()
                        if pk then pcall(rednet.broadcast, Net.sealWith(pk, sum), Net.protoFor(pk)) end
                        self.lastSum = os.clock()
                    end
                end
                if Kernel.app == self or Kernel.app.id == "home" then Kernel.invalidate() end
            elseif Kernel.app == self and self.view == "import" then
                pcall(self.readIo, self)
                Kernel.invalidate()
            end
            -- Automatisch einlagern (Einstellung LAGER > Auto-Einlagern)
            local auto = Settings.get("lagerAuto") or 0
            if auto > 0 and self.cfg.io and #self.jobs == 0 and os.clock() - (self.lastAuto or 0) >= auto then
                self.lastAuto = os.clock()
                pcall(self.readIo, self)
                if self.io and #self.io > 0 then self:job({ kind = "import", label = "Lagere ein (auto)" }) end
            end
            -- Warten (ein Auftrag, der waehrend des Lesens kam, wartet nicht)
            if #self.jobs == 0 then
                local t = os.startTimer(Kernel.app == self and 2 or 10)
                while true do
                    local ev, a = os.pullEvent()
                    if ev == "timer" and a == t then break end
                    if ev == "gts_lager" then break end
                    if ev == "peripheral" or ev == "peripheral_detach" then self.dirty = true break end
                end
            end
        end
    end
end

-- ---------- Bedienung ----------
function Lager:insert(text)
    if self.input then return Input.insert(self, text) end
    if self.view == "grid" then
        self.search = (self.search .. tostring(text):gsub("%c", "")):sub(1, 20)
        self.page = 1
    end
end
function Lager:key(action)
    if self.input then return Input.key(self, action) end
end
function Lager:onChar(ch) self:insert(ch) end
function Lager:onPaste(text) self:insert(text) end
function Lager:onKey(code)
    if self.input then return Input.onKey(self, code) end
    if self.view == "grid" and code == keys.backspace then
        self.search, self.page = self.search:sub(1, -2), 1
    elseif self.view ~= "grid" and code == keys.backspace then
        self.view = "grid"
    end
end
function Lager:onEnter()
    self.input = nil
    if self.view == "item" or self.view == "move" then self.view = "grid" end
end
function Lager:pageState()
    local v = self.view
    if v == "import" then return self.importPage end
    if v == "kisten" then return self.setupPage end
    if v == "cats" or v == "move" or v == "mods" then
        self.catsPage = self.catsPage or { page = 1 }
        return self.catsPage
    end
    return self
end
function Lager:onScroll(dir)
    local state = self:pageState()
    state.page = math.max(1, state.page + dir)
end

-- Gefilterte und sortierte Liste fuer das Raster. Favoriten stehen oben.
function Lager:visible()
    local out, q = {}, self.search:lower()
    local counts = { ALLES = 0, FAV = 0 }
    local ver = self.infoVer * 100000 + Kat.ver
    local fav = Kat.data.fav
    for _, e in ipairs(self.list) do
        if e.count > 0 then
            if e.v ~= ver then
                local inf = self:info(e.name)
                e.d, e.c, e.mod, e.t, e.v = inf.d, inf.c, inf.mod, inf.t or 0, ver
            end
            local match = (q == "") or e.d:lower():find(q, 1, true) or e.name:lower():find(q, 1, true)
            if match then
                counts.ALLES = counts.ALLES + 1
                counts[e.c] = (counts[e.c] or 0) + 1
                if fav[e.name] then counts.FAV = counts.FAV + 1 end
                if self.cat == "ALLES" or self.cat == e.c or (self.cat == "FAV" and fav[e.name]) then out[#out + 1] = e end
            end
        end
    end
    local sort = self.sort
    table.sort(out, function(a, b)
        local fa, fb = fav[a.name] and 1 or 0, fav[b.name] and 1 or 0
        if fa ~= fb then return fa > fb end
        if sort == "az" then
            if a.d ~= b.d then return a.d < b.d end
        elseif sort == "neu" then
            if a.t ~= b.t then return a.t > b.t end
        elseif sort == "mod" then
            if a.mod ~= b.mod then return a.mod < b.mod end
        elseif a.count ~= b.count then
            return a.count > b.count
        end
        if a.d ~= b.d then return a.d < b.d end
        return a.key < b.key
    end)
    return out, counts
end

-- Wie viel? Feste Mengen oder Eingabe.
function Lager:ask(title, max, onAmount)
    Input.open(self, { title = title, maxLen = 7, filter = "[^%d]", hint = "Hoechstens " .. max, onOk = function(t)
        local n = math.floor(tonumber(t) or 0)
        if n > 0 then onAmount(math.min(n, max)) end
    end })
end

local function cabling(y, w)
    local lines = {
        "1. An jede Kiste ein Wired Modem (Doppelkiste: nur eins).",
        "2. Alle mit Networking Cable verbinden, auch zum Computer",
        "   (dort ebenfalls ein Wired Modem).",
        "3. Jedes Modem rechtsklicken - rot = verbunden.",
        "4. Eine Kiste neben den Computer als EIN/AUS-Kiste,",
        "   auch sie mit Modem am Kabel. Dann EINRICHTEN.",
    }
    for i, l in ipairs(lines) do
        if y + i - 1 > Kernel.h - 1 then break end
        UI.text(3, y + i - 1, l:sub(1, w - 4), (i % 2 == 1 or i == 4) and colors.white or colors.lightGray)
    end
end

local function shortInv(name) return (tostring(name):gsub("^.-:", "")) end

-- Kategorie-Punkt + Name als kleines Etikett. Rueckgabe: x rechts daneben.
local function katChip(x, y, c, fg, bg)
    bg = bg or colors.brown
    UI.text(x, y, " \7", c.color, bg)
    UI.text(x + 2, y, " " .. c.name .. " ", fg or colors.white, bg)
    return x + #c.name + 4
end

-- ---------- Kisten (frueher SETUP) ----------
function Lager:drawKisten()
    local w, h, bh, narrow = Kernel.w, Kernel.h, UI.bh(), UI.narrow()
    local s = self.stats
    local sub = (self.cfg.io and ("EIN/AUS: " .. shortInv(self.cfg.io))) or "EIN/AUS-Kiste fehlt"
    if s and s.slots > 0 then sub = s.invs .. " Kisten, " .. math.floor(s.used * 100 / s.slots) .. " % voll  |  " .. sub end
    local top = UI.header("KISTEN", sub, {
        { text = narrow and "\17" or "\17 LAGER", onClick = function() self.view = "grid" end },
    }, (not self.cfg.io) and colors.orange or nil)
    local y = top
    if self.wizard == "wait" then
        UI.text(2, y, "Suche die EIN/AUS-Kiste ...", colors.yellow)
        y = y + 2
    elseif self.wizard == "put" then
        UI.text(2, y, ("Jetzt 1 Item in die Kiste am Computer legen,"):sub(1, w - 2), colors.yellow)
        UI.text(2, y + 1, ("dann FERTIG druecken."):sub(1, w - 2), colors.yellow)
        UI.button{ x = w - 10, y = y, w = 9, text = "FERTIG", style = "primary", onClick = function()
            self.wizard = "wait"
            self:job({ kind = "detect", label = "Suche" })
        end }
        y = y + 3
    else
        y = UI.flow({
            { text = "EIN/AUS-KISTE FINDEN", style = (not self.cfg.io) and "primary" or nil, onClick = function()
                self.wizard = "put"
                self:job({ kind = "snap", label = "Merke Kisten" })
            end },
            { text = "AUFRAEUMEN", disabled = self.work ~= nil or not s, onClick = function()
                self:job({ kind = "compact", label = "Raeume auf" })
            end },
            { text = "NEU LESEN", onClick = function() Kernel.scanHardware() self.dirty = true os.queueEvent("gts_lager") end },
        }, 2, y, w - 1) + 1
    end
    local invs = Kernel.hw.inventories or {}
    if #invs == 0 then
        UI.text(2, y, "Keine Kisten am Kabel gefunden. So geht's:", colors.orange)
        cabling(y + 1, w)
        return
    end
    local ch = narrow and 2 or bh
    UI.list(self.setupPage, invs, y, ch + 1, function(name, ry)
        local tx, xr = UI.rowCard(ry, ch)
        local role = self:role(name)
        local function set(r)
            return function()
                if r == "io" then
                    if SIDES[name] then Kernel.notify("Direkt am Computer geht nicht: Wired Modem + Kabel", colors.red) return end
                    self.cfg.io = name
                    self.cfg.roles[name] = nil
                else
                    if self.cfg.io == name then self.cfg.io = nil end
                    self.cfg.roles[name] = r
                end
                self:saveCfg()
                self.dirty = true
                os.queueEvent("gts_lager")
            end
        end
        local bx = UI.buttonsRight({
            { text = "LAGER", style = (role == "lager") and "primary" or nil, onClick = set("lager") },
            { text = narrow and "E/A" or "EIN/AUS", style = (role == "io") and "primary" or nil, onClick = set("io") },
            { text = "AUS", style = (role == "aus") and "danger" or nil, onClick = set("aus") },
        }, narrow and (ry + 1) or ry, xr)
        local inf = self.invInfo[name]
        local room = (narrow and xr or (bx - 2)) - tx + 1
        local label = shortInv(name)
        UI.text(tx, ry, label:sub(1, room), (role == "aus") and colors.lightGray or colors.white)
        if SIDES[name] then
            if #label + 16 <= room then UI.text(tx + #label + 2, ry, "direkt am PC", colors.lightGray) end
        elseif inf and inf.size > 0 and role == "lager" then
            -- Fuellstand: Balken + Zahl (rot ab 90 %)
            local pct = inf.used / inf.size
            local num, bxs = inf.used .. "/" .. inf.size, tx + #label + 2
            local free = room - #label - 2
            local bw = math.min(16, free - #num - 1)
            local fg = (pct >= 0.9) and colors.red or colors.lightGray
            if bw >= 4 then
                UI.bar(bxs, ry, bw, pct, (pct >= 0.9) and colors.red or colors.lime, colors.brown)
                UI.text(bxs + bw + 1, ry, num, fg)
            elseif #num <= free then
                UI.text(bxs, ry, num, fg)     -- schmal: nur die Zahl
            end
        elseif role == "io" then
            if #label + 12 <= room then UI.text(tx + #label + 2, ry, "EIN/AUS", colors.lime) end
        end
    end)
end

-- ---------- Item-Detail ----------
function Lager:drawItem(e)
    local w, h, bh, narrow = Kernel.w, Kernel.h, UI.bh(), UI.narrow()
    local inf = self:info(e.name)
    local cat = Kat.get(inf.c)
    local fav = Kat.data.fav[e.name]
    local top = UI.header(inf.d, e.name .. (e.nbt and " *" or ""), {
        { text = fav and "\4 FAVORIT" or "FAVORIT", fg = fav and colors.yellow or nil, onClick = function() Kat.toggleFav(e.name) end },
        { text = narrow and "\17" or "\17 LAGER", onClick = function() self.view = "grid" end },
    })
    local y = top
    -- grosse Zahl
    local big = Lager.fmtCount(e.count)
    UI.text(2, y, big, colors.white)
    local stacks = math.max(1, inf.m)
    local more = ((e.count >= 10000) and (e.count .. " Stueck, ") or "Stueck, ") .. math.ceil(e.count / stacks) .. " Stapel"
    UI.text(3 + #big, y, more:sub(1, w - #big - 4), colors.lightGray)
    y = y + 2
    local x, vx = 2, narrow and 9 or 14
    local function row(label, text, color)
        UI.text(x, y, label, colors.lightGray)
        UI.text(vx, y, tostring(text):sub(1, w - vx), color or colors.white)
        y = y + 1
    end
    -- Kategorie + Verschieben
    UI.text(x, y, narrow and "KAT." or "KATEGORIE", colors.lightGray)
    local cx = katChip(vx, y, cat)
    if not READONLY then
        UI.button{ x = cx + 1, y = y, w = narrow and 3 or 12, h = 1, text = narrow and "\16" or "VERSCHIEBEN", style = "ghost", fg = colors.white,
                   onClick = function() self.movePick, self.moveBack, self.view = { e.name }, "item", "move" end }
    end
    y = y + 1
    row("MOD", inf.mod .. ((cat.mod and inf.mod ~= "minecraft") and "  (im Mod-Ordner)" or ""))
    local kisten, order = {}, {}
    for _, wh in ipairs(e.where) do
        if not kisten[wh.inv] then kisten[wh.inv] = 0 order[#order + 1] = wh.inv end
        kisten[wh.inv] = kisten[wh.inv] + wh.count
    end
    local parts = {}
    for i, inv in ipairs(order) do
        if i > 3 then parts[#parts + 1] = "+" .. (#order - 3) break end
        parts[#parts + 1] = shortInv(inv) .. " " .. Lager.fmtCount(kisten[inv])
    end
    row("KISTEN", table.concat(parts, ", "))
    local min = Kat.data.min[e.name]
    UI.text(x, y, narrow and "MIN." or "MINDESTENS", colors.lightGray)
    local low = min and e.count < min
    UI.text(vx, y, min and (tostring(min) .. (low and "  (zu wenig!)" or "")) or "aus", low and colors.orange or (min and colors.white or colors.lightGray))
    if not READONLY then
        local mx = vx + (min and (#tostring(min) + (low and 14 or 0)) or 3) + 2
        UI.button{ x = mx, y = y, w = narrow and 3 or 9, h = 1, text = narrow and "\16" or "AENDERN", style = "ghost", fg = colors.white,
                   onClick = function()
                       Input.open(self, { title = "Warnen, wenn weniger als ... (0 = aus)", text = min and tostring(min) or "",
                                          maxLen = 7, filter = "[^%d]", onOk = function(t)
                           local n = math.floor(tonumber(t) or 0)
                           Kat.data.min[e.name] = (n > 0) and n or nil
                           Kat.save()
                           self.alerted = self.alerted or {}
                           self.alerted[e.name] = nil
                       end })
                   end }
    end
    y = y + 2
    if READONLY then return end
    if not self.cfg.io then
        UI.text(2, y, "Erst eine EIN/AUS-Kiste einrichten (KISTEN).", colors.orange)
        return
    end
    local function get(n, label)
        return { text = label or tostring(n), disabled = e.count <= 0 or self.work ~= nil, onClick = function()
            self:job({ kind = "export", key = e.key, name = e.name, amount = math.min(n, e.count), label = "Hole" })
        end }
    end
    local list = { get(1), get(16), get(64) }
    if stacks ~= 64 and stacks ~= 16 and stacks ~= 1 then list[#list + 1] = get(stacks, "STAPEL " .. stacks) end
    list[#list + 1] = get(math.max(1, math.floor(e.count / 2)), "HALB")
    list[#list + 1] = get(e.count, "ALLES")
    list[#list + 1] = { text = "ANZAHL ...", style = "primary", disabled = e.count <= 0, onClick = function()
        self:ask("Wie viele " .. inf.d .. "?", e.count, function(n)
            self:job({ kind = "export", key = e.key, name = e.name, amount = n, label = "Hole" })
        end)
    end }
    -- kleiner Bildschirm: kuerzer beschriften, notfalls ohne Ueberschrift
    if y + UI.flowHeight(list, 2, w - 1) > h then list[#list].text = "ANZ." end
    if y + UI.flowHeight(list, 2, w - 1) <= h then
        UI.section(2, y, "IN DIE EIN/AUS-KISTE", w - 3)
        y = y + 1
    end
    UI.flow(list, 2, y, w - 1)
end

-- ---------- Verschieben: Ziel-Kategorie waehlen ----------
function Lager:drawMove()
    local w, bh, narrow = Kernel.w, UI.bh(), UI.narrow()
    local names = self.movePick or {}
    local back = function()
        self.view = self.moveBack or "grid"
        if self.view == "grid" then self.selMode, self.selected = nil, nil end
    end
    local top = UI.header("VERSCHIEBEN NACH", #names .. " Item" .. ((#names == 1) and "" or "s"), {
        { text = narrow and "+K" or "+ KATEGORIE", onClick = function()
            Input.open(self, { title = "Neue Kategorie", maxLen = 14, onOk = function(t)
                if t ~= "" then Kernel.notify(Kat.move(names, Kat.create(t, false)), colors.lime) back() end
            end })
        end },
        { text = narrow and "+M" or "+ MOD-ORDNER", onClick = function()
            Input.open(self, { title = "Neuer Mod-Ordner (ganze Mods)", maxLen = 14, onOk = function(t)
                if t ~= "" then Kernel.notify(Kat.move(names, Kat.create(t, true)), colors.lime) back() end
            end })
        end },
        { text = "ABBRUCH", onClick = back },
    })
    local cols = (w >= 70) and 3 or ((w >= 45) and 2 or 1)
    local cw = math.floor((w - 1) / cols) - 1
    local cats = Kat.data.cats
    local rowsPer = math.floor((Kernel.h - bh - 1 - top + 1) / 2)
    local per = math.max(1, rowsPer * cols)
    local st = self:pageState()
    local pages = math.max(1, math.ceil(#cats / per))
    st.page = math.max(1, math.min(st.page, pages))
    for i = 1, per do
        local c = cats[(st.page - 1) * per + i]
        if not c then break end
        local col, r = (i - 1) % cols, math.floor((i - 1) / cols)
        local x, y = 2 + col * (cw + 1), top + r * 2
        UI.card(x, y, cw, 1)
        UI.text(x + 1, y, "\7", c.color)
        UI.text(x + 3, y, c.name:sub(1, cw - 4), colors.white)
        if c.mod and #c.name + 15 <= cw then UI.text(x + cw - 11, y, "MOD-ORDNER", colors.lightGray) end
        UI.hit(x, y, cw, 1, function()
            Kernel.notify(Kat.move(names, c.id), colors.lime)
            back()
        end)
        UI.surface = colors.black
    end
    if pages > 1 then UI.pager(st, pages) end
    UI.text(2, Kernel.h, ("Mod-Ordner nehmen die ganze Mod mit - Vanilla-Items wandern einzeln."):sub(1, w - 2), colors.lightGray)
end

-- ---------- Kategorien verwalten ----------
function Lager:drawCats()
    local w, bh, narrow = Kernel.w, UI.bh(), UI.narrow()
    local top = UI.header("KATEGORIEN", not narrow and "\17 \16 = Reihenfolge in der Leiste  \183  X loescht eigene" or nil, {
        { text = narrow and "+K" or "+ KATEGORIE", onClick = function()
            Input.open(self, { title = "Neue Kategorie", maxLen = 14, onOk = function(t)
                if t ~= "" then Kat.create(t, false) self:pageState().page = 999 end   -- ans Ende (neue Zeile sichtbar)
            end })
        end },
        { text = narrow and "+M" or "+ MOD-ORDNER", onClick = function()
            Input.open(self, { title = "Neuer Mod-Ordner", maxLen = 14,
                               hint = "Items hineinschieben: die ganze Mod wandert mit", onOk = function(t)
                if t ~= "" then Kat.create(t, true) self:pageState().page = 999 end
            end })
        end },
        { text = narrow and "\17" or "\17 LAGER", onClick = function() self.view = "grid" end },
    })
    local _, counts = self:visible()
    local ch = narrow and 2 or bh
    UI.list(self:pageState(), Kat.data.cats, top, ch + 1, function(c, y)
        local tx, xr = UI.rowCard(y, ch)
        local buttons = {
            { text = "\17", onClick = function() Kat.shift(c.id, -1) end },     -- in der Leiste nach links
            { text = "\16", onClick = function() Kat.shift(c.id, 1) end },      -- nach rechts
            { text = "FARBE", fg = c.color, onClick = function() Kat.recolor(c.id) end },
            { text = "NAME", onClick = function()
                Input.open(self, { title = "Name der Kategorie", text = c.name, maxLen = 14, onOk = function(t) Kat.rename(c.id, t) end })
            end },
        }
        if c.mod then buttons[#buttons + 1] = { text = "MODS", onClick = function() self.modsOf, self.view = c.id, "mods" end } end
        if not c.builtin then
            buttons[#buttons + 1] = { text = "X", style = "danger", confirm = "kat:" .. c.id, onClick = function() Kat.delete(c.id) end }
        end
        local bx = UI.buttonsRight(buttons, narrow and (y + 1) or y, xr)
        UI.text(tx - 1, y, "\7", c.color)
        local room = (narrow and xr or (bx - 2)) - tx + 1
        UI.text(tx + 1, y, c.name:sub(1, room - 1), colors.white)
        local info = (c.builtin and "eingebaut" or (c.mod and "Mod-Ordner" or "eigene")) .. ", " .. (counts[c.id] or 0) .. (((counts[c.id] or 0) == 1) and " Sorte" or " Sorten")
        if c.mod then
            local m = {}
            for mod in pairs(c.mods) do m[#m + 1] = mod end
            table.sort(m)
            if #m > 0 then info = info .. ": " .. table.concat(m, ", ") end
        end
        if #c.name + 3 + #info <= room then UI.text(tx + #c.name + 3, y, info, colors.lightGray)
        elseif ch >= 2 and not narrow then UI.text(tx + 1, y + 1, info:sub(1, room - 1), colors.lightGray) end
    end)
end

-- Mods eines Mod-Ordners (zum Herausnehmen).
function Lager:drawMods()
    local c = Kat.byId[self.modsOf or ""]
    if not c then self.view = "cats" return self:drawCats() end
    local w, bh, narrow = Kernel.w, UI.bh(), UI.narrow()
    local top = UI.header(c.name, "Mod-Ordner", {
        { text = narrow and "\17" or "\17 KATEGORIEN", onClick = function() self.view = "cats" end },
    })
    local mods = {}
    for m in pairs(c.mods) do mods[#mods + 1] = m end
    table.sort(mods)
    if #mods == 0 then
        UI.empty(top + 2, "Noch keine Mod im Ordner.", "Ein Item einer Mod hierher verschieben - dann wandert die ganze Mod mit.")
        return
    end
    UI.list(self:pageState(), mods, top, (narrow and 2 or bh) + 1, function(m, y)
        local tx, xr = UI.rowCard(y, narrow and 2 or bh)
        UI.buttonsRight({ { text = "HERAUSNEHMEN", onClick = function()
            c.mods[m] = nil
            Kat.index()
            Kat.save()
        end } }, narrow and (y + 1) or y, xr)
        UI.text(tx, y, m, colors.white)
    end)
end

function Lager:drawImport()
    local w, bh, narrow = Kernel.w, UI.bh(), UI.narrow()
    local io = self.io or {}
    local total = 0
    for _, it in ipairs(io) do total = total + it.count end
    local auto = Settings.get("lagerAuto") or 0
    local top = UI.header("EINLAGERN", "EIN/AUS-Kiste: " .. total .. " Items" .. ((auto > 0) and ("  |  automatisch alle " .. auto .. " s") or ""), {
        { text = narrow and "\17" or "\17 LAGER", onClick = function() self.view = "grid" end },
        { text = "ALLES EINLAGERN", style = "primary", disabled = #io == 0 or self.work ~= nil, onClick = function()
            self:job({ kind = "import", label = "Lagere ein" })
        end },
    })
    if #io == 0 then
        UI.empty(top + 2, "Die EIN/AUS-Kiste ist leer.", "Items hineinlegen - sie erscheinen hier von selbst.")
        return
    end
    local ch = narrow and 2 or bh
    UI.list(self.importPage, io, top, ch + 1, function(it, y)
        local tx, xr = UI.rowCard(y, ch)
        local inf = self:info(it.name)
        UI.text(tx - 1, y, "\7", Kat.get(inf.c).color)
        local bx = UI.buttonsRight({
            { text = "EINLAGERN", disabled = self.work ~= nil, onClick = function()
                self:job({ kind = "import", key = it.key, label = "Lagere ein" })
            end },
        }, narrow and (y + 1) or y, xr)
        local room = (narrow and xr or (bx - 2)) - tx + 1
        local cnt = Lager.fmtCount(it.count) .. "x "
        UI.text(tx + 1, y, cnt, colors.white)
        UI.text(tx + 1 + #cnt, y, inf.d:sub(1, math.max(1, room - #cnt - 1)), colors.lightGray)
    end)
end

-- Pocket/Handy: Uebersicht, die der PC per Funk schickt.
function Lager:drawRemote()
    local w, h = Kernel.w, Kernel.h
    local r = self.remote
    local function katOf(id)
        local k = r and r.kats and r.kats[id]
        if k then return k end
        local b = Lager.CAT[id]
        return { name = b and b.id or tostring(id), color = b and b.color or colors.white }
    end
    -- Kategorie-Knopf: tippen schaltet weiter (nur Kategorien, die vorkommen)
    local cats = { "ALLES" }
    if r then
        local have, order = {}, {}
        for _, it in ipairs(r.items) do
            if not have[it.c] then have[it.c] = true order[#order + 1] = it.c end
        end
        local rank = r.order or {}
        table.sort(order, function(a, b) return (rank[a] or 99) < (rank[b] or 99) end)
        for _, id in ipairs(order) do cats[#cats + 1] = id end
    end
    local cur = self.rcat or "ALLES"
    local idx = 1
    for i, c in ipairs(cats) do if c == cur then idx = i end end
    cur = cats[idx]
    local old = r and os.clock() - (r.at or os.clock()) > 120
    local curName = (cur == "ALLES") and "ALLES" or katOf(cur).name
    local top = UI.header("LAGER", r and (Lager.fmtCount(r.total) .. " Items" .. (old and " (alt)" or "")) or "keine Daten",
        r and { { text = curName:upper():sub(1, 12), fg = (cur ~= "ALLES") and katOf(cur).color or nil,
                  onClick = function() self.rcat, self.page = cats[idx % #cats + 1], 1 end } } or nil,
        old and colors.orange or nil)
    if not r then
        UI.empty(top + 1, "Noch keine Lager-Daten.", PHONE and ("Der PC funkt sie alle 30 s. Handy-Passwort in INFO (Standard "
            .. CONFIG.phonePassword .. ").") or "Der PC schickt sie alle 30 s (gleiches Schwarm-Passwort).")
        return
    end
    local y = top
    local pct = (r.slots > 0) and math.floor(r.used * 100 / r.slots) or 0
    UI.text(2, y, (r.kinds .. " Sorten, " .. r.invs .. " Kisten"):sub(1, w - 2), colors.lightGray)
    UI.bar(2, y + 1, w - 8, pct / 100, (pct > 90) and colors.red or colors.lime)
    UI.text(w - 5, y + 1, pct .. "%", colors.white)
    y = y + 3
    local q = self.search:lower()
    local items = {}
    for _, it in ipairs(r.items) do
        if (q == "" or it.d:lower():find(q, 1, true)) and (cur == "ALLES" or it.c == cur) then items[#items + 1] = it end
    end
    if q ~= "" then UI.text(2, y - 1, ("Suche: " .. self.search):sub(1, w - 2), colors.yellow) end
    UI.list(self, items, y, 1, function(it, ry)
        UI.text(1, ry, "\149", katOf(it.c).color)
        local cnt = Lager.fmtCount(it.n)
        UI.text(2, ry, it.d:sub(1, w - #cnt - 3), colors.white)
        UI.text(w - #cnt, ry, cnt, colors.lightGray)
    end)
end

local SORTS = { { id = "menge", label = "MENGE" }, { id = "az", label = "A-Z" }, { id = "neu", label = "NEU" }, { id = "mod", label = "MOD" } }

-- Kategorie-Chips in einer Zeile; passen nicht alle, blaettern < > seitenweise.
-- Am Ende ist die Leiste rechts aufgefuellt (kein Leerraum, letzter Chip sichtbar).
function Lager:drawChips(chips, y, x0, xMax)
    local widths = {}
    for i, c in ipairs(chips) do widths[i] = #c.name + #tostring(c.n) + 5 end
    local function fits(from)
        local x, last = x0, from - 1
        for i = from, #chips do
            if x + widths[i] - 1 > xMax - 8 then break end
            x, last = x + widths[i] + 1, i
        end
        return math.max(last, from)          -- mindestens ein Chip
    end
    -- groesster Start, bei dem der letzte Chip noch draufpasst
    local maxOff = #chips
    while maxOff > 1 and fits(maxOff - 1) >= #chips do maxOff = maxOff - 1 end
    self.chipOff = math.max(1, math.min(self.chipOff or 1, maxOff))
    -- neu gewaehlte Kategorie sichtbar machen (danach darf man frei blaettern)
    local active
    for i, c in ipairs(chips) do if c.id == self.cat then active = i end end
    if active and active ~= self.chipShown and (active < self.chipOff or active > fits(self.chipOff)) then
        self.chipOff = math.min(active, maxOff)
    end
    self.chipShown = active
    local last = fits(self.chipOff)
    local x = x0
    for i = self.chipOff, last do
        local c = chips[i]
        local on = (c.id == self.cat)
        local bg = on and colors.white or colors.gray
        local name = c.name:sub(1, math.max(1, xMax - 8 - x - #tostring(c.n) - 4))
        UI.text(x, y, " \7", c.color, bg)
        UI.text(x + 2, y, " " .. name .. " ", on and colors.black or colors.white, bg)
        UI.text(x + 4 + #name, y, tostring(c.n) .. " ", on and colors.gray or colors.lightGray, bg)
        local id = c.id
        UI.hit(x, y, widths[i], 1, function() self.cat, self.page = id, 1 end)
        x = x + widths[i] + 1
    end
    if self.chipOff > 1 or last < #chips then
        local off = self.chipOff
        UI.button{ x = xMax - 6, y = y, w = 3, h = 1, text = "\17", disabled = off <= 1, onClick = function()
            -- eine Seite zurueck: der Chip vor der Leiste wird der letzte sichtbare
            local s = off - 1
            while s > 1 and fits(s - 1) >= off - 1 do s = s - 1 end
            self.chipOff = math.max(1, s)
        end }
        UI.button{ x = xMax - 2, y = y, w = 3, h = 1, text = "\16", disabled = last >= #chips, onClick = function()
            self.chipOff = math.min(maxOff, last + 1)                      -- eine Seite vor
        end }
    end
end

function Lager:draw()
    if self.input then return Input.draw(self) end
    if READONLY then return self:drawRemote() end
    local views = { kisten = self.drawKisten, import = self.drawImport, cats = self.drawCats, move = self.drawMove, mods = self.drawMods }
    if views[self.view] then return views[self.view](self) end
    if self.view == "item" then
        local e = self.sel and self.index[self.sel]
        if e then return self:drawItem(e) end
        self.view = "grid"
    end
    local w, h, bh, narrow = Kernel.w, Kernel.h, UI.bh(), UI.narrow()
    local s = self.stats
    local ioCount = 0
    for _, it in ipairs(self.io or {}) do ioCount = ioCount + it.count end
    local sub
    if self.work then sub = self.work .. " ..."
    elseif s then sub = Lager.fmtCount(s.items) .. " Items, " .. s.kinds .. " Sorten, "
                        .. ((s.slots > 0) and math.floor(s.used * 100 / s.slots) or 0) .. "% voll"
                        .. ((self.low and #self.low > 0) and ("  |  " .. #self.low .. " knapp") or "")
    else sub = "lese Kisten ..." end
    self.selected = self.selected or {}
    local nSel = 0
    for _ in pairs(self.selected) do nSel = nSel + 1 end
    local items, counts = self:visible()
    local actions
    if self.selMode then
        actions = {
            { text = "VERSCHIEBEN" .. ((nSel > 0) and (" " .. nSel) or ""), style = (nSel > 0) and "primary" or nil, disabled = nSel == 0,
              onClick = function()
                  local names = {}
                  for name in pairs(self.selected) do names[#names + 1] = name end
                  self.movePick, self.moveBack, self.view = names, "grid", "move"
              end },
            { text = "FAVORIT", disabled = nSel == 0, onClick = function()
                  for name in pairs(self.selected) do Kat.data.fav[name] = true end
                  Kat.save()
                  self.selMode, self.selected = nil, nil
              end },
            { text = "ALLE", onClick = function() for _, e in ipairs(items) do self.selected[e.name] = true end end },
            { text = "FERTIG", onClick = function() self.selMode, self.selected = nil, nil end },
        }
    else
        actions = {
            { text = (narrow and "EIN" or "EINLAGERN") .. ((ioCount > 0) and (" " .. Lager.fmtCount(ioCount)) or ""),
              style = (ioCount > 0) and "primary" or nil, disabled = not self.cfg.io,
              onClick = function() self.view, self.importPage.page = "import", 1 end },
            { text = "KISTEN", style = (not self.cfg.io) and "primary" or nil, onClick = function() self.view = "kisten" end },
            { text = narrow and "KAT" or "KATEGORIEN", onClick = function() self.view = "cats" end },
        }
    end
    local top = UI.header("LAGER", sub, actions, self.work and colors.yellow or ((self.low and #self.low > 0) and colors.orange or nil))
    if #(Kernel.hw.inventories or {}) == 0 then
        UI.text(2, top, "Noch keine Kisten am Kabel. So geht's:", colors.orange)
        cabling(top + 1, w)
        return
    end

    -- 1) Kategorie-Chips (schmal: ein Wahlknopf)
    local chips = { { id = "ALLES", name = "ALLES", color = colors.white, n = counts.ALLES } }
    if counts.FAV > 0 then chips[#chips + 1] = { id = "FAV", name = "FAVORITEN", color = colors.yellow, n = counts.FAV } end
    local known = { ALLES = true, FAV = counts.FAV > 0 }
    for _, c in ipairs(Kat.data.cats) do
        if (counts[c.id] or 0) > 0 or not c.builtin then
            chips[#chips + 1] = { id = c.id, name = c.name, color = c.color, n = counts[c.id] or 0 }
            known[c.id] = true
        end
    end
    if not known[self.cat] then self.cat = "ALLES" end
    local y = top
    if narrow then
        local cur = chips[1]
        for i, c in ipairs(chips) do if c.id == self.cat then cur = chips[i] end end
        UI.button{ x = 1, y = y, w = w, h = 1, text = cur.name .. " (" .. cur.n .. ") \16", onClick = function()
            for i, c in ipairs(chips) do
                if c.id == self.cat then self.cat = chips[i % #chips + 1].id break end
            end
            self.page = 1
        end }
    else
        self:drawChips(chips, y, 2, w - 1)
    end
    y = y + 2

    -- 2) Suche, Sortierung, Ansicht, Auswahl
    local sortLabel = "MENGE"
    for _, so in ipairs(SORTS) do if so.id == self.sort then sortLabel = so.label end end
    local tools = {
        { text = sortLabel, h = 1, onClick = function()
            for i, so in ipairs(SORTS) do
                if so.id == self.sort then self.sort = SORTS[i % #SORTS + 1].id break end
            end
        end },
    }
    if not narrow then
        tools[#tools + 1] = { text = (self.layout == "liste") and "KACHELN" or "LISTE", h = 1,
                              onClick = function() self.layout = (self.layout == "liste") and "kacheln" or "liste" end }
        tools[#tools + 1] = { text = "AUSWAHL", h = 1, style = self.selMode and "primary" or nil,
                              onClick = function() self.selMode = not self.selMode self.selected = {} end }
    end
    local tw = -1
    for _, t in ipairs(tools) do tw = tw + #t.text + 3 end
    local fieldW = w - 2 - tw - 2
    local label = (self.search ~= "") and self.search or (Kernel.display.touch and "Suchen ..." or "Tippen zum Suchen ...")
    UI.fill(2, y, fieldW, 1, colors.gray)
    UI.text(3, y, "\187 " .. label:sub(1, fieldW - 4), (self.search ~= "") and colors.white or colors.lightGray, colors.gray)
    UI.hit(2, y, fieldW - 2, 1, function()
        Input.open(self, { title = "Suche (Name)", text = self.search, maxLen = 20, onOk = function(t) self.search, self.page = t, 1 end })
    end)
    if self.search ~= "" then
        UI.button{ x = 2 + fieldW - 2, y = y, w = 2, h = 1, text = "x", style = "ghost", fg = colors.red,
                   onClick = function() self.search, self.page = "", 1 end }
    end
    UI.buttonsRight(tools, y, w - 1)
    y = y + 2

    -- 3) Zuletzt geholt (Schnellzugriff)
    local recent = Kat.data.recent
    if not narrow and self.cat == "ALLES" and self.search == "" and not self.selMode and #recent > 0 then
        UI.text(2, y, "ZULETZT", colors.lightGray)
        local x = 11
        for _, name in ipairs(recent) do
            local e = self.index[name .. "|"]
            if e and e.count > 0 then
                local d = e.d or self:info(name).d
                if x + #d + 1 > w - 1 then break end
                UI.text(x, y, d, colors.white)
                local key = e.key
                UI.hit(x, y, #d, 1, function() self.sel, self.view = key, "item" end)
                x = x + #d + 3
                if x - 2 <= w - 1 then UI.text(x - 2, y, "\183", colors.brown) end
            end
        end
        y = y + 2
    end

    if #items == 0 then
        UI.text(2, y, ((s and s.kinds == 0) and "Das Lager ist leer." or "Nichts gefunden."):sub(1, w - 2), colors.lightGray)
        return
    end
    local fav = Kat.data.fav
    local function tap(e)
        return function()
            if self.selMode then
                self.selected[e.name] = (not self.selected[e.name]) or nil
            else
                self.sel, self.view = e.key, "item"
            end
        end
    end
    if self.layout == "liste" and not narrow then
        -- Liste: Name | Menge | Kisten | Mod
        local rows = h - bh - y
        if rows < 1 then return end
        local pages = math.max(1, math.ceil(#items / rows))
        self.page = math.max(1, math.min(self.page, pages))
        local first = (self.page - 1) * rows
        local nameW = w - 2 - 10 - 10 - 14
        for i = 1, rows do
            local e = items[first + i]
            if not e then break end
            local ry = y + i - 1
            local sel = self.selMode and self.selected[e.name]
            local bg = sel and colors.brown or ((i % 2 == 1) and colors.gray or colors.black)
            UI.fill(2, ry, w - 2, 1, bg)
            UI.text(2, ry, "\149", Kat.get(e.c).color, bg)
            local name = (fav[e.name] and "* " or "") .. e.d .. (e.nbt and "*" or "")
            UI.text(4, ry, name:sub(1, nameW - 1), colors.white, bg)
            if fav[e.name] then UI.text(4, ry, "*", colors.yellow, bg) end
            local cnt = Lager.fmtCount(e.count)
            UI.text(4 + nameW + 8 - #cnt, ry, cnt, colors.white, bg)
            local nk = {}
            for _, wh in ipairs(e.where) do nk[wh.inv] = true end
            local n = 0
            for _ in pairs(nk) do n = n + 1 end
            UI.text(4 + nameW + 10, ry, (n .. ((n == 1) and " Kiste" or " Kisten")):sub(1, 9), colors.lightGray, bg)
            UI.text(4 + nameW + 20, ry, e.mod:sub(1, w - (4 + nameW + 20) - 1), colors.lightGray, bg)
            if sel then UI.text(w - 2, ry, "\7", colors.lime, bg) end
            UI.hit(2, ry, w - 2, 1, tap(e))
        end
        if pages > 1 then UI.pager(self, pages) end
        return
    end
    -- Kacheln: Name, darunter Menge (+ Mod); links ein Streifen in Kategorie-Farbe
    local gw = w - 2
    local cellW = narrow and w or ((w >= 70) and 21 or 19)
    local cols = math.max(1, math.floor((gw + 1) / (cellW + 1)))
    cellW = math.floor((gw + 1) / cols) - 1
    local cellH = narrow and 1 or bh
    local rows = math.floor((h - bh - y) / cellH)
    if rows < 1 then return end
    local per = rows * cols
    local pages = math.max(1, math.ceil(#items / per))
    self.page = math.max(1, math.min(self.page, pages))
    local first = (self.page - 1) * per
    for i = 1, per do
        local e = items[first + i]
        if not e then break end
        local c = (i - 1) % cols
        local r = math.floor((i - 1) / cols)
        local x = narrow and 1 or (2 + c * (cellW + 1))
        local cy = y + r * cellH
        local sel = self.selMode and self.selected[e.name]
        local bg = sel and colors.brown or colors.gray
        UI.fill(x, cy, cellW, cellH, bg)
        local kc = Kat.get(e.c).color
        for k = 0, cellH - 1 do UI.text(x, cy + k, "\149", kc, bg) end
        local cnt = Lager.fmtCount(e.count)
        local star = fav[e.name] and 2 or 0
        local name = e.d .. (e.nbt and "*" or "")
        if star > 0 then UI.text(x + 1, cy, "*", colors.yellow, bg) end
        if cellH >= 2 then
            UI.text(x + 1 + star, cy, name:sub(1, cellW - 1 - star - (sel and 1 or 0)), colors.white, bg)
            UI.text(x + 1, cy + 1, e.mod:sub(1, cellW - #cnt - 3), colors.lightGray, bg)
            UI.text(x + cellW - #cnt, cy + 1, cnt, colors.white, bg)
        else
            UI.text(x + 1 + star, cy, name:sub(1, cellW - #cnt - 2 - star), colors.white, bg)
            UI.text(x + cellW - #cnt, cy, cnt, colors.white, bg)
        end
        if sel then UI.text(x + cellW - 1, cy, "\7", colors.lime, bg) end
        UI.hit(x, cy, cellW, cellH, tap(e))
    end
    if pages > 1 then UI.pager(self, pages) end
end

Apps.register(Lager)
if READONLY then
    Kernel.onNet = function(id, msg)
        if msg.t ~= "SUM" or type(msg.items) ~= "table" then return end
        local kats, order = {}, {}
        if type(msg.kats) == "table" then
            for i = 1, math.min(#msg.kats, 40) do
                local k = msg.kats[i]
                local col = type(k) == "table" and tonumber(k.color)
                local valid = false
                for b = 0, 15 do if col == 2 ^ b then valid = true end end
                if valid and type(k.id) == "string" and #k.id <= 12 and type(k.name) == "string" then
                    kats[k.id] = { name = k.name:sub(1, 14), color = col }
                    order[k.id] = tonumber(k.n) or i
                end
            end
        end
        local items = {}
        for i = 1, math.min(#msg.items, 100) do
            local it = msg.items[i]
            if type(it) == "table" and type(it.d) == "string" and tonumber(it.n) then
                local c = (type(it.c) == "string" and (kats[it.c] or Lager.CAT[it.c])) and it.c or "SONST"
                items[#items + 1] = { d = it.d:sub(1, 24), n = tonumber(it.n), c = c }
            end
        end
        Lager.remote = { at = os.clock(), from = id, items = items, total = tonumber(msg.total) or 0, kinds = tonumber(msg.kinds) or 0,
                         slots = tonumber(msg.slots) or 0, used = tonumber(msg.used) or 0, invs = tonumber(msg.invs) or 0,
                         kats = kats, order = order }
        if Kernel.app == Lager then Kernel.invalidate() end
    end
end

-- ======================================================================
-- [9] WEB (Textbrowser)
-- ======================================================================
-- Laedt Seiten ueber die HTTP-Schnittstelle von CC: Tweaked und zeigt sie
-- als Text: keine Bilder, kein JavaScript, kein Layout. Links sind
-- hellblau und antippbar. Gut fuer Wikis, Dokus, Pastebin und Rohdateien.

-- ---------- HTML -> Text ----------
local Html = {}

Html.named = {
    amp = "&", lt = "<", gt = ">", quot = "\"", apos = "'", nbsp = " ",
    auml = "\228", ouml = "\246", uuml = "\252", Auml = "\196", Ouml = "\214", Uuml = "\220", szlig = "\223",
    eacute = "\233", egrave = "\232", agrave = "\224", aacute = "\225", ccedil = "\231", ntilde = "\241",
    copy = "\169", reg = "\174", deg = "\176", plusmn = "\177", times = "x", middot = "\183",
    laquo = "\171", raquo = "\187", ndash = "-", mdash = "-", hellip = "...", bull = "*",
    lsquo = "'", rsquo = "'", ldquo = "\"", rdquo = "\"", bdquo = "\"", rarr = "->", larr = "<-", euro = "EUR",
}

-- Unicode-Zeichen -> Zeichensatz von ComputerCraft (Latin-1).
Html.special = {
    [0x2013] = "-", [0x2014] = "-", [0x2212] = "-", [0x2010] = "-", [0x2011] = "-",
    [0x2018] = "'", [0x2019] = "'", [0x201A] = "'", [0x2032] = "'",
    [0x201C] = "\"", [0x201D] = "\"", [0x201E] = "\"", [0x2033] = "\"",
    [0x2026] = "...", [0x2022] = "*", [0x2192] = "->", [0x2190] = "<-", [0x20AC] = "EUR",
    [0x2009] = " ", [0x202F] = " ", [0x2002] = " ", [0x2003] = " ",
    [0x200B] = "", [0x200C] = "", [0x200D] = "", [0x200E] = "", [0x200F] = "", [0x2060] = "", [0xFEFF] = "",
}

function Html.char(cp)
    if Html.special[cp] then return Html.special[cp] end
    if cp == 160 then return " " end
    if cp == 9 or cp == 10 then return " " end
    if (cp >= 32 and cp < 127) or (cp > 160 and cp < 256) then return string.char(cp) end
    return "?"
end

-- UTF-8 -> Latin-1. Bytes, die kein gueltiges UTF-8 sind, bleiben stehen.
function Html.utf8(s)
    return (s:gsub("[\192-\247][\128-\191]*", function(seq)
        local lead = seq:byte(1)
        local need = (lead >= 240) and 3 or (lead >= 224) and 2 or 1
        if #seq - 1 ~= need then return nil end
        local cp = (need == 1) and (lead - 192) or (need == 2) and (lead - 224) or (lead - 240)
        for i = 2, #seq do cp = cp * 64 + (seq:byte(i) - 128) end
        return Html.char(cp)
    end))
end

function Html.entity(text)
    if not text:find("&", 1, true) then return text end
    return (text:gsub("&(#?%w+);", function(name)
        if name:sub(1, 1) == "#" then
            local cp = (name:sub(2, 2):lower() == "x") and tonumber(name:sub(3), 16) or tonumber(name:sub(2))
            return cp and Html.char(cp) or nil
        end
        return Html.named[name]
    end))
end

-- Macht aus einem Link (relativ oder absolut) eine vollstaendige Adresse.
function Html.resolve(base, href)
    href = Html.entity(href):gsub("^%s+", ""):gsub("%s+$", "")
    if href == "" or href:sub(1, 1) == "#" then return nil end
    local scheme = href:match("^(%a[%w+.-]*):")
    if scheme then
        scheme = scheme:lower()
        return (scheme == "http" or scheme == "https") and href or nil
    end
    local bscheme, bhost, bpath = base:match("^(https?)://([^/?#]+)([^?#]*)")
    if not bscheme then return nil end
    if href:sub(1, 2) == "//" then return bscheme .. ":" .. href end
    if href:sub(1, 1) == "/" then return bscheme .. "://" .. bhost .. href end
    if href:sub(1, 1) == "?" then return bscheme .. "://" .. bhost .. (bpath == "" and "/" or bpath) .. href end
    local path = (bpath:match("^(.*/)") or "/") .. href
    local tail = path:match("[?#].*$") or ""
    path = path:sub(1, #path - #tail)
    local parts = {}
    for seg in path:gmatch("[^/]+") do
        if seg == ".." then table.remove(parts) elseif seg ~= "." then parts[#parts + 1] = seg end
    end
    local out = "/" .. table.concat(parts, "/")
    if path:sub(-1) == "/" and #parts > 0 then out = out .. "/" end
    return bscheme .. "://" .. bhost .. out .. tail
end

-- Inhalt dieser Elemente wird uebersprungen.
Html.skip = { script = true, style = true, svg = true, noscript = true, template = true, iframe = true,
              nav = true, footer = true, select = true, button = true, head = true }
-- Zeilenumbruch davor und danach.
Html.breaks = { div = true, section = true, article = true, header = true, main = true, ul = true, ol = true,
                table = true, tr = true, dl = true, dt = true, dd = true, figure = true, figcaption = true,
                address = true, form = true, li = true, br = true, hr = true, caption = true }
-- Leerzeile davor und danach.
Html.paras = { p = true, h1 = true, h2 = true, h3 = true, h4 = true, h5 = true, h6 = true,
               blockquote = true, pre = true }

-- Zerlegt HTML in eine Liste von Bausteinen:
--   { text, sp, link, st, ind }  Wort (sp = Leerzeichen davor; st: 0 Text,
--                           1 Ueberschrift, 2 Unterueberschrift, 4 Aufzaehlungspunkt,
--                           5 Trennzeichen; ind = Einrueckung in Listen)
--   { nl = 1|2 }            Zeilenumbruch / Leerzeile
--   { pre = "..." }         Zeile mit festem Layout (Code)
--   { hr = true }           Trennlinie
-- Rueckgabe: Bausteine, Titel, Liste der Link-Adressen.
function Html.parse(html, base, pause)
    html = Html.utf8(html):gsub("\r", "")
    -- MediaWiki: "[Bearbeiten]"-Links und Fussnoten-Nummern stoeren nur.
    html = html:gsub('<span class="mw%-editsection".-</span>%s*</span>', "")
    html = html:gsub('<sup[^>]-class="[^"]-reference.-</sup>', "")
    local lower = html:lower()

    local title
    local _, te = lower:find("<title[^>]*>")
    if te then
        local ce = lower:find("</title", te, true)
        if ce then title = Html.entity(html:sub(te + 1, ce - 1)):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "") end
    end

    -- Nur den Hauptinhalt nehmen, wenn die Seite ihn kennzeichnet.
    local function cut(open, close)
        local s, e = lower:find(open)
        if not s then return false end
        local gt = lower:find(">", e, true)
        if not gt then return false end
        local c = lower:find(close, gt, true)
        html = html:sub(gt + 1, (c or #html + 1) - 1)
        lower = html:lower()
        return true
    end
    local _ = cut("<main[%s>]", "</main") or cut('id="mw%-content%-text"', 'class="printfooter"')
           or cut("<article[%s>]", "</article") or cut("<body[%s>]", "</body")

    local out, links = {}, {}
    local brk, space, bullet = 0, false, false
    local heading, hlevel, pre, preBuf, cells, depth = 0, 1, 0, "", 0, 0
    local link = nil

    local function newline()
        if brk > 0 then
            if #out > 0 then out[#out + 1] = { nl = brk } end
            brk, space = 0, false
        end
    end
    local function word(text, st)
        newline()
        local ind = math.min(depth, 4) * 2
        if bullet then
            out[#out + 1] = { text = "\7", st = 4, ind = ind }
            bullet, space = false, true
        end
        out[#out + 1] = { text = text, sp = space, link = link, ind = ind,
                          st = st or ((heading > 0) and ((hlevel <= 2) and 1 or 2) or 0) }
    end
    local function flushPre()
        if brk == 2 and #out > 0 then out[#out + 1] = { nl = 2 } end
        brk = 0
        out[#out + 1] = { pre = preBuf }
        preBuf = ""
    end
    local function emit(text)
        if text == "" then return end
        text = Html.entity(text)
        if pre > 0 then
            for piece, nl in text:gmatch("([^\n]*)(\n?)") do
                preBuf = preBuf .. piece
                if nl == "\n" then flushPre() end
            end
            return
        end
        if text:find("^%s") then space = true end
        local any = false
        for w in text:gmatch("%S+") do
            word(w)
            space, any = true, true
        end
        if any and not text:find("%s$") then space = false end
    end
    local function mark(n) if n > brk then brk = n end end

    local pos, len, steps = 1, #html, 0
    while pos <= len and #out < 40000 do
        local lt = lower:find("<", pos, true)
        emit(html:sub(pos, (lt or len + 1) - 1))
        if not lt then break end
        if lower:sub(lt, lt + 3) == "<!--" then
            local e = lower:find("-->", lt + 4, true)
            pos = e and (e + 3) or (len + 1)
        else
            local gt = lower:find(">", lt + 1, true)
            if not gt then break end
            local closing = lower:sub(lt + 1, lt + 1) == "/"
            local name = lower:match("^/?%s*([%a][%w]*)", lt + 1)
            pos = gt + 1
            if name and Html.skip[name] and not closing then
                local e = lower:find("</" .. name, gt, true)
                local e2 = e and lower:find(">", e, true)
                pos = e2 and (e2 + 1) or (len + 1)
            elseif name == "a" then
                if closing then
                    link = nil
                else
                    local tag = html:sub(lt, gt)
                    local href = tag:match('[hH][rR][eE][fF]%s*=%s*"([^"]*)"') or tag:match("[hH][rR][eE][fF]%s*=%s*'([^']*)'")
                              or tag:match("[hH][rR][eE][fF]%s*=%s*([^%s>]+)")
                    local url = href and Html.resolve(base, href)
                    if url then
                        links[#links + 1] = url
                        link = #links
                    else
                        link = nil
                    end
                end
            elseif name == "pre" then
                if closing then
                    if preBuf ~= "" then flushPre() end
                    pre = math.max(0, pre - 1)
                else
                    pre = pre + 1
                end
                mark(2)
            elseif name == "td" or name == "th" then
                if not closing then
                    if cells > 0 then
                        word("|", 5)
                        space = true
                    end
                    cells = cells + 1
                end
            elseif name == "ul" or name == "ol" then
                depth = closing and math.max(0, depth - 1) or (depth + 1)
                mark(1)
            elseif name and Html.paras[name] then
                mark(2)
                if name:sub(1, 1) == "h" and #name == 2 then
                    heading = closing and math.max(0, heading - 1) or (heading + 1)
                    if not closing then hlevel = tonumber(name:sub(2)) or 1 end
                end
            elseif name and Html.breaks[name] then
                mark(1)
                if name == "tr" then cells = 0 end
                if name == "li" and not closing then bullet = true end
                if name == "hr" then
                    newline()
                    out[#out + 1] = { hr = true }
                    mark(1)
                end
            end
            steps = steps + 1
            if pause and steps % 3000 == 0 then pause() end
        end
    end
    if preBuf ~= "" then flushPre() end
    return out, title, links
end

-- Reiner Text (Pastebin, Lua-Dateien, JSON): Zeile fuer Zeile.
function Html.plain(text)
    local out = {}
    text = Html.utf8(text):gsub("\r", "")
    for line in (text .. "\n"):gmatch("([^\n]*)\n") do
        out[#out + 1] = { pre = line }
        if #out >= 20000 then break end
    end
    return out
end

-- Bricht die Bausteine auf die Bildschirmbreite um.
-- Rueckgabe: Zeilen, jede eine Liste von { x, text, st, link }.
-- Listen-Eintraege bekommen eine haengende Einrueckung.
function Html.layout(tokens, width)
    local lines, cur, x = {}, {}, 0
    local function flush()
        if #cur > 0 then lines[#lines + 1] = cur end
        cur, x = {}, 0
    end
    for _, t in ipairs(tokens) do
        if t.nl then
            flush()
            if t.nl >= 2 and #lines > 0 and #lines[#lines] > 0 then lines[#lines + 1] = {} end
        elseif t.hr then
            flush()
            lines[#lines + 1] = { { x = 0, text = string.rep("\140", width), st = 5 } }
        elseif t.pre then
            flush()
            local s = t.pre:gsub("\t", "  ")
            if s == "" then
                lines[#lines + 1] = {}
            else
                for i = 1, #s, width do lines[#lines + 1] = { { x = 0, text = s:sub(i, i + width - 1), st = 3 } } end
            end
        else
            local text = t.text
            local ind = math.min(t.ind or 0, math.floor(width / 3))
            local start = (t.st == 4) and math.max(0, ind - 2) or ind
            if #cur == 0 and x == 0 then x = start end
            local need = (#cur > 0 and t.sp) and 1 or 0
            if #cur > 0 and x + need + #text > width then
                flush()
                x, need = ind, 0
            end
            while #text > width - x do
                lines[#lines + 1] = { { x = x, text = text:sub(1, width - x), st = t.st, link = t.link } }
                text = text:sub(width - x + 1)
                cur, x = {}, ind
            end
            local prev = cur[#cur]
            if prev and need == 1 and prev.st == t.st and prev.link == t.link then
                prev.text = prev.text .. " " .. text   -- gleiche Art: zu einem Stueck verbinden
            elseif #text > 0 then
                cur[#cur + 1] = { x = x + need, text = text, st = t.st, link = t.link }
            end
            x = x + need + #text
        end
    end
    flush()
    return lines
end

-- ---------- Browser ----------
-- WEB v2 (OS 1.1.0): Startseite mit Suchfeld wie bei Google, Ergebnisliste,
-- Leseansicht mit Rand, Verlauf (vor/zurueck), Lesezeichen und letzte Suchen.
local Web = {
    id = "web", title = "WEB", order = 6,
    page = nil,         -- angezeigte Seite (nil = Startseite); kind = "doc" | "search"
    loading = nil,      -- { url, back, search } solange eine Anfrage laeuft
    error = nil, input = nil, shift = false,
    scroll = 1, back = {}, fwd = {}, cancelled = {}, bookmarks = {}, recent = {}, marks = { page = 1 },
    engine = "web", resPage = 1,
    dbFile = "/gts/web.db", maxSize = 1500000,
}

-- Prozent-Kodierung rueckgaengig ("%C3%A4" -> Bytes, "+" -> Leerzeichen)
function Web.urlDecode(s)
    return (tostring(s):gsub("+", " "):gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

-- HTML-Schnipsel -> einfacher Text (Ergebnisse, Auszuege)
function Web.stripTags(s)
    s = Html.utf8(tostring(s or "")):gsub("<[^>]*>", "")
    return (Html.entity(s):gsub("%s+", " "):gsub("^ ", ""):gsub(" $", ""))
end

-- Sichtbare Kurzform einer Adresse: "minecraft.wiki > w > Ancient_City"
function Web.niceUrl(u)
    local host, path = tostring(u):match("^%a+://([^/?#]+)([^?#]*)")
    if not host then return tostring(u) end
    host = host:gsub("^www%.", "")
    local parts = { host }
    for seg in path:gmatch("[^/]+") do parts[#parts + 1] = Web.urlDecode(seg) end
    return Html.utf8(table.concat(parts, " \187 "))
end

-- ---------- Suchmaschinen ----------
-- DuckDuckGo liefert eine reine HTML-Seite (ohne JavaScript); Wikipedia und
-- das Minecraft Wiki haben eine Such-Schnittstelle (JSON).
function Web.parseDDG(body)
    local out, pos = {}, 1
    while #out < 30 do
        local s, e, tag = body:find('(<a[^>]-class="result__a"[^>]*>)', pos)
        if not s then break end
        local ce = body:find("</a>", e, true) or e
        local nxt = body:find('class="result__a"', ce, true) or #body
        local seg = body:sub(ce, nxt)
        pos = ce + 1
        local href = Html.entity(tag:match('href="([^"]*)"') or "")
        local real = href:match("[?&]uddg=([^&]+)")
        local url = real and Web.encHigh(Web.urlDecode(real)) or href
        if url:sub(1, 2) == "//" then url = "https:" .. url end
        if url:find("^https?://") and not url:find("duckduckgo%.com/y%.js") then
            out[#out + 1] = { t = Web.stripTags(body:sub(e + 1, ce - 1)), u = url,
                              s = Web.stripTags(seg:match('class="result__snippet"[^>]*>(.-)</a>') or "") }
        end
    end
    return out
end

function Web.wikiParser(base)
    return function(body)
        local ok, data = pcall(textutils.unserializeJSON, body)
        local hits = ok and type(data) == "table" and type(data.query) == "table" and data.query.search
        local out = {}
        for _, r in ipairs(type(hits) == "table" and hits or {}) do
            if type(r) == "table" and type(r.title) == "string" then
                local path = r.title:gsub(" ", "_"):gsub("[^%w%-%._~/:%(%),']", function(c) return ("%%%02X"):format(c:byte()) end)
                out[#out + 1] = { t = Html.utf8(r.title), u = base .. path,
                                  s = Web.stripTags(r.snippet) }
            end
        end
        return out
    end
end

function Web.wikiApi(api)
    return function(q)
        return api .. "?action=query&list=search&format=json&utf8=1&srlimit=30&srsearch=" .. textutils.urlEncode(q)          -- macht aus Latin-1 selbst UTF-8
    end
end

Web.engines = {
    { id = "web", label = "WEB", short = "WEB", name = "Web (DuckDuckGo)", parse = Web.parseDDG,
      url = function(q) return "https://html.duckduckgo.com/html/?q=" .. textutils.urlEncode(q) end },
    { id = "wiki", label = "WIKIPEDIA", short = "WIKI", name = "Wikipedia", parse = Web.wikiParser("https://de.wikipedia.org/wiki/"),
      url = Web.wikiApi("https://de.wikipedia.org/w/api.php") },
    { id = "mc", label = "MC WIKI", short = "MC", name = "Minecraft Wiki", parse = Web.wikiParser("https://de.minecraft.wiki/w/"),
      url = Web.wikiApi("https://de.minecraft.wiki/api.php") },
}
Web.engineById = {}
for _, en in ipairs(Web.engines) do Web.engineById[en.id] = en end

-- Schnellzugriff auf der Startseite
Web.quick = {
    { label = "ATM10 GUIDES", short = "ATM10", url = "https://allthemods.github.io/alltheguides/atm10/" },
    { label = "CC DOKU", short = "DOKU", url = "https://tweaked.cc/" },
    { label = "PASTEBIN", short = "PASTE", ask = "Pastebin - Code (z.B. UzGHLbNC):",
      url = function(q) return "https://pastebin.com/raw/" .. q:gsub("[^%w]", "") end },
}

-- ---------- Speichern (Lesezeichen, letzte Suchen, Suchmaschine) ----------
function Web:loadMarks()
    local t = Store.load(self.dbFile)
    if not t then return end
    local marks = t.marks or t                      -- alte Fassung: nur eine Liste
    for _, b in ipairs(type(marks) == "table" and marks or {}) do
        if type(b) == "table" and type(b.u) == "string" and #self.bookmarks < 30 then
            self.bookmarks[#self.bookmarks + 1] = { u = b.u, t = type(b.t) == "string" and b.t or b.u }
        end
    end
    for _, q in ipairs(type(t.recent) == "table" and t.recent or {}) do
        if type(q) == "string" and #self.recent < 8 then self.recent[#self.recent + 1] = q end
    end
    if Web.engineById[t.engine or ""] then self.engine = t.engine end
end

-- Die Datei bleibt eine Liste (so liest sie auch eine aeltere Fassung nach einem
-- Rueckschritt), dazu stehen letzte Suchen und Suchmaschine als Felder.
function Web:saveMarks()
    local t = { recent = self.recent, engine = self.engine }
    for i, b in ipairs(self.bookmarks) do t[i] = b end
    Store.save(self.dbFile, t)
end

-- Eingabe: Adresse oder Suchbegriff?
function Web.isUrl(text)
    text = tostring(text):gsub("^%s+", ""):gsub("%s+$", "")
    if text:find("^%a[%w+.-]*://") then return true end
    if text:find("%s") or text:find("%.%.") then return false end
    local host = text:match("^([^/?#]+)")
    return host ~= nil and host:find("^[%w%-%.]+%.%a%a+$") ~= nil       -- endet auf .de, .cc, .wiki ...
end

-- Eingaben sind Latin-1 (Zeichensatz von CC), Suchmaschinen erwarten UTF-8.
function Web.utf8(s)
    return (tostring(s):gsub("[\128-\255]", function(c)
        local b = c:byte()
        return string.char(192 + math.floor(b / 64), 128 + b % 64)
    end))
end

-- Adressen bleiben ASCII: Bytes ab 128 werden %XX (UTF-8). latin = Text aus
-- dem CC-Zeichensatz (getippt oder aus einer Seite), sonst schon UTF-8.
function Web.encHigh(s, latin)
    s = tostring(s)
    if latin then s = Web.utf8(s) end
    return (s:gsub("[%c\128-\255]", function(c) return ("%%%02X"):format(c:byte()) end))
end

function Web:submit(text)
    text = tostring(text):gsub("^%s+", ""):gsub("%s+$", "")
    if text == "" then return end
    if Web.isUrl(text) then return self:go(text) end
    self:search(text, self.engine)
end

-- Suche starten (Ergebnis kommt im Dienst an). fallback = Wikipedia, falls
-- die Websuche nicht antwortet oder nichts Lesbares liefert.
function Web:search(q, engineId, isBack)
    local en = Web.engineById[engineId] or Web.engines[1]
    if not isBack then                  -- vor/zurueck aendert die Liste nicht
        self.engine = en.id
        for i, r in ipairs(self.recent) do if r == q then table.remove(self.recent, i) break end end
        table.insert(self.recent, 1, q)
        while #self.recent > 8 do table.remove(self.recent) end
        self:saveMarks()
    end
    self:go(en.url(q), isBack, { q = q, engine = en.id })
end

-- Laedt eine Adresse. Die Antwort kommt spaeter als Event (siehe service).
function Web:go(url, isBack, search)
    url = tostring(url):gsub("^%s+", ""):gsub("%s+$", "")
    if url == "" then return end
    if not url:find("^%a[%w+.-]*://") then url = "https://" .. url end
    url = Web.encHigh(url:gsub("#.*$", ""):gsub(" ", "%%20"), true)
    if self.loading and self.loading.url == url then return end
    if not http then
        self.error = "HTTP ist auf diesem Server abgeschaltet."
        return
    end
    if self.loading then self.cancelled[self.loading.url] = true end
    self.error, self.input = nil, nil
    self.loading = { url = url, back = isBack, search = search }
    local ok, err = http.request({ url = url, binary = true })
    if not ok then
        self.loading = nil
        self.error = "Adresse abgelehnt: " .. tostring(err)
    end
end

-- Eintrag fuer vor/zurueck: Adresse, Stelle und (bei Suchen) Begriff
function Web:here()
    local p = self.page
    if not p then return { start = true } end
    return { url = p.url, scroll = self.scroll, search = p.search, resPage = self.resPage }
end

function Web:open(entry, isBack)
    if entry.start then
        self.page, self.scroll = nil, 1
    elseif entry.search then
        self.restore, self.resRestore = entry.scroll, entry.resPage
        self:search(entry.search.q, entry.search.engine, true)
    else
        self.restore = entry.scroll
        self:go(entry.url, true)
    end
end

function Web:goBack()
    if self.loading then
        self.cancelled[self.loading.url] = true
        self.loading = nil
    elseif self.error then
        self.error = nil
    elseif #self.back > 0 then
        self.fwd[#self.fwd + 1] = self:here()
        self:open(table.remove(self.back), true)
    elseif self.page then
        self.fwd[#self.fwd + 1] = self:here()
        self.page, self.scroll = nil, 1
    end
end

function Web:goForward()
    if self.loading or #self.fwd == 0 then return end
    self.back[#self.back + 1] = self:here()
    self:open(table.remove(self.fwd), true)
end

function Web:home()
    if self.loading then self.cancelled[self.loading.url] = true end
    if self.page then self.back[#self.back + 1] = self:here() end
    self.page, self.loading, self.error, self.scroll, self.fwd = nil, nil, nil, 1, {}
end

-- Antwort verarbeiten: Suchergebnisse oder Seite (HTML zerlegen bzw. Text).
function Web:receive(req, handle)
    local raw = handle.readAll() or ""
    local headers = handle.getResponseHeaders and handle.getResponseHeaders() or {}
    pcall(handle.close)
    local page
    if req.search then
        local en = Web.engineById[req.search.engine] or Web.engines[1]
        local ok, results = pcall(en.parse, raw:sub(1, self.maxSize))
        results = ok and results or {}
        if #results == 0 and en.id == "web" and not req.search.fallback then
            -- Websuche blockiert oder leer: Wikipedia fragen
            local q = req.search.q
            self:go(Web.engineById.wiki.url(q), req.back, { q = q, engine = "wiki", fallback = true })
            return "again"
        end
        page = { kind = "search", url = req.url, search = req.search, results = results,
                 title = "Suche: " .. Html.utf8(req.search.q), note = req.search.fallback and "Websuche gerade nicht erreichbar - Ergebnisse aus Wikipedia" or nil }
    else
        local ctype = ""
        for k, v in pairs(headers) do
            if type(k) == "string" and k:lower() == "content-type" then ctype = tostring(v):lower() end
        end
        local head = raw:sub(1, 400):lower()
        local isHtml = ctype:find("html", 1, true) or head:find("<!doctype html", 1, true) or head:find("<html", 1, true)
        local body = (#raw > self.maxSize) and raw:sub(1, self.maxSize) or raw
        page = { kind = "doc", url = req.url, raw = raw, plain = not isHtml, links = {} }
        if isHtml then
            page.tokens, page.title, page.links = Html.parse(body, req.url, function()
                os.queueEvent("gts_pause")
                os.pullEvent("gts_pause")
            end)
        else
            page.tokens = Html.plain(body)
        end
        local words = 0
        for _, t in ipairs(page.tokens) do if t.text then words = words + 1 end if words > 5 then break end end
        if isHtml and words <= 5 and raw:find("<script", 1, true) then
            page.needsJs = true       -- (fast) leer: die Seite baut sich mit JavaScript auf
        end
        if #page.tokens == 0 then page.tokens = { { pre = "(Kein Text auf dieser Seite.)" } } end
        if #raw > self.maxSize or #page.tokens >= 20000 then
            page.tokens[#page.tokens + 1] = { nl = 2 }
            page.tokens[#page.tokens + 1] = { pre = "[Seite gekuerzt]" }
        end
    end
    if not req.back then
        if self.page then
            self.back[#self.back + 1] = self:here()
            while #self.back > 30 do table.remove(self.back, 1) end
        end
        self.fwd = {}
    end
    self.page = page
    self.scroll = req.back and self.restore or 1
    self.resPage = req.back and self.resRestore or 1
    self.restore, self.resRestore = nil, nil
end

-- Hintergrund-Dienst: wartet auf HTTP-Antworten (die Oberflaeche bleibt frei).
function Web:service()
    while true do
        local ev, url, a, b = os.pullEvent()
        if ev == "http_success" or ev == "http_failure" then
            local req = self.loading
            if req and req.url == url then
                self.loading = nil
                if ev == "http_success" then
                    local ok, err = pcall(self.receive, self, req, a)
                    if not ok then self.error = "Seite nicht lesbar: " .. tostring(err) end
                else
                    local code = type(b) == "table" and b.getResponseCode and b.getResponseCode()
                    if type(b) == "table" and b.close then pcall(b.close) end
                    if req.search and req.search.engine == "web" and not req.search.fallback then
                        self:go(Web.engineById.wiki.url(req.search.q), req.back, { q = req.search.q, engine = "wiki", fallback = true })
                    else
                        self.error = "Laden fehlgeschlagen: " .. tostring(a) .. (code and (" (HTTP " .. code .. ")") or "")
                    end
                end
                Kernel.invalidate()
            elseif self.cancelled[url] then
                self.cancelled[url] = nil
                local h = (ev == "http_success") and a or b
                if type(h) == "table" and h.close then pcall(h.close) end
            end
        end
    end
end

function Web:save()
    local p = self.page
    if not (p and p.raw) then return end
    local name = p.url:gsub("[?#].*$", ""):match("([^/]+)/?$") or "seite"
    name = name:gsub("[^%w%._%-]", "_"):sub(1, 30)
    -- Lua-Dateien und Pastebin-Code landen direkt bei den LUA APPS, alles andere in /downloads.
    local dir = "/downloads"
    if p.plain and (name:find("%.lua$") or p.url:find("pastebin%.com/raw/")) then
        dir = CONFIG.scriptDir
        if not name:find("%.lua$") then name = name .. ".lua" end
    elseif not name:find(".", 1, true) then
        name = name .. (p.plain and ".txt" or ".html")
    end
    local ok = pcall(function()
        fs.makeDir(dir)
        local f = fs.open(fs.combine(dir, name), "wb")
        if not f then error("x", 0) end
        f.write(p.raw)
        f.close()
    end)
    Kernel.notify(ok and ("Gespeichert: " .. dir .. "/" .. name) or "Speichern fehlgeschlagen (Speicher voll?)",
                  ok and colors.lime or colors.red)
end

function Web:isMarked()
    local p = self.page
    if not p then return false end
    for _, b in ipairs(self.bookmarks) do if b.u == p.url then return true end end
    return false
end

-- Merken bzw. wieder vergessen (Stern)
function Web:mark()
    local p = self.page
    if not p or p.kind == "search" then return end
    for i, b in ipairs(self.bookmarks) do
        if b.u == p.url then
            table.remove(self.bookmarks, i)
            self:saveMarks()
            Kernel.notify("Lesezeichen entfernt", colors.lightGray)
            return
        end
    end
    if #self.bookmarks >= 30 then
        Kernel.notify("Lesezeichen voll (30)", colors.red)
        return
    end
    self.bookmarks[#self.bookmarks + 1] = { u = p.url, t = (p.title and p.title ~= "") and p.title:sub(1, 40) or p.url }
    self:saveMarks()
    Kernel.notify("Lesezeichen gemerkt")
end

-- Eingabezeile (Adresse, Suchbegriff). done(text) wird bei OK aufgerufen.
function Web:ask(label, text, done)
    self.input = { label = label, text = text or "", done = done }
    self.shift = false
end

function Web:insert(text)
    local i = self.input
    if not i then return end
    i.text = (i.text .. text:gsub("[^\32-\255]", "")):sub(1, 200)
end

function Web:key(action)
    local i = self.input
    if not i then return end
    if action == "backspace" then
        i.text = i.text:sub(1, -2)
    elseif action == "enter" then
        self.input = nil
        if i.text:find("%S") then i.done(i.text) end
    end
end

function Web:lines(width)
    local p = self.page
    if p.width ~= width then
        p.layout, p.width = Html.layout(p.tokens, width), width
    end
    return p.layout
end

function Web:move(delta)
    self.scroll = math.max(1, self.scroll + delta)   -- obere Grenze setzt draw()
end

function Web:onScroll(dir)
    if self.input or not self.page then return end
    if self.page.kind == "search" then
        self.resPage = math.max(1, self.resPage + dir)
    else
        self:move(dir * 3)
    end
end
function Web:onChar(ch)
    if self.input then return self:insert(ch) end
    -- Tippen auf der Startseite beginnt gleich eine Suche
    if not self.page and not self.loading then self:ask("Suchen oder Adresse:", ch, function(q) self:submit(q) end) end
end
function Web:onPaste(text) self:insert(text) end

function Web:onKey(code)
    if self.input then
        if code == keys.enter or code == keys.numPadEnter then self:key("enter")
        elseif code == keys.backspace then self:key("backspace") end
        return
    end
    if not self.page then return end
    if self.page.kind == "search" then          -- Treffer: Pfeile blaettern die Seiten
        if code == keys.up or code == keys.pageUp or code == keys.left then self.resPage = math.max(1, self.resPage - 1)
        elseif code == keys.down or code == keys.pageDown or code == keys.right then self.resPage = self.resPage + 1
        elseif code == keys.home then self.resPage = 1
        elseif code == keys.backspace then self:goBack() end
        return
    end
    local page = self.rows or 10
    if code == keys.up then self:move(-1)
    elseif code == keys.down then self:move(1)
    elseif code == keys.pageUp then self:move(-(page - 1))
    elseif code == keys.pageDown then self:move(page - 1)
    elseif code == keys.home then self.scroll = 1
    elseif code == keys["end"] then self.scroll = 1000000
    elseif code == keys.backspace then self:goBack() end
end

function Web:drawInput()
    local h, narrow = Kernel.h, UI.narrow()
    local i = self.input
    local top = UI.header("WEB", not narrow and "Eingabe" or nil)
    UI.prompt{ y = top, title = i.label, text = i.text, hint = "Enter = OK",
               onOk = function() self:key("enter") end, onCancel = function() self.input = nil end }
    if Kernel.display.touch then OSK.draw(h - OSK.height(), self) end
end

-- Schriftzug "GTS" (Pixel wie das Logo) + "Suche"
function Web.drawLogo(y)
    local S = Logo.sizes[3]
    local word = { { "G", 0 }, { "T", S.W + S.g }, { "S", 2 * (S.W + S.g) } }
    local pw = 3 * S.W + 2 * S.g
    local cols, rows = math.ceil((pw + 2) / 2), math.ceil(S.H / 3)
    local total = cols + 1 + 5
    local x0 = math.floor((Kernel.w - total) / 2) + 1
    UI.pixels(x0, y, cols, rows, function(px, py)
        local x, yy = px - 2, py - 1
        if yy >= 0 and yy < S.H then
            for _, g in ipairs(word) do
                local gx = x - g[2]
                if gx >= 0 and gx < S.W and Logo.glyphs[g[1]](gx, yy, S) then
                    return (yy < S.H * 0.45) and colors.white or colors.lightGray
                end
            end
        end
        return colors.black
    end)
    UI.text(x0 + cols + 1, y + rows - 1, "Suche", colors.lightGray)
    UI.text(x0 + cols + 6, y + rows - 1, "\7", colors.lime)
    return y + rows
end

-- Startseite: ruhig und mittig - Suchfeld, Suchmaschine, letzte Suchen,
-- Schnellzugriff und Lesezeichen.
function Web:drawStart()
    local w, h, bh, narrow = Kernel.w, Kernel.h, UI.bh(), UI.narrow()
    local y = narrow and 2 or ((h >= 20) and 3 or 2)
    if not narrow and h >= 16 then y = Web.drawLogo(y) + 1 else
        UI.center(y, "GTS Suche", colors.white)
        y = y + 2
    end
    -- Suchfeld
    local fw = narrow and (w - 2) or math.min(w - 8, 64)
    local fx = math.floor((w - fw) / 2) + 1
    UI.fill(fx, y, fw, 1, colors.brown)
    UI.text(fx + 1, y, "\187", colors.lime, colors.brown)
    UI.text(fx + 3, y, ((fw >= 36) and "Suchen oder Adresse eingeben ..." or "Suchen / Adresse ..."):sub(1, fw - 4), colors.lightGray, colors.brown)
    UI.hit(fx, y, fw, 1, function() self:ask("Suchen oder Adresse:", "", function(q) self:submit(q) end) end)
    y = y + 2
    -- Suchmaschine waehlen (gilt fuer das Suchfeld)
    local chips = {}
    for _, en in ipairs(Web.engines) do
        chips[#chips + 1] = { text = narrow and en.short or en.label, h = 1, style = (self.engine == en.id) and "primary" or nil,
                              onClick = function() self.engine = en.id self:saveMarks() end }
    end
    local cw = -1
    for _, c in ipairs(chips) do cw = cw + #c.text + 3 end
    y = UI.flow(chips, math.max(2, math.floor((w - cw) / 2) + 1), y, w - 1) + 1
    if y > h - bh - 1 then return end
    -- Letzte Suchen
    if #self.recent > 0 then
        local label = narrow and "" or "Zuletzt:  "
        local x = math.max(2, fx)
        UI.text(x, y, label, colors.lightGray)
        x = x + #label
        for _, q in ipairs(self.recent) do
            local shown = Html.utf8(q)
            if x + #shown > w - 1 then break end
            UI.text(x, y, shown, colors.white)
            UI.hit(x, y, #shown, 1, function() self:search(q, self.engine) end)
            x = x + #shown
            if x + 3 <= w - 1 then UI.text(x + 1, y, "\183", colors.brown) end
            x = x + 3
        end
        y = y + 2
    end
    if y > h - bh - 1 then return end
    -- Schnellzugriff
    local quick = {}
    for _, qd in ipairs(Web.quick) do
        quick[#quick + 1] = { text = narrow and qd.short or qd.label, h = 1, onClick = function()
            if qd.ask then
                self:ask(qd.ask, "", function(q) self:go(qd.url(q)) end)
            else
                self:go(qd.url)
            end
        end }
    end
    if not narrow then     -- schmal: Adressen gehen auch ins Suchfeld
        quick[#quick + 1] = { text = "ADRESSE", h = 1, onClick = function() self:ask("Adresse:", "", function(q) self:go(q) end) end }
    end
    y = UI.flow(quick, math.max(2, fx), y, w - 1) + 1
    if y + 1 > h - bh - 1 then return end
    -- Lesezeichen
    UI.section(math.max(2, fx), y, "LESEZEICHEN (" .. #self.bookmarks .. ")", (narrow and w - 2) or (fw - 1))
    if #self.bookmarks == 0 then
        if y + 2 <= h - bh - 1 then
            UI.text(math.max(2, fx), y + 2, (narrow and "Auf einer Seite: \4" or "Auf einer Seite \4 MERKEN tippen."):sub(1, w - 2), colors.lightGray)
        end
        return
    end
    local lx, lw = math.max(1, fx - 1), narrow and w or (fw + 2)
    UI.list(self.marks, self.bookmarks, y + 2, 2, function(b, by)
        UI.card(lx, by, lw, 1)
        local tx, xr = lx + 2, lx + lw - 2
        local bx = UI.button{ x = xr - 2, y = by, w = 3, h = 1, text = "X", style = "ghost", fg = colors.red,
                              confirm = "web:del:" .. b.u, onClick = function()
                                  for n, other in ipairs(self.bookmarks) do
                                      if other == b then table.remove(self.bookmarks, n) break end
                                  end
                                  self:saveMarks()
                              end } - 4
        UI.text(tx - 1, by, "\4", colors.yellow)
        UI.text(tx + 1, by, b.t:sub(1, bx - tx - 1), colors.white)
        local host = b.u:match("^%a+://([^/]+)") or ""
        if not narrow and #b.t + #host + 4 <= bx - tx then UI.text(tx + #b.t + 3, by, host, colors.lightGray) end
        UI.hit(tx - 2, by, bx - tx + 2, 1, function() self:go(b.u) end)
        UI.surface = colors.black
    end)
end

-- Kopf mit vor/zurueck, neu laden, Stern; darunter die Adress-/Suchzeile.
-- Rueckgabe: erste Zeile fuer den Inhalt.
function Web:drawBar()
    local w, narrow = Kernel.w, UI.narrow()
    local p = self.page
    local busy = self.loading or self.error
    local title = p and p.title or nil
    if self.loading then title = "Lade ..." elseif self.error then title = "Fehler" end
    local marked = self:isMarked()
    local acts = {
        { text = "\17", w = narrow and 2 or 3, onClick = function() self:goBack() end },
        { text = "\16", w = narrow and 2 or 3, disabled = #self.fwd == 0 or self.loading ~= nil, onClick = function() self:goForward() end },
    }
    if not narrow then           -- schmal ist kein Platz: dort neu laden ueber die Adresszeile
        acts[#acts + 1] = { text = "NEU LADEN", disabled = not p or busy, onClick = function()
            self.fwd = {}
            self:open(self:here(), true)
        end }
    end
    acts[#acts + 1] = { text = narrow and "\4" or (marked and "\4 GEMERKT" or "\4 MERKEN"), w = narrow and 3 or nil,
                        fg = marked and colors.yellow or nil, disabled = not p or busy or p.kind == "search", onClick = function() self:mark() end }
    acts[#acts + 1] = { text = "START", onClick = function() self:home() end }
    if p and p.raw then
        acts[#acts + 1] = { text = narrow and "SICH" or "SICHERN", disabled = busy, onClick = function() self:save() end }
    end
    local top = UI.header("WEB", title or "", acts)
    -- Such-/Adresszeile (antippen = aendern)
    local ay = top - 1
    local shown, edit
    if self.loading then
        shown = self.loading.search and Html.utf8(self.loading.search.q) or self.loading.url
    elseif p and p.kind == "search" then
        shown, edit = Html.utf8(p.search.q), p.search.q
    else
        shown = p and p.url or ""
    end
    edit = edit or shown
    UI.fill(1, ay, w, 1, colors.brown)
    UI.text(2, ay, "\187", colors.lime, colors.brown)
    UI.text(4, ay, shown:sub(1, w - 5), colors.white, colors.brown)
    UI.hit(1, ay, w, 1, function()
        self:ask("Suchen oder Adresse:", edit, function(q) self:submit(q) end)
    end)
    return ay + 1
end

-- Ergebnisliste wie bei einer Suchmaschine: Titel, Adresse, Auszug.
function Web:drawResults(y0)
    local w, h, bh, narrow = Kernel.w, Kernel.h, UI.bh(), UI.narrow()
    local p = self.page
    local en = Web.engineById[p.search.engine] or Web.engines[1]
    local cw = narrow and (w - 2) or math.min(w - 4, 90)
    local x0 = narrow and 2 or 3
    local y = y0
    -- Suchmaschine fuer denselben Begriff wechseln
    local chips = {}
    for _, e in ipairs(Web.engines) do
        chips[#chips + 1] = { text = narrow and e.short or e.label, h = 1, style = (e.id == en.id) and "primary" or nil,
                              onClick = function() if e.id ~= en.id then self:search(p.search.q, e.id) end end }
    end
    y = UI.flow(chips, x0, y, w - 1)
    if p.note then
        UI.text(x0, y, p.note:sub(1, w - x0), colors.orange)
        y = y + 1
    end
    local res = p.results
    if #res == 0 then
        UI.text(x0, y + 1, ("Keine Treffer fuer \"" .. Html.utf8(p.search.q) .. "\"."):sub(1, w - x0), colors.white)
        UI.text(x0, y + 2, ("Andere Woerter oder andere Suchmaschine probieren."):sub(1, w - x0), colors.lightGray)
        return
    end
    UI.text(x0, y, (#res .. " Ergebnisse \183 " .. en.name):sub(1, w - x0), colors.lightGray)
    y = y + 2
    -- je Ergebnis: Titel, Adresse, 1-2 Zeilen Auszug, Leerzeile
    local bottom = h - bh - 1
    local snipLines = (bottom - y >= 16) and 2 or 1
    local per = math.max(1, math.floor((bottom - y + 1) / (3 + snipLines)))
    local pages = math.max(1, math.ceil(#res / per))
    self.resPage = math.max(1, math.min(self.resPage or 1, pages))
    for i = 1, per do
        local r = res[(self.resPage - 1) * per + i]
        if not r then break end
        UI.text(x0, y, r.t:sub(1, cw), colors.lightBlue)
        UI.text(x0, y + 1, Web.niceUrl(r.u):sub(1, cw), colors.green)
        local lines = UI.wrap(r.s ~= "" and r.s or "-", cw)
        for k = 1, snipLines do
            if lines[k] then
                local t = lines[k]
                if k == snipLines and lines[k + 1] then t = t:sub(1, cw - 3) .. "..." end
                UI.text(x0, y + 1 + k, t, colors.lightGray)
            end
        end
        local url = r.u
        UI.hit(x0, y, cw, 2 + snipLines, function() self:go(url) end)
        y = y + 3 + snipLines
    end
    -- Seiten wie bei Google:  <  1 2 3  >
    if pages > 1 then
        local by = h - bh
        -- nur so viele Seitenzahlen wie passen, um die aktuelle herum
        local room = w - 14
        local a, b = self.resPage, self.resPage
        local len = #tostring(a)
        local grew = true
        while grew do
            grew = false
            if b < pages and len + 1 + #tostring(b + 1) <= room then b = b + 1 len = len + 1 + #tostring(b) grew = true end
            if a > 1 and len + 1 + #tostring(a - 1) <= room then a = a - 1 len = len + 1 + #tostring(a) grew = true end
        end
        local x = math.floor((w - (len + 12)) / 2) + 1
        UI.button{ x = x, y = by, w = 5, text = "\17", disabled = self.resPage <= 1, onClick = function() self.resPage = self.resPage - 1 end }
        local nx = x + 6
        for i = a, b do
            local on = (i == self.resPage)
            UI.text(nx, by, tostring(i), on and colors.white or colors.lightBlue)
            if on then UI.text(nx, by + ((bh >= 2) and 1 or 0), (bh >= 2) and "\131" or "", colors.lime) end
            UI.hit(nx, by, #tostring(i), bh, function() self.resPage = i end)
            nx = nx + #tostring(i) + 1
        end
        UI.button{ x = nx, y = by, w = 5, text = "\16", disabled = self.resPage >= pages, onClick = function() self.resPage = self.resPage + 1 end }
    end
end

function Web:draw()
    if self.input then return self:drawInput() end
    local w, h, bh = Kernel.w, Kernel.h, UI.bh()
    local narrow = UI.narrow()
    if not self.page and not self.loading and not self.error then return self:drawStart() end
    local y0 = self:drawBar()
    if self.loading then
        UI.text(3, y0 + 1, (self.loading.search and "Suche ..." or "Lade ..."), colors.yellow)
        UI.button{ x = 3, y = y0 + 3, w = 11, text = "ABBRUCH", style = "danger", onClick = function() self:goBack() end }
        return
    end
    if self.error then
        local y = y0 + 1
        for _, line in ipairs(UI.wrap(self.error, w - 4)) do
            UI.text(3, y, line, colors.red)
            y = y + 1
        end
        UI.text(3, y + 1, ("\17 bringt dich zurueck."):sub(1, w - 4), colors.lightGray)
        return
    end
    local p = self.page
    if p.kind == "search" then return self:drawResults(y0) end
    if p.needsJs then
        UI.empty(y0 + 2, "Seite braucht JavaScript",
                 "Apps wie YouTube oder Discord laufen im Text-Browser nicht. Tipp: dasselbe suchen und eine Wiki- oder Doku-Seite nehmen.")
        return
    end

    -- Leseansicht: eine ruhige Spalte mit Rand (am Monitor hoechstens 90 breit)
    local bottom = h - bh - 1
    local rows = bottom - y0 + 1
    local tw = narrow and (w - 1) or math.min(w - 4, 90)
    local ox = narrow and 0 or math.floor((w - tw) / 2)
    local lines = self:lines(tw)
    self.rows = rows
    self.scroll = math.max(1, math.min(self.scroll, math.max(1, #lines - rows + 1)))
    local first = self.scroll
    local palette = { [0] = colors.white, [1] = colors.lime, [2] = colors.white, [3] = colors.lightGray,
                      [4] = colors.lime, [5] = colors.brown }
    for r = 0, rows - 1 do
        local line = lines[first + r]
        if not line then break end
        for _, seg in ipairs(line) do
            UI.text(1 + ox + seg.x, y0 + r, seg.text, seg.link and colors.lightBlue or palette[seg.st] or colors.white)
        end
        -- Ueberschriften: kleiner Akzent-Strich am Rand
        if not narrow and line[1] and line[1].st == 1 and ox >= 2 then UI.text(ox - 1, y0 + r, "\149", colors.lime) end
    end
    -- Link antippen. Trifft man knapp daneben in eine Luecke, zaehlt der
    -- naechste Link in der Zeile (bis 2 Zeichen Abstand).
    UI.hit(1, y0, w, rows, function(cx, cy)
        local line = lines[first + cy - y0]
        if not line then return end
        local best, bestD
        for _, seg in ipairs(line) do
            local a, b = seg.x + 1 + ox, seg.x + ox + #seg.text
            local d = (cx < a) and (a - cx) or ((cx > b) and (cx - b) or 0)
            if d == 0 and not seg.link then return end   -- normaler Text getroffen
            if seg.link and (not bestD or d < bestD) then best, bestD = seg, d end
        end
        if best and bestD <= 2 then self:go(self.page.links[best.link]) end
    end)

    -- Fusszeile: Position und Blaettern
    local by = h - bh
    local last = math.min(#lines, first + rows - 1)
    local pct = math.floor(last * 100 / math.max(1, #lines))
    UI.text(2, by, (narrow and "" or "Seite ") .. pct .. " %", colors.lightGray)
    if bh >= 2 then UI.bar(2, by + 1, math.min(20, w - 18), last / math.max(1, #lines), colors.lime) end
    UI.button{ x = w - 13, y = by, w = 6, text = "\30", disabled = first <= 1,
               onClick = function() self:move(-(rows - 1)) end }
    UI.button{ x = w - 6, y = by, w = 6, text = "\31", disabled = last >= #lines,
               onClick = function() self:move(rows - 1) end }
end

Web:loadMarks()
Apps.register(Web)

-- ======================================================================
-- [10] RECHNER
-- ======================================================================
-- Rechnet + - * / ^ mit Klammern. Prozent wie am Taschenrechner:
--   200 + 10%  = 220      200 - 10%  = 180
--   200 * 10%  = 20       50%        = 0,5
-- Bei ganzen Zahlen ab 64 steht darunter die Aufteilung in Stacks und Kisten.
local Calc = {
    id = "calc", title = "RECHNER", order = 7,
    expr = "", ans = nil, err = nil, fresh = false, history = {},
}

-- Wertet einen Ausdruck aus. Rueckgabe: Zahl oder nil, Fehlertext.
function Calc.eval(src)
    local s = src:gsub("%s", ""):gsub(",", "."):gsub("[xX]", "*"):gsub(":", "/")
    local pos = 1
    local expr
    local function peek() return s:sub(pos, pos) end
    local function fail(msg) error(msg, 0) end

    -- Jede Stufe liefert Wert und "ist Prozentangabe".
    local function primary()
        if peek() == "(" then
            pos = pos + 1
            local v = expr()
            if peek() ~= ")" then fail("Klammer fehlt") end
            pos = pos + 1
            return v
        end
        local num = s:match("^%d+%.?%d*", pos) or s:match("^%.%d+", pos)
        if not num then fail(pos > #s and "Unvollstaendig" or ("Unerwartet: " .. peek())) end
        pos = pos + #num
        return tonumber(num)
    end
    local function postfix()
        local v, pct = primary(), false
        while peek() == "%" do
            pos = pos + 1
            if pct then v = v / 100 end
            pct = true
        end
        return v, pct
    end
    local power
    local function unary()
        local c = peek()
        if c == "-" then
            pos = pos + 1
            local v, pct = unary()
            return -v, pct
        elseif c == "+" then
            pos = pos + 1
            return unary()
        end
        return power()
    end
    function power()
        local v, pct = postfix()
        if peek() == "^" then
            pos = pos + 1
            local e, epct = unary()
            if pct then v = v / 100 end
            if epct then e = e / 100 end
            return v ^ e, false
        end
        return v, pct
    end
    local function term()
        local v, pct = unary()
        while peek() == "*" or peek() == "/" do
            local op = peek()
            pos = pos + 1
            local r, rpct = unary()
            if pct then v, pct = v / 100, false end
            if rpct then r = r / 100 end
            if op == "*" then
                v = v * r
            else
                if r == 0 then fail("Division durch 0") end
                v = v / r
            end
        end
        return v, pct
    end
    function expr()
        local v, pct = term()
        if pct then v = v / 100 end
        while peek() == "+" or peek() == "-" do
            local op = peek()
            pos = pos + 1
            local r, rpct = term()
            if rpct then r = v * r / 100 end   -- "200 + 10%" = 200 + 10% von 200
            v = (op == "+") and (v + r) or (v - r)
        end
        return v
    end

    local ok, res = pcall(function()
        if s == "" then fail("Leer") end
        local v = expr()
        if pos <= #s then fail("Unerwartet: " .. peek()) end
        if v ~= v or v == math.huge or v == -math.huge then fail("Zahl zu gross") end
        return v
    end)
    if ok then return res end
    return nil, tostring(res)
end

-- Zahl -> Text mit Komma, ohne ueberfluessige Nullen.
function Calc.fmt(v)
    if math.abs(v) >= 1e15 then return (string.format("%.6g", v):gsub("%.", ",")) end
    if v == math.floor(v) then return string.format("%.0f", v) end
    local s = string.format("%.6f", v):gsub("0+$", ""):gsub("%.$", "")
    return (s:gsub("%.", ","))
end

-- "1000" -> "15 Stacks + 40" und ggf. Kisten (1 Kiste/Shulker = 27 Stacks).
function Calc.stacks(v)
    if v ~= math.floor(v) or v < 64 or v >= 1e12 then return nil end
    local stacks, rest = math.floor(v / 64), v % 64
    local a = stacks .. " Stacks" .. (rest > 0 and (" + " .. rest) or "")
    if stacks < 27 then return a end
    local chests, s2 = math.floor(stacks / 27), stacks % 27
    local b = chests .. " Kisten" .. (s2 > 0 and (" + " .. s2 .. " Stacks") or "") .. (rest > 0 and (" + " .. rest) or "")
    return a, b
end

function Calc:press(key, value)
    local isOp = (key == "+" or key == "-" or key == "*" or key == "/" or key == "^" or key == "%")
    self.err = nil
    if key == "C" then
        self.expr, self.fresh = "", false
    elseif key == "DEL" then
        self.expr, self.fresh = self.expr:sub(1, -2), false
    elseif key == "=" then
        local v, err = Calc.eval(self.expr)
        if v then
            table.insert(self.history, { self.expr, Calc.fmt(v) })
            while #self.history > 20 do table.remove(self.history, 1) end
            self.ans, self.fresh = v, true
        elseif self.expr ~= "" then
            self.err = err
        end
    else
        local text = key
        if key == "ANS" then text = value or (self.ans and Calc.fmt(self.ans) or "")
        elseif key == "x64" then text, isOp = "*64", true
        elseif key == "/64" then text, isOp = "/64", true end
        if self.fresh then
            -- Nach "=": Rechenzeichen rechnet mit dem Ergebnis weiter, alles andere beginnt neu.
            self.expr = (isOp and self.ans) and Calc.fmt(self.ans) or ""
            self.fresh = false
        end
        if #self.expr + #text <= 60 then self.expr = self.expr .. text end
    end
end

function Calc:onChar(ch)
    if ch:find("^[%d%+%-%*/%^%%%(%),%.]$") then self:press(ch == "." and "," or ch)
    elseif ch == "x" or ch == "X" then self:press("*")
    elseif ch == "=" then self:press("=")
    elseif ch == "c" or ch == "C" then self:press("C") end
end

function Calc:onKey(code)
    if code == keys.enter or code == keys.numPadEnter then self:press("=")
    elseif code == keys.backspace then self:press("DEL")
    elseif code == keys.delete then self:press("C") end
end

Calc.pad = {
    { "7", "8", "9", "/", "(", ")" },
    { "4", "5", "6", "*", "%", "C" },
    { "1", "2", "3", "-", "x64", "DEL" },
    { "0", ",", "ANS", "+", "/64", "=" },
}

-- Anzeige: Eingabe rechtsbuendig, darunter Ergebnis und Stacks.
function Calc:drawDisplay(x, y, cw, ch)
    UI.card(x, y, cw, ch)
    local iw = cw - 4
    local shown = self.expr
    if #shown > iw - 1 then shown = shown:sub(#shown - iw + 2) end
    local ex = x + cw - 2 - #shown
    UI.text(ex - 1, y + 1, shown, colors.white)
    UI.text(ex - 1 + #shown, y + 1, " ", colors.black, colors.lime)
    local v = Calc.eval(self.expr)
    local function right(row, text, color)
        text = text:sub(1, iw)
        UI.text(x + cw - 2 - #text, row, text, color)
    end
    if self.err then
        right(y + 2, "Fehler: " .. self.err, colors.red)
    elseif v then
        right(y + 2, "= " .. Calc.fmt(v), colors.lime)
        local a, b = Calc.stacks(v)
        if a and ch >= 4 then right(y + 3, "= " .. a, colors.yellow) end
        if b and ch >= 5 then right(y + 4, "= " .. b, colors.yellow) end
    end
    UI.surface = colors.black
end

-- Tastenfeld im Bereich x, y, Breite pw, Hoehe ph.
function Calc:drawPad(x0, y0, pw, ph)
    local kw = math.max(3, math.min(10, math.floor(pw / 6)))
    local kh = math.max(1, math.min(4, math.floor(ph / 4)))
    x0 = x0 + math.floor((pw - kw * 6) / 2)
    local gap = (kw >= 5) and 1 or 0
    local vgap = (kh >= 3) and 1 or 0
    for r, row in ipairs(self.pad) do
        for c, key in ipairs(row) do
            local o = { x = x0 + (c - 1) * kw, y = y0 + (r - 1) * kh, w = kw - gap, h = kh - vgap, text = key,
                        onClick = function() self:press(key) end }
            if key == "=" then o.style = "primary"
            elseif key == "C" or key == "DEL" then o.style = "danger"
            elseif key == "ANS" or key == "x64" or key == "/64" then o.fg = colors.lightBlue
            elseif not key:find("^[%d,]$") then o.fg = colors.lime
            elseif gap == 0 and (r + c) % 2 == 0 then o.bg = colors.gray end
            UI.button(o)
        end
    end
end

function Calc:draw()
    local w, h, bh = Kernel.w, Kernel.h, UI.bh()
    local narrow = UI.narrow()
    local sub = (w >= 70) and "200+10% = 220  |  1000 = Stacks und Kisten" or "200+10% = 220"
    local top = UI.header("RECHNER", not narrow and sub or nil)
    if w >= 80 then
        -- breit: links Anzeige und Verlauf, rechts das Tastenfeld
        local lw = math.floor(w * 0.42)
        self:drawDisplay(2, top, lw, 5)
        local y = top + 6
        UI.section(2, y, "VERLAUF", lw)
        local n = h - 1 - (y + 1)
        for i = 1, n do
            local hrow = self.history[#self.history + 1 - i]
            if not hrow then break end
            local text = (hrow[1] .. " = " .. hrow[2]):sub(1, lw - 2)
            UI.text(3, y + 1 + i, text, (i == 1) and colors.white or colors.lightGray)
            UI.hit(2, y + 1 + i, lw, 1, function() self:press("ANS", hrow[2]) end)
        end
        self:drawPad(lw + 4, top, w - lw - 4, h - top)
    else
        local hrow = self.history[#self.history]
        local dh = 5
        self:drawDisplay(2, top, w - 2, dh)
        if hrow then UI.text(3, top, (hrow[1] .. " = " .. hrow[2]):sub(1, w - 4), colors.lightGray, colors.gray) end
        self:drawPad(1, top + dh + 1, w, h - (top + dh + 1))
    end
end

Apps.register(Calc)

-- ======================================================================
-- [10b] NETHER-RECHNER und HANDY-STARTSEITE (nur GTS Phone)
-- ======================================================================
-- Oberwelt -> Nether: durch 8 (abgerundet), Nether -> Oberwelt: mal 8.
-- Die Hoehe bleibt gleich. Die letzten Umrechnungen bleiben gespeichert.
local Nether = { id = "nether", title = "NETHER", order = 7.5, page = 1, mode = "ow", cur = nil, hist = {},
                 loaded = false, input = nil, shift = false }

function Nether.convert(mode, x, y, z)
    if mode == "ow" then return math.floor(x / 8), y, math.floor(z / 8) end
    return x * 8, y, z * 8
end

local function xyz(x, y, z)
    return x .. " " .. (y and (y .. " ") or "") .. z
end

function Nether:load()
    self.loaded = true
    local t = Store.load(CONFIG.netherDb)
    if not t then return end
    for _, e in ipairs(t) do
        if type(e) == "table" and tonumber(e.x) and tonumber(e.z) and (e.mode == "ow" or e.mode == "n") and #self.hist < 8 then
            self.hist[#self.hist + 1] = e
        end
    end
    self.cur = self.hist[1]
end

function Nether:save() Store.save(CONFIG.netherDb, self.hist) end

function Nether:enter(text)
    local nums = {}
    for n in tostring(text):gmatch("-?%d+") do nums[#nums + 1] = tonumber(n) end
    local x, y, z
    if #nums == 2 then x, z = nums[1], nums[2]
    elseif #nums >= 3 then x, y, z = nums[1], nums[2], nums[3]
    else Kernel.notify("Bitte X Z oder X Y Z eingeben", colors.red) return end
    local cx, cy, cz = Nether.convert(self.mode, x, y, z)
    self.cur = { mode = self.mode, x = x, y = y, z = z, cx = cx, cy = cy, cz = cz }
    table.insert(self.hist, 1, self.cur)
    while #self.hist > 8 do table.remove(self.hist) end
    self:save()
end

function Nether:onEnter() if not self.loaded then self:load() end end
function Nether:onChar(ch) Input.insert(self, ch) end
function Nether:onPaste(text) Input.insert(self, text) end
function Nether:onKey(code) Input.onKey(self, code) end
function Nether:insert(text) return Input.insert(self, text) end
function Nether:key(action) return Input.key(self, action) end

function Nether:draw()
    if self.input then return Input.draw(self) end
    local w = Kernel.w
    local narrow = UI.narrow()
    local ow = (self.mode == "ow")
    local top = UI.header("NETHER", ow and "OW > Nether" or "Nether > OW", {
        { text = "\18", onClick = function() self.mode = ow and "n" or "ow" end },
    })
    local y = top
    UI.button{ x = 2, y = y, w = w - 2, text = "KOORDINATEN EINGEBEN", style = "primary", onClick = function()
        Input.open(self, { title = (ow and "Oberwelt" or "Nether") .. ": X Y Z (Y darf fehlen)", maxLen = 24,
                           filter = "[^%d%-%s,]", hint = "z.B. 800 64 -1200",
                           onOk = function(t) self:enter(t) end })
    end }
    y = y + UI.bh() + 1
    local c = self.cur
    if c then
        local fromName = (c.mode == "ow") and "OBERWELT" or "NETHER"
        local toName = (c.mode == "ow") and "NETHER" or "OBERWELT"
        UI.card(2, y, w - 2, 4)
        UI.text(3, y, fromName, colors.lightGray)
        UI.text(3, y + 1, xyz(c.x, c.y, c.z):sub(1, w - 4), colors.white)
        UI.text(3, y + 2, toName, (c.mode == "ow") and colors.red or colors.green)
        UI.text(3, y + 3, xyz(c.cx, c.cy, c.cz):sub(1, w - 4), colors.lime)
        UI.surface = colors.black
        y = y + 5
    else
        UI.text(2, y, "Portal bauen? Koordinaten", colors.lightGray)
        UI.text(2, y + 1, "eingeben, Ziel ablesen.", colors.lightGray)
        y = y + 3
    end
    if #self.hist > 1 and y < Kernel.h - 1 then
        UI.section(2, y, "ZULETZT", w - 2)
        y = y + 1
        for i = 2, #self.hist do
            if y > Kernel.h then break end
            local e = self.hist[i]
            local line = ((e.mode == "ow") and "O " or "N ") .. e.x .. " " .. e.z .. " > " .. e.cx .. " " .. e.cz
            UI.text(2, y, line:sub(1, w - 2), colors.white)
            UI.hit(1, y, w, 1, function() self.cur = e end)
            y = y + 1
        end
    end
    if narrow then return end
end

if PHONE then Apps.register(Nether) end

-- ---------- Handy-Startseite ----------
-- Oben eine Statusleiste (Uhr, Lager-Empfang, Sperre), darunter die
-- Minecraft-Zeit (Schlafen? Mond?) und die Apps als Kacheln.
local MOON = { [0] = "Vollmond", "abn. Dreiviertel", "Halbmond (abn.)", "abn. Sichel",
               "Neumond", "zun. Sichel", "Halbmond (zun.)", "zun. Dreiviertel" }

-- Minecraft-Zeit: Stunde (0-24), Tag, Schlafen moeglich, Minuten bis dahin, Mond.
function Kernel.mcTime()
    local ok, t = pcall(os.time)
    local okD, day = pcall(os.day)
    t = (ok and type(t) == "number") and t or 12
    day = (okD and type(day) == "number") and day or 1
    -- Betten gehen ab 18:32 bis 05:27 (12542 bis 23459 Ticks)
    local sleep = (t >= 18.54) or (t < 5.46)
    local wait = (not sleep) and math.max(1, math.ceil((18.54 - t) * 50 / 60)) or nil   -- 1 MC-Stunde = 50 s
    local mcDay = (t < 6) and (day - 2) or (day - 1)                                     -- Mond wechselt um 06:00
    return t, day, sleep, wait, MOON[mcDay % 8]
end

local PHONE_TILES = {
    { "lager", "LAGER", colors.cyan }, { "notes", "NOTIZEN", colors.magenta }, { "calc", "RECHNER", colors.orange },
    { "nether", "NETHER", colors.red }, { "web", "WEB", colors.lightBlue }, { "games", "GAMES", colors.yellow },
    { "info", "INFO", colors.lime },
}

local function phoneHome()
    local w, h = Kernel.w, Kernel.h
    -- Statusleiste
    UI.fill(1, 1, w, 1, colors.gray)
    UI.surface = colors.gray
    UI.text(2, 1, Kernel.clock, colors.white, colors.gray)
    local lager = Apps.byId.lager
    local r = lager and lager.remote
    local fresh = r and (os.clock() - (r.at or 0) < 75)
    local label = Kernel.locked and "GESPERRT" or "SPERREN"
    local lx = w - #label - 2
    UI.text(lx, 1, "\7 " .. label, colors.white, colors.gray)
    UI.text(lx, 1, "\7", Kernel.locked and colors.lime or colors.red, colors.gray)
    UI.hit(lx, 1, #label + 2, 1, function() Kernel.lock() end)
    local gx = math.max(#Kernel.clock + 3, lx - 9)   -- Lager-Empfang zwischen Uhr und Sperre
    if gx + 7 <= lx - 1 then
        UI.text(gx, 1, "\7 LAGER", fresh and colors.cyan or colors.lightGray, colors.gray)
        UI.text(gx + 2, 1, "LAGER", fresh and colors.white or colors.lightGray, colors.gray)
        UI.hit(gx, 1, 7, 1, function() Kernel.open("lager") end)
    end
    UI.surface = colors.black
    -- Minecraft-Zeit
    local t, day, sleep, wait, moon = Kernel.mcTime()
    local hh, mm = math.floor(t), math.floor((t % 1) * 60)
    local y = 3
    UI.card(2, y, w - 2, 4)
    UI.text(3, y, "MINECRAFT", colors.lightGray)
    local dayText = "Tag " .. day
    UI.text(w - #dayText - 1, y, dayText, colors.lightGray)
    UI.text(3, y + 1, string.format("%02d:%02d", hh, mm), sleep and colors.lightBlue or colors.yellow)
    UI.text(10, y + 1, sleep and "Nacht" or "Tag", colors.white)
    UI.text(3, y + 2, (sleep and "Schlafen geht jetzt" or ("Schlafen in " .. wait .. " min")):sub(1, w - 4),
            sleep and colors.lime or colors.white)
    UI.text(3, y + 3, ("Mond: " .. moon):sub(1, w - 4), colors.lightGray)
    UI.surface = colors.black
    -- App-Kacheln
    local tiles = {}
    for _, tdef in ipairs(PHONE_TILES) do
        if Apps.byId[tdef[1]] then tiles[#tiles + 1] = tdef end
    end
    local cols = math.max(2, math.min(4, math.floor((w - 1) / 8)))
    local tw = math.floor((w - 1 - cols) / cols)
    local th = (h - 8 >= 3 * 4) and 3 or 2
    y = y + 5
    for i, tdef in ipairs(tiles) do
        local cx = 2 + ((i - 1) % cols) * (tw + 1)
        local cy = y + math.floor((i - 1) / cols) * (th + 1)
        if cy + th - 1 <= h then
            UI.fill(cx, cy, tw, th, colors.gray)
            UI.fill(cx, cy, tw, 1, tdef[3])
            UI.text(cx + math.floor((tw - #tdef[2]) / 2), cy + th - 1, tdef[2]:sub(1, tw), colors.white, colors.gray)
            UI.hit(cx, cy, tw, th, function() Kernel.open(tdef[1]) end)
        end
    end
    UI.surface = colors.black
end

if PHONE then
    Apps.byId.home.draw = phoneHome
    Apps.byId.home.tick = function() return Kernel.app.id == "home" end   -- Uhr laeuft mit
end

-- ======================================================================
-- [11] SHELL
-- ======================================================================
-- Eine echte CraftOS-Shell in einem Fenster des OS (wie die Tabs bei Opus).
-- Alles funktioniert wie gewohnt: edit, delete, ls, pastebin, lua, eigene
-- Programme. Die Shell startet im Ordner /scripts; was dort liegt,
-- erscheint automatisch im Reiter LUA APPS.
-- Strg+T beendet das laufende Programm (nicht das OS), "exit" startet neu.
Shell = {
    id = "shell", title = "SHELL", order = 8,
    win = nil,       -- Fenster, in das die Shell schreibt
    session = nil,   -- { co, term, filter }
    osk = false, shift = false, restarts = {},
}

-- Eingaben gehen nur an die Shell, wenn ihr Reiter offen ist.
Shell.inputEvents = {
    char = true, key = true, key_up = true, paste = true, terminate = true,
    mouse_click = true, mouse_up = true, mouse_drag = true, mouse_scroll = true, monitor_touch = true,
}

-- Bereich des Shell-Fensters: unter der Kopfzeile bis ueber die Meldungszeile.
function Shell:area()
    local y = UI.bh() + 1
    local bottom = Kernel.h - 1
    if self.osk and Kernel.display.touch then bottom = Kernel.h - OSK.height() - 1 end
    return 1, y, Kernel.w, math.max(1, bottom - y + 1)
end

-- Legt das Fenster an oder passt es an (Tastatur ein/aus, anderer Bildschirm).
function Shell:ensure()
    local x, y, w, h = self:area()
    local geo = x .. "," .. y .. "," .. w .. "," .. h
    if not self.win then
        self.win = window.create(Kernel.screen, x, y, w, h, Kernel.app == self)
    elseif geo ~= self.geo or self.parent ~= Kernel.screen then
        self.win.reposition(x, y, w, h, Kernel.screen)
        self.geo, self.parent = geo, Kernel.screen
        if self.session then self:resume("term_resize") end
    end
    self.geo, self.parent = geo, Kernel.screen
end

-- Gibt der Shell ein Event. Waehrenddessen zeigt "term" auf ihr Fenster.
function Shell:resume(ev, ...)
    local s = self.session
    if not s then return end
    if s.filter and ev ~= s.filter and ev ~= "terminate" then return end
    local prev = term.redirect(s.term)
    local ok, res = coroutine.resume(s.co, ev, ...)
    s.term = term.current()
    term.redirect(prev)
    if not ok or coroutine.status(s.co) == "dead" then
        -- "exit" getippt oder abgestuerzt: neue Shell starten.
        self.session = nil
        if not ok then Kernel.log("FEHLER", "shell: " .. tostring(res)) end
        local now = os.clock()
        table.insert(self.restarts, now)
        while #self.restarts > 3 do table.remove(self.restarts, 1) end
        if #self.restarts == 3 and now - self.restarts[1] < 2 then
            self.win.setTextColor(colors.red)
            self.win.setCursorPos(1, 1)
            self.win.write("Shell startet nicht. NEUSTART versuchen.")
            return
        end
        self:start()
    else
        s.filter = res
    end
end

-- Startet eine neue Shell. Mit cmd laeuft zuerst dieses Programm.
function Shell:start(cmd)
    self:ensure()
    local win = self.win
    win.setBackgroundColor(colors.black)
    win.setTextColor(colors.white)
    win.clear()
    win.setCursorPos(1, 1)
    win.setCursorBlink(false)
    if not shell then
        win.write("Keine Shell verfuegbar.")
        return
    end
    pcall(shell.setDir, CONFIG.scriptDir)
    local co = coroutine.create(function()
        if cmd then
            shell.run(cmd)
            if term.getCursorPos() > 1 then print() end
            term.setTextColor(colors.lightGray)
            print("[Programm beendet]")
            term.setTextColor(colors.white)
        end
        shell.run("shell")
    end)
    self.session = { co = co, term = win }
    self:resume()
end

-- Startet ein Programm in der Shell und wechselt dorthin.
function Shell:launch(cmd)
    self:start(cmd)
    Kernel.open("shell")
end

-- Pfad fuer die Shell-Kommandozeile (mit Anfuehrungszeichen bei Leerzeichen).
function Shell.quote(path)
    path = "/" .. fs.combine(path, "")
    return path:find(" ", 1, true) and ("\"" .. path .. "\"") or path
end

-- Hintergrund-Dienst: reicht Events an die Shell weiter. Programme laufen
-- auch weiter, wenn ein anderer Reiter offen ist; Eingaben bekommen sie
-- aber nur, solange der SHELL-Reiter offen ist.
function Shell:service()
    while true do
        local ev = table.pack(os.pullEventRaw())
        local name = ev[1]
        -- Der Klick, der gerade erst auf diesen Reiter gewechselt hat, gehoert
        -- nicht dem Programm in der Shell.
        local muted = self.mute
        self.mute = false
        if type(name) == "string" and name:sub(1, 4) ~= "gts_" and self.session then
            if not self.inputEvents[name] then
                self:resume(table.unpack(ev, 1, ev.n))
            elseif Kernel.app == self and not muted and not Kernel.menu then
                local d = Kernel.display
                local ax, ay, aw, ah = self:area()
                if name == "monitor_touch" then
                    -- Antippen auf dem Monitor wird fuer das Programm zum Mausklick.
                    local x, y = ev[3] - ax + 1, ev[4] - ay + 1
                    if d.monitor and ev[2] == d.name and x >= 1 and x <= aw and y >= 1 and y <= ah then
                        self:resume("mouse_click", 1, x, y)
                        self:resume("mouse_up", 1, x, y)
                    end
                elseif name:sub(1, 6) == "mouse_" then
                    local x, y = ev[3] - ax + 1, ev[4] - ay + 1
                    if not d.monitor and x >= 1 and x <= aw and y >= 1 and y <= ah then
                        self:resume(name, ev[2], x, y)
                    end
                elseif name ~= "terminate" then
                    self:resume(table.unpack(ev, 1, ev.n))
                end
            end
        end
    end
end

-- Strg+T im SHELL-Reiter trifft das Programm in der Shell, nicht das OS.
function Shell:onTerminate() self:resume("terminate") end

-- Bildschirmtastatur -> Tastendruecke fuer das Programm.
function Shell:insert(text)
    for ch in text:gmatch(".") do self:resume("char", ch) end
end

function Shell:key(action)
    local code = ({ enter = keys.enter, backspace = keys.backspace, left = keys.left,
                    right = keys.right, up = keys.up, down = keys.down })[action]
    if code then
        self:resume("key", code, false)
        self:resume("key_up", code)
    end
end

function Shell:onEnter()
    self:ensure()
    if not self.session then self:start() end
    self.win.setVisible(true)
    self.mute = true
end

function Shell:onLeave()
    if self.win then self.win.setVisible(false) end
end

-- Nach dem Zeichnen den blinkenden Cursor der Shell wiederherstellen.
function Shell:cursor()
    if self.win then self.win.restoreCursor() end
end

function Shell:draw()
    local h = Kernel.h
    local touch = Kernel.display.touch
    local actions = {}
    if touch then
        actions[#actions + 1] = { text = "TASTATUR", style = self.osk and "primary" or nil,
                                  onClick = function() self.osk = not self.osk end }
    end
    actions[#actions + 1] = { text = "NEUSTART", style = "danger", confirm = "shell:restart", onClick = function()
        self.restarts = {}
        self:start()
    end }
    local sub = "Ordner: " .. CONFIG.scriptDir
    if UI.narrow() then sub = "" elseif UI.bh() >= 2 then sub = sub .. "   Strg+T beendet das Programm" end
    UI.header("SHELL", sub, actions, nil, true)
    self:ensure()
    self.win.setVisible(true)
    self.win.redraw()
    -- Ist das App-Menue offen, darf neue Ausgabe nicht darueber schreiben.
    if Kernel.menu then self.win.setVisible(false) end
    if self.osk and touch then OSK.draw(h - OSK.height(), self) end
end

Apps.register(Shell)

-- ======================================================================
-- [12] LUA APPS
-- ======================================================================
-- Zeigt die Dateien in /scripts wie ein Datei-Explorer, mit Ordnern.
-- Neue Scripts (ueber NEU + oder in der Shell mit "edit name.lua",
-- "pastebin get ...") erscheinen von selbst, geloeschte verschwinden.
--   turtle   Turtle-Programme: die Knoepfe in SCHWARM schicken sie per Funk
--            an die Turtles (DD, CHUNK, TEST, eigene, der Agent selbst)
--   games    ein kleiner versteckter Spiele-Ordner
local Games   -- [13]
local LuaApps = {
    id = "luaapps", title = "LUA APPS", order = 9,
    page = 1, input = nil, shift = false, dir = "",
}

-- Vorlage fuer ein neues Turtle-Programm (Ordner turtle).
local TURTLE_TEMPLATE = [[
-- GTS-PROG %s 1
-- Eigenes Turtle-Programm. Starten: SCHWARM > Turtle antippen > %s.
-- Es bekommt die Schnittstelle T (siehe dd.lua und chunk.lua) und args.
-- Werkzeug aus dem Inventar kurz benutzen (danach steckt wieder die Spitzhacke):
--   local biom = T.use("env", function(p) return p.getBiome() end)
--   (scanner, env, compass, player, chat, speaker, chunky)
local T, args = ...
T.status("Los")
for i = 1, 3 do
    T.check()                 -- reagiert auf STOP
    T.step("fwd")             -- graebt, wenn noetig
end
local ok = T.home()           -- zurueck zur Basis
return ok, ok and "Fertig" or "Heimweg blockiert"
]]

function LuaApps.isTurtleDir(dir) return fs.combine(CONFIG.scriptDir, dir) == fs.combine(CONFIG.progDir, "") end

-- Inhalt eines Ordners: erst Ordner, dann Dateien.
function LuaApps.list(dir)
    dir = dir or ""
    local base = fs.combine(CONFIG.scriptDir, dir)
    local folders, files = {}, {}
    if dir == "" and Games then
        folders[1] = { name = "games", virtual = true, info = #Games.defs .. " Spiele" }
    end
    if fs.isDir(base) then
        for _, name in ipairs(fs.list(base)) do
            local path = fs.combine(base, name)
            if fs.isDir(path) then
                if not (dir == "" and name == "games") then
                    local n = #fs.list(path)
                    folders[#folders + 1] = { name = name, path = path, info = (n == 1) and "1 Datei" or (n .. " Dateien") }
                end
            else
                files[#files + 1] = { name = name, path = path, size = fs.getSize(path) }
            end
        end
    end
    table.sort(folders, function(a, b) return a.name < b.name end)
    table.sort(files, function(a, b) return a.name < b.name end)
    for _, f in ipairs(files) do folders[#folders + 1] = f end
    return folders
end

function LuaApps:insert(text)
    local i = self.input
    if not i then return end
    i.text = (i.text .. text:gsub(" ", "_"):gsub("[^%w_%-%.]", "")):sub(1, 24)
end

function LuaApps:key(action)
    local i = self.input
    if not i then return end
    if action == "backspace" then
        i.text = i.text:sub(1, -2)
    elseif action == "enter" then
        local name = i.text:gsub("^%.+", "")
        self.input = nil
        if name == "" then return end
        if not name:find(".", 1, true) then name = name .. ".lua" end
        local path = fs.combine(fs.combine(CONFIG.scriptDir, self.dir), name)
        if LuaApps.isTurtleDir(self.dir) and not fs.exists(path) then
            local base = name:gsub("%.lua$", ""):gsub("[^%w_%-]", "")
            pcall(function()
                local h = fs.open(path, "w")
                h.write(TURTLE_TEMPLATE:format(base, base:upper()))
                h.close()
            end)
        end
        Shell:launch("edit " .. Shell.quote(path))
    end
end

function LuaApps:onChar(ch) self:insert(ch) end
function LuaApps:onPaste(text) self:insert(text) end
function LuaApps:onKey(code)
    if code == keys.enter or code == keys.numPadEnter then self:key("enter")
    elseif code == keys.backspace then self:key("backspace") end
end
function LuaApps:onEnter() self.input = nil end
function LuaApps:onScroll(dir) self.page = math.max(1, self.page + dir) end

function LuaApps:open(f)
    if f.virtual then return Kernel.open("games") end
    self.dir, self.page = fs.combine(self.dir, f.name), 1
end

function LuaApps:up()
    self.dir, self.page = fs.getDir(self.dir), 1
    if self.dir == ".." then self.dir = "" end
end

function LuaApps:draw()
    local h, bh, narrow = Kernel.h, UI.bh(), UI.narrow()
    if self.input then
        -- Name fuer ein neues Script abfragen, dann oeffnet sich der Editor.
        local top = UI.header("NEUES SCRIPT")
        UI.prompt{ y = top, title = "Name des Scripts", text = self.input.text, maxW = 28,
                   hint = narrow and ".lua kommt dazu" or "Die Endung .lua wird ergaenzt.",
                   onOk = function() self:key("enter") end, onCancel = function() self.input = nil end }
        if Kernel.display.touch then OSK.draw(h - OSK.height(), self) end
        return
    end
    if self.dir ~= "" and not fs.isDir(fs.combine(CONFIG.scriptDir, self.dir)) then self.dir = "" end
    local turtleDir = LuaApps.isTurtleDir(self.dir)
    local items = self.list(self.dir)
    local nFiles = 0
    for _, f in ipairs(items) do if f.size then nFiles = nFiles + 1 end end
    local where = "/" .. fs.combine(CONFIG.scriptDir, self.dir)
    local actions = {}
    if self.dir ~= "" then
        actions[#actions + 1] = { text = narrow and "\17" or "\17 ZURUECK", onClick = function() self:up() end }
    end
    actions[#actions + 1] = { text = "NEU +", style = "primary", onClick = function() self.input, self.shift = { text = "" }, false end }
    local title = (self.dir == "") and "LUA APPS" or self.dir:upper()
    local top = UI.header(title, ((nFiles == 1) and "1 Script" or (nFiles .. " Scripts")) .. " in " .. where, actions)
    if turtleDir and top <= h - 2 then
        UI.text(2, top, (narrow and "Start: SCHWARM > Turtle" or "Turtle-Programme: die Knoepfe in SCHWARM schicken sie per Funk an die Turtles."):sub(1, Kernel.w - 2), colors.lightGray)
        top = top + 2
    end
    if #items == 0 then
        UI.empty(top + 2, "Noch keine Scripts.", narrow and "NEU + oder SHELL: edit x"
                 or "NEU + tippen oder in der SHELL: edit name.lua")
        return
    end
    local ch = narrow and 2 or bh
    UI.list(self, items, top, ch + 1, function(f, y)
        local tx, xr = UI.rowCard(y, ch)
        if not f.size then
            -- Ordner: gelbes Symbol, ganze Zeile antippbar
            UI.text(tx, y, "  ", colors.black, colors.yellow)
            UI.text(tx + 3, y, f.name, colors.yellow)
            UI.text(tx + 4 + #f.name, y, f.info, colors.lightGray)
            local bx = UI.buttonsRight({ { text = narrow and "\16" or "OEFFNEN \16", onClick = function() self:open(f) end } },
                                       narrow and (y + 1) or y, xr)
            UI.hit(tx, y, bx - tx - 1, ch, function() self:open(f) end)
            return
        end
        local buttons = {}
        if not turtleDir then
            -- Sicherer Modus: eigene Programme starten nicht (sie koennten das OS lahmlegen)
            buttons[#buttons + 1] = { text = "START", style = "primary", disabled = Sys.safe,
                                      onClick = function() Shell:launch(Shell.quote(f.path)) end }
        end
        buttons[#buttons + 1] = { text = "EDIT", onClick = function() Shell:launch("edit " .. Shell.quote(f.path)) end }
        buttons[#buttons + 1] = { text = "DEL", style = "danger", confirm = "lua:del:" .. f.path, onClick = function()
            local _, bin = Sys.delete(f.path)
            Kernel.notify(bin and ("Im Papierkorb: " .. f.name) or ("Geloescht: " .. f.name), colors.lightGray,
                          bin and "info" or nil, bin and "trash" or nil)
        end }
        local bx = UI.buttonsRight(buttons, narrow and (y + 1) or y, xr)
        local room = (narrow and xr or (bx - 2)) - tx + 1
        UI.text(tx, y, f.name:sub(1, room), colors.white)
        local info = fmtSize(f.size)
        if turtleDir then
            local ver = TurtleProgs.version(f.name, (fs.getSize(f.path) < 200000) and readAll(f.path) or "")
            if ver then info = info .. "  v" .. ver end
        end
        if #f.name + 2 + #info <= room then UI.text(tx + #f.name + 2, y, info, colors.lightGray) end
    end)
end

Apps.register(LuaApps)

-- ======================================================================
-- [13] GAMES
-- ======================================================================
-- Vier kleine Spiele, alle selbst geschrieben: Snake, Runner, Dino, Pong.
-- Steuerung per Antippen oder Tastatur. Ein Spiel ist eine Tabelle mit
--   init(F)     neues Spiel; F = { x, y, w, h } ist das Spielfeld
--   update()    ein Zeitschritt (alle self.dt Sekunden)
--   draw(F)     zeichnet das Feld
--   tap(x, y)   Antippen (Koordinaten im Feld), key(code) Taste
--   state       "ready" | "run" | "over", score = Punkte
-- Ein neues Spiel wird mit Games.add(def) angemeldet.
Games = {
    id = "games", title = "GAMES", order = 10, tab = false,   -- versteckt: LUA APPS > games
    view = "menu", game = nil, paused = false, defs = {}, best = {},
    dbFile = "/gts/games.db",
}

function Games.add(def) Games.defs[#Games.defs + 1] = def end

-- ---------- Zeichenhilfen: alles bleibt innerhalb des Spielfelds ----------
local function gFill(F, x, y, w, h, color)
    x, y = math.floor(x), math.floor(y)
    local x1, y1 = math.max(1, x), math.max(1, y)
    local x2, y2 = math.min(F.w, x + w - 1), math.min(F.h, y + h - 1)
    if x2 >= x1 and y2 >= y1 then UI.fill(F.x + x1 - 1, F.y + y1 - 1, x2 - x1 + 1, y2 - y1 + 1, color) end
end

local function gText(F, x, y, text, fg, bg)
    x, y = math.floor(x), math.floor(y)
    if y < 1 or y > F.h or x > F.w then return end
    if x < 1 then text, x = text:sub(2 - x), 1 end
    text = text:sub(1, F.w - x + 1)
    if text ~= "" then UI.text(F.x + x - 1, F.y + y - 1, text, fg, bg) end
end

-- Figur aus Textzeilen: jedes Zeichen ist ein Pixel in der Farbe palette[zeichen].
-- sx = Breite eines Pixels in Bildschirmzeichen.
local function gSprite(F, rows, x, y, palette, sx)
    x, y = math.floor(x), math.floor(y)
    for r, row in ipairs(rows) do
        local c = 1
        while c <= #row do
            local ch = row:sub(c, c)
            local color = palette[ch]
            local run = 1
            if color then
                while row:sub(c + run, c + run) == ch do run = run + 1 end
                gFill(F, x + (c - 1) * sx, y + r - 1, run * sx, 1, color)
            end
            c = c + run
        end
    end
end

-- ---------- SNAKE ----------
local Snake = { name = "snake", title = "SNAKE", color = colors.lime, fg = colors.black,
                help = "Tippe dorthin, wohin die Schlange soll. Oder Pfeiltasten / WASD." }

function Snake:init(F)
    -- Ein Feld ist 2 Zeichen breit und 1 hoch (so wirkt es quadratisch). Rand ringsum.
    self.gw, self.gh = math.floor((F.w - 2) / 2), F.h - 2
    local cx, cy = math.max(4, math.floor(self.gw / 3)), math.floor(self.gh / 2) + 1
    self.body = { { x = cx, y = cy }, { x = cx - 1, y = cy }, { x = cx - 2, y = cy } }
    self.dx, self.dy, self.turns = 1, 0, {}
    self.score, self.dt = 0, (self.gw >= 30) and 0.1 or 0.15   -- grosses Feld: schneller
    self:placeFood()
end

function Snake:occupied(x, y)
    for _, p in ipairs(self.body) do
        if p.x == x and p.y == y then return true end
    end
    return false
end

function Snake:placeFood()
    for _ = 1, 300 do
        local x, y = math.random(self.gw), math.random(self.gh)
        if not self:occupied(x, y) then
            self.food = { x = x, y = y }
            return
        end
    end
    for x = 1, self.gw do
        for y = 1, self.gh do
            if not self:occupied(x, y) then
                self.food = { x = x, y = y }
                return
            end
        end
    end
    self.food = nil  -- alles voll: gewonnen
end

function Snake:turn(dx, dy)
    local last = self.turns[#self.turns] or { self.dx, self.dy }
    if (dx == -last[1] and dy == -last[2]) or (dx == last[1] and dy == last[2]) then return end
    if #self.turns < 2 then self.turns[#self.turns + 1] = { dx, dy } end
end

function Snake:key(code)
    if code == keys.up or code == keys.w then self:turn(0, -1)
    elseif code == keys.down or code == keys.s then self:turn(0, 1)
    elseif code == keys.left or code == keys.a then self:turn(-1, 0)
    elseif code == keys.right or code == keys.d then self:turn(1, 0) end
end

function Snake:tap(x, y)
    -- Richtung = dorthin, wo relativ zum Kopf getippt wurde.
    local head = self.body[1]
    local ddx, ddy = (x - (head.x * 2 + 0.5)) / 2, y - (head.y + 1)
    local horizontal = math.abs(ddx) >= math.abs(ddy)
    if horizontal and self.dx ~= 0 and ddy ~= 0 then horizontal = false end   -- faehrt schon waagerecht: abbiegen
    if not horizontal and self.dy ~= 0 and ddx ~= 0 then horizontal = true end
    if horizontal then self:turn(ddx > 0 and 1 or -1, 0) else self:turn(0, ddy > 0 and 1 or -1) end
end

function Snake:update()
    local t = table.remove(self.turns, 1)
    if t then self.dx, self.dy = t[1], t[2] end
    local head = self.body[1]
    local nx, ny = head.x + self.dx, head.y + self.dy
    local eat = self.food and nx == self.food.x and ny == self.food.y
    if not eat then table.remove(self.body) end   -- Schwanz rueckt nach
    if nx < 1 or ny < 1 or nx > self.gw or ny > self.gh or self:occupied(nx, ny) then
        self.state = "over"
        return
    end
    table.insert(self.body, 1, { x = nx, y = ny })
    if eat then
        self.score = self.score + 10
        self.dt = math.max(0.05, self.dt - 0.002)
        self:placeFood()
        if not self.food then self.state = "over" end
    end
end

function Snake:draw(F)
    gFill(F, 1, 1, F.w, F.h, colors.gray)                       -- Rand
    gFill(F, 2, 2, self.gw * 2, self.gh, colors.black)          -- Spielflaeche
    if self.food then gFill(F, self.food.x * 2, self.food.y + 1, 2, 1, colors.red) end
    for i = #self.body, 1, -1 do
        local p = self.body[i]
        gFill(F, p.x * 2, p.y + 1, 2, 1, (i == 1) and colors.yellow or colors.lime)
    end
end

Games.add(Snake)

-- ---------- RUNNER ----------
-- Drei Flugbahnen. Das Flugzeug sammelt Muenzen und weicht Hindernissen aus.
local Runner = { name = "runner", title = "RUNNER", color = colors.lightBlue, fg = colors.black,
                 help = "Tippe auf eine Bahn, um dorthin zu fliegen. Oder Pfeil hoch/runter, W/S." }

Runner.plane = {
    "rr       ",
    "wwwwbwbww",
    "   ggg   ",
}
Runner.palette = { r = colors.red, w = colors.white, b = colors.blue, g = colors.lightGray }

function Runner:init(F)
    self.laneH = math.floor(F.h / 3)
    self.lane, self.px, self.pw = 2, 4, #self.plane[1]
    self.items = {}        -- { x, lane, w, coin }
    self.speed, self.gap, self.dist, self.ticks = 1, 14, 0, 0
    self.coins, self.score, self.dt = 0, 0, 0.05
    self.fw = F.w
    self.pace = math.max(0.5, math.min(1, F.w / 60))   -- schmaler Schirm: langsamer
end

function Runner:key(code)
    if code == keys.up or code == keys.w then self.lane = math.max(1, self.lane - 1)
    elseif code == keys.down or code == keys.s then self.lane = math.min(3, self.lane + 1) end
end

function Runner:tap(_, y)
    self.lane = math.max(1, math.min(3, math.ceil(y / self.laneH)))
end

-- Neue Welle: ein oder zwei Bahnen sind versperrt, in einer freien liegen Muenzen.
function Runner:wave()
    local patterns = { { 1 }, { 2 }, { 3 }, { 1, 2 }, { 1, 3 }, { 2, 3 } }
    local blocked, free = {}, {}
    for _, lane in ipairs(patterns[math.random(#patterns)]) do
        blocked[lane] = true
        self.items[#self.items + 1] = { x = self.fw + 1, lane = lane, w = math.random(4, 6) }
    end
    for lane = 1, 3 do
        if not blocked[lane] then free[#free + 1] = lane end
    end
    local lane = free[math.random(#free)]
    for i = 0, math.random(2, 4) do
        self.items[#self.items + 1] = { x = self.fw + 1 + i * 4, lane = lane, w = 2, coin = true }
    end
end

function Runner:update()
    self.ticks = self.ticks + 1
    self.speed = self.pace * math.min(2.5, 1 + self.ticks * 0.0008)
    self.dist = self.dist + self.speed
    self.gap = self.gap - self.speed
    if self.gap <= 0 then
        self:wave()
        -- Abstand: mindestens so gross, dass das Flugzeug zwischen zwei Wellen die Bahn wechseln kann.
        self.gap = math.max(20, (26 + math.random(0, 14)) * (0.7 + 0.3 * self.speed) * self.pace)
    end
    local left, right = self.px, self.px + self.pw - 1
    for i = #self.items, 1, -1 do
        local it = self.items[i]
        it.x = it.x - self.speed
        local a, b = math.floor(it.x), math.floor(it.x) + it.w - 1
        if b < 1 then
            table.remove(self.items, i)
        elseif it.lane == self.lane and a <= right and b >= left then
            if it.coin then
                self.coins = self.coins + 1
                table.remove(self.items, i)
            else
                self.state = "over"
            end
        end
    end
    self.score = math.floor(self.dist / 4) + self.coins * 10
end

function Runner:draw(F)
    gFill(F, 1, 1, F.w, F.h, colors.lightBlue)
    -- Bahn-Linien laufen mit, damit man die Geschwindigkeit sieht.
    local dash = string.rep("-   ", math.ceil(F.w / 4) + 1)
    local shift = math.floor(self.dist) % 4
    for lane = 1, 2 do
        gText(F, 1, lane * self.laneH, dash:sub(1 + shift, F.w + shift), colors.white, colors.lightBlue)
    end
    for _, it in ipairs(self.items) do
        local top = (it.lane - 1) * self.laneH + 1
        if it.coin then
            gFill(F, it.x, top + math.floor((self.laneH - 1) / 2), 2, 1, colors.yellow)
        else
            gFill(F, it.x, top, it.w, self.laneH - 1, colors.red)
            gFill(F, it.x + 1, top + 1, it.w - 2, math.max(0, self.laneH - 3), colors.gray)
        end
    end
    local top = (self.lane - 1) * self.laneH + 1
    gSprite(F, self.plane, self.px, top + math.floor((self.laneH - 1 - #self.plane) / 2), self.palette, 1)
    gText(F, 2, 1, "Muenzen " .. self.coins, colors.black, colors.lightBlue)
end

Games.add(Runner)

-- ---------- DINO ----------
-- Weisser Hintergrund, schwarzer Dino, Kakteen. Springen und nicht anstossen.
local Dino = { name = "dino", title = "DINO", color = colors.white, fg = colors.black,
               help = "Tippen, Leertaste oder Pfeil hoch: springen." }

Dino.sprite = { "..###", "..#o#", "#.###", "####.", ".#.#." }
Dino.sprite2 = { "..###", "..#o#", "#.###", "####.", "#..#." }
Dino.cacti = {
    { ".#.", "###" },
    { ".#.", "###", ".#." },
    { ".#.", "##.", ".##" },
}
Dino.palette = { ["#"] = colors.black, o = colors.white }

function Dino:init(F)
    self.sx = (F.w >= 60) and 2 or 1        -- Pixelbreite in Zeichen
    self.pw = math.floor(F.w / self.sx)     -- Feldbreite in Pixeln
    self.x, self.y, self.vy = 4, 0, 0       -- y = Hoehe ueber dem Boden
    self.obst, self.speed, self.gap = {}, 1, 30
    self.ticks, self.score, self.dt = 0, 0, 0.05
end

function Dino:jump()
    if self.y == 0 then self.vy = 1.5 end
end

function Dino:key(code)
    if code == keys.space or code == keys.up or code == keys.w or code == keys.enter then self:jump() end
end

function Dino:tap() self:jump() end

-- Trifft ein schwarzes Pixel des Dinos ein Pixel eines Kaktus?
function Dino:hit()
    local height = math.floor(self.y + 0.5)
    for _, o in ipairs(self.obst) do
        local ox, rows = math.floor(o.x), self.cacti[o.kind]
        for r, row in ipairs(rows) do
            for c = 1, #row do
                if row:sub(c, c) == "#" then
                    local px, ph = ox + c - 1, #rows - r      -- Pixel und Hoehe ueber dem Boden
                    local dr = 5 - (ph - height)               -- passende Zeile im Dino
                    local dc = px - self.x + 1
                    if dr >= 1 and dr <= 5 and dc >= 1 and dc <= 5 and self.sprite[dr]:sub(dc, dc) == "#" then
                        return true
                    end
                end
            end
        end
    end
    return false
end

function Dino:update()
    self.ticks = self.ticks + 1
    self.score = math.floor(self.ticks / 2)
    self.speed = math.min(2.2, 1 + self.ticks * 0.0006)
    if self.y > 0 or self.vy > 0 then
        self.y = self.y + self.vy
        self.vy = self.vy - 0.2
        if self.y <= 0 then self.y, self.vy = 0, 0 end
    end
    for i = #self.obst, 1, -1 do
        local o = self.obst[i]
        o.x = o.x - self.speed
        if o.x < -4 then table.remove(self.obst, i) end
    end
    self.gap = self.gap - self.speed
    if self.gap <= 0 then
        self.obst[#self.obst + 1] = { x = self.pw + 1, kind = math.random(#self.cacti) }
        self.gap = 15 * self.speed + 10 + math.random(0, 25)   -- Platz zum Landen und neu Abspringen
    end
    if self:hit() then self.state = "over" end
end

function Dino:draw(F)
    local sx, ground = self.sx, F.h - 1
    gFill(F, 1, 1, F.w, F.h, colors.white)
    gText(F, 1, ground + 1, string.rep("\131", F.w), colors.black, colors.white)   -- Bodenlinie
    for _, o in ipairs(self.obst) do
        local rows = self.cacti[o.kind]
        gSprite(F, rows, (math.floor(o.x) - 1) * sx + 1, ground - #rows + 1, self.palette, sx)
    end
    local running = (self.y == 0) and (math.floor(self.ticks / 3) % 2 == 1)
    gSprite(F, running and self.sprite2 or self.sprite, (self.x - 1) * sx + 1,
            ground - 4 - math.floor(self.y + 0.5), self.palette, sx)
    local points = string.format("%05d", self.score)
    gText(F, F.w - #points, 1, points, colors.black, colors.white)
end

Games.add(Dino)

-- ---------- PONG ----------
-- Wer zuerst 10 Punkte hat, gewinnt. Gegen den Computer oder zu zweit.
local Pong = { name = "pong", title = "PONG", color = colors.purple, fg = colors.black, noBest = true, cpu = true,
               help = "Tippe auf deine Seite: der Schlaeger faehrt dorthin. Tasten: W/S und Pfeile." }

function Pong:init(F)
    self.w, self.h = F.w, F.h
    self.len = math.max(3, math.floor(F.h / 4))
    self.p1, self.p2 = F.h / 2, F.h / 2          -- Mitte der Schlaeger
    self.t1, self.t2 = self.p1, self.p2          -- wohin sie fahren sollen
    self.s1, self.s2, self.score, self.dt = 0, 0, 0, 0.05
    self.base = math.max(0.45, F.w / 70)         -- Ballgeschwindigkeit in Zeichen je Schritt
    self.cpu = Pong.cpu
    self:serve((math.random(2) == 1) and 1 or -1)
end

function Pong:serve(dir)
    self.bx, self.by = self.w / 2, self.h / 2
    self.vx, self.vy = dir * self.base, (math.random() * 2 - 1) * 0.4
    self.wait = 14
end

function Pong:clamp(v)
    local half = self.len / 2
    return math.max(half + 0.5, math.min(self.h - half + 0.5, v))
end

function Pong:tap(x, y)
    if self.cpu or x <= self.w / 2 then self.t1 = self:clamp(y) else self.t2 = self:clamp(y) end
end

function Pong:key(code)
    if code == keys.w then self.t1 = self:clamp(self.t1 - 3)
    elseif code == keys.s then self.t1 = self:clamp(self.t1 + 3)
    elseif code == keys.up then
        if self.cpu then self.t1 = self:clamp(self.t1 - 3) else self.t2 = self:clamp(self.t2 - 3) end
    elseif code == keys.down then
        if self.cpu then self.t1 = self:clamp(self.t1 + 3) else self.t2 = self:clamp(self.t2 + 3) end
    end
end

local function approach(v, target, step)
    if math.abs(target - v) <= step then return target end
    return v + ((target > v) and step or -step)
end

function Pong:point(first)
    if first then self.s1 = self.s1 + 1 else self.s2 = self.s2 + 1 end
    self.score = self.s1
    if self.s1 >= 10 or self.s2 >= 10 then
        self.state = "over"
        self.result = ((self.s1 > self.s2) and "Links" or "Rechts") .. " gewinnt " .. self.s1 .. " : " .. self.s2
    else
        self:serve(first and 1 or -1)   -- Aufschlag zum Verlierer des Punkts
    end
end

function Pong:update()
    if self.cpu then
        -- Der Computer folgt dem Ball, aber nicht beliebig schnell.
        self.t2 = self:clamp((self.vx > 0) and self.by or self.h / 2)
        self.p2 = approach(self.p2, self.t2, 0.42)
    else
        self.p2 = approach(self.p2, self.t2, 1.2)
    end
    self.p1 = approach(self.p1, self.t1, 1.2)
    if self.wait > 0 then
        self.wait = self.wait - 1
        return
    end
    local oldX = self.bx
    self.bx, self.by = self.bx + self.vx, self.by + self.vy
    if self.by < 1 then self.by, self.vy = 2 - self.by, -self.vy end
    if self.by > self.h then self.by, self.vy = 2 * self.h - self.by, -self.vy end
    local half = self.len / 2 + 0.6
    local faceL, faceR = 4, self.w - 3              -- Kanten der Schlaeger zum Feld hin
    local function bounce(center, face)
        self.bx = 2 * face - self.bx
        self.vx = -self.vx * 1.05
        local limit = self.base * 3
        self.vx = math.max(-limit, math.min(limit, self.vx))
        self.vy = math.max(-1.1, math.min(1.1, self.vy + (self.by - center) / half * 0.45))
    end
    if self.vx < 0 and oldX >= faceL and self.bx < faceL and math.abs(self.by - self.p1) <= half then
        bounce(self.p1, faceL)
    elseif self.vx > 0 and oldX <= faceR and self.bx > faceR and math.abs(self.by - self.p2) <= half then
        bounce(self.p2, faceR)
    elseif self.bx < 0 then
        self:point(false)
    elseif self.bx > self.w + 1 then
        self:point(true)
    end
end

function Pong:draw(F)
    gFill(F, 1, 1, F.w, F.h, colors.black)
    local mid = math.floor(F.w / 2)
    for y = 1, F.h, 2 do gFill(F, mid, y, 1, 1, colors.gray) end
    local score = self.s1 .. "   " .. self.s2
    gText(F, mid - math.floor(#score / 2) + 1, 1, score, colors.white, colors.black)
    local top1 = math.floor(self.p1 - self.len / 2 + 0.5)
    local top2 = math.floor(self.p2 - self.len / 2 + 0.5)
    gFill(F, 2, top1, 2, self.len, colors.white)
    gFill(F, F.w - 2, top2, 2, self.len, self.cpu and colors.lightGray or colors.white)
    gFill(F, self.bx, self.by + 0.5, 2, 1, colors.yellow)
end

Games.add(Pong)

-- ---------- Rahmen: Menue, Kopfzeile, Takt ----------
function Games:field()
    local y = UI.bh() + 1
    return { x = 1, y = y, w = Kernel.w, h = Kernel.h - y }
end

function Games:loadBest()
    local t = Store.load(self.dbFile)
    if not t then return end
    for name, v in pairs(t) do
        if type(name) == "string" and type(v) == "number" then self.best[name] = v end
    end
end

function Games:saveBest() Store.save(self.dbFile, self.best) end

function Games:start(def)
    local F = self:field()
    local g = setmetatable({ def = def, fw = F.w, fh = F.h, state = "ready", score = 0 }, { __index = def })
    math.randomseed(os.epoch("utc") % 1000000)
    g:init(F)
    self.game, self.view, self.paused = g, "play", false
end

-- Wird gerufen, wenn ein Spiel gerade zu Ende gegangen ist.
function Games:finish(g)
    g.overAt = os.clock()
    if not g.def.noBest and g.score > (self.best[g.def.name] or 0) then
        self.best[g.def.name] = g.score
        g.record = true
        self:saveBest()
    end
end

-- Eingabe ans Spiel. Die erste startet es, nach dem Ende beginnt sie sofort ein neues.
function Games:input(kind, a, b)
    local g = self.game
    if not g or self.view ~= "play" then return end
    os.queueEvent("gts_game")   -- weckt den Takt-Dienst
    if self.paused then
        self.paused = false
        return
    end
    if g.state == "over" then
        -- Kurze Sperre, damit ein letzter hektischer Tipp nicht sofort neu startet.
        if os.clock() - (g.overAt or 0) > 0.7 then
            self:start(g.def)
            self.game.state = "run"
        end
        return
    end
    if g.state == "ready" then g.state = "run" end
    if kind == "tap" then g:tap(a, b) else g:key(a) end
end

function Games:onKey(code) self:input("key", code) end
function Games:onLeave() if self.game and self.game.state == "run" then self.paused = true end end

-- Hintergrund-Dienst: der Takt der Spiele. Laeuft nur, wenn der Reiter offen ist.
function Games:service()
    while true do
        local g = self.game
        if g and g.state == "run" and not self.paused and Kernel.app == self then
            os.sleep(g.dt)
            if self.game == g and g.state == "run" and not self.paused and Kernel.app == self then
                local ok, err = pcall(g.update, g)
                if not ok then
                    Kernel.log("FEHLER", "games." .. g.def.name .. ": " .. tostring(err))
                    g.state = "over"
                end
                if g.state == "over" then self:finish(g) end
                Kernel.invalidate()
            end
        else
            os.pullEvent("gts_game")   -- schlafen, bis wieder gespielt wird
        end
    end
end

function Games:drawMenu()
    local w, h, bh = Kernel.w, Kernel.h, UI.bh()
    local narrow = UI.narrow()
    local n = #self.defs
    local top = UI.header("GAMES", n .. " Spiele", {
        { text = narrow and "\17" or (Apps.byId.luaapps and "\17 LUA APPS" or "\17 HOME"),
          onClick = function() Kernel.open(Apps.byId.luaapps and "luaapps" or "home") end },
    })
    local cols = narrow and 1 or ((w >= 70) and n or 2)
    local tw = math.floor((w - 1 - cols) / cols)
    local th = narrow and 2 or ((bh >= 2) and 7 or 4)
    for i, def in ipairs(self.defs) do
        local x = 2 + ((i - 1) % cols) * (tw + 1)
        local y = top + math.floor((i - 1) / cols) * (th + 1)
        -- Karte: farbiges Titelfeld, darunter der Rekord
        local band = th - (narrow and 0 or 2)
        UI.card(x, y, tw, th)
        if narrow then
            UI.text(x, y, "\149", def.color)
            UI.text(x, y + 1, "\149", def.color)
            UI.text(x + 2, y, def.title, colors.white)
        else
            UI.fill(x, y, tw, band, def.color)
            UI.text(x + math.floor((tw - #def.title) / 2), y + math.floor((band - 1) / 2), def.title, def.fg, def.color)
        end
        local best = def.noBest and "bis 10 Punkte" or ("Rekord: " .. (self.best[def.name] or 0))
        if #best > tw - 2 then best = def.noBest and "bis 10" or tostring(self.best[def.name] or 0) end
        if narrow then
            UI.text(x + 2, y + 1, best, colors.lightGray)
        else
            UI.text(x + 2, y + band, best, colors.lightGray)
            UI.text(x + tw - 9, y + band + 1, "SPIELEN \16", colors.lime)
        end
        UI.hit(x, y, tw, th, function() self:start(def) end)
    end
    UI.surface = colors.black
    if not narrow then
        local y = top + math.ceil(n / cols) * (th + 1)
        if y + #self.defs + 1 <= h - 1 then
            UI.section(2, y, "STEUERUNG", w - 3)
            y = y + 2
        end
        for _, def in ipairs(self.defs) do
            if y > h - 1 then break end
            UI.text(2, y, def.title, colors.white)
            UI.text(10, y, def.help:sub(1, w - 11), colors.lightGray)
            y = y + 1
        end
    end
end

function Games:draw()
    if self.view ~= "play" or not self.game then return self:drawMenu() end
    local w = Kernel.w
    local narrow = UI.narrow()
    local F = self:field()
    local g = self.game
    if g.fw ~= F.w or g.fh ~= F.h then   -- Bildschirm hat sich geaendert: neu beginnen
        self:start(g.def)
        g = self.game
    end

    -- Kopfzeile
    local info
    if g.def.noBest then
        info = g.s1 .. " : " .. g.s2
    else
        info = "Punkte " .. g.score .. (narrow and "" or ("   Rekord " .. (self.best[g.def.name] or 0)))
    end
    local actions = {}
    if g.def == Pong and not narrow then
        actions[#actions + 1] = { text = Pong.cpu and "GEGNER: CPU" or "2 SPIELER", onClick = function()
            Pong.cpu = not Pong.cpu
            self:start(Pong)
        end }
    end
    -- schmal ohne Rand in den Buttons, damit die Kopfzeile einzeilig bleibt
    actions[#actions + 1] = { text = "NEU", w = narrow and 3 or nil, onClick = function() self:start(g.def) end }
    actions[#actions + 1] = { text = "MENUE", w = narrow and 5 or nil, style = "primary", onClick = function()
        self.view, self.game = "menu", nil
    end }
    if narrow then
        UI.header(g.def.title .. " " .. (g.def.noBest and info or g.score), nil, actions, nil, true)
    else
        UI.header(g.def.title, info, actions, nil, true)
    end

    g:draw(F)
    UI.hit(F.x, F.y, F.w, F.h, function(cx, cy) self:input("tap", cx - F.x + 1, cy - F.y + 1) end)

    -- Hinweis in der Feldmitte
    local lines
    if self.paused then
        lines = { "PAUSE", narrow and "Tippen = weiter" or "Tippen zum Weiterspielen" }
    elseif g.state == "ready" then
        lines = { g.def.title, "Tippen zum Start" }
    elseif g.state == "over" then
        lines = { g.result or "GAME OVER", g.def.noBest and "" or ("Punkte: " .. g.score .. (g.record and "  NEUER REKORD!" or "")),
                  narrow and "Tippen = neu" or "Tippen fuer ein neues Spiel" }
    end
    if lines then
        local bw = 0
        for _, line in ipairs(lines) do bw = math.max(bw, #line) end
        bw = math.min(F.w, bw + 6)
        local bx = math.floor((w - bw) / 2) + 1
        local by = F.y + math.floor((F.h - #lines - 2) / 2)
        UI.card(bx, by, bw, #lines + 2)
        UI.line(bx, by, bw, colors.lime, "top")
        for i, line in ipairs(lines) do
            line = line:sub(1, bw)
            UI.text(math.floor((w - #line) / 2) + 1, by + i, line, (i == 1) and colors.lime or colors.white)
        end
        UI.surface = colors.black
    end
end

Games:loadBest()
Apps.register(Games)

-- ======================================================================
-- [14] EXTRAS: Geraete von Advanced Peripherals (alle freiwillig)
-- ======================================================================
-- Haengen am selben Kabel (Wired Modem) wie die Lager-Kisten oder direkt
-- am Computer und werden von selbst erkannt. Fehlt ein Geraet, fehlt nur
-- sein Komfort - das OS laeuft auch ganz ohne Peripherie-Mods:
--   player_detector       Wache: kommt ein fremder Spieler in die Naehe,
--                         gibt es eine Meldung, einen Ton, eine Nachricht an
--                         den Besitzer und das OS sperrt sich.
--   chat_box              schickt dem Besitzer Meldungen (Alarm, Funde,
--                         Ergebnisse der Turtle-Programme) als Toast.
--   speaker               Ton bei Alarm und Funden
--   environment_detector  Biom, Wetter und Mond in INFO
Extras = { alarm = nil, alerted = {}, outbox = {}, nearby = nil, env = nil }

Extras.KINDS = {
    player_detector = "Wache (Spieler)", chat_box = "Chat-Meldungen", speaker = "Ton",
    environment_detector = "Umgebung", me_bridge = "ME Bridge", rs_bridge = "RS Bridge",
    geo_scanner = "Geo Scanner", energy_detector = "Energie",
}

function Extras.find(kind)
    for _, e in ipairs(Kernel.hw.all or {}) do
        if e.kind == kind then
            local ok, dev = pcall(peripheral.wrap, e.name)
            if ok and dev then return dev, e.name end
        end
    end
end

-- Meldung an den Besitzer (Chat Box). Wird nacheinander verschickt.
function Extras.tell(text, title)
    local owner = Settings.get("owner")
    if READONLY or type(owner) ~= "string" or owner == "" or not Extras.find("chat_box") then return end
    if #Extras.outbox < 12 then Extras.outbox[#Extras.outbox + 1] = { text = tostring(text):sub(1, 90), title = title or "GTS OS" } end
end

function Extras.beep(alarm)
    local sp = Extras.find("speaker")
    if sp then
        pcall(sp.playNote, alarm and "bell" or "chime", alarm and 3 or 1, alarm and 18 or 12)
        if alarm then pcall(sp.playNote, "bell", 3, 12) end
    end
end

local function isTrusted(name)
    name = tostring(name):lower()
    if name == tostring(Settings.get("owner") or ""):lower() then return true end
    for _, t in ipairs(Settings.get("trusted") or {}) do
        if tostring(t):lower() == name then return true end
    end
    return false
end

-- Ein Durchlauf der Wache (alle 3 Sekunden).
function Extras.watch()
    local det = Extras.find("player_detector")
    if not det then Extras.nearby = nil return end
    local ok, list = pcall(det.getPlayersInRange, Settings.get("alarmRadius") or 24)
    if not ok or type(list) ~= "table" then return end
    Extras.nearby = list
    local owner = Settings.get("owner")
    if type(owner) ~= "string" or owner == "" then return end     -- ohne Besitzer kein Alarm
    local now = os.clock()
    for _, name in ipairs(list) do
        if type(name) == "string" and not isTrusted(name) then
            Extras.alarm = { name = name:sub(1, 16), t = now }
            if not Extras.alerted[name] or now - Extras.alerted[name] > 120 then
                Extras.alerted[name] = now
                Kernel.log("WARN", "Alarm: " .. name .. " in der Naehe")
                Kernel.notify("ALARM: " .. name .. " in der Naehe!", colors.red)
                Extras.beep(true)
                Extras.tell(name .. " ist an deiner Basis!", "GTS ALARM")
                if not Kernel.locked then Kernel.lock() end
            end
        end
    end
    if Extras.alarm and now - Extras.alarm.t > 60 then Extras.alarm = nil end
end

function Extras.service()
    while true do
        pcall(Extras.watch)
        local msg = table.remove(Extras.outbox, 1)
        if msg then
            local box = Extras.find("chat_box")
            local owner = Settings.get("owner")
            if box and owner and owner ~= "" then
                -- Die Chat Box meldet Fehler (Spieler offline ...) als Rueckgabe, nicht als Fehler.
                local ok, res = pcall(box.sendToastToPlayer, msg.text, msg.title, owner, "GTS")
                if not (ok and res) then pcall(box.sendMessageToPlayer, msg.text, owner, "GTS") end
            end
        end
        local env = Extras.find("environment_detector")
        if env then
            local e = {}
            pcall(function()
                e.biome = env.getBiome():gsub("^.-:", "")
                e.weather = env.isThunder() and "Gewitter" or (env.isRaining() and "Regen" or "klar")
                e.moon = env.getMoonName()
            end)
            Extras.env = e
        else
            Extras.env = nil
        end
        os.sleep(3)
    end
end

-- ======================================================================
-- [14b] INFO
-- ======================================================================
-- Alle Systeminformationen auf einen Blick: Geraet, Anzeige, Funk,
-- Schwarm, angeschlossene Geraete und Speicher.
-- ======================================================================
-- [15] SYSTEM: Hilfe, Papierkorb, Backup, Update, System-Check,
--      Speicher-Wache, Absturz-Bildschirm, sicherer Modus (v8.0)
-- ======================================================================
Sys = {
    BOOT_DB    = "/gts/start.db",        -- Abstuerze, sicherer Modus
    TRASH_DIR  = "/gts/papierkorb",
    TRASH_DB   = "/gts/papierkorb.db",
    TRASH_DAYS = 7,
    BACKUP_DIR = "/gts/backup",
    BACKUP_KEEP = 3,
    BACKUP_LABEL = "GTS-BACKUP",          -- Diskette mit diesem Namen bekommt eine Kopie
    REPO       = "https://raw.githubusercontent.com/Jonsixx101/gts-os/",
    GIST       = "https://gist.githubusercontent.com/Jonsixx101/f9a2f67862080feabe3f31fa70914957/raw",
    UPD_DB     = "/gts/update.db",
    UPD_OLD    = "/gts/update_alt.lua",
    UPD_BACK   = "/gts/update_zurueck.db",
    PART       = 32768,                   -- Pruefsumme je 32 KB (mit Pause dazwischen)
    safe = false, crashes = 0, started = 0,
    upd = { state = "idle", msg = "" },
}
-- Dateiname, unter dem das OS laeuft (wird beim Update ersetzt)
do
    local ok, p = pcall(function() return shell.getRunningProgram() end)
    Sys.SELF = "/" .. fs.combine((ok and type(p) == "string" and p ~= "") and p or "startup.lua", "")
end

-- ---------- Hilfe "?" ----------
Sys.HELP = {
    notes = { "Notizen schreiben, bearbeiten und drucken.",
              "NEU + legt eine Notiz an, EDIT oeffnet den Editor.",
              "DEL legt sie in den Papierkorb: INFO > SYSTEM, 7 Tage zurueckholbar." },
    swarm = { "Alle Turtles mit Status, Tank, Inventar und Position.",
              "Turtle antippen: Programme (DD, CHUNK, TEST), Werkzeuge und Befehle.",
              "PLANER: DD oder CHUNK an alle freien Turtles, Richtungen und Spuren verteilt er selbst.",
              "NAME und FARBE in der Turtle-Ansicht; die Farbe gilt auch auf der KARTE.",
              "FUNDE und KARTE zeigen, was die Turtles entdeckt haben.",
              "KARTE: welche Richtung oben ist, stellt INFO > EINSTELLUNGEN > SCHWARM ein. GPS zeigt die letzte GPS-Messung je Turtle.",
              "Neue Turtle: DATEN > TURTLE-DISK schreiben und die Turtle daneben starten." },
    lager = { "Alle Kisten am Kabel (Wired Modem) als ein grosses Lager.",
              "Item antippen: Menge in die EIN/AUS-Kiste holen, Kategorie, Mindestmenge, Favorit.",
              "EINLAGERN leert die EIN/AUS-Kiste ins Lager.",
              "AUSWAHL: mehrere Items antippen und zusammen verschieben.",
              "KATEGORIEN: eigene anlegen, mit \17 \16 die Reihenfolge in der Leiste aendern.",
              "Ein Mod-Ordner nimmt die ganze Mod mit, Vanilla-Items bleiben einzeln." },
    data  = { "Disketten im Laufwerk: Notizen und Programme sichern oder kopieren.",
              "TURTLE-DISK richtet neue Turtles ein, GPS-DISK macht GPS-Sender.",
              "Aktionen mit Disketten fragen immer nach dem Sperrcode." },
    web   = { "Suchen wie bei Google: WEB, WIKIPEDIA oder MC WIKI waehlen, Begriff oder Adresse eintippen.",
              "Treffer antippen oeffnet die Seite zum Lesen, Links darin antippen.",
              "\4 MERKEN legt ein Lesezeichen an. \17 \16 = zurueck und vor, START = Suchseite." },
    calc  = { "Taschenrechner mit Prozent und Stapeln (64er).", "NETHER rechnet Koordinaten Oberwelt <-> Nether um." },
    nether = { "Rechnet Koordinaten zwischen Oberwelt und Nether um (geteilt bzw. mal 8).",
               "Die letzten Umrechnungen bleiben gespeichert." },
    shell = { "CraftOS-Shell im Fenster: edit, pastebin, wget und eigene Programme.",
              "Strg+T beendet das laufende Programm, nicht das OS." },
    luaapps = { "Deine Programme in /scripts, mit Ordnern.",
                "START fuehrt aus, EDIT oeffnet den Editor, DEL legt in den Papierkorb.",
                "Ordner turtle: Programme fuer die Turtles (Start in SCHWARM)." },
    claude = { "Claude ist der Begleit-Droide der Basis: eine Turtle mit Schwert und allen Werkzeugen.",
               "Im Spiel: $claude komm, folge, bleib, heim, frei, wache, patrouille, hilfe ($ = unsichtbar).",
               "STATUS: Befehle und Steuerkreuz. KARTE: was Claude kennt; antippen = hinfliegen, Wegpunkt, Sperrzone.",
               "MODI: wie Claude sich verhaelt (frei, Patrouille, Wache, Kampf, Crafting, Stimme, Sicherheit).",
               "Er baut nie etwas ab, bleibt ueber Wasser, 100 Bloecke beim PC und weg von Create-Maschinen." },
    info  = { "Geraet, Funk, Speicher und Erweiterungen auf einen Blick.",
              "EINSTELLUNGEN: Passwoerter, Design, Lager, Schwarm.",
              "SYSTEM: Check, Update, Backup, Papierkorb, Aufraeumen, Einrichtung und sicherer Modus.",
              "Die Uhr unten rechts antippen: alle Mitteilungen." },
}

-- ---------- Start-Datei: Abstuerze und sicherer Modus ----------
function Sys.bootInit()
    local b = Store.load(Sys.BOOT_DB) or {}
    Sys.safe = b.safe == true
    if b.restored then
        Kernel.notify("Backup zurueckgeholt: " .. tostring(b.restored) .. " Dateien", colors.lime, "info", "backup")
        b.restored = nil
        Store.save(Sys.BOOT_DB, b)
    end
    local now, n = math.floor(os.epoch("utc") / 1000), 0
    for _, t in ipairs(type(b.crashes) == "table" and b.crashes or {}) do
        if type(t) == "number" and now - t < 600 then n = n + 1 end
    end
    Sys.crashes = n
end

function Sys.setSafe(on)
    local b = Store.load(Sys.BOOT_DB) or {}
    b.safe = on and true or nil
    if not on then b.crashes = nil end
    Store.save(Sys.BOOT_DB, b)
    Sys.safe = on and true or false
end

-- ---------- Papierkorb (Notizen, LUA APPS) ----------
function Sys.trashList()
    local t, out = Store.load(Sys.TRASH_DB), {}
    for _, e in ipairs(type(t) == "table" and t or {}) do
        if type(e) == "table" and type(e.id) == "string" and type(e.from) == "string"
           and fs.exists(fs.combine(Sys.TRASH_DIR, e.id)) then
            out[#out + 1] = e
        end
    end
    return out
end

function Sys.trashPut(path)
    if type(path) ~= "string" or not fs.exists(path) or fs.isDir(path) then return false end
    local list, now = Sys.trashList(), os.epoch("utc")
    local id = now .. "_" .. math.random(1000, 9999)
    local size = fs.getSize(path)
    if not pcall(fs.move, path, fs.combine(Sys.TRASH_DIR, id)) then return false end
    table.insert(list, 1, { id = id, name = fs.getName(path), from = "/" .. fs.combine(path, ""),
                            t = math.floor(now / 1000), size = size })
    Store.save(Sys.TRASH_DB, list)
    return true
end

-- Loeschen ueber den Papierkorb (klappt das nicht: wirklich loeschen).
-- Rueckgabe: ok, true wenn im Papierkorb.
function Sys.delete(path)
    if Sys.trashPut(path) then return true, true end
    return pcall(fs.delete, path), false
end

function Sys.trashRestore(id)
    local list = Sys.trashList()
    for i, e in ipairs(list) do
        if e.id == id then
            -- nur zurueck in die Ordner, aus denen der Papierkorb befuellt wird
            local to = e.from
            local okDir = to:find("^" .. CONFIG.notesDir .. "/") or to:find("^" .. CONFIG.scriptDir .. "/")
            if not okDir or to:find("..", 1, true) then to = "/" .. fs.combine(CONFIG.scriptDir, e.name) end
            local base, n = to, 2
            while fs.exists(to) do
                local stem, ext = base:match("^(.-)(%.%w+)$")
                to = stem and (stem .. "_" .. n .. ext) or (base .. "_" .. n)
                n = n + 1
            end
            if not pcall(fs.move, fs.combine(Sys.TRASH_DIR, e.id), to) then return false, "Zurueckholen fehlgeschlagen" end
            table.remove(list, i)
            Store.save(Sys.TRASH_DB, list)
            return true, fs.getName(to)
        end
    end
    return false, "Nicht mehr im Papierkorb"
end

-- Endgueltig loeschen: eine Datei (id), alles (id = nil) oder alles,
-- was aelter als maxAge Sekunden ist (Standard 7 Tage).
function Sys.trashDrop(id, maxAge)
    local now, keep, known, n = math.floor(os.epoch("utc") / 1000), {}, {}, 0
    for _, e in ipairs(Sys.trashList()) do
        local old = maxAge and (now - (tonumber(e.t) or 0) > maxAge)
        if (maxAge and old) or (not maxAge and (id == nil or e.id == id)) then
            pcall(fs.delete, fs.combine(Sys.TRASH_DIR, e.id))
            n = n + 1
        else
            keep[#keep + 1], known[e.id] = e, true
        end
    end
    -- Reste ohne Eintrag (z.B. nach einem Absturz) mit wegraeumen
    for _, name in ipairs(fs.isDir(Sys.TRASH_DIR) and fs.list(Sys.TRASH_DIR) or {}) do
        if not known[name] then pcall(fs.delete, fs.combine(Sys.TRASH_DIR, name)) end
    end
    Store.save(Sys.TRASH_DB, keep)
    return n
end

-- ---------- Backup (Einstellungen, Lager-Kategorien, Funde, Notizen) ----------
function Sys.backupFixed()
    return { CONFIG.settingsFile, Kat.file, CONFIG.lagerDb, CONFIG.dbFile, CONFIG.netherDb }
end

function Sys.backupPaths()
    local out = Sys.backupFixed()
    for _, name in ipairs(fs.isDir(CONFIG.notesDir) and fs.list(CONFIG.notesDir) or {}) do
        local p = "/" .. fs.combine(CONFIG.notesDir, name)
        if not fs.isDir(p) then out[#out + 1] = p end
    end
    return out
end

-- Disketten mit dem Namen GTS-BACKUP: { drive, path }
function Sys.backupDrives()
    local out = {}
    for _, drive in ipairs(Kernel.hw.drives or {}) do
        local ok, path = pcall(function()
            if disk.isPresent(drive) and disk.hasData(drive) and disk.getLabel(drive) == Sys.BACKUP_LABEL then
                return disk.getMountPath(drive)
            end
        end)
        if ok and path then out[#out + 1] = { drive = drive, path = path } end
    end
    return out
end

-- Alle Backups, neueste zuerst: { name, path, size, src, label }
function Sys.backupList(pcOnly)
    local out = {}
    for _, name in ipairs(fs.isDir(Sys.BACKUP_DIR) and fs.list(Sys.BACKUP_DIR) or {}) do
        local day = name:match("^(%d%d%d%d%-%d%d%-%d%d)%.db$")
        if day then
            local path = fs.combine(Sys.BACKUP_DIR, name)
            out[#out + 1] = { name = day, path = path, size = fs.getSize(path), src = "PC",
                              label = (day == os.date("%Y-%m-%d")) and "heute" or (day:sub(9, 10) .. "." .. day:sub(6, 7) .. "." .. day:sub(1, 4)) }
        end
    end
    table.sort(out, function(a, b) return a.name > b.name end)
    if not pcOnly then
        for _, d in ipairs(Sys.backupDrives()) do
            local path = fs.combine(d.path, "gts_backup.db")
            if fs.exists(path) then
                out[#out + 1] = { name = "disk", path = path, size = fs.getSize(path), src = "Diskette", label = "Diskette (" .. d.drive .. ")" }
            end
        end
    end
    return out
end

function Sys.backupMake()
    local files, n = {}, 0
    for _, p in ipairs(Sys.backupPaths()) do
        local s = Store.read(p)
        if s then files[p], n = s, n + 1 end
    end
    local data = { v = VERSION, t = math.floor(os.epoch("utc") / 1000), files = files }
    local ok, text = pcall(textutils.serialize, data, { compact = true })
    if not ok then ok, text = pcall(textutils.serialize, data) end
    if not ok then return false, "Sichern fehlgeschlagen" end
    local path = fs.combine(Sys.BACKUP_DIR, os.date("%Y-%m-%d") .. ".db")
    local free = fs.getFreeSpace("/")
    local old = fs.exists(path) and fs.getSize(path) or 0
    if type(free) == "number" and free + old < #text + 40000 then return false, "Zu wenig Speicher fuer ein Backup" end
    if not Store.write(path, text) then return false, "Schreiben fehlgeschlagen" end
    local list = Sys.backupList(true)
    for i = Sys.BACKUP_KEEP + 1, #list do pcall(fs.delete, list[i].path) end
    -- dazu eine Kopie auf jede GTS-BACKUP-Diskette
    local disks = 0
    for _, d in ipairs(Sys.backupDrives()) do
        local dp = fs.combine(d.path, "gts_backup.db")
        local dfree = fs.getFreeSpace(d.path)
        local dold = fs.exists(dp) and fs.getSize(dp) or 0
        if (type(dfree) ~= "number" or dfree + dold >= #text * 2) and Store.write(dp, text) then disks = disks + 1 end
    end
    Settings.set("backupDay", os.date("%Y-%m-%d"))
    Kernel.log("INFO", "Backup: " .. n .. " Dateien, " .. fmtSize(#text) .. ((disks > 0) and " (+ Diskette)" or ""))
    return true, n .. " Dateien gesichert" .. ((disks > 0) and " (+ Diskette)" or "")
end

-- Zurueckholen: nur bekannte Dateien und Notizen (eine fremde Diskette
-- koennte sonst z.B. startup.lua ueberschreiben).
function Sys.backupRestore(path)
    local t = Store.load(path)
    if type(t) ~= "table" or type(t.files) ~= "table" then return false, "Backup ist kaputt" end
    local allowed, n = {}, 0
    for _, p in ipairs(Sys.backupFixed()) do allowed[p] = true end
    for p, text in pairs(t.files) do
        local note = type(p) == "string" and p:match("^" .. CONFIG.notesDir .. "/([%w_%-%.]+)$")
        if type(text) == "string" and (allowed[p] or (note and not note:find("^%.+$"))) then
            if Store.write(p, text) then n = n + 1 end
        end
    end
    if n == 0 then return false, "Nichts zum Zurueckholen" end
    Kernel.log("INFO", "Backup zurueckgeholt: " .. n .. " Dateien")
    local b = Store.load(Sys.BOOT_DB) or {}
    b.restored = n
    Store.save(Sys.BOOT_DB, b)
    return true, n .. " Dateien zurueckgeholt - Neustart ..."
end

-- ---------- Speicher-Wache ----------
function Sys.diskCheck()
    local free = fs.getFreeSpace("/")
    if type(free) ~= "number" then return end
    if free < 60000 then
        -- erst selbst Platz schaffen: alter Papierkorb, altes Log, alte Backups
        Sys.trashDrop(nil, 86400)
        pcall(Sys.clean, Sys.cleanScan())
        pcall(fs.delete, CONFIG.logFile .. ".alt")
        local list = Sys.backupList(true)
        for i = 2, #list do pcall(fs.delete, list[i].path) end
        free = fs.getFreeSpace("/")
    end
    if free < 40000 then
        if not Sys.lowDisk then
            Sys.lowDisk = true
            Kernel.notify("Speicher fast voll: noch " .. fmtSize(free) .. " frei", colors.red, "info", "check")
        end
    elseif free > 60000 then
        Sys.lowDisk = false
    end
end

-- ---------- Aufraeumen (1.2.1) ----------
-- Positivliste: nur Dateien, die das OS selbst anlegt und die nachweislich
-- ueberfluessig sind. Unbekanntes wird nie angefasst, Daten des Nutzers
-- (Notizen, Scripts, Disketten-Kopien) werden nur angezeigt.
--   muell = weg damit (auch automatisch), frage = nur wenn man es auswaehlt.
local function onHdd(p)
    local ok, d = pcall(fs.getDrive, p)
    if ok and d then return d == "hdd" end
    return not (p:find("^rom") or p:find("^disk"))
end
local function cleanWalk(dir, depth, fn)
    local ok, list = pcall(fs.list, dir)
    if not ok then return end
    for _, name in ipairs(list) do
        local p = fs.combine(dir, name)
        if onHdd(p) then
            if fs.isDir(p) then
                if depth > 0 then cleanWalk(p, depth - 1, fn) end
            else
                fn(p, name)
            end
        end
    end
end
local function cleanSize(path)
    if fs.isDir(path) then
        local n = 0
        cleanWalk(path, 4, function(p) local ok, k = pcall(fs.getSize, p) n = n + (ok and tonumber(k) or 0) end)
        return n
    end
    local ok, n = pcall(fs.getSize, path)
    return ok and n or 0
end

function Sys.cleanScan()
    local items, seen = {}, {}
    local function add(path, why, kind, act)
        path = fs.combine(path, "")
        if seen[path] or not fs.exists(path) then return end
        seen[path] = true
        items[#items + 1] = { path = path, why = why, kind = kind, act = act, size = cleanSize(path) }
    end
    local self = fs.combine(Sys.SELF or "startup.lua", "")
    cleanWalk("", 5, function(p, name)
        if name:sub(-4) == ".neu" then
            -- halb geschrieben: nur wenn die Datei selbst heil daneben liegt
            if fs.exists(p:sub(1, -5)) then add(p, "halb geschrieben (Absturz)", "muell") end
        elseif name:sub(-4) == ".bak" and fs.exists(p:sub(1, -5)) and not p:find("^disk") then
            local base = p:sub(1, -5)
            local text = Store.read(base)
            if text and type(textutils.unserialize(text)) == "table" then
                add(p, "Sicherungskopie (kommt beim Speichern wieder)", "frage")
            end
        end
    end)
    add(CONFIG.logFile .. ".alt", "altes Log", "muell")
    if not Sys.upd.pending and not fs.exists(Sys.UPD_DB) then
        add(Sys.UPD_OLD, "alte OS-Fassung vom letzten Update", "muell")
    end
    -- alte OS-Kopien im Hauptordner (gross, GTS-Kopf, nicht die laufende Datei)
    for _, name in ipairs(fs.list("")) do
        local p = fs.combine(name, "")
        if p ~= self and not fs.isDir(p) and onHdd(p) and (fs.getSize(p) or 0) > 100000 then
            local h = fs.open(p, "r")
            local head = h and ((h.readLine() or "") .. "\n" .. (h.readLine() or "")) or ""
            if h then h.close() end
            if type(head) == "string" and head:find("GTS OS", 1, true) and head:find("^%-%-") then
                add(p, "alte Kopie von GTS OS", "frage")
            end
        end
    end
    local list = Sys.backupList(true)
    for i = 2, #list do add(list[i].path, "aelteres Backup (" .. list[i].label .. ")", "frage") end
    if #Sys.trashList() > 0 then add(Sys.TRASH_DIR, "Papierkorb leeren", "frage", "trash") end
    table.sort(items, function(a, b)
        if a.kind ~= b.kind then return a.kind == "muell" end
        return a.size > b.size
    end)
    return items
end

-- Loescht die ausgewaehlten Eintraege. Rueckgabe: frei gewordene Bytes, Anzahl.
function Sys.clean(items, pick)
    local freed, n = 0, 0
    for _, it in ipairs(items) do
        local on
        if pick then on = pick(it) else on = it.kind == "muell" end
        if on then
            if it.act == "trash" then
                local k = Sys.trashDrop()
                if k > 0 then n, freed = n + k, freed + it.size end
            elseif fs.exists(it.path) and pcall(fs.delete, it.path) and not fs.exists(it.path) then
                n, freed = n + 1, freed + it.size
            end
        end
    end
    if n > 0 then Kernel.log("INFO", "Aufgeraeumt: " .. n .. " Dateien, " .. fmtSize(freed) .. " frei") end
    return freed, n
end

-- Wer belegt wie viel? (fuer AUFRAEUMEN)
function Sys.usage()
    local self = fs.combine(Sys.SELF or "startup.lua", "")
    local groups = {
        { "GTS OS", 0 }, { "Daten (Einstellungen, Lager ...)", 0 }, { "Backups", 0 }, { "Papierkorb", 0 },
        { "Notizen", 0 }, { "Scripts / LUA APPS", 0 }, { "Logs", 0 }, { "Sonstiges", 0 },
    }
    local function grp(p)
        if p == self then return 1 end
        if p:find("^gts/backup/") or p:find("^backups/") then return 3 end
        if p:find("^gts/papierkorb/") then return 4 end
        if p:find("^gts/") then return 2 end
        if p:find("^notes/") then return 5 end
        if p:find("^scripts/") then return 6 end
        if p:find("^sys/") then return 7 end
        return 8
    end
    cleanWalk("", 6, function(p)
        local g = groups[grp(p)]
        local ok, n = pcall(fs.getSize, p)
        g[2] = g[2] + (ok and tonumber(n) or 0)
    end)
    return groups
end

-- ---------- Ein-Knopf-Update (GitHub, Gist als Alternative) ----------
-- Laedt eine Datei (im Hintergrund-Dienst, wartet auf die HTTP-Antwort).
function Sys.fetch(url, timeout)
    if not http then return nil, "HTTP ist im Modpack/Server aus" end
    local ok, err = http.request{ url = url, binary = true }
    if ok == false then return nil, tostring(err or "Adresse gesperrt") end
    local timer = os.startTimer(timeout or 30)
    while true do
        local ev, a, b, c = os.pullEvent()
        if ev == "http_success" and a == url then
            local okR, body = pcall(b.readAll)
            pcall(b.close)
            if okR and type(body) == "string" then return body end
            return nil, "Lesefehler"
        elseif ev == "http_failure" and a == url then
            if type(c) == "table" and c.close then pcall(c.close) end     -- Antwort mit Fehlercode (404 ...)
            return nil, tostring(b or "keine Verbindung")
        elseif ev == "timer" and a == timer then
            return nil, "keine Antwort (Zeit abgelaufen)"
        end
    end
end

-- Pruefsummen je 32 KB (aus manifest.lua); dazwischen kurze Pausen.
function Sys.verify(body, parts)
    if type(parts) ~= "table" then return true end      -- Gist: nur der Lauf-Test
    if #parts ~= math.max(1, math.ceil(#body / Sys.PART)) then return false end
    for i, want in ipairs(parts) do
        local got = Net.toHex(Crypto.sha256.digest(body:sub((i - 1) * Sys.PART + 1, i * Sys.PART)))
        if type(want) ~= "string" or #want < 8 or got:sub(1, #want) ~= want then return false end
        os.queueEvent("gts_upd")
        os.pullEvent("gts_upd")
    end
    return true
end

-- Angezeigte Version aus manifest.lua (ab 1.1.0 "release", davor nur "version").
function Sys.rel(m)
    return tostring((type(m) == "table") and (m.release or ("V" .. tostring(m.version))) or "?")
end

function Sys.updSource() return (Settings.get("updSrc") == "gist") and "gist" or "github" end

-- Sucht nach einer neuen Fassung. quiet = automatische Suche (nur Mitteilung).
function Sys.updCheck(quiet)
    local u = Sys.upd
    if u.busy then return end
    u.busy, u.state, u.msg = true, "check", "Suche ..."
    Kernel.invalidate()
    local ok, err = pcall(function()
        if Sys.updSource() == "gist" then
            if EDITION ~= "pc" then error("Im Gist liegt nur die PC-Fassung", 0) end
            local body, e = Sys.fetch(Sys.GIST, 60)
            if not body then error(e, 0) end
            local v = body:match('local VERSION%s*=%s*"([^"]+)"')
            if not v or not body:find("GTS OS", 1, true) then error("Im Gist liegt kein GTS OS", 0) end
            u.man, u.entry, u.body = { version = v, release = body:match('local RELEASE%s*=%s*"([^"]+)"'), notes = {}, gist = true },
                                     { file = "gist", size = #body }, body
        else
            local text, e = Sys.fetch(Sys.REPO .. "main/manifest.lua?t=" .. os.epoch("utc"))
            if not text then error(e, 0) end
            local m = textutils.unserialize(text)
            if type(m) ~= "table" or type(m.version) ~= "string" or type(m.files) ~= "table" then error("manifest.lua ist kaputt", 0) end
            local entry = m.files[EDITION]
            if type(entry) ~= "table" or type(entry.file) ~= "string" or not entry.file:match("^[%w_%-%.]+$") then
                error("Keine Datei fuer diese Ausgabe", 0)
            end
            u.man, u.entry, u.body = m, entry, nil
        end
    end)
    u.busy = false
    if not ok then
        u.state, u.msg = "error", tostring(err)
    elseif verLess(VERSION, u.man.version) then
        u.state, u.msg = "found", Sys.rel(u.man) .. " ist da"
        if quiet and Settings.get("updSeen") ~= u.man.version then
            Settings.set("updSeen", u.man.version)
            Kernel.notify("Update " .. Sys.rel(u.man) .. " verfuegbar", colors.yellow, "info", "update")
        end
    else
        u.state, u.msg = "none", "Aktuell (" .. RELEASE .. ")"
    end
    if quiet then Settings.set("updDay", os.date("%Y-%m-%d")) end
    Kernel.invalidate()
end

-- Laedt, prueft und installiert die gefundene Fassung, dann Neustart.
-- Die alte Fassung wird gesichert, wenn Platz ist (sonst kommt sie im
-- Notfall wieder aus dem Repo: Tag v<alte Version>).
function Sys.updInstall()
    local u = Sys.upd
    if u.busy or u.state ~= "found" then return end
    u.busy = true
    Sys.updConfirm()            -- ein noch offenes Update gilt jetzt als gut
    local ok, err = pcall(function()
        local self = Sys.SELF
        if self:find("^/disk") then error("Das OS laeuft von einer Diskette", 0) end
        local body = u.body
        if not body then
            u.state, u.msg = "load", "Lade " .. Sys.rel(u.man) .. " ..."
            Kernel.invalidate()
            local e
            body, e = Sys.fetch(Sys.REPO .. "main/" .. u.entry.file .. "?t=" .. os.epoch("utc"), 90)
            if not body then error(e, 0) end
        end
        u.state, u.msg = "verify", "Pruefe ..."
        Kernel.invalidate()
        if u.entry.size and #body ~= u.entry.size then error("Download unvollstaendig (" .. #body .. " von " .. u.entry.size .. " Bytes)", 0) end
        if not Sys.verify(body, u.entry.parts) then error("Pruefsumme falsch: Download kaputt", 0) end
        if body:match('local VERSION%s*=%s*"([^"]+)"') ~= u.man.version then error("Falsche Version im Download", 0) end
        local ed = body:match('local EDITION%s*=%s*"(%w+)"')
        if ed ~= EDITION then error("Download ist fuer " .. tostring(ed) .. ", nicht fuer " .. EDITION, 0) end
        local fn, cerr = load(body, "=update", "t", {})
        if not fn then error("Download laeuft nicht: " .. tostring(cerr), 0) end
        local oldSize = fs.exists(self) and fs.getSize(self) or 0
        local free = fs.getFreeSpace("/")
        if type(free) == "number" and free + oldSize < #body + 20000 then
            error("Zu wenig Speicher: " .. fmtSize(#body + 20000 - free - oldSize) .. " fehlen", 0)
        end
        u.state, u.msg = "write", "Installiere ..."
        Kernel.invalidate()
        pcall(fs.delete, Sys.UPD_OLD)
        local backup
        if oldSize > 0 and (type(free) ~= "number" or free - (#body - oldSize) - oldSize > 40000) then
            if pcall(fs.copy, self, Sys.UPD_OLD) then backup = Sys.UPD_OLD end
        end
        -- erst merken, dann schreiben: stirbt der PC mittendrin, weiss der naechste Start Bescheid
        Store.save(Sys.UPD_DB, { from = VERSION, to = u.man.version, fromRel = RELEASE, toRel = Sys.rel(u.man),
                                 file = u.entry.file, src = u.man.gist and "gist" or "github",
                                 backup = backup, t = math.floor(os.epoch("utc") / 1000) })
        -- die alte Fassung bleibt im Speicher: klappt das Schreiben nicht, kommt sie sofort zurueck
        local old = Store.read(self)
        local function put(text)
            local okW = pcall(function()
                local h = fs.open(self, "wb")
                if not h then error("nicht schreibbar", 0) end
                local okH, e = pcall(h.write, text)
                h.close()
                if not okH then error(e, 0) end
            end)
            return okW and fs.exists(self) and fs.getSize(self) == #text
        end
        if not put(body) then
            if not (old and put(old)) and backup then pcall(fs.delete, self) pcall(fs.copy, backup, self) end
            pcall(fs.delete, Sys.UPD_DB)
            error("Schreiben fehlgeschlagen (Speicher?) - alte Fassung bleibt", 0)
        end
    end)
    u.busy = false
    if not ok then
        u.state, u.msg = "error", tostring(err)
        Kernel.notify("Update: " .. tostring(err), colors.red, "info", "update")
    else
        u.state, u.msg = "done", "Installiert - Neustart ..."
        Kernel.log("INFO", "Update auf " .. Sys.rel(u.man) .. " installiert")
        Sys.rebootAt = os.clock() + 4
    end
    Kernel.invalidate()
end

-- Beim Start: frisch installiert? Dann nach einer Minute ohne Absturz bestaetigen.
function Sys.updBoot()
    local u = Store.load(Sys.UPD_DB)
    if type(u) == "table" then
        if u.to == VERSION then Sys.upd.pending = u else pcall(fs.delete, Sys.UPD_DB) end
    end
    local back = Store.load(Sys.UPD_BACK)
    if type(back) == "table" then
        pcall(fs.delete, Sys.UPD_BACK)
        Kernel.notify("Update auf " .. tostring(back.toRel or back.to) .. " lief nicht - " .. RELEASE .. " ist zurueck", colors.red, "info", "update")
    end
end

function Sys.updConfirm()
    if not Sys.upd.pending then return end
    Sys.upd.pending = nil
    pcall(fs.delete, Sys.UPD_DB)
    pcall(fs.delete, Sys.UPD_OLD)
    Kernel.notify("Update fertig: GTS OS " .. RELEASE, colors.lime, "info", "update")
end

-- Nach einem Absturz der frischen Fassung: alte Fassung zurueck.
function Sys.updRollback(err)
    local p = Sys.upd.pending
    if not p then
        -- Absturz vor Sys.updBoot(): Eintrag selbst lesen
        local u = Store.load(Sys.UPD_DB)
        if type(u) == "table" and u.to == VERSION then p = u end
    end
    if not p then return nil end
    local self, ok = Sys.SELF, false
    if type(p.backup) == "string" and fs.exists(p.backup) then
        ok = pcall(function() fs.delete(self) fs.move(p.backup, self) end) and fs.exists(self)
    end
    if not ok and p.src == "github" and http and http.get and type(p.from) == "string" and type(p.file) == "string" then
        pcall(function()
            local h = http.get(Sys.REPO .. "v" .. tostring(p.fromRel or p.from) .. "/" .. p.file, nil, true)
            if not h then return end
            local body = h.readAll()
            h.close()
            if type(body) == "string" and load(body, "=alt", "t", {}) then
                local f = fs.open(self, "wb")
                f.write(body)
                f.close()
                ok = fs.getSize(self) == #body
            end
        end)
    end
    pcall(fs.delete, Sys.UPD_DB)
    if ok then Store.save(Sys.UPD_BACK, { from = p.from, to = p.to, toRel = p.toRel, err = tostring(err):sub(1, 120) }) end
    Sys.upd.pending = nil
    return ok, p.fromRel or p.from
end

-- ---------- System-Check: Ampel + Tipp ----------
-- { name, level = "ok" | "warn" | "bad" | "info", text, tip }
function Sys.checks()
    local out = {}
    local function add(name, level, text, tip) out[#out + 1] = { name = name, level = level, text = text, tip = tip } end
    local hw, d = Kernel.hw, Kernel.display
    if hw.modem then add("Funk-Modem", "ok", "Wireless/Ender Modem bereit")
    else add("Funk-Modem", "bad", "kein Funk-Modem", "Ein Ender Modem (oder Wireless Modem) an den Computer bauen.") end
    if PHONE then
        if Net.isDefault then add("Lager-Passwort", "info", "Standard " .. CONFIG.phonePassword, "Hat dein Freund am PC ein eigenes gesetzt: INFO > EINSTELLUNGEN.") end
    elseif Net.isDefault then
        add("Schwarm-Passwort", "warn", "Standard (unsicher)", "EINSTELLUNGEN > SICHERHEIT: eigenes setzen, dann TURTLE-DISK neu schreiben.")
    else
        add("Schwarm-Passwort", "ok", "eigenes Passwort")
    end
    if Settings.get("code") then add("Sperrcode", "ok", "eigener Code")
    else add("Sperrcode", "warn", "3344 (Standard)", "EINSTELLUNGEN > SICHERHEIT > Sperrcode aendern.") end
    if not PHONE then
        local g = Geo.here()
        if g then add("Position", "ok", g.x .. " " .. g.y .. " " .. g.z .. ((g.src == "gps") and " (GPS)" or " (von Hand)"))
        else add("Position", "warn", "unbekannt", "GPS bauen (DATEN > GPS-DISK, 4 Computer) oder PC-Position eintragen.") end
    end
    if d.monitor then
        add("Monitor", d.touch and "ok" or "warn", d.name .. ", " .. Kernel.W .. "x" .. Kernel.H .. (d.touch and " Touch" or ""),
            (not d.touch) and "Advanced Monitor nehmen: dann geht Touch." or nil)
    elseif EDITION == "pc" then
        add("Monitor", "info", "keiner (Bedienung am PC)", "Schoener: 5x2 Advanced Monitor an den Computer.")
    end
    if EDITION == "pc" then
        local L, invs = Apps.byId.lager, #(hw.inventories or {})
        if invs == 0 then
            add("Lager", "info", "keine Kisten am Kabel", "Freiwillig: Kisten per Wired Modem + Kabel anschliessen.")
        elseif not (L and L.cfg.io) then
            add("Lager", "warn", invs .. " Kisten, keine EIN/AUS-Kiste", "LAGER > KISTEN > EIN/AUS-KISTE FINDEN.")
        else
            local s = L.stats
            local pct = (s and s.slots > 0) and math.floor(s.used * 100 / s.slots) or 0
            add("Lager", (pct >= 90) and "warn" or "ok", ((s and s.invs) or invs) .. " Kisten, " .. pct .. " % voll",
                (pct >= 90) and "Mehr Kisten anschliessen oder LAGER > KISTEN > AUFRAEUMEN." or nil)
            if L.low and #L.low > 0 then add("Mindestmengen", "warn", #L.low .. " Items knapp", "LAGER: knappe Items nachfuellen.") end
        end
        local fleet = Fleets.UP
        if fleet then
            local online, total = fleet:counts()
            local agent = TurtleProgs.get("agent")
            local old, nopick, fuel = 0, 0, 0
            for _, e in pairs(fleet.store) do
                if agent and e.v and verLess(e.v, agent.ver) then old = old + 1 end
                if e.online and e.pick == false then nopick = nopick + 1 end
                if e.online and type(e.level) == "number" and e.level < 500 then fuel = fuel + 1 end
            end
            if total == 0 then
                add("Turtles", "info", "noch keine", "DATEN > TURTLE-DISK schreiben und eine Turtle daneben starten.")
            else
                add("Turtles", (online < total) and "warn" or "ok", online .. " von " .. total .. " online",
                    (online < total) and "Offline: Chunk nicht geladen, Turtle aus oder ausser Reichweite." or nil)
            end
            if old > 0 then add("Turtle-Agent", "warn", old .. " mit altem Agent", "SCHWARM > ALLE > UPDATE (Agent v" .. tostring(agent.ver) .. ").") end
            if nopick > 0 then add("Spitzhacke", "warn", nopick .. " Turtle(s) ohne", "Diamant-Spitzhacke ins Inventar der Turtle legen.") end
            if fuel > 0 then add("Treibstoff", "warn", fuel .. " Turtle(s) fast leer", "Kohle in die Turtle legen (unter 500).") end
        end
    end
    local free = fs.getFreeSpace("/")
    if type(free) == "number" then
        local lvl = (free < 40000) and "bad" or ((free < 150000) and "warn" or "ok")
        add("Speicher", lvl, fmtSize(free) .. " frei", (lvl ~= "ok") and "Papierkorb leeren, alte Backups und Scripts loeschen." or nil)
    end
    add("HTTP", http and "ok" or "warn", http and "an (WEB, UPDATE)" or "aus",
        (not http) and "In der CC: Tweaked-Config http aktivieren (fuer WEB und UPDATE)." or nil)
    local u = Sys.upd
    if u.state == "found" then add("Update", "warn", Sys.rel(u.man) .. " verfuegbar", "INFO > SYSTEM > UPDATE.")
    elseif u.state == "none" then add("Update", "ok", "aktuell (" .. RELEASE .. ")") end
    if not READONLY then
        local list = Sys.backupList()
        if #list == 0 then add("Backup", "warn", "noch keins", "INFO > SYSTEM > BACKUP > JETZT SICHERN.")
        else add("Backup", "ok", "zuletzt " .. list[1].label) end
    end
    if Sys.crashes > 0 then add("Abstuerze", "warn", Sys.crashes .. " in den letzten 10 min", "Log ansehen: " .. CONFIG.logFile) end
    if Sys.safe then add("Sicherer Modus", "warn", "an (ohne Erweiterungen)", "INFO > SYSTEM > SICHERER MODUS > NORMAL STARTEN.") end
    local ex = {}
    for _, e in ipairs(hw.all or {}) do if Extras.KINDS[e.kind] then ex[#ex + 1] = Extras.KINDS[e.kind] end end
    add("Erweiterungen", "info", (#ex > 0) and table.concat(ex, ", ") or "keine (freiwillig)")
    return out
end

-- ---------- Hintergrund: Neustart, Bestaetigung, Speicher, taeglich ----------
function Sys.service()
    Sys.started = os.clock()
    local nextDisk, nextDaily = os.clock() + 20, os.clock() + 300
    while true do
        os.sleep(5)
        local now = os.clock()
        if Sys.rebootAt and now >= Sys.rebootAt then os.reboot() end
        if Sys.upd.pending and now - Sys.started >= 60 then Sys.updConfirm() end
        if now >= nextDisk then nextDisk = now + 60 Sys.diskCheck() end
        if now >= nextDaily then
            nextDaily = now + 900
            Sys.trashDrop(nil, Sys.TRASH_DAYS * 86400)
            if Settings.get("cleanAuto") ~= false and Settings.get("cleanDay") ~= os.date("%Y-%m-%d") then
                Settings.set("cleanDay", os.date("%Y-%m-%d"))
                local ok, freed, n = pcall(function() return Sys.clean(Sys.cleanScan()) end)
                if ok and n and n > 0 and freed > 8000 then
                    Kernel.notify("Aufgeraeumt: " .. fmtSize(freed) .. " frei", colors.lime, "info", "clean")
                end
            end
            if not READONLY and Settings.get("autoBackup") ~= false and Settings.get("backupDay") ~= os.date("%Y-%m-%d") then
                local ok, msg = Sys.backupMake()
                if not ok then Kernel.notify("Backup: " .. msg, colors.orange, "info", "backup") end
            end
            if http and Settings.get("updAuto") ~= false and Settings.get("updDay") ~= os.date("%Y-%m-%d") then
                Sys.updCheck(true)
            end
        end
    end
end

-- ---------- Absturz-Bildschirm ----------
-- Statt eines Lua-Fehlers: was passiert ist, Log-Auszug, Neustart nach 15 s.
-- Drei Abstuerze in 10 Minuten: naechster Start im sicheren Modus. Lief
-- gerade ein frisches Update, kommt die alte Fassung zurueck. Die Shell gibt
-- es nur mit dem Sperrcode. Rueckgabe "shell" = zur Shell, sonst Neustart.
function Sys.crashScreen(err, mon)
    err = tostring(err)
    pcall(Settings.load)            -- eigener Sperrcode gilt auch hier
    local rolled, oldV = Sys.updRollback(err)
    local b = Store.load(Sys.BOOT_DB) or {}
    local now, list = math.floor(os.epoch("utc") / 1000), {}
    for _, t in ipairs(type(b.crashes) == "table" and b.crashes or {}) do
        if type(t) == "number" and now - t < 600 then list[#list + 1] = t end
    end
    list[#list + 1] = now
    b.crashes = list
    local toSafe = #list >= 3 and not b.safe and not rolled
    if toSafe then b.safe = true end
    Store.save(Sys.BOOT_DB, b)
    local tail = {}
    for line in (Store.read(CONFIG.logFile) or ""):gmatch("[^\n]+") do
        if line:find("FEHLER", 1, true) then tail[#tail + 1] = line end
    end
    while #tail > 3 do table.remove(tail, 1) end
    local screens = { nativeTerm, mon }
    local left, paused, buttons = 15, false, {}
    local function draw()
        buttons = {}
        for si = 1, 2 do
            local t = screens[si]
            if t then pcall(function()
                applyPalette(t, true)
                local w, h = t.getSize()
                local function at(x, y, text, fg, bg)
                    if y < 1 or y > h then return end
                    t.setCursorPos(x, y)
                    t.setTextColor(fg or colors.white)
                    t.setBackgroundColor(bg or colors.black)
                    t.write(text)
                end
                t.setBackgroundColor(colors.black)
                t.clear()
                at(1, 1, string.rep(" ", w), colors.white, colors.red)
                at(2, 1, "GTS OS IST ABGESTUERZT", colors.white, colors.red)
                local y = 3
                at(2, y, "Was passiert ist:", colors.lightGray)
                y = y + 1
                for i, l in ipairs(UI.wrap(err, w - 4)) do
                    if i <= 4 then at(3, y, l, colors.white) y = y + 1 end
                end
                y = y + 1
                if #tail > 0 and h >= 18 then
                    at(2, y, "Aus dem Log:", colors.lightGray)
                    for i, l in ipairs(tail) do at(3, y + i, l:sub(1, w - 4), colors.lightGray) end
                    y = y + #tail + 2
                end
                if rolled then
                    at(2, y, ("Das Update wurde zurueckgenommen: wieder " .. tostring(oldV) .. "."):sub(1, w - 2), colors.lime)
                    y = y + 1
                elseif rolled == false then
                    at(2, y, ("Update fehlerhaft, alte Fassung nicht gefunden."):sub(1, w - 2), colors.orange)
                    y = y + 1
                end
                if toSafe then
                    at(2, y, ("3 Abstuerze in 10 min: Neustart im SICHEREN MODUS."):sub(1, w - 2), colors.orange)
                    y = y + 1
                end
                at(2, y + 1, paused and "Neustart angehalten." or ("Neustart in " .. left .. " s ..."), colors.white)
                local by, x = math.max(y + 3, h - 1), 2
                local list = { { " NEUSTART ", "reboot", colors.black, colors.white },
                               { " SICHERER MODUS ", "safe", colors.white, colors.gray } }
                if si == 1 then list[3] = { " SHELL (CODE) ", "shell", colors.white, colors.gray } end
                for _, bt in ipairs(list) do
                    if x + #bt[1] - 1 <= w then
                        at(x, by, bt[1], bt[3], bt[4])
                        buttons[#buttons + 1] = { s = si, x = x, y = by, w = #bt[1], action = bt[2] }
                    end
                    x = x + #bt[1] + 1
                end
                if si == 1 and by + 1 <= h then at(2, by + 1, ("Tasten: R Neustart, S sicherer Modus, C Shell"):sub(1, w - 2), colors.lightGray) end
            end) end
        end
    end
    draw()
    local timer = os.startTimer(1)
    local wrong, lockUntil = 0, 0
    while true do
        local ev, a, bx, by = os.pullEventRaw()
        local action
        if ev == "timer" and a == timer then
            if not paused then left = left - 1 end
            if left <= 0 then action = "reboot" else timer = os.startTimer(1) draw() end
        elseif ev == "char" then
            -- Buchstaben ueber "char": dann landet das "c" nicht in der Code-Abfrage
            local ch = a:lower()
            if ch == "r" then action = "reboot"
            elseif ch == "s" then action = "safe"
            elseif ch == "c" then action = "shell"
            else paused = true draw() end
        elseif ev == "key" then
            if a == keys.enter then action = "reboot"
            elseif a ~= keys.r and a ~= keys.s and a ~= keys.c then paused = true draw() end
        elseif ev == "mouse_click" or ev == "monitor_touch" then
            local si = (ev == "mouse_click") and 1 or 2
            for _, bt in ipairs(buttons) do
                if bt.s == si and bx >= bt.x and bx < bt.x + bt.w and by == bt.y then action = bt.action end
            end
            if not action then paused = true draw() end
        end
        if action == "reboot" then
            os.reboot()
        elseif action == "safe" then
            Sys.setSafe(true)
            os.reboot()
        elseif action == "shell" and os.clock() < lockUntil then
            paused = true
            draw()
        elseif action == "shell" then
            paused = true
            local old = os.pullEvent
            os.pullEvent = os.pullEventRaw          -- Strg+T bricht die Abfrage nicht ab
            local okR, code = pcall(function()
                term.redirect(nativeTerm)
                nativeTerm.setBackgroundColor(colors.black)
                nativeTerm.setTextColor(colors.white)
                nativeTerm.clear()
                nativeTerm.setCursorPos(1, 1)
                write("Sperrcode fuer die Shell: ")
                return read("*")
            end)
            os.pullEvent = old
            if okR and Settings.checkCode(code) then return "shell" end
            wrong = wrong + 1
            if wrong >= 5 then wrong, lockUntil = 0, os.clock() + 30 end   -- wie die normale Sperre
            draw()
        end
    end
end

local Info = { id = "info", title = "INFO", order = 11, page = 1, gps = nil, gpsBusy = false,
               view = "info", setPage = { page = 1 }, sysPage = { page = 1 }, input = nil, shift = false }

function Info:insert(text) Input.insert(self, text) end
function Info:key(action) Input.key(self, action) end
function Info:onChar(ch) Input.insert(self, ch) end
function Info:onPaste(text) Input.insert(self, text) end
function Info:onKey(code) Input.onKey(self, code) end
function Info:onEnter(view)
    self.input = nil
    if view then self.view, self.setPage.page = view, 1 end
end

-- Neues Schwarm-Passwort: Schluessel ableiten, an alle Turtles schicken, die
-- gerade online sind (verschluesselt mit dem alten Schluessel), dann umstellen.
-- Ausnahme: war das alte Passwort der Standard, geht der neue Schluessel NICHT
-- per Funk raus - wer "gts" kennt, koennte ihn sonst mitlesen. Dann bekommen
-- die Turtles das Passwort ueber eine neue TURTLE-DISK oder P an der Turtle.
-- Offline-Turtles brauchen es ebenfalls von Hand.
function Info:setPassword(text)
    if PHONE then
        -- Handy: nur der Schluessel fuer die Lager-Daten (leer = Standard 1234)
        local pw = (text == "") and CONFIG.phonePassword or text
        Net.setKey(Net.derive(pw), pw == CONFIG.phonePassword, os.epoch("utc"))
        Net.save(CONFIG.keyFile)
        Apps.byId.lager.remote = nil
        Kernel.notify("Lager-Passwort gesetzt", colors.lime)
        return
    end
    local isDefault = (text == "")
    local key = Net.derive(isDefault and "gts" or text)
    local since = os.epoch("utc")
    local viaAir = not Net.isDefault
    local sent, waiting = 0, 0
    if not READONLY then
        for _, fleet in pairs(Fleets) do
            for id, e in pairs(fleet.store) do
                if e.online and viaAir then
                    -- sofort und noch mit dem alten Schluessel verpacken
                    Net.send(id, { t = "KEY", key = Net.toHex(key), default = isDefault, since = since })
                    sent = sent + 1
                else
                    waiting = waiting + 1
                end
                e.keyOld = true
            end
        end
        -- Claude (eigene App, nicht im Schwarm) bekommt den Schluessel genauso
        for id, u in pairs(Kernel.claude and Kernel.claude.units or {}) do
            if u.online and viaAir then
                Net.send(id, { t = "KEY", key = Net.toHex(key), default = isDefault, since = since })
                sent = sent + 1
            else
                waiting = waiting + 1
            end
        end
    end
    Net.setKey(key, isDefault, since)
    Net.save(CONFIG.keyFile)
    Kernel.log("INFO", "Schwarm-Passwort geaendert (" .. sent .. " per Funk, " .. waiting .. " von Hand)")
    if READONLY then
        Kernel.notify("Passwort gesetzt", colors.lime)
    elseif isDefault then
        Kernel.notify("Standard-Passwort gesetzt (unsicher)", colors.orange)
    elseif waiting > 0 then
        Kernel.notify("Passwort gesetzt. " .. waiting .. " Turtle(s): TURTLE-DISK neu schreiben oder P an der Turtle", colors.orange)
    else
        Kernel.notify("Passwort gesetzt" .. (sent > 0 and (", " .. sent .. " Turtle(s) per Funk umgestellt") or ""), colors.lime)
    end
end

function Info:changeCode()
    Kernel.askCode("Alter Code", function()
        Kernel.askNew("Neuer Code (4-8 Ziffern)", function(a)
            if #a < 4 then Kernel.notify("Mindestens 4 Ziffern", colors.red) return end
            Kernel.askNew("Neuen Code wiederholen", function(b)
                if a ~= b then Kernel.notify("Nicht gleich - Code nicht geaendert", colors.red) return end
                Settings.set("code", Settings.codeHash(a))
                Kernel.log("INFO", "Sperrcode geaendert")
                Kernel.notify("Sperrcode geaendert", colors.lime)
            end)
        end)
    end)
end

-- Zeilen der Einstellungen: { Name, Wert, Farbe, Buttons }
function Info:settingRows()
    local rows = {}
    local function choice(key, values, fmt, after)
        local out = {}
        for _, v in ipairs(values) do
            out[#out + 1] = { text = fmt(v), style = (Settings.get(key) == v) and "primary" or nil, onClick = function()
                Settings.set(key, v)
                if after then after(v) end
            end }
        end
        return out
    end
    if PHONE then
        rows[#rows + 1] = { "Lager-Passwort", Net.isDefault and (CONFIG.phonePassword .. " (Standard)") or "eigenes", nil,
            { { text = "AENDERN", onClick = function()
                Input.open(self, { title = "Handy-Passwort vom PC", mask = true, maxLen = 32,
                                   hint = "Steht am PC unter INFO > Handy-Passwort. Leer = " .. CONFIG.phonePassword,
                                   onOk = function(t) self:setPassword(t) end })
            end } } }
    else
    rows[#rows + 1] = { "Schwarm-Passwort", Net.isDefault and "Standard (unsicher!)" or "eigenes",
        Net.isDefault and colors.orange or colors.lime, { { text = "AENDERN", onClick = function()
            Input.open(self, { title = "Schwarm-Passwort (gleich an allen Turtles)", mask = true, maxLen = 32,
                               hint = Net.isDefault and "Danach TURTLE-DISK neu schreiben (oder P an jeder Turtle)."
                                      or "Leer = Standard. Turtles online werden per Funk umgestellt.",
                               onOk = function(t) self:setPassword(t) end })
        end } } }
    end
    rows[#rows + 1] = { "Sperrcode", Settings.get("code") and "eigener Code" or "3344 (Standard)",
        Settings.get("code") and colors.lime or colors.orange, { { text = "AENDERN", onClick = function() self:changeCode() end } } }
    rows[#rows + 1] = { "Auto-Sperre", (Settings.get("autoLock") or 0) > 0 and (Settings.get("autoLock") .. " min") or "aus", nil,
        choice("autoLock", { 5, 10, 30, 0 }, function(v) return v == 0 and "AUS" or tostring(v) end) }
    if not READONLY then
        rows[#rows + 1] = { "Handy-Passwort", Settings.get("phoneSet") and "eigenes" or (CONFIG.phonePassword .. " (Standard)"), nil,
            { { text = "AENDERN", onClick = function()
                Input.open(self, { title = "Handy-Passwort (GTS Phone, nur Lager)", mask = true, maxLen = 32,
                                   hint = "Fuer die Handys deiner Freunde. Leer = " .. CONFIG.phonePassword,
                                   onOk = function(t)
                                       local pw = (t == "") and CONFIG.phonePassword or t
                                       Settings.set("phoneKey", Net.toHex(Net.derive(pw)))
                                       Settings.set("phoneSet", t ~= "" and t ~= CONFIG.phonePassword)
                                       Kernel.notify("Handy-Passwort gesetzt", colors.lime)
                                   end })
            end } } }
    end
    if not READONLY then
        rows[#rows + 1] = { "DD-Tunnel", CONFIG.exploreDist .. " Bloecke", nil,
            choice("ddDist", { 64, 96, 128, 256 }, tostring, function(v) CONFIG.exploreDist = v end) }
        local trash = Settings.get("chunkTrash") ~= false
        rows[#rows + 1] = { "CHUNK-Muell", trash and "wegwerfen" or "behalten (alles in die Kiste)", nil, {
            { text = "WEG", style = trash and "primary" or nil, onClick = function() Settings.set("chunkTrash", true) end },
            { text = "BEHALTEN", style = (not trash) and "primary" or nil, onClick = function() Settings.set("chunkTrash", false) end } } }
        local owner = Settings.get("owner")
        rows[#rows + 1] = { "Besitzer", (owner ~= "" and owner) or "- (fuer Chat und Wache)", (owner == "") and colors.lightGray or nil,
            { { text = "AENDERN", onClick = function()
                Input.open(self, { title = "Dein Spielername", text = owner, maxLen = 16, filter = "[^%w_]",
                                   hint = "Bekommt Meldungen der Chat Box", onOk = function(t) Settings.set("owner", t) end })
            end } } }
        local trusted = Settings.get("trusted") or {}
        rows[#rows + 1] = { "Vertraute", (#trusted > 0) and table.concat(trusted, ", ") or "-", nil,
            { { text = "AENDERN", onClick = function()
                Input.open(self, { title = "Vertraute Spieler (mit Komma)", text = table.concat(trusted, ","), maxLen = 120,
                                   filter = "[^%w_, ]", hint = "Loesen keinen Alarm aus", onOk = function(t)
                    local list = {}
                    for name in t:gmatch("[%w_]+") do if #list < 20 then list[#list + 1] = name end end
                    Settings.set("trusted", list)
                end })
            end } } }
        rows[#rows + 1] = { "Alarm-Radius", (Settings.get("alarmRadius") or 24) .. " Bloecke", nil,
            choice("alarmRadius", { 8, 16, 24, 48 }, tostring) }
        local here, hand = Geo.here(), Settings.get("pcPos")
        rows[#rows + 1] = { "PC-Position", here and (here.x .. " " .. here.y .. " " .. here.z .. ((here.src == "gps") and " (GPS)" or " (von Hand)"))
                                or "unbekannt (fuer die KARTE)", here and colors.white or colors.orange,
            { { text = "AENDERN", onClick = function()
                Input.open(self, { title = "Koordinaten dieses PCs (F3)", text = type(hand) == "table" and (hand.x .. " " .. hand.y .. " " .. hand.z) or "",
                                   maxLen = 30, filter = "[^%d%-%s,]", hint = "z.B. 120 64 -340. Leer = per GPS", onOk = function(t)
                    local x, y, z = t:match("(-?%d+)[%s,]+(-?%d+)[%s,]+(-?%d+)")
                    Settings.set("pcPos", x and { x = tonumber(x), y = tonumber(y), z = tonumber(z) } or nil)
                    if not x then os.queueEvent("gts_gps") end
                end })
            end } } }
        rows[#rows + 1] = { "Disketten-Start", "aus (fremde Disketten starten nicht)", colors.lightGray, {} }
        local swChat = Settings.get("swarmChat") ~= false
        rows[#rows + 1] = { "Turtle-Warnungen", swChat and "im OS und per Chat Box" or "nur im OS", nil, {
            { text = "CHAT AN", style = swChat and "primary" or nil, onClick = function() Settings.set("swarmChat", true) end },
            { text = "AUS", style = (not swChat) and "primary" or nil, onClick = function() Settings.set("swarmChat", false) end } } }
        local auto = Settings.get("lagerAuto") or 0
        rows[#rows + 1] = { "Auto-Einlagern", (auto > 0) and ("alle " .. auto .. " s") or "aus (EINLAGERN von Hand)", nil, {
            { text = "AUS", style = (auto == 0) and "primary" or nil, onClick = function() Settings.set("lagerAuto", 0) end },
            { text = "30 S", style = (auto == 30) and "primary" or nil, onClick = function() Settings.set("lagerAuto", 30) end },
            { text = "2 MIN", style = (auto == 120) and "primary" or nil, onClick = function() Settings.set("lagerAuto", 120) end } } }
        local chat = Settings.get("lagerChat") ~= false
        rows[#rows + 1] = { "Knapp-Meldung", chat and "im OS und per Chat Box" or "nur im OS", nil, {
            { text = "CHAT AN", style = chat and "primary" or nil, onClick = function() Settings.set("lagerChat", true) end },
            { text = "AUS", style = (not chat) and "primary" or nil, onClick = function() Settings.set("lagerChat", false) end } } }
    end
    -- Karte drehen: oben = Blickrichtung, wenn man vor dem Monitor steht (F3: Facing)
    if not PHONE then
        local NAMES = { [0] = "Norden", "Osten", "Sueden", "Westen" }
        local cur = tonumber(Settings.get("mapUp")) or 0
        local list = {}
        for i, l in ipairs({ "N", "O", "S", "W" }) do
            list[i] = { text = l, style = (cur == i - 1) and "primary" or nil, onClick = function() Settings.set("mapUp", i - 1) end }
        end
        rows[#rows + 1] = { "Karte: oben", (NAMES[cur] or "Norden") .. (UI.narrow() and "" or " (Blick zum Monitor, F3 Facing)"), nil, list }
    end
    -- Design (alle Ausgaben): Grundton und Akzent mit < >, dazu der Sternenhimmel
    local function cycle(key, list)
        local cur = 1
        for i, x in ipairs(list) do if x.id == Settings.get(key) then cur = i end end
        local function go(d)
            Settings.set(key, list[(cur - 1 + d) % #list + 1].id)
            setTheme(Settings.get("theme"), Settings.get("accent"))
        end
        return list[cur].name, { { text = "\17", onClick = function() go(-1) end }, { text = "\16", onClick = function() go(1) end } }
    end
    local tName, tBtn = cycle("theme", THEMES)
    rows[#rows + 1] = { "Grundton", tName, nil, tBtn }
    local aName, aBtn = cycle("accent", ACCENTS)
    rows[#rows + 1] = { "Akzentfarbe", "\7 " .. aName, colors.lime, aBtn }
    local stars = Settings.get("stars") ~= false
    rows[#rows + 1] = { "Sternenhimmel", stars and "an (Startseite)" or "aus", nil, {
        { text = "AN", style = stars and "primary" or nil, onClick = function() Settings.set("stars", true) end },
        { text = "AUS", style = (not stars) and "primary" or nil, onClick = function() Settings.set("stars", false) end } } }
    -- Gruppen (Reiter oben in den Einstellungen)
    local GROUP = { ["Schwarm-Passwort"] = "SICHERHEIT", ["Lager-Passwort"] = "SICHERHEIT", Sperrcode = "SICHERHEIT",
                    ["Auto-Sperre"] = "SICHERHEIT", ["Handy-Passwort"] = "SICHERHEIT", Vertraute = "SICHERHEIT",
                    ["Alarm-Radius"] = "SICHERHEIT", ["Disketten-Start"] = "SICHERHEIT",
                    ["DD-Tunnel"] = "SCHWARM", ["CHUNK-Muell"] = "SCHWARM", ["PC-Position"] = "SCHWARM", ["Turtle-Warnungen"] = "SCHWARM", ["Karte: oben"] = "SCHWARM",
                    Besitzer = "ALLGEMEIN", Grundton = "DESIGN", Akzentfarbe = "DESIGN", Sternenhimmel = "DESIGN",
                    ["Auto-Einlagern"] = "LAGER", ["Knapp-Meldung"] = "LAGER" }
    for _, r in ipairs(rows) do r.g = r.g or GROUP[r[1]] or "SYSTEM" end
    return rows
end

Info.GROUPS = { "SICHERHEIT", "ALLGEMEIN", "DESIGN", "SCHWARM", "LAGER", "SYSTEM" }

function Info:drawSettings()
    local w, bh, narrow = Kernel.w, UI.bh(), UI.narrow()
    local top = UI.header("EINSTELLUNGEN", not narrow and "Aenderungen gelten sofort" or nil, {
        { text = narrow and "\17" or "\17 INFO", onClick = function() self.view = "info" end },
    })
    local all = self:settingRows()
    -- Reiter: nur Gruppen, die es in dieser Ausgabe gibt
    local groups, has = {}, {}
    for _, r in ipairs(all) do has[r.g] = true end
    for _, g in ipairs(Info.GROUPS) do if has[g] then groups[#groups + 1] = g end end
    if not has[self.setGroup or ""] then self.setGroup = groups[1] end
    local tabs, need = {}, -1
    for _, g in ipairs(groups) do
        need = need + #g + 3
        tabs[#tabs + 1] = { text = g, style = (g == self.setGroup) and "primary" or nil, h = 1,
                            onClick = function() self.setGroup, self.setPage.page = g, 1 end }
    end
    if need <= w - 2 then
        UI.flow(tabs, 2, top, w - 1)
    else
        UI.button{ x = 1, y = top, w = w, h = 1, text = self.setGroup .. " \16", onClick = function()
            for i, g in ipairs(groups) do
                if g == self.setGroup then self.setGroup = groups[i % #groups + 1] break end
            end
            self.setPage.page = 1
        end }
    end
    top = top + 2
    local rows = {}
    for _, r in ipairs(all) do if r.g == self.setGroup then rows[#rows + 1] = r end end
    UI.settingsList(self.setPage, rows, top)
end

-- Einstellungs-Liste: rows = { { Name, Wert, Farbe, { Knoepfe } }, ... }
-- schmal (Handy, Pocket): Name, Wert und Knoepfe je in einer eigenen Zeile;
-- PC ohne Monitor: Name + Knoepfe, darunter der Wert; Touch-Monitor: eine Zeile.
function UI.settingsList(state, rows, top)
    local bh, narrow = UI.bh(), UI.narrow()
    local mode = narrow and "stack" or ((bh == 1) and "two" or "one")
    local ch = (mode == "stack") and 3 or ((mode == "two") and 2 or bh)
    UI.list(state, rows, top, ch + 1, function(r, y)
        local tx, xr = UI.rowCard(y, ch)
        if mode ~= "one" then
            local by = (mode == "stack") and (y + 2) or y
            local bx = (#r[4] > 0) and UI.buttonsRight(r[4], by, xr, (mode == "stack") and (tx - 1) or nil) or (xr + 2)
            UI.text(tx, y, r[1]:sub(1, ((mode == "stack") and xr or (bx - 2)) - tx + 1), colors.white)
            UI.text(tx, y + 1, tostring(r[2]):sub(1, xr - tx + 1), r[3] or colors.lightGray)
            return
        end
        local bx = UI.buttonsRight(r[4], narrow and (y + 1) or y, xr)
        if #r[4] == 0 then bx = xr + 2 end
        local lw = narrow and 0 or 18
        UI.text(tx, y, r[1]:sub(1, narrow and (xr - tx + 1) or 17), colors.white)
        local vx = narrow and (tx + #r[1] + 1) or (tx + lw)
        local room = (narrow and xr or (bx - 2)) - vx + 1
        if narrow and #r[4] > 0 then
            vx, room = tx + #r[1] + 1, xr - (tx + #r[1] + 1) + 1
        end
        if room > 2 then UI.text(vx, y, tostring(r[2]):sub(1, room), r[3] or colors.lightGray) end
    end)
end

-- ---------- INFO > SYSTEM (v8.0) ----------
-- Kacheln: System-Check, Update, Backup, Papierkorb, Einrichtung, sicherer Modus.
function Info.ago(t)
    local d = math.floor(os.epoch("utc") / 1000) - (tonumber(t) or 0)
    if d < 3600 then return "vor " .. math.max(1, math.floor(d / 60)) .. " min" end
    if d < 86400 then return "vor " .. math.floor(d / 3600) .. " h" end
    local days = math.floor(d / 86400)
    return (days == 1) and "gestern" or ("vor " .. days .. " Tagen")
end

Info.LEVEL = { ok = colors.lime, warn = colors.yellow, bad = colors.red, info = colors.lightGray }

function Info:back(to)
    return { text = UI.narrow() and "\17" or ("\17 " .. (to and "SYSTEM" or "INFO")),
             onClick = function() self.view, self.setPage.page = to and "system" or "info", 1 end }
end

function Info:drawSystem()
    local w, h, bh, narrow = Kernel.w, Kernel.h, UI.bh(), UI.narrow()
    local top = UI.header("SYSTEM", not narrow and "Pflege und Hilfe fuer GTS OS" or nil, { self:back() })
    local bad, warn = 0, 0
    for _, c in ipairs(Sys.checks()) do
        if c.level == "bad" then bad = bad + 1 elseif c.level == "warn" then warn = warn + 1 end
    end
    local u = Sys.upd
    local tiles = {
        { id = "check", title = "SYSTEM-CHECK", value = (bad + warn == 0) and "alles in Ordnung" or ((bad + warn) .. " Hinweise"),
          dot = (bad > 0) and colors.red or ((warn > 0) and colors.yellow or colors.lime) },
        { id = "update", title = "UPDATE", value = (u.state == "found") and (Sys.rel(u.man) .. " bereit") or (RELEASE .. " installiert"),
          dot = (u.state == "found") and colors.yellow or colors.lime },
    }
    if not READONLY then
        local list, trash = Sys.backupList(), Sys.trashList()
        tiles[#tiles + 1] = { id = "backup", title = "BACKUP", value = list[1] and ("zuletzt " .. list[1].label) or "noch keins",
                              dot = list[1] and colors.lime or colors.yellow }
        tiles[#tiles + 1] = { id = "trash", title = "PAPIERKORB", value = (#trash == 0) and "leer" or ((#trash == 1) and "1 Datei" or (#trash .. " Dateien")),
                              dot = colors.lightGray }
        tiles[#tiles + 1] = { id = "setup", title = "EINRICHTUNG", value = Settings.get("setupDone") and "erledigt" or "jetzt starten",
                              dot = Settings.get("setupDone") and colors.lime or colors.yellow }
    end
    local free = fs.getFreeSpace("/")
    tiles[#tiles + 1] = { id = "clean", title = "AUFRAEUMEN", value = (type(free) == "number") and (fmtSize(free) .. " frei") or "Speicher",
                          dot = (type(free) == "number" and free < 60000) and colors.yellow or colors.lime }
    tiles[#tiles + 1] = { id = "safe", title = "SICHERER MODUS", value = Sys.safe and "an" or "aus", dot = Sys.safe and colors.orange or colors.lightGray }
    local cols = narrow and 1 or ((w >= 70) and 3 or 2)
    local tw = narrow and w or math.floor((w - 2 - (cols - 1) * 2) / cols)
    local th = narrow and 2 or 3
    -- Kacheln reihenweise; passen nicht alle, wird geblaettert
    local rowsList = {}
    for i, t in ipairs(tiles) do
        local r = math.floor((i - 1) / cols) + 1
        rowsList[r] = rowsList[r] or {}
        rowsList[r][#rowsList[r] + 1] = t
    end
    UI.list(self.sysPage, rowsList, top, th + 1, function(row, y)
        for c, t in ipairs(row) do
            local x = (narrow and 1 or 2) + (c - 1) * (tw + 2)
            UI.card(x, y, tw, th)
            UI.text(x + 1, y, "\7", t.dot)
            UI.text(x + 3, y, t.title:sub(1, tw - 5), colors.white)
            UI.text(x + 3, y + 1, t.value:sub(1, tw - 5), colors.lightGray)
            UI.text(x + tw - 2, y, "\16", colors.lightGray)
            UI.hit(x, y, tw, th, function() self.view = t.id self.setPage.page = 1 end)
            UI.surface = colors.black
        end
    end)
end

function Info:drawCheck()
    local w, bh, narrow = Kernel.w, UI.bh(), UI.narrow()
    local list = Sys.checks()
    local top = UI.header("SYSTEM-CHECK", not narrow and "Ampel mit Tipp - was fehlt, steht dabei" or nil, {
        { text = narrow and "NEU" or "NEU PRUEFEN", onClick = function()
            Kernel.scanHardware()
            os.queueEvent("gts_gps")
            Kernel.notify("Geprueft", colors.lime)
        end },
        self:back(true),
    })
    -- erst Probleme, dann Hinweise, dann ok
    local rank = { bad = 1, warn = 2, info = 3, ok = 4 }
    for i, c in ipairs(list) do c.i = i end
    table.sort(list, function(a, b)
        if rank[a.level] ~= rank[b.level] then return rank[a.level] < rank[b.level] end
        return a.i < b.i
    end)
    UI.list(self.setPage, list, top, 3, function(c, y)
        local tx, xr = UI.rowCard(y, 2)
        UI.text(tx - 1, y, "\7", Info.LEVEL[c.level])
        local nw = narrow and 0 or 17
        UI.text(tx + 1, y, c.name:sub(1, narrow and (xr - tx) or 16), colors.white)
        if narrow then
            UI.text(tx + 1, y + 1, (c.tip or c.text):sub(1, xr - tx), c.tip and colors.lightGray or Info.LEVEL[c.level])
        else
            UI.text(tx + 1 + nw, y, c.text:sub(1, xr - tx - nw), (c.level == "ok" or c.level == "info") and colors.white or Info.LEVEL[c.level])
            if c.tip then UI.text(tx + 1 + nw, y + 1, c.tip:sub(1, xr - tx - nw), colors.lightGray) end
        end
    end)
end

-- Zeile "Bezeichnung  Wert  [Knoepfe]" (Update, Backup)
function Info:kv(y, label, value, color, buttons)
    local w, narrow = Kernel.w, UI.narrow()
    local vx = narrow and 2 or 16
    local bx = (buttons and #buttons > 0) and UI.buttonsRight(buttons, y, w - 1) or (w + 1)
    if not narrow then UI.text(2, y, label, colors.lightGray) end
    UI.text(vx, y, tostring(value):sub(1, math.max(0, bx - vx - 1)), color or colors.white)
    return y + UI.bh()
end

function Info:drawUpdate()
    local w, h, bh, narrow = Kernel.w, Kernel.h, UI.bh(), UI.narrow()
    local u = Sys.upd
    local src = Sys.updSource()
    local top = UI.header("UPDATE", not narrow and ("GTS OS " .. RELEASE .. ((EDITION == "pc") and "" or (" " .. EDITION))) or nil, {
        { text = "SUCHEN", style = (u.state ~= "found") and "primary" or nil, disabled = u.busy or not http,
          onClick = function() Kernel.spawn("update", function() Sys.updCheck(false) end) end },
        self:back(true),
    })
    local y = top
    local stateColor = ({ found = colors.yellow, error = colors.red, none = colors.lime, done = colors.lime })[u.state] or colors.white
    y = self:kv(y, "Status", (not http) and "HTTP ist aus" or ((u.state == "idle") and "noch nicht gesucht" or u.msg),
                (not http) and colors.red or stateColor)
    y = self:kv(y, "Installiert", RELEASE)
    local srcButtons
    if EDITION == "pc" then
        srcButtons = {
            { text = "GITHUB", h = 1, style = (src == "github") and "primary" or nil, onClick = function() Settings.set("updSrc", "github") Sys.upd.state = "idle" end },
            { text = "GIST", h = 1, style = (src == "gist") and "primary" or nil, onClick = function() Settings.set("updSrc", "gist") Sys.upd.state = "idle" end },
        }
    end
    y = self:kv(y, "Quelle", (src == "gist") and "Gist (nur PC)" or "GitHub Jonsixx101/gts-os", nil, srcButtons)
    local auto = Settings.get("updAuto") ~= false
    y = self:kv(y, "Auto-Suche", auto and "einmal am Tag" or "aus", nil, {
        { text = "AN", h = 1, style = auto and "primary" or nil, onClick = function() Settings.set("updAuto", true) end },
        { text = "AUS", h = 1, style = (not auto) and "primary" or nil, onClick = function() Settings.set("updAuto", false) end },
    })
    y = y + 1
    if u.state == "found" and u.man then
        UI.section(2, y, "NEU IN " .. Sys.rel(u.man), w - 3)
        y = y + 1
        local n = 0
        for _, note in ipairs(type(u.man.notes) == "table" and u.man.notes or {}) do
            if type(note) == "string" and y <= h - bh * 2 - 3 and n < 6 then
                UI.text(2, y, "\7", colors.lime)
                UI.text(4, y, note:sub(1, w - 5), colors.white)
                y, n = y + 1, n + 1
            end
        end
        y = y + 1
        UI.button{ x = 2, y = math.min(y, h - bh * 2 - 1), text = narrow and "INSTALLIEREN" or "JETZT INSTALLIEREN", style = "primary",
                   confirm = "upd", disabled = u.busy, onClick = function() Kernel.spawn("update", Sys.updInstall) end }
    elseif not narrow and y <= h - bh - 2 then
        UI.text(2, y, ("Danach bekommen die Turtles den neuen Agent per SCHWARM > ALLE > UPDATE."):sub(1, w - 2), colors.lightGray)
    end
end

function Info:drawBackup()
    local w, h, bh, narrow = Kernel.w, Kernel.h, UI.bh(), UI.narrow()
    local list = Sys.backupList()
    local top = UI.header("BACKUP", not narrow and "Einstellungen, Lager-Kategorien, Funde, Notizen" or nil, {
        { text = narrow and "SICHERN" or "JETZT SICHERN", style = "primary", onClick = function()
            local ok, msg = Sys.backupMake()
            Kernel.notify(msg, ok and colors.lime or colors.red)
        end },
        self:back(true),
    })
    local auto = Settings.get("autoBackup") ~= false
    local y = self:kv(top, "Automatisch", auto and "taeglich, 3 bleiben" or "aus", nil, {
        { text = "AN", h = 1, style = auto and "primary" or nil, onClick = function() Settings.set("autoBackup", true) end },
        { text = "AUS", h = 1, style = (not auto) and "primary" or nil, onClick = function() Settings.set("autoBackup", false) end },
    })
    local drives = Sys.backupDrives()
    y = self:kv(y, "Diskette", (#drives > 0) and ("bekommt jede Sicherung (" .. drives[1].drive .. ")") or ("leere Diskette, Name " .. Sys.BACKUP_LABEL), nil, {
        { text = "EINRICHTEN", h = 1, onClick = Kernel.guard("Backup-Diskette", function()
            for _, drive in ipairs(Kernel.hw.drives or {}) do
                local ok, done = pcall(function()
                    if disk.isPresent(drive) and disk.hasData(drive) then
                        local l = disk.getLabel(drive)
                        if l and l ~= Sys.BACKUP_LABEL and l ~= "" then return "belegt:" .. l end
                        disk.setLabel(drive, Sys.BACKUP_LABEL)
                        return "ok"
                    end
                end)
                if ok and done == "ok" then
                    local okB, msg = Sys.backupMake()
                    Kernel.notify(okB and "Backup-Diskette fertig" or msg, okB and colors.lime or colors.red)
                    return
                elseif ok and done then
                    Kernel.notify("Diskette heisst schon " .. done:sub(8) .. " - leere Diskette nehmen", colors.orange)
                    return
                end
            end
            Kernel.notify("Keine Diskette im Laufwerk", colors.orange)
        end) },
    })
    y = y + 1
    if #list == 0 then
        UI.empty(y + 1, "Noch kein Backup.", "JETZT SICHERN tippen.")
        return
    end
    UI.section(2, y, "SICHERUNGEN", w - 3)
    y = y + 2
    local ch = narrow and 2 or bh
    UI.list(self.setPage, list, y, ch + 1, function(b, ry)
        local tx, xr = UI.rowCard(ry, ch)
        local bx = UI.buttonsRight({
            { text = narrow and "HOLEN" or "ZURUECKHOLEN", style = "danger", confirm = "rest:" .. b.path, onClick = function()
                local ok, msg = Sys.backupRestore(b.path)
                if ok then os.reboot() end     -- sofort: sonst ueberschreibt das laufende OS die Dateien wieder
                Kernel.notify(msg, ok and colors.lime or colors.red)
            end },
        }, narrow and (ry + 1) or ry, xr)
        local room = (narrow and xr or (bx - 2)) - tx + 1
        UI.text(tx, ry, b.label:sub(1, room), colors.white)
        local info = b.src .. "  " .. fmtSize(b.size)
        if #b.label + 3 + #info <= room then UI.text(tx + #b.label + 3, ry, info, colors.lightGray) end
    end)
end

function Info:drawTrash()
    local w, h, bh, narrow = Kernel.w, Kernel.h, UI.bh(), UI.narrow()
    local list = Sys.trashList()
    local top = UI.header("PAPIERKORB", not narrow and ("Geloeschte Notizen und Scripts, " .. Sys.TRASH_DAYS .. " Tage lang") or nil, {
        { text = "LEEREN", style = "danger", confirm = "trash-all", disabled = #list == 0, onClick = function()
            local n = Sys.trashDrop()
            Kernel.notify(n .. " Datei(en) endgueltig geloescht", colors.orange)
        end },
        self:back(true),
    })
    if #list == 0 then
        UI.empty(top + 2, "Der Papierkorb ist leer.", "DEL in NOTIZEN und LUA APPS legt Dateien hier ab.")
        return
    end
    local ch = narrow and 2 or bh
    UI.list(self.setPage, list, top, ch + 1, function(e, y)
        local tx, xr = UI.rowCard(y, ch)
        local bx = UI.buttonsRight({
            { text = narrow and "ZURUECK" or "WIEDERHERSTELLEN", style = "primary", onClick = function()
                local ok, msg = Sys.trashRestore(e.id)
                Kernel.notify(ok and ("Zurueck: " .. msg) or msg, ok and colors.lime or colors.red)
            end },
            { text = "X", style = "danger", confirm = "trash:" .. e.id, onClick = function() Sys.trashDrop(e.id) end },
        }, narrow and (y + 1) or y, xr)
        local room = (narrow and xr or (bx - 2)) - tx + 1
        UI.text(tx, y, e.name:sub(1, room), colors.white)
        local info = fs.getDir(e.from) .. "  " .. Info.ago(e.t) .. "  " .. fmtSize(e.size)
        if #e.name + 2 + #info <= room then UI.text(tx + #e.name + 2, y, info, colors.lightGray) end
    end)
end

-- AUFRAEUMEN: Muell (immer an), Rest nur auf Wunsch, darunter wer wie viel belegt
function Info:drawClean()
    local w, bh, narrow = Kernel.w, UI.bh(), UI.narrow()
    if not self.cleanItems or os.clock() - (self.cleanT or -99) > 15 then
        self.cleanItems, self.cleanUse, self.cleanT = Sys.cleanScan(), Sys.usage(), os.clock()
        self.cleanSel = self.cleanSel or {}
    end
    local items, sel = self.cleanItems, self.cleanSel
    local function on(it) if sel[it.path] ~= nil then return sel[it.path] end return it.kind == "muell" end
    local total, count = 0, 0
    for _, it in ipairs(items) do if on(it) then total, count = total + it.size, count + 1 end end
    local top = UI.header("AUFRAEUMEN", not narrow and "Nur echter Muell - deine Dateien bleiben" or nil, {
        { text = narrow and "LOS" or ("AUFRAEUMEN " .. fmtSize(total)), style = "primary", confirm = "clean", disabled = count == 0,
          onClick = function()
              local freed, n = Sys.clean(items, on)
              self.cleanT, self.cleanSel = -99, {}
              Kernel.notify(n .. " entfernt, " .. fmtSize(freed) .. " frei geworden", colors.lime)
          end },
        self:back(true),
    })
    local free, cap = fs.getFreeSpace("/"), nil
    pcall(function() cap = fs.getCapacity("/") end)
    local x0 = narrow and 1 or 2
    if type(free) == "number" and type(cap) == "number" and cap > 0 then
        UI.text(x0, top, ("Frei " .. fmtSize(free) .. " von " .. fmtSize(cap)):sub(1, w - x0), colors.white)
        local bx = narrow and x0 or (x0 + 24)
        local by = narrow and (top + 1) or top
        UI.bar(bx, by, math.max(4, w - bx - 1), 1 - free / cap, (free < 60000) and colors.orange or colors.lime)
        top = by + 2
    end
    -- Zeilen: Eintraege (Grund, Groesse, Pfad, Knopf), Automatik, Belegung
    local rows = {}
    for _, it in ipairs(items) do rows[#rows + 1] = { item = it } end
    if #items == 0 then rows[1] = { text = "Kein Muell gefunden - alles sauber.", color = colors.lime } end
    rows[#rows + 1] = { auto = true }
    local used = {}
    for _, g in ipairs(self.cleanUse or {}) do if g[2] > 0 then used[#used + 1] = g end end
    for i = 1, #used, 2 do rows[#rows + 1] = { use = { used[i], used[i + 1] } } end
    UI.list(self.setPage, rows, top, 3, function(r, y)
        local tx, xr = UI.rowCard(y, 2)
        if r.item then
            local it, isOn = r.item, on(r.item)
            local bx = UI.buttonsRight({ { text = isOn and "WEG" or "BLEIBT", style = isOn and "danger" or nil, h = 1,
                                           onClick = function() sel[it.path] = not isOn end } }, y, xr)
            local size = fmtSize(it.size)
            UI.text(tx, y, it.why:sub(1, math.max(1, bx - tx - #size - 3)), it.kind == "muell" and colors.white or colors.lightGray)
            UI.text(bx - #size - 1, y, size, colors.lightGray)
            UI.text(tx, y + 1, it.path:sub(1, xr - tx + 1), colors.lightGray)
        elseif r.auto then
            local auto = Settings.get("cleanAuto") ~= false
            local bx = UI.buttonsRight({
                { text = "AN", h = 1, style = auto and "primary" or nil, onClick = function() Settings.set("cleanAuto", true) end },
                { text = "AUS", h = 1, style = (not auto) and "primary" or nil, onClick = function() Settings.set("cleanAuto", false) end } }, y, xr)
            UI.text(tx, y, ("Automatisch"):sub(1, bx - tx - 1), colors.white)
            UI.text(tx, y + 1, (auto and "einmal am Tag, nur Muell" or "aus"):sub(1, xr - tx + 1), colors.lightGray)
        elseif r.use then
            for i, g in ipairs(r.use) do
                local t = (g[1] .. ": " .. fmtSize(g[2]))
                UI.text(tx, y + i - 1, t:sub(1, xr - tx + 1), colors.lightGray)
            end
        else
            UI.text(tx, y, r.text:sub(1, xr - tx + 1), r.color or colors.white)
        end
    end)
end

-- Einrichtungs-Assistent: jeder Schritt zeigt eine Einstellung (dieselben
-- Knoepfe wie in EINSTELLUNGEN). Alles darf man ueberspringen.
Info.SETUP = {
    { row = "Besitzer", title = "Wie heisst du?",
      text = "Dein Minecraft-Name. An ihn schickt die Chat Box Meldungen: Funde, Alarm, Lager knapp." },
    { row = "Sperrcode", title = "Sperrcode",
      text = "Schuetzt das OS vor anderen Spielern. Ab Werk ist er 3344 - bitte aendern." },
    { row = "Schwarm-Passwort", title = "Schwarm-Passwort",
      text = "Verschluesselt den Funk zu deinen Turtles. Danach DATEN > TURTLE-DISK neu schreiben." },
    { row = "Handy-Passwort", title = "Handy-Passwort",
      text = "Freunde mit dem GTS Phone sehen damit nur dein Lager. Ab Werk 1234." },
    { row = "PC-Position", title = "Wo steht der PC?",
      text = "Fuer Karte und Entfernungen. Mit GPS geht es von selbst, sonst die F3-Koordinaten eintippen." },
    { lager = true, title = "Lager",
      text = "Kisten per Wired Modem und Kabel anschliessen. Dann eine Kiste als EIN/AUS-Kiste festlegen." },
    { done = true, title = "Fertig!",
      text = "Der SYSTEM-CHECK zeigt jederzeit, ob alles passt. Diese Einrichtung findest du in INFO > SYSTEM." },
}

function Info:drawSetup()
    local w, h, bh, narrow = Kernel.w, Kernel.h, UI.bh(), UI.narrow()
    local steps = Info.SETUP
    self.step = math.max(1, math.min(self.step or 1, #steps))
    local s = steps[self.step]
    local top = UI.header("EINRICHTUNG", "Schritt " .. self.step .. " von " .. #steps, {
        { text = narrow and "X" or "SPAETER", style = "ghost", onClick = function() self.view = "info" end },
    })
    local px = math.floor((w - (#steps * 2 - 1)) / 2) + 1
    for i = 1, #steps do
        UI.text(px + (i - 1) * 2, top, "\7", (i == self.step) and colors.lime or ((i < self.step) and colors.white or colors.brown))
    end
    local cw = narrow and w or math.min(w - 4, 64)
    local cx = math.floor((w - cw) / 2) + 1
    local y = top + 2
    local lines = UI.wrap(s.text, cw - 4)
    local ch = 4 + #lines + bh
    UI.card(cx, y, cw, ch)
    UI.text(cx + 2, y + 1, s.title, colors.white)
    for i, l in ipairs(lines) do UI.text(cx + 2, y + 1 + i, l, colors.lightGray) end
    local ry = y + 3 + #lines
    local value, color, buttons = nil, nil, {}
    if s.row then
        for _, r in ipairs(self:settingRows()) do
            if r[1] == s.row then value, color, buttons = r[2], r[3], r[4] end
        end
    elseif s.lager then
        local invs, L = #(Kernel.hw.inventories or {}), Apps.byId.lager
        value = (invs == 0) and "keine Kisten gefunden" or (invs .. " Kisten" .. ((L and L.cfg.io) and ", EIN/AUS fertig" or ", EIN/AUS fehlt"))
        color = (invs > 0 and L and L.cfg.io) and colors.lime or colors.lightGray
        buttons = { { text = narrow and "LAGER" or "LAGER EINRICHTEN", onClick = function()
            if L then L.view = "kisten" end
            Kernel.open("lager")
        end } }
    elseif s.done then
        buttons = { { text = "SYSTEM-CHECK", onClick = function() self.view = "check" end } }
    end
    local bx = (#buttons > 0) and UI.buttonsRight(buttons, ry, cx + cw - 3) or (cx + cw)
    if value then UI.text(cx + 2, ry, tostring(value):sub(1, bx - cx - 4), color or colors.white) end
    UI.surface = colors.black
    local ny = math.min(y + ch + 1, h - bh * 2)
    local nav = {}
    if self.step > 1 then nav[#nav + 1] = { text = "\17 ZURUECK", onClick = function() self.step = self.step - 1 end } end
    if self.step < #steps then
        nav[#nav + 1] = { text = "WEITER \16", style = "primary", onClick = function() self.step = self.step + 1 end }
    else
        nav[#nav + 1] = { text = "FERTIG", style = "primary", onClick = function()
            Settings.set("setupDone", true)
            self.view, self.step = "info", 1
            Kernel.notify("Einrichtung fertig", colors.lime)
        end }
    end
    UI.buttonsRight(nav, ny, cx + cw - 1)
end

function Info:drawSafe()
    local w, h, bh, narrow = Kernel.w, Kernel.h, UI.bh(), UI.narrow()
    local top = UI.header("SICHERER MODUS", Sys.safe and "ist an" or "ist aus", { self:back(true) }, Sys.safe and colors.orange or nil)
    local text = "Startet GTS OS ohne Erweiterungen aus /gts/apps; eigene Programme in LUA APPS starten nicht. "
        .. "So kommst du wieder hinein, wenn ein Script das OS lahmlegt. Nach 3 Abstuerzen in 10 Minuten passiert das von selbst."
    local y = top
    for _, l in ipairs(UI.wrap(text, math.min(w - 4, 70))) do UI.text(2, y, l, colors.lightGray) y = y + 1 end
    y = y + 1
    UI.button{ x = 2, y = y, text = Sys.safe and "NORMAL NEU STARTEN" or "NEUSTART IM SICHEREN MODUS", style = Sys.safe and "primary" or "danger",
               confirm = "safe", onClick = function() Sys.setSafe(not Sys.safe) os.reboot() end }
end

local function fmtDuration(sec)
    sec = math.floor(sec)
    local d, h, m = math.floor(sec / 86400), math.floor(sec / 3600) % 24, math.floor(sec / 60) % 60
    if d > 0 then return d .. "d " .. h .. "h" end
    if h > 0 then return h .. "h " .. m .. "min" end
    return m .. "min " .. (sec % 60) .. "s"
end

-- Liefert die Abschnitte: { title, rows = { { Bezeichnung, Wert, Farbe } } }
function Info:sections()
    local hw, d = Kernel.hw, Kernel.display
    local out = {}
    local function add(title, rows) out[#out + 1] = { title = title, rows = rows } end
    local host = tostring(_HOST or "")
    local device = (pocket and "Pocket Computer") or (turtle and "Turtle") or (commands and "Command Computer")
                   or "Computer"
    if term.isColour and term.isColour() then device = "Advanced " .. device end

    add("SYSTEM", {
        { "GTS OS", RELEASE .. ((EDITION == "pocket") and " Pocket" or (PHONE and " Phone" or "")), colors.lime },
        { "CraftOS", os.version and os.version():gsub("^CraftOS ", "") or "?" },
        { "CC: Tweaked", host:match("ComputerCraft ([%w%.%-]+)") or "?" },
        { "Minecraft", host:match("Minecraft ([%w%.%-]+)") or "?" },
        { "Geraet", device },
        { "ID / Name", "#" .. os.getComputerID() .. " " .. (os.getComputerLabel() or "") },
        { "Laufzeit", fmtDuration(os.clock()) },
        { "Tastatur", "F1 Home, F2-F12 Apps" },
        { "Spielzeit", (os.day and ("Tag " .. os.day() .. ", ") or "") .. textutils.formatTime(os.time(), true) },
    })

    local screen
    if d.monitor then screen = "Monitor " .. d.name
    else screen = pocket and "Pocket-Bildschirm" or "Computer-Bildschirm" end
    add("ANZEIGE", {
        { "Oberflaeche", screen },
        { "Groesse", Kernel.W .. " x " .. Kernel.H .. " Zeichen" },
        { "Schriftgroesse", d.monitor and tostring(d.scale or "?") or "-" },
        { "Bedienung", d.touch and "Touch" or "Maus und Tastatur" },
        { "Monitore", tostring(#hw.monitors) },
    })

    local radio = {}
    if #hw.modems == 0 then
        radio[#radio + 1] = { "Modem", "keins", colors.red }
    end
    for _, m in ipairs(hw.modems) do
        radio[#radio + 1] = { "Modem " .. m.name, m.wireless and "Wireless" or "Kabel",
                              m.wireless and colors.lime or colors.white }
    end
    if PHONE then
        local r = Apps.byId.lager and Apps.byId.lager.remote
        radio[#radio + 1] = { "Lager-Daten", r and ("vor " .. math.floor(os.clock() - (r.at or 0)) .. " s") or "noch keine",
                              r and colors.lime or colors.lightGray }
    else
    radio[#radio + 1] = { "Funk", Net.isDefault and "verschluesselt, Standard-Passwort!" or "verschluesselt",
                          Net.isDefault and colors.orange or colors.lime }
    end
    local gps = self.gpsBusy and "suche ..." or self.gps or "nicht geprueft"
    radio[#radio + 1] = { "GPS", gps, (self.gps and self.gps:find("^%-?%d")) and colors.lime or colors.lightGray }
    radio[#radio + 1] = { "HTTP", http and "an" or "aus", http and colors.lime or colors.red }
    add("FUNK", radio)

    local fleet = {}
    for _, f in pairs(Fleets) do
        if not f.hidden then
            local online, total = f:counts()
            fleet[#fleet + 1] = { f.short, online .. " online / " .. total, (online > 0) and colors.lime or nil }
        end
    end
    table.sort(fleet, function(a, b) return a[1] > b[1] end)
    fleet[#fleet + 1] = { "Funde offen", tostring(#Finds.list) }
    fleet[#fleet + 1] = { "DD-Tunnel", CONFIG.exploreDist .. " Bloecke" }
    fleet[#fleet + 1] = { "CHUNK-Muell", (Settings.get("chunkTrash") ~= false) and "wegwerfen" or "behalten" }
    if PHONE then
        local t, day, sleep, wait, moon = Kernel.mcTime()
        add("MINECRAFT", { { "Uhrzeit", string.format("%02d:%02d", math.floor(t), math.floor((t % 1) * 60)) },
                           { "Tag", tostring(day) }, { "Schlafen", sleep and "jetzt" or ("in " .. wait .. " min") },
                           { "Mond", moon } })
    else
        add("SCHWARM", fleet)
    end

    local ex = {}
    for _, e in ipairs(hw.all) do
        if Extras.KINDS[e.kind] then ex[#ex + 1] = { Extras.KINDS[e.kind], e.name, colors.lime } end
    end
    if #ex == 0 then ex[1] = { "Advanced Periph.", "keine (optional)", colors.lightGray } end
    if Extras.nearby then ex[#ex + 1] = { "Spieler nah", tostring(#Extras.nearby) } end
    if Extras.alarm then ex[#ex + 1] = { "ALARM", Extras.alarm.name, colors.red } end
    if Extras.env then
        ex[#ex + 1] = { "Biom", tostring(Extras.env.biome or "?") }
        ex[#ex + 1] = { "Wetter", tostring(Extras.env.weather or "?") }
        ex[#ex + 1] = { "Mond", tostring(Extras.env.moon or "?") }
    end
    add("EXTRAS", ex)

    local dev = {}
    local p = hw.printer
    if p then
        local ok, paper, ink = pcall(function() return p.getPaperLevel(), p.getInkLevel() end)
        dev[#dev + 1] = { "Drucker", ok and ("Papier " .. paper .. ", Tinte " .. ink) or "ja" }
    else
        dev[#dev + 1] = { "Drucker", "nein", colors.lightGray }
    end
    if #hw.drives == 0 then
        dev[#dev + 1] = { "Laufwerk", "nein", colors.lightGray }
    end
    for _, drive in ipairs(hw.drives) do
        local inside = "leer"
        if disk.isPresent(drive) then
            inside = disk.hasData(drive) and ("Disk " .. (disk.getLabel(drive) or ("#" .. tostring(disk.getID(drive)))))
                     or "Musik-Disk"
        end
        dev[#dev + 1] = { "Laufwerk " .. drive, inside }
    end
    for _, e in ipairs(hw.all) do
        if e.kind ~= "modem" and e.kind ~= "drive" and e.kind ~= "printer" and e.kind ~= "monitor"
           and not Extras.KINDS[e.kind] and not e.inventory then
            dev[#dev + 1] = { e.name, e.kind }
        end
    end
    add("GERAETE", dev)

    local free, cap = fs.getFreeSpace("/"), nil
    if fs.getCapacity then
        local ok, c = pcall(fs.getCapacity, "/")
        if ok then cap = c end
    end
    local function count(dir)
        return fs.isDir(dir) and #fs.list(dir) or 0
    end
    local logSize = fs.exists(CONFIG.logFile) and fs.getSize(CONFIG.logFile) or 0
    add("SPEICHER", {
        { "Frei", fmtSize(free) .. (cap and (" von " .. fmtSize(cap)) or ""),
          (type(free) == "number" and free < 50000) and colors.red or nil },
        { "Notizen", tostring(#Notes.list()) },
        { "Scripts", tostring(count(CONFIG.scriptDir)) },
        { "Backups", tostring(count(CONFIG.backupDir)) },
        { "Erweiterungen", tostring(count(CONFIG.appDir)) },
        { "Log", fmtSize(logSize) .. " " .. CONFIG.logFile },
    })
    return out
end

-- GPS-Abfrage im eigenen Dienst: blockiert die Oberflaeche nicht.
function Info:service()
    -- beim Start einmal von selbst (fuer Karte und Entfernungen im SCHWARM)
    if Kernel.hw and Kernel.hw.modem then os.queueEvent("gts_gps") end
    while true do
        os.pullEvent("gts_gps")
        self.gpsBusy = true
        Kernel.invalidate()
        local ok, x, y, z = pcall(gps.locate, 2)
        self.gpsBusy = false
        if ok and type(x) == "number" then
            x, y, z = math.floor(x), math.floor(y), math.floor(z)
            self.gps = x .. " " .. y .. " " .. z
            Geo.gps, Geo.gpsT = { x = x, y = y, z = z }, os.clock()
        else
            self.gps = #Kernel.hw.modems > 0 and "keine Antwort" or "kein Modem"
        end
        Kernel.invalidate()
    end
end

function Info:onScroll(dir)
    local state = (self.view ~= "info") and self.setPage or self
    state.page = math.max(1, state.page + dir)
end
function Info:tick() return Kernel.app == self end   -- Laufzeit und Uhr laufen mit

Info.VIEWS = { settings = "drawSettings", system = "drawSystem", check = "drawCheck", update = "drawUpdate",
               backup = "drawBackup", trash = "drawTrash", setup = "drawSetup", safe = "drawSafe", clean = "drawClean" }

function Info:draw()
    if self.input then return Input.draw(self) end
    local v = Info.VIEWS[self.view]
    if v then return self[v](self) end
    local w, h, bh = Kernel.w, Kernel.h, UI.bh()
    local narrow = UI.narrow()
    local sub = not narrow and ("GTS OS " .. RELEASE .. "  |  " .. (os.getComputerLabel() or ("Computer #" .. os.getComputerID()))) or nil
    local top = UI.header("INFO", sub, {
        { text = narrow and "SETUP" or "EINSTELLUNGEN", style = Net.isDefault and "primary" or nil,
          onClick = function() self.view, self.setPage.page = "settings", 1 end },
        { text = narrow and "SYS" or "SYSTEM", onClick = function() self.view, self.setPage.page = "system", 1 end },
        { text = "GPS", disabled = self.gpsBusy or not gps, onClick = function() os.queueEvent("gts_gps") end },
        { text = narrow and "NEU" or "AKTUALISIEREN", onClick = function()
            Kernel.scanHardware()
            Kernel.notify("Geraete neu eingelesen")
        end },
    })
    -- Abschnitte als Karten in Spalten: jeder kommt in die erste Spalte, in
    -- der er noch Platz hat; was nirgends passt, kommt auf die naechste Seite.
    local cols = math.max(1, math.floor((w - 1) / 33))
    local cw = math.floor((w - 1) / cols) - 1
    local bottom = h - bh - 1
    local pages = {}
    local function newPage()
        local p = { fill = {} }
        for c = 1, cols do p[c], p.fill[c] = {}, top end
        pages[#pages + 1] = p
        return p
    end
    newPage()
    for _, sec in ipairs(self:sections()) do
        -- Zeilen fuer die Spaltenbreite: zu lange Werte rutschen in eine eigene Zeile.
        sec.lines = {}
        for _, r in ipairs(sec.rows) do
            local key, val = r[1], tostring(r[2])
            local kw = math.min(#key, 15)
            if #val <= cw - 4 - kw then
                sec.lines[#sec.lines + 1] = { key:sub(1, 15), val, r[3] }
            else
                if #val > cw - 3 then val = val:sub(1, cw - 4) .. "~" end
                sec.lines[#sec.lines + 1] = { key:sub(1, cw - 3), "", r[3] }
                sec.lines[#sec.lines + 1] = { "", val, r[3] }
            end
        end
        local need = #sec.lines + 1
        local placed = false
        for _, p in ipairs(pages) do
            for c = 1, cols do
                if p.fill[c] + need - 1 <= bottom or p.fill[c] == top then
                    table.insert(p[c], { sec = sec, y = p.fill[c] })
                    p.fill[c] = p.fill[c] + need + 1
                    placed = true
                    break
                end
            end
            if placed then break end
        end
        if not placed then
            local p = newPage()
            table.insert(p[1], { sec = sec, y = top })
            p.fill[1] = top + need + 1
        end
    end
    self.page = math.max(1, math.min(self.page, #pages))
    for c = 1, cols do
        local list = pages[self.page][c]
        local x = 2 + (c - 1) * (cw + 1)
        for _, item in ipairs(list) do
            local sec, sy = item.sec, item.y
            local rows = math.min(#sec.lines, bottom - sy)
            UI.card(x, sy, cw, rows + 1)
            UI.text(x + 1, sy, sec.title, colors.white)
            for i = 1, rows do
                local l = sec.lines[i]
                UI.text(x + 1, sy + i, l[1], colors.lightGray)
                -- Werte weiss; der Akzent nur als kleiner Status-Punkt davor
                local col = l[3]
                if col == colors.lime then
                    UI.text(x + cw - 3 - #l[2], sy + i, "\7", colors.lime)
                    col = colors.white
                end
                UI.text(x + cw - 1 - #l[2], sy + i, l[2], col or colors.white)
            end
            UI.surface = colors.black
        end
    end
    if #pages > 1 then UI.pager(self, #pages) end
end

Apps.register(Info)

-- ======================================================================
-- [16] DIENSTE UND START
-- ======================================================================

-- Tastatur am PC: F1 = HOME, F2 bis F12 = Apps in der Reihenfolge der
-- Taskleiste. In der Shell bleiben die F-Tasten beim Programm, im Editor
-- passiert nichts (sonst ginge ungespeicherter Text verloren).
function Kernel.fkey(code)
    if Kernel.app == Shell or Kernel.app.fullscreen then return nil end
    for i = 1, 12 do
        local k = keys["f" .. i]
        if k and code == k then
            if i == 1 then return "home" end
            local app = UI.taskLayout().list[i - 1]
            return app and app.id
        end
    end
end

-- Oberflaeche: Eingaben verteilen und bei Bedarf neu zeichnen.
local function uiRoutine()
    Kernel.wakeSent = false
    Kernel.render()
    while true do
        local ev = table.pack(os.pullEventRaw())
        local name, a, b, c = ev[1], ev[2], ev[3], ev[4]
        local d, app = Kernel.display, Kernel.app
        if name == "monitor_touch" or name == "mouse_click" or name == "char" or name == "key"
           or name == "paste" or name == "mouse_scroll" then
            Kernel.lastInput = os.clock()
        end
        if Kernel.popup and (name == "char" or name == "key" or name == "paste" or name == "mouse_scroll") then
            -- Code-Fenster offen: Tastatur geht nur dorthin.
            if name == "char" and a:find("^%d$") then Kernel.codeKey(a)
            elseif name == "key" and a == keys.backspace then Kernel.codeKey("del")
            elseif name == "key" and (a == keys.enter or a == keys.numPadEnter) then Kernel.codeKey("ok") end
        elseif name == "gts_redraw" then
            Kernel.wakeSent = false
        elseif name == "monitor_touch" then
            if d.monitor and a == d.name then UI.click(b, c) end
        elseif name == "mouse_click" then
            -- Klicks auf den PC-Schirm zaehlen nur, wenn dort auch die Oberflaeche ist.
            if not d.monitor and a == 1 then UI.click(b, c) end
        elseif name == "mouse_scroll" then
            if not d.monitor then Kernel.call(app, "onScroll", a) Kernel.invalidate() end
        elseif name == "char" then
            if app.onChar then Kernel.call(app, "onChar", a) Kernel.invalidate() end
        elseif name == "key" then
            local target = Kernel.fkey(a)
            if target then
                Kernel.open(target)
            elseif app.onKey then
                Kernel.call(app, "onKey", a)
                Kernel.invalidate()
            end
        elseif name == "paste" then
            if app.onPaste then Kernel.call(app, "onPaste", a) Kernel.invalidate() end
        elseif name == "monitor_resize" or name == "term_resize"
            or name == "peripheral" or name == "peripheral_detach" then
            Kernel.hardwareEvent(name, a)
        elseif name == "disk" or name == "disk_eject" then
            Kernel.invalidate()
        end
        if Kernel.dirty and Kernel.running then Kernel.render() end
    end
end

-- Funk: nimmt Status-Pakete an. Nur verschluesselte Pakete mit dem
-- Schwarm-Schluessel zaehlen; alles andere ist fuer das OS Rauschen.
local function netRoutine()
    while true do
        local _, id, msg, proto = os.pullEvent("rednet_message")
        if proto == Net.proto and type(id) == "number" then
            local payload, from = Net.open(msg)
            local fleet = payload and Fleets[payload.t]
            if payload and Kernel.claude and (payload.t == "CLD" or (payload.t == "UP" and payload.role == "claude")) then
                fleet = Kernel.claude
            end
            if fleet and from == id then
                local ok, changed = pcall(fleet.receive, fleet, id, payload)
                if ok and changed and (Kernel.app == fleet or Kernel.app.id == "home") then
                    Kernel.invalidate()
                end
            elseif payload and from == id and Kernel.onNet then
                pcall(Kernel.onNet, id, payload)
            end
        elseif proto == "SWARM_UPDATE" and type(id) == "number" then
            if not legacy[id] then Kernel.invalidate() end
            legacy[id] = os.clock()   -- alte Turtle (v4): Hinweis in SCHWARM
        end
    end
end

local function outRoutine()
    while true do
        local job = table.remove(Kernel.outbox, 1)
        if not job then
            os.pullEvent("gts_out")
        else
            pcall(function()
                if job.id == "*" then Net.broadcast(job.p) else Net.send(job.id, job.p) end
            end)
            if #Kernel.outbox > 0 then
                os.queueEvent("gts_out_next")
                os.pullEvent("gts_out_next")
            end
        end
    end
end

-- Sekundentakt: Offline-Erkennung, ablaufende Meldungen und Bestaetigungen.
local function tickRoutine()
    while true do
        os.sleep(1)
        local changed = false
        for _, app in ipairs(Apps.list) do
            if app.tick then
                local ok, res = pcall(app.tick, app)
                if ok and res then changed = true end
            end
        end
        local now = os.clock()
        if Kernel.armed and now >= Kernel.armed.untilT then Kernel.armed, changed = nil, true end
        if Kernel.toast and now >= Kernel.toast.untilT then Kernel.toast, changed = nil, true end
        local mins = Settings.get("autoLock")
        if not Kernel.locked and type(mins) == "number" and mins > 0 and now - Kernel.lastInput > mins * 60 then
            Kernel.lock()
            changed = true
        end
        local clock = os.date("%H:%M")
        if clock ~= Kernel.clock then
            Kernel.clock = clock
            if not Kernel.app.fullscreen then changed = true end
        end
        if changed then Kernel.invalidate() end
    end
end

-- Eigene Apps: jede .lua-Datei in /gts/apps wird geladen und kann sich
-- mit GTS.Apps.register{...} anmelden. Fehler darin landen nur im Log.
local function loadPlugins()
    if not fs.isDir(CONFIG.appDir) then return end
    local api = { VERSION = VERSION, RELEASE = RELEASE, CONFIG = CONFIG, Kernel = Kernel, UI = UI, Apps = Apps,
                  Notes = Notes, Finds = Finds }
    local files = fs.list(CONFIG.appDir)
    table.sort(files)
    for _, file in ipairs(files) do
        if file:match("%.lua$") then
            local path = fs.combine(CONFIG.appDir, file)
            local fn, err = loadfile(path, nil, setmetatable({ GTS = api }, { __index = _ENV }))
            local ok = false
            if fn then ok, err = pcall(fn) end
            Kernel.log(ok and "INFO" or "FEHLER", "App " .. file .. (ok and " geladen" or (": " .. tostring(err))))
        end
    end
end

local function main()
    pcall(Sys.updBoot)          -- zuerst: ein frisches Update muss sich bei einem Absturz zuruecknehmen lassen
    fs.makeDir(CONFIG.notesDir)
    fs.makeDir(CONFIG.backupDir)
    fs.makeDir(fs.getDir(CONFIG.logFile))
    fs.makeDir(fs.getDir(CONFIG.dbFile))
    fs.makeDir(CONFIG.scriptDir)
    Settings.load()
    -- wer schon eingerichtet hat (v7), bekommt den Assistenten nicht mehr angeboten
    if Settings.get("setupDone") == nil and ((Settings.get("owner") or "") ~= "" or Settings.get("code")) then
        Settings.set("setupDone", true)
    end
    Sys.bootInit()
    setTheme(Settings.get("theme"), Settings.get("accent"))
    CONFIG.exploreDist = Settings.get("ddDist") or CONFIG.exploreDist
    Net.load(CONFIG.keyFile)
    -- Ein Gegner koennte sonst eine Diskette mit eigenem startup einlegen.
    pcall(function()
        if settings.get("shell.allow_disk_startup") ~= false then
            settings.set("shell.allow_disk_startup", false)
            settings.save()
        end
    end)
    Finds.load()
    if not READONLY then TurtleProgs.install() end
    Kernel.scanHardware()
    Kernel.initDisplay()
    Kernel.seq = math.floor(os.epoch("utc") / 100) % 100000000
    Kernel.clock = os.date("%H:%M")
    if Sys.safe then
        Kernel.log("WARN", "Sicherer Modus: ohne Erweiterungen")
        Kernel.notify("Sicherer Modus: ohne Erweiterungen", colors.orange, "info", "safe")
    else
        loadPlugins()
    end
    if PHONE then
        -- Handy fuer Freunde: Lager, Notizen, Rechner, Nether, Web, Games, Info - keine Turtles.
        Kernel.claude = nil
        for _, id in ipairs({ "swarm", "pcraft", "data", "shell", "luaapps", "claude" }) do
            local app = Apps.byId[id]
            if app then
                Apps.byId[id] = nil
                for i, a in ipairs(Apps.list) do if a == app then table.remove(Apps.list, i) break end end
            end
        end
        for k in pairs(Fleets) do Fleets[k] = nil end
        if Apps.byId.games then Apps.byId.games.tab = nil end
        if Net.isDefault and not fs.exists(CONFIG.keyFile) then
            Net.setKey(Net.derive(CONFIG.phonePassword), true)
        end
        UI.layoutCache = nil
    elseif EDITION == "claude" then
        -- Claude-Fernbedienung: nur Claude (als Startseite) und INFO.
        for _, app in ipairs({ table.unpack(Apps.list) }) do
            if app.id ~= "boot" and app.id ~= "claude" and app.id ~= "info" then
                Apps.byId[app.id] = nil
                for i, a in ipairs(Apps.list) do if a == app then table.remove(Apps.list, i) break end end
            end
        end
        local cl = Apps.byId.claude
        cl.tab = false
        Apps.byId.home = cl
        for k in pairs(Fleets) do Fleets[k] = nil end
        UI.layoutCache = nil
    elseif READONLY then
        -- Pocket = Fortschritts-Tablet: nur Anzeigen, keine Werkzeuge.
        Kernel.claude = nil
        for _, id in ipairs({ "pcraft", "data", "web", "shell", "luaapps", "notes", "editor", "games", "claude" }) do
            local app = Apps.byId[id]
            if app then
                Apps.byId[id] = nil
                for i, a in ipairs(Apps.list) do if a == app then table.remove(Apps.list, i) break end end
            end
        end
        UI.layoutCache = nil
    end
    Kernel.app = Apps.byId.boot
    Kernel.spawn("ui", uiRoutine, true, true)
    Kernel.spawn("net", netRoutine, true)
    Kernel.spawn("funk", outRoutine, true)
    Kernel.spawn("tick", tickRoutine, true)
    Kernel.spawn("extras", Extras.service, true)
    Kernel.spawn("system", Sys.service, true)
    for _, app in ipairs(Apps.list) do
        if app.service then
            Kernel.spawn(app.id .. "-dienst", function() app:service() end, true)
        end
    end

    while Kernel.running do
        local ev = table.pack(os.pullEventRaw())
        if ev[1] == "terminate" then
            -- Strg+T: beendet das OS, ausser die offene App faengt es ab (Shell).
            -- Gesperrt passiert nichts (sonst kaeme man so an die Shell).
            if Kernel.locked then
                Kernel.log("WARN", "Strg+T im gesperrten Zustand ignoriert")
            elseif not (Kernel.app and Kernel.app.onTerminate) then
                break
            else
                Kernel.call(Kernel.app, "onTerminate")
            end
        else
            for i = 1, #Kernel.routines do
                Kernel.resume(Kernel.routines[i], table.unpack(ev, 1, ev.n))
            end
        end
    end
end

print("Starte GTS OS " .. RELEASE .. "...")
local startDir = shell and shell.dir()
local ok, err = pcall(main)
if not ok then Kernel.crash = tostring(err) end
if startDir then pcall(shell.setDir, startDir) end

-- Absturz: eigener Bildschirm mit Neustart (zur Shell nur mit Sperrcode).
if Kernel.crash then
    Kernel.log("CRASH", Kernel.crash)
    local mon = Kernel.display and Kernel.display.monitor and Kernel.display.target
    local okS, res = pcall(Sys.crashScreen, Kernel.crash, mon)
    if not okS then
        Kernel.log("FEHLER", "Absturz-Bildschirm: " .. tostring(res))
        local t = os.startTimer(10)
        repeat local ev, id = os.pullEventRaw() until ev == "timer" and id == t
        os.reboot()
    end
end

-- Aufraeumen: Standardfarben zurueck, Monitor leeren, Meldung auf dem PC.
applyPalette(nativeTerm, false)
if Kernel.display and Kernel.display.monitor then
    applyPalette(Kernel.display.target, false)
    pcall(function()
        local m = Kernel.display.target
        m.setBackgroundColor(colors.black)
        m.setTextColor(colors.lightGray)
        m.clear()
        m.setCursorPos(2, 2)
        m.write("GTS OS beendet.")
    end)
end
nativeTerm.setBackgroundColor(colors.black)
nativeTerm.clear()
nativeTerm.setCursorPos(1, 1)
if Kernel.crash then
    Kernel.display = nil
    nativeTerm.setTextColor(colors.red)
    print("GTS OS abgestuerzt:")
    print(Kernel.crash)
    nativeTerm.setTextColor(colors.white)
    print("Details: " .. CONFIG.logFile)
else
    nativeTerm.setTextColor(colors.white)
    print("GTS OS sicher heruntergefahren.")
end
