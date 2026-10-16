-- GTS OS (OpenComputers) - DROHNEN: Zentrale fuer Drohnen und Robots
local K, G, UI, S = ...
local computer = require("computer")
local C = G.C
local U = K.units
local A = { view = "list", sel = nil, listPage = { page = 1 }, visPage = { page = 1 }, ptPage = { page = 1 },
            logPage = { page = 1 }, chPage = { page = 1 }, filter = "alle", mapScale = nil, reconN = 0 }
local COLORS = { 0x3DDC84, 0x4C9AFF, 0x2EC4B6, 0xFF9F43, 0xA78BFA, 0xF472B6, 0xFF5A5F, 0xF5D547, 0xE7EAF0 }
local VIEWS = { { id = "list", text = "ÜBERSICHT" }, { id = "map", text = "KARTE" }, { id = "recon", text = "AUFKLÄRUNG" },
                { id = "chargers", text = "LADEN" }, { id = "points", text = "PUNKTE" }, { id = "visitors", text = "BESUCHER" },
                { id = "setup", text = "EINRICHTEN" } }

function A.enter(arg)
    if type(arg) == "table" and arg.sel then A.sel = arg.sel A.view = "list" end
end

local function units()
    local out = {}
    for _, u in ipairs(U.fleet()) do
        if not u.waiting and (A.filter == "alle" or (A.filter == "drohnen" and u.kind ~= "robot") or (A.filter == "robots" and u.kind == "robot")
            or (A.filter == "online" and u.online)) then out[#out + 1] = u end
    end
    table.sort(out, function(a, b) if a.online ~= b.online then return a.online end return U.label(a) < U.label(b) end)
    return out
end
local function selected() return A.sel and U.byAddr[A.sel] end
local function pct(v) return v and (math.floor(v * 100) .. " %") or "-" end
local function eColor(e) return (not e and C.muted) or (e < 0.25 and C.bad) or (e < 0.5 and C.warn) or C.accent end
-- Position: Weltkoordinaten, wenn die Ladestation bekannt ist, sonst relativ zum Startplatz
local function posText(u)
    if u.x == nil then return "unbekannt" end
    local wx, wy, wz = U.toWorld(u)
    if wx then return string.format("%d, %d, %d", wx, wy, wz) end
    return string.format("%d, %d, %d (relativ)", math.floor(u.x), math.floor(u.y), math.floor(u.z))
end
local TASK = { idle = "frei", ["goto"] = "fliegt", home = "heim", patrol = "Patrouille", guard = "Wache", courier = "Kurier",
               charge = "lädt", dig = "baut ab", scan = "scannt", unload = "lädt ab", recon = "Aufklärung" }
-- Punkt (Welt oder relativ) -> Koordinaten der Einheit
local function localPoint(u, p)
    if p.w then
        local x, y, z = U.toLocal(u, p.x, p.y, p.z)
        if not x then return nil end
        return { x = x, y = y, z = z }
    end
    return { x = p.x, y = p.y, z = p.z }
end

-- ---------------------------------------------------------------------
-- Eingaben
-- ---------------------------------------------------------------------
local function askXYZ(title, cb, def, u)
    local world = u and U.homeOf(u) ~= nil
    UI.prompt({ title = title, text = def or "", hint = world and "x y z in Weltkoordinaten (F3), z.B. 120 70 -340" or "x y z relativ zum Startplatz, z.B. 10 5 -20",
                validate = function(t)
                    local x, y, z = t:match("^%s*(%-?%d+)[%s,]+(%-?%d+)[%s,]+(%-?%d+)%s*$")
                    if not x then return "Drei Zahlen: x y z" end
                end,
                onOk = function(t)
                    local x, y, z = t:match("^%s*(%-?%d+)[%s,]+(%-?%d+)[%s,]+(%-?%d+)%s*$")
                    x, y, z = tonumber(x), tonumber(y), tonumber(z)
                    local label = x .. "," .. y .. "," .. z
                    if world then x, y, z = U.toLocal(u, x, y, z) end
                    cb(x, y, z, label)
                end })
end
local function pickPoint(title, cb)
    local pts = U.db.points
    if #pts == 0 then K.notify("Erst Wegpunkte anlegen (WEGPUNKTE)", "warn") return end
    A.picker = { title = title, cb = cb }
end

-- Aktionen je Art: die wichtigsten als Knoepfe, der Rest unter MEHR
local function chargerMenu(u)
    local items = {}
    for _, c in ipairs(U.db.chargers) do
        items[#items + 1] = { text = (u.charger == c.id and "✓  " or "○  ") .. c.name, sub = c.x .. " " .. c.y .. " " .. c.z, onClick = function()
            u.charger = c.id U.remember(u) K.notify(U.label(u) .. " startet an " .. c.name, "ok")
        end }
    end
    if #items == 0 then K.notify("Erst unter LADEN eine Ladestation eintragen", "warn") A.view = "chargers" return end
    UI.menu("Wo startet " .. U.label(u) .. "?", items)
end
local function actions(u)
    local main, more = {}, {}
    local function add(list, text, style, fn, confirm) list[#list + 1] = { text = text, style = style, onClick = fn, confirm = confirm } end
    add(main, "HEIM", "secondary", function() U.cmd(u.addr, "home", {}, "heim") end)
    add(main, "STOP", "secondary", function() U.cmd(u.addr, "stop", {}, "stop") end)
    add(main, "ZIEL", "secondary", function()
        askXYZ(u.kind == "robot" and "Robot fährt zu" or "Drohne fliegt zu", function(x, y, z, label)
            U.cmd(u.addr, "goto", { x = x, y = y, z = z }, "Ziel " .. label)
        end, nil, u)
    end)
    if u.kind == "robot" then
        add(main, "ABBAUEN", "primary", function()
            UI.prompt({ title = "Abbauen: Breite Länge Tiefe", text = "5 5 3", hint = "ab dem Feld vor dem Robot: nach vorn, nach rechts, nach unten",
                        validate = function(t) if not t:match("^%s*%d+%s+%d+%s+%d+%s*$") then return "Drei Zahlen" end end,
                        onOk = function(t)
                            local w, l, d = t:match("(%d+)%s+(%d+)%s+(%d+)")
                            U.cmd(u.addr, "dig", { w = tonumber(w), l = tonumber(l), d = tonumber(d) }, "abbauen " .. t)
                        end })
        end)
        add(more, "SCAN (Geolyzer)", nil, function() U.cmd(u.addr, "scan", { r = 2 }, "scan") end)
        add(more, "ABLADEN", nil, function() U.cmd(u.addr, "unload", {}, "abladen") end)
    else
        add(main, "PATROUILLE", "primary", function()
            local pts = {}
            for _, p in ipairs(U.db.points) do local lp = localPoint(u, p) if lp then pts[#pts + 1] = lp end end
            if #pts < 2 then K.notify("Mindestens 2 Wegpunkte anlegen (PUNKTE)", "warn") return end
            U.cmd(u.addr, "patrol", { points = pts, loop = true }, "Patrouille (" .. #pts .. " Punkte)")
        end)
        add(more, "WACHE (hier bleiben)", nil, function()
            if u.x then U.cmd(u.addr, "guard", { x = math.floor(u.x), y = math.floor(u.y), z = math.floor(u.z) }, "Wache hier")
            else askXYZ("Wache halten bei", function(x, y, z) U.cmd(u.addr, "guard", { x = x, y = y, z = z }, "Wache") end, nil, u) end
        end)
        add(more, "KURIER (Punkt A → B)", nil, function()
            pickPoint("Kurier: Abholen bei", function(a)
                pickPoint("Kurier: Bringen nach", function(b)
                    local la, lb = localPoint(u, a), localPoint(u, b)
                    if not la or not lb then K.notify("Ladestation der Drohne unbekannt", "warn") return end
                    U.cmd(u.addr, "courier", { from = la, to = lb, rounds = 1 }, "Kurier " .. a.name .. " → " .. b.name)
                end)
            end)
        end)
        if u.cl then add(more, "CHUNKLOADER " .. (u.chunkOn and "AUS" or "AN"), nil, function() u.chunkOn = not u.chunkOn U.cmd(u.addr, "chunk", { on = u.chunkOn }, "Chunkloader " .. (u.chunkOn and "an" or "aus")) end) end
        add(more, "LADESTATION (Start)", nil, function() chargerMenu(u) end)
    end
    add(more, "NAME", nil, function()
        UI.prompt({ title = "Name", text = u.name or "", maxLen = 16, onOk = function(t)
            u.name = (t ~= "") and t or nil
            U.remember(u)
            if u.online then U.cmd(u.addr, "name", { name = t }, "Name") end
        end })
    end)
    add(more, "FARBE WECHSELN", nil, function()
        local i = 1
        for k, c in ipairs(COLORS) do if c == u.color then i = k % #COLORS + 1 end end
        u.color = COLORS[i]
        U.remember(u)
        if u.online then U.cmd(u.addr, "light", { c = u.color }, "Licht") end
    end)
    add(more, "PIEPEN (finden)", nil, function() U.cmd(u.addr, "ping", {}, "piep") end)
    add(more, "NEU STARTEN", nil, function() U.cmd(u.addr, "restart", {}, "neu starten") end, "re-" .. u.addr)
    add(more, "VERGESSEN", "danger", function() U.forget(u.addr) A.sel = nil end, "fg-" .. u.addr)
    for _, b in ipairs(more) do
        local t = b.text
        if not u.online and t ~= "VERGESSEN" and t ~= "NAME" and t ~= "FARBE WECHSELN" and t ~= "LADESTATION (Start)" then b.disabled = true end
    end
    return main, more
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
    local compact = ih < 24          -- kleiner Bildschirm: weniger Zeilen, flache Knoepfe
    G.put(ix, iy, "●", u.online and (u.color or C.accent) or C.muted, C.card)
    G.text(ix + 2, iy, G.fit(U.label(u), iw - 22), C.text, C.card)
    G.right(ix + iw - 1, iy, (u.online and "ONLINE" or "OFFLINE") .. "  " .. ((u.kind == "robot") and "ROBOT" or "DROHNE"), u.online and C.accent or C.muted, C.card)
    G.text(ix + 2, iy + 1, u.addr:sub(1, 8) .. " · Programm " .. tostring(u.v or "-") .. (u.secure and " · AES" or " · gesiegelt"), C.muted, C.card)
    local yy = iy + (compact and 2 or 3)
    -- Akku mit Verlauf
    G.text(ix, yy, "AKKU", C.muted, C.card)
    G.bar(ix + 10, yy, iw - 18, u.e or 0, eColor(u.e), C.line)
    G.right(ix + iw - 1, yy, pct(u.e) .. (u.charging and " ⚡" or ""), C.text, C.card)
    yy = yy + 1
    if u.hist and #u.hist > 2 and ih > 26 then
        G.spark(ix + 10, yy, iw - 18, 2, u.hist, eColor(u.e), C.card, true)
        yy = yy + 2
    end
    if not compact then yy = yy + 1 end
    local kw = 14
    UI.kv(ix, yy, iw, "Status", u.online and (u.busy and ("wartet: " .. u.busy) or (u.st or "-")) or "offline", nil, kw) yy = yy + 1
    if not compact then UI.kv(ix, yy, iw, "Auftrag", TASK[u.task] or tostring(u.task or "-"), nil, kw) yy = yy + 1 end
    UI.kv(ix, yy, iw, "Position", posText(u) .. (u.nav and "  (Navigation)" or ""), nil, kw) yy = yy + 1
    if u.kind ~= "robot" then
        local c = u.charger and U.charger(u.charger) or (#U.db.chargers == 1 and U.db.chargers[1])
        UI.kv(ix, yy, iw, "Ladestation", c and (c.name .. "  (" .. c.x .. " " .. c.y .. " " .. c.z .. ")") or "unbekannt - unter MEHR wählen", c and C.dim or C.warn, kw) yy = yy + 1
    end
    if not compact then UI.kv(ix, yy, iw, "Funk", u.dist and (math.floor(u.dist) .. " Blöcke") or "-", (u.dist or 0) > 350 and C.warn or nil, kw) yy = yy + 1 end
    if u.kind == "robot" then
        UI.kv(ix, yy, iw, "Inventar", (u.inv or 0) .. " / " .. (u.invMax or "?") .. " Plätze · " .. tostring(u.mined or 0) .. " abgebaut"
            .. (u.progress and (" · Ebene " .. u.progress.layer .. "/" .. u.progress.of) or ""), nil, kw) yy = yy + 1
    elseif not compact then
        UI.kv(ix, yy, iw, "Inventar", tostring(u.inv or 0) .. " Items", nil, kw) yy = yy + 1
    end
    if not compact then
        local caps = {}
        if u.nav then caps[#caps + 1] = "Navigation" end
        if u.ms then caps[#caps + 1] = "Bewegungssensor" end
        if u.cl then caps[#caps + 1] = "Chunkloader" end
        if u.geo then caps[#caps + 1] = "Geolyzer" end
        if u.aes then caps[#caps + 1] = "AES" end
        UI.kv(ix, yy, iw, "Ausstattung", #caps > 0 and table.concat(caps, " · ") or "Grundausstattung", C.dim, kw) yy = yy + 1
    end
    yy = yy + 1
    -- Knoepfe: wenige grosse, der Rest unter MEHR
    local main, more = actions(u)
    main[#main + 1] = { text = "MEHR …", style = "subtle", onClick = function() UI.menu(U.label(u), more) end }
    local bh = compact and 1 or 3
    local bx, by = ix, yy
    for _, b in ipairs(main) do
        local bw = UI.btnW(b.text) + (compact and 0 or 2)
        if bx + bw > ix + iw then bx, by = ix, by + bh + 1 end
        if by + bh - 1 > iy + ih - 1 then break end
        b.x, b.y, b.w, b.h = bx, by, bw, bh
        if not u.online and b.text ~= "MEHR …" then b.disabled = true end
        UI.button(b)
        bx = bx + bw + (compact and 1 or 2)
    end
    -- Verlauf
    local ly = by + bh + 1
    if ly < iy + ih - 1 then
        G.text(ix, ly, "VERLAUF", C.muted, C.card)
        for i, e in ipairs(u.log) do
            if ly + i > iy + ih - 1 then break end
            G.text(ix, ly + i, e.c, C.muted, C.card)
            G.text(ix + 6, ly + i, G.fit(e.text, iw - 6), C.dim, C.card)
        end
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
            { text = "ALLE HEIM", style = "secondary", onClick = function() U.cmdMany(U.fleet(), "home", nil, "heim") end },
            { text = "ALLE STOP", style = "danger", confirm = "allstop", onClick = function() U.cmdMany(U.fleet(), "stop", nil, "stop") end },
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

-- Karte: von oben. Mit Ladestationen in Weltkoordinaten, sonst relativ zum Startplatz
local function drawMap(x, y, w, h)
    local world = U.worldMode()
    local b = U.base()
    local ix, iy, iw, ih = UI.card(x, y, w, h, world and ("KARTE (von oben, Mitte " .. b.x .. " / " .. b.z .. ")") or "KARTE (von oben, ⌂ = Startplatz)",
                                   { right = "MASSSTAB " .. (A.mapScale or "AUTO") })
    local pts = {}
    for _, u in ipairs(U.fleet()) do
        if u.x then
            local wx, _, wz = U.toWorld(u)
            if world and wx then pts[#pts + 1] = { x = wx - b.x, z = wz - b.z, u = u }
            elseif not world then pts[#pts + 1] = { x = u.x, z = u.z, u = u } end
        end
    end
    for _, p in ipairs(U.db.points) do
        if world and p.w then pts[#pts + 1] = { x = p.x - b.x, z = p.z - b.z, p = p }
        elseif not world and not p.w then pts[#pts + 1] = { x = p.x, z = p.z, p = p } end
    end
    if world then for _, c in ipairs(U.db.chargers) do pts[#pts + 1] = { x = c.x - b.x, z = c.z - b.z, c = c } end end
    local now = K.realMs()
    for _, v in ipairs(U.visitors) do
        if now - (v.t or 0) < 600000 then
            if world and v.wx then pts[#pts + 1] = { x = v.wx - b.x, z = v.wz - b.z, v = v }
            elseif not world and v.x then pts[#pts + 1] = { x = v.x, z = v.z, v = v } end
        end
    end
    local route
    if world then
        local active = false
        for _, u in ipairs(U.fleet()) do if u.online and u.task == "recon" then active = true end end
        if active then route = U.reconRoute(U.db.recon.r, U.db.recon.h, U.db.recon.shape) end
    end
    local maxD = 8
    for _, p in ipairs(pts) do maxD = math.max(maxD, math.abs(p.x), math.abs(p.z) * 2) end
    if route then maxD = math.max(maxD, U.db.recon.r * 2 + 4) end
    local scale = A.mapScale or math.max(1, math.ceil(maxD * 1.1 / (iw / 2)))
    local cx, cy = ix + math.floor(iw / 2), iy + math.floor((ih - 1) / 2)
    for gx = ix, ix + iw - 1 do
        for gy = iy, iy + ih - 2 do
            local wx = (gx - cx) * scale
            local wz = (gy - cy) * scale * 2
            if (wx % 16 < scale) and (wz % 16 < scale * 2) then G.put(gx, gy, "·", C.line, C.card) end
        end
    end
    local function plot(p, glyph, col, label)
        local px = cx + math.floor(p.x / scale + 0.5)
        local py = cy + math.floor(p.z / scale / 2 + 0.5)
        if px >= ix and px < ix + iw and py >= iy and py < iy + ih - 1 then
            G.put(px, py, glyph, col, C.card)
            if label and px + 2 + G.len(label) < ix + iw then G.text(px + 2, py, label, C.dim, C.card) end
            return px, py
        end
    end
    if route then for _, p in ipairs(route) do plot({ x = p.x - b.x, z = p.z - b.z }, "∘", C.info) end end
    G.put(cx, cy, world and "+" or "⌂", C.text, C.card)
    for _, p in ipairs(pts) do
        if p.p then plot(p, "◇", C.info, G.fit(p.p.name, 10)) end
        if p.c then plot(p, "⚡", C.warn, G.fit(p.c.name, 10)) end
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
        local dx = (ix + rx - 1 - cx) * scale
        local dz = (iy + ry - 1 - cy) * scale * 2
        local tx, ty, tz, label
        if world then
            local wx, wy = U.toWorld(u)
            if not wx then K.notify("Ladestation von " .. U.label(u) .. " unbekannt (MEHR > LADESTATION)", "warn") return end
            tx, ty, tz = U.toLocal(u, b.x + dx, wy, b.z + dz)
            label = (b.x + dx) .. ", " .. wy .. ", " .. (b.z + dz)
        else
            tx, ty, tz = dx, math.floor(u.y or 0), dz
            label = tx .. ", " .. ty .. ", " .. tz
        end
        UI.ask("Hierhin?", U.label(u) .. " nach " .. label .. " schicken?", function()
            U.cmd(u.addr, "goto", { x = tx, y = ty, z = tz }, "Ziel " .. label)
        end, "LOS")
    end)
    local legend = "1 Zeichen = " .. scale .. " Bl.  ● Drohne ■ Robot ⚡ Laden ◇ Punkt ✕ Besucher"
    G.text(ix, iy + ih - 1, G.fit(legend, iw - 22), C.muted, C.card)
    UI.buttonsRight({
        { text = "−", w = 3, style = "subtle", onClick = function() A.mapScale = math.min(256, (A.mapScale or scale) * 2) end },
        { text = "+", w = 3, style = "subtle", onClick = function() A.mapScale = math.max(1, math.floor((A.mapScale or scale) / 2)) end },
        { text = "AUTO", style = "subtle", onClick = function() A.mapScale = nil end },
    }, iy + ih - 1, ix + iw - 1)
end

local function parsePoint(t)
    local n, px, py, pz = t:match("^%s*(.-)%s+(%-?%d+)[%s,]+(%-?%d+)[%s,]+(%-?%d+)%s*$")
    return n, tonumber(px), tonumber(py), tonumber(pz)
end
local function drawPoints(x, y, w, h)
    local world = U.worldMode()
    local ix, iy, iw, ih = UI.card(x, y, w, h, world and "WEGPUNKTE (Weltkoordinaten, für Patrouille und Kurier)" or "WEGPUNKTE (relativ zum Startplatz)")
    UI.row({
        { text = "+ NEU", style = "primary", onClick = function()
            UI.prompt({ title = "Wegpunkt: Name x y z", hint = world and "z.B. Tor 120 70 -340 (F3)" or "z.B. Tor 12 4 -30",
                        validate = function(t) if not parsePoint(t) then return "Name und drei Zahlen" end end,
                        onOk = function(t)
                            local n, px, py, pz = parsePoint(t)
                            U.db.points[#U.db.points + 1] = { name = n, x = px, y = py, z = pz, w = world or nil }
                            U.save()
                        end })
        end },
        { text = "+ HIER (gewählte Einheit)", style = "secondary", onClick = function()
            local u = selected()
            if not u or not u.x then K.notify("Keine Einheit mit Position gewählt", "warn") return end
            local wx, wy, wz = U.toWorld(u)
            UI.prompt({ title = "Name für den Punkt", text = "Punkt " .. (#U.db.points + 1), onOk = function(t)
                if world and wx then U.db.points[#U.db.points + 1] = { name = t, x = wx, y = wy, z = wz, w = true }
                else U.db.points[#U.db.points + 1] = { name = t, x = math.floor(u.x), y = math.floor(u.y), z = math.floor(u.z) } end
                U.save()
            end })
        end },
    }, ix, iy, 2)
    local pts = U.db.points
    if #pts == 0 then UI.para(ix, iy + 2, iw, "Noch keine Wegpunkte. Patrouillen fliegen die Punkte der Reihe nach ab.", C.muted) return end
    UI.list(A.ptPage, pts, ix, iy + 2, iw, ih - 2, 1, function(p, rx, ry, rw, i)
        G.text(rx, ry, string.format("%2d", i), C.muted, C.card)
        G.text(rx + 4, ry, G.fit(p.name, 20), C.text, C.card)
        G.text(rx + 26, ry, string.format("%d, %d, %d", p.x, p.y, p.z) .. (p.w and "" or "  (relativ)"), C.dim, C.card)
        UI.buttonsRight({
            { text = "▲", w = 3, style = "subtle", disabled = i == 1, onClick = function() pts[i], pts[i - 1] = pts[i - 1], pts[i] U.save() end },
            { text = "LÖSCHEN", style = "subtle", onClick = function() table.remove(pts, i) U.save() end },
        }, ry, rx + rw - 1)
    end)
end

-- Ladestationen (Weltkoordinaten) ---------------------------------------------
local function drawChargers(x, y, w, h)
    local wide = w >= 110
    local lw = wide and math.floor(w * 0.55) or w
    local list = U.db.chargers
    local lh = wide and h or math.max(8, h - 12)
    local ix, iy, iw, ih = UI.card(x, y, lw, lh, #list .. " LADESTATIONEN")
    UI.button({ x = ix + iw - 10, y = iy - 1, w = 10, text = "+ NEU", style = "primary", onClick = function()
        UI.prompt({ title = "Ladestation: Name x y z", hint = "Koordinaten des Chargers (F3, Block anschauen), z.B. Dach 120 64 -340",
                    validate = function(t) if not parsePoint(t) then return "Name und drei Zahlen" end end,
                    onOk = function(t) local n, px, py, pz = parsePoint(t) U.addCharger(n, px, py, pz) end })
    end })
    if #list == 0 then
        UI.para(ix, iy + 1, iw, "Trag deine Charger mit Koordinaten ein: Dann zeigt GTS OS Weltkoordinaten, schickt Drohnen mit leerem Akku zur nächsten freien Station und kann Aufklärungsflüge um die Basis planen.", C.muted)
    else
        UI.list(A.chPage, list, ix, iy + 1, iw, ih - 1, 2, function(c, rx, ry, rw, i)
            local n = 0
            for _, u in ipairs(U.fleet()) do if u.charger == c.id or (#list == 1 and u.kind == "drone") then n = n + 1 end end
            local busy
            for _, u in ipairs(U.fleet()) do if u.charging and u.chargeAt == c.id then busy = U.label(u) end end
            G.put(rx, ry, "⚡", C.warn, C.card)
            G.text(rx + 2, ry, G.fit(c.name, rw - 14), C.text, C.card)
            G.text(rx + 2, ry + 1, G.fit(c.x .. " " .. c.y .. " " .. c.z .. "  ·  " .. n .. " Drohne(n) starten hier" .. (busy and ("  ·  lädt: " .. busy) or ""), rw - 14), C.dim, C.card)
            UI.button({ x = rx + rw - 10, y = ry, w = 10, text = "LÖSCHEN", style = "subtle", confirm = "cd" .. c.id, onClick = function()
                table.remove(list, i) U.save()
            end })
        end)
    end
    local tx, ty, tw, th
    if wide then tx, ty, tw, th = UI.card(x + lw + 2, y, w - lw - 2, h, "SO GEHT'S")
    else tx, ty, tw, th = UI.card(x, y + lh + 1, w, h - lh - 1, "SO GEHT'S") end
    local yy = ty
    for _, t in ipairs({
        "• Die Drohne steht beim Start direkt über ihrem Charger. Wo sie startet, legst du bei mehreren Stationen in der ÜBERSICHT unter MEHR > LADESTATION fest.",
        "• Wird der Akku knapp, schickt GTS OS sie zur nächsten freien Station und danach zurück an die Arbeit.",
        "• Charger brauchen ein Redstone-Signal und Strom.",
    }) do yy = UI.para(tx, yy, tw, t, C.dim) + 1 end
    local b = U.base()
    if b and yy + 2 < ty + th then
        G.text(tx, yy, "Basis-Mitte: " .. b.x .. " " .. b.y .. " " .. b.z .. (U.db.base and "" or "  (= erste Station)"), C.text, C.card)
        UI.button({ x = tx, y = yy + 1, text = "MITTE ÄNDERN", style = "subtle", onClick = function()
            UI.prompt({ title = "Basis-Mitte x y z (leer = erste Station)", maxLen = 30, onOk = function(t)
                local bx, by, bz = t:match("^%s*(%-?%d+)[%s,]+(%-?%d+)[%s,]+(%-?%d+)%s*$")
                U.db.base = bx and { x = tonumber(bx), y = tonumber(by), z = tonumber(bz) } or nil
                U.save()
            end })
        end })
    end
end

-- Aufklaerung ---------------------------------------------------------------
local function drawRecon(x, y, w, h)
    local rc = U.db.recon
    A.rr = A.rr or rc.r or 32
    A.rh = A.rh or rc.h or 12
    A.rs = A.rs or rc.shape or "ring"
    local wide = w >= 110
    local lw = wide and math.floor(w * 0.5) or w
    local ix, iy, iw, ih = UI.card(x, y, lw, wide and h or math.min(h, 18), "AUFKLÄRUNG UM DIE BASIS")
    local b = U.base()
    if not b then
        UI.para(ix, iy + 1, iw, "Dafür muss GTS OS wissen, wo die Basis ist: Unter LADEN mindestens eine Ladestation mit Koordinaten eintragen.", C.warn)
        UI.button({ x = ix, y = iy + 4, text = "ZU DEN LADESTATIONEN", style = "primary", onClick = function() A.view = "chargers" end })
        return
    end
    local yy = UI.para(ix, iy, iw, "Drohnen fliegen im Kreis (oder Rechteck) um die Basis-Mitte. Mit Bewegungssensor melden sie jeden Spieler - Fremde landen bei SICHERHEIT.", C.dim) + 1
    G.text(ix, yy, "Radius", C.muted, C.card)
    local cx = ix + 12
    for _, r in ipairs({ 16, 32, 48, 64, 96, 128 }) do cx = UI.chip(cx, yy, r .. "", A.rr == r, function() A.rr = r end) + 1 end
    UI.chip(cx, yy, "…", false, function()
        UI.prompt({ title = "Radius in Blöcken (8-400)", text = tostring(A.rr), numeric = true, onOk = function(t) A.rr = math.max(8, math.min(400, tonumber(t) or 32)) end })
    end)
    yy = yy + 2
    G.text(ix, yy, "Höhe", C.muted, C.card)
    cx = ix + 12
    for _, hh in ipairs({ 6, 12, 20, 32 }) do cx = UI.chip(cx, yy, "+" .. hh, A.rh == hh, function() A.rh = hh end) + 1 end
    yy = yy + 2
    G.text(ix, yy, "Form", C.muted, C.card)
    cx = ix + 12
    cx = UI.chip(cx, yy, "KREIS", A.rs == "ring", function() A.rs = "ring" end) + 1
    UI.chip(cx, yy, "RECHTECK", A.rs == "rechteck", function() A.rs = "rechteck" end)
    yy = yy + 2
    local free, onRecon = {}, {}
    for _, u in ipairs(U.fleet()) do
        if u.online and u.kind == "drone" then
            if u.task == "recon" then onRecon[#onRecon + 1] = u else free[#free + 1] = u end
        end
    end
    G.text(ix, yy, "Drohnen", C.muted, C.card)
    cx = ix + 12
    local avail = #free + #onRecon
    cx = UI.chip(cx, yy, "ALLE (" .. avail .. ")", A.reconN == 0, function() A.reconN = 0 end) + 1
    for k = 1, math.min(3, avail) do cx = UI.chip(cx, yy, k .. "", A.reconN == k, function() A.reconN = k end) + 1 end
    yy = yy + 2
    local pts = U.reconRoute(A.rr, A.rh, A.rs) or {}
    local len = 0
    for i = 1, #pts do local p, q = pts[i], pts[i % #pts + 1] len = len + math.sqrt((p.x - q.x) ^ 2 + (p.z - q.z) ^ 2) end
    G.text(ix, yy, G.fit("Rundweg " .. math.floor(len) .. " Blöcke · " .. #pts .. " Punkte · Mitte " .. b.x .. " " .. b.z, iw), C.dim, C.card)
    yy = yy + 2
    UI.row({
        { text = "STARTEN", style = "primary", onClick = function()
            local list = {}
            for _, u in ipairs(onRecon) do list[#list + 1] = u end
            for _, u in ipairs(free) do list[#list + 1] = u end
            if A.reconN > 0 then while #list > A.reconN do table.remove(list) end end
            local n, err = U.startRecon(list, A.rr, A.rh, A.rs)
            K.notify(n > 0 and ("Aufklärung: " .. n .. " Drohne(n) unterwegs") or err, n > 0 and "ok" or "warn")
        end },
        { text = "BEENDEN", style = "secondary", disabled = #onRecon == 0, onClick = function() U.cmdMany(onRecon, "home", nil, "heim") end },
    }, ix, yy, 2)
    -- Vorschau
    local px, py, pw, ph
    if wide then px, py, pw, ph = UI.card(x + lw + 2, y, w - lw - 2, h, "VORSCHAU")
    else
        if y + 19 + 6 > y + h then return end
        px, py, pw, ph = UI.card(x, y + 19, w, h - 19, "VORSCHAU")
    end
    local scale = math.max(1, math.ceil((A.rr * 2 + 8) / pw))
    local mx, my = px + math.floor(pw / 2), py + math.floor(ph / 2)
    for _, p in ipairs(pts) do
        local qx, qy = mx + math.floor((p.x - b.x) / scale + 0.5), my + math.floor((p.z - b.z) / scale / 2 + 0.5)
        if qx >= px and qx < px + pw and qy >= py and qy < py + ph then G.put(qx, qy, "∘", C.info, C.card) end
    end
    G.put(mx, my, "+", C.text, C.card)
    for _, u in ipairs(U.fleet()) do
        local wx, _, wz = U.toWorld(u)
        if wx and u.online then
            local qx, qy = mx + math.floor((wx - b.x) / scale + 0.5), my + math.floor((wz - b.z) / scale / 2 + 0.5)
            if qx >= px and qx < px + pw and qy >= py and qy < py + ph then G.put(qx, qy, "●", u.color or C.accent, C.card) end
        end
    end
    G.text(px, py + ph - 1, "1 Zeichen = " .. scale .. " Bl.", C.muted, C.card)
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
    local tall = h >= 34
    A.setupTab = A.setupTab or "drohne"
    if not wide and not tall then
        -- kleiner Bildschirm: eine Karte, Umschalter oben
        local cx = x
        cx = UI.chip(cx, y, "DROHNE", A.setupTab == "drohne", function() A.setupTab = "drohne" end) + 1
        UI.chip(cx, y, "ROBOT", A.setupTab == "robot", function() A.setupTab = "robot" end)
        y, h = y + 2, h - 2
    end
    local showDrone = wide or tall or A.setupTab == "drohne"
    local showRobot = wide or tall or A.setupTab == "robot"
    local cw = wide and math.floor((w - 2) / 2) or w
    local dh = (wide or not tall) and h or math.floor(h * 0.55)
    if showDrone then
        local ix, iy, iw, ih = UI.card(x, y, cw, dh, "DROHNE IN DEN SCHWARM")
        local yy = iy
        for _, t in ipairs({
            "1  Drohne bauen: Wireless-Karte Tier 2, Data Card (Tier 2 = AES), CPU, RAM. Upgrades nach Wunsch: Bewegungssensor, Navigation, Chunkloader, Inventar.",
            "2  Eine LEERE EEPROM hier einstecken (die BIOS-EEPROM vorher herausnehmen).",
            "3  GTS-LADER SCHREIBEN, EEPROM raus, BIOS wieder rein. EEPROM in den Assembler zur Drohne.",
            "4  Drohne über ihren Charger setzen (Charger braucht Redstone) - sie meldet sich hier.",
        }) do yy = UI.para(ix, yy, iw, t, C.dim, math.max(1, iy + ih - 6 - yy)) end
        local ee = require("component").isAvailable("eeprom") and require("component").eeprom
        local label = ee and ee.getLabel() or "keine"
        local isBios = U.isBios()
        local by = math.max(yy + 1, iy + ih - 5)
        G.text(ix, by, "EEPROM im Rechner: ", C.muted, C.card)
        G.text(ix + 19, by, G.fit(label, iw - 19), isBios and C.warn or C.text, C.card)
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
        }, ix, by + 2, 2)
        G.text(ix, iy + ih - 1, "Neue automatisch annehmen", C.dim, C.card)
        UI.toggle(ix + iw - 10, iy + ih - 1, K.set.autoAccept, function() K.setting("autoAccept", not K.set.autoAccept) end)
    end
    if showRobot then
        local rx, ry, rw, rh
        if wide then rx, ry, rw, rh = UI.card(x + cw + 2, y, w - cw - 2, h, "ROBOT IN DEN SCHWARM")
        elseif tall then rx, ry, rw, rh = UI.card(x, y + dh + 1, w, h - dh - 1, "ROBOT IN DEN SCHWARM")
        else rx, ry, rw, rh = UI.card(x, y, w, h, "ROBOT IN DEN SCHWARM") end
        local yy2 = ry
        for _, t in ipairs({
            "1  Robot mit Festplatte (OpenOS), Wireless-Karte und Data Card; für Scans ein Geolyzer.",
            "2  Am Robot:  wget -f https://raw.githubusercontent.com/Jonsixx101/gts-os/main/install.lua /tmp/i.lua  dann  /tmp/i.lua",
            "3  Schwarm-Passwort eingeben (wie hier). Zu Hause: auf einer Kiste, neben einem Charger.",
        }) do yy2 = UI.para(rx, yy2, rw, t, C.dim, math.max(1, ry + rh - 2 - yy2)) end
        yy2 = yy2 + 1
        local waiting = {}
        for _, u in ipairs(U.list) do if u.waiting then waiting[#waiting + 1] = u end end
        if #waiting > 0 and yy2 < ry + rh - 1 then
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
    G.text(x, y + 1, "DROHNEN", C.text)
    local n, nd, nr = U.online()
    G.text(x + 8, y + 1, "  " .. n .. " online · " .. nd .. (nd == 1 and " Drohne · " or " Drohnen · ") .. nr .. (nr == 1 and " Robot" or " Robots"), C.muted)
    UI.tabs(x, y + 3, w, VIEWS, A.view, function(v) A.view = v A.picker = nil end)
    local top = y + 5
    local hh = y + h - top
    A.narrow = w < 100
    if A.picker then drawPicker(x, top, w, hh) return end
    if A.view == "list" then drawList(x, top, w, hh)
    elseif A.view == "map" then drawMap(x, top, w, hh)
    elseif A.view == "recon" then drawRecon(x, top, w, hh)
    elseif A.view == "chargers" then drawChargers(x, top, w, hh)
    elseif A.view == "points" then drawPoints(x, top, w, hh)
    elseif A.view == "visitors" then drawVisitors(x, top, w, hh)
    elseif A.view == "setup" then drawSetup(x, top, w, hh) end
end
function A.tick() return true end
return A
