-- ======================================================================
-- GTS OS (OpenComputers) - secu: Zugang, Tueren, Melder, Redstone, Alarm
-- ======================================================================
-- Laeuft immer im Hintergrund (auch ohne offene App):
--  * Kartenleser (Mag/RFID), Biometrie und Tastenfelder -> Person pruefen
--    -> Tuer auf, nach ein paar Sekunden wieder zu
--  * Melder (Entity Detector) scannen regelmaessig nach Spielern; Fremde
--    werden gemeldet. Ist die ABWEHR scharf, loest GTS OS die gewaehlten
--    Massnahmen aus: Alarm, Redstone-Ausgaenge (z.B. Fallen), Abriegeln,
--    eine Drohne zum Beobachten hinschicken. Keine Waffen.
return function(K, S, D)
local computer = require("computer")
local Sec = { log = {}, closeAt = {}, pins = {}, enroll = nil, seen = {}, alarmOn = false }
local DB = K.ROOT .. "/data/sicherheit.db"
local LOG = K.ROOT .. "/data/sicherheit.log"
local db = S.load(DB, {})
db.people = db.people or {}
db.doors = db.doors or {}
db.outputs = db.outputs or {}
db.sensors = db.sensors or {}
db.guard = db.guard or { on = false, alarm = true, lock = false, outs = {}, drone = false, alarmMin = 2 }
db.n = db.n or 0
Sec.db = db
function Sec.save() S.save(DB, db) end
local function newId() db.n = db.n + 1 return db.n end
Sec.newId = newId

-- Protokoll ---------------------------------------------------------------
function Sec.note(level, text)
    local e = { clock = K.clock(), level = level, text = text }
    table.insert(Sec.log, 1, e)
    while #Sec.log > 80 do table.remove(Sec.log) end
    pcall(function()
        local fs = require("filesystem")
        if fs.exists(LOG) and fs.size(LOG) > 16000 then
            if fs.exists(LOG .. ".alt") then fs.remove(LOG .. ".alt") end
            fs.rename(LOG, LOG .. ".alt")
        end
        local h = io.open(LOG, "a")
        if h then h:write(K.clock() .. " " .. level .. " " .. text .. "\n") h:close() end
    end)
    K.dirty = true
end

