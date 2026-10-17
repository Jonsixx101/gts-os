-- ======================================================================
-- GTS OS (OpenComputers) - gfx: Bildpuffer, Farben, Zeichen
-- ======================================================================
-- Alles wird in einen Puffer gezeichnet und danach nur die Zeilen, die
-- sich geaendert haben, an die GPU geschickt - nach Farbpaaren sortiert,
-- damit setForeground/setBackground selten aufgerufen werden (jeder
-- GPU-Aufruf kostet Rechenzeit, siehe OC "call budget").
-- Speicher: zwei flache Tabellen (Zeichen, Farbpaar) statt Zeilen-Tabellen
-- und je Zeile nur ein Schluessel-Text fuer den Vergleich - bei 160x50
-- rund 300 KB statt 1,2 MB.
--
-- Farben: Zahlen 0..15 sind die 16 Themenfarben, groessere Zahlen sind RGB.
-- Farbmodus (Einstellung colorMode, F10 schaltet um):
--  * rgb     - (Standard, AUTO) alles als echte RGB-Farbe senden, die Palette
--              der Karte bleibt Standard. Robust: haengt nicht davon ab, dass
--              Palettenwechsel beim Spieler ankommen. Auf manchen Servern tun
--              sie das nicht - dann sah man die OC-Standardpalette: weisser
--              Hintergrund, rosa/pinke Karten, unleserliche Schrift.
--              8 Bit (Tier 3): naechste der 256 festen Farben (fast exakt).
--              4 Bit (Tier 2): naechste der 16 Standardfarben (dunkel, gut lesbar).
--  * palette - Themenfarben exakt in die 16 Palettenplaetze schreiben (nur
--              sinnvoll, wenn die Palette beim Spieler ankommt)
--  * mono    - 1 Bit (Tier 1): hell/dunkel nach Helligkeit, Text immer lesbar
-- Jeder setPaletteColor pausiert den Rechner in OC 0,1 s - darum sparsam.
local G = {}
local gpu, screenAddr
local W, H = 80, 25
local cb, cc = {}, {}              -- Rueckpuffer: Zeichen, Farbpaar (fg + bg * P), Index (y-1)*W+x
local front = {}                   -- je Zeile: Inhalt, der auf dem Schirm steht (als Text)
local floor = math.floor
local P = 16777216                 -- 2^24: Farben sind Palettenplatz (<16) oder RGB (<2^24)
local clip = nil
local depth = 8
G.useRGB = false                   -- true: echte RGB-Farben senden (Modus rgb oder Palette haelt nicht)
G.mode = "auto"                    -- Einstellung: auto | rgb | palette
G.active = "rgb"                   -- tatsaechlich genutzt: rgb | palette | mono
G.stats = { flushes = 0, sets = 0, colors = 0 }

-- Palettenplaetze (Namen fuer die Apps)
G.C = { bg = 0, bg2 = 1, card = 2, raised = 3, line = 4, muted = 5, dim = 6, text = 7,
        accent = 8, accentDim = 9, onAccent = 10, warn = 11, bad = 12, info = 13, shadow = 14, white = 15 }
local C = G.C

