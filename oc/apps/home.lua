-- GTS OS (OpenComputers) - HOME
local K, G, UI, S = ...
local computer = require("computer")
local C = G.C
local A = { page = { page = 1 } }

A.ICON = { home = "◆", drones = "◎", security = "▣", plant = "☢", storage = "▦", devices = "◫", info = "◈", notes = "≡", calc = "±",
           files = "▤", ki = "◇", shell = "›" }
A.SUB = { drones = "Drohnen & Robots", security = "Türen, Melder, Abwehr", plant = "Reaktoren & Energie", storage = "ME-Netz (AE2)",
          devices = "Geräte & Knoten", info = "Einstellungen", notes = "Merkzettel", calc = "Rechnen", files = "Dateien ansehen",
          ki = "Claude fragen", shell = "OpenOS (Admin)" }

local function greeting()
    local _, _, _, h = K.localTime()
    local g = (h < 5 and "Gute Nacht") or (h < 11 and "Guten Morgen") or (h < 18 and "Hallo") or "Guten Abend"
    if K.set.owner ~= "" then g = g .. ", " .. K.set.owner end
    return g
end

-- kleine Kennzahl-Karte mit Verlauf
local function stat(x, y, w, h, title, value, sub, color, hist)
    local ix, iy, iw = UI.card(x, y, w, h, title)
    G.text(ix, iy, G.fit(value, iw), color or C.text, C.card)
    if sub and h >= 5 then G.text(ix, iy + 1, G.fit(sub, iw), C.muted, C.card) end
    if hist and #hist >= 4 and h >= 6 then G.spark(ix, iy + 2, iw, h - 5, hist, color or C.accent, C.card, true) end
end

local function unitRow(u, x, y, w)
    local col = u.online and (u.color or C.accent) or C.muted
    G.put(x, y, "●", col, C.card)
    local name = G.fit(K.units.label(u), math.max(6, math.floor(w * 0.35)))
    G.text(x + 2, y, name, u.online and C.text or C.muted, C.card)
    local st = u.online and (u.st or "bereit") or ("offline " .. K.ago(computer.uptime() - (u.seen or 0)))
    local bx = x + math.floor(w * 0.38) + 2
    local bw = math.min(12, math.floor(w * 0.22))
    if u.online and u.e then
        G.bar(bx, y, bw, u.e, u.e < 0.25 and C.bad or (u.e < 0.5 and C.warn or C.accent), C.line)
        G.text(bx + bw + 1, y, string.format("%3d%%", math.floor(u.e * 100)), C.dim, C.card)
        G.text(bx + bw + 6, y, G.fit(st, x + w - bx - bw - 6), C.dim, C.card)
    else
        G.text(bx, y, G.fit(st, x + w - bx), C.muted, C.card)
    end
    UI.region(x, y, w, 1, function() K.open("drones", { sel = u.addr }) end)
end

