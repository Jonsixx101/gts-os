-- ======================================================================
-- GTS OS fuer OpenComputers (MC 1.7.10)                     /gts/boot.lua
-- ======================================================================
-- Start aus /home/.shrc (macht der Installer). Laedt den Kern, richtet
-- den Bildschirm ein und laesst den Kern laufen. Faellt etwas um, kommt
-- der Absturz-Bildschirm; nach 3 Abstuerzen in 10 Minuten startet das OS
-- im sicheren Modus (ohne Zusatz-Apps).
local ROOT = "/gts"
local component = require("component")
local computer = require("computer")
local fs = require("filesystem")

-- Strg+Alt+C beendet das OS nicht (Shell nur ueber die App mit Admin-Code)
pcall(function() require("process").info().data.signal = function() end end)

local function lib(name, ...)
    local f, err = loadfile(ROOT .. "/lib/" .. name .. ".lua")
    if not f then error("Kern-Datei fehlt: " .. name .. " (" .. tostring(err) .. ")", 0) end
    return f(...)
end

local G = lib("gfx")
local UI = lib("ui")(G)
local S = lib("store")
local K = lib("kernel")(G, UI, S, ROOT)
K.G, K.UI, K.S = G, UI, S
K.lib = lib
K.Cr = lib("crypto")()

-- Absturz-Bildschirm --------------------------------------------------
local function crashScreen(err, trace)
    K.log("FEHLER", "Absturz: " .. tostring(err))
    local now = K.realMs()
    local list = {}
    for _, t in ipairs(K.set.crashes or {}) do if now - t < 600000 then list[#list + 1] = t end end
    list[#list + 1] = now
    K.set.crashes = list
    if #list >= 3 then K.set.safeMode = true end
    K.save()
    local gpu = component.isAvailable("gpu") and component.gpu
    if not gpu then return end
    local C = G.C
    pcall(function()
        G.clear(C.bg)
        local W, H = G.size()
        G.fill(1, 1, W, 3, C.bad)
        G.text(3, 2, "GTS OS ist abgestürzt", C.white, C.bad)
        local UIw = UI.wrap("Fehler: " .. tostring(err), W - 6)
        local y = 5
        for i, l in ipairs(UIw) do if i <= 6 then G.text(4, y, l, C.text) y = y + 1 end end
        y = y + 1
        for line in tostring(trace or ""):gmatch("[^\n]+") do
            if y >= H - 4 then break end
            G.text(4, y, G.fit(line, W - 8), C.muted)
            y = y + 1
        end
        G.text(4, H - 2, K.set.safeMode and "Nächster Start: SICHERER MODUS (3 Abstürze in 10 min)" or "Neustart in 10 Sekunden ...", C.warn)
        G.flush()
    end)
    local dl = computer.uptime() + 10
    while computer.uptime() < dl do
        local ok = pcall(computer.pullSignal, dl - computer.uptime())
    end
end

-- Apps -------------------------------------------------------------------
local function app(id, title, order, extra)
    local def = { id = id, title = title, file = ROOT .. "/apps/" .. id .. ".lua", order = order }
    for k, v in pairs(extra or {}) do def[k] = v end
    if K.set.safeMode and def.optional then return end
    if fs.exists(def.file) then K.register(def) end
end
local function has(cat)
    return function()
        if not K.dev then return false end
        for _, e in ipairs(K.dev.list) do if e.cat == cat and not e.infra then return true end end
        return false
    end
end
app("home", "HOME", 1, { keep = true })
app("drones", "DROHNEN", 2)
app("security", "SICHERHEIT", 3, { optional = true })
app("plant", "ANLAGEN", 4, { visible = has("anlagen"), optional = true })
app("storage", "LAGER", 5, { visible = has("lager"), optional = true })
app("devices", "GERÄTE", 6)
app("info", "SYSTEM", 7)
app("notes", "NOTIZEN", 10, { optional = true })
app("calc", "RECHNER", 11, { optional = true })
app("files", "DATEIEN", 12, { optional = true })
app("ki", "KI", 13, { optional = true })
app("shell", "SHELL", 20)
app("setup", "EINRICHTEN", 90, { hidden = true })

-- Start ---------------------------------------------------------------
local function main()
    K.initScreen()
    K.net = lib("net")(K, S)
    K.net.start()
    K.units = lib("units")(K, S, K.net)
    K.spawn("einheiten", K.units.service)
    K.dev = lib("dev")(K, S, K.net, K.units)
    K.spawn("geraete", K.dev.service)
    local sys = lib("sys")(K, S)
    K.sys = sys
    K.spawn("system", sys.service)
    -- Sicherheit (Tueren, Leser, Melder) und Vorrat (AE2) laufen immer, auch ohne offene App
    if not K.set.safeMode then
        for _, l in ipairs({ { "secu", "sec", "sicherheit" }, { "stock", "stock", "vorrat" } }) do
            local ok, mod = pcall(function() return lib(l[1])(K, S, K.dev) end)
            if ok then K[l[2]] = mod K.spawn(l[3], mod.service) else K.log("FEHLER", l[1] .. ": " .. tostring(mod)) end
        end
    end
    -- KI-Ereignis-Modus (nur wenn in KI > EINSTELLUNGEN eingeschaltet)
    local function kiEvent(text)
        if not K.set.kiEvents then return end
        local ok, ki = pcall(K.module, "ki")
        if ok and ki and ki.event then pcall(ki.event, text) end
    end
    K.onIntruder = function(name, where) kiEvent("Fremder Spieler \"" .. tostring(name) .. "\" gesehen bei " .. tostring(where)) end
    K.onRule = function(r, v, why) kiEvent("Wächter \"" .. tostring(r and r.name or "?") .. "\" hat ausgelöst" .. (why and (": " .. why) or "")) end
    -- Schwarm-Autopilot (KI > EINSTELLUNGEN > AUTOPILOT)
    K.onUnit = function(u, what, text)
        if not K.set.kiAuto then return end
        local ok, ki = pcall(K.module, "ki")
        if ok and ki and ki.unitEvent then pcall(ki.unitEvent, what, text) end
    end
    K.locked = K.set.setupDone
    if not K.set.setupDone then K.open("setup") else K.open("home") end
    K.log("INFO", "GTS OS " .. K.VERSION .. " gestartet" .. (K.set.safeMode and " (sicherer Modus)" or ""))
    K.run()
end

while true do
    local trace
    local ok, err = xpcall(main, function(e) trace = debug and debug.traceback and debug.traceback() or "" return e end)
    if ok or K.quit then break end
    crashScreen(err, trace)
    K.services = {}
    K.loaded = {}
    K.handlers = {}
    K.running = true
end
-- OS beendet (SHELL-App): Bildschirm aufraeumen, Farben zuruecksetzen
pcall(function()
    local gpu = component.gpu
    local w, h = gpu.maxResolution()
    pcall(gpu.setResolution, w, h)
    -- Standard-Palette wiederherstellen: setDepth setzt sie bei Server und
    -- Spieler zurueck (16x setPaletteColor kostete 1,6 s Pause)
    pcall(gpu.setDepth, gpu.getDepth())
    gpu.setBackground(0x000000)
    gpu.setForeground(0xFFFFFF)
    gpu.fill(1, 1, w, h, " ")
    pcall(function() require("term").clear() end)
end)
if K.afterExit then
    print("GTS OS: starte " .. K.afterExit .. "  (zurück mit: reboot)")
    local ok, err = pcall(function() require("shell").execute(K.afterExit) end)
    if not ok then print(err) end
else
    print("GTS OS beendet. Zurück mit: reboot  (oder /gts/boot.lua)")
end