-- Themen: 16 Farben je Thema (Platz 8-10 setzt die Akzentfarbe)
G.THEMES = {
    graphit     = { name = "Graphit",     0x101318, 0x161A21, 0x1D222B, 0x272D38, 0x353C49, 0x5E6678, 0x9AA3B5, 0xE7EAF0 },
    mitternacht = { name = "Mitternacht", 0x0B0F1A, 0x111729, 0x18203A, 0x212B4A, 0x2E3A5E, 0x56648C, 0x93A0C4, 0xE6EAF5 },
    wald        = { name = "Wald",        0x0E1411, 0x131B17, 0x1A241F, 0x233029, 0x2F3F36, 0x587063, 0x93A99C, 0xE5EEE8 },
    imperium    = { name = "Imperium",    0x0A0A0B, 0x121214, 0x1A1A1D, 0x242428, 0x323237, 0x5C5C64, 0x9C9CA6, 0xEDEDF0 },
    hell        = { name = "Hell",        0xEEF1F5, 0xE3E7ED, 0xFFFFFF, 0xF2F4F7, 0xCDD3DC, 0x8A93A3, 0x5A6272, 0x161A21, light = true },
}
G.THEME_ORDER = { "graphit", "mitternacht", "wald", "imperium", "hell" }
-- Akzente: { Akzent, gedimmt (auf dunkel), Text auf Akzent }
G.ACCENTS = {
    gruen  = { name = "Grün",  0x3DDC84, 0x1C5E3C, 0x06150D },
    blau   = { name = "Blau",   0x4C9AFF, 0x1E4170, 0x061325 },
    tuerkis = { name = "Türkis", 0x2EC4B6, 0x165C56, 0x041513 },
    orange = { name = "Orange", 0xFF9F43, 0x6E4216, 0x1C0E02 },
    lila   = { name = "Lila",   0xA78BFA, 0x45396E, 0x120C24 },
    rosa   = { name = "Rosa",   0xF472B6, 0x6B2F4F, 0x1F0814 },
    rot    = { name = "Rot",    0xFF5A5F, 0x6E2224, 0x1F0607 },
    weiss  = { name = "Weiß",  0xE7EAF0, 0x4A5160, 0x101318 },
}
G.ACCENT_ORDER = { "gruen", "blau", "tuerkis", "orange", "lila", "rosa", "rot", "weiss" }
local STATUS = { 0xF5A623, 0xFF5A5F, 0x4AA3FF, 0x07090C, 0xFFFFFF }   -- warn, bad, info, shadow, white
G.palette = {}

function G.applyTheme(themeId, accentId)
    local t = G.THEMES[themeId] or G.THEMES.graphit
    local a = G.ACCENTS[accentId] or G.ACCENTS.gruen
    local p = {}
    for i = 1, 8 do p[i - 1] = t[i] end
    p[8], p[9], p[10] = a[1], a[2], a[3]
    if t.light then p[9] = a[1] end
    p[11], p[12], p[13], p[14], p[15] = STATUS[1], STATUS[2], STATUS[3], t.light and 0xC4CAD4 or STATUS[4], STATUS[5]
    G.palette = p
    G.light = t.light == true
    if gpu then G.verifyPalette() end
    G.invalidate()
end

-- Farbmodus festlegen und (nur im Palettenmodus) die Palette schreiben und
-- PRUEFEN. Haelt sie nicht (Server setzt sie zurueck), geht es mit RGB weiter.
function G.verifyPalette()
    if not gpu then return end
    if depth <= 1 then G.useRGB, G.active = true, "mono" return end
    local want = G.mode
    if want ~= "palette" then want = "rgb" end
    if want == "rgb" then
        -- Standardpalette wiederherstellen (setDepth setzt sie bei Server UND
        -- Spieler zurueck), damit RGB-Farben ueberall gleich aussehen
        if G.active == "palette" then pcall(gpu.setDepth, depth) end
        G.useRGB, G.active = true, "rgb"
        return
    end
    for _ = 1, 2 do
        for i = 0, 15 do pcall(gpu.setPaletteColor, i, G.palette[i]) end
        local ok, c0 = pcall(gpu.getPaletteColor, 0)
        if ok and c0 == G.palette[0] then G.useRGB, G.active = false, "palette" G.palNext = 0 return end
    end
    G.useRGB, G.active = true, "rgb"
end
function G.setMode(m)
    G.mode = m or "auto"
    G.verifyPalette()
    G.resetColorCache()
    G.invalidate()
end
-- Palettenmodus: je Aufruf EINEN Platz neu senden (falls der Spieler die
-- Palette verloren hat). Abweichungen beim Server werden sofort repariert.
function G.reassertPalette()
    if not gpu or G.active ~= "palette" then return end
    for i = 0, 15 do
        local ok, c = pcall(gpu.getPaletteColor, i)
        if ok and c ~= G.palette[i] then pcall(gpu.setPaletteColor, i, G.palette[i]) end
    end
    local n = G.palNext or 0
    pcall(gpu.setPaletteColor, n, G.palette[n])
    G.palNext = (n + 1) % 16
