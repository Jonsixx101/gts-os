-- GTS OS (OpenComputers) - SCHIFF: WarpDrive-Bruecke, Sprung, Radar, Erkundung, Tarnung
local K, G, UI, S = ...
local computer = require("computer")
local C = G.C
if not K.warp then
    K.warp = K.lib("warp")(K, S)
    K.spawn("schiff", K.warp.service)
end
local W = K.warp
local db = W.db
local A = { view = nil, mode = "rel", mv = { front = 0, up = 0, right = 0, rot = 0 }, tgt = nil, sel = nil, zoom = 1,
            filter = "alle", tPage = { page = 1 }, cPage = { page = 1 }, rPage = { page = 1 }, hPage = { page = 1 },
            lPage = { page = 1 } }
local ROT = { { 0, "KEINE" }, { 1, "90° ↻" }, { 2, "180°" }, { 3, "90° ↺" } }
local GLYPH = { ship = "●", warp_echo = "○", planet = "◉", star = "✶", structure = "▪", jumpgate = "◎", transporter = "◇" }

-- ---------------------------------------------------------------------
-- Hilfen
-- ---------------------------------------------------------------------
local function num(n)
    n = math.floor(tonumber(n) or 0)
    local s = tostring(math.abs(n)):reverse():gsub("(%d%d%d)", "%1."):reverse():gsub("^%.", "")
    return (n < 0 and "-" or "") .. s
end
local function pos(x, y, z)
    if not x then return "unbekannt" end
    return num(x) .. "  " .. num(y) .. "  " .. num(z)
end
local function has()
    return { ship = W.ship() ~= nil, radar = W.radar() ~= nil, cloak = W.cloak() ~= nil }
