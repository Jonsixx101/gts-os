-- ======================================================================
-- GTS OS (OpenComputers) - kernel: Apps, Dienste, Sperre, Zeit, Meldungen
-- ======================================================================
return function(G, UI, S, ROOT)
local component = require("component")
local computer = require("computer")
local fs = require("filesystem")
local K = { apps = {}, byId = {}, app = nil, appId = nil, notes = {}, toast = nil, locked = true,
            services = {}, dirty = true, running = true, lastInput = 0, ROOT = ROOT, loaded = {} }
local C = G.C
K.VERSION = "1.1.0"
K.EDITION = "oc"

-- ---------------------------------------------------------------------
-- Einstellungen
-- ---------------------------------------------------------------------
local SETFILE = ROOT .. "/data/einstellungen.db"
local DEFAULTS = {
    owner = "", theme = "graphit", accent = "gruen", autoLock = 10, res = "auto", scale = "normal", tz = "berlin",
    codeHash = nil, adminHash = nil, setupDone = false, port = 4711, heartbeat = 5, homeAt = 25,
    autoAccept = true, sound = true, pinned = { "home", "drones", "security", "plant", "storage", "info" }, trusted = {},
    kiModel = "claude-haiku-5-5", kiDaily = 100, crashes = {},
}
K.set = S.load(SETFILE, {})
for k, v in pairs(DEFAULTS) do if K.set[k] == nil then K.set[k] = v end end
-- aus 1.0: SCHIFF und SPIELE gibt es nicht mehr, neue Apps anheften
for _, id in ipairs(K.set.pinned or {}) do if id == "ship" or id == "games" then K.set.pinned = DEFAULTS.pinned break end end
function K.save() S.save(SETFILE, K.set) end
function K.setting(k, v) K.set[k] = v K.save() K.dirty = true end

-- ---------------------------------------------------------------------
-- Zeit: Echtzeit ueber das Aenderungsdatum einer tmpfs-Datei (Serveruhr,
-- auf allen Rechnern des Servers gleich), Spielzeit ueber os.time()
-- ---------------------------------------------------------------------
local tmpfs = component.proxy(computer.tmpAddress())
-- Die Datei wird nur alle 30 s neu gestempelt (tmpfs.open: hoechstens 4 je Tick);
-- dazwischen zaehlt die Laufzeit weiter.
local realBase, realAt = nil, -1e9
function K.realMs()
    local up = computer.uptime()
    if not realBase or up - realAt > 30 then
        local ok, t = pcall(function()
            local h = tmpfs.open("/.gts_uhr", "w")
            tmpfs.write(h, "t")
            tmpfs.close(h)
            return tmpfs.lastModified("/.gts_uhr")
        end)
        if ok and type(t) == "number" and t > 1e12 then realBase, realAt = t - math.floor(up * 1000), up
        elseif not realBase then realBase, realAt = 0, up end
    end
    return realBase + math.floor(up * 1000)
end
function K.uptime() return computer.uptime() end
-- Kalenderdatum aus Tagen seit 1970 (Howard Hinnant)
local function civil(days)
    days = days + 719468
    local era = math.floor(days / 146097)
    local doe = days - era * 146097
    local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
    local y = yoe + era * 400
    local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
    local mp = math.floor((5 * doy + 2) / 153)
    local d = doy - math.floor((153 * mp + 2) / 5) + 1
    local m = mp < 10 and mp + 3 or mp - 9
    if m <= 2 then y = y + 1 end
    return y, m, d
end
K.civil = civil
local function lastSunday(y, m)        -- Tag (1..31) des letzten Sonntags
    local dim = ({ 31, (y % 4 == 0 and (y % 100 ~= 0 or y % 400 == 0)) and 29 or 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 })[m]
    -- Wochentag des Monatsletzten: Tage seit 1970 bis dahin
    local function daysFrom(yy, mm, dd)
        yy = (mm <= 2) and yy - 1 or yy
        local era = math.floor(yy / 400)
        local yoe = yy - era * 400
        local mp = (mm > 2) and mm - 3 or mm + 9
        local doy = math.floor((153 * mp + 2) / 5) + dd - 1
        local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
        return era * 146097 + doe - 719468
    end
    local wd = (daysFrom(y, m, dim) + 4) % 7          -- 0 = Sonntag
    return dim - wd, daysFrom
