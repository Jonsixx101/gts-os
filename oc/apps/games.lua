-- GTS OS (OpenComputers) - SPIELE: Snake und Asteroiden (Halbblock-Pixel)
local K, G, UI, S = ...
local computer = require("computer")
local C = G.C
local A = { game = nil, st = nil, run = 0 }
local DB = K.ROOT .. "/data/spiele.db"
local best = S.load(DB, {})
local function saveBest(id, score)
    if score > (best[id] or 0) then best[id] = score S.save(DB, best) return true end
end
math.randomseed(math.floor(computer.uptime() * 1000) % 2147483647)

local GAMES = {
    { id = "snake", title = "SNAKE", sub = "Fressen, wachsen, nicht beißen", icon = "∿" },
    { id = "dodge", title = "ASTEROIDEN", sub = "Ausweichen im Asteroidenfeld", icon = "✦" },
}

-- Pixel: jede Zelle = 2 Pixel uebereinander (▀ mit Vorder-/Hintergrund)
local function drawPixels(x, y, pw, ph, pix, base)
    for cy = 0, math.floor(ph / 2) - 1 do
        for cx = 0, pw - 1 do
            local t = pix[(cy * 2) * pw + cx] or base
            local b = pix[(cy * 2 + 1) * pw + cx] or base
            if t == b then G.put(x + cx, y + cy, " ", t, t) else G.put(x + cx, y + cy, "▀", t, b) end
        end
    end
end

