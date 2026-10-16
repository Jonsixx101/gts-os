-- GTS OS (OpenComputers) - SICHERHEIT: Türen, Personen, Melder, Redstone, Abwehr (OpenSecurity)
local K, G, UI, S = ...
local computer = require("computer")
local C = G.C
local D, Sec = K.dev, K.sec
local A = { view = "home", page = { page = 1 }, pPage = { page = 1 }, dPage = { page = 1 }, oPage = { page = 1 }, mPage = { page = 1 }, lPage = { page = 1 } }
local VIEWS = { { id = "home", text = "ÜBERSICHT" }, { id = "doors", text = "TÜREN" }, { id = "people", text = "PERSONEN" },
                { id = "sensors", text = "MELDER" }, { id = "outs", text = "AUSGÄNGE" }, { id = "log", text = "PROTOKOLL" } }
local SIDES = { [0] = "unten", "oben", "hinten (N)", "vorne (S)", "rechts (W)", "links (O)" }
local COLORS = { [0] = "weiß", "orange", "magenta", "hellblau", "gelb", "hellgrün", "rosa", "grau", "hellgrau", "türkis",
                 "lila", "blau", "braun", "grün", "rot", "schwarz" }
function A.enter(arg) if type(arg) == "string" then A.view = arg end end

local function admin(title, fn) K.askAdmin(title or "Admin-Code", fn) end
local function pickDevice(title, pattern, cb)
    local list, items = D.of(nil, pattern), {}
    for _, e in ipairs(list) do items[#items + 1] = { text = D.label(e), sub = D.where(e), onClick = function() cb(e) end } end
    if #items == 0 then K.notify("Kein passendes Gerät angeschlossen", "warn") return end
    if #items == 1 then cb(list[1]) return end
    UI.menu(title, items)
end

if not Sec then
    function A.draw(x, y, w, h)
        UI.empty(x, y + math.floor(h / 2) - 1, w, "SICHERHEIT ist im sicheren Modus aus", "SYSTEM > WARTUNG: sicheren Modus beenden.")
    end
    return A
end
local db = Sec.db

-- ---------------------------------------------------------------------
-- Uebersicht
-- ---------------------------------------------------------------------
local guardMenu
guardMenu = function()
    local g = db.guard
    local function t(key, text) return { text = (g[key] and "✓  " or "○  ") .. text, onClick = function() g[key] = not g[key] Sec.save() guardMenu() end } end
    local items = { t("alarm", "Alarm auslösen"), t("lock", "Basis abriegeln (Türen zu, nur Admins)"), t("drone", "Freie Drohne zum Beobachten schicken") }
    for _, o in ipairs(db.outputs) do
        g.outs = g.outs or {}
        items[#items + 1] = { text = (g.outs[o.id] and "✓  " or "○  ") .. "Redstone: " .. o.name, onClick = function() g.outs[o.id] = (not g.outs[o.id]) or nil Sec.save() guardMenu() end }
    end
    UI.menu("Maßnahmen bei Fremden (Abwehr scharf)", items)
end

local function drawHome(x, y, w, h)
    local wide = w >= 110
    local lw = wide and math.floor((w - 2) * 0.5) or w
    local g = db.guard
    local small = h < 30           -- 80x25: alles in einer Spalte, ohne Grossschrift
    -- Abwehr
    local ah = small and 6 or 11
    local ix, iy, iw = UI.card(x, y, lw, ah, small and ("ABWEHR: " .. (g.on and "SCHARF" or "AUS")) or "ABWEHR",
                               { titleColor = small and (g.on and C.bad or C.dim) or nil })
    if not small then G.big(ix, iy, g.on and "SCHARF" or "AUS", g.on and C.bad or C.dim, C.card) end
    local acts = {}
    if g.alarm then acts[#acts + 1] = "Alarm" end
    if g.lock then acts[#acts + 1] = "Abriegeln" end
    if g.drone then acts[#acts + 1] = "Drohne" end
    local nOut = 0
    for _, on in pairs(g.outs or {}) do if on then nOut = nOut + 1 end end
    if nOut > 0 then acts[#acts + 1] = nOut .. " Redstone" end
    G.text(ix, iy + (small and 0 or 4), G.fit("Bei Fremden: " .. (#acts > 0 and table.concat(acts, " · ") or "nur Meldung"), iw), C.dim, C.card)
    UI.row({
        { text = g.on and "ENTSCHÄRFEN" or "SCHARF SCHALTEN", style = g.on and "secondary" or "danger", onClick = function()
            if g.on then admin("Admin-Code (entschärfen)", function() g.on = false Sec.save() Sec.note("info", "Abwehr entschärft") end)
            else g.on = true Sec.save() Sec.note("warn", "Abwehr scharf") end
        end },
        { text = "MASSNAHMEN", style = "subtle", onClick = guardMenu },
    }, ix, iy + (small and 2 or 6), 2)
    -- Alarm / Abriegeln
    local ay = y + ah + 1
    local sh = small and 6 or 7
    local bx, by, bw = UI.card(x, ay, lw, sh, "SOFORT")
    if small then by = by - 1 end
    UI.row({
        { text = Sec.alarmOn and "ALARM AUS" or "ALARM AN", style = Sec.alarmOn and "primary" or "warn", onClick = function() Sec.alarm(not Sec.alarmOn, "von Hand") end },
        { text = db.lockdown and "ABRIEGELN AUFHEBEN" or "ABRIEGELN", style = db.lockdown and "primary" or "danger", confirm = (not db.lockdown) and "lock" or nil,
          onClick = function()
              if db.lockdown then admin("Admin-Code (aufheben)", function() Sec.lockdown(false) end) else Sec.lockdown(true, "von Hand") end
          end },
    }, bx, by + 1, 2)
    if db.lockdown then G.text(bx, by + 3, G.fit("Abgeriegelt: alle Türen zu, Zutritt nur für Admins", bw), C.bad, C.card) end
    if small then
        -- klein: darunter nur die letzten Ereignisse
        local ly = ay + sh + 1
        if y + h - ly >= 3 then
            local lx, lyy, lw2, lh = UI.card(x, ly, lw, y + h - ly, "LETZTE EREIGNISSE")
            if #Sec.log == 0 then G.text(lx, lyy, "Noch nichts passiert", C.muted, C.card) end
            for i, e in ipairs(Sec.log) do
                if i > lh then break end
                G.text(lx, lyy + i - 1, e.clock, C.muted, C.card)
                G.text(lx + 6, lyy + i - 1, G.fit(e.text, lw2 - 6), K.LEVEL[e.level] or C.text, C.card)
            end
        end
        return
    end
    -- Melder (nur breit: links unten)
    local my = ay + 8
    if wide and y + h - my >= 5 then
        local list = D.of("sicherheit", "^os_entdetector$")
        local mx, myy, mw, mh = UI.card(x, my, lw, y + h - my, "MELDER", { right = #list .. "" })
        if #list == 0 then UI.para(mx, myy, mw, "Kein Entity Detector angeschlossen. Drohnen mit Bewegungssensor melden trotzdem.", C.muted, mh) end
        for i, e in ipairs(list) do
            if i > mh then break end
            local sn = Sec.sensor(e.addr)
            local names = {}
            for _, l in ipairs(sn.last or {}) do names[#names + 1] = l.name end
            G.put(mx, myy + i - 1, "●", (sn.on and D.online(e)) and C.accent or C.muted, C.card)
            G.text(mx + 2, myy + i - 1, G.fit(D.label(e) .. "  ·  " .. sn.radius .. " Bl.  ·  " .. (#names > 0 and table.concat(names, ", ") or "niemand"), mw - 2), C.text, C.card)
        end
    end
    -- rechts / unten: Tueren + Ereignisse
    local rx, ry, rw = wide and (x + lw + 2) or x, wide and y or (ay + 7), wide and (w - lw - 2) or w
    local rh = y + h - ry
    local half = math.max(5, math.floor(rh / 2))
    local dx, dy, dw, dh = UI.card(rx, ry, rw, half, "TÜREN", { right = #db.doors .. "" })
    if #db.doors == 0 then UI.para(dx, dy, dw, "Noch keine Türen. TÜREN > + TÜR (Security-Door-Steuerung oder ein Redstone-Ausgang).", C.muted, dh) end
    for i, d in ipairs(db.doors) do
        if i > dh then break end
        G.put(dx, dy + i - 1, d.isOpen and "◌" or "■", d.isOpen and C.warn or C.accent, C.card)
        G.text(dx + 2, dy + i - 1, G.fit(d.name, dw - 14), C.text, C.card)
        UI.button({ x = dx + dw - 10, y = dy + i - 1, w = 10, text = "ÖFFNEN", style = "subtle", onClick = function() Sec.doorSet(d, true, "von Hand") end })
    end
    local lx, ly, lw2, lh = UI.card(rx, ry + half + 1, rw, rh - half - 1, "LETZTE EREIGNISSE")
    if #Sec.log == 0 then G.text(lx, ly, "Noch nichts passiert", C.muted, C.card) end
    for i, e in ipairs(Sec.log) do
        if i > lh then break end
        G.text(lx, ly + i - 1, e.clock, C.muted, C.card)
        G.text(lx + 6, ly + i - 1, G.fit(e.text, lw2 - 6), K.LEVEL[e.level] or C.text, C.card)
    end
end

-- ---------------------------------------------------------------------
-- Tueren
-- ---------------------------------------------------------------------
local function readersMenu(d)
    local items = {}
    d.readers = d.readers or {}
    for _, e in ipairs(D.of("sicherheit")) do
        if e.type == "os_magreader" or e.type == "os_rfidreader" or e.type == "os_biometric" or e.type == "os_keypad" then
            items[#items + 1] = { text = (d.readers[e.addr] and "✓  " or "○  ") .. D.label(e), sub = e.kind, onClick = function()
                d.readers[e.addr] = (not d.readers[e.addr]) or nil
                Sec.save()
                readersMenu(d)
            end }
        end
    end
    if #items == 0 then K.notify("Keine Leser angeschlossen (Karten-, RFID-, Biometrie-Leser, Tastenfeld)", "warn") return end
    UI.menu("Leser für " .. d.name, items)
end
local function doorMenu(d, i)
    UI.menu(d.name, {
        { text = "LESER VERKNÜPFEN", onClick = function() admin(nil, function() readersMenu(d) end) end },
        { text = "OFFEN-ZEIT: " .. (d.open or 4) .. " s", onClick = function()
            UI.prompt({ title = "Sekunden offen (0 = bleibt offen)", text = tostring(d.open or 4), numeric = true, onOk = function(t) d.open = tonumber(t) or 4 Sec.save() end })
        end },
        { text = "ZONE: " .. (d.zone or "keine"), onClick = function()
            admin(nil, function() UI.prompt({ title = "Zone (leer = alle Personen)", text = d.zone or "", maxLen = 16, onOk = function(t) d.zone = t ~= "" and t or nil Sec.save() end }) end)
        end },
        { text = "UMBENENNEN", onClick = function() UI.prompt({ title = "Name der Tür", text = d.name, maxLen = 24, onOk = function(t) d.name = t Sec.save() end }) end },
        { text = d.kind == "os" and "TÜR-PASSWORT" or "(Redstone-Tür)", disabled = d.kind ~= "os", onClick = function()
            admin(nil, function() UI.prompt({ title = "Passwort der Security Door (wie am Block gesetzt, leer = keins)", mask = true, maxLen = 32,
                onOk = function(t) d.pw = t ~= "" and t or nil Sec.save() end }) end)
        end },
        { text = "ENTFERNEN", style = "danger", confirm = "ddel" .. d.id, onClick = function() admin(nil, function() table.remove(db.doors, i) Sec.save() end) end },
    })
end
local function addDoor()
    admin(nil, function()
        local items = {}
        local used = {}
        for _, d in ipairs(db.doors) do used[d.dev] = true end
        for _, e in ipairs(D.of("sicherheit", "^os_door$")) do
            if not used[e.addr] then
                items[#items + 1] = { text = D.label(e), sub = "Security Door · " .. D.where(e), onClick = function()
                    db.doors[#db.doors + 1] = { id = Sec.newId(), name = D.names[e.addr] or ("Tür " .. (#db.doors + 1)), dev = e.addr, kind = "os", readers = {}, open = 4 }
                    Sec.save()
                end }
            end
        end
        for _, o in ipairs(db.outputs) do
            items[#items + 1] = { text = "Redstone: " .. o.name, sub = "Tür/Tor über Redstone", onClick = function()
                db.doors[#db.doors + 1] = { id = Sec.newId(), name = o.name, dev = o.id, kind = "rs", readers = {}, open = 4 }
                Sec.save()
            end }
        end
        if #items == 0 then K.notify("Keine Security-Door-Steuerung und keine Redstone-Ausgänge (AUSGÄNGE)", "warn") return end
        UI.menu("Welche Tür?", items)
    end)
end
local function drawDoors(x, y, w, h)
    local ix, iy, iw, ih = UI.card(x, y, w, h, #db.doors .. " TÜREN")
    UI.button({ x = ix + iw - 10, y = iy - 1, w = 10, text = "+ TÜR", style = "primary", onClick = addDoor })
    if #db.doors == 0 then
        UI.para(ix, iy + 1, iw, "Eine Tür ist eine Security-Door-Steuerung (OpenSecurity) oder ein Redstone-Ausgang (z.B. Kolben-Tor). Leser (Karte, RFID, Biometrie, Tastenfeld) werden mit Türen verknüpft: eine erlaubte Person öffnet die Tür für ein paar Sekunden.", C.muted)
        return
    end
    UI.list(A.dPage, db.doors, ix, iy + 1, iw, ih - 1, 3, function(d, rx, ry, rw, i)
        local nr = 0
        for _ in pairs(d.readers or {}) do nr = nr + 1 end
        G.put(rx, ry, d.isOpen and "◌" or "■", d.isOpen and C.warn or C.accent, C.card)
        G.text(rx + 2, ry, G.fit(d.name, rw - 32), C.text, C.card)
        G.text(rx + 2, ry + 1, G.fit((d.kind == "os" and "Security Door" or "Redstone") .. " · " .. nr .. " Leser · Zone " .. (d.zone or "alle")
            .. " · " .. (d.open or 4) .. " s", rw - 32), C.dim, C.card)
        UI.button({ x = rx + rw - 29, y = ry, w = 10, text = "ÖFFNEN", style = "secondary", onClick = function() Sec.doorSet(d, true, "von Hand") end })
        UI.button({ x = rx + rw - 18, y = ry, w = 9, text = "ZU", style = "subtle", onClick = function() Sec.doorSet(d, false) end })
        UI.button({ x = rx + rw - 8, y = ry, w = 8, text = "MEHR", style = "subtle", onClick = function() doorMenu(d, i) end })
    end)
end

-- ---------------------------------------------------------------------
-- Personen
-- ---------------------------------------------------------------------
local function count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
local function personMenu(p, i)
    UI.menu(p.name, {
        { text = "KARTE SCHREIBEN", sub = "Mag- oder RFID-Karte in den Kartenschreiber", onClick = function()
            admin(nil, function()
                pickDevice("Welcher Kartenschreiber?", "^os_cardwriter$", function(e)
                    Sec.issueCard(p, e.addr, function(ok) K.notify(ok and ("Karte für " .. p.name .. " fertig") or "Kartenschreiber: fehlgeschlagen (Karte eingelegt?)", ok and "ok" or "warn") end)
                end)
            end)
        end },
        { text = "BIOMETRIE ANLERNEN", sub = "30 s: Hand auf den Leser", onClick = function()
            admin(nil, function()
                Sec.enroll = { id = p.id, kind = "bio", untilT = computer.uptime() + 30 }
                K.notify(p.name .. ": jetzt die Hand auf einen Biometrie-Leser legen (30 s)", "info")
            end)
        end },
        { text = p.pin and "PIN ÄNDERN" or "PIN FESTLEGEN", sub = "fürs Tastenfeld, mit # bestätigen", onClick = function()
            admin(nil, function() UI.keypad({ title = "PIN für " .. p.name, maxLen = 8, onOk = function(t)
                if #t < 4 then K.notify("Mindestens 4 Ziffern", "warn") return end
                Sec.setPin(p, t) K.notify("PIN gesetzt", "ok") end }) end)
        end },
        { text = "ZONEN: " .. (p.zones == "alle" and "alle" or table.concat((function() local t = {} for z in pairs(p.zones or {}) do t[#t + 1] = z end return t end)(), ", ")),
          onClick = function()
              admin(nil, function() UI.prompt({ title = "Zonen (mit Komma, leer = alle)", maxLen = 60, onOk = function(t)
                  if t == "" then p.zones = "alle" else p.zones = {} for z in t:gmatch("[^,%s][^,]*") do p.zones[(z:gsub("%s+$", ""))] = true end end
                  Sec.save() end }) end)
          end },
        { text = p.admin and "ADMIN: JA (auch beim Abriegeln)" or "ADMIN: NEIN", onClick = function() admin(nil, function() p.admin = not p.admin Sec.save() end) end },
        { text = p.blocked and "ZUTRITT WIEDER ERLAUBEN" or "ZUTRITT SPERREN", onClick = function() admin(nil, function() p.blocked = not p.blocked Sec.save() end) end },
        { text = "ALLE KARTEN UNGÜLTIG", style = "warn", confirm = "rv" .. p.id, onClick = function() admin(nil, function() Sec.revokeCards(p) end) end },
        { text = "LÖSCHEN", style = "danger", confirm = "pd" .. p.id, onClick = function() admin(nil, function() table.remove(db.people, i) Sec.save() end) end },
    })
end
local function drawPeople(x, y, w, h)
    local ix, iy, iw, ih = UI.card(x, y, w, h, #db.people .. " PERSONEN")
    UI.button({ x = ix + iw - 12, y = iy - 1, w = 12, text = "+ PERSON", style = "primary", onClick = function()
        admin(nil, function() UI.prompt({ title = "Name (Spielername)", maxLen = 24, onOk = function(t) if t ~= "" then Sec.addPerson(t) end end }) end)
    end })
    if #db.people == 0 then
        UI.para(ix, iy + 1, iw, "Personen bekommen Karten (Kartenschreiber), Biometrie oder eine PIN. Wer hier steht, gilt auch für die Melder als bekannt.", C.muted)
        return
    end
    UI.list(A.pPage, db.people, ix, iy + 1, iw, ih - 1, 3, function(p, rx, ry, rw, i)
        G.put(rx, ry, "●", p.blocked and C.bad or (p.admin and C.warn or C.accent), C.card)
        G.text(rx + 2, ry, G.fit(p.name .. (p.admin and "  (Admin)" or "") .. (p.blocked and "  GESPERRT" or ""), rw - 12), p.blocked and C.bad or C.text, C.card)
        local info = count(p.cards) .. " Karte(n) · " .. #(p.bio or {}) .. " Biometrie · " .. (p.pin and "PIN" or "keine PIN")
            .. " · Zonen " .. (p.zones == "alle" and "alle" or count(p.zones))
        G.text(rx + 2, ry + 1, G.fit(info, rw - 12), C.dim, C.card)
        UI.button({ x = rx + rw - 8, y = ry, w = 8, text = "MEHR", style = "subtle", onClick = function() personMenu(p, i) end })
    end)
    if Sec.enroll and computer.uptime() < Sec.enroll.untilT then
        G.text(ix, iy + ih - 1, "Biometrie: warte auf Hand am Leser … " .. math.ceil(Sec.enroll.untilT - computer.uptime()) .. " s", C.warn, C.card)
    end
end

-- ---------------------------------------------------------------------
-- Melder
-- ---------------------------------------------------------------------
local function drawSensors(x, y, w, h)
    local list = D.of("sicherheit", "^os_entdetector$")
    local wide = w >= 110
    local lw = wide and math.floor(w * 0.6) or w
    local lh = wide and h or math.max(8, h - 10)
    local ix, iy, iw, ih = UI.card(x, y, lw, lh, #list .. " MELDER (Entity Detector)")
    if #list == 0 then
        UI.para(ix, iy + 1, iw, "Kein Entity Detector angeschlossen. Melder suchen regelmäßig nach Spielern im Umkreis; Fremde werden gemeldet - und bei scharfer ABWEHR greifen die Maßnahmen. Drohnen mit Bewegungssensor melden auch.", C.muted)
    else
        UI.list(A.mPage, list, ix, iy, iw, ih, 4, function(e, rx, ry, rw)
            local s = Sec.sensor(e.addr)
            G.put(rx, ry, "●", (s.on and D.online(e)) and C.accent or C.muted, C.card)
            G.text(rx + 2, ry, G.fit(D.label(e) .. " · " .. D.where(e), rw - 12), C.text, C.card)
            UI.toggle(rx + rw - 9, ry, s.on, function() s.on = not s.on Sec.save() end)
            G.text(rx + 2, ry + 1, "Radius", C.muted, C.card)
            local cx = rx + 10
            for _, r in ipairs({ 8, 16, 32, 64 }) do cx = UI.chip(cx, ry + 1, r .. "", s.radius == r, function() s.radius = r Sec.save() end) + 1 end
            G.text(cx + 1, ry + 1, "alle", C.muted, C.card)
            cx = cx + 6
            for _, t in ipairs({ 2, 5, 10 }) do cx = UI.chip(cx, ry + 1, t .. " s", s.every == t, function() s.every = t Sec.save() end) + 1 end
            local seen = {}
            for _, l in ipairs(s.last or {}) do seen[#seen + 1] = l.name end
            G.text(rx + 2, ry + 2, G.fit(s.lastT and ("Zuletzt: " .. (#seen > 0 and table.concat(seen, ", ") or "niemand")) or "noch nicht gescannt", rw - 4), C.dim, C.card)
        end)
    end
    local tx, ty, tw, th
    if wide then tx, ty, tw, th = UI.card(x + lw + 2, y, w - lw - 2, h, "BEKANNT (kein Alarm)")
    else tx, ty, tw, th = UI.card(x, y + lh + 1, w, h - lh - 1, "BEKANNT (kein Alarm)") end
    local names = { K.set.owner ~= "" and K.set.owner or nil }
    for _, t in ipairs(K.set.trusted or {}) do names[#names + 1] = t end
    for _, p in ipairs(db.people) do names[#names + 1] = p.name end
    UI.para(tx, ty, tw, #names > 0 and table.concat(names, ", ") or "niemand", C.text, th - 2)
    UI.row({
        { text = "+ VERTRAUT", style = "subtle", onClick = function()
            UI.prompt({ title = "Spielername", maxLen = 16, onOk = function(t) if t ~= "" then local l = K.set.trusted or {} l[#l + 1] = t K.setting("trusted", l) end end })
        end },
        { text = "LEEREN", style = "subtle", confirm = "trclr", onClick = function() admin(nil, function() K.setting("trusted", {}) end) end },
    }, tx, ty + th - 1, 2)
end

-- ---------------------------------------------------------------------
-- Ausgaenge (Redstone)
-- ---------------------------------------------------------------------
local function outLabel(o)
    local e = D.byAddr[o.dev]
    return (e and D.label(e) or "Gerät fehlt") .. " · " .. (SIDES[o.side or 1] or "?") .. (o.color and (" · Bündel " .. COLORS[o.color]) or "")
        .. " · " .. (o.mode == "puls" and ("Puls " .. (o.pulse or 1) .. " s") or "Schalter")
end
local function addOutput()
    pickDevice("Welches Redstone-Gerät?", "^redstone$", function(e)
        UI.menu("Seite", (function()
            local items = {}
            for side = 0, 5 do
                items[#items + 1] = { text = SIDES[side], onClick = function()
                    UI.prompt({ title = "Name (z.B. Falle Tor)", maxLen = 24, onOk = function(t)
                        db.outputs[#db.outputs + 1] = { id = Sec.newId(), name = t ~= "" and t or ("Ausgang " .. (#db.outputs + 1)), dev = e.addr, side = side, mode = "schalter", pulse = 1 }
                        Sec.save()
                    end })
                end }
            end
            return items
        end)())
    end)
end
local function outMenu(o, i)
    UI.menu(o.name, {
        { text = "ART: " .. (o.mode == "puls" and "PULS" or "SCHALTER"), onClick = function() o.mode = (o.mode == "puls") and "schalter" or "puls" Sec.save() end },
        { text = "PULSLÄNGE: " .. (o.pulse or 1) .. " s", onClick = function()
            UI.prompt({ title = "Sekunden", text = tostring(o.pulse or 1), numeric = true, onOk = function(t) o.pulse = math.max(1, tonumber(t) or 1) Sec.save() end })
        end },
        { text = "BÜNDEL-FARBE: " .. (o.color and COLORS[o.color] or "aus"), onClick = function()
            UI.prompt({ title = "Farbe 0-15 (leer = normales Signal)", text = o.color and tostring(o.color) or "", numeric = true, onOk = function(t)
                local c = tonumber(t) o.color = (c and c >= 0 and c <= 15) and math.floor(c) or nil Sec.save() end })
        end },
        { text = "UMGEKEHRT: " .. (o.inv and "JA" or "NEIN"), onClick = function() o.inv = not o.inv Sec.save() end },
        { text = "BEIM ABRIEGELN AN: " .. (o.lock and "JA" or "NEIN"), onClick = function() o.lock = not o.lock Sec.save() end },
        { text = "UMBENENNEN", onClick = function() UI.prompt({ title = "Name", text = o.name, maxLen = 24, onOk = function(t) o.name = t Sec.save() end }) end },
        { text = "ENTFERNEN", style = "danger", confirm = "od" .. o.id, onClick = function() table.remove(db.outputs, i) Sec.save() end },
    })
end
local function drawOuts(x, y, w, h)
    local ix, iy, iw, ih = UI.card(x, y, w, h, #db.outputs .. " REDSTONE-AUSGÄNGE")
    UI.button({ x = ix + iw - 14, y = iy - 1, w = 14, text = "+ AUSGANG", style = "primary", onClick = function() admin(nil, addOutput) end })
    if #db.outputs == 0 then
        UI.para(ix, iy + 1, iw, "Benannte Redstone-Signale an Redstone-Karten oder Redstone-I/O-Blöcken - auch an Knoten weit weg. Für Tore, Lampen, Fallen oder Maschinen; auslösbar von Hand, von der ABWEHR und von Wächtern.", C.muted)
        return
    end
    UI.list(A.oPage, db.outputs, ix, iy + 1, iw, ih - 1, 3, function(o, rx, ry, rw, i)
        G.put(rx, ry, "●", o.on and C.warn or C.muted, C.card)
        G.text(rx + 2, ry, G.fit(o.name, rw - 32), C.text, C.card)
        G.text(rx + 2, ry + 1, G.fit(outLabel(o), rw - 22), C.dim, C.card)
        UI.button({ x = rx + rw - 29, y = ry, w = 10, text = o.mode == "puls" and "PULS" or (o.on and "AUS" or "AN"), style = "secondary",
                    onClick = function() Sec.trigger(o, "von Hand") end })
        UI.button({ x = rx + rw - 18, y = ry, w = 9, text = "TEST", style = "subtle", onClick = function() Sec.pulse(o, "Test") end })
        UI.button({ x = rx + rw - 8, y = ry, w = 8, text = "MEHR", style = "subtle", onClick = function() admin(nil, function() outMenu(o, i) end) end })
    end)
end

local function drawLog(x, y, w, h)
    local ix, iy, iw, ih = UI.card(x, y, w, h, "PROTOKOLL", { right = #Sec.log .. " Einträge" })
    if #Sec.log == 0 then G.text(ix, iy, "Noch keine Einträge", C.muted, C.card) return end
    UI.list(A.lPage, Sec.log, ix, iy, iw, ih, 1, function(e, rx, ry, rw)
        G.text(rx, ry, e.clock, C.muted, C.card)
        G.text(rx + 7, ry, G.fit(e.text, rw - 7), K.LEVEL[e.level] or C.text, C.card)
    end)
end

function A.draw(x, y, w, h)
    local pad = (w < 100) and 1 or 2
    x, w = x + pad, w - pad * 2
    G.text(x, y + 1, "SICHERHEIT", C.text)
    local st = db.lockdown and "ABGERIEGELT" or (db.guard.on and "Abwehr scharf" or "Abwehr aus")
    G.text(x + 12, y + 1, "  " .. st .. (Sec.alarmOn and " · ALARM" or ""), (db.lockdown or Sec.alarmOn) and C.bad or C.muted)
    UI.tabs(x, y + 3, w, VIEWS, A.view, function(v) A.view = v end)
    local top = y + 5
    local hh = y + h - top
    if A.view == "home" then drawHome(x, top, w, hh)
    elseif A.view == "doors" then drawDoors(x, top, w, hh)
    elseif A.view == "people" then drawPeople(x, top, w, hh)
    elseif A.view == "sensors" then drawSensors(x, top, w, hh)
    elseif A.view == "outs" then drawOuts(x, top, w, hh)
    else drawLog(x, top, w, hh) end
end
function A.tick() return true end
return A
