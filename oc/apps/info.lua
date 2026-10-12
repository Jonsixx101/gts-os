-- GTS OS (OpenComputers) - SYSTEM: Info, Check, Einstellungen, Meldungen, Update, Wartung
local K, G, UI, S = ...
local computer = require("computer")
local component = require("component")
local C = G.C
local Y = K.sys
local A = { view = "info", tab = "sicherheit", compPage = { page = 1 }, notePage = { page = 1 }, logPage = { page = 1 }, chkPage = { page = 1 } }
local VIEWS = { { id = "info", text = "ÜBERSICHT" }, { id = "check", text = "CHECK" }, { id = "settings", text = "EINSTELLUNGEN" },
                { id = "notes", text = "MELDUNGEN" }, { id = "update", text = "UPDATE" }, { id = "care", text = "WARTUNG" } }

function A.enter(arg) if type(arg) == "string" then A.view = arg end if A.view == "notes" then K.unread = 0 end end

local function graph(x, y, w, h, title, value, hist, color)
    local ix, iy, iw, ih = UI.card(x, y, w, h, title, { right = value })
    if hist and #hist >= 4 then G.spark(ix, iy, iw, ih, hist, color, C.card, true) else G.text(ix, iy, "sammle Messwerte ...", C.muted, C.card) end
end

