-- ======================================================================
-- GTS OS (OpenComputers) - ops: Komponenten-Aufrufe und Waechter-Regeln
-- ======================================================================
-- Laeuft im GTS OS (lokale Geraete) und auf jedem Knoten (wird dort vor
-- das Knoten-Programm gesetzt). Darum: keine OpenOS-Bibliotheken, nur
-- component/computer.
-- Aufruf  c = { a = Adresse, m = Methode, p = { Argumente }, f = { Felder },
--               x = { q = Suchtext, sort = Feld, lim = Anzahl, off = Start } }
-- Ergebnis { true, Wert1, Wert2, ... } oder { false, Fehler }
local O = { jobs = {}, jn = 0, fired = {}, rules = {} }
local cp = component or require("component")

-- Waffen: nie in Regeln, nie fuer die KI (Abwehr bleibt bei Tueren, Alarm, Redstone)
O.WEAPON = { ntm_turret = true, ntm_artillery = true, ntm_launch_pad = true, ntm_custom_launch_pad = true,
             os_energyturret = true }

-- Werte reisefertig machen: keine Funktionen/Userdata, Tiefe und Menge begrenzt
local function clean(v, f, depth, budget)
    local t = type(v)
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return 0 end
        return v
    end
    if t == "string" then return #v > 2000 and v:sub(1, 2000) or v end
    if t == "boolean" then return v end
    if t ~= "table" or depth > 4 then return nil end
    local out = {}
    if f then
        if type(v[1]) == "table" then
            -- Liste von Tabellen: Felder je Eintrag
            for i, x in ipairs(v) do
                budget.n = budget.n - 1
                if budget.n < 0 then break end
                out[i] = clean(x, f, depth + 1, budget)
            end
            return out
        end
        for _, k in ipairs(f) do out[k] = clean(v[k], nil, depth + 1, budget) end
        return out
    end
    for k, x in pairs(v) do
        budget.n = budget.n - 1
        if budget.n < 0 then break end
        local tk = type(k)
        if tk == "string" or tk == "number" then out[k] = clean(x, nil, depth + 1, budget) end
    end
    return out
end
O.clean = clean

