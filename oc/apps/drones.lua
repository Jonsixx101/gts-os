-- GTS OS (OpenComputers) - DROHNEN: Zentrale fuer Drohnen und Robots
local K, G, UI, S = ...
local computer = require("computer")
local C = G.C
local U = K.units
local A = { view = "list", sel = nil, listPage = { page = 1 }, visPage = { page = 1 }, ptPage = { page = 1 },
            logPage = { page = 1 }, filter = "alle", mapScale = nil }
local COLORS = { 0x3DDC84, 0x4C9AFF, 0x2EC4B6, 0xFF9F43, 0xA78BFA, 0xF472B6, 0xFF5A5F, 0xF5D547, 0xE7EAF0 }
local VIEWS = { { id = "list", text = "ÜBERSICHT" }, { id = "map", text = "KARTE" }, { id = "points", text = "WEGPUNKTE" },
                { id = "visitors", text = "BESUCHER" }, { id = "setup", text = "EINRICHTEN" } }

function A.enter(arg)
    if type(arg) == "table" and arg.sel then A.sel = arg.sel A.view = "list" end
end

local function units()
    local out = {}
    for _, u in ipairs(U.list) do
        if not u.waiting and (A.filter == "alle" or (A.filter == "drohnen" and u.kind ~= "robot") or (A.filter == "robots" and u.kind == "robot")
            or (A.filter == "online" and u.online)) then out[#out + 1] = u end
    end
    table.sort(out, function(a, b) if a.online ~= b.online then return a.online end return U.label(a) < U.label(b) end)
    return out
end
local function selected() return A.sel and U.byAddr[A.sel] end
local function pct(v) return v and (math.floor(v * 100) .. " %") or "-" end
local function eColor(e) return (not e and C.muted) or (e < 0.25 and C.bad) or (e < 0.5 and C.warn) or C.accent end
local function posText(u)
    if u.x == nil then return "unbekannt" end
    return string.format("%d, %d, %d", math.floor(u.x), math.floor(u.y), math.floor(u.z))
end
local TASK = { idle = "frei", ["goto"] = "fliegt", home = "heim", patrol = "Patrouille", guard = "Wache", courier = "Kurier",
               charge = "lädt", dig = "baut ab", scan = "scannt", unload = "lädt ab" }

-- ---------------------------------------------------------------------
-- Eingaben
-- ---------------------------------------------------------------------
local function askXYZ(title, cb, def)
    UI.prompt({ title = title, text = def or "", hint = "x y z relativ zum Startplatz, z.B. 10 5 -20",
                validate = function(t)
                    local x, y, z = t:match("^%s*(%-?%d+)[%s,]+(%-?%d+)[%s,]+(%-?%d+)%s*$")
                    if not x then return "Drei Zahlen: x y z" end
                end,
                onOk = function(t)
                    local x, y, z = t:match("^%s*(%-?%d+)[%s,]+(%-?%d+)[%s,]+(%-?%d+)%s*$")
                    cb(tonumber(x), tonumber(y), tonumber(z))
                end })
end
local function pickPoint(title, cb)
    local pts = U.db.points
    if #pts == 0 then K.notify("Erst Wegpunkte anlegen (WEGPUNKTE)", "warn") return end
    A.picker = { title = title, cb = cb }
end

-- Aktionen je Art
local function actions(u)
    local list = {}
    local function add(text, style, fn, confirm) list[#list + 1] = { text = text, style = style, onClick = fn, confirm = confirm } end
    if u.kind == "robot" then
        add("HEIM", "secondary", function() U.cmd(u.addr, "home", {}, "heim") end)
        add("STOP", "secondary", function() U.cmd(u.addr, "stop", {}, "stop") end)
        add("ZIEL", "secondary", function() askXYZ("Robot fährt zu", function(x, y, z) U.cmd(u.addr, "goto", { x = x, y = y, z = z }, "Ziel " .. x .. "," .. y .. "," .. z) end) end)
        add("ABBAUEN", "primary", function()
            UI.prompt({ title = "Abbauen: Breite Länge Tiefe", text = "5 5 3", hint = "ab dem Feld vor dem Robot: nach vorn, nach rechts, nach unten",
                        validate = function(t) if not t:match("^%s*%d+%s+%d+%s+%d+%s*$") then return "Drei Zahlen" end end,
                        onOk = function(t)
                            local w, l, d = t:match("(%d+)%s+(%d+)%s+(%d+)")
                            U.cmd(u.addr, "dig", { w = tonumber(w), l = tonumber(l), d = tonumber(d) }, "abbauen " .. t)
                        end })
        end)
        add("SCAN", "secondary", function() U.cmd(u.addr, "scan", { r = 2 }, "scan") end)
        add("ABLADEN", "secondary", function() U.cmd(u.addr, "unload", {}, "abladen") end)
    else
        add("HEIM", "secondary", function() U.cmd(u.addr, "home", {}, "heim") end)
        add("STOP", "secondary", function() U.cmd(u.addr, "stop", {}, "stop") end)
        add("ZIEL", "secondary", function() askXYZ("Drohne fliegt zu", function(x, y, z) U.cmd(u.addr, "goto", { x = x, y = y, z = z }, "Ziel " .. x .. "," .. y .. "," .. z) end) end)
        add("PATROUILLE", "primary", function()
            local pts = {}
            for _, p in ipairs(U.db.points) do pts[#pts + 1] = { x = p.x, y = p.y, z = p.z } end
            if #pts < 2 then K.notify("Mindestens 2 Wegpunkte anlegen (WEGPUNKTE)", "warn") return end
            U.cmd(u.addr, "patrol", { points = pts, loop = true }, "Patrouille (" .. #pts .. " Punkte)")
        end)
        add("WACHE", "secondary", function()
            if u.x then U.cmd(u.addr, "guard", { x = math.floor(u.x), y = math.floor(u.y), z = math.floor(u.z) }, "Wache hier")
            else askXYZ("Wache halten bei", function(x, y, z) U.cmd(u.addr, "guard", { x = x, y = y, z = z }, "Wache") end) end
        end)
        add("KURIER", "secondary", function()
            pickPoint("Kurier: Abholen bei", function(a)
                pickPoint("Kurier: Bringen nach", function(b)
                    U.cmd(u.addr, "courier", { from = { x = a.x, y = a.y, z = a.z }, to = { x = b.x, y = b.y, z = b.z }, rounds = 1 },
                          "Kurier " .. a.name .. " → " .. b.name)
                end)
            end)
        end)
        if u.cl then add("CHUNK", "secondary", function() u.chunkOn = not u.chunkOn U.cmd(u.addr, "chunk", { on = u.chunkOn }, "Chunkloader " .. (u.chunkOn and "an" or "aus")) end) end
    end
    add("NAME", "subtle", function()
        UI.prompt({ title = "Name", text = u.name or "", maxLen = 16, onOk = function(t)
            u.name = (t ~= "") and t or nil
            U.remember(u)
            U.cmd(u.addr, "name", { name = t }, "Name")
        end })
    end)
    add("FARBE", "subtle", function()
        local i = 1
        for k, c in ipairs(COLORS) do if c == u.color then i = k % #COLORS + 1 end end
        u.color = COLORS[i]
        U.remember(u)
        if u.online then U.cmd(u.addr, "light", { c = u.color }, "Licht") end
    end)
    add("PIEP", "subtle", function() U.cmd(u.addr, "ping", {}, "piep") end)
    add("NEU STARTEN", "subtle", function() U.cmd(u.addr, "restart", {}, "neu starten") end, "re-" .. u.addr)
    add("VERGESSEN", "danger", function() U.forget(u.addr) A.sel = nil end, "fg-" .. u.addr)
    return list
end

-- ---------------------------------------------------------------------
-- Ansichten
-- ---------------------------------------------------------------------
local function drawRow(u, x, y, w)
    local sel = A.sel == u.addr
    local b = sel and C.raised or C.card
    G.fill(x - 1, y, w + 2, 2, b)
    if sel then G.put(x - 1, y, "▍", C.accent, b) G.put(x - 1, y + 1, "▍", C.accent, b) end
    G.put(x + 1, y, "●", u.online and (u.color or C.accent) or C.muted, b)
    G.text(x + 3, y, G.fit(U.label(u), w - 14), u.online and C.text or C.muted, b)
    G.right(x + w - 1, y, (u.kind == "robot") and "ROBOT" or "DROHNE", C.muted, b)
    local st = u.online and (u.busy and ("… " .. u.busy) or (u.st or TASK[u.task] or "bereit")) or ("offline · " .. K.ago(computer.uptime() - (u.seen or 0)))
    if u.online and u.e then
        G.bar(x + 3, y + 1, 8, u.e, eColor(u.e), C.line)
        G.text(x + 12, y + 1, string.format("%3d%%", math.floor(u.e * 100)), C.dim, b)
        G.text(x + 17, y + 1, G.fit(st, w - 18), C.dim, b)
    else
        G.text(x + 3, y + 1, G.fit(st, w - 4), C.muted, b)
    end
    UI.region(x - 1, y, w + 2, 2, function() A.sel = u.addr A.detail = true end)
end

local function drawDetail(u, x, y, w, h)
    local ix, iy, iw, ih = UI.card(x, y, w, h, nil)
    G.put(ix, iy, "●", u.online and (u.color or C.accent) or C.muted, C.card)
    G.text(ix + 2, iy, G.fit(U.label(u), iw - 22), C.text, C.card)
    G.right(ix + iw - 1, iy, (u.online and "ONLINE" or "OFFLINE") .. "  " .. ((u.kind == "robot") and "ROBOT" or "DROHNE"), u.online and C.accent or C.muted, C.card)
    G.text(ix + 2, iy + 1, u.addr:sub(1, 8) .. " · Programm " .. tostring(u.v or "-") .. (u.secure and " · AES" or " · gesiegelt"), C.muted, C.card)
    local yy = iy + 3
    -- Akku mit Verlauf
    G.text(ix, yy, "AKKU", C.muted, C.card)
    G.bar(ix + 10, yy, iw - 18, u.e or 0, eColor(u.e), C.line)
    G.right(ix + iw - 1, yy, pct(u.e) .. (u.charging and " ⚡" or ""), C.text, C.card)
    yy = yy + 1
    if u.hist and #u.hist > 2 and ih > 22 then
        G.spark(ix + 10, yy, iw - 18, 2, u.hist, eColor(u.e), C.card, true)
        yy = yy + 2
    end
    yy = yy + 1
    local kw = 14
    UI.kv(ix, yy, iw, "Status", u.online and (u.busy and ("wartet: " .. u.busy) or (u.st or "-")) or "offline", nil, kw) yy = yy + 1
    UI.kv(ix, yy, iw, "Auftrag", TASK[u.task] or tostring(u.task or "-"), nil, kw) yy = yy + 1
    UI.kv(ix, yy, iw, "Position", posText(u) .. (u.nav and "  (Navigation)" or ""), nil, kw) yy = yy + 1
    UI.kv(ix, yy, iw, "Funk", u.dist and (math.floor(u.dist) .. " Blöcke") or "-", (u.dist or 0) > 350 and C.warn or nil, kw) yy = yy + 1
    if u.kind == "robot" then
        UI.kv(ix, yy, iw, "Inventar", (u.inv or 0) .. " / " .. (u.invMax or "?") .. " Plätze", nil, kw) yy = yy + 1
        UI.kv(ix, yy, iw, "Abgebaut", tostring(u.mined or 0) .. " Blöcke" .. (u.progress and (" · Ebene " .. u.progress.layer .. "/" .. u.progress.of) or ""), nil, kw) yy = yy + 1
    else
        UI.kv(ix, yy, iw, "Inventar", tostring(u.inv or 0) .. " Items", nil, kw) yy = yy + 1
    end
    local caps = {}
    if u.nav then caps[#caps + 1] = "Navigation" end
    if u.ms then caps[#caps + 1] = "Bewegungssensor" end
    if u.cl then caps[#caps + 1] = "Chunkloader" end
    if u.geo then caps[#caps + 1] = "Geolyzer" end
    if u.aes then caps[#caps + 1] = "AES" end
    UI.kv(ix, yy, iw, "Ausstattung", #caps > 0 and table.concat(caps, " · ") or "Grundausstattung", C.dim, kw) yy = yy + 2
    -- Knoepfe
    local acts = actions(u)
    local bx, by = ix, yy
    for _, b in ipairs(acts) do
        local bw = UI.btnW(b.text)
        if bx + bw > ix + iw then bx, by = ix, by + 2 end
        if by > iy + ih - 6 then break end
        b.x, b.y, b.disabled = bx, by, (not u.online and b.text ~= "VERGESSEN" and b.text ~= "NAME" and b.text ~= "FARBE")
        UI.button(b)
        bx = bx + bw + 1
    end
    -- Verlauf
    local ly = by + 2
    if ly < iy + ih - 1 then
        G.text(ix, ly, "VERLAUF", C.muted, C.card)
        for i, e in ipairs(u.log) do
            if ly + i > iy + ih - 1 then break end
            G.text(ix, ly + i, e.c, C.muted, C.card)
            G.text(ix + 6, ly + i, G.fit(e.text, iw - 6), C.dim, C.card)
        end
    end
    -- Scan-Treffer (Robot mit Geolyzer)
    if u.scan and #u.scan > 0 and not A.narrow then
        -- (im Verlauf vermerkt; Liste in WEGPUNKTE uebernehmbar)
    end
end

local function drawList(x, y, w, h)
    -- Filter + Sammelbefehle
    local fx = x
    for _, f in ipairs({ { "alle", "ALLE" }, { "online", "ONLINE" }, { "drohnen", "DROHNEN" }, { "robots", "ROBOTS" } }) do
        fx = UI.chip(fx, y, f[2], A.filter == f[1], function() A.filter = f[1] A.listPage.page = 1 end) + 1
    end
    local n = U.online()
    if n > 0 and w > 60 then
        UI.buttonsRight({
            { text = "ALLE HEIM", style = "secondary", onClick = function() U.cmdMany(U.list, "home", nil, "heim") end },
            { text = "ALLE STOP", style = "danger", confirm = "allstop", onClick = function() U.cmdMany(U.list, "stop", nil, "stop") end },
        }, y, x + w - 1, fx + 2)
    end
    y = y + 2
    h = h - 2
    local list = units()
    local wide = w >= 110
    local lw = wide and math.floor(w * 0.42) or w
    if not wide and A.detail and selected() then
        UI.button({ x = x, y = y, text = "◀ LISTE", style = "ghost", onClick = function() A.detail = false end })
        drawDetail(selected(), x, y + 1, w, h - 1)
        return
    end
    local ix, iy, iw, ih = UI.card(x, y, lw, h, #list .. " EINHEITEN")
    if #list == 0 then
        UI.para(ix, iy + 1, iw, "Keine Einheiten. EINRICHTEN zeigt, wie eine Drohne oder ein Robot in den Schwarm kommt.", C.muted)
    else
        UI.list(A.listPage, list, ix, iy, iw, ih, 2, drawRow)
    end
    if wide then
        local u = selected() or list[1]
        if u then A.sel = u.addr drawDetail(u, x + lw + 2, y, w - lw - 2, h)
        else UI.card(x + lw + 2, y, w - lw - 2, h, nil) end
    end
end

-- Karte: von oben, Startplatz in der Mitte
local function drawMap(x, y, w, h)
    local ix, iy, iw, ih = UI.card(x, y, w, h, "KARTE (von oben, ⌂ = Startplatz)", { right = "MASSSTAB " .. (A.mapScale or "AUTO") })
    local pts = {}
    for _, u in ipairs(U.list) do if u.x then pts[#pts + 1] = { x = u.x, z = u.z, u = u } end end
    for _, p in ipairs(U.db.points) do pts[#pts + 1] = { x = p.x, z = p.z, p = p } end
    local now = K.realMs()
    for _, v in ipairs(U.visitors) do
        if v.x and now - (v.t or 0) < 600000 then pts[#pts + 1] = { x = v.x, z = v.z, v = v } end
    end
    local maxD = 8
    for _, p in ipairs(pts) do maxD = math.max(maxD, math.abs(p.x), math.abs(p.z) * 2) end
    local scale = A.mapScale or math.max(1, math.ceil(maxD * 1.1 / (iw / 2)))
    local cx, cy = ix + math.floor(iw / 2), iy + math.floor((ih - 1) / 2)
    -- Raster alle 16 Bloecke (Chunks)
    for gx = ix, ix + iw - 1 do
        for gy = iy, iy + ih - 2 do
            local wx = (gx - cx) * scale
            local wz = (gy - cy) * scale * 2
            if (wx % 16 < scale) and (wz % 16 < scale * 2) then G.put(gx, gy, "·", C.line, C.card) end
        end
    end
    G.put(cx, cy, "⌂", C.text, C.card)
    local function plot(p, glyph, col, label)
        local px = cx + math.floor(p.x / scale + 0.5)
        local py = cy + math.floor(p.z / scale / 2 + 0.5)
        if px >= ix and px < ix + iw and py >= iy and py < iy + ih - 1 then
            G.put(px, py, glyph, col, C.card)
            if label and px + 2 + G.len(label) < ix + iw then G.text(px + 2, py, label, C.dim, C.card) end
            return px, py
        end
    end
    for _, p in ipairs(pts) do
        if p.p then plot(p, "◇", C.info, G.fit(p.p.name, 10)) end
        if p.v then plot(p, "✕", C.bad, G.fit(p.v.name, 10)) end
    end
    for _, p in ipairs(pts) do
        if p.u then
            local u = p.u
            local px, py = plot(p, u.kind == "robot" and "■" or "●", u.online and (u.color or C.accent) or C.muted, G.fit(U.label(u), 12))
            if px then UI.region(px, py, 1, 1, function() A.sel = u.addr A.view = "list" A.detail = true end) end
        end
    end
    -- Antippen: ausgewaehlte Drohne dorthin
    UI.region(ix, iy, iw, ih - 1, function(rx, ry)
        local u = selected()
        if not u or not u.online then K.notify("Erst in der ÜBERSICHT eine Einheit wählen", "info") return end
        local wx = (ix + rx - 1 - cx) * scale
        local wz = (iy + ry - 1 - cy) * scale * 2
        local wy = math.floor(u.y or 0)
        UI.ask("Hierhin?", U.label(u) .. " nach " .. wx .. ", " .. wy .. ", " .. wz .. " schicken?", function()
            U.cmd(u.addr, "goto", { x = wx, y = wy, z = wz }, "Ziel " .. wx .. "," .. wy .. "," .. wz)
        end, "LOS")
    end)
    local legend = "1 Zeichen = " .. scale .. " Bl.   ● Drohne  ■ Robot  ◇ Wegpunkt  ✕ Besucher (10 min)"
    G.text(ix, iy + ih - 1, G.fit(legend, iw - 22), C.muted, C.card)
    UI.buttonsRight({
        { text = "−", w = 3, style = "subtle", onClick = function() A.mapScale = math.min(256, (A.mapScale or scale) * 2) end },
        { text = "+", w = 3, style = "subtle", onClick = function() A.mapScale = math.max(1, math.floor((A.mapScale or scale) / 2)) end },
        { text = "AUTO", style = "subtle", onClick = function() A.mapScale = nil end },
    }, iy + ih - 1, ix + iw - 1)
end

local function drawPoints(x, y, w, h)
    local ix, iy, iw, ih = UI.card(x, y, w, h, "WEGPUNKTE (für Patrouille und Kurier, relativ zum Startplatz)")
    UI.row({
        { text = "+ NEU", style = "primary", onClick = function()
            UI.prompt({ title = "Wegpunkt: Name x y z", hint = "z.B. Tor 12 4 -30",
                        validate = function(t) if not t:match("^%s*(.-)%s+(%-?%d+)%s+(%-?%d+)%s+(%-?%d+)%s*$") then return "Name und drei Zahlen" end end,
                        onOk = function(t)
                            local n, px, py, pz = t:match("^%s*(.-)%s+(%-?%d+)%s+(%-?%d+)%s+(%-?%d+)%s*$")
                            U.addPoint(n, tonumber(px), tonumber(py), tonumber(pz))
                        end })
        end },
        { text = "+ HIER (gewählte Einheit)", style = "secondary", onClick = function()
            local u = selected()
            if not u or not u.x then K.notify("Keine Einheit mit Position gewählt", "warn") return end
            UI.prompt({ title = "Name für den Punkt", text = "Punkt " .. (#U.db.points + 1), onOk = function(t)
                U.addPoint(t, math.floor(u.x), math.floor(u.y), math.floor(u.z))
            end })
        end },
    }, ix, iy)
    local pts = U.db.points
    if #pts == 0 then UI.para(ix, iy + 2, iw, "Noch keine Wegpunkte. Patrouillen fliegen die Punkte der Reihe nach ab.", C.muted) return end
    UI.list(A.ptPage, pts, ix, iy + 2, iw, ih - 2, 1, function(p, rx, ry, rw, i)
        G.text(rx, ry, string.format("%2d", i), C.muted, C.card)
        G.text(rx + 4, ry, G.fit(p.name, 20), C.text, C.card)
        G.text(rx + 26, ry, string.format("%d, %d, %d", p.x, p.y, p.z), C.dim, C.card)
        UI.buttonsRight({
            { text = "▲", w = 3, style = "subtle", disabled = i == 1, onClick = function() pts[i], pts[i - 1] = pts[i - 1], pts[i] U.save() end },
            { text = "LÖSCHEN", style = "subtle", onClick = function() table.remove(pts, i) U.save() end },
        }, ry, rx + rw - 1)
    end)
end

local function drawVisitors(x, y, w, h)
    local ix, iy, iw, ih = UI.card(x, y, w, h, "BESUCHER-LOG (Bewegungssensoren der Drohnen)", { right = #U.visitors .. " Einträge" })
    if #U.visitors == 0 then
        UI.para(ix, iy + 1, iw, "Noch keine Einträge. Eine Drohne mit Bewegungssensor (Upgrade Tier 2) meldet jeden, der sich in 8 Blöcken Abstand bewegt - mit Namen.", C.muted)
        return
    end
    G.text(ix, iy, "ZEIT", C.muted, C.card) G.text(ix + 7, iy, "NAME", C.muted, C.card)
    G.text(ix + 28, iy, "GESEHEN VON", C.muted, C.card) G.text(ix + 50, iy, "ORT", C.muted, C.card)
    UI.list(A.visPage, U.visitors, ix, iy + 1, iw, ih - 1, 1, function(v, rx, ry, rw)
        local trusted = v.name == K.set.owner
        for _, t in ipairs(K.set.trusted or {}) do if t:lower() == v.name:lower() then trusted = true end end
        G.text(rx, ry, v.clock or "", C.muted, C.card)
        G.text(rx + 7, ry, G.fit(v.name, 20), trusted and C.accent or C.text, C.card)
        G.text(rx + 28, ry, G.fit(v.unit or "", 20), C.dim, C.card)
        if v.x then G.text(rx + 50, ry, string.format("%d, %d, %d", v.x, v.y or 0, v.z), C.dim, C.card) end
        if not trusted and rw > 75 and v.name ~= "?" then
            UI.button({ x = rx + rw - 12, y = ry, w = 12, text = "VERTRAUEN", style = "subtle", onClick = function()
                local t = K.set.trusted or {}
                t[#t + 1] = v.name
                K.setting("trusted", t)
            end })
        end
    end)
end

local function drawSetup(x, y, w, h)
    local wide = w >= 110
    local cw = wide and math.floor((w - 2) / 2) or w
    -- Drohne
    local ix, iy, iw, ih = UI.card(x, y, cw, wide and h or math.floor(h * 0.55), "DROHNE IN DEN SCHWARM")
    local steps = {
        "1  Drohne bauen (Drohnen-Gehäuse Tier 2): Wireless-Karte Tier 2 + Data Card (Tier 2 für AES), CPU, RAM. Upgrades nach Wunsch: Chunkloader, Bewegungssensor, Navigation, Inventar.",
        "2  Eine LEERE EEPROM in diesen Computer stecken (die Lua-BIOS-EEPROM vorher herausnehmen und aufheben).",
        "3  GTS-LADER SCHREIBEN antippen, EEPROM herausnehmen, BIOS wieder einsetzen.",
        "4  EEPROM in den Assembler zur Drohne, Drohne neben einen Charger setzen (Charger braucht ein Redstone-Signal). Sie meldet sich hier von selbst.",
    }
    local yy = iy
    for _, s in ipairs(steps) do yy = UI.para(ix, yy, iw, s, C.dim) + 0 end
    yy = yy + 1
    local ee = require("component").isAvailable("eeprom") and require("component").eeprom
    local label = ee and ee.getLabel() or "keine"
    local isBios = U.isBios()
    G.text(ix, yy, "EEPROM im Rechner: ", C.muted, C.card)
    G.text(ix + 19, yy, G.fit(label, iw - 19), isBios and C.warn or C.text, C.card)
    yy = yy + 2
    UI.row({
        { text = "GTS-LADER SCHREIBEN", style = isBios and "warn" or "primary", confirm = isBios and "flashbios" or nil,
          confirmText = "DAS IST DAS BIOS! TROTZDEM?", disabled = not ee or not K.net.ready, onClick = function()
            UI.prompt({ title = "Name der Drohne (optional)", maxLen = 16, onOk = function(name)
                local ok, err = U.flash(name)
                K.notify(ok and "EEPROM beschrieben - jetzt herausnehmen" or ("Fehler: " .. tostring(err)), ok and "ok" or "bad")
            end })
        end },
        { text = "LUA BIOS ZURÜCK", style = "subtle", disabled = not ee, confirm = "restorebios", onClick = function()
            local ok, err = U.restoreBios()
            K.notify(ok and "Lua BIOS geschrieben" or ("Fehler: " .. tostring(err)), ok and "ok" or "bad")
        end },
    }, ix, yy)
    yy = yy + 2
    G.text(ix, yy, "Neue Einheiten automatisch annehmen", C.dim, C.card)
    UI.toggle(ix + iw - 10, yy, K.set.autoAccept, function() K.setting("autoAccept", not K.set.autoAccept) end)
    -- Robot + Wartende
    local rx, ry, rw, rh
    if wide then rx, ry, rw, rh = UI.card(x + cw + 2, y, w - cw - 2, h, "ROBOT IN DEN SCHWARM")
    else rx, ry, rw, rh = UI.card(x, y + math.floor(h * 0.55) + 1, w, h - math.floor(h * 0.55) - 1, "ROBOT IN DEN SCHWARM") end
    local yy2 = ry
    for _, s in ipairs({
        "1  Robot mit Festplatte (OpenOS), Wireless-Karte und Data Card bauen; für Scans einen Geolyzer.",
        "2  Am Robot: wget -f " .. "https://raw.githubusercontent.com/Jonsixx101/gts-os/main/install.lua /tmp/i.lua" .. "  dann  /tmp/i.lua",
        "3  Das Schwarm-Passwort eingeben (wie hier). Der Robot startet neu und meldet sich hier.",
        "Zu Hause steht der Robot auf einer Kiste (Abladen nach unten) und neben einem Charger.",
    }) do yy2 = UI.para(rx, yy2, rw, s, C.dim) end
    yy2 = yy2 + 1
    local waiting = {}
    for _, u in ipairs(U.list) do if u.waiting then waiting[#waiting + 1] = u end end
    if #waiting > 0 then
        G.text(rx, yy2, "WARTEN AUF FREIGABE", C.warn, C.card)
        for i, u in ipairs(waiting) do
            local wy = yy2 + i
            if wy > ry + rh - 1 then break end
            G.text(rx, wy, G.fit(U.label(u) .. "  " .. u.addr:sub(1, 8), rw - 24), C.text, C.card)
            UI.buttonsRight({ { text = "ANNEHMEN", style = "primary", onClick = function() U.accept(u.addr) end },
                              { text = "X", w = 3, style = "subtle", onClick = function() U.forget(u.addr) end } }, wy, rx + rw - 1)
        end
    end
    if not K.net.ready then G.text(rx, ry + rh - 1, "Funk aus: " .. tostring(K.net.reason), C.bad, C.card) end
end

local function drawPicker(x, y, w, h)
    local pk = A.picker
    local ix, iy, iw, ih = UI.card(x, y, w, h, pk.title)
    for i, p in ipairs(U.db.points) do
        if i > ih - 2 then break end
        UI.button({ x = ix, y = iy + i - 1, w = iw, text = p.name .. "   (" .. p.x .. ", " .. p.y .. ", " .. p.z .. ")", style = "subtle", align = "left",
                    onClick = function() A.picker = nil pk.cb(p) end })
    end
    UI.button({ x = ix, y = iy + ih - 1, text = "ABBRECHEN", style = "ghost", onClick = function() A.picker = nil end })
end

function A.draw(x, y, w, h)
    local pad = (w < 100) and 1 or 2
    x, w = x + pad, w - pad * 2
    G.text(x, y + 1, "DROHNENZENTRALE", C.text)
    local n, nd, nr = U.online()
    G.text(x + 17, y + 1, "  " .. n .. " online · " .. nd .. (nd == 1 and " Drohne · " or " Drohnen · ") .. nr .. (nr == 1 and " Robot" or " Robots"), C.muted)
    UI.tabs(x, y + 3, w, VIEWS, A.view, function(v) A.view = v A.picker = nil end)
    local top = y + 5
    local hh = y + h - top
    A.narrow = w < 100
    if A.picker then drawPicker(x, top, w, hh) return end
    if A.view == "list" then drawList(x, top, w, hh)
    elseif A.view == "map" then drawMap(x, top, w, hh)
    elseif A.view == "points" then drawPoints(x, top, w, hh)
    elseif A.view == "visitors" then drawVisitors(x, top, w, hh)
    elseif A.view == "setup" then drawSetup(x, top, w, hh) end
end
function A.tick() return true end
return A
