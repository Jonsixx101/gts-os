-- ======================================================================
-- GTS OS (OpenComputers) - units: Drohnen und Robots im Schwarm
-- ======================================================================
-- Ablauf: Drohne/Robot startet den GTS-Lader -> BOOT (gesiegelt) -> das OS
-- schickt das passende Programm in Teilen (CODE, mit SHA-256) -> das
-- Programm meldet sich alle paar Sekunden (UP). Befehle gehen als CMD mit
-- laufender Nummer; die Einheit antwortet mit ACK. Ohne ACK nach 4 s wird
-- einmal wiederholt.
return function(K, S, N)
local computer = require("computer")
local component = require("component")
local fs = require("filesystem")
local U = { list = {}, byAddr = {}, events = {}, visitors = {}, seq = 0, pending = {} }
local DBFILE = K.ROOT .. "/data/einheiten.db"
local VISFILE = K.ROOT .. "/data/besucher.db"
local db = S.load(DBFILE, { units = {}, groups = {}, points = {} })
db.units, db.groups, db.points = db.units or {}, db.groups or {}, db.points or {}
U.db = db
U.visitors = S.load(VISFILE, {})
local CODE = {}
function U.save() S.save(DBFILE, db) end

-- Programme aus /gts/units laden (Pruefsumme fuer den Lader)
local function hexHash(s)
    local d = N.data
    if not d then return "" end
    return N.hex(d.sha256(s))
end
function U.program(kind)
    local file = K.ROOT .. "/units/" .. kind .. ".lua"
    local h = io.open(file, "r")
    if not h then return nil end
    local code = h:read("*a")
    h:close()
    if not CODE[kind] or CODE[kind].code ~= code then CODE[kind] = { code = code, hash = hexHash(code) } end
    return CODE[kind]
end

