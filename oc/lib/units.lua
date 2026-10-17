-- ======================================================================
-- GTS OS (OpenComputers) - units: Drohnen und Robots im Schwarm
-- ======================================================================
-- Ablauf: Drohne/Robot/Knoten startet den GTS-Lader -> BOOT (gesiegelt) ->
-- das OS schickt das passende Programm in Teilen (CODE, je Teil gesiegelt)
-- -> das Programm meldet sich alle paar Sekunden (UP). Befehle gehen als
-- CMD mit laufender Nummer; die Einheit antwortet mit ACK. Ohne ACK nach
-- 4 s wird einmal wiederholt. Knoten: CALL -> RES (Geraete-Aufrufe), EV
-- (Ereignisse ihrer Geraete), grosse Nachrichten in Teilen (FR).
return function(K, S, N)
local computer = require("computer")
local component = require("component")
local fs = require("filesystem")
local U = { list = {}, byAddr = {}, events = {}, visitors = {}, seq = 0, pending = {} }
local DBFILE = K.ROOT .. "/data/einheiten.db"
local VISFILE = K.ROOT .. "/data/besucher.db"
local db = S.load(DBFILE, { units = {}, groups = {}, points = {} })
db.units, db.groups, db.points = db.units or {}, db.groups or {}, db.points or {}
-- Ladestationen in Weltkoordinaten (F3): { id, name, x, y, z }; Start der Drohne = 1 Block darueber
db.chargers = db.chargers or {}
db.recon = db.recon or { r = 32, h = 12, shape = "ring" }
U.db = db
U.visitors = S.load(VISFILE, {})
local CODE = {}
function U.save() S.save(DBFILE, db) end

-- Programme aus /gts/units laden (Pruefsumme fuer den Lader)
local function hexHash(s) return K.Cr.sha256hex(s) end
local function readFile(path)
    local h = io.open(path, "r")
    if not h then return nil end
    local code = h:read("*a")
    h:close()
    return code
end
function U.program(kind)
    local code = readFile(K.ROOT .. "/units/" .. kind .. ".lua")
    if not code then return nil end
    if kind == "node" then
        -- Knoten: ops (Aufrufe, Regeln) und crypto (SHA-256 in Lua) davor
        local ops, cr = readFile(K.ROOT .. "/lib/ops.lua"), readFile(K.ROOT .. "/lib/crypto.lua")
        if not ops or not cr then return nil end
        code = "local O = (function()\n" .. ops .. "\nend)()\nlocal Cr = (function()\n" .. cr .. "\nend)()()\n" .. code
    end
    if not CODE[kind] or CODE[kind].code ~= code then CODE[kind] = { code = code, hash = hexHash(code) } end
    return CODE[kind]
end

