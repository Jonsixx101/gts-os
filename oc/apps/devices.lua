-- GTS OS (OpenComputers) - GERÄTE: alle Komponenten im Verbund, Knoten, Wächter
local K, G, UI, S = ...
local computer = require("computer")
local component = require("component")
local C = G.C
local D, U = K.dev, K.units
local A = { view = "list", cat = "alle", page = { page = 1 }, nodePage = { page = 1 }, rulePage = { page = 1 }, pickPage = { page = 1 } }
local VIEWS = { { id = "list", text = "GERÄTE" }, { id = "nodes", text = "VERBUND" }, { id = "rules", text = "WÄCHTER" } }
function A.enter(arg) if type(arg) == "string" then A.view = arg end end

local function ser(v)
    local ok, s = pcall(require("serialization").serialize, v)
    return ok and s or tostring(v)
end

-- ---------------------------------------------------------------------
-- Geraeteliste + Inspektor
-- ---------------------------------------------------------------------
local function devices()
    local out = {}
    for _, e in ipairs(D.list) do
        if (A.cat == "alle" and not e.infra and e.cat ~= "system") or e.cat == A.cat then out[#out + 1] = e end
    end
    return out
end
local function selected() return A.sel and D.byAddr[A.sel] end

local function inspect(e)
    K.askAdmin("Admin-Code (Geräte direkt bedienen)", function()
        A.insp = { addr = e.addr, methods = nil, out = "lade Methoden …" }
        D.call(e.addr, "__methods", {}, function(r)
            if A.insp and A.insp.addr == e.addr then
                A.insp.methods = (r and r[1] and type(r[2]) == "table") and r[2] or {}
                A.insp.out = (r and r[1]) and (#A.insp.methods .. " Methoden - antippen zum Aufrufen") or ("Fehler: " .. tostring(r and r[2]))
                K.dirty = true
            end
        end)
    end)
end
local function invoke(e, m)
    if e.weapon then K.notify("Waffen bedient GTS OS nicht", "warn") return end
    UI.prompt({ title = m .. "(…)", hint = "Argumente als Lua, z.B.  1, true, \"text\"  (leer = keine)", maxLen = 200, onOk = function(t)
        local f = load("return " .. (t ~= "" and t or "nil"), "=args", "t", {})
        if not f then A.insp.out = "Argumente unlesbar" return end
        local args = table.pack(pcall(f))
        if not args[1] then A.insp.out = tostring(args[2]) return end
        local p = { n = args.n - 1 }
        for i = 2, args.n do p[i - 1] = args[i] end
        if t == "" then p = {} end
        A.insp.out = "läuft …"
        K.log("INFO", "Gerät " .. D.label(e) .. ": " .. m .. "(" .. t .. ")")
        D.call(e.addr, m, p, function(r)
            if not A.insp then return end
            if not r[1] then A.insp.out = "Fehler: " .. tostring(r[2])
            else
                local parts = {}
                for i = 2, (r.n or #r) do parts[#parts + 1] = ser(r[i]) end
                A.insp.out = #parts > 0 and table.concat(parts, ", ") or "(keine Rückgabe)"
            end
            K.dirty = true
        end)
    end })
end

local function drawDetail(e, x, y, w, h)
    local ix, iy, iw, ih = UI.card(x, y, w, h, nil)
    local on = D.online(e)
    local insp = A.insp and A.insp.addr == e.addr and A.insp
    local compact = insp and ih < 24
    G.put(ix, iy, "●", on and C.accent or C.muted, C.card)
    G.text(ix + 2, iy, G.fit(D.label(e), iw - 2), C.text, C.card)
    local yy = iy + 2
    local kw = 14
    if not compact then
        UI.kv(ix, yy, iw, "Art", e.kind, nil, kw) yy = yy + 1
        UI.kv(ix, yy, iw, "Typ", e.type, C.dim, kw) yy = yy + 1
        UI.kv(ix, yy, iw, "Adresse", e.addr, C.dim, kw) yy = yy + 1
        UI.kv(ix, yy, iw, "Ort", D.where(e) .. (on and "" or "  (offline)"), on and C.text or C.warn, kw) yy = yy + 1
        if e.weapon then UI.para(ix, yy + 1, iw, "Waffe: GTS OS bedient sie nicht automatisch (keine Regeln, keine KI).", C.warn) yy = yy + 2 end
        yy = yy + 1
        local open = ({ sicherheit = "security", anlagen = "plant", lager = "storage" })[e.cat]
        local btns = { { text = "UMBENENNEN", style = "secondary", onClick = function()
            UI.prompt({ title = "Name für " .. e.kind, text = D.names[e.addr] or "", maxLen = 24, onOk = function(t) D.rename(e.addr, t) end })
        end } }
        if open and K.byId[open] then btns[#btns + 1] = { text = "IN " .. K.byId[open].title .. " ▸", style = "subtle", onClick = function() K.open(open) end } end
        btns[#btns + 1] = { text = "DIREKT BEDIENEN", style = "subtle", onClick = function() inspect(e) end }
        UI.row(btns, ix, yy, 2)
        yy = yy + 2
    else
        UI.button({ x = ix + iw - 12, y = iy, w = 12, text = "SCHLIESSEN", style = "subtle", onClick = function() A.insp = nil end })
    end
    if not insp then return end
    G.hline(ix, yy, iw, C.line, C.card)
    yy = yy + 1
    for i, l in ipairs(UI.wrap(insp.out or "", iw)) do
        if i > (compact and 3 or 4) then break end
        G.text(ix, yy, l, C.info, C.card)
        yy = yy + 1
    end
    yy = yy + 1
    -- Methoden als Chips, bei Platzmangel seitenweise
    local methods = insp.methods or {}
    insp.off = math.min(insp.off or 0, math.max(0, #methods - 1))
    local mx, my = ix, yy
    local gap = compact and 1 or 2
    local shown = 0
    for i = insp.off + 1, #methods do
        local m = methods[i]
        local mw = G.len(m) + 2
        if mx + mw > ix + iw - 8 then mx, my = ix, my + gap end
        if my > iy + ih - 1 then break end
        UI.chip(mx, my, m, false, function() invoke(e, m) end)
        mx = mx + mw + 1
        shown = shown + 1
    end
    if insp.off + shown < #methods or insp.off > 0 then
        UI.chip(ix + iw - 7, iy + ih - 1, insp.off + shown < #methods and "MEHR▸" or "◂ANF.", false, function()
            if insp.off + shown < #methods then insp.off = insp.off + shown else insp.off = 0 end
        end)
    end
end

local function drawList(x, y, w, h)
    -- Bereichs-Chips + Komponenten-Grenze
    local fx = x
    fx = UI.chip(fx, y, "ALLE", A.cat == "alle", function() A.cat = "alle" A.page.page = 1 end) + 1
    for _, c in ipairs(D.CATS) do
        fx = UI.chip(fx, y, c.text, A.cat == c.id, function() A.cat = c.id A.page.page = 1 end) + 1
    end
    local n, cap = D.limit()
    local lbl = "Komponenten hier " .. n .. " / " .. cap
    if w - (fx - x) > G.len(lbl) + 14 then
        G.right(x + w - 1, y, lbl, n >= cap and C.bad or (n >= cap - 2 and C.warn or C.muted))
    end
    y, h = y + 2, h - 2
    local list = devices()
    local wide = w >= 110
    local lw = wide and math.floor(w * 0.45) or w
    if not wide and A.detail and selected() then
        UI.button({ x = x, y = y, text = "◀ LISTE", style = "ghost", onClick = function() A.detail = false end })
        drawDetail(selected(), x, y + 1, w, h - 1)
        return
    end
    local ix, iy, iw, ih = UI.card(x, y, lw, h, #list .. " GERÄTE")
    if #list == 0 then
        UI.para(ix, iy + 1, iw, "Keine Geräte in diesem Bereich. Geräte per Kabel an diesen Rechner oder an einen Knoten (VERBUND) anschließen - sie erscheinen von selbst.", C.muted)
    else
        UI.list(A.page, list, ix, iy, iw, ih, 2, function(e, rx, ry, rw)
            local sel = A.sel == e.addr
            local b = sel and C.raised or C.card
            G.fill(rx - 1, ry, rw + 2, 2, b)
            if sel then G.put(rx - 1, ry, "▍", C.accent, b) G.put(rx - 1, ry + 1, "▍", C.accent, b) end
            G.put(rx + 1, ry, "●", D.online(e) and C.accent or C.muted, b)
            G.text(rx + 3, ry, G.fit(D.label(e), rw - 4), C.text, b)
            G.text(rx + 3, ry + 1, G.fit(e.kind .. " · " .. D.where(e), rw - 4), C.muted, b)
            UI.region(rx - 1, ry, rw + 2, 2, function() A.sel = e.addr A.detail = true if not (A.insp and A.insp.addr == e.addr) then A.insp = nil end end)
        end)
    end
    if wide then
        local e = selected() or list[1]
        if e then A.sel = e.addr drawDetail(e, x + lw + 2, y, w - lw - 2, h)
        else UI.card(x + lw + 2, y, w - lw - 2, h, nil) end
    end
end

-- ---------------------------------------------------------------------
-- Verbund: Knoten
-- ---------------------------------------------------------------------
local function nodeMenu(u)
    UI.menu(U.label(u), {
        { text = "NAME ÄNDERN", onClick = function()
            UI.prompt({ title = "Name des Knotens", text = u.name or "", maxLen = 16, onOk = function(t)
                u.name = t ~= "" and t or nil U.remember(u) U.cmd(u.addr, "name", { name = t }, "Name") end })
        end },
        { text = "PIEPEN (finden)", disabled = not u.online, onClick = function() U.cmd(u.addr, "ping", {}, "piep") end },
        { text = "GERÄTE NEU LADEN", disabled = not u.online, onClick = function() U.cmd(u.addr, "comps", {}, "Komponenten") end },
        { text = "NEU STARTEN", disabled = not u.online, confirm = "nre" .. u.addr, onClick = function() U.cmd(u.addr, "restart", {}, "Neustart") end },
        { text = "VERGESSEN", style = "danger", confirm = "nfg" .. u.addr, onClick = function() U.forget(u.addr) D.rebuild() end },
    })
end
local function drawNodes(x, y, w, h)
    local wide = w >= 110
    local small = not wide and h < 30
    local lw = wide and math.floor(w * 0.55) or w
    local nodes = U.nodes()
    local lh = wide and h or (small and h or math.max(8, h - 15))
    if small and A.nodeSetup then
        UI.button({ x = x, y = y, text = "◀ KNOTEN", style = "ghost", onClick = function() A.nodeSetup = false end })
        y, h = y + 1, h - 1
    end
    local ix, iy, iw, ih
    if not (small and A.nodeSetup) then
        ix, iy, iw, ih = UI.card(x, y, lw, lh, #nodes .. " KNOTEN")
        if small then UI.button({ x = ix + iw - 14, y = iy - 1, w = 14, text = "EINRICHTEN …", style = "subtle", onClick = function() A.nodeSetup = true end }) end
    end
    if small and A.nodeSetup then nodes = nil end
    if not nodes then
        -- (nur Einrichten sichtbar)
    elseif #nodes == 0 then
        UI.para(ix, iy + 1, iw, "Noch keine Knoten. Ein Knoten ist ein weiterer Rechner ohne Bildschirm: Er bringt eigene Steckplätze und 16 weitere Komponenten mit - alles erscheint hier in einer Oberfläche.", C.muted)
    else
        UI.list(A.nodePage, nodes, ix, iy, iw, ih, 3, function(u, rx, ry, rw)
            G.put(rx, ry, "●", u.online and C.accent or C.muted, C.card)
            G.text(rx + 2, ry, G.fit(U.label(u), rw - 26), u.online and C.text or C.muted, C.card)
            local link = u.wired and "Kabel" or (u.secure and "Funk AES" or "Funk gesiegelt")
            G.right(rx + rw - 1, ry, u.online and link or ("offline · " .. K.ago(computer.uptime() - (u.seen or 0))), u.online and C.dim or C.muted, C.card)
            local nc = 0
            for _, t in pairs(u.comps or {}) do if not ({ computer = 1, eeprom = 1, filesystem = 1, modem = 1, data = 1 })[t] then nc = nc + 1 end end
            local info = nc .. " Geräte · " .. (u.rulesN or 0) .. " Wächter"
            if u.mem and u.tot then info = info .. " · RAM " .. math.floor((1 - u.mem / math.max(1, u.tot)) * 100) .. " %" end
            if u.inet then info = info .. " · Internet" end
            G.text(rx + 2, ry + 1, G.fit(info, rw - 10), C.dim, C.card)
            UI.button({ x = rx + rw - 8, y = ry + 1, w = 8, text = "MEHR", style = "subtle", onClick = function() nodeMenu(u) end })
        end)
    end
    -- Einrichten
    if small and not A.nodeSetup then return end
    local sx, sy, sw, sh
    if wide then sx, sy, sw, sh = UI.card(x + lw + 2, y, w - lw - 2, h, "KNOTEN EINRICHTEN")
    elseif small then sx, sy, sw, sh = UI.card(x, y, w, h, "KNOTEN EINRICHTEN")
    else sx, sy, sw, sh = UI.card(x, y + lh + 1, w, h - lh - 1, "KNOTEN EINRICHTEN") end
    local yy = sy
    for _, t in ipairs({
        "1  Rechner bauen: Gehäuse, CPU, RAM, Netzwerk- oder Wireless-Karte und Data Card (Tier 1 reicht). Kein Bildschirm, keine Festplatte.",
        "2  LEERE EEPROM hier einstecken (BIOS vorher raus), KNOTEN-EEPROM SCHREIBEN, EEPROM in den Knoten.",
        "3  Geräte per Kabel an den Knoten, einschalten - er meldet sich hier. Capacitor daneben hilft.",
    }) do yy = UI.para(sx, yy, sw, t, C.dim, math.max(1, sy + sh - 3 - yy)) + (small and 0 or 1) end
    if yy + 2 <= sy + sh then
        local ee = component.isAvailable("eeprom") and component.eeprom
        local isBios = U.isBios()
        UI.row({
            { text = "KNOTEN-EEPROM SCHREIBEN", style = isBios and "warn" or "primary", confirm = isBios and "nflash" or nil,
              confirmText = "DAS IST DAS BIOS! TROTZDEM?", disabled = not ee or not K.net.ready, onClick = function()
                UI.prompt({ title = "Name des Knotens (optional)", maxLen = 16, onOk = function(name)
                    local ok, err = U.flash(name, "node")
                    K.notify(ok and "Knoten-EEPROM geschrieben - jetzt herausnehmen" or ("Fehler: " .. tostring(err)), ok and "ok" or "bad")
                end })
            end },
            { text = "BIOS ZURÜCK", style = "subtle", disabled = not ee, confirm = "nbios", onClick = function()
                local ok, err = U.restoreBios()
                K.notify(ok and "Lua BIOS geschrieben" or ("Fehler: " .. tostring(err)), ok and "ok" or "bad")
            end },
        }, sx, yy, 2)
    end
end

-- ---------------------------------------------------------------------
-- Waechter-Regeln
-- ---------------------------------------------------------------------
-- Vorlagen: { Text, Methode, Ergebnis-Nr., Feld, Vergleich, Grenze, Argumente }
local COND = {
    zirnox_reactor = { { "Temperatur über (°C)", "getTemp", 1, nil, ">", 650 }, { "Druck über (bar)", "getPressure", 1, nil, ">", 25 } },
    research_reactor = { { "Temperatur über", "getTemp", 1, nil, ">", 1500 } },
    ntm_pwr_control = { { "Kernhitze über", "getHeat", 1, nil, ">", 50000 }, { "Hüllenhitze über", "getHeat", 2, nil, ">", 50000 } },
    watz_reactor = { { "Hitze über", "getHeat", 1, nil, ">", 900 } },
    ntm_energy_storage = { { "Energie unter", "getEnergyInfo", 1, nil, "<", 1000000 }, { "Energie über", "getEnergyInfo", 1, nil, ">", 1000000 } },
    ntm_energy_storage_legacy = { { "Energie unter", "getEnergyInfo", 1, nil, "<", 1000000 } },
    ntm_fluid_tank = { { "Füllstand unter (mB)", "getFluidStored", 1, nil, "<", 1000 }, { "Füllstand über (mB)", "getFluidStored", 1, nil, ">", 60000 } },
    ntm_geiger = { { "Strahlung über (RAD/s)", "getRads", 1, nil, ">", 10 } },
    ntm_turbine = { { "Dampf unter (mB)", "getFluid", 1, nil, "<", 1000 } },
    redstone = { { "Eingang Seite 1 an", "getInput", 1, nil, ">", 0, { 1 } }, { "Eingang Seite 0 an", "getInput", 1, nil, ">", 0, { 0 } } },
    me_controller = { { "AE-Energie unter", "getStoredPower", 1, nil, "<", 1000 } },
}
-- Massnahmen-Vorlagen fuer dasselbe Geraet
local ACT = {
    zirnox_reactor = { { "Reaktor aus", "setActive", { false } } },
    research_reactor = { { "Stäbe ganz rein", "setLevel", { 0 } } },
    ntm_gas_turbine = { { "Turbine stoppen", "stop", {} } },
    ntm_combustion_engine = { { "Motor stoppen", "stop", {} } },
    dfc_emitter = { { "Emitter aus", "setActive", { false } } },
}
local function condText(r)
    if r.kind == "rbmk" then return "Hülle > " .. (r.hull or 1200) .. " °C oder Kern ≥ " .. math.floor((r.core or 0.9) * 100) .. " % → AZ-5" end
    return (r.mtext or r.m) .. " " .. (r.op or ">") .. " " .. K.num(r.v, 1)
end
local function newRule()
    A.wiz = { step = 1 }
end
local function finishRule()
    local wz = A.wiz
    local r = wz.rule
    r.act = {}
    for _, a in ipairs(wz.acts) do
        if a.out then r.outs = r.outs or {} r.outs[#r.outs + 1] = a.out
        elseif a.alarm then r.alarm = true
        else r.act[#r.act + 1] = { a = wz.dev.addr, m = a.m, p = a.p } end
    end
    -- Redstone/Alarm laufen ueber SICHERHEIT im GTS OS (die Regel meldet, das OS handelt)
    local maxId = 0
    for _, x in ipairs(D.rules) do if x.id > maxId then maxId = x.id end end
    r.id = maxId + 1
    UI.prompt({ title = "Name der Regel", text = D.label(wz.dev) .. ": " .. (r.kind == "rbmk" and "AZ-5" or (r.mtext or r.m)), maxLen = 32, onOk = function(t)
        r.name = t
        D.rules[#D.rules + 1] = r
        D.saveRules()
        A.wiz = nil
        K.notify("Wächter „" .. t .. "“ aktiv", "ok")
    end })
end
local function drawWizard(x, y, w, h)
    local wz = A.wiz
    local ix, iy, iw, ih = UI.card(x, y, w, h, "NEUER WÄCHTER · SCHRITT " .. wz.step .. " / 3")
    UI.button({ x = ix + iw - 11, y = iy - 1, w = 11, text = "ABBRECHEN", style = "ghost", onClick = function() A.wiz = nil end })
    if wz.step == 1 then
        G.text(ix, iy, "Welches Gerät soll überwacht werden?", C.text, C.card)
        local list = {}
        for _, e in ipairs(D.list) do
            if not e.infra and not e.weapon and e.cat ~= "system" and (COND[e.type] or e.type == "rbmk_console" or e.cat == "anlagen" or e.type == "redstone") then list[#list + 1] = e end
        end
        if #list == 0 then UI.para(ix, iy + 2, iw, "Keine passenden Geräte gefunden (Reaktoren, Speicher, Tanks, Redstone …).", C.muted) return end
        UI.list(A.pickPage, list, ix, iy + 2, iw, ih - 2, 1, function(e, rx, ry, rw)
            UI.button({ x = rx, y = ry, w = rw, text = D.label(e) .. "  ·  " .. e.kind .. "  ·  " .. D.where(e), style = "subtle", align = "left",
                        onClick = function() wz.dev = e wz.step = 2 end })
        end)
    elseif wz.step == 2 then
        local e = wz.dev
        G.text(ix, iy, "Wann soll der Wächter auslösen?  (" .. D.label(e) .. ")", C.text, C.card)
        local yy = iy + 2
        local opts = {}
        if e.type == "rbmk_console" then
            opts[#opts + 1] = { text = "RBMK-Notabschaltung: Hülle > 1200 °C oder Brennstab-Kern ≥ 90 % → AZ-5", onClick = function()
                wz.rule = { kind = "rbmk", a = e.addr, hull = 1200, core = 0.9, every = 2, cool = 60 }
                wz.acts = {}
                wz.step = 3
            end }
        end
        for _, c in ipairs(COND[e.type] or {}) do
            opts[#opts + 1] = { text = c[1] .. "  (Vorschlag " .. K.num(c[6]) .. ")", onClick = function()
                UI.prompt({ title = c[1], text = tostring(c[6]), numeric = true, signed = true, onOk = function(t)
                    wz.rule = { a = e.addr, m = c[2], i = c[3], k = c[4], op = c[5], v = tonumber(t) or c[6], p = c[7], mtext = c[1]:gsub(" %(.*%)$", ""):gsub(" über$", ""):gsub(" unter$", ""), every = 2, cool = 60 }
                    wz.acts = {}
                    wz.step = 3
                end })
            end }
        end
        opts[#opts + 1] = { text = "Eigene Bedingung (Methode, Vergleich, Grenze) …", onClick = function()
            UI.prompt({ title = "z.B.  getTemp > 800   oder   getFluid 3 < 500", maxLen = 60,
                        validate = function(t) if not t:match("^%s*([%w_]+)%s*(%d*)%s*([<>=])%s*(%-?[%d%.]+)%s*$") then return "Methode [Nr.] > Zahl" end end,
                        onOk = function(t)
                            local m, i, op, v = t:match("^%s*([%w_]+)%s*(%d*)%s*([<>=])%s*(%-?[%d%.]+)%s*$")
                            wz.rule = { a = e.addr, m = m, i = tonumber(i) or 1, op = op, v = tonumber(v), every = 2, cool = 60 }
                            wz.acts = {}
                            wz.step = 3
                        end })
        end }
        for _, o in ipairs(opts) do
            if yy > iy + ih - 2 then break end
            o.x, o.y, o.w, o.style, o.align = ix, yy, iw, "subtle", "left"
            UI.button(o)
            yy = yy + 2
        end
    else
        local e = wz.dev
        G.text(ix, iy, "Was soll passieren?  " .. condText(wz.rule), C.text, C.card)
        G.text(ix, iy + 1, "Eine Meldung kommt immer. Weitere Maßnahmen antippen (mehrere möglich):", C.muted, C.card)
        local yy = iy + 3
        local function has(test) for i, a in ipairs(wz.acts) do if test(a) then return i end end end
        local function opt(text, test, make)
            local i = has(test)
            local function flip()
                local j = has(test)
                if j then table.remove(wz.acts, j) else wz.acts[#wz.acts + 1] = make() end
            end
            UI.toggle(ix, yy, i ~= nil, flip)
            G.text(ix + 10, yy, G.fit(text, iw - 10), C.text, C.card)
            UI.region(ix + 9, yy, iw - 9, 1, flip)
            yy = yy + 2
        end
        for _, a in ipairs(ACT[e.type] or {}) do
            opt(a[1], function(x) return x.m == a[2] end, function() return { m = a[2], p = a[3] } end)
        end
        if K.sec then
            opt("Alarm auslösen (alle Alarme)", function(x) return x.alarm end, function() return { alarm = true } end)
            for _, o in ipairs(K.sec.db.outputs) do
                if yy > iy + ih - 3 then break end
                opt("Redstone: " .. o.name, function(x) return x.out == o.id end, function() return { out = o.id } end)
            end
        end
        UI.button({ x = ix + iw - 16, y = iy + ih - 1, w = 16, text = "SPEICHERN", style = "primary", onClick = finishRule })
    end
end
local function drawRules(x, y, w, h)
    if A.wiz then drawWizard(x, y, w, h) return end
    local wide = w >= 110
    local lw = wide and math.floor(w * 0.62) or w
    local lh = wide and h or math.max(8, h - 9)
    local ix, iy, iw, ih = UI.card(x, y, lw, lh, #D.rules .. " WÄCHTER")
    UI.button({ x = ix + iw - 14, y = iy - 1, w = 14, text = "+ NEUER", style = "primary", onClick = newRule })
    if #D.rules == 0 then
        UI.para(ix, iy + 1, iw, "Wächter prüfen Geräte alle 2 Sekunden und greifen ein - z.B. RBMK-Notabschaltung bei zu viel Hitze, Reaktor aus, Alarm oder ein Redstone-Signal. Sie laufen dort, wo das Gerät hängt: auf einem Knoten auch dann, wenn dieser Rechner aus ist.", C.muted)
    else
        UI.list(A.rulePage, D.rules, ix, iy + 1, iw, ih - 1, 2, function(r, rx, ry, rw, i)
            local e = D.byAddr[r.a]
            G.put(rx, ry, "●", r.off and C.muted or C.accent, C.card)
            G.text(rx + 2, ry, G.fit(r.name or ("Regel " .. r.id), rw - 22), r.off and C.muted or C.text, C.card)
            G.text(rx + 2, ry + 1, G.fit((e and D.label(e) or "Gerät fehlt") .. " · " .. condText(r), rw - 4), C.dim, C.card)
            UI.button({ x = rx + rw - 19, y = ry, w = 8, text = r.off and "AN" or "AUS", style = "subtle", onClick = function() r.off = not r.off D.saveRules() end })
            UI.button({ x = rx + rw - 10, y = ry, w = 10, text = "LÖSCHEN", style = "subtle", confirm = "rdel" .. r.id, onClick = function() table.remove(D.rules, i) D.saveRules() end })
        end)
    end
    local lx, ly, lw2, lh2
    if wide then lx, ly, lw2, lh2 = UI.card(x + lw + 2, y, w - lw - 2, h, "AUSGELÖST")
    else lx, ly, lw2, lh2 = UI.card(x, y + lh + 1, w, h - lh - 1, "AUSGELÖST") end
    if #D.ruleLog == 0 then G.text(lx, ly, "Noch nichts ausgelöst", C.muted, C.card) end
    for i, l in ipairs(D.ruleLog) do
        if i > lh2 then break end
        G.text(lx, ly + i - 1, l.clock, C.muted, C.card)
        G.text(lx + 6, ly + i - 1, G.fit(l.text, lw2 - 6), C.warn, C.card)
    end
end

function A.draw(x, y, w, h)
    local pad = (w < 100) and 1 or 2
    x, w = x + pad, w - pad * 2
    G.text(x, y + 1, "GERÄTE", C.text)
    local _, _, _, k = U.online()
    local nd = 0
    for _, e in ipairs(D.list) do if not e.infra and e.cat ~= "system" then nd = nd + 1 end end
    G.text(x + 8, y + 1, "  " .. nd .. " Geräte · " .. k .. " Knoten online", C.muted)
    UI.tabs(x, y + 3, w, VIEWS, A.view, function(v) A.view = v A.wiz = nil end)
    local top = y + 5
    local hh = y + h - top
    if A.view == "list" then drawList(x, top, w, hh)
    elseif A.view == "nodes" then drawNodes(x, top, w, hh)
    else drawRules(x, top, w, hh) end
end
function A.tick() return true end
return A