end
-- Versatz zur UTC in Stunden (Berlin mit Sommerzeit, sonst fest)
function K.tzOffset(ms)
    local tz = K.set.tz
    if type(tz) == "number" then return tz end
    local sec = math.floor(ms / 1000)
    local y = civil(math.floor(sec / 86400))
    local sMar, daysFrom = lastSunday(y, 3)
    local sOct = lastSunday(y, 10)
    local startS = daysFrom(y, 3, sMar) * 86400 + 3600
    local endS = daysFrom(y, 10, sOct) * 86400 + 3600
    return (sec >= startS and sec < endS) and 2 or 1
end
-- Ortszeit: Jahr, Monat, Tag, Stunde, Minute, Sekunde, Wochentag (1=Mo)
function K.localTime(ms)
    ms = ms or K.realMs()
    local sec = math.floor(ms / 1000) + K.tzOffset(ms) * 3600
    local days = math.floor(sec / 86400)
    local y, mo, d = civil(days)
    local rest = sec - days * 86400
    return y, mo, d, math.floor(rest / 3600), math.floor(rest / 60) % 60, rest % 60, (days + 3) % 7 + 1
end
function K.clock()
    local _, _, _, h, mi = K.localTime()
    return string.format("%02d:%02d", h, mi)
end
K.WEEKDAYS = { "Montag", "Dienstag", "Mittwoch", "Donnerstag", "Freitag", "Samstag", "Sonntag" }
K.MONTHS = { "Januar", "Februar", "März", "April", "Mai", "Juni", "Juli", "August", "September", "Oktober", "November", "Dezember" }
function K.dateText()
    local y, mo, d, _, _, _, wd = K.localTime()
    return string.format("%s, %d. %s %d", K.WEEKDAYS[wd], d, K.MONTHS[mo], y)
end
-- Spielzeit (0-24) und Tag
function K.mcTime()
    local t = os.time() / 3.6 % 24000 / 1000      -- 0 = 6 Uhr morgens im Spiel
    return (t + 6) % 24
end
function K.ago(sec)
    sec = math.max(0, math.floor(sec))
    if sec < 60 then return sec .. " s" end
    if sec < 3600 then return math.floor(sec / 60) .. " min" end
    if sec < 86400 then return math.floor(sec / 3600) .. " h" end
    return math.floor(sec / 86400) .. " d"
end
-- Zahlen deutsch: 1.234.567 bzw. 12,5; gross: 3,4 Mio / 1,2 Mrd
function K.num(n, dec)
    n = tonumber(n)
    if not n then return "-" end
    if n ~= n then return "-" end
    local neg = n < 0
    n = math.abs(n)
    local int = math.floor(n)
    local s = string.format("%.0f", int):reverse():gsub("(%d%d%d)", "%1."):reverse():gsub("^%.", "")
    if dec and dec > 0 then
        local f = math.floor((n - int) * 10 ^ dec + 0.5)
        if f >= 10 ^ dec then return K.num((neg and -1 or 1) * (int + 1), dec) end
        s = s .. "," .. string.format("%0" .. dec .. "d", f)
    end
    return (neg and "-" or "") .. s
end
function K.si(n)
    n = tonumber(n) or 0
    local a = math.abs(n)
    if a >= 1e12 then return K.num(n / 1e12, 1) .. " Bio" end
    if a >= 1e9 then return K.num(n / 1e9, 1) .. " Mrd" end
    if a >= 1e6 then return K.num(n / 1e6, 1) .. " Mio" end
    if a >= 1e4 then return K.num(n / 1e3, 1) .. " Tsd" end
    return K.num(n, a < 10 and a ~= math.floor(a) and 1 or 0)
end
function K.bytes(n)
    if n >= 1048576 then return (string.format("%.1f MB", n / 1048576):gsub("%.", ",", 1)) end
    if n >= 1024 then return string.format("%.0f KB", n / 1024) end
    return n .. " B"
end