end

-- Farbe als RGB (fuer Mischungen und den Test)
function G.rgb(c) if c < 16 then return G.palette[c] or 0 end return c end
-- Mischung zweier Farben (RGB-Ergebnis, landet im 240er-Wuerfel)
function G.mix(a, b, t)
    a, b = G.rgb(a), G.rgb(b)
    local function ch_(v, s) return math.floor(v / s) % 256 end
    local r = ch_(a, 65536) + (ch_(b, 65536) - ch_(a, 65536)) * t
    local g = ch_(a, 256) + (ch_(b, 256) - ch_(a, 256)) * t
    local bb = a % 256 + (b % 256 - a % 256) * t
    local v = math.floor(r + 0.5) * 65536 + math.floor(g + 0.5) * 256 + math.floor(bb + 0.5)
    if v < 16 then v = 16 end
    return v
end

-- ---------------------------------------------------------------------
-- Bildschirm
-- ---------------------------------------------------------------------
local function alloc()
    cb, cc, front = {}, {}, {}
    local def = C.text + C.bg * P
    for i = 1, W * H do cb[i] = " " cc[i] = def end
end

-- Aufloesung passend zum Seitenverhaeltnis des Bildschirms (Zeichen 1:2)
function G.autoResolution(maxW, maxH, aw, ah)
    if not aw or not ah or aw < 1 or ah < 1 then return maxW, maxH end
    local ratio = 2 * aw / ah                 -- Zeichenbreite je Zeile fuer gleiches Bild
    local h = maxH
    local w = math.floor(h * ratio + 0.5)
    if w > maxW then w = maxW h = math.floor(w / ratio + 0.5) end
    return math.max(50, math.min(maxW, w)), math.max(16, math.min(maxH, h))
end

function G.init(gpuProxy, scr, want)
    gpu = gpuProxy
    screenAddr = scr
    if scr and gpu.getScreen() ~= scr then gpu.bind(scr) end
    depth = gpu.maxDepth and gpu.maxDepth() or 8
    pcall(gpu.setDepth, depth)
    local mw, mh = gpu.maxResolution()
    local w, h = mw, mh
    if want and want.w then
        w, h = math.min(mw, want.w), math.min(mh, want.h)
    elseif want and want.aw then
        w, h = G.autoResolution(mw, mh, want.aw, want.ah)
        -- Skalierung: weniger Zeichen, groessere Schrift (nicht unter 80x25)
        local f = want.f or 1
        if f < 1 then
            local ratio = w / h
            local nh = math.max(25, math.floor(h * f + 0.5))
            local nw = math.floor(nh * ratio + 0.5)
            if nw < 80 then nw = 80 nh = math.max(25, math.floor(nw / ratio + 0.5)) end
            w, h = math.min(mw, nw), math.min(mh, nh)
        end
    end
    pcall(gpu.setResolution, w, h)
    W, H = gpu.getResolution()
    G.depth = depth
    alloc()
    G.active = "rgb"                      -- setDepth oben hat die Palette ohnehin zurueckgesetzt
    if G.palette[0] then G.verifyPalette() end
    G.resetColorCache()
    G.invalidate()
    return W, H
end
function G.size() return W, H end
function G.gpu() return gpu end
function G.invalidate() front = {} end

