-- ======================================================================
-- GTS OS (OpenComputers) - warp: WarpDrive (Schiff, Radar, Tarnung)
-- ======================================================================
-- Befehle wie im WarpDrive-Quelltext (Zweig MC1.7, 1.4.x):
--   Ship Controller: shipName, dim_positive/negative (vorn,rechts,hoch /
--     hinten,links,runter), movement (vorn, hoch, rechts), rotationSteps,
--     command ("MANUAL", "HYPERDRIVE", "IDLE" ...), enable(true) = Sprung,
--     getMaxJumpDistance -> ok, Bloecke; getEnergyRequired -> ok, EU;
--     energy -> gespeichert, max; position -> x,y,z (Kern);
--     getOrientation -> dx, 0, dz; getShipSize -> Masse, Volumen
--   Radar: radius(r), getEnergyRequired(r), getScanDuration(r), start(),
--     getResultsCount() (-1 = laeuft), getResult(i) (ab 0) ->
--     ok, Typ, Name, x, y, z, Masse (universelle Koordinaten);
--     position -> x,y,z, Ort, ux,uy,uz
--   Signal "shipCoreCooldownDone" wenn das Schiff wieder springen kann.
-- Jeder WarpDrive-Aufruf kostet einen Server-Tick (50 ms). Darum werden
-- die Werte im Hintergrund gesammelt (W.st) und nicht beim Zeichnen.
-- Aeltere WarpDrive-Fassungen kennen manche Befehle nicht: alles mit pcall.
return function(K, S)
local component = require("component")
local computer = require("computer")
local W = { scan = { state = "idle" }, st = nil, hist = {}, open = false }
local DB = K.ROOT .. "/data/schiff.db"
local db = S.load(DB, {})
db.contacts = db.contacts or {}
db.radius = db.radius or 2000
db.autoEvery = db.autoEvery or 0          -- Minuten, 0 = aus
db.history = db.history or {}
db.targets = db.targets or {}
W.db = db
function W.save() S.save(DB, db) end

-- Erkundung, die beim letzten Start lief, gilt als unterbrochen
if db.survey and db.survey.active then
    db.survey.active = false
    db.survey.interrupted = true
    db.survey.state = "unterbrochen (Neustart)"
end

local function first(t)
    for a in component.list(t, true) do return component.proxy(a) end
end
function W.ship() return first("warpdriveShipController") end
function W.radar() return first("warpdriveRadar") end
function W.cloak() return first("warpdriveCloakingCore") end
function W.available() return W.ship() ~= nil or W.radar() ~= nil or W.cloak() ~= nil end

-- Aufruf ohne Absturz; liefert alle Rueckgaben oder nil, Fehler
local function call(dev, method, ...)
    if not dev or type(dev[method]) ~= "function" and type(dev[method]) ~= "table" then return nil, "nicht vorhanden" end
    local r = table.pack(pcall(dev[method], ...))
    if not r[1] then return nil, tostring(r[2]) end
    return table.unpack(r, 2, r.n)
end
W.call = call

W.TYPES = {
    ship = { "Schiff", "warn" }, jumpgate = { "Sprungtor", "info" }, planet = { "Planet", "accent" },
    star = { "Stern", "white" }, structure = { "Struktur", "dim" }, warp_echo = { "Warp-Echo", "bad" },
    transporter = { "Transporter", "info" },
}
W.MODES = { OFFLINE = "aus", IDLE = "bereit", MANUAL = "manuell", HYPERDRIVE = "Hyperraum", SUMMON = "Rufen",
            GATE = "Sprungtor", MAINTENANCE = "Wartung" }
W.DIRS = { N = { 0, -1, "Norden" }, O = { 1, 0, "Osten" }, S = { 0, 1, "Süden" }, W = { -1, 0, "Westen" } }