-- Personen ------------------------------------------------------------------
local function byId(list, id) for i, x in ipairs(list) do if x.id == id then return x, i end end end
Sec.byId = byId
function Sec.person(id) return byId(db.people, id) end
function Sec.addPerson(name, admin)
    local p = { id = newId(), name = tostring(name):sub(1, 24), admin = admin == true, cards = {}, bio = {}, zones = "alle" }
    db.people[#db.people + 1] = p
    Sec.save()
    return p
end
function Sec.trusted(name)
    if not name or name == "" then return false end
    local n = tostring(name):lower()
    if n == tostring(K.set.owner or ""):lower() then return true end
    for _, t in ipairs(K.set.trusted or {}) do if t:lower() == n then return true end end
    for _, p in ipairs(db.people) do if p.name:lower() == n then return true end end
    return false
end
local function mayEnter(p, door)
    if not p then return false end
    if p.blocked then return false end
    if db.lockdown and not p.admin then return false end
    if p.zones == "alle" or not door or not door.zone then return true end
    return type(p.zones) == "table" and p.zones[door.zone] == true
end
Sec.mayEnter = mayEnter

-- Tueren und Ausgaenge --------------------------------------------------------
-- Tuer: { id, name, dev (os_door oder Redstone-Ausgang-Id), kind = "os"|"rs", readers = { addr = true }, open = s, zone, pw }
-- Ausgang: { id, name, dev (redstone), side 0-5, color (nil = normal, 0-15 = Bundled), mode "schalter"|"puls", pulse s, on }
function Sec.setOutput(o, on, why)
    if type(o) == "number" then o = byId(db.outputs, o) end
    if not o then return false, "Ausgang fehlt" end
    local v = on and 15 or 0
    if o.inv then v = 15 - v end
    local res
    if o.color then res = D.call(o.dev, "setBundledOutput", { o.side or 1, o.color, on and 255 or 0 })
    else res = D.call(o.dev, "setOutput", { o.side or 1, v }) end
    o.on = on
    Sec.note("info", o.name .. (on and " an" or " aus") .. (why and (" (" .. why .. ")") or ""))
    return res == nil or res[1] ~= false
end
function Sec.pulse(o, why)
    if type(o) == "number" then o = byId(db.outputs, o) end
    if not o then return false end
    Sec.setOutput(o, true, why or "Puls")
    Sec.closeAt[#Sec.closeAt + 1] = { t = computer.uptime() + (o.pulse or 1), out = o.id }
    return true
end
function Sec.trigger(o, why)
    if type(o) == "number" then o = byId(db.outputs, o) end
    if not o then return false end
    if o.mode == "puls" then return Sec.pulse(o, why) end
    return Sec.setOutput(o, not o.on, why)
end
function Sec.doorSet(d, open, who)
    if type(d) == "number" then d = byId(db.doors, d) end
    if not d then return false, "Tür fehlt" end
    if d.kind == "rs" then
        Sec.setOutput(tonumber(d.dev), open, d.name)
    else
        D.call(d.dev, open and "open" or "close", d.pw and { d.pw } or {}, function(r)
            if r and r[1] == true and r[2] == false then Sec.note("warn", d.name .. ": " .. tostring(r[3] or "abgelehnt")) end
        end)
    end
    d.isOpen = open
    if open then
        Sec.note("ok", d.name .. " geöffnet" .. (who and (" für " .. who) or ""))
        if (d.open or 4) > 0 then Sec.closeAt[#Sec.closeAt + 1] = { t = computer.uptime() + (d.open or 4), door = d.id } end
    else
        Sec.note("info", d.name .. " geschlossen")
    end
    K.dirty = true
    return true
end

-- Alarm und Abriegeln -------------------------------------------------------
function Sec.alarm(on, why)
    for _, e in ipairs(D.of("sicherheit", "^os_alarm$")) do
        if on and db.alarmSound then D.call(e.addr, "setAlarm", { db.alarmSound }) end
        D.call(e.addr, on and "activate" or "deactivate", {})
    end
    Sec.alarmOn = on
    Sec.alarmUntil = on and (computer.uptime() + (db.guard.alarmMin or 2) * 60) or nil
    Sec.note(on and "bad" or "info", "Alarm " .. (on and "AN" or "aus") .. (why and (" - " .. why) or ""))
    K.dirty = true
end
function Sec.lockdown(on, why)
    db.lockdown = on
    Sec.save()
    if on then for _, d in ipairs(db.doors) do Sec.doorSet(d, false) end end
    for _, o in ipairs(db.outputs) do if o.lock then Sec.setOutput(o, on, "Abriegeln") end end
    for _, e in ipairs(D.of("sicherheit", "^os_keypad$")) do D.call(e.addr, "setDisplay", { on and "GESPERRT" or "", on and 4 or 7 }) end
    Sec.note(on and "bad" or "ok", on and ("ABGERIEGELT" .. (why and (" - " .. why) or "")) or "Abriegeln aufgehoben")
    K.notify(on and "Basis abgeriegelt" or "Abriegeln aufgehoben", on and "warn" or "ok", "security")
end

-- Fremde ------------------------------------------------------------------
-- von Meldern und von den Bewegungssensoren der Drohnen
function Sec.intruder(name, where, pos)
    if Sec.trusted(name) or name == "?" or tostring(name):match("^entity%.") then return end
    local now = computer.uptime()
    if Sec.seen[name] and now - Sec.seen[name] < 90 then return end
    Sec.seen[name] = now
    local g = db.guard
    Sec.note("bad", "Fremder: " .. name .. " (" .. tostring(where) .. ")")
    K.log("WARN", "Fremder: " .. name .. " bei " .. tostring(where))
    if not g.on then
        K.notify(name .. " gesehen (" .. tostring(where) .. ")", "warn", "security")
        return
    end
    K.notify("ABWEHR: " .. name .. " bei " .. tostring(where), "bad", "security")
    if g.alarm then Sec.alarm(true, name) end
    if g.lock and not db.lockdown then Sec.lockdown(true, name) end
    for id, on in pairs(g.outs or {}) do if on then Sec.trigger(id, "Abwehr: " .. name) end end
    if g.drone and pos and K.units and K.units.toLocal then
        -- eine freie Drohne zum Beobachten hinschicken (Kamera-Rolle, keine Waffe);
        -- pos ist in Weltkoordinaten, die Drohne braucht ihre eigenen
        for _, u in ipairs(K.units.fleet()) do
            if u.online and u.kind == "drone" and (u.e or 0) > 0.4 and (u.task == "idle" or u.task == "recon" or not u.task) then
                local x, y, z = K.units.toLocal(u, pos.x, pos.y + 4, pos.z)
                if x then
                    K.units.cmd(u.addr, "goto", { x = x, y = y, z = z }, "beobachten: " .. name)
                    break
                end
            end
        end
    end
    if K.onIntruder then pcall(K.onIntruder, name, where) end
end

-- Leser ---------------------------------------------------------------------
local function doorsFor(reader)
    local out = {}
    for _, d in ipairs(db.doors) do if d.readers and d.readers[reader] then out[#out + 1] = d end end
    return out
end
local function grant(reader, p, how)
    local doors = doorsFor(reader)
    if #doors == 0 then Sec.note("info", (p and p.name or "?") .. " am Leser " .. D.label(reader) .. " (keine Tür verknüpft)") return end
    for _, d in ipairs(doors) do
        if mayEnter(p, d) then Sec.doorSet(d, true, p.name .. " · " .. how)
        else
            Sec.note("warn", "Zutritt verweigert: " .. (p and p.name or "unbekannt") .. " an " .. d.name .. " (" .. how .. ")")
            if not p then K.notify("Unbekannte Karte an " .. d.name, "warn", "security") end
        end
    end
end
local function personByToken(data, uuid)
    if type(data) ~= "string" then return nil end
    local tok = data:match("^GTS:(%w+)$")
    if not tok then return nil end
    for _, p in ipairs(db.people) do
        local bound = p.cards[tok]
        if bound ~= nil then
            -- erste Nutzung bindet die Karten-Kennung; eine andere Kennung = Kopie
            if bound == true and uuid and uuid ~= "-1" then p.cards[tok] = uuid Sec.save() return p end
            if bound == true or bound == uuid or uuid == "-1" or not uuid then return p end
            Sec.note("bad", "Kopierte Karte von " .. p.name .. "?")
            K.notify("Verdächtige Karte (Kopie von " .. p.name .. "?)", "bad", "security")
            return nil
        end
    end
end
local function enrollCard(kind, value)
    local e = Sec.enroll
    if not e or e.kind ~= kind or computer.uptime() > e.untilT then return false end
    local p = Sec.person(e.id)
    Sec.enroll = nil
    if not p then return false end
    if kind == "bio" then p.bio[#p.bio + 1] = value end
    Sec.save()
    Sec.note("ok", p.name .. ": " .. (kind == "bio" and "Biometrie angelernt" or "Karte angelernt"))
    K.notify(p.name .. ": angelernt", "ok", "security")
    return true
end
D.on("magData", function(addr, user, data, uuid)
    local p = personByToken(data, uuid)
    grant(addr, p, "Karte")
end)
D.on("rfidData", function(addr, name, range, data, uuid)
    local p = personByToken(data, uuid)
    if not p then return end
    local now = computer.uptime()
    if Sec.pins["rf" .. addr .. p.id] and now - Sec.pins["rf" .. addr .. p.id] < 8 then return end
    Sec.pins["rf" .. addr .. p.id] = now
    grant(addr, p, "RFID")
end)
D.on("bioReader", function(addr, uuid)
    if enrollCard("bio", uuid) then return end
    local who
    for _, p in ipairs(db.people) do for _, b in ipairs(p.bio) do if b == uuid then who = p end end end
    grant(addr, who, "Biometrie")
end)
D.on("keypad", function(addr, index, label)
    local buf = Sec.pins[addr] or ""
    label = tostring(label or "")
    if label == "*" then buf = ""
    elseif label == "#" then
        Sec.pins[addr] = ""
        local h = K.hash("pin|" .. buf)
        local who
        for _, p in ipairs(db.people) do if p.pin == h then who = p end end
        D.call(addr, "setDisplay", { who and "OK" or "FALSCH", who and 2 or 4 })
        grant(addr, who, "PIN")
        Sec.resetPad = Sec.resetPad or {}
        Sec.resetPad[addr] = computer.uptime() + 2
        return
    elseif label:match("^%d$") and #buf < 8 then buf = buf .. label end
    Sec.pins[addr] = buf
    D.call(addr, "setDisplay", { string.rep("*", #buf), 7 })
end)
-- Melder-Ereignisse kommen auch als Signal (bei jedem Scan); ausgewertet wird das Scan-Ergebnis

-- Karten ausstellen -----------------------------------------------------------
function Sec.issueCard(p, writer, cb)
    local tok = K.Cr.sha256hex(tostring(K.realMs()) .. tostring(math.random()) .. p.name .. tostring(computer.uptime())):sub(1, 16)
    D.call(writer, "write", { "GTS:" .. tok, "GTS " .. p.name, true, 5 }, function(r)
        local ok = r and r[1] and r[2] == true
        if ok then
            -- write liefert die Kennung der Karte: gleich binden (Kopien fallen auf)
            p.cards[tok] = type(r[3]) == "string" and r[3] ~= "" and r[3] or true
            Sec.save()
            Sec.note("ok", "Karte für " .. p.name .. " geschrieben")
        else
            Sec.note("warn", "Kartenschreiber: " .. tostring(r and (r[3] or r[2]) or "keine Antwort"))
        end
        if cb then cb(ok, r) end
    end)
end
function Sec.revokeCards(p) p.cards = {} Sec.save() Sec.note("warn", p.name .. ": alle Karten gesperrt") end
function Sec.setPin(p, pin) p.pin = pin and K.hash("pin|" .. pin) or nil Sec.save() end

-- Melder einstellen: { radius, every, on }
function Sec.sensor(addr)
    local s = db.sensors[addr]
    if not s then s = { radius = 16, every = 5, on = true } db.sensors[addr] = s end
    return s
end

-- Dienst ------------------------------------------------------------------
function Sec.service()
    local nextScan = {}
    while true do
        local now = computer.uptime()
        -- Tueren/Pulse schliessen
        local i = 1
        while i <= #Sec.closeAt do
            local c = Sec.closeAt[i]
            if now >= c.t then
                table.remove(Sec.closeAt, i)
                if c.door then Sec.doorSet(c.door, false)
                elseif c.out then Sec.setOutput(c.out, false, "Puls Ende") end
            else i = i + 1 end
        end
        if Sec.alarmOn and Sec.alarmUntil and now > Sec.alarmUntil then Sec.alarm(false, "Zeit abgelaufen") end
        for addr, t in pairs(Sec.resetPad or {}) do
            if now > t then Sec.resetPad[addr] = nil D.call(addr, "setDisplay", { db.lockdown and "GESPERRT" or "", db.lockdown and 4 or 7 }) end
        end
        -- Melder scannen
        for _, e in ipairs(D.of("sicherheit", "^os_entdetector$")) do
            local s = Sec.sensor(e.addr)
            if s.on and D.online(e) and now >= (nextScan[e.addr] or 0) then
                nextScan[e.addr] = now + (s.every or 5)
                D.call(e.addr, "scanPlayers", { s.radius or 16, false }, function(r)
                    if not r or not r[1] or type(r[2]) ~= "table" then return end
                    s.last, s.lastT = {}, computer.uptime()
                    for _, hit in pairs(r[2]) do
                        if type(hit) == "table" and hit.name then
                            s.last[#s.last + 1] = { name = hit.name, range = hit.range }
                            local pos = tonumber(hit.x) and { x = hit.x, y = hit.y, z = hit.z } or nil
                            Sec.intruder(hit.name, D.label(e), pos)
                        end
                    end
                end)
            end
        end
        -- RFID-Leser an Tueren regelmaessig scannen (Reichweite 3)
        for _, d in ipairs(db.doors) do
            for addr in pairs(d.readers or {}) do
                local e = D.byAddr[addr]
                if e and e.type == "os_rfidreader" and D.online(e) and now >= (nextScan[addr] or 0) then
                    nextScan[addr] = now + 2
                    D.call(addr, "scan", { d.rfid or 3 })
                end
            end
        end
        K.sleep(0.5)
    end
end

return Sec
end
