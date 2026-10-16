-- GTS OS (OpenComputers) - ANLAGEN: HBM's NTM - Reaktoren, RBMK, Energie, Turbinen, Tanks, Strahlung
local K, G, UI, S = ...
local computer = require("computer")
local C = G.C
local D = K.dev
local A = { view = "home", page = { page = 1 }, mode = "hitze", hist = {} }
local VIEWS = { { id = "home", text = "ÜBERSICHT" }, { id = "rbmk", text = "RBMK" }, { id = "guards", text = "WÄCHTER" } }
function A.enter(arg) if type(arg) == "string" then A.view = arg end end

local function val(addr, m, p, every)
    local r = D.get(addr, m, p, every or 2)
    if r and r[1] then return r end
end
local function n(v) return tonumber(v) end
local function tempColor(t, max)
    local f = (n(t) or 0) / (max or 1500)
    return (f >= 0.8 and C.bad) or (f >= 0.55 and C.warn) or C.accent
end
local function bar(x, y, w, frac, label, color)
    frac = math.max(0, math.min(1, frac or 0))
    G.bar(x, y, w - 8, frac, color or C.accent, C.line)
    G.right(x + w - 1, y, label or (math.floor(frac * 100) .. " %"), C.text, C.card)
end
-- Energie-Verlauf je Speicher (fuer +/- pro Sekunde)
local function trend(addr, v)
    local h = A.hist[addr]
    local now = computer.uptime()
    if not h then h = { t = now, v = v, d = 0 } A.hist[addr] = h return 0 end
    if now - h.t >= 2 then h.d = (v - h.v) / (now - h.t) h.t, h.v = now, v end
    return h.d
end

-- ---------------------------------------------------------------------
-- Karten je Geraet
-- ---------------------------------------------------------------------
local CARD = {}
local function energyCard(e, x, y, w)
    local r = val(e.addr, "getEnergyInfo")
    if not r then return "lädt …" end
    local p, max = n(r[2]) or 0, n(r[3]) or 1
    local d = trend(e.addr, p)
    bar(x, y, w, p / math.max(1, max), math.floor(p / math.max(1, max) * 100) .. " %")
    G.text(x, y + 1, K.si(p) .. " / " .. K.si(max) .. " HE", C.dim, C.card)
    G.right(x + w - 1, y + 1, (d >= 0 and "+" or "") .. K.si(d * 0.05) .. "/t", d < 0 and C.warn or C.accent, C.card)
end
CARD.ntm_energy_storage, CARD.ntm_energy_storage_legacy = energyCard, energyCard
function CARD.ntm_turbine(e, x, y, w)
    local r = val(e.addr, "getFluid")
    local pw = val(e.addr, "getPower")
    if not r then return "lädt …" end
    G.text(x, y, "Dampf", C.muted, C.card)
    bar(x + 8, y, w - 8, (n(r[2]) or 0) / math.max(1, n(r[3]) or 1), K.si(r[2]) .. " mB")
    G.text(x, y + 1, "Leistung " .. (pw and K.si(pw[2]) or "-") .. " HE", C.dim, C.card)
end
local function engineCard(e, x, y, w)
    local st = val(e.addr, "getState")
    local pw = val(e.addr, "getPower")
    local th = val(e.addr, "getThrottle")
    local on = st and (st[2] == 1 or st[2] == true)
    G.text(x, y, (on and "läuft" or "aus") .. "  ·  " .. (pw and K.si(pw[2]) or "-") .. " HE" .. (th and ("  ·  Gas " .. K.num(th[2]) .. " %") or ""), on and C.accent or C.dim, C.card)
    UI.row({
        { text = "START", style = "subtle", onClick = function() D.call(e.addr, "start", {}) D.refresh(e.addr, "getState") end },
        { text = "STOP", style = "subtle", onClick = function() D.call(e.addr, "stop", {}) D.refresh(e.addr, "getState") end },
        { text = "GAS", style = "subtle", onClick = function()
            UI.prompt({ title = "Gas (0-100 %)", text = th and tostring(th[2]) or "100", numeric = true, onOk = function(t) D.call(e.addr, "setThrottle", { tonumber(t) or 100 }) end })
        end },
    }, x, y + 1, 1)