-- ---------------------------------------------------------------------
-- Schiffsdaten (gesammelt)
-- ---------------------------------------------------------------------
-- full = alles (ca. 15 Aufrufe), sonst nur Energie/Modus/Position
function W.refresh(full)
    local s = W.ship()
    if not s then W.st = nil return nil end
    local st = W.st or {}
    if full or not st.full then
        st.name = call(s, "shipName")
        st.front, st.right, st.up = call(s, "dim_positive")
        st.back, st.left, st.down = call(s, "dim_negative")
        st.mass, st.volume = call(s, "getShipSize")
        local fx, _, fz = call(s, "getOrientation")
        st.fx, st.fz = tonumber(fx) or 0, tonumber(fz) or 0
        st.space = call(s, "isInSpace") == true
        st.hyper = call(s, "isInHyperspace") == true
        local okJ, dist = call(s, "getMaxJumpDistance")
        if okJ == true then st.maxJump, st.maxJumpErr = tonumber(dist), nil else st.maxJump, st.maxJumpErr = nil, dist end
        local list, players = call(s, "getAttachedPlayers")
        st.players = type(players) == "table" and players or {}
        if #st.players == 0 and type(list) == "string" and list ~= "" then
            for p in list:gmatch("[^,]+") do st.players[#st.players + 1] = p end
        end
        st.full = true
        st.fullT = computer.uptime()
    end
    local ok, msg = call(s, "isAssemblyValid")
    st.valid, st.validMsg = ok == true, msg
    st.mode = call(s, "command")
    st.energy, st.energyMax = call(s, "energy")
    st.energy, st.energyMax = tonumber(st.energy) or 0, tonumber(st.energyMax) or 0
    st.x, st.y, st.z = call(s, "position")
    st.t = computer.uptime()
    W.st = st
    local h = W.hist
    h[#h + 1] = st.energyMax > 0 and st.energy / st.energyMax or 0
    while #h > 60 do table.remove(h, 1) end
    K.dirty = true
    return st
end
function W.facingName(st)
    st = st or W.st
    if not st then return "?" end
    for _, d in pairs(W.DIRS) do if d[1] == st.fx and d[2] == st.fz then return d[3] end end
    return "?"
end
-- Weltversatz <-> Schiffsachsen (WarpDrive: moveX = fx*vorn - fz*rechts,
-- moveZ = fz*vorn + fx*rechts)
function W.toLocal(dx, dz, st)
    st = st or W.st
    local fx, fz = st and st.fx or 0, st and st.fz or -1
    return fx * dx + fz * dz, -fz * dx + fx * dz
end
function W.toWorld(front, right, st)
    st = st or W.st
    local fx, fz = st and st.fx or 0, st and st.fz or -1
    return fx * front - fz * right, fz * front + fx * right
end
-- groesste erlaubte Bewegung je Achse (Schiffsgroesse + Sprungweite)
function W.axisLimit(axis, st)
    st = st or W.st
    if not st or not st.maxJump then return nil end
    local size
    if axis == "front" then size = (st.front or 0) + 1 + (st.back or 0)
    elseif axis == "right" then size = (st.right or 0) + 1 + (st.left or 0)
    else size = (st.up or 0) + 1 + (st.down or 0) end
    return size + st.maxJump, size
end

-- Energiebedarf fuer eine geplante Bewegung (setzt MANUAL + movement)
function W.plan(front, up, right, rot)
    local s = W.ship()
    if not s then return nil, "keine Schiffssteuerung" end
    call(s, "enable", false)
    call(s, "command", "MANUAL")
    call(s, "movement", front, up, right)
    call(s, "rotationSteps", rot or 0)
    local okJ, maxD = call(s, "getMaxJumpDistance")
    local okE, need = call(s, "getEnergyRequired")
    local p = { front = front, up = up, right = right, rot = rot or 0, t = computer.uptime(),
                maxJump = okJ == true and tonumber(maxD) or nil, maxErr = okJ ~= true and maxD or nil,
                energy = okE == true and tonumber(need) or nil, energyErr = okE ~= true and need or nil }
    if W.st and p.maxJump then W.st.maxJump = p.maxJump end
    -- Pruefung
    local st = W.st or {}
    local problems = {}
    if st.valid == false then problems[#problems + 1] = "Schiff ungültig: " .. tostring(st.validMsg) end
    if p.maxErr then problems[#problems + 1] = tostring(p.maxErr) end
    if p.energyErr then problems[#problems + 1] = tostring(p.energyErr) end
    if front == 0 and up == 0 and right == 0 and (rot or 0) == 0 then problems[#problems + 1] = "Keine Bewegung eingestellt" end
    for _, ax in ipairs({ { "front", front, "vorn" }, { "up", up, "hoch" }, { "right", right, "rechts" } }) do
        local lim = W.axisLimit(ax[1], st)
        if lim and math.abs(ax[2]) > lim then
            problems[#problems + 1] = "Zu weit " .. ax[3] .. ": " .. math.abs(ax[2]) .. " (max " .. lim .. ")"
        end
    end
    if p.energy and st.energy and st.energy < p.energy then
        problems[#problems + 1] = "Zu wenig Energie (" .. W.fmt(st.energy) .. " von " .. W.fmt(p.energy) .. ")"
    end
    p.problems = problems
    p.ok = #problems == 0
    W.lastPlan = p
    return p
end

-- Sprung ausloesen; kind = "MANUAL" | "HYPERDRIVE"
function W.jump(kind, front, up, right, rot)
    local s = W.ship()
    if not s then return false, "keine Schiffssteuerung" end
    local ok, msg = call(s, "isAssemblyValid")
    if ok ~= true then return false, tostring(msg or "Schiff ungültig") end
    if kind == "HYPERDRIVE" then
        call(s, "command", "HYPERDRIVE")
    else
        call(s, "command", "MANUAL")
        call(s, "movement", front or 0, up or 0, right or 0)
        call(s, "rotationSteps", rot or 0)
    end
    local _, err = call(s, "enable", true)
    local st = W.st or {}
    local dx, dz = W.toWorld(front or 0, right or 0)
    db.history[#db.history + 1] = { t = K.realMs(), clock = K.clock(), kind = kind, f = front, u = up, r = right, rot = rot,
                                    from = st.x and { st.x, st.y, st.z } or nil,
                                    to = st.x and kind ~= "HYPERDRIVE" and { st.x + dx, st.y + (up or 0), st.z + dz } or nil }
    while #db.history > 30 do table.remove(db.history, 1) end
    W.save()
    K.log("INFO", "Sprung " .. kind .. " " .. tostring(front) .. "/" .. tostring(up) .. "/" .. tostring(right) .. " rot " .. tostring(rot))
    return true, err
end
function W.abort()
    local s = W.ship()
    if s then call(s, "enable", false) call(s, "command", "IDLE") end
    K.log("INFO", "Sprung abgebrochen")
end
function W.rename(name)
    local s = W.ship()
    if not s then return end
    call(s, "shipName", name)
    if W.st then W.st.name = call(s, "shipName") end
end

-- ---------------------------------------------------------------------
-- Radar
-- ---------------------------------------------------------------------
function W.radarInfo(r)
    local rd = W.radar()
    if not rd then return nil end
    local e, emax = call(rd, "energy")
    local need = call(rd, "getEnergyRequired", r or db.radius)
    local dur = call(rd, "getScanDuration", r or db.radius)
    local _, _, _, place, ux, uy, uz = call(rd, "position")
    local info = { energy = tonumber(e), energyMax = tonumber(emax), need = tonumber(need), duration = tonumber(dur),
                   place = place, ux = ux, uy = uy, uz = uz, r = r or db.radius, t = computer.uptime() }
    W.rinfo = info
    return info
end

local function contactKey(c)
    if c.name and c.name ~= "" then return c.type .. "|" .. c.name end
    return c.type .. "|" .. math.floor(c.x / 32) .. "," .. math.floor(c.y / 32) .. "," .. math.floor(c.z / 32)
end
W.contactKey = contactKey

-- Scan als Dienst (blockiert nicht die Oberflaeche)
function W.runScan(r)
    local rd = W.radar()
    local sc = W.scan
    if not rd then sc.state, sc.err = "error", "kein Radar" return end
    if sc.state == "running" then return end
    r = r or db.radius
    sc.state, sc.err, sc.radius = "running", nil, r
    sc.startT = computer.uptime()
    K.dirty = true
    call(rd, "radius", r)
    local ok, err = call(rd, "start")
    if ok ~= true then sc.state, sc.err = "error", tostring(err or "Start abgelehnt") K.dirty = true return end
    local dur = tonumber((call(rd, "getScanDuration", r))) or 1
    sc.untilT = computer.uptime() + dur
    K.sleep(dur)
    local n
    for _ = 1, 60 do
        n = call(rd, "getResultsCount")
        if n and n >= 0 then break end
        K.sleep(0.25)
    end
    local info = W.radarInfo(r) or {}
    local results = {}
    local now = K.realMs()
    local newShips = {}
    local ownName = W.st and W.st.name
    for i = 0, (n or 0) - 1 do
        local okR, typ, name, x, y, z, mass = call(rd, "getResult", i)
        if okR == true and x then
            local c = { type = tostring(typ), name = name or "", x = math.floor(x), y = math.floor(y), z = math.floor(z), mass = mass }
            if info.ux then
                c.dx, c.dy, c.dz = c.x - math.floor(info.ux), c.y - math.floor(info.uy), c.z - math.floor(info.uz)
                c.dist = math.floor(math.sqrt(c.dx ^ 2 + c.dy ^ 2 + c.dz ^ 2))
            end
            c.own = c.type == "ship" and ((ownName and c.name == ownName) or (c.dist and c.dist < 48))
            results[#results + 1] = c
            if not c.own then
                local key = contactKey(c)
                local known = db.contacts[key]
                if not known then
                    known = { first = now, count = 0 }
                    db.contacts[key] = known
                    if c.type == "ship" or c.type == "warp_echo" then newShips[#newShips + 1] = c end
                end
                known.type, known.name, known.x, known.y, known.z, known.mass = c.type, c.name, c.x, c.y, c.z, mass
                known.last, known.count, known.dist, known.place = now, known.count + 1, c.dist, info.place
            end
        end
    end
    table.sort(results, function(a, b) return (a.dist or 0) < (b.dist or 0) end)
    sc.results, sc.state, sc.t, sc.clock = results, "done", now, K.clock()
    sc.center = info.ux and { x = info.ux, y = info.uy, z = info.uz } or nil
    db.lastScan = now
    db.lastCount = #results
    -- Kontaktliste klein halten (aelteste raus)
    local keys = {}
    for k, v in pairs(db.contacts) do keys[#keys + 1] = { k = k, t = v.last or 0 } end
    if #keys > 200 then
        table.sort(keys, function(a, b) return a.t < b.t end)
        for i = 1, #keys - 200 do db.contacts[keys[i].k] = nil end
    end
    W.save()
    if #newShips > 0 then
        local c = newShips[1]
        local label = (c.name ~= "" and c.name or W.typeName(c.type))
        K.notify("Radar: " .. (#newShips == 1 and ("neu: " .. label .. (c.dist and (" in " .. W.fmt(c.dist) .. " Bl.") or ""))
                                 or (#newShips .. " neue Schiffe/Echos")), "warn", "ship")
    end
    K.log("INFO", "Radar-Scan " .. r .. ": " .. #results .. " Kontakte")
    K.dirty = true
end
function W.typeName(t) return (W.TYPES[t] and W.TYPES[t][1]) or tostring(t) end
function W.typeColor(t, C) return C[(W.TYPES[t] and W.TYPES[t][2]) or "dim"] end

-- ---------------------------------------------------------------------
-- Erkundungsflug: n Spruenge in eine Himmelsrichtung, nach jedem Sprung
-- ein Radar-Scan. Bricht bei jedem Problem ab (Schiff bleibt stehen).
-- db.survey = { dir, step, total, done, scanR, active, state, log }
-- ---------------------------------------------------------------------
local function svStop(sv, msg, level)
    sv.active = false
    sv.state = msg
    W.save()
    K.notify("Erkundung: " .. msg, level or "warn", "ship")
    K.log("INFO", "Erkundung beendet: " .. msg)
    K.dirty = true
end
function W.surveyRun()
    local sv = db.survey
    if not sv then return end
    sv.active, sv.interrupted = true, false
    sv.log = sv.log or {}
    W.save()
    local s = W.ship()
    while sv.active and sv.done < sv.total do
        s = W.ship()
        if not s then return svStop(sv, "Schiffssteuerung fehlt", "bad") end
        sv.state = "prüfe Schiff"
        K.dirty = true
        local st = W.refresh(true)
        if not st or not st.valid then return svStop(sv, "Schiff ungültig: " .. tostring(st and st.validMsg), "bad") end
        local d = W.DIRS[sv.dir] or W.DIRS.N
        local lim = W.axisLimit((d[1] ~= 0 and st.fx ~= 0 or d[2] ~= 0 and st.fz ~= 0) and "front" or "right", st)
        local dist = sv.step
        if lim and dist > lim then dist = lim end
        local front, right = W.toLocal(d[1] * dist, d[2] * dist, st)
        local p = W.plan(front, 0, right, 0)
        if not p then return svStop(sv, "keine Schiffssteuerung", "bad") end
        if p.maxErr then return svStop(sv, tostring(p.maxErr), "bad") end
        -- auf Energie warten (hoechstens 10 Minuten)
        local waited = 0
        while sv.active and p.energy and (W.st.energy or 0) < p.energy do
            sv.state = "lädt Energie " .. math.floor((W.st.energy or 0) / p.energy * 100) .. " %"
            K.dirty = true
            K.sleep(10)
            waited = waited + 10
            W.refresh(false)
            if waited > 600 then return svStop(sv, "zu wenig Energie für den Sprung", "bad") end
        end
        if not sv.active then break end
        local x0, z0 = st.x, st.z
        sv.state = "Sprung " .. (sv.done + 1) .. " / " .. sv.total
        K.dirty = true
        local ok, err = W.jump("MANUAL", front, 0, right, 0)
        if not ok then return svStop(sv, "Sprung abgelehnt: " .. tostring(err), "bad") end
        local moved = false
        for _ = 1, 75 do
            K.sleep(2)
            if not sv.active then break end
            local x, _, z = call(s, "position")
            if x and (x ~= x0 or z ~= z0) then moved = true break end
        end
        if not sv.active then W.abort() break end
        if not moved then
            W.abort()
            return svStop(sv, "Sprung nicht erfolgt (Hindernis, Abkühlung oder Energie?)", "bad")
        end
        sv.done = sv.done + 1
        W.refresh(false)
        local entry = { n = sv.done, x = W.st.x, y = W.st.y, z = W.st.z, clock = K.clock() }
        sv.log[#sv.log + 1] = entry
        while #sv.log > 40 do table.remove(sv.log, 1) end
        W.save()
        if W.radar() and (sv.scanR or 0) > 0 then
            sv.state = "Radar-Scan " .. sv.done .. " / " .. sv.total
            K.dirty = true
            K.sleep(2)
            W.runScan(sv.scanR)
            entry.contacts = W.scan.results and #W.scan.results or 0
            local ships = 0
            for _, c in ipairs(W.scan.results or {}) do if not c.own and (c.type == "ship" or c.type == "warp_echo") then ships = ships + 1 end end
            entry.ships = ships
            W.save()
        end
        if sv.done < sv.total then
            sv.state = "Abkühlung"
            K.dirty = true
            K.waitSignal("shipCoreCooldownDone", tonumber(sv.cool) or 60)
        end
    end
    if sv.active then svStop(sv, "fertig: " .. sv.done .. (sv.done == 1 and " Sprung" or " Sprünge"), "ok") end
end
function W.surveyStop()
    if db.survey and db.survey.active then
        db.survey.active = false
        db.survey.state = "gestoppt"
        W.abort()
        W.save()
    end
end

-- ---------------------------------------------------------------------
-- Hintergrund: Werte sammeln + automatischer Scan (Lauschstation)
-- ---------------------------------------------------------------------
function W.service()
    K.sleep(3)
    local lastFull, lastQuick = -1e9, -1e9
    while true do
        local now = computer.uptime()
        if W.ship() then
            if now - lastFull >= (W.open and 20 or 120) then
                pcall(W.refresh, true)
                lastFull, lastQuick = now, now
            elseif now - lastQuick >= (W.open and 4 or 30) then
                pcall(W.refresh, false)
                lastQuick = now
            end
        end
        local every = tonumber(db.autoEvery) or 0
        if every > 0 and W.radar() and W.scan.state ~= "running" and not (db.survey and db.survey.active) then
            if K.realMs() - (db.lastScan or 0) >= every * 60000 then
                local ok, err = pcall(W.runScan, db.radius)
                if not ok then W.scan.state, W.scan.err = "error", tostring(err) end
            end
        end
        K.sleep(2)
    end
end

-- ---------------------------------------------------------------------
-- Tarnung
-- ---------------------------------------------------------------------
function W.cloakInfo()
    local c = W.cloak()
    if not c then return nil end
    local ok, msg = call(c, "isAssemblyValid")
    local e, emax = call(c, "energy")
    W.cinfo = { valid = ok == true, msg = msg, tier = tonumber((call(c, "tier"))) or 1, on = call(c, "enable") == true,
                energy = tonumber(e), energyMax = tonumber(emax), t = computer.uptime() }
    return W.cinfo
end
function W.setCloak(on, tier)
    local c = W.cloak()
    if not c then return false end
    if tier then call(c, "tier", tier) end
    if on ~= nil then call(c, "enable", on) end
    K.log("INFO", "Tarnung " .. tostring(on) .. " Stufe " .. tostring(tier))
    W.cloakInfo()
    return true
end

-- ---------------------------------------------------------------------
-- Hilfen
-- ---------------------------------------------------------------------
-- Richtung als Himmelsrichtung (x = Ost, z = Sued)
function W.bearing(dx, dz)
    if dx == 0 and dz == 0 then return "-" end
    local names = { "N", "NO", "O", "SO", "S", "SW", "W", "NW" }
    local a = math.atan2 and math.atan2(dx, -dz) or math.atan(dx, -dz)
    local i = math.floor((a / (2 * math.pi) * 8) + 0.5) % 8
    return names[i + 1]
end
-- grosse Zahlen kurz: 1234567 -> 1,2 Mio
function W.fmt(n)
    n = tonumber(n) or 0
    local a = math.abs(n)
    if a >= 1e9 then return (string.format("%.1f Mrd", n / 1e9):gsub("%.", ",")) end
    if a >= 1e6 then return (string.format("%.1f Mio", n / 1e6):gsub("%.", ",")) end
    if a >= 1e4 then return string.format("%d Tsd", math.floor(n / 1000)) end
    return tostring(math.floor(n))
end

return W
end