U.KIND = { drone = "Drohne", robot = "Robot", node = "Knoten", mc = "Knoten" }
local function progFor(kind) return (kind == "robot" and "robot") or ((kind == "node" or kind == "mc") and "node") or "drone" end
U.progFor = progFor
local function unit(addr)
    local u = U.byAddr[addr]
    if not u then
        local saved = db.units[addr] or {}
        u = { addr = addr, name = saved.name, color = saved.color or 0x3DDC84, group = saved.group, kind = saved.kind,
              online = false, seen = 0, log = {}, created = saved.created, charger = saved.charger }
        U.byAddr[addr] = u
        U.list[#U.list + 1] = u
    end
    return u
end
U.unit = unit
function U.remember(u)
    db.units[u.addr] = { name = u.name, color = u.color, group = u.group, kind = u.kind, created = u.created or K.realMs(),
                         charger = u.charger }
    U.save()
end
function U.label(u) return u.name or ((U.KIND[u.kind] or "Einheit") .. " " .. u.addr:sub(1, 4)) end
local function ulog(u, text)
    table.insert(u.log, 1, { c = K.clock(), text = text })
    while #u.log > 20 do table.remove(u.log) end
end
U.ulog = ulog
-- Ereignis fuer die KI (Autopilot): fn(u, art, text)
local function hook(u, what, text)
    if K.onUnit then pcall(K.onUnit, u, what, text) end
end

-- Programm schicken (in Teilen zu 1000 Zeichen: jeder Teil wird auf der
-- Gegenseite mit der Data Card geprueft, und die kostet Strom je Byte)
function U.push(addr, kind)
    local p = U.program(kind)
    if not p then K.notify("Programm für " .. kind .. " fehlt", "bad") return false end
    local parts = {}
    for i = 1, #p.code, 1000 do parts[#parts + 1] = p.code:sub(i, i + 999) end
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
U.frag = {}
U.onNode = {}          -- Knoten-Nachrichten fuer dev.lua: fn(u, m)
local onMsg
local function reassemble(from, m, dist, mode)
    local key = from .. "|" .. tostring(m.id)
    local f = U.frag[key] or { n = 0, t = computer.uptime() }
    U.frag[key] = f
    if type(m.n) ~= "number" or type(m.of) ~= "number" or m.of > 64 then U.frag[key] = nil return end
    if not f[m.n] then f[m.n] = tostring(m.d or "") f.n = f.n + 1 end
    if f.n < m.of then return end
    U.frag[key] = nil
    local inner = N.unser(table.concat(f, "", 1, m.of))
    if type(inner) == "table" and inner.t ~= "FR" then onMsg(from, inner, dist, mode) end
end
onMsg = function(from, m, dist, mode)
    if m.t == "FR" then return reassemble(from, m, dist, mode) end
    local u = unit(from)
    if m.t == "RES" or (m.t == "EV" and (m.ev == "sig" or m.ev == "rule")) or (m.t == "UP" and m.kind == "node") then
        u.seen = computer.uptime()
        for _, fn in ipairs(U.onNode) do
            local ok, err = pcall(fn, u, m, dist, mode)
            if not ok then K.log("FEHLER", "Knoten: " .. tostring(err)) end
        end
        if m.t ~= "UP" then return end
    end
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
        U.push(from, progFor(u.kind))
    elseif m.t == "UP" then
        local wasOff = not u.online
        u.online, u.seen, u.dist, u.secure = true, computer.uptime(), dist, mode == "E"
        u.kind = m.kind or u.kind
        u.e, u.x, u.y, u.z, u.f = m.e, m.x, m.y, m.z, m.f
        u.task, u.st, u.v = m.task, m.st, m.v
        u.nav, u.ms, u.cl, u.geo = m.nav, m.ms, m.cl, m.geo
        u.inv, u.invMax, u.tool, u.mined, u.charging = m.inv, m.invMax, m.tool, m.mined, m.charging
        u.recon, u.ch = m.recon, m.ch
        u.mem, u.tot, u.inet = m.mem, m.tot, m.inet
        u.aes = m.aes == true
        if m.name and not u.name then u.name = m.name end
        u.hist = u.hist or {}
        u.hist[#u.hist + 1] = m.e or 0
        while #u.hist > 120 do table.remove(u.hist, 1) end
        if wasOff then ulog(u, "wieder online") end
        if u.kind ~= "node" and (m.e or 1) < 0.15 and not u.lowWarned then
            u.lowWarned = true
            K.notify(U.label(u) .. ": Akku " .. math.floor((m.e or 0) * 100) .. " %", "warn", "drones")
            hook(u, "akku", U.label(u) .. " hat nur noch " .. math.floor((m.e or 0) * 100) .. " % Akku")
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
        hook(u, "fertig", U.label(u) .. " hat den Auftrag " .. tostring(m.task) .. " beendet" .. (m.st and (" - Status: " .. tostring(m.st)) or "") .. (m.mined and m.mined > 0 and (" (" .. m.mined .. " Blöcke abgebaut)") or ""))
        K.dirty = true
    elseif m.t == "EV" then
        u.seen = computer.uptime()
        if m.ev == "motion" then
            local name = tostring(m.name or "?"):sub(1, 32)
            local v = { name = name, unit = U.label(u), x = m.x, y = m.y, z = m.z, t = K.realMs(), clock = K.clock() }
            table.insert(U.visitors, 1, v)
            while #U.visitors > 200 do table.remove(U.visitors) end
            U.visDirty = true
            local wx, wy, wz = U.toWorld(u, m.x, m.y, m.z)
            if wx then v.wx, v.wy, v.wz = wx, wy, wz end
            local trusted = (name == K.set.owner)
            for _, t in ipairs(K.set.trusted or {}) do if t:lower() == name:lower() then trusted = true end end
            if K.sec then
                -- SICHERHEIT entscheidet (Personen, Abwehr)
                if not K.sec.trusted(name) then K.sec.intruder(name, U.label(u), wx and { x = wx, y = wy, z = wz } or nil) end
            elseif not trusted and name ~= "?" and not name:match("^entity%.") then
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
            hook(u, "blockiert", U.label(u) .. " ist blockiert (Position relativ " .. tostring(m.x) .. " " .. tostring(m.y) .. " " .. tostring(m.z) .. ")")
        elseif m.ev == "scan" then
            u.scan = m.hits
            ulog(u, "Scan: " .. #(m.hits or {}) .. " Treffer")
            K.notify(U.label(u) .. ": Scan fertig (" .. #(m.hits or {}) .. ")", "ok", "drones")
            hook(u, "scan", U.label(u) .. ": Scan fertig, " .. #(m.hits or {}) .. " Treffer (Werkzeug scan_result)")
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
                if not U.isNode(u) then hook(u, "offline", U.label(u) .. " ist offline (Akku leer, zerstört oder außer Reichweite?)") end
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
        for k, f in pairs(U.frag) do if now - f.t > 20 then U.frag[k] = nil end end
        pcall(chargeCheck, now)
    end
end

-- online: Einheiten (Drohnen + Robots), Drohnen, Robots, Knoten
function U.online()
    local n, d, r, k = 0, 0, 0, 0
    for _, u in ipairs(U.list) do
        if u.online then
            if u.kind == "node" or u.kind == "mc" then k = k + 1
            else n = n + 1 if u.kind == "robot" then r = r + 1 else d = d + 1 end end
        end
    end
    return n, d, r, k
end
function U.isNode(u) return u.kind == "node" or u.kind == "mc" end
-- nur Drohnen und Robots (ohne Knoten)
function U.fleet()
    local out = {}
    for _, u in ipairs(U.list) do if not U.isNode(u) then out[#out + 1] = u end end
    return out
end
function U.nodes()
    local out = {}
    for _, u in ipairs(U.list) do if U.isNode(u) and not u.waiting then out[#out + 1] = u end end
    return out
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
    U.push(addr, progFor(u.kind))
end

-- Ladestationen und Weltkoordinaten ---------------------------------------------
function U.addCharger(name, x, y, z)
    local id = 1
    for _, c in ipairs(db.chargers) do if c.id >= id then id = c.id + 1 end end
    db.chargers[#db.chargers + 1] = { id = id, name = name, x = x, y = y, z = z }
    U.save()
    return id
end
function U.charger(id) for _, c in ipairs(db.chargers) do if c.id == id then return c end end end
-- Startplatz einer Drohne in Weltkoordinaten (oder nil, wenn unbekannt)
function U.homeOf(u)
    if u.kind == "robot" or U.isNode(u) then return nil end
    local c = u.charger and U.charger(u.charger)
    if not c and #db.chargers == 1 then c = db.chargers[1] end
    if not c then return nil end
    return { x = c.x, y = c.y + 1, z = c.z }
end
function U.toWorld(u, x, y, z)
    local h = U.homeOf(u)
    x, y, z = x or u.x, y or u.y, z or u.z
    if not h or x == nil then return nil end
    return math.floor(h.x + x + 0.5), math.floor(h.y + y + 0.5), math.floor(h.z + z + 0.5)
end
function U.toLocal(u, wx, wy, wz)
    local h = U.homeOf(u)
    if not h then return nil end
    return math.floor(wx - h.x + 0.5), math.floor(wy - h.y + 0.5), math.floor(wz - h.z + 0.5)
end
-- Mitte der Basis (fuer Karte und Aufklaerung): eigene Angabe, sonst erste Ladestation
function U.base()
    if db.base then return db.base end
    local c = db.chargers[1]
    if c then return { x = c.x, y = c.y, z = c.z } end
end
function U.worldMode() return U.base() ~= nil end

-- Aufklaerung: Rundweg um die Basis (Weltkoordinaten), auf die Drohnen verteilt
function U.reconRoute(r, h, shape)
    local b = U.base()
    if not b then return nil end
    local pts = {}
    local y = b.y + (h or 12)
    if shape == "rechteck" then
        local step = math.max(8, math.floor(r / 2))
        for x = -r, r - 1, step do pts[#pts + 1] = { x = b.x + x, y = y, z = b.z - r } end
        for z = -r, r - 1, step do pts[#pts + 1] = { x = b.x + r, y = y, z = b.z + z } end
        for x = r, -r + 1, -step do pts[#pts + 1] = { x = b.x + x, y = y, z = b.z + r } end
        for z = r, -r + 1, -step do pts[#pts + 1] = { x = b.x - r, y = y, z = b.z + z } end
    else
        local n = math.max(8, math.ceil(2 * math.pi * r / 12))
        for i = 0, n - 1 do
            local a = i / n * 2 * math.pi
            pts[#pts + 1] = { x = math.floor(b.x + math.cos(a) * r + 0.5), y = y, z = math.floor(b.z + math.sin(a) * r + 0.5) }
        end
    end
    return pts
end
function U.startRecon(list, r, h, shape)
    local pts = U.reconRoute(r, h, shape)
    if not pts then return 0, "Erst eine Ladestation eintragen (Weltkoordinaten)" end
    db.recon = { r = r, h = h, shape = shape }
    U.save()
    local drones = {}
    for _, u in ipairs(list) do if u.online and u.kind == "drone" and U.homeOf(u) then drones[#drones + 1] = u end end
    if #drones == 0 then return 0, "Keine Drohne online mit bekannter Ladestation" end
    for k, u in ipairs(drones) do
        local loc = {}
        for i, p in ipairs(pts) do local x, y, z = U.toLocal(u, p.x, p.y, p.z) loc[i] = { x = x, y = y, z = z } end
        -- gleichmaessig verteilt starten
        local start = math.floor((k - 1) * #pts / #drones) + 1
        U.cmd(u.addr, "recon", { points = loc, start = start }, "Aufklärung r=" .. r)
    end
    K.log("INFO", "Aufklärung gestartet: " .. #drones .. " Drohne(n), Radius " .. r)
    return #drones
end

-- Akku knapp: naechste freie Ladestation vorgeben (bei mehreren Stationen)
local function chargeCheck(now)
    if #db.chargers < 2 then return end
    for _, u in ipairs(U.list) do
        if u.online and u.kind == "drone" and u.e and not u.charging and u.task ~= "charge"
           and u.e < ((K.set.homeAt or 25) + 8) / 100 and now - (u.chargeCmd or -1e9) > 60 then
            local wx, wy, wz = U.toWorld(u)
            if wx then
                local taken = {}
                for _, o in ipairs(U.list) do if o ~= u and o.chargeAt and (o.task == "charge" or o.charging) then taken[o.chargeAt] = true end end
                local best, bd
                for _, c in ipairs(db.chargers) do
                    if not taken[c.id] then
                        local d = (c.x - wx) ^ 2 + (c.y + 1 - wy) ^ 2 + (c.z - wz) ^ 2
                        if not bd or d < bd then best, bd = c, d end
                    end
                end
                if best then
                    local x, y, z = U.toLocal(u, best.x, best.y + 1, best.z)
                    u.chargeCmd, u.chargeAt = now, best.id
                    U.cmd(u.addr, "charge", { x = x, y = y, z = z }, "laden an " .. best.name)
                end
            end
        end
    end
end

-- Wegpunkte (eigene, relativ zum Startplatz der Einheiten)
function U.addPoint(name, x, y, z)
    db.points[#db.points + 1] = { name = name, x = x, y = y, z = z }
    U.save()
end

-- EEPROM fuer Drohnen schreiben (Lader + Schluessel). Die EEPROM im PC
-- wird ueberschrieben - vorher eine leere einsetzen!
function U.flash(name, kind)
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
    ee.setLabel((kind == "node" and "GTS Knoten" or "GTS Drohne") .. ((name and name ~= "") and (" " .. name) or ""))
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