end
CARD.ntm_gas_turbine, CARD.ntm_combustion_engine = engineCard, engineCard
function CARD.ntm_fluid_tank(e, x, y, w)
    local f, m, t = val(e.addr, "getFluidStored", nil, 3), val(e.addr, "getMaxStored", nil, 10), val(e.addr, "getTypeStored", nil, 10)
    if not f then return "lädt …" end
    local max = m and n(m[2]) or 1
    bar(x, y, w, (n(f[2]) or 0) / math.max(1, max))
    G.text(x, y + 1, G.fit((t and tostring(t[2]) or "?") .. " · " .. K.num(f[2]) .. " / " .. K.num(max) .. " mB", w), C.dim, C.card)
end
function CARD.ntm_mass_storage(e, x, y, w)
    local f, c = val(e.addr, "getFill", nil, 3), val(e.addr, "getCapacity", nil, 10)
    if not f then return "lädt …" end
    bar(x, y, w, (n(f[2]) or 0) / math.max(1, c and n(c[2]) or 1))
    G.text(x, y + 1, K.num(f[2]) .. " Items", C.dim, C.card)
end
function CARD.ntm_geiger(e, x, y, w)
    local r = val(e.addr, "getRads")
    if not r then return "lädt …" end
    local v = n(r[2]) or 0
    G.text(x, y, K.num(v, 1) .. " RAD/s", (v > 10 and C.bad) or (v > 1 and C.warn) or C.accent, C.card)
    G.text(x, y + 1, v > 10 and "gefährlich - Schutzanzug!" or (v > 1 and "erhöht" or "unbedenklich"), C.dim, C.card)
end
local function gaugeCard(e, x, y, w)
    local r = val(e.addr, "getTransfer")
    if not r then return "lädt …" end
    G.text(x, y, K.si(r[2]) .. " / Tick", C.text, C.card)
    G.text(x, y + 1, K.si(r[3]) .. " / Sekunde", C.dim, C.card)
end
CARD.ntm_power_gauge, CARD.ntm_fluid_gauge = gaugeCard, gaugeCard
function CARD.zirnox_reactor(e, x, y, w)
    local t, p, a = val(e.addr, "getTemp"), val(e.addr, "getPressure"), val(e.addr, "isActive")
    if not t then return "lädt …" end
    local on = a and a[2] == true
    G.text(x, y, K.num(t[2]) .. " °C", tempColor(t[2], 780), C.card)
    G.text(x + 10, y, (p and (K.num(p[2]) .. " bar") or "") .. "  ·  " .. (on and "AN" or "AUS"), on and C.accent or C.dim, C.card)
    UI.row({
        { text = "AN", style = "subtle", onClick = function() D.call(e.addr, "setActive", { true }) D.refresh(e.addr, "isActive") end },
        { text = "AUS", style = "subtle", onClick = function() D.call(e.addr, "setActive", { false }) D.refresh(e.addr, "isActive") end },
    }, x, y + 1, 1)
end
function CARD.research_reactor(e, x, y, w)
    local t, l = val(e.addr, "getTemp"), val(e.addr, "getLevel")
    if not t then return "lädt …" end
    G.text(x, y, "Hitze " .. K.num(t[2]) .. "  ·  Stäbe " .. (l and K.num(l[2]) or "?") .. " %", C.text, C.card)
    UI.button({ x = x, y = y + 1, text = "STÄBE", style = "subtle", onClick = function()
        UI.prompt({ title = "Steuerstäbe (0-100 %)", text = l and tostring(math.floor(n(l[2]) or 0)) or "0", numeric = true, onOk = function(s)
            D.call(e.addr, "setLevel", { (tonumber(s) or 0) / 100 }) D.refresh(e.addr, "getLevel") end })
    end })