-- Liste filtern/sortieren/kuerzen (fuer grosse Ergebnisse wie AE2-Lager)
local function shape(list, f, x)
    local out = {}
    local q = x.q and x.q ~= "" and tostring(x.q):lower()
    for _, it in ipairs(list) do
        if type(it) == "table" then
            local label = tostring(it.label or it.name or "")
            if not q or label:lower():find(q, 1, true) or tostring(it.name or ""):lower():find(q, 1, true) then out[#out + 1] = it end
        end
    end
    if x.sort then
        local k = x.sort
        table.sort(out, function(a, b) return (tonumber(a[k]) or 0) > (tonumber(b[k]) or 0) end)
    end
    local total = #out
    local off, lim = x.off or 0, x.lim or 100
    local page = {}
    local budget = { n = 20000 }
    for i = off + 1, math.min(total, off + lim) do page[#page + 1] = clean(out[i], f, 1, budget) end
    return { items = page, n = total }
end

-- Sonder-Aufrufe ------------------------------------------------------------
local SPECIAL = {}
-- RBMK-Raster in einem Zug: { [i] = { x, y, typ, Huelle, Kern, Kern max, Stab } }
function SPECIAL.__rbmk(c)
    local grid = {}
    for y = 0, 14 do
        for x = 0, 14 do
            local ok, d = pcall(cp.invoke, c.a, "getColumnData", x, y)
            if ok and type(d) == "table" and d.type then
                grid[#grid + 1] = { x, y, tostring(d.type), tonumber(d.hullTemp) or 0, tonumber(d.coreTemp) or 0,
                                    tonumber(d.coreMaxTemp) or 0, tonumber(d.level) or -1, tonumber(d.water) or -1 }
            end
        end
    end
    return grid
end
-- AE2: Auftrag starten (das Status-Objekt bleibt hier, abfragen mit __job)
function SPECIAL.__craft(c)
    local p = c.p or {}
    local list = cp.invoke(c.a, "getCraftables", p[1] or {})
    local cr = list and list[1]
    if not cr then error("kein Rezept", 0) end
    local st = cr.request(tonumber(p[2]) or 1)
    if not st then error("abgelehnt", 0) end
    O.jn = O.jn + 1
    O.jobs[O.jn] = st
    return O.jn
end
function SPECIAL.__job(c)
    local st = O.jobs[(c.p or {})[1]]
    if not st then return "unbekannt" end
    local okd, done = pcall(st.isDone)
    local okc, canc = pcall(st.isCanceled)
    if okc and canc then O.jobs[c.p[1]] = nil return "abgebrochen" end
    if okd and done then O.jobs[c.p[1]] = nil return "fertig" end
    return "läuft"
end
-- Komponentenliste mit Methoden (Inspektor)
function SPECIAL.__methods(c)
    local out = {}
    for name, direct in pairs(cp.methods(c.a)) do out[#out + 1] = name end
    table.sort(out)
    return out
end
function SPECIAL.__doc(c) return tostring(cp.doc(c.a, (c.p or {})[1]) or "") end

-- einen Aufruf ausfuehren
function O.call(c)
    if type(c) ~= "table" or type(c.m) ~= "string" then return { false, "Aufruf unlesbar" } end
    local sp = SPECIAL[c.m]
    local r
    if sp then
        local ok, v = pcall(sp, c)
        r = { ok, v, n = 2 }
    else
        local p = c.p or {}
        r = table.pack(pcall(cp.invoke, c.a, c.m, table.unpack(p, 1, p.n or #p)))
    end
    local out = { r[1] }
    if not r[1] then out[2] = tostring(r[2]) return out end
    local budget = { n = 4000 }
    for i = 2, r.n do
        local v = r[i]
        if c.x and type(v) == "table" then out[i] = shape(v, c.f, c.x)
        else out[i] = clean(v, c.f, 1, budget) end
    end
    out.n = r.n
    return out
end

-- Waechter-Regeln -------------------------------------------------------------
-- r = { id, a, m, p, i (Ergebnis-Nr., Standard 1), k (Feld), op = ">"|"<"|"=",
--       v = Grenze, every = s, act = { { a, m, p }, ... }, cool = s, ev = true }
-- r.kind = "rbmk": a = Konsole, hull = Grad, core = Anteil (0..1) -> AZ-5
O.next = {}
local function value(r)
    if r.kind == "rbmk" then
        local grid = SPECIAL.__rbmk(r)
        local worst, why = 0, nil
        for _, col in ipairs(grid) do
            if col[4] > worst then worst = col[4] why = "Hülle " .. math.floor(col[4]) .. " °C" end
            if col[6] > 0 and col[5] / col[6] >= (r.core or 0.9) then return math.huge, "Kern " .. math.floor(col[5]) .. " °C" end
        end
        return worst, why
    end
    local p = r.p or {}
    local res = table.pack(pcall(cp.invoke, r.a, r.m, table.unpack(p, 1, #p)))
    if not res[1] then return nil end
    local v = res[(r.i or 1) + 1]
    if r.k and type(v) == "table" then v = v[r.k] end
    if type(v) == "boolean" then v = v and 1 or 0 end
    return tonumber(v)
end
function O.tick(now, emit)
    for _, r in ipairs(O.rules) do
        if not O.WEAPON[r.t or ""] and now >= (O.next[r.id] or 0) then
            O.next[r.id] = now + (r.every or 2)
            local ok, v, why = pcall(value, r)
            if ok and v then
                local lim = r.kind == "rbmk" and (r.hull or 1200) or r.v
                local hit = (r.op == "<" and v < lim) or (r.op == "=" and v == lim) or ((r.op == ">" or not r.op) and v > lim)
                if hit and now - (O.fired[r.id] or -1e9) >= (r.cool or 30) then
                    O.fired[r.id] = now
                    local done = {}
                    for _, a in ipairs(r.act or {}) do
                        local res = O.call(a)
                        done[#done + 1] = res[1] and "ok" or tostring(res[2])
                    end
                    if r.kind == "rbmk" then pcall(cp.invoke, r.a, "pressAZ5") done[#done + 1] = "AZ-5" end
                    if emit then emit(r.id, v == math.huge and -1 or v, why, done) end
                end
            end
        end
    end
end
function O.setRules(list)
    local ok = {}
    for _, r in ipairs(list or {}) do
        local t = r.a and cp.type(r.a)
        local acts = {}
        for _, a in ipairs(r.act or {}) do
            local at = a.a and cp.type(a.a)
            if at and not O.WEAPON[at] then acts[#acts + 1] = a end
        end
        r.act = acts
        if t and not O.WEAPON[t] then r.t = t ok[#ok + 1] = r end
    end
    O.rules = ok
    return #ok
end

return O