U.KIND = { drone = "Drohne", robot = "Robot", mc = "Mikrocontroller" }
local function unit(addr)
    local u = U.byAddr[addr]
    if not u then
        local saved = db.units[addr] or {}
        u = { addr = addr, name = saved.name, color = saved.color or 0x3DDC84, group = saved.group, kind = saved.kind,
              online = false, seen = 0, log = {}, created = saved.created }
        U.byAddr[addr] = u
        U.list[#U.list + 1] = u
    end
    return u
end
U.unit = unit
function U.remember(u)
    db.units[u.addr] = { name = u.name, color = u.color, group = u.group, kind = u.kind, created = u.created or K.realMs() }
    U.save()
end
function U.label(u) return u.name or ((U.KIND[u.kind] or "Einheit") .. " " .. u.addr:sub(1, 4)) end
local function ulog(u, text)
    table.insert(u.log, 1, { c = K.clock(), text = text })
    while #u.log > 20 do table.remove(u.log) end
end
U.ulog = ulog

-- Programm schicken (in Teilen zu 4000 Zeichen)
function U.push(addr, kind)
    local p = U.program(kind)
    if not p then K.notify("Programm für " .. kind .. " fehlt", "bad") return false end
    local parts = {}
    for i = 1, #p.code, 4000 do parts[#parts + 1] = p.code:sub(i, i + 3999) end
    for i, d in ipairs(parts) do
        N.send(addr, { t = "CODE", n = i, of = #parts, h = p.hash, d = d, aes = N.aes })
    end
    return true
end

-- Befehl an eine Einheit
function U.cmd(addr, cmd, args, label)
    local u = U.byAddr[addr]
    if not u or not u.online then K.notify((u and U.label(u) or "Einheit") .. " ist nicht erreichbar", "warn") return false end
    U.seq = U.seq + 1
    local msg = { t = "CMD", seq = U.seq, cmd = cmd, args = args or {}, aes = N.aes }
    U.pending[U.seq] = { addr = addr, msg = msg, t = computer.uptime(), tries = 1, label = label or cmd }
    N.send(addr, msg)
    u.busy = label or cmd
    ulog(u, "Befehl: " .. (label or cmd))
    K.dirty = true
    return true
end
function U.cmdMany(list, cmd, argsFn, label)
    local n = 0
    for _, u in ipairs(list) do
        if u.online and U.cmd(u.addr, cmd, argsFn and argsFn(u) or {}, label) then n = n + 1 end
    end
    return n
end

-- Empfang
local function onMsg(from, m, dist, mode)
    local u = unit(from)
    if m.t == "BOOT" then
        u.kind = m.kind or u.kind or "drone"
        u.caps = m.caps or {}
        u.aes = m.aes == true
        u.booted = computer.uptime()
        u.online = true
        u.seen = computer.uptime()
        u.e = m.energy
        u.dist = dist
        if not u.created then u.created = K.realMs() end
        if not db.units[from] and not K.set.autoAccept then
            u.waiting = true
            K.notify("Neue " .. (U.KIND[u.kind] or "Einheit") .. " wartet auf Freigabe", "warn", "drones")
            return
        end
        if not db.units[from] then
            if m.name and m.name ~= "" then u.name = m.name end
            K.notify((U.KIND[u.kind] or "Einheit") .. " " .. U.label(u) .. " ist neu im Schwarm", "ok", "drones")
        end
        U.remember(u)
        ulog(u, "gestartet, Programm wird gesendet")
        U.push(from, u.kind == "robot" and "robot" or "drone")
    elseif m.t == "UP" then
        local wasOff = not u.online
        u.online, u.seen, u.dist, u.secure = true, computer.uptime(), dist, mode == "E"
        u.kind = m.kind or u.kind
        u.e, u.x, u.y, u.z, u.f = m.e, m.x, m.y, m.z, m.f
        u.task, u.st, u.v = m.task, m.st, m.v
        u.nav, u.ms, u.cl, u.geo = m.nav, m.ms, m.cl, m.geo
        u.inv, u.invMax, u.tool, u.mined, u.charging = m.inv, m.invMax, m.tool, m.mined, m.charging
        u.aes = m.aes == true
        if m.name and not u.name then u.name = m.name end
        u.hist = u.hist or {}
        u.hist[#u.hist + 1] = m.e or 0
        while #u.hist > 120 do table.remove(u.hist, 1) end
        if wasOff then ulog(u, "wieder online") end
        if (m.e or 1) < 0.15 and not u.lowWarned then
            u.lowWarned = true
            K.notify(U.label(u) .. ": Akku " .. math.floor((m.e or 0) * 100) .. " %", "warn", "drones")
        elseif (m.e or 0) > 0.5 then u.lowWarned = false end
        K.dirty = true
    elseif m.t == "ACK" then
        local p = U.pending[m.seq]
        U.pending[m.seq] = nil
        u.busy = nil
        if p and not m.ok then
            K.notify(U.label(u) .. ": " .. tostring(m.msg or "abgelehnt"), "warn", "drones")
            ulog(u, "abgelehnt: " .. tostring(m.msg))
        end
        K.dirty = true
    elseif m.t == "DONE" then
        ulog(u, "fertig: " .. tostring(m.task))
        if m.task ~= "goto" and m.task ~= "home" then K.notify(U.label(u) .. ": " .. tostring(m.task) .. " fertig", "ok", "drones") end
        K.dirty = true
    elseif m.t == "EV" then
        u.seen = computer.uptime()
        if m.ev == "motion" then
            local name = tostring(m.name or "?"):sub(1, 32)
            local v = { name = name, unit = U.label(u), x = m.x, y = m.y, z = m.z, t = K.realMs(), clock = K.clock() }
            table.insert(U.visitors, 1, v)
            while #U.visitors > 200 do table.remove(U.visitors) end
            U.visDirty = true
            local trusted = (name == K.set.owner)
            for _, t in ipairs(K.set.trusted or {}) do if t:lower() == name:lower() then trusted = true end end
            if not trusted and name ~= "?" and not name:match("^entity%.") then
                local last = U.alerted and U.alerted[name]
                U.alerted = U.alerted or {}
                if not last or computer.uptime() - last > 120 then
                    U.alerted[name] = computer.uptime()
                    K.notify(name .. " gesehen von " .. U.label(u), "warn", "drones")
                    K.log("WARN", "Besucher: " .. name .. " (" .. U.label(u) .. ")")
                end
            end
        elseif m.ev == "blocked" then
            K.notify(U.label(u) .. " ist blockiert", "warn", "drones")
            ulog(u, "blockiert bei " .. tostring(m.x) .. "," .. tostring(m.y) .. "," .. tostring(m.z))
        elseif m.ev == "scan" then
            u.scan = m.hits
            ulog(u, "Scan: " .. #(m.hits or {}) .. " Treffer")
            K.notify(U.label(u) .. ": Scan fertig (" .. #(m.hits or {}) .. ")", "ok", "drones")
        elseif m.ev == "progress" then
            u.progress = { layer = m.layer, of = m.of, mined = m.mined }
        end
        K.dirty = true
    end
end
N.on(onMsg)

-- Dienst: offline erkennen, Befehle wiederholen, Besucher sichern
function U.service()
    while true do
        K.sleep(1)
        local now = computer.uptime()
        for _, u in ipairs(U.list) do
            local hb = (K.set.heartbeat or 5) * 3 + 2
            if u.online and now - u.seen > hb then
                u.online = false
                ulog(u, "offline")
                K.dirty = true
            end
        end
        for seq, p in pairs(U.pending) do
            if now - p.t > 4 then
                if p.tries < 2 then
                    p.tries, p.t = p.tries + 1, now
                    N.send(p.addr, p.msg)
                else
                    U.pending[seq] = nil
                    local u = U.byAddr[p.addr]
                    if u then u.busy = nil ulog(u, "keine Antwort: " .. p.label) end
                    K.notify((u and U.label(u) or "Einheit") .. ": keine Antwort", "warn", "drones")
                end
            end
        end
        if U.visDirty then U.visDirty = false S.save(VISFILE, U.visitors) end
    end
end

function U.online()
    local n, d, r = 0, 0, 0
    for _, u in ipairs(U.list) do
        if u.online then n = n + 1 if u.kind == "robot" then r = r + 1 else d = d + 1 end end
    end
    return n, d, r
end
function U.forget(addr)
    local u = U.byAddr[addr]
    db.units[addr] = nil
    U.byAddr[addr] = nil
    for i, x in ipairs(U.list) do if x == u then table.remove(U.list, i) break end end
    U.save()
end
function U.accept(addr)
    local u = U.byAddr[addr]
    if not u then return end
    u.waiting = nil
    U.remember(u)
    U.push(addr, u.kind == "robot" and "robot" or "drone")
end

-- Wegpunkte (eigene, relativ zum Startplatz der Einheiten)
function U.addPoint(name, x, y, z)
    db.points[#db.points + 1] = { name = name, x = x, y = y, z = z }
    U.save()
end

-- EEPROM fuer Drohnen schreiben (Lader + Schluessel). Die EEPROM im PC
-- wird ueberschrieben - vorher eine leere einsetzen!
function U.flash(name)
    if not component.isAvailable("eeprom") then return false, "keine EEPROM im Rechner" end
    local ee = component.eeprom
    local h = io.open(K.ROOT .. "/units/loader.min.lua", "r") or io.open(K.ROOT .. "/units/loader.lua", "r")
    if not h then return false, "Lader fehlt" end
    local code = h:read("*a")
    h:close()
    if #code > 4096 then return false, "Lader zu groß (" .. #code .. ")" end
    if not N.keyHex() then return false, "kein Schlüssel (Data Card?)" end
    local data = "GTS1|" .. N.keyHex() .. "|" .. tostring(N.port) .. "|" .. tostring(name or ""):sub(1, 16)
    local ok, err = ee.set(code)
    if not ok and err then return false, tostring(err) end
    ee.setData(data)
    ee.setLabel("GTS Drohne" .. ((name and name ~= "") and (" " .. name) or ""))
    K.log("INFO", "EEPROM geschrieben: " .. tostring(name))
    return true
end
-- Lua BIOS zurueckschreiben (falls versehentlich die BIOS-EEPROM beschrieben wurde)
function U.restoreBios()
    if not component.isAvailable("eeprom") then return false, "keine EEPROM" end
    local h = io.open(K.ROOT .. "/units/bios.lua", "r")
    if not h then return false, "BIOS-Datei fehlt" end
    local code = h:read("*a")
    h:close()
    local ee = component.eeprom
    ee.set(code)
    ee.setData("")
    ee.setLabel("EEPROM (Lua BIOS)")
    return true
end
function U.isBios()
    if not component.isAvailable("eeprom") then return false end
    local l = component.eeprom.getLabel() or ""
    return l:find("BIOS", 1, true) ~= nil
end
-- Robot-Konfiguration (Datei auf der Festplatte des Robots, per Installer)
function U.unitCfg(name)
    return "GTS1|" .. (N.keyHex() or "") .. "|" .. tostring(N.port) .. "|" .. tostring(name or "")
end

return U
end