end
function CARD.ntm_pwr_control(e, x, y, w)
    local h, l = val(e.addr, "getHeat"), val(e.addr, "getLevel")
    if not h then return "lädt …" end
    G.text(x, y, G.fit("Kern " .. K.si(h[2]) .. " · Hülle " .. K.si(h[3]) .. " · Stäbe " .. (l and K.num(l[3]) or "?") .. " %", w), C.text, C.card)
    UI.button({ x = x, y = y + 1, text = "STÄBE", style = "subtle", onClick = function()
        UI.prompt({ title = "Steuerstäbe Ziel (0-100)", text = l and tostring(math.floor(n(l[2]) or 0)) or "0", numeric = true, onOk = function(s)
            D.call(e.addr, "setLevel", { tonumber(s) or 0 }) D.refresh(e.addr, "getLevel") end })
    end })
end
function CARD.watz_reactor(e, x, y, w)
    local h, f, o = val(e.addr, "getHeat"), val(e.addr, "getFlux"), val(e.addr, "isOn")
    if not h then return "lädt …" end
    G.text(x, y, "Hitze " .. K.num(h[2]) .. "  ·  Fluss " .. (f and K.si(f[2]) or "?"), C.text, C.card)
    G.text(x, y + 1, (o and o[2]) and "läuft" or "aus", (o and o[2]) and C.accent or C.dim, C.card)
end
function CARD.rbmk_console(e, x, y, w)
    local r = D.get(e.addr, "__rbmk", nil, 3)
    if not r then return "lädt …" end
    if not r[1] then return tostring(r[2]) end
    local hot, nCol = 0, 0
    for _, c in ipairs(r[2] or {}) do nCol = nCol + 1 if c[4] > hot then hot = c[4] end end
    G.text(x, y, nCol .. " Säulen · heißeste " .. K.num(hot) .. " °C", tempColor(hot), C.card)
    UI.button({ x = x, y = y + 1, text = "RASTER ▸", style = "subtle", onClick = function() A.view = "rbmk" A.console = e.addr end })