end
local function views(hv)
    local v = {}
    if hv.ship then v[#v + 1] = { id = "bridge", text = "BRÜCKE" } v[#v + 1] = { id = "jump", text = "SPRUNG" } end
    if hv.radar then v[#v + 1] = { id = "radar", text = "RADAR" } v[#v + 1] = { id = "contacts", text = "KONTAKTE" } end
    if hv.ship then v[#v + 1] = { id = "survey", text = "ERKUNDUNG" } end
    if hv.cloak then v[#v + 1] = { id = "cloak", text = "TARNUNG" } end
    return v
end
local function bg(fn, name)
    K.spawn(name or "schiff-aufgabe", function()
        local ok, err = pcall(fn)
        if not ok then K.notify("Schiff: " .. tostring(err), "bad") K.log("FEHLER", "schiff: " .. tostring(err)) end
        K.dirty = true
    end)
end

function A.enter(arg)
    W.open = true
    local hv = has()
    if type(arg) == "string" then A.view = arg end
    if not A.view then A.view = hv.ship and "bridge" or (hv.radar and "radar" or "cloak") end
    bg(function()
        if hv.ship then W.refresh(true) end
        if hv.radar then W.radarInfo(db.radius) end
        if hv.cloak then W.cloakInfo() end
    end, "schiff-lesen")
end
function A.leave() W.open = false end
function A.unload() W.open = false end

-- aktuelle Bewegung (vorn, hoch, rechts, Drehung) je nach Eingabeart
local function curMove()
    local st = W.st
    if A.mode ~= "rel" and A.tgt and st and st.x then
        local f, r = W.toLocal(A.tgt.x - st.x, A.tgt.z - st.z, st)
        return f, A.tgt.y - st.y, r, A.mv.rot
    end
    return A.mv.front, A.mv.up, A.mv.right, A.mv.rot
end
local function planFresh()
    local p = W.lastPlan
    if not p then return nil end
    local f, u, r, rot = curMove()
    if p.front == f and p.up == u and p.right == r and p.rot == rot and computer.uptime() - p.t < 90 then return p end
end
local function replan()
    if A.planning then return end
    A.planning = true
    A.edited = nil
    local f, u, r, rot = curMove()
    K.spawn("sprungplan", function()
        local ok, err = pcall(W.plan, f, u, r, rot)
        A.planning = false
        if not ok then K.notify("Berechnung: " .. tostring(err), "bad") end
        K.dirty = true
    end)
end
local function edited() A.edited = computer.uptime() end

local function startCountdown(kind, text, p)
    local go = function() A.count = { untilT = computer.uptime() + 5, kind = kind, text = text, p = p } end
    if K.set.jumpAdmin then K.askAdmin("Admin-Code für den Sprung", go) else go() end
end
local function fire()
    local c = A.count
    A.count = nil
    local ok, err
    if c.kind == "HYPERDRIVE" then ok, err = W.jump("HYPERDRIVE")
    else ok, err = W.jump("MANUAL", c.p.front, c.p.up, c.p.right, c.p.rot) end
    if ok then
        A.jumping = { t = computer.uptime(), x = W.st and W.st.x, z = W.st and W.st.z, y = W.st and W.st.y }
        K.notify(c.kind == "HYPERDRIVE" and "Hyperantrieb aktiviert" or "Sprung eingeleitet - Schiff wärmt auf", "ok")
    else
        K.notify("Sprung abgelehnt: " .. tostring(err), "bad")
    end
end
local function setTargetFromContact(c)
    local st, ri = W.st, W.rinfo
    if not st or not st.x or not ri or not ri.ux then K.notify("Erst Schiff und Radar lesen lassen", "warn") return end
    local dx, dz = c.x - math.floor(ri.ux), c.z - math.floor(ri.uz)
    local d = math.sqrt(dx * dx + dz * dz)
    local keep = 150
    local f = d > keep and (d - keep) / d or 0
    A.tgt = { x = st.x + math.floor(dx * f), y = st.y, z = st.z + math.floor(dz * f) }
    A.mode = "abs"
    A.view = "jump"
    edited()
    K.notify("Kurs gesetzt: 150 Bl. vor " .. (c.name ~= "" and c.name or W.typeName(c.type)), "info")
end

-- ---------------------------------------------------------------------
-- BRUECKE
-- ---------------------------------------------------------------------
local function status(st)
    if not st then return "● LESE DATEN …", C.muted end
    if db.survey and db.survey.active then return "● ERKUNDUNG", C.info end
    if A.jumping then return "● SPRUNG LÄUFT", C.warn end
    if not st.valid then return "● NICHT BEREIT", C.bad end
    return "● BEREIT", C.accent
end
local function placeText(st)
    if st.hyper then return "Hyperraum" end
    if st.space then return "Weltraum" end
    return "Planet / Atmosphäre"
end
local function quickActions(x, y, w, st)
    local list = {
        { text = "SPRUNG PLANEN ▸", style = "primary", onClick = function() A.view = "jump" end },
        { text = "NAME", style = "secondary", onClick = function()
            UI.prompt({ title = "Schiffsname", text = st and st.name or "", maxLen = 24, onOk = function(t) bg(function() W.rename(t) end) end })
        end },
    }
    if st and (st.space or st.hyper) then
        list[#list + 1] = { text = st.hyper and "HYPERRAUM VERLASSEN" or "HYPERRAUM", style = "secondary", confirm = "hyper",
                            onClick = function() startCountdown("HYPERDRIVE", st.hyper and "zurück in den Normalraum" or "in den Hyperraum") end }
    end
    list[#list + 1] = { text = "NOTSTOPP", style = "danger", onClick = function()
        A.count = nil
        W.surveyStop()
        bg(W.abort)
        K.notify("Sprung und Erkundung gestoppt", "warn")
    end }
    UI.row(list, x, y)
end

local function drawHistory(x, y, w, h)
    local ix, iy, iw, ih = UI.card(x, y, w, h, "LETZTE SPRÜNGE", { right = #db.history .. "" })
    if #db.history == 0 then G.text(ix, iy, "Noch keine Sprünge mit GTS OS", C.muted, C.card) return end
    local list = {}
    for i = #db.history, 1, -1 do list[#list + 1] = db.history[i] end
    UI.list(A.hPage, list, ix, iy, iw, ih, 1, function(j, rx, ry, rw)
        G.text(rx, ry, j.clock or "", C.muted, C.card)
        if j.kind == "HYPERDRIVE" then
            G.text(rx + 7, ry, "HYPERRAUM", C.info, C.card)
        else
            G.text(rx + 7, ry, G.fit(string.format("vorn %s · hoch %s · rechts %s%s", num(j.f), num(j.u), num(j.r),
                (j.rot or 0) > 0 and (" · Drehung " .. (j.rot * 90) .. "°") or ""), rw - 32), C.text, C.card)
            if j.to then G.right(rx + rw - 1, ry, "→ " .. pos(j.to[1], j.to[2], j.to[3]), C.dim, C.card) end
        end
    end)
end

local function drawEnergy(x, y, w, h, st)
    local frac = (st and st.energyMax > 0) and st.energy / st.energyMax or 0
    local col = frac < 0.2 and C.bad or (frac < 0.5 and C.warn or C.info)
    local ix, iy, iw, ih = UI.card(x, y, w, h, "ENERGIE", { right = st and (W.fmt(st.energy) .. " / " .. W.fmt(st.energyMax) .. " EU") or "" })
    local pct = tostring(math.floor(frac * 100))
    local ex = G.big(ix, iy, pct, C.text, C.card)
    G.text(ex + 1, iy + 2, "%", C.dim, C.card)
    G.bar(ex + 4, iy + 1, ix + iw - ex - 4, frac, col, C.line)
    local plan = W.lastPlan
    if plan and plan.energy then
        G.text(ex + 4, iy + 2, G.fit("letzter Plan braucht " .. W.fmt(plan.energy) .. " EU", ix + iw - ex - 4), C.muted, C.card)
    end
    if ih >= 6 and #W.hist >= 4 then G.spark(ix, iy + 4, iw, ih - 4, W.hist, col, C.card, true)
    elseif ih >= 6 then G.text(ix, iy + 4, "Verlauf: sammle Messwerte …", C.muted, C.card) end
end

local function drawRadarSummary(x, y, w, h, hv)
    local ix, iy, iw, ih = UI.card(x, y, w, h, "RADAR")
    if not hv.radar then UI.para(ix, iy, iw, "Kein Radar angeschlossen. Ein WarpDrive-Radar per Kabel anschließen - dann gibt es hier Kontakte und Erkundungsflüge.", C.muted, ih) return end
    local sc = W.scan
    local last = db.lastScan and K.ago((K.realMs() - db.lastScan) / 1000) or "nie"
    UI.kv(ix, iy, iw, "Letzter Scan", last .. (db.lastCount and ("  ·  " .. db.lastCount .. " Kontakte") or ""), nil, 14)
    local near
    for _, c in ipairs(sc.results or {}) do if not c.own and (c.type == "ship") then near = c break end end
    UI.kv(ix, iy + 1, iw, "Nächstes Schiff", near and ((near.name ~= "" and near.name or "?") .. "  " .. num(near.dist) .. " Bl. " .. W.bearing(near.dx, near.dz)) or "keins gesehen",
          near and C.warn or C.dim, 14)
    UI.kv(ix, iy + 2, iw, "Lauschstation", (db.autoEvery or 0) > 0 and ("alle " .. db.autoEvery .. " min") or "aus", nil, 14)
    if ih >= 4 then
        UI.row({ { text = sc.state == "running" and "SCANNT …" or "SCAN", style = "secondary", disabled = sc.state == "running",
                   onClick = function() bg(function() W.runScan(db.radius) end, "radar") end },
                 { text = "RADAR ▸", style = "subtle", onClick = function() A.view = "radar" end } }, ix, iy + ih - 1)
    end
end

local function drawBridge(x, y, w, h, hv)
    local st = W.st
    local wide = w >= 110
    local lw = wide and math.floor(w * 0.56) or w
    local cardH = wide and 15 or math.min(11, h)
    local ix, iy, iw, ih = UI.card(x, y, lw, cardH, "SCHIFF")
    if not st then
        UI.para(ix, iy + 1, iw, "Lese Schiffsdaten (jeder WarpDrive-Befehl dauert einen Tick) …", C.muted)
        return
    end
    G.text(ix, iy, G.fit(st.name and st.name ~= "" and st.name or "Schiff ohne Namen", iw), C.text, C.card)
    if not st.valid then G.text(ix, iy + 1, G.fit(tostring(st.validMsg or ""), iw), C.bad, C.card) end
    local rows = {
        { "Modus", W.MODES[tostring(st.mode)] or tostring(st.mode or "?") },
        { "Ort", placeText(st) },
        { "Position", pos(st.x, st.y, st.z) },
        { "Bug zeigt nach", W.facingName(st) },
        { "Masse", st.mass and (num(st.mass) .. " Bl. · Vol. " .. num(st.volume)) or "?" },
        { "Maße L×B×H", st.front and string.format("%d × %d × %d", st.front + 1 + st.back, st.left + 1 + st.right, st.up + 1 + st.down) or "?" },
        { "Max. Sprung", st.maxJump and (num(st.maxJump) .. " Blöcke") or tostring(st.maxJumpErr or "?"), st.maxJump and C.text or C.warn },
        { "An Bord", #st.players > 0 and table.concat(st.players, ", ") or "niemand angemeldet", #st.players > 0 and C.text or C.muted },
    }
    local ry = iy + 2
    if wide or iw >= 70 then
        local colW = wide and iw or math.floor((iw - 2) / 2)
        for i, r in ipairs(rows) do
            local cx = (not wide and i % 2 == 0) and (ix + colW + 2) or ix
            if wide then UI.kv(ix, ry, iw, r[1], r[2], r[3], 18) ry = ry + 1
            else UI.kv(cx, ry, colW, r[1], r[2], r[3], 15) if i % 2 == 0 then ry = ry + 1 end end
        end
    else
        for _, r in ipairs(rows) do if ry < iy + ih - 2 then UI.kv(ix, ry, iw, r[1], r[2], r[3], 15) ry = ry + 1 end end
    end
    if wide then
        quickActions(ix, iy + ih - 1, iw, st)
        drawHistory(x, y + cardH + 1, lw, h - cardH - 1)
        local rx, rw = x + lw + 2, w - lw - 2
        drawEnergy(rx, y, rw, 12, st)
        drawRadarSummary(rx, y + 13, rw, 8, hv)
        local cx2, cy2, cw2, ch2 = UI.card(rx, y + 22, rw, h - 22, "AN BORD", { right = #st.players .. "" })
        if #st.players == 0 then UI.para(cx2, cy2, cw2, "Niemand angemeldet. Spieler melden sich am Ship Controller an (Rechtsklick), damit sie beim Sprung mitkommen.", C.muted, ch2) end
        for i, p in ipairs(st.players) do
            if i > ch2 then break end
            G.put(cx2, cy2 + i - 1, "●", p == K.set.owner and C.accent or C.info, C.card)
            G.text(cx2 + 2, cy2 + i - 1, G.fit(p, cw2 - 2), C.text, C.card)
        end
    else
        -- schmal: Energiebalken in der Karte, Knoepfe darunter
        local frac = st.energyMax > 0 and st.energy / st.energyMax or 0
        local ey = iy + ih - 1
        G.text(ix, ey, "Energie", C.muted, C.card)
        UI.meter(ix + 15, ey, iw - 15, frac, frac < 0.2 and C.bad or C.info, string.format("%3d%%", math.floor(frac * 100)))
        local ay = y + cardH + 1
        if ay <= y + h - 1 then quickActions(x, ay, w, st) end
        if y + h - ay - 2 >= 4 then drawHistory(x, ay + 2, w, y + h - ay - 2) end
    end
end

-- ---------------------------------------------------------------------
-- SPRUNG
-- ---------------------------------------------------------------------
local function axisRow(x, y, w, label, key, lim)
    G.text(x, y, label, C.muted, C.card)
    local v = A.mv[key]
    G.fill(x + 8, y, 10, 1, C.bg2)
    G.right(x + 16, y, num(v), v ~= 0 and C.text or C.muted, C.bg2)
    local bx = x + 19
    for _, d in ipairs({ -100, -10, 10, 100 }) do
        bx = UI.button({ x = bx, y = y, w = 6, text = (d > 0 and "+" or "−") .. math.abs(d), style = "subtle",
                         onClick = function() A.mv[key] = A.mv[key] + d edited() end }) + 1
    end
    bx = UI.button({ x = bx, y = y, w = 4, text = "✎", style = "subtle", onClick = function()
        UI.prompt({ title = label .. " (Blöcke, minus = Gegenrichtung)", text = tostring(v), maxLen = 7,
                    signed = true, validate = function(t) if not tonumber(t) then return "Bitte eine Zahl" end end,
                    onOk = function(t) A.mv[key] = math.floor(tonumber(t)) edited() end })
    end }) + 1
    UI.button({ x = bx, y = y, w = 3, text = "0", style = "ghost", onClick = function() A.mv[key] = 0 edited() end })
    if lim and x + w - (bx + 4) >= 12 then G.right(x + w - 1, y, "max ±" .. num(lim), C.muted, C.card) end
end
local function coordRow(x, y, w, label, key)
    G.text(x, y, label, C.muted, C.card)
    local v = A.tgt and A.tgt[key]
    G.fill(x + 8, y, 12, 1, C.bg2)
    G.right(x + 18, y, v and num(v) or "-", v and C.text or C.muted, C.bg2)
    UI.button({ x = x + 21, y = y, w = 4, text = "✎", style = "subtle", onClick = function()
        UI.prompt({ title = "Ziel " .. label, text = v and tostring(v) or "", maxLen = 9,
                    signed = true, validate = function(t) if not tonumber(t) then return "Bitte eine Zahl" end end,
                    onOk = function(t)
                        local st = W.st or {}
                        A.tgt = A.tgt or { x = st.x or 0, y = st.y or 0, z = st.z or 0 }
                        A.tgt[key] = math.floor(tonumber(t))
                        edited()
                    end })
    end })
end

local function drawTargets(x, y, w, h)
    local st = W.st
    UI.row({
        { text = "+ HIER", style = "secondary", disabled = not (st and st.x), onClick = function()
            UI.prompt({ title = "Name für diese Position", text = "Ziel " .. (#db.targets + 1), maxLen = 20, onOk = function(t)
                db.targets[#db.targets + 1] = { name = t, x = st.x, y = st.y, z = st.z } W.save() end })
        end },
        { text = "+ EINGEBEN", style = "secondary", onClick = function()
            UI.prompt({ title = "Ziel: Name x y z", hint = "z.B. Basis 1200 180 -3400", maxLen = 40,
                        validate = function(t) if not t:match("^%s*(.-)%s+(%-?%d+)%s+(%-?%d+)%s+(%-?%d+)%s*$") then return "Name und drei Zahlen" end end,
                        onOk = function(t)
                            local n, px, py, pz = t:match("^%s*(.-)%s+(%-?%d+)%s+(%-?%d+)%s+(%-?%d+)%s*$")
                            db.targets[#db.targets + 1] = { name = n, x = tonumber(px), y = tonumber(py), z = tonumber(pz) }
                            W.save()
                        end })
        end },
    }, x, y)
    if #db.targets == 0 then UI.para(x, y + 2, w, "Noch keine Ziele. Gespeicherte Ziele (Basis, Stationen, Planeten) lassen sich mit einem Tipp als Kurs setzen.", C.muted) return end
    UI.list(A.tPage, db.targets, x, y + 2, w, h - 2, 1, function(t, rx, ry, rw, i)
        G.text(rx, ry, G.fit(t.name, 16), C.text, C.card)
        G.text(rx + 17, ry, G.fit(pos(t.x, t.y, t.z), 24), C.dim, C.card)
        if st and st.x and rw > 60 then
            local d = math.floor(math.sqrt((t.x - st.x) ^ 2 + (t.z - st.z) ^ 2))
            G.text(rx + 42, ry, G.fit(num(d) .. " Bl. " .. W.bearing(t.x - st.x, t.z - st.z), rw - 58), C.muted, C.card)
        end
        UI.buttonsRight({
            { text = "KURS", style = "accent", onClick = function() A.tgt = { x = t.x, y = t.y, z = t.z } A.mode = "abs" edited() end },
            { text = "✕", w = 3, style = "subtle", confirm = "tg" .. i, confirmText = "?", onClick = function() table.remove(db.targets, i) W.save() end },
        }, ry, rx + rw - 1)
    end)
end

local function drawPreview(x, y, w, h, compact)
    local st = W.st
    local ix, iy, iw, ih = UI.card(x, y, w, h, compact and nil or "VORSCHAU")
    if not st or not st.x then G.text(ix, iy, "Lese Schiffsdaten …", C.muted, C.card) return end
    local f, u, r, rot = curMove()
    local dx, dz = W.toWorld(f, r, st)
    local kw = 14
    local yy = iy
    local dist = math.floor(math.sqrt(dx * dx + u * u + dz * dz))
    local p = planFresh()
    if compact and ih < 2 then
    elseif compact then
        UI.kv(ix, yy, iw, "Ziel", pos(st.x + dx, st.y + u, st.z + dz), C.accent, 6)
        G.right(ix + iw - 1, yy, num(dist) .. " Bl. " .. W.bearing(dx, dz), C.dim, C.card)
        yy = yy + 1
        local line, col
        if A.planning then line, col = "berechne …", C.dim
        elseif not p then line, col = "Werte geändert - wird gleich berechnet", C.muted
        elseif p.ok then line, col = "✓ Sprung möglich · braucht " .. W.fmt(p.energy) .. " von " .. W.fmt(st.energy) .. " EU", C.accent
        else line, col = "✕ " .. tostring(p.problems[1]), C.bad end
        if ih >= 3 then G.text(ix, yy, G.fit(line, iw), col, C.card) end
        if p and not p.ok and p.problems[2] and ih >= 4 then G.text(ix, yy + 1, G.fit("✕ " .. p.problems[2], iw), C.bad, C.card) end
    else
        UI.kv(ix, yy, iw, "Von", pos(st.x, st.y, st.z), nil, kw) yy = yy + 1
        UI.kv(ix, yy, iw, "Nach", pos(st.x + dx, st.y + u, st.z + dz), C.accent, kw) yy = yy + 1
        UI.kv(ix, yy, iw, "Strecke", num(dist) .. " Bl.  " .. W.bearing(dx, dz) .. (rot > 0 and ("  ·  Drehung " .. rot * 90 .. "°") or ""), nil, kw) yy = yy + 1
        if A.mode ~= "rel" then
            UI.kv(ix, yy, iw, "Schiffsachsen", "vorn " .. num(f) .. " · hoch " .. num(u) .. " · rechts " .. num(r), C.dim, kw) yy = yy + 1
        end
        yy = yy + 1
    end
    if compact then
    elseif A.planning then
        G.text(ix, yy, "berechne …", C.dim, C.card)
    elseif p then
        UI.kv(ix, yy, iw, "Energie nötig", p.energy and (W.fmt(p.energy) .. " EU") or tostring(p.energyErr), p.energy and C.text or C.warn, kw) yy = yy + 1
        UI.kv(ix, yy, iw, "Vorhanden", W.fmt(st.energy) .. " EU", (p.energy and st.energy < p.energy) and C.bad or C.text, kw) yy = yy + 1
        if p.ok then
            G.text(ix, yy, "✓ Sprung möglich", C.accent, C.card)
        else
            for _, pr in ipairs(p.problems) do
                if yy > iy + ih - 3 then break end
                G.text(ix, yy, G.fit("✕ " .. pr, iw), C.bad, C.card)
                yy = yy + 1
            end
        end
    else
        G.text(ix, yy, "Werte geändert - wird gleich berechnet", C.muted, C.card)
    end
    local by = iy + ih - 1
    local busy = A.planning or A.jumping ~= nil or (db.survey and db.survey.active)
    UI.row({
        { text = "BERECHNEN", style = "secondary", disabled = busy, onClick = replan },
        { text = "SPRINGEN", style = "primary", disabled = not (p and p.ok) or A.count ~= nil or busy, confirm = "jump", confirmText = "WIRKLICH SPRINGEN?",
          onClick = function() startCountdown("MANUAL", string.format("%s Bl. nach %s", num(dist), W.bearing(dx, dz)), p) end },
    }, ix, by)
end

local function drawJump(x, y, w, h)
    local st = W.st
    local wide = w >= 110
    local lw = wide and math.floor(w * 0.55) or w
    local kh = wide and h or 10
    local gap = wide and 2 or 1
    local ix, iy, iw, ih = UI.card(x, y, lw, kh, "KURS", { right = "Bug zeigt nach " .. W.facingName(st) })
    local cx = ix
    if wide and A.mode == "list" then A.mode = "abs" end
    local modes = { { "rel", "RELATIV" }, { "abs", "KOORDINATEN" } }
    if not wide then modes[3] = { "list", "ZIELE" } end
    for _, m in ipairs(modes) do
        cx = UI.chip(cx, iy, m[2], A.mode == m[1], function()
            if m[1] == "abs" and not A.tgt and st and st.x then A.tgt = { x = st.x, y = st.y, z = st.z } end
            A.mode = m[1]
            edited()
        end) + 1
    end
    local yy = iy + 2
    if A.mode == "rel" then
        axisRow(ix, yy, iw, "VORN", "front", W.axisLimit("front"))
        axisRow(ix, yy + gap, iw, "HOCH", "up", W.axisLimit("up"))
        axisRow(ix, yy + gap * 2, iw, "RECHTS", "right", W.axisLimit("right"))
        yy = yy + gap * 2 + 2
    elseif A.mode == "abs" then
        coordRow(ix, yy, iw, "X", "x")
        coordRow(ix, yy + 1, iw, "Y", "y")
        coordRow(ix, yy + 2, iw, "Z", "z")
        UI.button({ x = ix + 27, y = yy, text = "AKTUELLE POSITION", style = "subtle", disabled = not (st and st.x), onClick = function()
            A.tgt = { x = st.x, y = st.y, z = st.z } edited() end })
        UI.button({ x = ix + 27, y = yy + 2, text = "ALS ZIEL SPEICHERN", style = "subtle", disabled = not A.tgt, onClick = function()
            UI.prompt({ title = "Name für das Ziel", text = "Ziel " .. (#db.targets + 1), maxLen = 20, onOk = function(t)
                db.targets[#db.targets + 1] = { name = t, x = A.tgt.x, y = A.tgt.y, z = A.tgt.z } W.save() end })
        end })
        yy = yy + 4
    else
        drawTargets(ix, yy, iw, iy + ih - yy)
    end
    if A.mode ~= "list" then
        local ry = wide and yy or (iy + ih - 1)
        G.text(ix, ry, "DREHUNG", C.muted, C.card)
        local rx = ix + 9
        for _, rr in ipairs(ROT) do
            rx = UI.chip(rx, ry, rr[2], A.mv.rot == rr[1], function() A.mv.rot = rr[1] edited() end) + 1
        end
        if wide and iy + ih - (ry + 3) >= 5 then
            G.hline(ix, ry + 2, iw, C.line, C.card)
            G.text(ix, ry + 3, "GESPEICHERTE ZIELE", C.muted, C.card)
            drawTargets(ix, ry + 5, iw, iy + ih - (ry + 5))
        end
    end
    if wide then
        local px = x + lw + 2
        local ph = math.min(h, 15)
        drawPreview(px, y, w - lw - 2, ph)
        if h > ph + 6 then
            local hx, hy, hw, hh = UI.card(px, y + ph + 1, w - lw - 2, h - ph - 1, "SO FUNKTIONIERT DER SPRUNG")
            local tips = {
                "Werte gelten in Schiffsrichtung: VORN = Richtung Bug, RECHTS von der Brücke aus gesehen.",
                "Die Bewegung muss größer als das Schiff selbst sein, sonst überlappt es sich. Pro Achse geht höchstens Schiffslänge + max. Sprungweite.",
                "KOORDINATEN rechnet ein Weltziel in Schiffsachsen um. Ziel ist die Position des Schiffskerns.",
                "Spieler müssen am Ship Controller angemeldet sein, sonst bleiben sie zurück.",
                "Nach dem Sprung kühlt der Kern ab; erst dann geht der nächste.",
            }
            local ty = hy
            for _, t in ipairs(tips) do
                if ty >= hy + hh then break end
                G.put(hx, ty, "•", C.accent, C.card)
                ty = UI.para(hx + 2, ty, hw - 2, t, C.dim, hy + hh - ty) + 0
            end
        end
    else
        drawPreview(x, y + kh + 1, w, h - kh - 1, true)
    end
end

-- ---------------------------------------------------------------------
-- RADAR
-- ---------------------------------------------------------------------
local function plot(x, y, w, h, results, R)
    if w < 6 or h < 3 then return end
    -- Braille-Ringe: Punkte sind etwa quadratisch, also echte Kreise
    local cv = G.canvas(w, h)
    local pcx, pcy = w, h * 2                      -- Mitte in Punkten
    local rd = math.max(2, math.min(w - 2, h * 2 - 2))
    cv.circle(pcx, pcy, rd)
    cv.circle(pcx, pcy, rd / 2, 2)
    cv.line(pcx - rd, pcy, pcx + rd, pcy, 4)
    cv.line(pcx, pcy - rd, pcx, pcy + rd, 4)
    G.setClip(x, y, w, h)
    cv.draw(x, y, C.line, C.card)
    local cx, cy = x + math.floor(pcx / 2), y + math.floor(pcy / 4)
    local rc = rd / 2                                -- Radius in Zellen (waagrecht)
    local top, bottom = cy - math.floor(rd / 4) - 1, cy + math.floor(rd / 4) + 1
    G.put(cx, top >= y and top or y, "N", C.dim, C.card)
    if bottom < y + h then G.put(cx, bottom, "S", C.muted, C.card) end
    G.put(cx + math.floor(rc) + 1, cy, "O", C.muted, C.card)
    G.put(cx - math.floor(rc) - 1, cy, "W", C.muted, C.card)
    if rc >= 8 then G.text(cx + math.floor(rc / 2) + 1, cy - 1, num(R / 2), C.muted, C.card) end
    G.put(cx, cy, "◆", C.accent, C.card)
    local selC
    for _, c in ipairs(results) do
        if not c.own and c.dx then
            local px = cx + math.floor(c.dx / R * rc + 0.5)
            local py = cy + math.floor(c.dz / R * rc / 2 + 0.5)
            if px >= x and px < x + w and py >= y and py < y + h then
                local key = W.contactKey(c)
                G.put(px, py, GLYPH[c.type] or "•", W.typeColor(c.type, C), C.card)
                UI.region(px, py, 1, 1, function() A.sel = key end)
                if A.sel == key then selC = { c = c, px = px, py = py } end
            end
        end
    end
    if selC then
        G.put(selC.px, selC.py, "◉", C.white, C.card)
        local label = " " .. (selC.c.name ~= "" and selC.c.name or W.typeName(selC.c.type)) .. "  " .. num(selC.c.dist) .. " Bl. "
        local lx = selC.px + 2
        if lx + G.len(label) > x + w then lx = selC.px - G.len(label) - 1 end
        G.text(lx, selC.py, label, C.white, C.raised)
    end
    G.setClip()
end

local function selectedResult()
    for _, c in ipairs(W.scan.results or {}) do if W.contactKey(c) == A.sel then return c end end
end

local function drawRadar(x, y, w, h)
    local sc = W.scan
    local ri = W.rinfo
    local wide = w >= 110
    local results = sc.results or {}
    local R = (sc.radius or db.radius) / A.zoom
    -- Steuerung
    local ctrlH = wide and 13 or 6
    local cw = wide and math.floor(w * 0.42) or w
    local px, pw = wide and (x + cw + 2) or x, wide and (w - cw - 2) or math.floor(w * 0.5)
    local cx, cy, ciw, cih = UI.card(x, y, cw, ctrlH, "RADAR", { right = ri and ri.place and tostring(ri.place) or "" })
    local rcx = cx
    if wide then G.text(cx, cy, "Radius", C.muted, C.card) rcx = cx + 10 end
    for _, r in ipairs({ 500, 1000, 2500, 5000, 10000 }) do
        rcx = UI.chip(rcx, cy, num(r), db.radius == r, function()
            db.radius = r W.save()
            bg(function() W.radarInfo(r) end, "radar-info")
        end) + 1
    end
    if not wide then
        UI.button({ x = cx + ciw - 12, y = cy, w = 12, text = sc.state == "running" and "SCANNT" or "SCAN", style = "primary",
                    disabled = sc.state == "running", onClick = function() bg(function() W.runScan(db.radius) end, "radar") end })
        local info = ri and string.format("Bedarf %s EU · Speicher %s · %s s", W.fmt(ri.need), W.fmt(ri.energy), ri.duration and string.format("%.0f", ri.duration) or "?") or "lese Radar …"
        G.text(cx, cy + 2, G.fit(info, ciw), (ri and ri.need and ri.energy and ri.energy < ri.need) and C.bad or C.dim, C.card)
    else
        local yy = cy + 2
        if ri then
            UI.kv(cx, yy, ciw, "Energie nötig", W.fmt(ri.need) .. " EU", (ri.need and ri.energy and ri.energy < ri.need) and C.bad or nil, 15)
            UI.kv(cx, yy + 1, ciw, "Speicher", W.fmt(ri.energy) .. " / " .. W.fmt(ri.energyMax) .. " EU", nil, 15)
            G.bar(cx + 15, yy + 2, ciw - 15, (ri.energyMax or 0) > 0 and ri.energy / ri.energyMax or 0, C.info, C.line)
            UI.kv(cx, yy + 3, ciw, "Dauer", ri.duration and (string.format("%.1f", ri.duration) .. " s") or "?", nil, 15)
            UI.kv(cx, yy + 4, ciw, "Universal", ri.ux and pos(ri.ux, ri.uy, ri.uz) or "?", C.dim, 15)
        else
            G.text(cx, yy, "lese Radar …", C.muted, C.card)
        end
        G.text(cx, yy + 6, "Lauschstation", C.muted, C.card)
        local ax = cx + 15
        for _, m in ipairs({ 0, 5, 15, 60 }) do
            ax = UI.chip(ax, yy + 6, m == 0 and "AUS" or (m .. " min"), (db.autoEvery or 0) == m, function() db.autoEvery = m W.save() end) + 1
        end
        UI.button({ x = cx, y = cy + cih - 1, w = ciw, text = sc.state == "running" and "SCANNT …" or "JETZT SCANNEN", style = "primary",
                    disabled = sc.state == "running", onClick = function() bg(function() W.runScan(db.radius) end, "radar") end })
    end
    if sc.state == "running" and sc.untilT then
        local frac = 1 - math.max(0, sc.untilT - computer.uptime()) / math.max(0.1, sc.untilT - (sc.startT or sc.untilT - 1))
        G.thinBar(cx, cy + 1, ciw, frac, C.accent, C.line, C.card)
    elseif sc.state == "error" then
        G.text(cx, cy + 1, G.fit("✕ " .. tostring(sc.err), ciw), C.bad, C.card)
    end
    -- Bild
    local py0 = wide and y or (y + ctrlH + 1)
    local ph = wide and h or (h - ctrlH - 1)
    local bx, by, bw, bh = UI.card(px, py0, pw, ph, "LAGEBILD (von oben)", { right = A.zoom > 1 and ("×" .. A.zoom) or nil })
    plot(bx, by, bw, bh - 1, results, R)
    if #results == 0 then
        G.text(bx, by, sc.state == "done" and "Nichts im Radius gefunden" or "Noch kein Scan", C.muted, C.card)
    end
    local zx = bx
    for _, z in ipairs({ 1, 2, 4, 8 }) do zx = UI.chip(zx, by + bh - 1, "×" .. z, A.zoom == z, function() A.zoom = z end) + 1 end
    if bw - (zx - bx) > 20 then G.right(bx + bw - 1, by + bh - 1, "Ring = " .. num(R) .. " Bl.", C.muted, C.card) end
    -- Kontakte (letzter Scan)
    local lx, ly0, lw, lh
    if wide then lx, ly0, lw, lh = x, y + ctrlH + 1, cw, h - ctrlH - 1
    else lx, ly0, lw, lh = x + pw + 1, py0, w - pw - 1, ph end
    local kx, ky, kw, kh = UI.card(lx, ly0, lw, lh, "LETZTER SCAN", { right = sc.clock and (sc.clock .. " · " .. #results) or nil })
    local list = {}
    for _, c in ipairs(results) do if not c.own then list[#list + 1] = c end end
    local sel = selectedResult()
    local listH = sel and (kh - 3) or kh
    UI.list(A.rPage, list, kx, ky, kw, listH, 1, function(c, rx, ry, rw)
        local key = W.contactKey(c)
        local on = key == A.sel
        if on then G.fill(rx - 1, ry, rw + 2, 1, C.raised) end
        local b = on and C.raised or C.card
        G.put(rx, ry, GLYPH[c.type] or "•", W.typeColor(c.type, C), b)
        G.text(rx + 2, ry, G.fit(c.name ~= "" and c.name or W.typeName(c.type), rw - 18), C.text, b)
        G.right(rx + rw - 1, ry, num(c.dist) .. " " .. W.bearing(c.dx or 0, c.dz or 0), C.dim, b)
        UI.region(rx, ry, rw, 1, function() A.sel = on and nil or key end)
    end)
    if sel then
        local sy = ky + kh - 2
        G.text(kx, sy, G.fit(W.typeName(sel.type) .. " · Masse " .. num(sel.mass) .. " · Höhe " .. (sel.dy and ((sel.dy >= 0 and "+" or "") .. num(sel.dy)) or "?"), kw), C.dim, C.card)
        UI.row({
            { text = "KURS SETZEN", style = "accent", disabled = not W.ship(), onClick = function() setTargetFromContact(sel) end },
            { text = "✕", w = 3, style = "ghost", onClick = function() A.sel = nil end },
        }, kx, sy + 1)
    end
end

-- ---------------------------------------------------------------------
-- KONTAKTE (Gedaechtnis aller Scans)
-- ---------------------------------------------------------------------
local FILTERS = { { "alle", "ALLE" }, { "ship", "SCHIFFE" }, { "warp_echo", "ECHOS" }, { "orte", "ORTE" } }
local function contactList()
    local out = {}
    for key, c in pairs(db.contacts) do
        local ok = A.filter == "alle" or c.type == A.filter
            or (A.filter == "orte" and (c.type == "planet" or c.type == "star" or c.type == "structure" or c.type == "jumpgate" or c.type == "transporter"))
        if ok then out[#out + 1] = { key = key, c = c } end
    end
    table.sort(out, function(a, b) return (a.c.last or 0) > (b.c.last or 0) end)
    return out
end
local function drawContacts(x, y, w, h)
    local wide = w >= 110
    local lw = wide and math.floor(w * 0.6) or w
    local list = contactList()
    local ix, iy, iw, ih = UI.card(x, y, lw, h, "KONTAKTE (alle Scans)", { right = #list .. "" })
    local fx = ix
    for _, f in ipairs(FILTERS) do fx = UI.chip(fx, iy, f[2], A.filter == f[1], function() A.filter = f[1] A.cPage.page = 1 end) + 1 end
    UI.buttonsRight({ { text = "LEEREN", style = "subtle", confirm = "clrc", onClick = function() db.contacts = {} W.save() A.csel = nil end } }, iy, ix + iw - 1)
    if #list == 0 then UI.para(ix, iy + 2, iw, "Noch keine Kontakte. Jeder Radar-Scan trägt hier ein, was er findet - mit erstem und letztem Sichtkontakt.", C.muted) return end
    local now = K.realMs()
    G.text(ix + 2, iy + 2, "NAME", C.muted, C.card)
    if iw > 60 then G.text(ix + 26, iy + 2, "ART", C.muted, C.card) end
    G.right(ix + iw - 1, iy + 2, "ZULETZT", C.muted, C.card)
    UI.list(A.cPage, list, ix, iy + 3, iw, ih - 3, 1, function(e, rx, ry, rw)
        local c = e.c
        local on = A.csel == e.key
        local b = on and C.raised or C.card
        if on then G.fill(rx - 1, ry, rw + 2, 1, C.raised) end
        G.put(rx, ry, GLYPH[c.type] or "•", W.typeColor(c.type, C), b)
        G.text(rx + 2, ry, G.fit(c.name ~= "" and c.name or "(ohne Namen)", 22), c.name ~= "" and C.text or C.muted, b)
        if rw > 60 then
            G.text(rx + 26, ry, G.fit(W.typeName(c.type), 11), C.dim, b)
            G.text(rx + 38, ry, G.fit(c.dist and (num(c.dist) .. " Bl.") or "", 12), C.dim, b)
        end
        G.right(rx + rw - 1, ry, "vor " .. K.ago((now - (c.last or now)) / 1000) .. "  " .. (c.count or 1) .. "×", C.muted, b)
        UI.region(rx, ry, rw, 1, function() A.csel = (A.csel == e.key) and nil or e.key end)
    end)
    -- Einzelheiten
    local c = A.csel and db.contacts[A.csel]
    if not c then
        if wide then
            local dx, dy, dw, dh = UI.card(x + lw + 2, y, w - lw - 2, h, "EINZELHEITEN")
            UI.para(dx, dy, dw, "Einen Kontakt antippen. Warp-Echos sind Spuren frischer Sprünge - so lässt sich sehen, wohin andere Schiffe gesprungen sind.", C.muted)
        end
        return
    end
    local dx, dy, dw, dh
    if wide then dx, dy, dw, dh = UI.card(x + lw + 2, y, w - lw - 2, h, "EINZELHEITEN")
    else
        local bh = 9
        UI.region(x + 2, y + h - bh - 1, w - 4, bh, function() end)
        dx, dy, dw, dh = UI.card(x + 2, y + h - bh - 1, w - 4, bh, "EINZELHEITEN", { bg = C.raised })
        G.shadow(x + 3, y + h - 1, w - 4)
    end
    G.text(dx, dy, G.fit(c.name ~= "" and c.name or "(ohne Namen)", dw), C.text)
    local kw = 13
    local rows = {
        { "Art", W.typeName(c.type), W.typeColor(c.type, C) },
        { "Masse", num(c.mass) .. " Blöcke" },
        { "Universal", pos(c.x, c.y, c.z) },
        { "Abstand", c.dist and (num(c.dist) .. " Bl. (beim letzten Scan)") or "?" },
        { "Gesehen", (c.count or 1) .. "× · erst vor " .. K.ago((now - (c.first or now)) / 1000) },
    }
    for i, r in ipairs(rows) do if dy + i < dy + dh - 1 then UI.kv(dx, dy + i, dw, r[1], r[2], r[3], kw) end end
    UI.row({
        { text = "KURS SETZEN", style = "accent", disabled = not W.ship() or not W.rinfo, onClick = function() setTargetFromContact(c) end },
        { text = "VERGESSEN", style = "subtle", onClick = function() db.contacts[A.csel] = nil A.csel = nil W.save() end },
        { text = "✕", w = 3, style = "ghost", onClick = function() A.csel = nil end },
    }, dx, dy + dh - 1)
end

-- ---------------------------------------------------------------------
-- ERKUNDUNG
-- ---------------------------------------------------------------------
local function drawSurvey(x, y, w, h)
    db.survey = db.survey or { dir = "N", step = 2000, total = 5, done = 0, scanR = 2500, log = {}, state = "bereit" }
    local sv = db.survey
    local wide = w >= 110
    local lw = wide and math.floor(w * 0.5) or w
    local setH = wide and h or 13
    local ix, iy, iw, ih = UI.card(x, y, lw, setH, "ERKUNDUNGSFLUG")
    local running = sv.active
    local yy = iy
    if wide then
        yy = UI.para(ix, yy, iw, "Das Schiff springt mehrmals in eine Himmelsrichtung und scannt nach jedem Sprung mit dem Radar. Bei jedem Problem bleibt es stehen. Abstand der Sprünge höchstens 1,5 × Radius, damit keine Lücken entstehen.", C.dim) + 1
    end
    local function chips(label, values, cur, fmt, set)
        G.text(ix, yy, label, C.muted, C.card)
        local cx = ix + 14
        for _, v in ipairs(values) do
            local t = fmt(v)
            if cx + G.len(t) + 2 > ix + iw then break end
            cx = UI.chip(cx, yy, t, cur == v, (not running) and function() set(v) W.save() end or nil) + 1
        end
        yy = yy + 2
    end
    chips("Richtung", { "N", "O", "S", "W" }, sv.dir, function(v) return W.DIRS[v][3]:upper() end, function(v) sv.dir = v end)
    chips("Sprungweite", { 500, 1000, 2000, 4000, 8000 }, sv.step, num, function(v) sv.step = v end)
    chips("Sprünge", { 3, 5, 10, 20 }, sv.total, tostring, function(v) sv.total = v end)
    chips("Radar", { 0, 1000, 2500, 5000, 10000 }, sv.scanR, function(v) return v == 0 and "AUS" or num(v) end, function(v) sv.scanR = v end)
    local lim = W.st and W.axisLimit("front")
    local info = "Strecke " .. num(sv.step * sv.total) .. " Bl." .. (lim and sv.step > lim and ("  ·  Sprung wird auf " .. num(lim) .. " gekürzt") or "")
    if sv.scanR > 0 and sv.step > sv.scanR * 1.5 then info = info .. "  ·  Lücken zwischen den Scans!" end
    G.text(ix, yy, G.fit(info, iw), (sv.scanR > 0 and sv.step > sv.scanR * 1.5) and C.warn or C.dim, C.card)
    local by = iy + ih - 1
    if running then
        UI.row({ { text = "STOPP", style = "danger", onClick = function() W.surveyStop() K.notify("Erkundung gestoppt", "warn") end } }, ix, by)
    else
        local function start(resume)
            K.askAdmin("Admin-Code für den Autopiloten", function()
                if not resume then sv.done = 0 sv.log = {} end
                bg(W.surveyRun, "erkundung")
            end)
        end
        UI.row({
            { text = "STARTEN", style = "primary", disabled = not W.ship(), confirm = "survey", confirmText = "AUTOPILOT STARTEN?", onClick = function() start(false) end },
            sv.interrupted and sv.done < sv.total and { text = "FORTSETZEN (" .. sv.done .. "/" .. sv.total .. ")", style = "secondary", onClick = function() start(true) end } or nil,
        }, ix, by)
    end
    -- Verlauf
    local sx, sy, sw, sh
    if wide then sx, sy, sw, sh = UI.card(x + lw + 2, y, w - lw - 2, h, "STATUS")
    else sx, sy, sw, sh = UI.card(x, y + setH + 1, w, h - setH - 1, "STATUS") end
    G.text(sx, sy, G.fit(tostring(sv.state or "bereit"), sw - 12), running and C.info or (sv.interrupted and C.warn or C.text), C.card)
    G.right(sx + sw - 1, sy, sv.done .. " / " .. sv.total, C.dim, C.card)
    G.bar(sx, sy + 1, sw, sv.total > 0 and sv.done / sv.total or 0, C.accent, C.line)
    local log = {}
    for i = #(sv.log or {}), 1, -1 do log[#log + 1] = sv.log[i] end
    if #log == 0 then G.text(sx, sy + 3, "Noch keine Wegpunkte", C.muted, C.card) return end
    UI.list(A.lPage, log, sx, sy + 3, sw, sh - 3, 1, function(e, rx, ry, rw)
        G.text(rx, ry, string.format("%2d", e.n), C.muted, C.card)
        G.text(rx + 3, ry, e.clock or "", C.muted, C.card)
        G.text(rx + 10, ry, G.fit(pos(e.x, e.y, e.z), rw - 30), C.text, C.card)
        if e.contacts then
            G.right(rx + rw - 1, ry, (e.ships or 0) .. ((e.ships == 1) and " Schiff · " or " Schiffe · ") .. e.contacts .. " Kont.", (e.ships or 0) > 0 and C.warn or C.dim, C.card)
        end
    end)
end

-- ---------------------------------------------------------------------
-- TARNUNG
-- ---------------------------------------------------------------------
local function drawCloak(x, y, w, h)
    local ci = W.cinfo
    local cw = math.min(w, 70)
    local ix, iy, iw, ih = UI.card(x, y, cw, math.min(h, 16), "TARNFELD (Cloaking Core)")
    if not ci then G.text(ix, iy, "lese Tarnfeld …", C.muted, C.card) return end
    G.text(ix, iy, ci.on and "● AKTIV" or "○ AUS", ci.on and C.accent or C.muted, C.card)
    G.right(ix + iw - 1, iy, ci.valid and "Aufbau in Ordnung" or ("✕ " .. tostring(ci.msg or "Aufbau fehlerhaft")), ci.valid and C.dim or C.bad, C.card)
    local frac = (ci.energyMax or 0) > 0 and (ci.energy or 0) / ci.energyMax or 0
    UI.kv(ix, iy + 2, iw, "Energie", W.fmt(ci.energy) .. " / " .. W.fmt(ci.energyMax) .. " EU", nil, 14)
    G.bar(ix, iy + 3, iw, frac, C.info, C.line)
    G.text(ix, iy + 5, "Stufe", C.muted, C.card)
    local tx = ix + 14
    tx = UI.chip(tx, iy + 5, "1  GÜNSTIG", ci.tier == 1, function() bg(function() W.setCloak(nil, 1) end) end) + 1
    UI.chip(tx, iy + 5, "2  STARK", ci.tier == 2, function() bg(function() W.setCloak(nil, 2) end) end)
    UI.para(ix, iy + 7, iw, "Stufe 2 verbirgt mehr, braucht aber deutlich mehr Energie. Die Spulen müssen in alle sechs Richtungen frei sein.", C.muted, 3)
    UI.button({ x = ix, y = iy + ih - 3, w = iw, h = 3, text = ci.on and "TARNUNG AUS" or "TARNUNG AN", style = ci.on and "secondary" or "primary",
                disabled = not ci.valid and not ci.on, onClick = function() bg(function() W.setCloak(not ci.on) end) end })
end

-- ---------------------------------------------------------------------
-- Zeichnen
-- ---------------------------------------------------------------------
local function drawCountdown()
    local c = A.count
    local SW, SH = G.size()
    UI.region(1, 1, SW, SH, function() end)
    local w, h = 46, 13
    local x, y = math.floor((SW - w) / 2) + 1, math.floor((SH - h) / 2) + 1
    G.softBox(x, y, w, h, C.raised, G.getBg(x, y))
    G.shadow(x + 1, y + h, w, G.getBg(x + 1, y + h))
    local left = math.max(0, math.ceil(c.untilT - computer.uptime()))
    G.center(x, y + 1, w, c.kind == "HYPERDRIVE" and "HYPERRAUM IN" or "SPRUNG IN", C.muted, C.raised)
    local s = tostring(left)
    G.big(x + math.floor((w - G.bigWidth(s)) / 2), y + 3, s, C.warn, C.raised)
    G.center(x, y + 7, w, c.text or "", C.dim, C.raised)
    UI.button({ x = x + 3, y = y + h - 4, w = w - 6, h = 3, text = "ABBRECHEN", style = "danger", onClick = function()
        A.count = nil K.notify("Sprung abgebrochen", "info") end })
end

function A.draw(x, y, w, h)
    local pad = (w < 100) and 1 or 2
    x, w = x + pad, w - pad * 2
    local hv = has()
    local vs = views(hv)
    local valid = false
    for _, v in ipairs(vs) do if v.id == A.view then valid = true end end
    if not valid then A.view = vs[1] and vs[1].id end
    G.text(x, y + 1, "SCHIFF", C.text)
    local st = W.st
    local sub = st and st.name and st.name ~= "" and st.name or "WarpDrive"
    G.text(x + 8, y + 1, "  " .. G.fit(sub, 30), C.muted)
    local stText, stCol = status(st)
    if hv.ship then G.right(x + w - 1, y + 1, stText, stCol) end
    if #vs == 0 then
        local ix, iy, iw = UI.card(x, y + 3, w, 10, "KEINE WARPDRIVE-GERÄTE")
        UI.para(ix, iy, iw, "Ship Controller, Radar oder Cloaking Core per Kabel an diesen Rechner anschließen (oder direkt daneben stellen). Die App erscheint, sobald ein Gerät da ist.", C.muted)
        return
    end
    UI.tabs(x, y + 3, w, vs, A.view, function(v) A.view = v end)
    local top = y + 5
    local hh = y + h - top
    if A.view == "bridge" then drawBridge(x, top, w, hh, hv)
    elseif A.view == "jump" then drawJump(x, top, w, hh)
    elseif A.view == "radar" then drawRadar(x, top, w, hh)
    elseif A.view == "contacts" then drawContacts(x, top, w, hh)
    elseif A.view == "survey" then drawSurvey(x, top, w, hh)
    elseif A.view == "cloak" then drawCloak(x, top, w, hh) end
    if A.count then drawCountdown() end
end

function A.tick()
    local now = computer.uptime()
    if A.count and now >= A.count.untilT then fire() end
    if A.edited and now - A.edited > 1.2 and not A.planning and not A.jumping and not (db.survey and db.survey.active) and W.ship() then replan() end
    if A.jumping then
        local st = W.st
        if st and A.jumping.x and (st.x ~= A.jumping.x or st.z ~= A.jumping.z or st.y ~= A.jumping.y) then
            A.jumping = nil
            K.notify("Sprung abgeschlossen", "ok")
        elseif now - A.jumping.t > 120 then
            A.jumping = nil
        end
    end
    if A.view == "cloak" and (not W.cinfo or now - W.cinfo.t > 5) then bg(W.cloakInfo, "tarnung") end
    return true
end
function A.key(char, code)
    if code == 1 and A.count then A.count = nil K.notify("Sprung abgebrochen", "info") end
end
function A.scroll(dir) end
return A
