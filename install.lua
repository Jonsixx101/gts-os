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
    edition = ask("Welche?", { ["1"] = "pocket", ["2"] = "phone" })
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