function A.draw(x, y, w, h)
    local narrow = w < 100
    local pad = narrow and 1 or 2
    local cx, cw = x + pad, w - pad * 2
    -- Kopf
    G.text(cx, y + 1, greeting(), C.text)
    G.text(cx, y + 2, K.dateText() .. "  ·  " .. K.clock(), C.muted)
    local net = K.net
    local chips = {}
    chips[#chips + 1] = { net.ready and (net.aes and "● FUNK AES" or "● FUNK") or "○ FUNK AUS", net.ready and C.accent or C.bad }
    if K.set.safeMode then chips[#chips + 1] = { "SICHERER MODUS", C.warn } end
    local chx = x + w - pad
    for i = #chips, 1, -1 do
        local t = " " .. chips[i][1] .. " "
        chx = chx - G.len(t)
        G.text(chx, y + 1, t, chips[i][2], C.bg2)
        chx = chx - 1
    end
    local top = y + 4
    -- Kennzahlen
    local n, nd, nr = K.units.online()
    local total = #K.units.list
    local e = computer.energy() / math.max(1, computer.maxEnergy())
    local ram = 1 - computer.freeMemory() / math.max(1, computer.totalMemory())
    local hist = K.sys.hist
    local fleet = #K.units.fleet()
    local _, _, _, nk = K.units.online()
    local sec = K.sec and K.sec.db
    local nDev = 0
    for _, e in ipairs(K.dev.list) do if not e.infra and e.cat ~= "system" then nDev = nDev + 1 end end
    local cards = {
        { "EINHEITEN", n .. " / " .. fleet .. " online", nd .. (nd == 1 and " Drohne · " or " Drohnen · ") .. nr .. (nr == 1 and " Robot" or " Robots"), n > 0 and C.accent or C.dim, nil, "drones" },
        { "SICHERHEIT", sec and (sec.lockdown and "ABGERIEGELT" or (sec.guard.on and "SCHARF" or "Abwehr aus")) or "-",
          sec and (#sec.doors .. " Türen · " .. #sec.people .. " Personen") or "", sec and (sec.lockdown or K.sec.alarmOn) and C.bad or (sec and sec.guard.on and C.warn or C.dim), nil, "security" },
        { "VERBUND", nDev .. " Geräte", nk .. " Knoten online", C.info, nil, "devices" },
        { "ENERGIE", math.floor(e * 100) .. " %", string.format("%d / %d im Puffer", math.floor(computer.energy()), math.floor(computer.maxEnergy())), e < 0.2 and C.bad or C.info, hist.energy, "info" },
        { "ARBEITSSPEICHER", math.floor(ram * 100) .. " %", K.bytes(computer.freeMemory()) .. " frei", ram > 0.85 and C.warn or C.accent, hist.ram, "info" },
        { "FUNK", net.ready and (net.aes and "AES" or "gesiegelt") or "aus", net.ready and (net.isDefault and "Standard-Passwort!" or "Port " .. net.port) or (net.reason or ""), net.isDefault and C.warn or C.dim, nil, "info" },
    }
    local perRow = math.max(2, math.min(6, math.floor((cw + 2) / 24)))
    while #cards > perRow * 2 do table.remove(cards) end
    if h < 30 then while #cards > perRow do table.remove(cards) end end
    local ch = (h >= 40) and 8 or (h >= 28 and 5 or 4)
    -- Spalten exakt auf die Breite verteilen (der Rest geht nicht verloren)
    local function colX(i, n, gap) return cx + math.floor((i - 1) * (cw + gap) / n) end
    for i, c in ipairs(cards) do
        local col, row = (i - 1) % perRow, math.floor((i - 1) / perRow)
        local x0 = colX(col + 1, perRow, 2)
        local x1 = colX(col + 2, perRow, 2) - 2
        stat(x0, top + row * (ch + 1), x1 - x0, ch, c[1], c[2], c[3], c[4], c[5])
        if c[6] then UI.region(x0, top + row * (ch + 1), x1 - x0, ch, function() K.open(c[6]) end) end
    end
    top = top + math.ceil(#cards / perRow) * (ch + 1)
    -- App-Kacheln (unten): Anzahl Reihen vorab bestimmen
    local apps = {}
    for _, a in ipairs(K.visibleApps()) do if a.id ~= "home" and not a.hidden then apps[#apps + 1] = a end end
    local per = narrow and 4 or math.min(#apps, 6)
    local tileRows = math.ceil(#apps / math.max(1, per))
    local tilesH = (narrow or h < 30) and 3 or 5
    local tilesArea = tileRows * tilesH
    -- Schwarm + Meldungen
    local midH = y + h - top - tilesArea - 1
    if midH >= 6 then
        local leftW = narrow and cw or math.floor(cw * 0.58)
        local ix, iy, iw, ih = UI.card(cx, top, leftW, midH, "SCHWARM", { right = fleet > 0 and "ALLE ANSEHEN ▸" or nil })
        UI.region(cx + leftW - 18, top + 1, 16, 1, function() K.open("drones") end)
        local list = {}
        for _, u in ipairs(K.units.fleet()) do if not u.waiting then list[#list + 1] = u end end
        table.sort(list, function(a, b) if a.online ~= b.online then return a.online end return K.units.label(a) < K.units.label(b) end)
        if #list == 0 then
            UI.para(ix, iy + 1, iw, "Noch keine Drohnen oder Robots. In DROHNEN > EINRICHTEN eine EEPROM schreiben und eine Drohne bauen.", C.muted, ih - 1)
        else
            UI.list(A.page, list, ix, iy, iw, ih, 1, unitRow)
        end
        if not narrow then
            local rx = cx + leftW + 2
            local rw = cw - leftW - 2
            local half = math.floor(midH / 2)
            local mx, my, mw, mh = UI.card(rx, top, rw, half, "MELDUNGEN")
            if #K.notes == 0 then G.text(mx, my, "Keine Meldungen", C.muted, C.card) end
            for i, nt in ipairs(K.notes) do
                if i > mh then break end
                G.put(mx, my + i - 1, "●", K.LEVEL[nt.level] or C.info, C.card)
                G.text(mx + 2, my + i - 1, nt.clock, C.muted, C.card)
                G.text(mx + 8, my + i - 1, G.fit(nt.text, mw - 8), C.text, C.card)
            end
            UI.region(rx, top, rw, half, function() K.unread = 0 K.open("info", "notes") end)
            local vx, vy, vw, vh = UI.card(rx, top + half, rw, midH - half, "BESUCHER (SENSOREN)")
            local vis = K.units.visitors
            if #vis == 0 then G.text(vx, vy, "Noch niemand gesehen", C.muted, C.card) end
            for i, v in ipairs(vis) do
                if i > vh then break end
                G.text(vx, vy + i - 1, v.clock or "", C.muted, C.card)
                G.text(vx + 6, vy + i - 1, G.fit(v.name, 18), v.name == K.set.owner and C.accent or C.text, C.card)
                G.text(vx + 25, vy + i - 1, G.fit(v.unit or "", vw - 25), C.dim, C.card)
            end
        end
        top = top + midH + 1
    end
    -- App-Kacheln
    if midH < 6 then top = y + h - tilesArea end
    local th = math.max(3, math.min(tilesH, y + h - top))
    for i, a in ipairs(apps) do
        if i > per * math.max(1, math.floor((y + h - top) / th)) then break end
        local col, row = (i - 1) % per, math.floor((i - 1) / per)
        local tx, ty = cx + math.floor(col * (cw + 1) / per), top + row * th
        local tw = cx + math.floor((col + 1) * (cw + 1) / per) - 1 - tx
        if ty + th - 1 > y + h - 1 then break end
        UI.button({ x = tx, y = ty, w = tw, h = th, text = (A.ICON[a.id] or "•") .. "  " .. a.title,
                    sub = (not narrow and th >= 4) and A.SUB[a.id] or nil, style = "subtle", onClick = function() K.open(a.id) end })
    end
end

function A.tick() return true end
return A