local function drawInfo(x, y, w, h)
    local d = Y.device()
    local wide = w >= 110
    local col = wide and math.floor((w - 2) / 2) or w
    -- Geraet
    local ix, iy, iw, ih = UI.card(x, y, col, 13, "DIESER RECHNER")
    local kw = 18
    UI.kv(ix, iy, iw, "GTS OS", K.VERSION .. (K.set.safeMode and "  (sicherer Modus)" or ""), nil, kw)
    UI.kv(ix, iy + 1, iw, "Prozessor", d.cpu .. (d.cpuClock and ("  ·  " .. d.cpuClock .. " Takt") or ""), nil, kw)
    UI.kv(ix, iy + 2, iw, "Arbeitsspeicher", K.bytes(computer.totalMemory()) .. "  ·  " .. K.bytes(computer.freeMemory()) .. " frei", nil, kw)
    UI.kv(ix, iy + 3, iw, "Grafik", "Tier " .. (d.gpuTier or "?") .. "  ·  max " .. d.gpuRes .. "  ·  " .. (d.gpuDepth or 0) .. " Bit", nil, kw)
    UI.kv(ix, iy + 4, iw, "Bildschirm", K.w .. "x" .. K.h .. (K.hasKeyboard and "  ·  mit Tastatur" or "  ·  ohne Tastatur"), nil, kw)
    UI.kv(ix, iy + 5, iw, "Energie", string.format("%d / %d", math.floor(computer.energy()), math.floor(computer.maxEnergy())), nil, kw)
    UI.kv(ix, iy + 6, iw, "Laufzeit", K.ago(computer.uptime()), nil, kw)
    UI.kv(ix, iy + 7, iw, "Data Card", d.dataTier and ("Tier " .. d.dataTier .. (d.dataTier >= 2 and "  ·  AES" or "  ·  nur Siegel")) or "fehlt", (not d.dataTier) and C.warn or C.text, kw)
    UI.kv(ix, iy + 8, iw, "Funk", K.net.ready and ((K.net.wireless and "drahtlos 400 Bl." or "Kabel") .. "  ·  Port " .. K.net.port) or tostring(K.net.reason), K.net.ready and C.text or C.bad, kw)
    UI.kv(ix, iy + 9, iw, "Internet", d.internet and "ja" or "nein", nil, kw)
    -- Verlaeufe
    local gx, gy = wide and (x + col + 2) or x, wide and y or (y + 14)
    local gw = wide and (w - col - 2) or w
    local gh = 6
    local e = computer.energy() / math.max(1, computer.maxEnergy())
    local ram = 1 - computer.freeMemory() / math.max(1, computer.totalMemory())
    graph(gx, gy, gw, gh, "ENERGIE", math.floor(e * 100) .. " %", Y.hist.energy, e < 0.2 and C.bad or C.info)
    graph(gx, gy + gh, gw, gh, "ARBEITSSPEICHER", math.floor(ram * 100) .. " %", Y.hist.ram, ram > 0.85 and C.warn or C.accent)
    -- Speicher
    local sy = wide and (y + 14) or (gy + 2 * gh + 1)
    local disks = Y.disks()
    local dh = math.min(#disks * 2 + 3, 12)
    if sy + dh <= y + h then
        local dx, dy, dw = UI.card(x, sy, col, dh, "SPEICHER")
        for i, dk in ipairs(disks) do
            local yy = dy + (i - 1) * 2
            if yy + 1 > sy + dh - 2 then break end
            local frac = dk.total > 0 and dk.used / dk.total or 0
            G.text(dx, yy, G.fit((dk.boot and "■ " or "□ ") .. dk.label .. (dk.tmp and " (tmp)" or "") .. (dk.ro and " (nur lesen)" or ""), dw - 22), C.text, C.card)
            G.right(dx + dw - 1, yy, K.bytes(dk.used) .. " / " .. K.bytes(dk.total), C.dim, C.card)
            G.bar(dx, yy + 1, dw, frac, frac > 0.9 and C.bad or C.accent, C.line)
        end
    end
    -- Komponenten
    local cy = wide and (gy + 2 * gh) or (sy + dh)
    local cx = wide and gx or x
    local cwid = wide and gw or w
    if cy + 4 <= y + h then
        local comps = Y.components()
        local kx, ky, kw2, kh = UI.card(cx, cy, cwid, y + h - cy, "KOMPONENTEN", { right = #comps .. "" })
        UI.list(A.compPage, comps, kx, ky, kw2, kh, 1, function(c, rx, ry, rw)
            G.text(rx, ry, G.fit(c.name, 22), C.text, C.card)
            G.text(rx + 24, ry, G.fit(c.type, rw - 36), C.muted, C.card)
            G.right(rx + rw - 1, ry, c.addr:sub(1, 8), C.muted, C.card)
        end)
    end
end

local function drawCheck(x, y, w, h)
    local list = Y.check()
    local ix, iy, iw, ih = UI.card(x, y, w, h, "SYSTEM-CHECK")
    local bad, warn = 0, 0
    for _, c in ipairs(list) do if c.level == "bad" then bad = bad + 1 elseif c.level == "warn" then warn = warn + 1 end end
    local col = bad > 0 and C.bad or (warn > 0 and C.warn or C.accent)
    G.text(ix, iy, bad > 0 and ("● " .. bad .. " Problem(e)") or (warn > 0 and ("● " .. warn .. " Hinweis(e)") or "● Alles in Ordnung"), col, C.card)
    UI.list(A.chkPage, list, ix, iy + 2, iw, ih - 2, 2, function(c, rx, ry, rw)
        local cc = ({ ok = C.accent, warn = C.warn, bad = C.bad })[c.level]
        G.put(rx, ry, "●", cc, C.card)
        G.text(rx + 2, ry, G.fit(c.title, rw - 2), C.text, C.card)
        G.text(rx + 2, ry + 1, G.fit(c.tip or "", rw - 2), C.muted, C.card)
    end)
end

-- Einstellungen ----------------------------------------------------------
local function row(x, y, w, label, value, buttons, color)
    G.text(x, y, G.fit(label, 24), C.text, C.card)
    if value then G.text(x + 26, y, G.fit(value, w - 26 - 30), color or C.dim, C.card) end
    if buttons then UI.buttonsRight(buttons, y, x + w - 1, x + 26) end
end
local function codeTwice(title, key)
    UI.keypad({ title = "Neuer " .. title, maxLen = 8, onOk = function(a)
        if #a < 4 then K.notify("Mindestens 4 Ziffern", "warn") return end
        UI.keypad({ title = title .. " wiederholen", maxLen = 8, onOk = function(b)
            if a ~= b then K.notify("Nicht gleich - nicht geändert", "warn") return end
            K.setting(key, K.hash(a))
            K.notify(title .. " geändert", "ok")
        end })
    end })
end
local function choice(key, values, fmt, after)
    local out = {}
    for _, v in ipairs(values) do
        out[#out + 1] = { text = fmt(v), style = (K.set[key] == v) and "primary" or "subtle", onClick = function()
            K.setting(key, v)
            if after then after(v) end
        end }
    end
    return out
end
local function drawSettings(x, y, w, h)
    local tabs = { { id = "sicherheit", text = "SICHERHEIT" }, { id = "allgemein", text = "ALLGEMEIN" }, { id = "design", text = "DESIGN" }, { id = "schwarm", text = "SCHWARM" } }
    local ix, iy, iw, ih = UI.card(x, y, w, h, nil)
    UI.tabs(ix, iy, iw, tabs, A.tab, function(t) A.tab = t end)
    local yy = iy + 3
    local function r(...) row(ix, yy, iw, ...) yy = yy + 2 end
    if A.tab == "sicherheit" then
        r("Sperrcode", K.set.codeHash and "eigener Code" or "3344 (Standard)", { { text = "ÄNDERN", style = "secondary", onClick = function()
            K.askAdmin("Admin-Code", function() codeTwice("Sperrcode", "codeHash") end) end } }, not K.set.codeHash and C.warn)
        r("Admin-Code", K.set.adminHash and "gesetzt" or "fehlt", { { text = "ÄNDERN", style = "secondary", onClick = function()
            K.askAdmin("Admin-Code (bisher)", function() codeTwice("Admin-Code", "adminHash") end) end } }, not K.set.adminHash and C.warn)
        r("Auto-Sperre", (K.set.autoLock or 0) > 0 and (K.set.autoLock .. " min") or "aus", choice("autoLock", { 2, 5, 10, 30, 0 }, function(v) return v == 0 and "AUS" or tostring(v) end))
        r("Jetzt sperren", nil, { { text = "SPERREN", style = "secondary", onClick = function() K.lock() end } })
        r("Vertraute Spieler", #(K.set.trusted or {}) > 0 and table.concat(K.set.trusted, ", ") or "keine",
          { { text = "+", w = 3, style = "subtle", onClick = function()
              UI.prompt({ title = "Spielername", maxLen = 16, onOk = function(t) local l = K.set.trusted or {} l[#l + 1] = t K.setting("trusted", l) end })
          end }, { text = "LEEREN", style = "subtle", onClick = function() K.setting("trusted", {}) end } })
    elseif A.tab == "allgemein" then
        r("Besitzer", K.set.owner ~= "" and K.set.owner or "fehlt", { { text = "ÄNDERN", style = "secondary", onClick = function()
            UI.prompt({ title = "Dein Spielername", text = K.set.owner, maxLen = 16, onOk = function(t) K.setting("owner", t) end }) end } })
        r("Zeitzone", K.set.tz == "berlin" and "Berlin (Sommerzeit automatisch)" or ("UTC" .. (K.set.tz >= 0 and "+" or "") .. K.set.tz),
          choice("tz", { "berlin", 0, 1, 2 }, function(v) return v == "berlin" and "BERLIN" or ("UTC+" .. v) end))
        r("Auflösung", type(K.set.res) == "table" and (K.set.res[1] .. "x" .. K.set.res[2]) or "automatisch (passend zum Bildschirm)",
          { { text = "AUTO", style = K.set.res == "auto" and "primary" or "subtle", onClick = function() K.setting("res", "auto") K.initScreen() end },
            { text = "100x32", style = "subtle", onClick = function() K.setting("res", { 100, 32 }) K.initScreen() end },
            { text = "160x50", style = "subtle", onClick = function() K.setting("res", { 160, 50 }) K.initScreen() end } })
        r("Töne", K.set.sound and "an" or "aus", { { text = K.set.sound and "AUS" or "AN", style = "subtle", onClick = function() K.setting("sound", not K.set.sound) end } })
        r("Updates suchen", K.set.autoUpdate == false and "von Hand" or "täglich", { { text = K.set.autoUpdate == false and "TÄGLICH" or "VON HAND", style = "subtle",
            onClick = function() K.setting("autoUpdate", K.set.autoUpdate == false) end } })
    elseif A.tab == "design" then
        G.text(ix, yy, "Thema", C.text, C.card)
        local tx = ix + 26
        for _, id in ipairs(G.THEME_ORDER) do
            tx = UI.chip(tx, yy, G.THEMES[id].name, K.set.theme == id, function() K.setting("theme", id) G.applyTheme(K.set.theme, K.set.accent) end) + 1
        end
        yy = yy + 2
        G.text(ix, yy, "Akzentfarbe", C.text, C.card)
        tx = ix + 26
        for _, id in ipairs(G.ACCENT_ORDER) do
            if tx + 10 > ix + iw then yy = yy + 2 tx = ix + 26 end
            tx = UI.chip(tx, yy, G.ACCENTS[id].name, K.set.accent == id, function() K.setting("accent", id) G.applyTheme(K.set.theme, K.set.accent) end) + 1
        end
        yy = yy + 3
        G.text(ix, yy, "Vorschau", C.muted, C.card)
        UI.button({ x = ix + 26, y = yy, text = "HAUPTKNOPF", style = "primary" })
        UI.button({ x = ix + 40, y = yy, text = "KNOPF", style = "secondary" })
        G.bar(ix + 49, yy, math.max(5, iw - 49), 0.7, C.accent, C.line)
        yy = yy + 2
        for i = 0, 15 do G.fill(ix + 26 + i * 3, yy, 3, 1, i) end
        G.text(ix, yy, "Palette (16 Farben)", C.muted, C.card)
    elseif A.tab == "schwarm" then
        local net = K.net
        r("Schwarm-Passwort", net.ready and (net.isDefault and "Standard (gts) - unsicher!" or "eigenes") or tostring(net.reason),
          { { text = "ÄNDERN", style = "secondary", disabled = not net.ready, onClick = function()
              K.askAdmin("Admin-Code", function()
                  UI.prompt({ title = "Neues Schwarm-Passwort", mask = true, maxLen = 32, validate = function(t) if #t < 4 then return "Mindestens 4 Zeichen" end end,
                              onOk = function(t) net.setPassword(t) K.notify("Passwort gesetzt - Drohnen-EEPROMs und Robots neu einrichten", "warn") end })
              end)
          end } }, net.isDefault and C.warn)
        r("Funk-Port", tostring(K.set.port), { { text = "ÄNDERN", style = "subtle", onClick = function()
            UI.prompt({ title = "Port (1-65535)", text = tostring(K.set.port), numeric = true, onOk = function(t)
                local p = tonumber(t) if p and p >= 1 and p <= 65535 then K.setting("port", p) K.net.start() end end })
        end } })
        r("Heim bei Akku unter", K.set.homeAt .. " %", choice("homeAt", { 15, 25, 40 }, function(v) return v .. "%" end, function(v)
            K.units.cmdMany(K.units.list, "cfg", function() return { homeAt = v } end, "Akku-Grenze")
        end))
        r("Herzschlag", K.set.heartbeat .. " s", choice("heartbeat", { 3, 5, 10 }, function(v) return v .. "s" end, function(v)
            K.units.cmdMany(K.units.list, "cfg", function() return { beat = v } end, "Herzschlag")
        end))
        r("Neue automatisch annehmen", K.set.autoAccept and "ja" or "nein (Freigabe in DROHNEN)", { { text = K.set.autoAccept and "NEIN" or "JA", style = "subtle",
            onClick = function() K.setting("autoAccept", not K.set.autoAccept) end } })
    end
end

local function drawNotes(x, y, w, h)
    local ix, iy, iw, ih = UI.card(x, y, w, h, "MELDUNGEN", { right = #K.notes .. "" })
    if #K.notes == 0 then G.text(ix, iy, "Keine Meldungen", C.muted, C.card) return end
    UI.buttonsRight({ { text = "LEEREN", style = "subtle", onClick = function() K.notes = {} K.unread = 0 end } }, iy - 1, ix + iw - 1)
    UI.list(A.notePage, K.notes, ix, iy + 1, iw, ih - 1, 1, function(n, rx, ry, rw)
        G.put(rx, ry, "●", K.LEVEL[n.level] or C.info, C.card)
        G.text(rx + 2, ry, n.clock, C.muted, C.card)
        G.text(rx + 8, ry, G.fit(n.text, rw - 8), C.text, C.card)
        if n.target then UI.region(rx, ry, rw, 1, function() K.open(n.target) end) end
    end)
end

local function drawUpdate(x, y, w, h)
    local U = Y.update
    local ix, iy, iw, ih = UI.card(x, y, w, h, "UPDATE")
    UI.kv(ix, iy, iw, "Installiert", "GTS OS " .. K.VERSION)
    local yy = iy + 2
    if U.state == "checking" then G.text(ix, yy, "Suche nach Updates ...", C.dim, C.card)
    elseif U.state == "error" then G.text(ix, yy, "Fehler: " .. tostring(U.err), C.bad, C.card)
    elseif U.state == "current" then G.text(ix, yy, "✓ Aktuell (geprüft " .. tostring(U.checked) .. ")", C.accent, C.card)
    elseif U.state == "available" then
        G.text(ix, yy, "GTS OS " .. U.manifest.version .. " ist da", C.accent, C.card)
        for i, n in ipairs(U.manifest.notes or {}) do G.text(ix + 2, yy + i, "• " .. G.fit(n, iw - 4), C.dim, C.card) end
    elseif U.state == "downloading" then
        G.text(ix, yy, "Lade " .. U.done .. " / " .. U.total .. " Dateien ...", C.dim, C.card)
        G.bar(ix, yy + 1, iw, U.done / math.max(1, U.total), C.accent, C.line)
    elseif U.state == "ready" then G.text(ix, yy, "✓ Installiert. Neustart aktiviert die neue Fassung.", C.accent, C.card)
    else G.text(ix, yy, "Noch nicht gesucht.", C.muted, C.card) end
    local by = iy + ih - 2
    local btns = { { text = "SUCHEN", style = "secondary", disabled = U.state == "checking" or U.state == "downloading",
                     onClick = function() K.spawn("update", Y.checkUpdate) end } }
    if U.state == "available" then btns[#btns + 1] = { text = "INSTALLIEREN", style = "primary", onClick = function() K.spawn("update", Y.installUpdate) end } end
    if U.state == "ready" then btns[#btns + 1] = { text = "NEU STARTEN", style = "primary", onClick = function() computer.shutdown(true) end } end
    UI.row(btns, ix, by)
    G.text(ix, by - 2, G.fit("Quelle: " .. Y.REPO, iw), C.muted, C.card)
end

local function drawCare(x, y, w, h)
    local wide = w >= 110
    local col = wide and math.floor((w - 2) / 2) or w
    local bx, by, bw, bh = UI.card(x, y, col, 14, "BACKUP (täglich, die letzten 3)")
    local list = Y.backups()
    UI.kv(bx, by, bw, "Letztes", tostring(K.set.lastBackup or "-"))
    UI.button({ x = bx, y = by + 2, text = "JETZT SICHERN", style = "secondary", onClick = function() local n = Y.backup() K.notify("Backup " .. n .. " gespeichert", "ok") end })
    for i, name in ipairs(list) do
        local yy = by + 3 + i
        if yy > by + bh - 1 then break end
        G.text(bx, yy, name, C.text, C.card)
        UI.button({ x = bx + bw - 15, y = yy, w = 15, text = "ZURÜCKHOLEN", style = "subtle", confirm = "rs-" .. name, onClick = function()
            local ok, n = Y.restore(name)
            K.notify(ok and (n .. " Dateien zurückgeholt - Neustart empfohlen") or "Backup unlesbar", ok and "ok" or "bad")
        end })
    end
    local cx, cy = wide and (x + col + 2) or x, wide and y or (y + 15)
    local ccw = wide and (w - col - 2) or w
    local jx, jy, jw = UI.card(cx, cy, ccw, 14, "AUFRÄUMEN & SYSTEM")
    local junk = Y.junk()
    local size = 0
    for _, j in ipairs(junk) do size = size + j.size end
    UI.kv(jx, jy, jw, "Müll", #junk .. " Datei(en), " .. K.bytes(size))
    UI.button({ x = jx, y = jy + 2, text = "AUFRÄUMEN", style = "secondary", disabled = #junk == 0, onClick = function()
        local n, b = Y.clean() K.notify(n .. " Datei(en) entfernt, " .. K.bytes(b) .. " frei", "ok") end })
    UI.kv(jx, jy + 4, jw, "Sicherer Modus", K.set.safeMode and "AN (Zusatz-Apps aus)" or "aus", K.set.safeMode and C.warn or nil)
    UI.button({ x = jx, y = jy + 6, text = K.set.safeMode and "BEENDEN + NEUSTART" or "EINSCHALTEN + NEUSTART", style = "subtle", confirm = "safe", onClick = function()
        K.set.safeMode = not K.set.safeMode K.set.crashes = {} K.save() computer.shutdown(true) end })
    UI.button({ x = jx, y = jy + 8, text = "NEU STARTEN", style = "subtle", confirm = "reboot", onClick = function() computer.shutdown(true) end })
    UI.button({ x = jx + 15, y = jy + 8, text = "AUSSCHALTEN", style = "danger", confirm = "off", onClick = function() computer.shutdown(false) end })
    -- Protokoll
    local ly = (wide and y or cy) + 15
    if ly + 4 < y + h then
        local lx, lyy, lw, lh = UI.card(x, ly, w, y + h - ly, "PROTOKOLL")
        local lines = {}
        local txt = S.read(K.ROOT .. "/data/gts.log") or ""
        for l in txt:gmatch("[^\n]+") do table.insert(lines, 1, l) end
        UI.list(A.logPage, lines, lx, lyy, lw, lh, 1, function(l, rx, ry, rw)
            local col2 = l:find(" FEHLER ") and C.bad or (l:find(" WARN ") and C.warn or C.dim)
            G.text(rx, ry, G.fit(l, rw), col2, C.card)
        end)
    end
end

function A.draw(x, y, w, h)
    local pad = (w < 100) and 1 or 2
    x, w = x + pad, w - pad * 2
    G.text(x, y + 1, "SYSTEM", C.text)
    G.text(x + 8, y + 1, "  GTS OS " .. K.VERSION .. " · OpenComputers", C.muted)
    UI.tabs(x, y + 3, w, VIEWS, A.view, function(v) A.view = v if v == "notes" then K.unread = 0 end end)
    local top = y + 5
    local hh = y + h - top
    if A.view == "info" then drawInfo(x, top, w, hh)
    elseif A.view == "check" then drawCheck(x, top, w, hh)
    elseif A.view == "settings" then drawSettings(x, top, w, hh)
    elseif A.view == "notes" then drawNotes(x, top, w, hh)
    elseif A.view == "update" then drawUpdate(x, top, w, hh)
    elseif A.view == "care" then drawCare(x, top, w, hh) end
end
function A.tick() return A.view == "info" or A.view == "update" end
return A