end
-- unbekannt: getInfo (falls vorhanden) roh anzeigen
local function genericCard(e, x, y, w)
    local r = D.get(e.addr, "getInfo", nil, 5)
    if not r then return "lädt …" end
    if not r[1] then G.text(x, y, "ohne Anzeige - GERÄTE > DIREKT BEDIENEN", C.muted, C.card) return end
    local parts = {}
    for i = 2, (r.n or #r) do parts[#parts + 1] = type(r[i]) == "number" and K.si(r[i]) or tostring(r[i]) end
    UI.para(x, y, w, table.concat(parts, " · "), C.dim, 2)
end

local function drawHome(x, y, w, h)
    local list = D.of("anlagen")
    if #list == 0 then
        UI.empty(x, y + math.floor(h / 2) - 2, w, "Keine NTM-Geräte gefunden",
                 "Reaktoren, RBMK-Konsole, Speicher, Turbinen, Tanks und Geigerzähler per Kabel (oder über einen Adapter) an diesen Rechner oder an einen Knoten anschließen.")
        return
    end
    local cols = math.max(1, math.floor((w + 2) / 38))
    local cw = math.floor((w + 2) / cols) - 2
    local ch = (h >= 30) and 6 or 5
    local rows = math.max(1, math.floor((h + 1) / (ch + 1)))
    local per = cols * rows
    local pages = math.max(1, math.ceil(#list / per))
    A.page.page = math.max(1, math.min(A.page.page, pages))
    local first = (A.page.page - 1) * per
    for i = 1, per do
        local e = list[first + i]
        if not e then break end
        local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
        local cx, cy = x + col * (cw + 2), y + row * (ch + 1)
        local right = (not D.online(e) and "offline") or (D.names[e.addr] and e.kind) or (e.node and D.where(e)) or nil
        local ix, iy, iw = UI.card(cx, cy, cw, ch, D.label(e), { right = right, rightColor = D.online(e) and C.muted or C.bad })
        local fn = CARD[e.type] or genericCard
        local cy0 = iy + ch - 5
        local ok, msg = pcall(fn, e, ix, cy0, iw)
        if not ok then G.text(ix, cy0, G.fit(tostring(msg), iw), C.bad, C.card)
        elseif msg then G.text(ix, cy0, G.fit(msg, iw), C.muted, C.card) end
    end
    UI.onScroll(x, y, w, h, function(dir) A.page.page = math.max(1, math.min(pages, A.page.page + (dir < 0 and 1 or -1))) end)
    if pages > 1 then
        UI.buttonsRight({ { text = "◀", w = 4, style = "subtle", onClick = function() A.page.page = math.max(1, A.page.page - 1) end },
                          { text = A.page.page .. "/" .. pages, w = 7, style = "ghost" },
                          { text = "▶", w = 4, style = "subtle", onClick = function() A.page.page = math.min(pages, A.page.page + 1) end } }, y + h - 1, x + w - 1)
    end
end

-- ---------------------------------------------------------------------
-- RBMK-Raster
-- ---------------------------------------------------------------------
local LETTER = { FUEL = "F", FUEL_SIM = "F", CONTROL = "C", CONTROL_AUTO = "A", BOILER = "B", MODERATOR = "M", ABSORBER = "X",
                 REFLECTOR = "R", OUTGASSER = "O", BREEDER = "O", STORAGE = "S", COOLER = "K", HEATEX = "H", BLANK = "·" }
local TYPENAME = { FUEL = "Brennstab", FUEL_SIM = "Brennstab", CONTROL = "Steuerstab", CONTROL_AUTO = "Steuerstab (auto)", BOILER = "Dampfkanal",
                   MODERATOR = "Moderator", ABSORBER = "Absorber", REFLECTOR = "Reflektor", OUTGASSER = "Bestrahlung", BREEDER = "Bestrahlung",
                   STORAGE = "Lager", COOLER = "Kühler", HEATEX = "Wärmetauscher", BLANK = "Struktur" }
local function heatCol(t)
    local f = (t or 0) / 1500
    if f >= 0.8 then return 0xFF3B30 elseif f >= 0.6 then return 0xFF9F43 elseif f >= 0.4 then return 0xF5D547
    elseif f >= 0.2 then return 0x3DDC84 else return 0x2E7DFF end
end
local function drawRbmk(x, y, w, h)
    local consoles = D.of("anlagen", "^rbmk_console$")
    if #consoles == 0 then UI.empty(x, y + 4, w, "Keine RBMK-Konsole", "Die RBMK-Konsole (nicht die Säulen) per Kabel anschließen und mit dem Gerät an die Säulen verknüpfen.") return end
    local cons = A.console and D.byAddr[A.console] or consoles[1]
    A.console = cons.addr
    local fx = x
    if #consoles > 1 then
        for _, c in ipairs(consoles) do fx = UI.chip(fx, y, D.label(c), c.addr == cons.addr, function() A.console = c.addr A.sel = nil end) + 1 end
        fx = fx + 2
    end
    for _, m in ipairs({ { "hitze", "HÜLLE" }, { "kern", "KERN" }, { "staebe", "STÄBE" } }) do
        fx = UI.chip(fx, y, m[2], A.mode == m[1], function() A.mode = m[1] end) + 1
    end
    y, h = y + 2, h - 2
    local r = D.get(cons.addr, "__rbmk", nil, 2)
    local grid = (r and r[1] and r[2]) or {}
    local cellW = (w >= 110) and 4 or ((w >= 95) and 3 or 2)
    local gw, gh = 15 * cellW + 4, 17
    local gx, gy, giw, gih = UI.card(x, y, gw, math.min(h, gh), D.label(cons))
    if not r then G.text(gx, gy, "lade Säulen …", C.muted, C.card)
    elseif not r[1] then G.text(gx, gy, G.fit(tostring(r[2]), giw), C.bad, C.card) end
    local hot, sum, nRod = 0, 0, 0
    local by = {}
    for _, c in ipairs(grid) do
        by[c[1] .. "," .. c[2]] = c
        if c[4] > hot then hot = c[4] end
        if c[3] == "CONTROL" or c[3] == "CONTROL_AUTO" then sum = sum + math.max(0, c[7]) nRod = nRod + 1 end
        local cx, cy = gx + c[1] * cellW, gy + c[2]
        if cy < gy + gih then
            local bg, txt = C.raised, LETTER[c[3]] or "?"
            if A.mode == "hitze" then bg = heatCol(c[4])
            elseif A.mode == "kern" then bg = (c[6] > 0 and c[5] > 0) and heatCol(c[5] / c[6] * 1500) or C.raised
            elseif A.mode == "staebe" and c[7] >= 0 then txt = tostring(math.floor(c[7] * 100 + 0.5)) bg = c[7] > 0.5 and C.accentDim or C.raised end
            local sel = A.sel == c[1] .. "," .. c[2]
            G.fill(cx, cy, cellW - 1, 1, bg)
            txt = G.fit(txt, cellW - 1)
            G.text(cx + math.floor((cellW - 1 - G.len(txt)) / 2), cy, txt, sel and C.white or (A.mode == "staebe" and C.text or C.shadow), bg)
            if sel then G.put(cx + cellW - 1, cy, "◂", C.white, C.card) end
            UI.region(cx, cy, cellW, 1, function() A.sel = c[1] .. "," .. c[2] end)
        end
    end
    -- rechts: Kennzahlen + Bedienung
    local rx = x + gw + 2
    local rw = w - gw - 2
    if rw < 30 then rx, rw = x, w end
    local ry = (rx == x) and (y + gh + 1) or y
    local ix, iy, iw, ih = UI.card(rx, ry, rw, y + h - ry, "STEUERUNG")
    UI.kv(ix, iy, iw, "Heißeste Hülle", K.num(hot) .. " °C", tempColor(hot), 18)
    UI.kv(ix, iy + 1, iw, "Steuerstäbe", nRod > 0 and (math.floor(sum / nRod * 100 + 0.5) .. " % raus (" .. nRod .. ")") or "-", nil, 18)
    local yy = iy + 3
    local c = A.sel and by[A.sel]
    if c then
        G.text(ix, yy, (TYPENAME[c[3]] or c[3]) .. "  " .. c[1] .. "/" .. c[2], C.text, C.card)
        UI.kv(ix, yy + 1, iw, "Hülle", K.num(c[4]) .. " °C", tempColor(c[4]), 18)
        if c[6] > 0 then UI.kv(ix, yy + 2, iw, "Kern", K.num(c[5]) .. " / " .. K.num(c[6]) .. " °C", tempColor(c[5], c[6]), 18) end
        if c[8] >= 0 then UI.kv(ix, yy + 2, iw, "Wasser", K.num(c[8]) .. " mB", nil, 18) end
        yy = yy + 4
        if c[3] == "CONTROL" then
            G.text(ix, yy, "Stab " .. math.floor(c[7] * 100 + 0.5) .. " % raus", C.dim, C.card)
            local bx = ix
            for _, lv in ipairs({ 0, 25, 50, 75, 100 }) do
                bx = UI.button({ x = bx, y = yy + 1, w = 6, text = lv .. "", style = "subtle", onClick = function()
                    D.call(cons.addr, "setColumnLevel", { c[1], c[2], lv / 100 }) D.refresh(cons.addr, "__rbmk") end }) + 1
            end
            yy = yy + 3
        end
    else
        G.text(ix, yy, "Säule antippen für Details", C.muted, C.card)
        yy = yy + 2
    end
    local legend = "F Brennstab · C Steuerstab · A Auto-Stab · B Dampfkanal · M Moderator · R Reflektor · X Absorber · K Kühler · O Bestrahlung"
    if ih >= 22 then UI.para(ix, iy + ih - 7, iw, legend, C.muted, 3) end
    UI.button({ x = ix, y = yy, text = "ALLE STÄBE …", style = "secondary", onClick = function()
        UI.prompt({ title = "Alle Steuerstäbe: % herausgezogen (0-100)", numeric = true, onOk = function(t)
            D.call(cons.addr, "setLevel", { math.max(0, math.min(100, tonumber(t) or 0)) / 100 }) D.refresh(cons.addr, "__rbmk") end })
    end })
    UI.button({ x = ix, y = iy + ih - 3, w = math.min(iw, 24), h = 3, text = "AZ-5  NOTABSCHALTUNG", style = "danger", confirm = "az5",
                confirmText = "WIRKLICH AZ-5?", onClick = function()
        D.call(cons.addr, "pressAZ5", {})
        K.log("WARN", "AZ-5 von Hand: " .. D.label(cons))
        K.notify("AZ-5 ausgelöst: " .. D.label(cons), "warn", "plant")
        D.refresh(cons.addr, "__rbmk")
    end })
end

-- ---------------------------------------------------------------------
-- Waechter (Kurzweg)
-- ---------------------------------------------------------------------
local function drawGuards(x, y, w, h)
    local ix, iy, iw, ih = UI.card(x, y, w, h, "WÄCHTER FÜR ANLAGEN")
    local yy = UI.para(ix, iy, iw, "Wächter prüfen Werte alle 2 Sekunden und greifen sofort ein - auf einem Knoten sogar, wenn dieser Rechner aus ist. Alle Wächter verwaltest du unter GERÄTE > WÄCHTER.", C.dim) + 1
    for _, cons in ipairs(D.of("anlagen", "^rbmk_console$")) do
        local has
        for _, r in ipairs(D.rules) do if r.kind == "rbmk" and r.a == cons.addr then has = r end end
        G.text(ix, yy, G.fit(D.label(cons), iw - 34), C.text, C.card)
        if has then
            G.right(ix + iw - 1, yy, has.off and "Notabschaltung AUS" or ("AZ-5 ab " .. (has.hull or 1200) .. " °C aktiv"), has.off and C.warn or C.accent, C.card)
        else
            UI.button({ x = ix + iw - 30, y = yy, w = 30, text = "NOTABSCHALTUNG EINRICHTEN", style = "primary", onClick = function()
                UI.prompt({ title = "AZ-5 ab Hüllentemperatur (°C)", text = "1200", numeric = true, onOk = function(t)
                    local maxId = 0
                    for _, r in ipairs(D.rules) do if r.id > maxId then maxId = r.id end end
                    D.rules[#D.rules + 1] = { id = maxId + 1, kind = "rbmk", a = cons.addr, hull = tonumber(t) or 1200, core = 0.9, every = 2, cool = 60,
                                              name = "AZ-5 " .. D.label(cons), alarm = true }
                    D.saveRules()
                    K.notify("Notabschaltung aktiv", "ok")
                end })
            end })
        end
        yy = yy + 2
    end
    local n = 0
    for _, r in ipairs(D.rules) do local e = D.byAddr[r.a] if e and e.cat == "anlagen" then n = n + 1 end end
    G.text(ix, yy, n .. " Wächter für Anlagen eingerichtet", C.muted, C.card)
    UI.button({ x = ix, y = yy + 2, text = "ALLE WÄCHTER ▸", style = "secondary", onClick = function() K.open("devices", "rules") end })
    if #D.ruleLog > 0 then
        G.text(ix, yy + 4, "Zuletzt: " .. D.ruleLog[1].clock .. "  " .. G.fit(D.ruleLog[1].text, iw - 16), C.warn, C.card)
    end
end

function A.draw(x, y, w, h)
    local pad = (w < 100) and 1 or 2
    x, w = x + pad, w - pad * 2
    G.text(x, y + 1, "ANLAGEN", C.text)
    G.text(x + 9, y + 1, "  HBM's Nuclear Tech · " .. #D.of("anlagen") .. " Geräte", C.muted)
    UI.tabs(x, y + 3, w, VIEWS, A.view, function(v) A.view = v end)
    local top = y + 5
    local hh = y + h - top
    if A.view == "home" then drawHome(x, top, w, hh)
    elseif A.view == "rbmk" then drawRbmk(x, top, w, hh)
    else drawGuards(x, top, w, hh) end
end
function A.tick() return true end
return A