-- ---------------------------------------------------------------------
-- Snake
-- ---------------------------------------------------------------------
local Snake = {}
function Snake.new(pw, ph)
    local s = { pw = pw, ph = ph, body = {}, dir = { 1, 0 }, next = { 1, 0 }, score = 0, alive = true, step = 0.14 }
    local mx, my = math.floor(pw / 2), math.floor(ph / 2)
    for i = 0, 3 do s.body[#s.body + 1] = { mx - i, my } end
    Snake.food(s)
    return s
end
function Snake.food(s)
    local free = {}
    local used = {}
    for _, b in ipairs(s.body) do used[b[2] * s.pw + b[1]] = true end
    for i = 0, s.pw * s.ph - 1 do if not used[i] then free[#free + 1] = i end end
    if #free == 0 then s.alive = false return end
    local k = free[math.random(1, #free)]
    s.fx, s.fy = k % s.pw, math.floor(k / s.pw)
end
function Snake.turn(s, dx, dy)
    if dx == -s.dir[1] and dy == -s.dir[2] then return end
    s.next = { dx, dy }
end
function Snake.update(s)
    if not s.alive then return end
    s.dir = s.next
    local h = s.body[1]
    local nx, ny = h[1] + s.dir[1], h[2] + s.dir[2]
    if nx < 0 or ny < 0 or nx >= s.pw or ny >= s.ph then s.alive = false return end
    for i = 1, #s.body - 1 do if s.body[i][1] == nx and s.body[i][2] == ny then s.alive = false return end end
    table.insert(s.body, 1, { nx, ny })
    if nx == s.fx and ny == s.fy then
        s.score = s.score + 10
        s.step = math.max(0.06, s.step - 0.004)
        Snake.food(s)
    else
        table.remove(s.body)
    end
end
function Snake.pixels(s)
    local pix = {}
    for i, b in ipairs(s.body) do pix[b[2] * s.pw + b[1]] = (i == 1) and C.white or (i % 2 == 0 and C.accent or C.accentDim) end
    pix[s.fy * s.pw + s.fx] = C.bad
    return pix
end

-- ---------------------------------------------------------------------
-- Asteroiden: Schiff unten, Brocken fallen
-- ---------------------------------------------------------------------
local Dodge = {}
function Dodge.new(pw, ph)
    return { pw = pw, ph = ph, x = math.floor(pw / 2), rocks = {}, score = 0, alive = true, step = 0.08, t = 0, rate = 0.25 }
end
function Dodge.turn(s, dx) if dx ~= 0 then s.move = dx end end
function Dodge.update(s)
    if not s.alive then return end
    s.t = s.t + 1
    if s.move then s.x = math.max(1, math.min(s.pw - 2, s.x + s.move * 2)) s.move = nil end
    for _, r in ipairs(s.rocks) do r.y = r.y + r.v end
    local keep = {}
    for _, r in ipairs(s.rocks) do if r.y < s.ph then keep[#keep + 1] = r else s.score = s.score + 1 end end
    s.rocks = keep
    if math.random() < s.rate then s.rocks[#s.rocks + 1] = { x = math.random(0, s.pw - 2), y = 0, v = math.random() < 0.3 and 2 or 1, big = math.random() < 0.3 } end
    if s.t % 100 == 0 then s.rate = math.min(0.9, s.rate + 0.05) end
    -- Treffer: Schiff belegt (x-1..x+1, ph-2) und (x, ph-3)
    local sy = s.ph - 2
    for _, r in ipairs(s.rocks) do
        local rw = r.big and 2 or 1
        for dx = 0, rw - 1 do
            for dy = (r.v > 1) and -1 or 0, rw - 1 do
                local px, py = r.x + dx, math.floor(r.y) + dy
                if (py == sy and px >= s.x - 1 and px <= s.x + 1) or (py == sy - 1 and px == s.x) then s.alive = false end
            end
        end
    end
end
function Dodge.pixels(s)
    local pix = {}
    -- Sterne (fest)
    for i = 0, s.pw * s.ph - 1, 37 do pix[(i * 7919) % (s.pw * s.ph)] = C.line end
    for _, r in ipairs(s.rocks) do
        local rw = r.big and 2 or 1
        for dx = 0, rw - 1 do for dy = 0, rw - 1 do
            local px, py = r.x + dx, math.floor(r.y) + dy
            if px >= 0 and px < s.pw and py >= 0 and py < s.ph then pix[py * s.pw + px] = r.big and C.dim or C.warn end
        end end
    end
    local sy = s.ph - 2
    for dx = -1, 1 do pix[sy * s.pw + s.x + dx] = s.alive and C.accent or C.bad end
    pix[(sy - 1) * s.pw + s.x] = s.alive and C.white or C.bad
    return pix
end

local IMPL = { snake = Snake, dodge = Dodge }

-- ---------------------------------------------------------------------
-- Ablauf
-- ---------------------------------------------------------------------
local function start(id)
    A.game = id
    A.pending = true          -- Feldgroesse kommt beim naechsten Zeichnen
    A.paused = false
end
local function loop(runId)
    while A.run == runId and A.st do
        local st = A.st
        if not A.paused and st.alive then
            IMPL[A.game].update(st)
            if not st.alive then
                A.newBest = saveBest(A.game, st.score)
                if K.set.sound then pcall(computer.beep, 220, 0.2) end
            end
            K.dirty = true
        end
        K.sleep(st.step)
    end
end
local function begin(pw, ph)
    A.st = IMPL[A.game].new(pw, ph)
    A.newBest = false
    A.run = A.run + 1
    local id = A.run
    K.spawn("spiel", function() loop(id) end)
end
local function control(dx, dy)
    if not A.st then return end
    if A.game == "snake" then Snake.turn(A.st, dx, dy) else Dodge.turn(A.st, dx) end
end

function A.leave() A.paused = true end
function A.unload() A.run = A.run + 1 A.st = nil end

local function drawMenu(x, y, w, h)
    local cw = math.min(w, 80)
    local cx = x + math.floor((w - cw) / 2)
    local yy = y + 1
    for _, g in ipairs(GAMES) do
        local ix, iy, iw = UI.card(cx, yy, cw, 7, nil)
        G.big(ix + 1, iy, g.icon == "∿" and "S" or "A", C.accent, C.card)
        G.text(ix + 7, iy, g.title, C.text, C.card)
        G.text(ix + 7, iy + 1, g.sub, C.muted, C.card)
        G.text(ix + 7, iy + 3, "Bestwert: " .. (best[g.id] or 0), C.dim, C.card)
        UI.button({ x = ix + iw - 14, y = iy + 1, w = 14, h = 3, text = "SPIELEN", style = "primary", onClick = function() start(g.id) end })
        yy = yy + 8
    end
    if yy + 2 < y + h then
        G.center(x, yy + 1, w, "Steuerung: Pfeiltasten / WASD oder die Knöpfe am Rand · P = Pause · Esc = Menü", C.muted)
    end
end

local function drawGame(x, y, w, h)
    local wide = w >= 100
    local padW = wide and 22 or 0
    local bw = math.min(w - padW - 2, wide and 90 or w)
    local bh = h - (wide and 2 or 6)
    if A.pending or not A.st then
        A.pending = false
        begin(bw, bh * 2)
    end
    local st = A.st
    local bx = x
    local _, iy = UI.card(bx - 1, y - 1, st.pw + 2, math.floor(st.ph / 2) + 2, nil)
    drawPixels(bx, y, st.pw, st.ph, IMPL[A.game].pixels(st), C.bg2)
    if A.game == "dodge" then
        UI.region(bx, y, math.floor(st.pw / 2), st.ph / 2, function() control(-1, 0) end)
        UI.region(bx + math.floor(st.pw / 2), y, st.pw - math.floor(st.pw / 2), st.ph / 2, function() control(1, 0) end)
    end
    -- Seitenleiste / Fusszeile
    local sx, sy = wide and (bx + st.pw + 3) or x, wide and y or (y + math.floor(st.ph / 2) + 2)
    G.text(sx, sy, (A.game == "snake" and "SNAKE" or "ASTEROIDEN"), C.text)
    G.text(sx, sy + 1, "Punkte " .. st.score, C.accent)
    G.text(sx, sy + 2, "Bestwert " .. (best[A.game] or 0), C.muted)
    local px = wide and sx or (x + w - 24)
    local py = wide and (sy + 5) or sy
    if A.game == "snake" then
        UI.button({ x = px + 7, y = py, w = 6, text = "▲", style = "subtle", onClick = function() control(0, -1) end })
        UI.button({ x = px, y = py + 1, w = 6, text = "◀", style = "subtle", onClick = function() control(-1, 0) end })
        UI.button({ x = px + 14, y = py + 1, w = 6, text = "▶", style = "subtle", onClick = function() control(1, 0) end })
        UI.button({ x = px + 7, y = py + 2, w = 6, text = "▼", style = "subtle", onClick = function() control(0, 1) end })
    else
        UI.button({ x = px, y = py + 1, w = 9, text = "◀", style = "subtle", onClick = function() control(-1, 0) end })
        UI.button({ x = px + 11, y = py + 1, w = 9, text = "▶", style = "subtle", onClick = function() control(1, 0) end })
    end
    local by = wide and (py + 5) or (sy + 4)
    local bxx = wide and sx or x
    bxx = UI.button({ x = bxx, y = by, w = wide and 20 or nil, text = A.paused and "WEITER" or "PAUSE", style = "secondary",
                      onClick = function() A.paused = not A.paused end }) + 1
    if wide then by = by + 2 bxx = sx end
    UI.button({ x = bxx, y = by, w = wide and 20 or nil, text = "MENÜ", style = "subtle", onClick = function() A.run = A.run + 1 A.st, A.game = nil, nil end })
    -- Ende
    if not st.alive or A.paused then
        local mw, mh = 30, 7
        local mx, my = bx + math.floor((st.pw - mw) / 2), y + math.floor((st.ph / 2 - mh) / 2)
        G.softBox(mx, my, mw, mh, C.raised, G.getBg(mx, my))
        if not st.alive then
            G.center(mx, my + 1, mw, A.newBest and "NEUER BESTWERT!" or "VORBEI", A.newBest and C.accent or C.text, C.raised)
            G.center(mx, my + 2, mw, st.score .. " Punkte", C.dim, C.raised)
            UI.button({ x = mx + 3, y = my + 4, w = mw - 6, text = "NOCHMAL", style = "primary", onClick = function() A.pending = true A.run = A.run + 1 end })
        else
            G.center(mx, my + 2, mw, "PAUSE", C.text, C.raised)
            UI.button({ x = mx + 3, y = my + 4, w = mw - 6, text = "WEITER", style = "primary", onClick = function() A.paused = false end })
        end
    end
end

function A.draw(x, y, w, h)
    local pad = (w < 100) and 1 or 2
    x, w = x + pad, w - pad * 2
    if A.game then drawGame(x + 1, y + 2, w - 2, h - 3) return end
    G.text(x, y + 1, "SPIELE", C.text)
    G.text(x + 8, y + 1, "  für die Pause zwischendurch", C.muted)
    drawMenu(x, y + 3, w, h - 4)
end
function A.key(char, code)
    if not A.game then return end
    local c = (char and char >= 32 and char < 128) and string.char(char):lower() or ""
    if code == 200 or c == "w" then control(0, -1)
    elseif code == 208 or c == "s" then control(0, 1)
    elseif code == 203 or c == "a" then control(-1, 0)
    elseif code == 205 or c == "d" then control(1, 0)
    elseif c == "p" or code == 57 then A.paused = not A.paused
    elseif code == 28 and A.st and not A.st.alive then A.pending = true A.run = A.run + 1
    elseif code == 1 then A.run = A.run + 1 A.st, A.game = nil, nil end
end
function A.tick() return A.game == nil end
return A
