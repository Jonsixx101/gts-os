-- GTS OS (OpenComputers) - LAGER: Applied Energistics 2 - Items, Bestellen, Aufträge, Vorrat
local K, G, UI, S = ...
local C = G.C
local D, St = K.dev, K.stock
local A = { view = "home", q = "", off = 0, jPage = { page = 1 }, rPage = { page = 1 } }
local VIEWS = { { id = "home", text = "ÜBERSICHT" }, { id = "items", text = "ITEMS" }, { id = "jobs", text = "AUFTRÄGE" }, { id = "stock", text = "VORRAT" } }
local FIELDS = { "label", "size", "name", "damage", "isCraftable" }
function A.enter(arg) if type(arg) == "string" then A.view = arg end end

if not St then
    function A.draw(x, y, w, h) UI.empty(x, y + math.floor(h / 2) - 1, w, "LAGER ist im sicheren Modus aus", "SYSTEM > WARTUNG: sicheren Modus beenden.") end
    return A
end

local function order(it)
    UI.prompt({ title = "Bestellen: " .. tostring(it.label), text = "64", numeric = true, onOk = function(t)
        local n = math.floor(tonumber(t) or 0)
        if n < 1 then return end
        local ok, err = St.craft(it, n, "von Hand")
        K.notify(ok and (n .. "x " .. it.label .. " bestellt") or err, ok and "ok" or "warn", "storage")
    end })
end
local function keep(it)
    UI.prompt({ title = "Vorrat halten: Mindestmenge " .. tostring(it.label), text = "64", numeric = true, onOk = function(t)
        local min = math.floor(tonumber(t) or 0)
        if min < 1 then return end
        UI.prompt({ title = "Je Auftrag herstellen", text = tostring(math.max(1, min)), numeric = true, onOk = function(b)
            St.addRule(it, min, math.max(1, math.floor(tonumber(b) or min)))
            K.notify("Vorrat: " .. it.label .. " ab " .. min, "ok", "storage")
        end })
    end })
end