-- ---------------------------------------------------------------------
-- Protokoll und Meldungen
-- ---------------------------------------------------------------------
local LOGFILE = ROOT .. "/data/gts.log"
function K.log(level, text)
    local line = string.format("%s %s %s\n", K.clock(), level, tostring(text))
    pcall(function()
        if fs.exists(LOGFILE) and fs.size(LOGFILE) > 24000 then
            if fs.exists(LOGFILE .. ".alt") then fs.remove(LOGFILE .. ".alt") end
            fs.rename(LOGFILE, LOGFILE .. ".alt")
        end
        local h = io.open(LOGFILE, "a")
        if h then h:write(line) h:close() end
    end)
end
-- level: "info" | "ok" | "warn" | "bad"; target: App-Id zum Oeffnen
function K.notify(text, level, target)
    level = level or "info"
    local n = { text = tostring(text), level = level, t = computer.uptime(), target = target, clock = K.clock() }
    table.insert(K.notes, 1, n)
    while #K.notes > 30 do table.remove(K.notes) end
    K.toast = { note = n, untilT = computer.uptime() + (level == "bad" and 6 or 4) }
    if level == "bad" or level == "warn" then K.unread = (K.unread or 0) + 1 end
    if level == "bad" and K.set.sound then pcall(computer.beep, 880, 0.15) end
    K.dirty = true
end
K.LEVEL = { info = C.info, ok = C.accent, warn = C.warn, bad = C.bad }

-- ---------------------------------------------------------------------
-- Code-Hash: SHA-256 (Data Card oder Lua - gleiches Ergebnis)
-- Aeltere Fassungen ohne Data Card speicherten "x..." (eigene Pruefsumme).
-- ---------------------------------------------------------------------
local function oldHash(s)
    local h1, h2 = 5381, 52711
    for i = 1, #s do
        local b = s:byte(i)
        h1 = (h1 * 33 + b) % 4294967296
        h2 = (h2 * 31 + b * 7 + i) % 4294967296
    end
    return string.format("x%08x%08x", h1, h2)
end
function K.hash(s) return K.Cr.sha256hex("GTS-OC|" .. s) end
function K.checkCode(code, which)
    local h = K.set[which or "codeHash"]
    if not h then return code == "3344" end
    if h:sub(1, 1) == "x" then return oldHash(code) == h end
    return K.hash(code) == h
end

