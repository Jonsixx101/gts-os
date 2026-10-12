-- GTS OS (OpenComputers) - SHELL: OpenOS-Kommandozeile, Lua-Konsole, Programme (nur mit Admin-Code)
local K, G, UI, S = ...
local computer = require("computer")
local fs = require("filesystem")
local C = G.C
local A = { out = {}, line = "", hist = {}, hi = 0, page = { page = 1 }, progPage = { page = 1 } }

local function push(text, color)
    for l in (tostring(text) .. "\n"):gmatch("(.-)\n") do A.out[#A.out + 1] = { l, color or C.text } end
    while #A.out > 200 do table.remove(A.out, 1) end
end

-- Lua-Konsole: erst als Ausdruck, sonst als Anweisung
local env = setmetatable({ K = K, G = G, UI = UI, S = S }, { __index = _G })
env.print = function(...)
    local t = {}
    for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
    push(table.concat(t, "  "), C.text)
end
local function run(code)
    if code == "" then return end
    push("› " .. code, C.dim)
    table.insert(A.hist, code)
    while #A.hist > 30 do table.remove(A.hist, 1) end
    A.hi = #A.hist + 1
    K.log("INFO", "Lua-Konsole: " .. code:sub(1, 60))
    local f, err = load("return " .. code, "=konsole", "t", env)
    if not f then f, err = load(code, "=konsole", "t", env) end
    if not f then push(err, C.bad) return end
    local r = table.pack(pcall(f))
    if not r[1] then push(tostring(r[2]), C.bad) return end
    if r.n > 1 then
        local t = {}
        for i = 2, r.n do
            local v = r[i]
            if type(v) == "table" then
                local ok, s = pcall(require("serialization").serialize, v, true)
                t[#t + 1] = ok and s or tostring(v)
            else t[#t + 1] = tostring(v) end
        end
        push(table.concat(t, "  "), C.accent)
    end
end

-- OS verlassen; nach X Minuten ohne Eingabe startet der Rechner neu
local function leave(program)
    local mins = K.set.shellTimeout or 15
    local event = require("event")
    local last = computer.uptime()
    local function seen() last = computer.uptime() end
    pcall(event.listen, "key_down", seen)
    pcall(event.listen, "touch", seen)
    pcall(event.timer, 20, function()
        if computer.uptime() - last > mins * 60 then computer.shutdown(true) end
    end, math.huge)
    K.log("WARN", "Shell geöffnet" .. (program and (" (" .. program .. ")") or ""))
    K.afterExit = program
    K.quit = true
    K.running = false
end

local function programs()
    local out = {}
    for _, dir in ipairs({ "/home", "/usr/bin" }) do
        if fs.exists(dir) then
            for name in fs.list(dir) do
                if name:match("%.lua$") then out[#out + 1] = { name = name, path = dir .. "/" .. name } end
            end
        end
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

local function drawLocked(x, y, w, h)
    local cw = math.min(w, 64)
    local cx = x + math.floor((w - cw) / 2)
    local ix, iy, iw = UI.card(cx, y + 2, cw, 12, nil)
    G.center(ix, iy + 1, iw, "⚿  NUR FÜR ADMINS", C.warn, C.card)
    UI.para(ix + 2, iy + 3, iw - 4, "Shell und Lua-Konsole haben vollen Zugriff auf den Rechner. Darum fragt GTS OS hier nach dem Admin-Code (gilt dann 2 Minuten).", C.dim)
    UI.button({ x = ix + math.floor((iw - 26) / 2), y = iy + 7, w = 26, h = 3, text = "ADMIN-CODE EINGEBEN", style = "primary",
                onClick = function() K.askAdmin("Admin-Code", function() K.dirty = true end) end })
end

function A.draw(x, y, w, h)
    local pad = (w < 100) and 1 or 2
    x, w = x + pad, w - pad * 2
    G.text(x, y + 1, "SHELL", C.text)
    G.text(x + 7, y + 1, "  OpenOS · Lua · Programme", C.muted)
    local admin = K.isAdmin()
    if admin then G.right(x + w - 1, y + 1, "Admin noch " .. math.ceil(K.adminUntil - computer.uptime()) .. " s", C.warn) end
    local top = y + 3
    local hh = y + h - top
    if not admin then drawLocked(x, top, w, hh) return end
    local wide = w >= 110
    local lw = wide and math.floor(w * 0.4) or w
    -- links: Shell + Programme
    local sh = wide and 13 or 8
    local ix, iy, iw, ih = UI.card(x, top, lw, sh, "OPENOS-SHELL")
    if wide then
        iy = UI.para(ix, iy, iw, "Beendet GTS OS und öffnet die Kommandozeile. Ohne Eingabe startet der Rechner nach der eingestellten Zeit neu - zurück ins gesperrte GTS OS.", C.dim) + 1
    end
    G.text(ix, iy, "Neustart nach", C.muted, C.card)
    local cx = ix + 15
    for _, m in ipairs({ 5, 15, 30, 60 }) do
        cx = UI.chip(cx, iy, m .. " min", (K.set.shellTimeout or 15) == m, function() K.setting("shellTimeout", m) end) + 1
    end
    UI.button({ x = ix, y = top + sh - 2, text = "SHELL ÖFFNEN", style = "warn", confirm = "shell", confirmText = "GTS OS BEENDEN?",
                onClick = function() leave(nil) end })
    UI.button({ x = ix + 18, y = top + sh - 2, text = "NEU STARTEN", style = "subtle", confirm = "rb", onClick = function() computer.shutdown(true) end })
    if wide then
        local px, py, pw, ph = UI.card(x, top + sh + 1, lw, hh - sh - 1, "PROGRAMME (/home, /usr/bin)")
        local list = programs()
        if #list == 0 then UI.para(px, py, pw, "Keine .lua-Programme gefunden. Mit DATEIEN anlegen oder per wget/pastebin holen.", C.muted) end
        UI.list(A.progPage, list, px, py, pw, ph, 1, function(p, rx, ry, rw)
            G.text(rx, ry, G.fit(p.name, rw - 10), C.text, C.card)
            UI.button({ x = rx + rw - 8, y = ry, w = 8, text = "START", style = "subtle", confirm = "run" .. p.path, confirmText = "OS BEENDEN?",
                        onClick = function() leave(p.path) end })
        end)
    end
    -- rechts: Lua-Konsole
    local kx, ky, kw2, kh
    if wide then kx, ky, kw2, kh = UI.card(x + lw + 2, top, w - lw - 2, hh, "LUA-KONSOLE")
    else kx, ky, kw2, kh = UI.card(x, top + sh + 1, w, hh - sh - 1, "LUA-KONSOLE") end
    G.right(kx + kw2 - 1, ky - 1, "K, G, UI, S verfügbar", C.muted, C.card)
    local outH = kh - 2
    local first = math.max(1, #A.out - outH + 1)
    for i = first, #A.out do
        local o = A.out[i]
        G.text(kx, ky + i - first, G.fit(o[1], kw2), o[2], C.card)
    end
    if #A.out == 0 then G.text(kx, ky, "Beispiel: computer.freeMemory()  oder  K.units.list[1]", C.muted, C.card) end
    local ly = ky + kh - 1
    G.fill(kx, ly, kw2, 1, C.bg2)
    G.text(kx + 1, ly, "›", C.accent, C.bg2)
    local shown = A.line
    if G.len(shown) > kw2 - 14 then shown = G.sub(shown, G.len(shown) - kw2 + 15) end
    G.text(kx + 3, ly, shown, C.text, C.bg2)
    if K.hasKeyboard then G.put(kx + 3 + G.len(shown), ly, " ", C.onAccent, C.accent) end
    UI.button({ x = kx + kw2 - 10, y = ly, w = 10, text = K.hasKeyboard and "AUSFÜHREN" or "EINGEBEN", style = "primary", onClick = function()
        if K.hasKeyboard and A.line ~= "" then local l = A.line A.line = "" run(l)
        else UI.prompt({ title = "Lua", text = A.line, select = false, maxLen = 200, onOk = function(t) A.line = "" run(t) end }) end
    end })
    UI.region(kx, ky, kw2, kh - 1, function() end)
end
function A.key(char, code)
    if not K.isAdmin() then return end
    K.adminUntil = computer.uptime() + 120
    if code == 28 then local l = A.line A.line = "" run(l)
    elseif code == 14 then A.line = G.sub(A.line, 1, G.len(A.line) - 1)
    elseif code == 200 then A.hi = math.max(1, A.hi - 1) A.line = A.hist[A.hi] or A.line
    elseif code == 208 then A.hi = math.min(#A.hist + 1, A.hi + 1) A.line = A.hist[A.hi] or ""
    elseif char and char >= 32 then A.line = A.line .. (unicode and unicode.char(char) or string.char(char)) end
end
function A.paste(t) if K.isAdmin() then A.line = A.line .. tostring(t):gsub("[\r\n]", " ") end end
function A.tick() return true end
return A