local function drawHome(x, y, w, h, me)
    local wide = w >= 110
    local lw = wide and math.floor((w - 2) / 2) or w
    local ix, iy, iw = UI.card(x, y, lw, 9, "ME-NETZ", { right = D.label(me) })
    local p, mx = D.get(me.addr, "getStoredPower", nil, 3), D.get(me.addr, "getMaxStoredPower", nil, 10)
    local inj, use = D.get(me.addr, "getAvgPowerInjection", nil, 3), D.get(me.addr, "getAvgPowerUsage", nil, 3)
    local pv, mv = p and p[1] and tonumber(p[2]) or 0, mx and mx[1] and tonumber(mx[2]) or 0
    G.text(ix, iy, "Energie", C.muted, C.card)
    G.bar(ix + 10, iy, iw - 20, pv / math.max(1, mv), C.accent, C.line)
    G.right(ix + iw - 1, iy, K.si(pv) .. " AE", C.text, C.card)
    UI.kv(ix, iy + 2, iw, "Zufluss", inj and inj[1] and (K.num(inj[2], 1) .. " AE/t") or "-", nil, 16)
    UI.kv(ix, iy + 3, iw, "Verbrauch", use and use[1] and (K.num(use[2], 1) .. " AE/t") or "-", nil, 16)
    local items = D.get(me.addr, "getItemsInNetwork", nil, 10, { x = { sort = "size", lim = 12 }, f = FIELDS, key = "top" })
    local n = items and items[1] and type(items[2]) == "table" and items[2].n
    UI.kv(ix, iy + 4, iw, "Item-Sorten", n and K.num(n) or "…", nil, 16)
    local active = 0
    for _, j in ipairs(St.jobs) do if j.state == "läuft" then active = active + 1 end end
    UI.kv(ix, iy + 5, iw, "Aufträge", active .. " laufen · " .. #St.db.rules .. " Vorrat-Regeln", nil, 16)
    -- CPUs
    local cy = y + 10
    local cpus = D.get(me.addr, "getCpus", nil, 5)
    local cx2, cy2, cw2, ch2 = UI.card(x, cy, lw, y + h - cy, "CRAFTING-CPUS")
    local list = cpus and cpus[1] and cpus[2] or {}
    if #list == 0 then G.text(cx2, cy2, cpus and "keine CPUs" or "lade …", C.muted, C.card) end
    for i, c in ipairs(list) do
        if i > ch2 then break end
        G.put(cx2, cy2 + i - 1, "●", c.busy and C.warn or C.accent, C.card)
        G.text(cx2 + 2, cy2 + i - 1, G.fit((c.name ~= "" and c.name or ("CPU " .. i)) .. " · " .. K.bytes(tonumber(c.storage) or 0)
            .. " · " .. (c.coprocessors or 0) .. " Co" .. (c.busy and " · beschäftigt" or " · frei"), cw2 - 2), C.text, C.card)
    end
    -- Top-Items
    local tx, ty, tw, th
    if wide then tx, ty, tw, th = UI.card(x + lw + 2, y, w - lw - 2, h, "MEISTE ITEMS")
    else return end
    local top = items and items[1] and items[2] and items[2].items or {}
    if #top == 0 then G.text(tx, ty, items and "leer" or "lade …", C.muted, C.card) end
    for i, it in ipairs(top) do
        if i * 2 - 1 > th then break end
        G.text(tx, ty + (i - 1) * 2, G.fit(tostring(it.label), tw - 14), C.text, C.card)
        G.right(tx + tw - 1, ty + (i - 1) * 2, K.num(it.size), C.accent, C.card)
    end
end

local function drawItems(x, y, w, h, me)
    -- Suche
    G.fill(x, y, w - 30, 1, C.bg2)
    G.text(x + 1, y, A.q ~= "" and ("Suche: " .. A.q) or (K.hasKeyboard and "Tippen zum Suchen …" or "Suche antippen …"), A.q ~= "" and C.text or C.muted, C.bg2)
    UI.region(x, y, w - 30, 1, function()
        UI.prompt({ title = "Item suchen", text = A.q, maxLen = 30, onOk = function(t) A.q = t A.off = 0 end })
    end)
    UI.row({ { text = "SUCHEN", style = "primary", onClick = function()
                UI.prompt({ title = "Item suchen", text = A.q, maxLen = 30, onOk = function(t) A.q = t A.off = 0 end }) end },
             { text = "ALLE", style = "subtle", onClick = function() A.q = "" A.off = 0 end } }, x + w - 28, y, 2)
    y, h = y + 2, h - 2
    local per = math.max(1, math.floor((h - 3) / 2))
    local r = D.get(me.addr, "getItemsInNetwork", nil, 5, { x = { q = A.q, sort = "size", lim = per, off = A.off }, f = FIELDS, key = A.q .. "|" .. A.off .. "|" .. per })
    local ix, iy, iw, ih = UI.card(x, y, w, h, nil)
    if not r then G.text(ix, iy, "lade …", C.muted, C.card) return end
    if not r[1] then G.text(ix, iy, G.fit("Fehler: " .. tostring(r[2]), iw), C.bad, C.card) return end
    local res = r[2] or {}
    local list, total = res.items or {}, res.n or 0
    G.text(ix, iy, K.num(total) .. " Treffer", C.muted, C.card)
    for i, it in ipairs(list) do
        local ry = iy + 1 + (i - 1) * 2
        G.text(ix, ry, G.fit(tostring(it.label or it.name), iw - 40), C.text, C.card)
        G.text(ix, ry + 1, G.fit(tostring(it.name) .. (it.damage and it.damage ~= 0 and (":" .. it.damage) or ""), iw - 40), C.muted, C.card)
        G.right(ix + iw - 27, ry, K.num(it.size), (tonumber(it.size) or 0) > 0 and C.accent or C.warn, C.card)
        UI.button({ x = ix + iw - 24, y = ry, w = 12, text = "BESTELLEN", style = it.isCraftable and "secondary" or "subtle", disabled = not it.isCraftable,
                    onClick = function() order(it) end })
        UI.button({ x = ix + iw - 11, y = ry, w = 11, text = "VORRAT", style = "subtle", disabled = not it.isCraftable, onClick = function() keep(it) end })
    end
    local pages = math.max(1, math.ceil(total / per))
    local page = math.floor(A.off / per) + 1
    if pages > 1 then
        UI.buttonsRight({ { text = "◀", w = 4, style = "subtle", disabled = page <= 1, onClick = function() A.off = math.max(0, A.off - per) end },
                          { text = page .. "/" .. pages, w = 9, style = "ghost" },
                          { text = "▶", w = 4, style = "subtle", disabled = page >= pages, onClick = function() A.off = A.off + per end } }, iy + ih - 1, ix + iw - 1)
    end
    UI.onScroll(ix, iy, iw, ih, function(dir)
        if dir < 0 and page < pages then A.off = A.off + per elseif dir > 0 and page > 1 then A.off = math.max(0, A.off - per) end
    end)
end

local function drawJobs(x, y, w, h)
    local ix, iy, iw, ih = UI.card(x, y, w, h, "AUFTRÄGE (zuletzt " .. #St.jobs .. ")")
    if #St.jobs == 0 then UI.para(ix, iy + 1, iw, "Noch keine Aufträge. Unter ITEMS bestellen oder unter VORRAT Mindestmengen festlegen.", C.muted) return end
    UI.list(A.jPage, St.jobs, ix, iy, iw, ih, 1, function(j, rx, ry, rw)
        local col = (j.state == "fertig" and C.accent) or (j.state == "läuft" and C.info) or (j.state:find("abgelehnt") and C.bad) or C.dim
        G.put(rx, ry, "●", col, C.card)
        G.text(rx + 2, ry, G.fit(K.num(j.amount) .. "x " .. j.label .. (j.why and ("  (" .. j.why .. ")") or ""), rw - 26), C.text, C.card)
        G.right(rx + rw - 1, ry, G.fit(j.state, 22), col, C.card)
    end)
end

local function drawStock(x, y, w, h)
    local ix, iy, iw, ih = UI.card(x, y, w, h, "VORRAT HALTEN")
    local rules = St.db.rules
    if #rules == 0 then
        UI.para(ix, iy + 1, iw, "Fällt ein Item unter die Mindestmenge, bestellt GTS OS automatisch nach (jede Minute geprüft). Anlegen unter ITEMS > VORRAT bei einem herstellbaren Item.", C.muted)
        return
    end
    UI.list(A.rPage, rules, ix, iy, iw, ih, 2, function(r, rx, ry, rw, i)
        G.put(rx, ry, "●", r.on and C.accent or C.muted, C.card)
        G.text(rx + 2, ry, G.fit(r.label, rw - 24), r.on and C.text or C.muted, C.card)
        local have = r.have and K.num(r.have) or "?"
        G.text(rx + 2, ry + 1, G.fit("hat " .. have .. " · mindestens " .. K.num(r.min) .. " · je Auftrag " .. K.num(r.batch) .. (r.checked and (" · geprüft " .. r.checked) or ""), rw - 24),
               (r.have and r.have < r.min) and C.warn or C.dim, C.card)
        UI.button({ x = rx + rw - 21, y = ry, w = 8, text = r.on and "AUS" or "AN", style = "subtle", onClick = function() r.on = not r.on St.save() end })
        UI.button({ x = rx + rw - 12, y = ry, w = 12, text = "LÖSCHEN", style = "subtle", confirm = "sd" .. r.id, onClick = function() table.remove(rules, i) St.save() end })
    end)
end

function A.draw(x, y, w, h)
    local pad = (w < 100) and 1 or 2
    x, w = x + pad, w - pad * 2
    G.text(x, y + 1, "LAGER", C.text)
    local me = St.me()
    G.text(x + 7, y + 1, "  Applied Energistics 2" .. (me and (" · " .. D.label(me) .. " · " .. D.where(me)) or ""), C.muted)
    UI.tabs(x, y + 3, w, VIEWS, A.view, function(v) A.view = v end)
    local top = y + 5
    local hh = y + h - top
    if not me then
        UI.empty(x, top + math.floor(hh / 2) - 2, w, "Kein ME-Netz gefunden", "Einen ME-Controller oder ein ME-Interface per OC-Kabel (oder Adapter) an diesen Rechner oder einen Knoten anschließen.")
        return
    end
    if A.view == "home" then drawHome(x, top, w, hh, me)
    elseif A.view == "items" then drawItems(x, top, w, hh, me)
    elseif A.view == "jobs" then drawJobs(x, top, w, hh)
    else drawStock(x, top, w, hh) end
end
function A.key(char, code)
    if A.view ~= "items" or UI.modal then return end
    if code == 14 then A.q = G.sub(A.q, 1, G.len(A.q) - 1) A.off = 0
    elseif char and char >= 32 then A.q = A.q .. (unicode and unicode.char(char) or string.char(char)) A.off = 0 end
end
function A.tick() return true end
return A
