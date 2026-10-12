-- ======================================================================
-- GTS OS (OpenComputers) - sys: Messwerte, Geraete, Update, Backup
-- ======================================================================
return function(K, S)
local component = require("component")
local computer = require("computer")
local fs = require("filesystem")
local Y = { hist = { ram = {}, energy = {} }, update = { state = "idle" } }
local REPO = "https://raw.githubusercontent.com/Jonsixx101/gts-os/main/oc/"
Y.REPO = REPO

-- Komponenten mit Namen ------------------------------------------------
Y.NAMES = {
    gpu = "Grafikkarte", screen = "Bildschirm", keyboard = "Tastatur", filesystem = "Speicher", modem = "Netzwerk/Funk",
    data = "Data Card", internet = "Internet Card", eeprom = "EEPROM", redstone = "Redstone", computer = "Computer",
    tunnel = "Linked Card", hologram = "Hologramm", geolyzer = "Geolyzer", motion_sensor = "Bewegungssensor",
    navigation = "Navigation", chunkloader = "Chunkloader", transposer = "Transposer", drone = "Drohne", robot = "Robot",
    warpdriveShipController = "Schiffssteuerung", warpdriveRadar = "Radar", warpdriveCloakingCore = "Tarnung",
    warpdriveLaserCamera = "Laser-Kamera", warpdriveLaser = "Laser", warpdriveTransporterCore = "Transporter",
    warpdriveMiningLaser = "Mining-Laser", warpdriveForceFieldProjector = "Kraftfeld", warpdriveEnanReactorCore = "Reaktor",
    sound = "Soundkarte", chat_box = "Chat Box", tape_drive = "Bandlaufwerk", printer3d = "3D-Drucker", disk_drive = "Laufwerk",
}
function Y.components()
    local out = {}
    for addr, t in pairs(component.list()) do out[#out + 1] = { addr = addr, type = t, name = Y.NAMES[t] or t } end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end
function Y.count(t) local n = 0 for _ in component.list(t, true) do n = n + 1 end return n end

-- Geraete-Infos (CPU-Stufe, Data-Card-Stufe ...)
function Y.device()
    local d = { cpu = "?", ram = computer.totalMemory(), gpuDepth = 0, gpuRes = "?" }
    local ok, info = pcall(computer.getDeviceInfo)
    if ok and type(info) == "table" then
        for _, i in pairs(info) do
            if i.class == "processor" and i.description == "CPU" then
                local comps = tonumber(i.capacity or "")
                d.cpu = comps and ({ [8] = "Tier 1", [12] = "Tier 2", [16] = "Tier 3", [1024] = "Kreativ" })[comps] or (i.product or "?")
                d.cpuClock = i.clock
            elseif i.class == "processor" and (i.description or ""):find("APU") then d.cpu = "APU " .. (i.product or "")
            end
        end
    end
    if component.isAvailable("gpu") then
        local g = component.gpu
        d.gpuDepth = g.maxDepth()
        local w, h = g.maxResolution()
        d.gpuRes = w .. "x" .. h
        d.gpuTier = ({ [1] = 1, [4] = 2, [8] = 3 })[d.gpuDepth] or 0
    end
    if component.isAvailable("data") then
        local dc = component.data
        d.dataTier = dc.ecdh and 3 or (dc.encrypt and 2 or 1)
    end
    if component.isAvailable("modem") then
        local m = component.modem
        d.wireless = m.isWireless()
        d.range = m.isWireless() and m.getStrength() or nil
    end
    d.internet = component.isAvailable("internet")
    return d
end

function Y.disks()
    local out = {}
    for addr in component.list("filesystem") do
        local p = component.proxy(addr)
        local ok, used, total = pcall(function() return p.spaceUsed(), p.spaceTotal() end)
        if ok then
            local label = p.getLabel() or addr:sub(1, 6)
            out[#out + 1] = { addr = addr, label = label, used = used, total = total, tmp = addr == computer.tmpAddress(),
                              boot = addr == computer.getBootAddress(), ro = p.isReadOnly() }
        end
    end
    table.sort(out, function(a, b) return (a.boot and 0 or 1) < (b.boot and 0 or 1) end)
    return out
end

-- System-Check: Ampel + Tipp
function Y.check()
    local d = Y.device()
    local list = {}
    local function add(level, title, tip) list[#list + 1] = { level = level, title = title, tip = tip } end
    if (d.gpuTier or 0) >= 3 then add("ok", "Grafik Tier 3", "160x50 Zeichen, 256 Farben")
    elseif (d.gpuTier or 0) == 2 then add("warn", "Grafik Tier 2", "Läuft (80x25). Tier 3 zeigt mehr auf einmal.")
    else add("bad", "Grafik Tier 1", "Zu klein für GTS OS: Grafikkarte und Bildschirm Tier 2 oder 3 einbauen.") end
    local free = computer.freeMemory()
    if free > 200 * 1024 then add("ok", "Arbeitsspeicher", K.bytes(free) .. " frei")
    elseif free > 80 * 1024 then add("warn", "Arbeitsspeicher knapp", K.bytes(free) .. " frei - mehr RAM einbauen (2x Tier 3).")
    else add("bad", "Arbeitsspeicher fast voll", "Mehr oder größeren RAM einbauen.") end
    if not K.net.ready then add("bad", "Funk aus", K.net.reason or "?")
    elseif K.net.isDefault then add("warn", "Schwarm-Passwort: Standard", "In SYSTEM > EINSTELLUNGEN ein eigenes setzen, dann EEPROMs neu schreiben.")
    else add("ok", "Funk verschlüsselt", K.net.aes and "AES (Data Card Tier 2+)" or "gesiegelt (Data Card Tier 1)") end
    if d.wireless == false then add("warn", "Nur Kabelnetz", "Für Drohnen eine Wireless-Karte (Tier 2: 400 Blöcke) einbauen.") end
    if not d.internet then add("warn", "Keine Internet Card", "Updates und KI brauchen eine Internet Card.") end
    if not K.set.adminHash then add("warn", "Kein Admin-Code", "Shell und Lua sind nur mit dem Sperrcode geschützt.") end
    if not K.set.codeHash then add("warn", "Sperrcode: Standard 3344", "In SYSTEM > EINSTELLUNGEN ändern.") end
    for _, dk in ipairs(Y.disks()) do
        if dk.boot and dk.total > 0 and dk.used / dk.total > 0.9 then add("warn", "Festplatte fast voll", K.bytes(dk.total - dk.used) .. " frei - AUFRÄUMEN.") end
    end
    local e = computer.energy() / math.max(1, computer.maxEnergy())
    if e < 0.2 then add("bad", "Strom knapp", math.floor(e * 100) .. " % im Puffer") end
    local off = 0
    for _, u in ipairs(K.units.list) do if not u.online and not u.waiting then off = off + 1 end end
    if off > 0 then add("warn", off .. " Einheit(en) offline", "In DROHNEN nachsehen (Akku leer, ausser Reichweite?).") end
    if K.set.safeMode then add("warn", "Sicherer Modus", "Zusatz-Apps aus. In SYSTEM beenden.") end
    return list
end

-- Backup: Einstellungen, Einheiten, Besucher, Notizen ------------------
local BACKUP = { "data/einstellungen.db", "data/einheiten.db", "data/besucher.db", "data/notizen.db", "data/schiff.db" }
function Y.backup()
    local _, _, _, _ = K.localTime()
    local y, mo, d = K.localTime()
    local name = string.format("%04d-%02d-%02d", y, mo, d)
    local all = {}
    for _, f in ipairs(BACKUP) do all[f] = S.read(K.ROOT .. "/" .. f) end
    S.save(K.ROOT .. "/backup/" .. name .. ".db", all)
    K.set.lastBackup = name
    K.save()
    -- nur die letzten 3 behalten
    local list = {}
    if fs.exists(K.ROOT .. "/backup") then
        for f in fs.list(K.ROOT .. "/backup") do if f:match("%.db$") then list[#list + 1] = f end end
    end
    table.sort(list)
    while #list > 3 do fs.remove(K.ROOT .. "/backup/" .. table.remove(list, 1)) end
    return name
end
function Y.backups()
    local list = {}
    if fs.exists(K.ROOT .. "/backup") then
        for f in fs.list(K.ROOT .. "/backup") do if f:match("^%d+%-%d+%-%d+%.db$") then list[#list + 1] = f:sub(1, -4) end end
    end
    table.sort(list, function(a, b) return a > b end)
    return list
end
function Y.restore(name)
    local all = S.load(K.ROOT .. "/backup/" .. name .. ".db")
    if type(all) ~= "table" then return false end
    local n = 0
    for _, f in ipairs(BACKUP) do                       -- nur bekannte Dateien
        if type(all[f]) == "string" then S.write(K.ROOT .. "/" .. f, all[f]) n = n + 1 end
    end
    return true, n
end

-- Aufraeumen: nur echter Muell
function Y.junk()
    local list = {}
    local function walk(dir)
        if not fs.exists(dir) then return end
        for name in fs.list(dir) do
            local p = dir .. "/" .. name:gsub("/$", "")
            if name:sub(-1) == "/" then walk(p)
            elseif name:match("%.neu$") and fs.exists(p:sub(1, -5)) then list[#list + 1] = { path = p, why = "halb geschrieben", size = fs.size(p) }
            elseif name == "gts.log.alt" then list[#list + 1] = { path = p, why = "altes Protokoll", size = fs.size(p) }
            elseif dir:match("/%.update$") and K.sys.update.state ~= "ready" then list[#list + 1] = { path = p, why = "Update-Reste", size = fs.size(p) }
            end
        end
    end
    walk(K.ROOT)
    return list
end
function Y.clean()
    local n, bytes = 0, 0
    for _, j in ipairs(Y.junk()) do bytes = bytes + j.size fs.remove(j.path) n = n + 1 end
    return n, bytes
end

-- Update ---------------------------------------------------------------
-- oc/manifest.lua: { version, notes, files = { { path, size, sha }, ... } }
local function fetch(url)
    if not component.isAvailable("internet") then return nil, "keine Internet Card" end
    local inet = component.internet
    local ok, h = pcall(inet.request, url .. "?t=" .. math.floor(K.realMs() / 60000))
    if not ok or not h then return nil, tostring(h) end
    local dl = computer.uptime() + 20
    while true do
        local ok2, done = pcall(h.finishConnect)
        if not ok2 then return nil, tostring(done) end
        if done then break end
        if computer.uptime() > dl then pcall(h.close) return nil, "Zeitüberschreitung" end
        K.sleep(0.1)
    end
    local okr, code = pcall(h.response)
    code = okr and tonumber(code) or nil
    if code and code >= 400 then pcall(h.close) return nil, "HTTP " .. code end
    local out = {}
    while true do
        local okc, chunk, err = pcall(h.read, 8192)
        if not okc then pcall(h.close) return nil, tostring(chunk) end
        if chunk == nil then if err then pcall(h.close) return nil, err end break end
        if chunk == "" then K.sleep(0.05) else out[#out + 1] = chunk end
        if computer.uptime() > dl then pcall(h.close) return nil, "Zeitüberschreitung" end
    end
    pcall(h.close)
    return table.concat(out)
end
Y.fetch = fetch

local function verLess(a, b)
    local function parts(v) local t = {} for n in tostring(v):gmatch("%d+") do t[#t + 1] = tonumber(n) end return t end
    local x, y = parts(a), parts(b)
    for i = 1, math.max(#x, #y) do
        if (x[i] or 0) ~= (y[i] or 0) then return (x[i] or 0) < (y[i] or 0) end
    end
    return false
end
Y.verLess = verLess

function Y.checkUpdate()
    local U = Y.update
    U.state, U.err = "checking", nil
    K.dirty = true
    local txt, err = fetch(REPO .. "manifest.lua")
    if not txt then U.state, U.err = "error", err K.dirty = true return end
    local f = load("return " .. txt:gsub("^%s*%-%-[^\n]*\n", ""):gsub("^%s*%-%-[^\n]*\n", ""), "=manifest", "t", {})
    local ok, man = pcall(f or error)
    if not ok or type(man) ~= "table" or not man.version then U.state, U.err = "error", "Manifest unlesbar" K.dirty = true return end
    U.manifest = man
    U.checked = K.clock()
    if verLess(K.VERSION, man.version) then
        U.state = "available"
        K.notify("GTS OS " .. man.version .. " ist da (SYSTEM > UPDATE)", "info", "info")
    else
        U.state = "current"
    end
    K.dirty = true
end

function Y.installUpdate()
    local U = Y.update
    local man = U.manifest
    if not man then return end
    U.state = "downloading"
    U.done, U.total = 0, #man.files
    local stage = K.ROOT .. "/.update"
    if fs.exists(stage) then fs.remove(stage) end
    fs.makeDirectory(stage)
    local data = component.isAvailable("data") and component.data
    for _, f in ipairs(man.files) do
        local body, err = fetch(REPO .. f.path)
        if not body then U.state, U.err = "error", f.path .. ": " .. tostring(err) K.dirty = true return end
        if f.size and #body ~= f.size then U.state, U.err = "error", f.path .. ": Größe falsch" K.dirty = true return end
        if data and f.sha then
            local h = (data.sha256(body):gsub(".", function(c) return string.format("%02x", c:byte()) end))
            if h ~= f.sha then U.state, U.err = "error", f.path .. ": Prüfsumme falsch" K.dirty = true return end
        end
        if not S.write(stage .. "/" .. f.path, body) then U.state, U.err = "error", "Speicher voll" K.dirty = true return end
        U.done = U.done + 1
        K.dirty = true
        K.sleep(0)
    end
    -- alles da: alte Dateien sichern, neue einsetzen
    for _, f in ipairs(man.files) do
        local dst = K.ROOT .. "/" .. f.path
        S.copy(stage .. "/" .. f.path, dst)
    end
    fs.remove(stage)
    K.set.updatedFrom = K.VERSION
    K.save()
    U.state = "ready"
    K.log("INFO", "Update auf " .. man.version .. " installiert")
    K.dirty = true
end

-- Dienst: Messwerte, taegliches Backup, Update-Suche ---------------------
function Y.service()
    local lastDay
    K.sleep(3)
    while true do
        local ram = 1 - computer.freeMemory() / math.max(1, computer.totalMemory())
        local e = computer.energy() / math.max(1, computer.maxEnergy())
        table.insert(Y.hist.ram, ram)
        table.insert(Y.hist.energy, e)
        while #Y.hist.ram > 120 do table.remove(Y.hist.ram, 1) end
        while #Y.hist.energy > 120 do table.remove(Y.hist.energy, 1) end
        local y, mo, d = K.localTime()
        local day = string.format("%04d-%02d-%02d", y, mo, d)
        if day ~= lastDay then
            lastDay = day
            if K.set.lastBackup ~= day then pcall(Y.backup) end
            if K.set.autoUpdate ~= false and component.isAvailable("internet") then Y.checkUpdate() end
        end
        if K.set.safeMode and computer.uptime() > 600 and #(K.set.crashes or {}) > 0 then
            K.set.crashes = {}
            K.save()
        end
        K.sleep(5)
    end
end

return Y
end