-- ---------------------------------------------------------------------
-- Zeichnen in den Puffer
-- ---------------------------------------------------------------------
local PAT = "[%z\1-\127\194-\244][\128-\191]*"
local cache = setmetatable({}, { __mode = "k" })
local function chars(s)
    local t = {}
    for c in s:gmatch(PAT) do t[#t + 1] = c end
    return t
end
G.chars = chars
function G.len(s)
    local n = 0
    for _ in tostring(s):gmatch(PAT) do n = n + 1 end
    return n
end
function G.sub(s, i, j)
    local t = chars(tostring(s))
    return table.concat(t, "", math.max(1, i or 1), math.min(#t, j or #t))
end
-- auf Breite kuerzen (mit "..")
function G.fit(s, w)
    s = tostring(s or "")
    if w <= 0 then return "" end
    if G.len(s) <= w then return s end
    if w <= 2 then return G.sub(s, 1, w) end
    return G.sub(s, 1, w - 1) .. "…"
end

function G.setClip(x, y, w, h)
    if not x then clip = nil return end
    clip = { x1 = x, y1 = y, x2 = x + w - 1, y2 = y + h - 1 }
end
function G.getClip() return clip end
local function inClip(x, y)
    if x < 1 or y < 1 or x > W or y > H then return false end
    if clip and (x < clip.x1 or x > clip.x2 or y < clip.y1 or y > clip.y2) then return false end
    return true
end

local function set(i, c, f, b)
    cb[i] = c
    if f or b then
        local v = cc[i]
        local of = v % P
        cc[i] = (f or of) + (b or floor(v / P)) * P
    end
end
function G.put(x, y, c, f, b)
    if inClip(x, y) then set((y - 1) * W + x, c, f, b) end
end
-- Text; f/b nil = Farbe darunter behalten
function G.text(x, y, s, f, b)
    s = tostring(s)
    if y < 1 or y > H then return x end
    if clip and (y < clip.y1 or y > clip.y2) then return x + G.len(s) end
    local row = (y - 1) * W
    for c in s:gmatch(PAT) do
        if inClip(x, y) then set(row + x, c, f, b) end
        x = x + 1
    end
    return x
end
function G.fill(x, y, w, h, b, c, f)
    c = c or " "
    for yy = y, y + h - 1 do
        if yy >= 1 and yy <= H then
            local row = (yy - 1) * W
            for xx = x, x + w - 1 do
                if inClip(xx, yy) then
                    local i = row + xx
                    cb[i] = c
                    cc[i] = (f or cc[i] % P) + b * P
                end
            end
        end
    end
end
function G.clear(b) G.fill(1, 1, W, H, b or C.bg) end
function G.getBg(x, y)
    if y >= 1 and y <= H and x >= 1 and x <= W then local v = cc[(y - 1) * W + x] return floor(v / P) end
    return C.bg
end
function G.getCell(x, y)
    if y >= 1 and y <= H and x >= 1 and x <= W then
        local i = (y - 1) * W + x
        local v = cc[i]
        return cb[i], v % P, floor(v / P)
    end
end
-- Text zentriert in [x, x+w)
function G.center(x, y, w, s, f, b)
    s = G.fit(s, w)
    return G.text(x + math.floor((w - G.len(s)) / 2), y, s, f, b)
end
function G.right(xr, y, s, f, b)
    return G.text(xr - G.len(s) + 1, y, s, f, b)
end

-- Weiche Kanten: halbe Zeichen oben/unten (Karte beginnt "in der Mitte" der Zelle)
-- Fuellt den Bereich und setzt oben ▄ bzw. unten ▀ in der Kartenfarbe.
function G.softBox(x, y, w, h, b, parent)
    parent = parent or C.bg
    if h <= 2 then G.fill(x, y, w, h, b) return end
    for xx = x, x + w - 1 do
        G.put(xx, y, "▄", b, parent)
        G.put(xx, y + h - 1, "▀", b, parent)
    end
    G.fill(x, y + 1, w, h - 2, b)
end
-- Schatten unter einer Flaeche (eine halbe Zeile)
function G.shadow(x, y, w, parent)
    for xx = x, x + w - 1 do
        local c, f, b = G.getCell(xx, y)
        if c then G.put(xx, y, "▀", C.shadow, parent or b) end
    end
end

-- Linien
function G.hline(x, y, w, f, b, c) for xx = x, x + w - 1 do G.put(xx, y, c or "─", f, b) end end
function G.vline(x, y, h, f, b, c) for yy = y, y + h - 1 do G.put(x, yy, c or "│", f, b) end end
function G.frame(x, y, w, h, f, b, round)
    local tl, tr, bl, br = "┌", "┐", "└", "┘"
    if round then tl, tr, bl, br = "╭", "╮", "╰", "╯" end
    G.put(x, y, tl, f, b) G.put(x + w - 1, y, tr, f, b)
    G.put(x, y + h - 1, bl, f, b) G.put(x + w - 1, y + h - 1, br, f, b)
    G.hline(x + 1, y, w - 2, f, b) G.hline(x + 1, y + h - 1, w - 2, f, b)
    G.vline(x, y + 1, h - 2, f, b) G.vline(x + w - 1, y + 1, h - 2, f, b)
end

-- Balken mit Achtel-Zeichen (feine Fuellstaende)
local EIGHTHS = { "▏", "▎", "▍", "▌", "▋", "▊", "▉" }
function G.bar(x, y, w, frac, f, b)
    frac = math.max(0, math.min(1, frac or 0))
    local units = math.floor(frac * w * 8 + 0.5)
    for i = 0, w - 1 do
        local u = units - i * 8
        if u >= 8 then G.put(x + i, y, " ", f, f)
        elseif u <= 0 then G.put(x + i, y, " ", b, b)
        else G.put(x + i, y, EIGHTHS[u], f, b) end
    end
end
-- duenner Balken (halbe Hoehe, unten)
function G.thinBar(x, y, w, frac, f, b, parent)
    frac = math.max(0, math.min(1, frac or 0))
    local n = math.floor(frac * w + 0.5)
    for i = 0, w - 1 do G.put(x + i, y, "▄", (i < n) and f or b, parent) end
end

-- Braille-Verlauf (2x4 Punkte je Zelle): Werte 0..1, aelteste links
local BR = { { 0x01, 0x08 }, { 0x02, 0x10 }, { 0x04, 0x20 }, { 0x40, 0x80 } }
local function braille(bits)
    local cp = 0x2800 + bits
    return string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
end
G.braille = braille
function G.spark(x, y, w, h, values, f, b, filled)
    local cols = w * 2
    local n = #values
    local dots = h * 4
    for cx = 0, w - 1 do
        for cy = 0, h - 1 do
            local bits = 0
            for sx = 1, 2 do
                local i = n - cols + cx * 2 + sx
                local v = values[i]
                if v then
                    local level = math.floor(math.max(0, math.min(1, v)) * (dots - 1) + 0.5)  -- 0 = unten
                    for sy = 1, 4 do
                        local dotRow = (h - 1 - cy) * 4 + (4 - sy)   -- 0 = unterster Punkt
                        if dotRow == level or (filled and dotRow < level) then bits = bits + BR[sy][sx] end
                    end
                end
            end
            G.put(x + cx, y + cy, bits > 0 and braille(bits) or " ", f, b)
        end
    end
end

-- Braille-Leinwand: w x h Zellen = 2w x 4h Punkte (Punkte sind etwa quadratisch)
function G.canvas(w, h)
    local cv = { w = w, h = h, cells = {} }
    function cv.set(px, py)
        px, py = math.floor(px + 0.5), math.floor(py + 0.5)
        if px < 0 or py < 0 or px >= w * 2 or py >= h * 4 then return end
        local k = math.floor(py / 4) * w + math.floor(px / 2)
        local bit = BR[py % 4 + 1][px % 2 + 1]
        local v = cv.cells[k] or 0
        if math.floor(v / bit) % 2 == 0 then cv.cells[k] = v + bit end
    end
    -- Kreis um (cx, cy) in Punkten; step = jeder wievielte Punkt (gestrichelt)
    function cv.circle(cx, cy, r, step)
        local n = math.max(8, math.floor(2 * math.pi * r))
        for i = 0, n - 1 do
            if not step or i % step == 0 then
                local a = i / n * 2 * math.pi
                cv.set(cx + math.cos(a) * r, cy + math.sin(a) * r)
            end
        end
    end
    function cv.line(x0, y0, x1, y1, step)
        local n = math.max(math.abs(x1 - x0), math.abs(y1 - y0))
        for i = 0, n do
            if not step or i % step == 0 then cv.set(x0 + (x1 - x0) * i / math.max(1, n), y0 + (y1 - y0) * i / math.max(1, n)) end
        end
    end
    -- nur Zellen mit Punkten zeichnen (der Rest bleibt, wie er ist)
    function cv.draw(x, y, f, b)
        for k, bits in pairs(cv.cells) do
            local cx, cy = k % w, math.floor(k / w)
            G.put(x + cx, y + cy, braille(bits), f, b)
        end
    end
    return cv
end

-- Pixelschrift 3x5 (fuer Uhr und Logo), gezeichnet mit Halbbloecken
local FONT = {
    ["0"] = { "111", "101", "101", "101", "111" }, ["1"] = { "010", "110", "010", "010", "111" },
    ["2"] = { "111", "001", "111", "100", "111" }, ["3"] = { "111", "001", "011", "001", "111" },
    ["4"] = { "101", "101", "111", "001", "001" }, ["5"] = { "111", "100", "111", "001", "111" },
    ["6"] = { "111", "100", "111", "101", "111" }, ["7"] = { "111", "001", "010", "010", "010" },
    ["8"] = { "111", "101", "111", "101", "111" }, ["9"] = { "111", "101", "111", "001", "111" },
    [":"] = { "0", "1", "0", "1", "0" }, [" "] = { "0", "0", "0", "0", "0" },
    G = { "111", "100", "101", "101", "111" }, T = { "111", "010", "010", "010", "010" },
    S = { "111", "100", "111", "001", "111" }, O = { "111", "101", "101", "101", "111" },
    C = { "111", "100", "100", "100", "111" }, D = { "110", "101", "101", "101", "110" },
    E = { "111", "100", "110", "100", "111" }, R = { "110", "101", "110", "101", "101" },
    N = { "101", "111", "111", "101", "101" }, A = { "010", "101", "111", "101", "101" },
    L = { "100", "100", "100", "100", "111" }, K = { "101", "101", "110", "101", "101" },
    I = { "111", "010", "010", "010", "111" }, H = { "101", "101", "111", "101", "101" },
    U = { "101", "101", "101", "101", "111" }, P = { "111", "101", "111", "100", "100" },
    M = { "101", "111", "111", "101", "101" }, B = { "110", "101", "110", "101", "110" },
    F = { "111", "100", "110", "100", "100" }, W = { "101", "101", "111", "111", "101" },
    ["-"] = { "000", "000", "111", "000", "000" }, ["+"] = { "000", "010", "111", "010", "000" },
    ["."] = { "0", "0", "0", "0", "1" }, [","] = { "0", "0", "0", "1", "1" }, ["%"] = { "101", "001", "010", "100", "101" },
    ["/"] = { "001", "001", "010", "100", "100" }, ["="] = { "000", "111", "000", "111", "000" },
    V = { "101", "101", "101", "101", "010" }, Y = { "101", "101", "010", "010", "010" }, X = { "101", "101", "010", "101", "101" },
    Z = { "111", "001", "010", "100", "111" }, J = { "001", "001", "001", "101", "111" }, Q = { "111", "101", "101", "111", "001" },
}
-- Breite eines Pixeltextes in Zeichen
function G.bigWidth(s)
    local w = 0
    for c in tostring(s):upper():gmatch(".") do w = w + #(FONT[c] or FONT[" "])[1] + 1 end
    return math.max(0, w - 1)
end
-- zeichnet in 3 Zeilen (5 Pixel hoch, oben leere halbe Zeile)
function G.big(x, y, s, f, b)
    local cx = x
    for c in tostring(s):upper():gmatch(".") do
        local g = FONT[c] or FONT[" "]
        local gw = #g[1]
        for col = 1, gw do
            for row = 0, 2 do
                local top = row * 2 - 1        -- Pixelzeilen: -1(leer),0 | 1,2 | 3,4
                local p1 = (top >= 0) and g[top + 1]:sub(col, col) == "1"
                local p2 = g[top + 2] and g[top + 2]:sub(col, col) == "1"
                local glyph = (p1 and p2) and "█" or (p1 and "▀") or (p2 and "▄") or " "
                G.put(cx + col - 1, y + row, glyph, f, b)
            end
        end
        cx = cx + gw + 1
    end
    return cx
end

-- ---------------------------------------------------------------------
-- Ausgabe an die GPU (nur Aenderungen, nach Farben gebuendelt)
-- ---------------------------------------------------------------------
local curF, curB = nil, nil
local concat = table.concat
-- Farbwert fuer die GPU: Palettenplatz (schnell) oder echtes RGB, wenn die
-- Palette nicht haelt (G.useRGB). Grosse Zahlen sind ohnehin RGB.
-- Helligkeit 0..1
local function lum(v)
    return (floor(v / 65536) % 256 * 0.2126 + floor(v / 256) % 256 * 0.7152 + v % 256 * 0.0722) / 255
end
G.lum = lum
local function toGpu(c, isBg)
    if depth <= 1 then
        -- Schwarz/Weiss: Flaechen erst ab hell weiss, Schrift schon ab mittel
        local v = c < 16 and (G.palette[c] or 0) or c
        if isBg then return lum(v) > 0.55 and 0xFFFFFF or 0, false end
        return lum(v) > 0.22 and 0xFFFFFF or 0, false
    end
    if c < 16 then
        if G.useRGB then return G.palette[c] or 0, false end
        return c, true
    end
    return c, false
end
function G.flush()
    if not gpu then return end
    local buckets, order = {}, {}
    local runs = 0
    for y = 1, H do
        local i0 = (y - 1) * W
        local key = concat(cb, "", i0 + 1, i0 + W) .. "|" .. concat(cc, ",", i0 + 1, i0 + W)
        if key ~= front[y] then
            front[y] = key
            local x = 1
            while x <= W do
                local v = cc[i0 + x]
                local x0 = x
                while x < W and cc[i0 + x + 1] == v do x = x + 1 end
                local bk = buckets[v]
                if not bk then bk = {} buckets[v] = bk order[#order + 1] = v end
                bk[#bk + 1] = { x0, y, concat(cb, "", i0 + x0, i0 + x) }
                runs = runs + 1
                x = x + 1
            end
        end
    end
    if runs == 0 then return 0 end
    -- nach Hintergrund sortiert, damit setBackground selten ist
    table.sort(order, function(a, b)
        local ba, bb = floor(a / P), floor(b / P)
        if ba ~= bb then return ba < bb end
        return a % P < b % P
    end)
    for _, v in ipairs(order) do
        local f, b = v % P, floor(v / P)
        if depth <= 1 then
            -- Schwarz/Weiss: Schrift nie in der Flaechenfarbe (Kanten-Zeichen ▄▀ duerfen verschwinden)
            local bv = toGpu(b, true)
            local fv = toGpu(f, false)
            if bv ~= curB then gpu.setBackground(bv) curB = bv G.stats.colors = G.stats.colors + 1 end
            local bk = buckets[v]
            for _, r in ipairs(bk) do
                local fr = fv
                if fr == bv and r[3]:find("[%w]") then fr = (bv == 0) and 0xFFFFFF or 0 end
                if fr ~= curF then gpu.setForeground(fr) curF = fr G.stats.colors = G.stats.colors + 1 end
                gpu.set(r[1], r[2], r[3])
            end
            G.stats.sets = G.stats.sets + #bk
        else
            if b ~= curB then local bv, bp = toGpu(b, true) gpu.setBackground(bv, bp) curB = b G.stats.colors = G.stats.colors + 1 end
            if f ~= curF then local fv, fp = toGpu(f, false) gpu.setForeground(fv, fp) curF = f G.stats.colors = G.stats.colors + 1 end
            local bk = buckets[v]
            for _, r in ipairs(bk) do gpu.set(r[1], r[2], r[3]) end
            G.stats.sets = G.stats.sets + #bk
        end
    end
    G.stats.flushes = G.stats.flushes + 1
    return runs
end
function G.resetColorCache() curF, curB = nil, nil end

return G
