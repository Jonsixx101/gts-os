-- ======================================================================
-- GTS OS - Installer (ComputerCraft und OpenComputers)       by Jonsi
-- ComputerCraft:  wget run https://raw.githubusercontent.com/Jonsixx101/gts-os/main/install.lua
-- OpenComputers:  wget -f https://raw.githubusercontent.com/Jonsixx101/gts-os/main/install.lua /tmp/i.lua
--                 /tmp/i.lua
-- ======================================================================
-- ---------------------------------------------------------------------
-- OpenComputers (MC 1.7.10): GTS OS bzw. Robot-Einheit installieren
-- Im Rechner/Robot (OpenOS, Internet Card):
--   wget -f https://raw.githubusercontent.com/Jonsixx101/gts-os/main/install.lua /tmp/i.lua
--   /tmp/i.lua
-- ---------------------------------------------------------------------
do
local okOC, component = pcall(require, "component")
if okOC and type(component) == "table" and component.isAvailable then
    local computer = require("computer")
    local fs = require("filesystem")
    local BASE = "https://raw.githubusercontent.com/Jonsixx101/gts-os/main/oc/"
    local gpu = component.isAvailable("gpu") and component.gpu or nil
    local function color(c) if gpu and gpu.getDepth() > 1 then pcall(gpu.setForeground, c) end end
    local function say(text, c) color(c or 0xFFFFFF) print(text) color(0xFFFFFF) end
    local GREEN, RED, YELLOW, GREY = 0x3DDC84, 0xFF5A5F, 0xF5A623, 0x9AA3B5
    local function readLine(mask)
        local line
        local okT, term = pcall(require, "term")
        if okT and term and term.read then
            local ok, r = pcall(term.read, {}, true, nil, mask and "*" or nil)
            if ok then line = r end
        end
        if line == nil then line = io.read() end
        return (tostring(line or ""):gsub("[\r\n]+$", ""))
    end
    local function ask(q, default, mask)
        color(YELLOW) io.write(q .. (default and (" [" .. default .. "]") or "") .. " ") color(0xFFFFFF)
        local a = readLine(mask)
        if a == "" and default then a = default end
        return a
    end
    local function hex(s)
        if type(s) ~= "string" then return "" end
        return (s:gsub(".", function(c) return string.format("%02x", c:byte()) end))
    end
    -- SHA-256 in Lua: die Data Card wirft "not enough energy", wenn der Puffer
    -- des Rechners (500 ohne Capacitor) fuer grosse Daten nicht reicht.
    local bit = bit32
    if not bit then local okb, b = pcall(require, "bit32") if okb then bit = b end end
    local band, bxor, bnot, rshift, rrot = bit.band, bit.bxor, bit.bnot, bit.rshift, bit.rrotate
    local KT = {}
    do
        local primes, n = {}, 2
        while #primes < 64 do
            local p = true
            for d = 2, math.floor(math.sqrt(n)) do if n % d == 0 then p = false break end end
            if p then primes[#primes + 1] = n end
            n = n + 1
        end
        for i, pr in ipairs(primes) do local c = pr ^ (1 / 3) KT[i] = math.floor((c - math.floor(c)) * 4294967296) end
    end
    local function be32(v) return string.char(band(rshift(v, 24), 255), band(rshift(v, 16), 255), band(rshift(v, 8), 255), band(v, 255)) end
    local function luaSha(msg)
        local ml, M32 = #msg, 4294967296
        msg = msg .. "\128" .. string.rep("\0", (55 - ml) % 64) .. be32(math.floor(ml * 8 / M32)) .. be32(ml * 8 % M32)
        local H = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 }
        local w = {}
        for p = 1, #msg, 64 do
            for i = 0, 15 do local a, b, c, d = msg:byte(p + i * 4, p + i * 4 + 3) w[i] = ((a * 256 + b) * 256 + c) * 256 + d end
            for i = 16, 63 do
                local x, y = w[i - 15], w[i - 2]
                w[i] = (w[i - 16] + bxor(rrot(x, 7), rrot(x, 18), rshift(x, 3)) + w[i - 7] + bxor(rrot(y, 17), rrot(y, 19), rshift(y, 10))) % M32
            end
            local a, b, c, d, e, f, g, h = H[1], H[2], H[3], H[4], H[5], H[6], H[7], H[8]
            for i = 0, 63 do
                local t1 = (h + bxor(rrot(e, 6), rrot(e, 11), rrot(e, 25)) + bxor(band(e, f), band(bnot(e), g)) + KT[i + 1] + w[i]) % M32
                local t2 = (bxor(rrot(a, 2), rrot(a, 13), rrot(a, 22)) + bxor(band(a, b), band(a, c), band(b, c))) % M32
                h, g, f, e, d, c, b, a = g, f, e, (d + t1) % M32, c, b, a, (t1 + t2) % M32
            end
            H[1], H[2], H[3], H[4] = (H[1] + a) % M32, (H[2] + b) % M32, (H[3] + c) % M32, (H[4] + d) % M32
            H[5], H[6], H[7], H[8] = (H[5] + e) % M32, (H[6] + f) % M32, (H[7] + g) % M32, (H[8] + h) % M32
        end
        local out = {}
        for i = 1, 8 do out[i] = be32(H[i]) end
        return table.concat(out)
    end
    -- Adler-32 (Pruefsumme der Downloads, ohne Data Card)
    local function adler(s)
        local a, b = 1, 0
        for i = 1, #s, 2048 do
            for k = i, math.min(#s, i + 2047) do a = a + s:byte(k) b = b + a end
            a, b = a % 65521, b % 65521
        end
        return string.format("%08x", b * 65536 + a)
    end

    say("GTS OS Installer · OpenComputers", GREEN)
    if not component.isAvailable("internet") then say("Es fehlt eine Internet Card.", RED) return end
    local inet = component.internet
    local function get(path)
        local ok, h = pcall(inet.request, BASE .. path .. "?t=" .. math.floor(computer.uptime() * 1000))
        if not ok or not h then return nil, tostring(h) end
        local dl = computer.uptime() + 30
        while true do
            local okc, done = pcall(h.finishConnect)
            if not okc then return nil, tostring(done) end
            if done then break end
            local okr0, c0 = pcall(h.response)
            if okr0 and c0 then break end
            if computer.uptime() > dl then return nil, "keine Antwort" end
            os.sleep(0.1)
        end
        local okr, code = pcall(h.response)
        if okr and tonumber(code) and tonumber(code) >= 400 then pcall(h.close) return nil, "HTTP " .. code end
        local parts = {}
        while true do
            local okd, chunk = pcall(h.read, 8192)
            if not okd then pcall(h.close) return nil, tostring(chunk) end
            if chunk == nil then break end
            if chunk == "" then os.sleep(0.05) else parts[#parts + 1] = chunk end
            if computer.uptime() > dl then pcall(h.close) return nil, "zu langsam" end
        end
        pcall(h.close)
        return table.concat(parts)
    end
    local function write(path, body)
        local dir = path:match("^(.*)/[^/]*$")
        if dir and dir ~= "" and not fs.exists(dir) then fs.makeDirectory(dir) end
        local h, err = io.open(path, "w")
        if not h then return false, err end
        h:write(body)
        h:close()
        return true
    end
    local function startup(line)
        local rc = "/home/.shrc"
        local old = ""
        local h = io.open(rc, "r")
        if h then old = h:read("*a") or "" h:close() end
        local out = {}
        for l in (old .. "\n"):gmatch("(.-)\n") do
            if l ~= "" and not l:match("^/gts/") then out[#out + 1] = l end
        end
        out[#out + 1] = line
        write(rc, table.concat(out, "\n") .. "\n")
    end

    say("Lade Dateiliste ...", GREY)
    local txt, err = get("manifest.lua")
    if not txt then say("Download fehlgeschlagen: " .. tostring(err), RED) return end
    local f = load("return " .. txt:gsub("^%s*%-%-[^\n]*\n", ""):gsub("^%s*%-%-[^\n]*\n", ""), "=manifest", "t", {})
    local okm, man = pcall(f or error)
    if not okm or type(man) ~= "table" or type(man.files) ~= "table" then say("Dateiliste unlesbar", RED) return end
    local data = component.isAvailable("data") and component.data or nil

    -- SHA-256: Data Card, sonst Lua (gleiches Ergebnis)
    local function sha(s)
        if data and #s <= 8192 then
            local ok, h = pcall(data.sha256, s)
            if ok and type(h) == "string" and #h == 32 then return h end
        end
        return luaSha(s)
    end
    local function fetchFile(entry)
        local body, e = get(entry.path)
        if not body then return nil, e end
        if entry.size and #body ~= entry.size then return nil, "Größe stimmt nicht" end
        if entry.sum then
            if adler(body) ~= entry.sum then return nil, "Prüfsumme falsch" end
        elseif data and data.sha256 and entry.sha then
            local ok, rawHash = pcall(data.sha256, body)
            if ok and type(rawHash) == "string" and hex(rawHash) ~= entry.sha then return nil, "Prüfsumme falsch" end
        end
        return body
    end

    if computer.isRobot and computer.isRobot() then
        -- Robot: nur den Lader + Schwarm-Zugang
        say("Robot erkannt - Einrichtung als Schwarm-Einheit (GTS OS " .. man.version .. ")", GREEN)
        if not data then say("Der Robot braucht eine Data Card (Tier 2 für AES).", RED) return end
        local modem = component.isAvailable("modem") and component.modem
        if not modem or not modem.isWireless() then say("Der Robot braucht eine Wireless Network Card.", RED) return end
        local entry
        for _, e in ipairs(man.files) do if e.path == "units/loader.lua" then entry = e end end
        if not entry then say("Lader fehlt in der Dateiliste", RED) return end
        local body, e = fetchFile(entry)
        if not body then say("Lader: " .. tostring(e), RED) return end
        local pw = ask("Schwarm-Passwort (wie am GTS OS):", nil, true)
        if pw == "" then say("Abgebrochen", RED) return end
        local port = tonumber(ask("Funk-Port:", "4711")) or 4711
        local name = ask("Name des Robots:", "Robot"):sub(1, 16)
        -- Schluessel wie im GTS OS (net.lua: N.derive)
        local k = sha("GTS-OC-1|" .. pw)
        for _ = 1, 64 do k = sha(k .. pw) end
        write("/gts/units/loader.lua", body)
        write("/gts/unit.cfg", "GTS1|" .. hex(k) .. "|" .. port .. "|" .. name)
        startup("/gts/units/loader.lua")
        say("Fertig. Der Robot startet neu und meldet sich im GTS OS (DROHNEN).", GREEN)
        say("Zu Hause: auf eine Kiste stellen (Abladen nach unten), Charger daneben.", GREY)
        os.sleep(2)
        computer.shutdown(true)
        return
    end

    -- PC / Server: GTS OS komplett
    local need = 0
    for _, e in ipairs(man.files) do need = need + (e.size or 0) end
    local hdd = fs.get("/")
    local free = hdd and (hdd.spaceTotal() - hdd.spaceUsed()) or math.huge
    say("GTS OS " .. man.version .. " für OpenComputers - " .. #man.files .. " Dateien, " .. math.floor(need / 1024) .. " KB", GREEN)
    if free < need + 32768 then say("Zu wenig Platz auf der Festplatte (" .. math.floor(free / 1024) .. " KB frei).", RED) return end
    if not component.isAvailable("gpu") or not component.isAvailable("screen") then say("Hinweis: Grafikkarte/Bildschirm fehlt.", YELLOW) end
    if not data then say("Hinweis: ohne Data Card kein AES - der Funk ist trotzdem gesiegelt (Drohnen brauchen eine eigene).", YELLOW) end
    local stage = "/gts/.install"
    if fs.exists(stage) then fs.remove(stage) end
    for i, e in ipairs(man.files) do
        io.write(string.format("[%2d/%2d] %s ", i, #man.files, e.path))
        local body, er = fetchFile(e)
        if not body then say("FEHLER: " .. tostring(er), RED) say("Nichts geändert - bitte nochmal versuchen.", RED) return end
        local ok, werr = write(stage .. "/" .. e.path, body)
        if not ok then say("FEHLER: " .. tostring(werr), RED) return end
        say("ok", GREEN)
    end
    -- alles geladen: einsetzen (Daten in /gts/data bleiben unberuehrt)
    for _, e in ipairs(man.files) do
        local dst = "/gts/" .. e.path
        if fs.exists(dst) then fs.remove(dst) end
        local dir = dst:match("^(.*)/[^/]*$")
        if dir and not fs.exists(dir) then fs.makeDirectory(dir) end
        fs.rename(stage .. "/" .. e.path, dst)
    end
    fs.remove(stage)
    startup("/gts/boot.lua")
    say("GTS OS ist installiert. Start beim Hochfahren ist eingerichtet.", GREEN)
    say("Erster Start: Einrichtung mit Name, Sperrcode, Admin-Code und Schwarm-Passwort.", GREY)
    local a = ask("Jetzt neu starten? (j/n)", "j")
    if a:lower():sub(1, 1) == "j" then computer.shutdown(true) end
    return
end
end
-- @@CC@@
-- ======================================================================
-- GTS OS - Installer                                          by Jonsi
-- Im Computer eintippen:
--   wget run https://raw.githubusercontent.com/Jonsixx101/gts-os/main/install.lua
-- Erkennt PC, Pocket und Turtle, laedt die passende Datei aus GitHub,
-- prueft sie und richtet sie als Startprogramm ein. Danach Neustart.
-- Spaeter kommen Updates per INFO > SYSTEM > UPDATE (am PC) und
-- SCHWARM > ALLE > UPDATE (Turtles).
-- ======================================================================
local BASE = "https://raw.githubusercontent.com/Jonsixx101/gts-os/main/"

local function color(c) if term.isColor() then term.setTextColor(c) end end
local function say(text, c) color(c or colors.white) print(text) color(colors.white) end

local function get(name)
    local h, err = http.get(BASE .. name .. "?t=" .. os.epoch("utc"), nil, true)
    if not h then return nil, err end
    local body = h.readAll()
    h.close()
    return body
end

local function ask(question, answers)
    while true do
        color(colors.yellow) write(question .. " ") color(colors.white)
        local a = (read() or ""):lower():gsub("%s", "")
        if answers[a] ~= nil then return answers[a] end
    end
end

term.clear()
term.setCursorPos(1, 1)
say("GTS OS Installer", colors.lime)
if not http then
    say("HTTP ist aus. In der CC: Tweaked-Config http aktivieren.", colors.red)
    return
end

-- 1) Welche Fassung?
local edition
if turtle then
    edition = "turtle"
elseif pocket then
    say("1 = GTS Pocket (Schwarm-Tablet)")
    say("2 = GTS Phone (fuer Freunde: Lager, Notizen ...)")
    say("3 = Claude-Fernbedienung")
    edition = ask("Welche?", { ["1"] = "pocket", ["2"] = "phone", ["3"] = "claude" })
else
    edition = "pc"
end

-- 2) Manifest lesen (Version, Groesse)
write("Lade Manifest ... ")
local text, err = get("manifest.lua")
local man = text and textutils.unserialize(text)
if type(man) ~= "table" or type(man.files) ~= "table" or type(man.files[edition]) ~= "table" then
    say("Fehler: " .. tostring(err or "manifest.lua kaputt"), colors.red)
    return
end
local entry = man.files[edition]
say(tostring(man.release or ("V" .. tostring(man.version))), colors.lime)

-- 3) Datei laden und pruefen
write("Lade " .. entry.file .. " ... ")
local body
body, err = get(entry.file)
if not body then say("Fehler: " .. tostring(err), colors.red) return end
if entry.size and #body ~= entry.size then
    say("unvollstaendig (" .. #body .. " von " .. entry.size .. " Bytes). Nochmal versuchen.", colors.red)
    return
end
if not load(body, "=gts", "t", {}) then say("Datei laeuft nicht - nochmal versuchen.", colors.red) return end
say(math.floor(#body / 1024) .. " KB ok", colors.lime)

-- 4) Als Startprogramm einrichten (vorhandenes startup wird ersetzt)
local target = (fs.exists("startup") and not fs.isDir("startup")) and "startup" or "startup.lua"
if fs.exists(target) then
    local h = fs.open(target, "r")
    local old = h and h.readAll() or ""
    if h then h.close() end
    if not old:find("GTS", 1, true) then
        if ask(target .. " ist kein GTS-Programm. Ersetzen? (j/n)", { j = true, n = false }) == false then
            say("Abgebrochen.", colors.orange)
            return
        end
    end
end
local free = fs.getFreeSpace("/")
local oldSize = fs.exists(target) and fs.getSize(target) or 0
if type(free) == "number" and free + oldSize < #body + 10000 then
    say("Zu wenig Speicher: " .. math.ceil((#body + 10000 - free - oldSize) / 1024) .. " KB fehlen.", colors.red)
    return
end
local f = fs.open(target, "wb")
f.write(body)
f.close()
if fs.getSize(target) ~= #body then say("Schreiben fehlgeschlagen.", colors.red) return end
say("Installiert als " .. target, colors.lime)

if edition == "turtle" then
    say("Turtle: nach dem Neustart P druecken und das", colors.yellow)
    say("Schwarm-Passwort vom PC eingeben.", colors.yellow)
    say("(Oder ganz einfach: DATEN > TURTLE-DISK am PC.)", colors.lightGray)
end
say("Neustart in 3 s ...")
sleep(3)
os.reboot()