-- ---------------------------------------------------------------------
-- Apps
-- ---------------------------------------------------------------------
-- def = { id, title, file, order, icon, visible = function() -> bool, keep }
function K.register(def)
    K.byId[def.id] = def
    K.apps[#K.apps + 1] = def
    table.sort(K.apps, function(a, b) return (a.order or 50) < (b.order or 50) end)
end
function K.visibleApps()
    local out = {}
    for _, a in ipairs(K.apps) do
        if not a.visible or a.visible() then out[#out + 1] = a end
    end
    return out
end
-- Modul einer App laden (bleiben hoechstens 2 im Speicher, dazu HOME)
local loadOrder = {}
function K.module(id)
    local def = K.byId[id]
    if not def then return nil end
    if K.loaded[id] then return K.loaded[id] end
    local f, err = loadfile(def.file)
    if not f then error("App " .. id .. ": " .. tostring(err), 0) end
    local mod = f(K, G, UI, S)
    K.loaded[id] = mod
    loadOrder[#loadOrder + 1] = id
    while #loadOrder > 2 do
        local old = table.remove(loadOrder, 1)
        if old ~= K.appId and not (K.byId[old] and K.byId[old].keep) then
            if K.loaded[old] and K.loaded[old].unload then pcall(K.loaded[old].unload) end
            K.loaded[old] = nil
        else
            loadOrder[#loadOrder + 1] = old
            break
        end
    end
    return mod
end
function K.open(id, arg)
    if not K.byId[id] then return false end
    local prev = K.app
    if prev and prev.leave then pcall(prev.leave) end
    local ok, mod = pcall(K.module, id)
    if not ok then
        K.notify("App " .. id .. " startet nicht: " .. tostring(mod), "bad")
        K.log("FEHLER", tostring(mod))
        return false
    end
    K.app, K.appId = mod, id
    UI.armed = nil
    if mod.enter then pcall(mod.enter, arg) end
    K.dirty = true

    return true
end
function K.call(name, ...)
    local a = K.app
    if a and a[name] then
        local ok, err = pcall(a[name], ...)
        if not ok then K.notify("Fehler: " .. tostring(err), "bad") K.log("FEHLER", tostring(err)) end
        return ok
    end
end

-- ---------------------------------------------------------------------
-- Dienste (Koroutinen): K.sleep, K.waitSignal
-- ---------------------------------------------------------------------
function K.spawn(name, fn)
    local s = { name = name, co = coroutine.create(fn), wake = 0 }
    K.services[#K.services + 1] = s
    return s
end
function K.sleep(sec) coroutine.yield({ sleep = sec or 0 }) end
function K.waitSignal(filter, timeout)
    local r = coroutine.yield({ signal = filter, sleep = timeout or math.huge })
    if r then return table.unpack(r, 1, r.n) end
end
local function resume(s, args)
    local ok, req = coroutine.resume(s.co, args)
    if not ok then
        K.log("FEHLER", "Dienst " .. s.name .. ": " .. tostring(req))
        s.dead = true
        s.err = req
        return
    end
    if coroutine.status(s.co) == "dead" then s.dead = true return end
    s.wake = computer.uptime() + ((req and req.sleep) or 0)
    s.filter = req and req.signal
end
local function runServices(ev)
    local now = computer.uptime()
    local i = 1
    while i <= #K.services do
        local s = K.services[i]
        if s.dead then
            table.remove(K.services, i)
        else
            if ev and s.filter and ev[1] == s.filter then
                s.filter = nil
                resume(s, ev)
            elseif now >= s.wake then
                s.filter = nil
                resume(s, nil)
            end
            i = i + 1
        end
    end
end
local function nextWake()
    local w = math.huge
    for _, s in ipairs(K.services) do if not s.dead and s.wake < w then w = s.wake end end
    return w
end

-- ---------------------------------------------------------------------
-- Bildschirm
-- ---------------------------------------------------------------------
-- Bildschirm: der gewaehlte, sonst der groesste (in Bloecken; mit Tastatur
-- bevorzugt). Grafikkarte: die staerkste. Skalierung: weniger Zeichen =
-- groessere Schrift (Gross 60 %, Mittel 80 %, Normal = alles).
K.SCALES = { { id = "gross", text = "GROSS", f = 0.6 }, { id = "mittel", text = "MITTEL", f = 0.8 }, { id = "normal", text = "NORMAL", f = 1 } }
local function pickScreen()
    local best, bestScore
    for addr in component.list("screen", true) do
        local p = component.proxy(addr)
        local aw, ah, kb = 1, 1, 0
        pcall(function() aw, ah = p.getAspectRatio() end)
        pcall(function() kb = #p.getKeyboards() end)
        local score = aw * ah * 10 + (kb > 0 and 5 or 0) + (addr == K.set.screen and 1e6 or 0)
        if not bestScore or score > bestScore then best, bestScore = p, score end
    end
    return best
end
local function pickGpu()
    local best, bestScore
    for addr in component.list("gpu", true) do
        local p = component.proxy(addr)
        local ok, w, h = pcall(p.maxResolution)
        local score = ok and (w * h) or 0
        if not bestScore or score > bestScore then best, bestScore = p, score end
    end
    return best
end
function K.screens()
    local out = {}
    for addr in component.list("screen", true) do
        local p = component.proxy(addr)
        local aw, ah, kb = 1, 1, 0
        pcall(function() aw, ah = p.getAspectRatio() end)
        pcall(function() kb = #p.getKeyboards() end)
        out[#out + 1] = { addr = addr, aw = aw, ah = ah, kb = kb > 0, on = addr == K.screen }
    end
    return out
end
function K.initScreen()
    local gpu, scr = pickGpu(), pickScreen()
    if not gpu or not scr then error("GTS OS braucht Grafikkarte und Bildschirm", 0) end
    K.screen = scr.address
    K.keyboards = scr.getKeyboards and scr.getKeyboards() or {}
    local aw, ah = 1, 1
    pcall(function() aw, ah = scr.getAspectRatio() end)
    K.aspect = aw .. "x" .. ah
    local want
    if type(K.set.res) == "table" then
        want = { w = K.set.res[1], h = K.set.res[2] }
    else
        local f = 1
        for _, sc in ipairs(K.SCALES) do if sc.id == K.set.scale then f = sc.f end end
        want = { aw = aw, ah = ah, f = f }
    end
    G.applyTheme(K.set.theme, K.set.accent)
    K.w, K.h = G.init(gpu, scr.address, want)
    K.hasKeyboard = #K.keyboards > 0
    K.dirty = true
end
-- regelmaessig: hat sich der Bildschirm veraendert (Bloecke dazu, andere Karte)?
function K.checkScreen()
    local scr = pickScreen()
    if not scr then return end
    local aw, ah = 1, 1
    pcall(function() aw, ah = scr.getAspectRatio() end)
    if scr.address ~= K.screen or (aw .. "x" .. ah) ~= K.aspect then K.initScreen() end
end
function K.narrow() return K.w < 100 end

-- Taskleiste unten
local function drawTaskbar()
    local W, H = K.w, K.h
    local y = H
    G.fill(1, y, W, 1, C.bg2)
    local x = 1
    local onHome = K.appId == "home"
    G.fill(x, y, 7, 1, onHome and C.accent or C.raised)
    G.text(x + 1, y, "◆ GTS", onHome and C.onAccent or C.accent)
    UI.region(x, y, 7, 1, function() K.open("home") end)
    x = x + 8
    -- Uhr, Meldungen, Sperre rechts
    local clock = K.clock()
    local xr = W
    xr = xr - 4
    G.text(xr, y, " ⏏ ", C.dim, C.raised)
    UI.region(xr, y, 3, 1, function() K.lock() end)
    xr = xr - #clock - 2
    G.text(xr, y, " " .. clock .. " ", C.text, C.bg2)
    UI.region(xr, y, #clock + 2, 1, function() K.open("info", "notes") end)
    if (K.unread or 0) > 0 then
        local label = " ● " .. K.unread .. " "
        xr = xr - G.len(label)
        G.text(xr, y, label, C.white, C.bad)
        UI.region(xr, y, G.len(label), 1, function() K.open("info", "notes") end)
    end
    -- Reiter zuerst (sie verschwinden nicht hinter einer Mitteilung)
    for _, id in ipairs(K.set.pinned or {}) do
        local a = K.byId[id]
        if a and id ~= "home" and (not a.visible or a.visible()) then
            local label = " " .. a.title .. " "
            local lw = G.len(label)
            if x + lw >= xr - 1 then break end
            local on = K.appId == id
            G.fill(x, y, lw, 1, on and C.raised or C.bg2)
            G.text(x, y, label, on and C.text or C.muted)
            if on then G.put(x, y, "▍", C.accent) end
            UI.region(x, y, lw, 1, function() K.open(id) end)
            x = x + lw
        end
    end
    -- Mitteilung (Toast) im freien Platz dazwischen - verdeckt nie den Inhalt
    local t = K.toast
    if t and computer.uptime() <= t.untilT then
        local n = t.note
        local room = xr - x - 2
        if room >= 8 then
            local text = G.fit(n.text, math.min(room, 60) - 4)
            local tw = G.len(text) + 4
            local tx = xr - tw - 1
            G.fill(tx, y, tw, 1, C.raised)
            G.put(tx + 1, y, "●", K.LEVEL[n.level] or C.info, C.raised)
            G.text(tx + 3, y, text, C.text, C.raised)
            UI.region(tx, y, tw, 1, function()
                K.toast = nil
                if n.target then K.open(n.target) end
            end)
        end
    end
end

local function drawToast()
    -- ohne Taskleiste (Einrichtung): Mitteilung unten rechts
    local t = K.toast
    if not t or K.appId ~= "setup" then return end
    if computer.uptime() > t.untilT then K.toast = nil return end
    local n = t.note
    local text = G.fit(n.text, K.w - 8)
    G.text(K.w - G.len(text) - 3, K.h, " ● " .. text .. " ", C.text, C.raised)
end

-- Sternenhimmel (fest, damit nichts flackert)
local function stars(seed)
    local s = seed or 7
    for i = 1, math.floor(K.w * K.h / 45) do
        s = (s * 1103515245 + 12345) % 2147483648
        local x = math.floor(s / 65536) % K.w + 1
        s = (s * 1103515245 + 12345) % 2147483648
        local y = math.floor(s / 65536) % (K.h - 1) + 1
        local b = math.floor(s / 4096) % 5
        G.put(x, y, b == 0 and "✦" or (b < 3 and "·" or "∙"), b == 0 and C.dim or C.muted)
    end
end
K.stars = stars

-- Sperrbildschirm
local function drawLock()
    G.clear(C.bg)
    stars(K.set.owner and #K.set.owner + 11 or 11)
    local _, _, _, h, mi = K.localTime()
    local clock = string.format("%02d:%02d", h, mi)
    local cw = G.bigWidth(clock)
    local cx = math.floor((K.w - cw) / 2) + 1
    local cy = math.max(2, math.floor(K.h / 2) - 5)
    G.big(cx, cy, clock, C.text, nil)
    G.center(1, cy + 4, K.w, K.dateText(), C.dim)
    local hello = (K.set.owner ~= "" and ("Hallo " .. K.set.owner)) or "GTS OS"
    G.center(1, cy + 6, K.w, hello, C.muted)
    local bw = 26
    UI.button({ x = math.floor((K.w - bw) / 2) + 1, y = cy + 8, w = bw, h = 3, text = "ENTSPERREN", style = "primary",
                onClick = function() K.askUnlock() end })
    if K.lockout and computer.uptime() < K.lockout then
        G.center(1, cy + 12, K.w, "Zu viele Fehlversuche - warten (" .. math.ceil(K.lockout - computer.uptime()) .. " s)", C.bad)
    end
    if (K.unread or 0) > 0 then G.center(1, K.h - 2, K.w, "● " .. K.unread .. " neue Meldung(en)", C.warn) end
    G.text(2, K.h, "GTS OS " .. K.VERSION .. " · OpenComputers", C.muted)
    UI.region(1, 1, K.w, K.h, function() K.askUnlock() end)
end

function K.lock()
    K.locked = true
    UI.modal = nil
    K.dirty = true
end
function K.askUnlock(after, err)
    if K.lockout and computer.uptime() < K.lockout then return end
    UI.keypad({ title = "Sperrcode", maxLen = 8, err = err, onOk = function(code)
        if K.checkCode(code) then
            K.locked = false
            K.fails = 0
            K.lastInput = computer.uptime()
            K.log("INFO", "entsperrt")
            if after then after() end
        else
            K.fails = (K.fails or 0) + 1
            K.log("WARN", "falscher Sperrcode")
            if K.fails >= 5 then
                K.lockout = computer.uptime() + 30
                K.fails = 0
                K.notify("5 Fehlversuche - 30 s gesperrt", "bad")
            else
                K.askUnlock(after, "Falsch (" .. K.fails .. "/5)")
            end
        end
    end })
end
-- Admin-Code fuer Shell, Lua und Sicherheits-Einstellungen
function K.askAdmin(title, after)
    -- innerhalb des Admin-Fensters (2 min) nicht nochmal fragen
    if K.isAdmin() then K.adminUntil = computer.uptime() + 120 after() return end
    UI.keypad({ title = title or "Admin-Code", maxLen = 8, onOk = function(code)
        if K.checkCode(code, "adminHash") or (not K.set.adminHash and K.checkCode(code)) then
            K.adminUntil = computer.uptime() + 120
            after()
        else
            K.log("WARN", "falscher Admin-Code")
            K.notify("Admin-Code falsch", "bad")
        end
    end })
end
function K.isAdmin() return K.adminUntil and computer.uptime() < K.adminUntil end

-- ---------------------------------------------------------------------
-- Zeichnen
-- ---------------------------------------------------------------------
function K.draw()
    UI.begin()
    UI.now = computer.uptime
    if K.locked then
        drawLock()
    else
        G.clear(C.bg)
        local a = K.app
        if a and a.draw then
            local ok, err = pcall(a.draw, 1, 1, K.w, K.h - 1)
            if not ok then
                G.clear(C.bg)
                G.text(2, 2, "Diese Ansicht hat einen Fehler:", C.bad)
                UI.para(2, 4, K.w - 4, tostring(err), C.dim)
                K.log("FEHLER", "draw " .. tostring(K.appId) .. ": " .. tostring(err))
            end
        end
        if K.appId ~= "setup" then drawTaskbar() end
        drawToast()
    end
    UI.drawModal(K.hasKeyboard)
    G.flush()
    K.dirty = false
end

-- ---------------------------------------------------------------------
-- Ereignisse
-- ---------------------------------------------------------------------
K.handlers = {}       -- name -> { fn, ... } (z.B. modem_message fuer das Netz)
function K.on(name, fn)
    K.handlers[name] = K.handlers[name] or {}
    table.insert(K.handlers[name], fn)
end
local function dispatch(ev)
    local name = ev[1]
    if not name then return end
    if name == "touch" or name == "drag" then
        if ev[2] ~= K.screen then return end
        K.lastInput = computer.uptime()
        if name == "touch" then
            if UI.armed and computer.uptime() - UI.armed.t > 4 then UI.armed = nil end
            UI.click(ev[3], ev[4], ev[5], ev[6])
            K.dirty = true
        end
    elseif name == "scroll" then
        if ev[2] ~= K.screen then return end
        K.lastInput = computer.uptime()
        if not UI.scroll(ev[3], ev[4], ev[5]) then K.call("scroll", ev[5]) end
        K.dirty = true
    elseif name == "key_down" then
        K.lastInput = computer.uptime()
        if not UI.key(ev[3], ev[4]) then
            if K.locked then
                if ev[4] == 28 or (ev[3] and ev[3] >= 48 and ev[3] <= 57) then
                    K.askUnlock()
                    if ev[3] >= 48 then UI.key(ev[3], ev[4]) end
                end
            else
                K.call("key", ev[3], ev[4])
            end
        end
        K.dirty = true
    elseif name == "clipboard" then
        if not UI.paste(ev[3]) and not K.locked then K.call("paste", ev[3]) end
        K.dirty = true
    elseif name == "screen_resized" then
        G.invalidate()
        K.dirty = true
    elseif name == "component_added" or name == "component_removed" then
        K.hwChanged = true
        if ev[3] == "screen" or ev[3] == "gpu" or ev[3] == "keyboard" then K.screenCheckAt = computer.uptime() + 0.5 end
        K.dirty = true
    end
    for _, fn in ipairs(K.handlers[name] or {}) do
        local ok, err = pcall(fn, table.unpack(ev, 2, ev.n))
        if not ok then K.log("FEHLER", name .. ": " .. tostring(err)) end
    end
    for _, fn in ipairs(K.handlers["*"] or {}) do
        local ok, err = pcall(fn, ev)
        if not ok then K.log("FEHLER", "*: " .. tostring(err)) end
    end
    if not K.locked and K.app and K.app.signal then pcall(K.app.signal, table.unpack(ev, 1, ev.n)) end
end

-- Hauptschleife
function K.run()
    local lastSecond = -1
    local lastMinute = ""
    while K.running do
        if K.dirty then K.draw() end
        local timeout = math.max(0.05, math.min(1, nextWake() - computer.uptime()))
        local ok, ev = pcall(function() return table.pack(computer.pullSignal(timeout)) end)
        if not ok then
            -- Strg+Alt+C ("interrupted") beendet das OS nicht
            K.log("WARN", "Unterbrechung abgefangen: " .. tostring(ev))
            ev = { n = 0 }
        end
        if ev[1] == "interrupted" then ev = { n = 0 } end
        dispatch(ev)
        runServices(ev)
        local now = computer.uptime()
        if math.floor(now) ~= lastSecond then
            lastSecond = math.floor(now)
            if K.app and K.app.tick and not K.locked then
                local ok2, changed = pcall(K.app.tick)
                if ok2 and changed then K.dirty = true end
            end
            if K.screenCheckAt and now >= K.screenCheckAt then
                K.screenCheckAt = nil
                pcall(K.checkScreen)
            end
            local mins = K.set.autoLock or 0
            if not K.locked and mins > 0 and now - K.lastInput > mins * 60 then K.lock() end
            if K.toast and now > K.toast.untilT then K.toast = nil K.dirty = true end
            local c = K.clock()
            if c ~= lastMinute then lastMinute = c K.dirty = true end
            if UI.armed and now - UI.armed.t > 4 then UI.armed = nil K.dirty = true end
        end
    end
end

return K
end
