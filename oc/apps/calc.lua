-- GTS OS (OpenComputers) - RECHNER: Taschenrechner + Umrechner (Stacks, Energie, Zeit)
-- Rechnet mit einem eigenen Parser (kein load), also sicher bei jeder Eingabe.
local K, G, UI, S = ...
local C = G.C
local A = { view = "calc", expr = "", result = nil, err = nil, hist = {}, conv = "stacks", value = 1000, unit = nil }
local HIST = K.ROOT .. "/data/rechner.db"
A.hist = S.load(HIST, {})

-- ---------------------------------------------------------------------
-- Parser: + - * / % ^ ( ), Funktionen, Konstanten, Komma als Dezimalzeichen
-- ---------------------------------------------------------------------
local FN = { sqrt = math.sqrt, wurzel = math.sqrt, abs = math.abs, sin = function(v) return math.sin(math.rad(v)) end,
             cos = function(v) return math.cos(math.rad(v)) end, tan = function(v) return math.tan(math.rad(v)) end,
             ln = math.log, log = function(v) return math.log(v, 10) end, floor = math.floor, ceil = math.ceil,
             round = function(v) return math.floor(v + 0.5) end }
local CONST = { pi = math.pi, e = math.exp(1) }
local function evaluate(src)
    src = src:gsub("×", "*"):gsub("÷", "/"):gsub("−", "-"):gsub("√", "sqrt"):gsub("π", "pi"):gsub("²", "^2")
    src = src:gsub("(%d),(%d)", "%1.%2"):gsub(",", ".")
    local pos = 1
    local function skip() pos = src:find("%S", pos) or (#src + 1) end
    local function peek() skip() return src:sub(pos, pos) end
    local expr
    local function primary()
        local c = peek()
        if c == "(" then
            pos = pos + 1
            local v = expr()
            if peek() ~= ")" then error("Klammer fehlt", 0) end
            pos = pos + 1
            return v
        end
        local num = src:match("^%d*%.?%d+[eE][%+%-]?%d+", pos) or src:match("^%d+%.?%d*", pos) or src:match("^%.%d+", pos)
        if num then pos = pos + #num return tonumber(num) end
        local id = src:match("^%a+", pos)
        if id then
            pos = pos + #id
            id = id:lower()
            if CONST[id] then return CONST[id] end
            local f = FN[id]
            if not f then error("unbekannt: " .. id, 0) end
            return f(primary())
        end
        error(c == "" and "Ausdruck unvollständig" or ("unerwartet: " .. c), 0)
    end
    local function power()
        local b = primary()
        if peek() == "^" then pos = pos + 1 local u = power() return b ^ u end
        if peek() == "!" then
            pos = pos + 1
            if b < 0 or b > 170 or b % 1 ~= 0 then error("Fakultät nur 0..170", 0) end
            local r = 1 for i = 2, b do r = r * i end
            return r
        end
        return b
    end
    local function unary()
        local c = peek()
        if c == "-" then pos = pos + 1 return -unary() end
        if c == "+" then pos = pos + 1 return unary() end
        return power()
    end
    local function term()
        local v = unary()
        while true do
            local c = peek()
            if c == "*" then pos = pos + 1 v = v * unary()
            elseif c == "/" then pos = pos + 1 local d = unary() if d == 0 then error("Division durch 0", 0) end v = v / d
            elseif c == "%" then pos = pos + 1 local d = unary() if d == 0 then error("Division durch 0", 0) end v = v % d
            elseif c == "(" or c:match("%a") then v = v * unary()      -- 2(3+4), 2pi
            else return v end
        end
    end
    expr = function()
        local v = term()
        while true do
            local c = peek()
            if c == "+" then pos = pos + 1 v = v + term()
            elseif c == "-" then pos = pos + 1 v = v - term()
            else return v end
        end
    end
    local v = expr()
    if pos <= #src then error("unerwartet: " .. src:sub(pos, pos), 0) end
    if v ~= v then error("keine Zahl", 0) end
    if v == math.huge or v == -math.huge then error("zu groß", 0) end
    return v
end
A.evaluate = evaluate

local function fmt(v)
    if not v then return "" end
    if math.abs(v) >= 1e15 or (math.abs(v) < 1e-6 and v ~= 0) then return (string.format("%.6g", v):gsub("%.", ",")) end
    if v % 1 == 0 then
        local s = string.format("%d", v)
        return (s:reverse():gsub("(%d%d%d)", "%1."):reverse():gsub("^(%-?)%.", "%1"))
    end
    local s = string.format("%.10f", v):gsub("0+$", ""):gsub("%.$", "")
    local int, frac = s:match("^(%-?%d+)%.?(%d*)$")
    int = int:reverse():gsub("(%d%d%d)", "%1."):reverse():gsub("^(%-?)%.", "%1")
    return int .. (frac ~= "" and ("," .. frac) or "")
end
A.fmt = fmt

local function calc()
    if A.expr == "" then return end
    local ok, v = pcall(evaluate, A.expr)
    if ok then
        A.result, A.err = v, nil
        table.insert(A.hist, 1, { e = A.expr, r = v })
        while #A.hist > 30 do table.remove(A.hist) end
        S.save(HIST, A.hist)
        A.done = true
    else
        A.err = tostring(v)
    end
end
local function press(k)
    A.err = nil
    if k == "C" then A.expr, A.result, A.done = "", nil, false return end
    if k == "⌫" then A.expr = G.sub(A.expr, 1, G.len(A.expr) - 1) A.done = false return end
    if k == "=" then calc() return end
    if A.done then
        -- nach "=" rechnet ein Operator mit dem Ergebnis weiter, eine Zahl beginnt neu
        if k:match("^[%+%−%×%÷%^%%]") or k == "−" or k == "×" or k == "÷" or k == "²" then A.expr = fmt(A.result):gsub("%.", "") else A.expr = "" end
        A.done = false
    end
    A.expr = A.expr .. k
end

-- ---------------------------------------------------------------------
-- Zeichnen
-- ---------------------------------------------------------------------
local KEYS = {
    { "C", "(", ")", "÷" },
    { "7", "8", "9", "×" },
    { "4", "5", "6", "−" },
    { "1", "2", "3", "+" },
    { "0", ",", "⌫", "=" },
}
local EXTRA = { "√", "²", "^", "%", "π" }

local function drawCalc(x, y, w, h)
    local wide = w >= 110
    local cw = wide and math.min(70, math.floor(w * 0.55)) or w
    -- Anzeige
    local dh = (h >= 30) and 7 or 6
    local ix, iy, iw = UI.card(x, y, cw, dh, nil)
    G.right(ix + iw - 1, iy, G.fit(A.expr ~= "" and A.expr or "0", iw), A.done and C.muted or C.text, C.card)
    local res = A.err and A.err or (A.result and fmt(A.result) or "")
    if A.err then
        G.right(ix + iw - 1, iy + 2, G.fit(res, iw), C.bad, C.card)
    elseif res ~= "" then
        local bw = G.bigWidth(res)
        if bw <= iw then G.big(ix + iw - bw, iy + 1, res, A.done and C.accent or C.dim, C.card)
        else G.right(ix + iw - 1, iy + 2, G.fit("= " .. res, iw), C.accent, C.card) end
    end
    -- Tasten
    local ky = y + dh + 1
    local avail = y + h - ky
    local function colX(c, n) return x + math.floor((c - 1) * (cw + 1) / n) end
    local function colW(c, n) return colX(c + 1, n) - colX(c, n) - 1 end
    -- Funktionsreihe (wenn Platz ist)
    if avail >= 14 then
        for i, k in ipairs(EXTRA) do
            UI.button({ x = colX(i, 5), y = ky, w = colW(i, 5), h = 1, text = k, style = "subtle", onClick = function() press(k == "√" and "√(" or k) end })
        end
        ky = ky + 2
        avail = avail - 2
    end
    local kh = math.max(1, math.min(3, math.floor((avail + 1) / #KEYS) - 1))
    for r, row in ipairs(KEYS) do
        for c, k in ipairs(row) do
            local style = (k == "=") and "primary" or ((c == 4 or k == "C") and "accent" or "subtle")
            UI.button({ x = colX(c, 4), y = ky + (r - 1) * (kh + 1), w = colW(c, 4), h = kh, text = k, style = style,
                        onClick = function() press(k) end })
        end
    end
    -- Verlauf
    if wide then
        local hx, hy, hw, hh = UI.card(x + cw + 2, y, w - cw - 2, h, "VERLAUF", { right = #A.hist > 0 and "LEEREN" or nil })
        if #A.hist > 0 then UI.region(x + w - 10, y + 1, 8, 1, function() A.hist = {} S.save(HIST, A.hist) end) end
        if #A.hist == 0 then G.text(hx, hy, "Noch nichts gerechnet", C.muted, C.card) end
        for i, e in ipairs(A.hist) do
            local yy = hy + (i - 1) * 2
            if yy + 1 > hy + hh - 1 then break end
            G.right(hx + hw - 1, yy, G.fit(e.e, hw), C.muted, C.card)
            G.right(hx + hw - 1, yy + 1, "= " .. fmt(e.r), C.text, C.card)
            UI.region(hx, yy, hw, 2, function() A.expr, A.result, A.done, A.err = fmt(e.r):gsub("%.", ""), e.r, false, nil end)
        end
    end
end

-- Umrechner ----------------------------------------------------------------
local CONV = {
    stacks = { title = "STACKS", units = { "Items" }, rows = function(v)
        local function st(n, size) return string.format("%s Stacks + %s", fmt(math.floor(n / size)), fmt(n % size)) end
        return {
            { "Stacks zu 64", st(v, 64) }, { "Stacks zu 16", st(v, 16) },
            { "Kisten (27 Plätze)", string.format("%s", fmt(math.ceil(v / (27 * 64) * 100) / 100)) },
            { "Doppelkisten (54)", string.format("%s", fmt(math.ceil(v / (54 * 64) * 100) / 100)) },
        }
    end },
    energie = { title = "ENERGIE", units = { "RF", "EU", "J" }, rows = function(v, u)
        -- Mekanism-Standard: 1 EU = 4 RF = 10 J
        local rf = (u == "EU" and v * 4) or (u == "J" and v * 0.4) or v
        return { { "RF (Redstone Flux)", fmt(rf) }, { "EU (IndustrialCraft)", fmt(rf / 4) }, { "J (Mekanism)", fmt(rf * 2.5) },
                 { "WarpDrive (EU)", fmt(rf / 4) }, { "bei 20 Mio RF/t", fmt(rf / 2e7) .. " Ticks = " .. fmt(rf / 2e7 / 20) .. " s" } }
    end },
    zeit = { title = "ZEIT", units = { "Ticks", "Sekunden", "Minuten", "MC-Tage" }, rows = function(v, u)
        local t = (u == "Sekunden" and v * 20) or (u == "Minuten" and v * 1200) or (u == "MC-Tage" and v * 24000) or v
        return { { "Ticks", fmt(t) }, { "Sekunden", fmt(t / 20) }, { "Minuten", fmt(t / 1200) }, { "Stunden", fmt(t / 72000) },
                 { "Minecraft-Tage", fmt(t / 24000) } }
    end },
    strecke = { title = "STRECKE", units = { "Blöcke", "Chunks", "Regionen" }, rows = function(v, u)
        local b = (u == "Chunks" and v * 16) or (u == "Regionen" and v * 512) or v
        return { { "Blöcke", fmt(b) }, { "Chunks", fmt(b / 16) }, { "Regionen (32 Chunks)", fmt(b / 512) },
                 { "Drohne (8 m/s)", fmt(b / 8) .. " s" }, { "Nether (÷ 8)", fmt(b / 8) .. " Blöcke" } }
    end },
}
local CONV_ORDER = { "stacks", "energie", "zeit", "strecke" }
local function drawConv(x, y, w, h)
    local cw = math.min(w, 90)
    local ix, iy, iw, ih = UI.card(x, y, cw, h, nil)
    local cx = ix
    for _, id in ipairs(CONV_ORDER) do
        cx = UI.chip(cx, iy, CONV[id].title, A.conv == id, function() A.conv = id A.unit = nil end) + 1
    end
    local c = CONV[A.conv]
    A.unit = A.unit or c.units[1]
    G.text(ix, iy + 2, "Wert", C.muted, C.card)
    G.fill(ix + 10, iy + 2, 20, 1, C.bg2)
    G.right(ix + 28, iy + 2, fmt(A.value), C.text, C.bg2)
    UI.button({ x = ix + 31, y = iy + 2, w = 4, text = "✎", style = "subtle", onClick = function()
        UI.prompt({ title = "Wert (auch Rechnung, z.B. 27*64)", text = fmt(A.value):gsub("%.", ""), signed = false, maxLen = 30,
                    validate = function(t) local ok = pcall(evaluate, t) if not ok then return "Keine gültige Zahl/Rechnung" end end,
                    onOk = function(t) A.value = evaluate(t) end })
    end })
    if #c.units > 1 then
        local ux = ix + 37
        for _, u in ipairs(c.units) do ux = UI.chip(ux, iy + 2, u, A.unit == u, function() A.unit = u end) + 1 end
    end
    local yy = iy + 4
    for _, r in ipairs(c.rows(A.value, A.unit)) do
        if yy > iy + ih - 1 then break end
        G.text(ix, yy, G.fit(r[1], 26), C.muted, C.card)
        G.text(ix + 28, yy, G.fit(r[2], iw - 28), C.text, C.card)
        yy = yy + 2
    end
    if A.conv == "energie" and yy < iy + ih - 1 then G.text(ix, yy, "Umrechnung nach Mekanism-Standard: 1 EU = 4 RF = 10 J", C.muted, C.card) end
end

function A.draw(x, y, w, h)
    local pad = (w < 100) and 1 or 2
    x, w = x + pad, w - pad * 2
    G.text(x, y + 1, "RECHNER", C.text)
    UI.tabs(x, y + 3, w, { { id = "calc", text = "RECHNER" }, { id = "conv", text = "UMRECHNER" } }, A.view, function(v) A.view = v end)
    local top = y + 5
    if A.view == "calc" then drawCalc(x, top, w, y + h - top) else drawConv(x, top, w, y + h - top) end
end
function A.key(char, code)
    if A.view ~= "calc" then return end
    if code == 28 then press("=") return end
    if code == 14 then press("⌫") return end
    if code == 1 or code == 211 then press("C") return end
    if char and char >= 32 then
        local c = unicode and unicode.char(char) or string.char(char)
        if c == "*" then c = "×" elseif c == "/" then c = "÷" elseif c == "-" then c = "−" end
        if c == "=" then press("=") return end
        if c:match("[%d%.,%+%(%)%^%%%a!×÷−]") then press(c) end
    end
end
function A.paste(t) A.expr = A.expr .. tostring(t):gsub("[\r\n]", "") A.done = false end
return A
