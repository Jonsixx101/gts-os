-- ======================================================================
-- GTS OS (OpenComputers) - dev: alle Geraete im Verbund
-- ======================================================================
-- Ein Verzeichnis fuer die Komponenten dieses Rechners UND aller Knoten.
-- Apps fragen Werte mit D.get (zwischengespeichert, der Dienst holt sie
-- nach) und loesen Aktionen mit D.call aus - egal, wo das Geraet haengt.
-- Ereignisse (Kartenleser, Melder, Redstone ...) kommen ueber D.on.
return function(K, S, N, U)
local component = require("component")
local computer = require("computer")
local O = K.lib("ops")
local D = { list = {}, byAddr = {}, want = {}, pend = {}, q = 0, listeners = {}, ver = 0, O = O, ruleLog = {} }
local NAMEFILE = K.ROOT .. "/data/geraete.db"
local RULEFILE = K.ROOT .. "/data/regeln.db"
D.names = S.load(NAMEFILE, {})
D.rules = S.load(RULEFILE, {})
D.WEAPON = O.WEAPON

-- Arten: Bereich + Name ---------------------------------------------------
-- Bereiche: sicherheit, anlagen, lager, system, verbund, sonstige
local T = {
    os_door = { "sicherheit", "Tür" }, os_rfidreader = { "sicherheit", "RFID-Leser" }, os_magreader = { "sicherheit", "Kartenleser" },
    os_biometric = { "sicherheit", "Biometrie-Leser" }, os_keypad = { "sicherheit", "Tastenfeld" }, os_entdetector = { "sicherheit", "Melder" },
    os_alarm = { "sicherheit", "Alarm" }, os_cardwriter = { "sicherheit", "Kartenschreiber" }, os_switchinghub = { "sicherheit", "Switch" },
    os_datablock = { "system", "Datenblock" }, os_kvm = { "system", "KVM" }, os_energyturret = { "sonstige", "Geschütz (keine Automatik)" },
    redstone = { "sicherheit", "Redstone" }, motion_sensor = { "sicherheit", "Bewegungssensor" },
    rbmk_console = { "anlagen", "RBMK-Konsole" }, ntm_energy_storage = { "anlagen", "Energiespeicher" },
    ntm_energy_storage_legacy = { "anlagen", "Energiespeicher" }, ntm_turbine = { "anlagen", "Dampfturbine" },
    ntm_gas_turbine = { "anlagen", "Gasturbine" }, ntm_combustion_engine = { "anlagen", "Verbrennungsmotor" },
    ntm_fluid_tank = { "anlagen", "Tank" }, ntm_mass_storage = { "anlagen", "Massenspeicher" }, ntm_fluid_gauge = { "anlagen", "Durchfluss" },
    ntm_power_gauge = { "anlagen", "Stromzähler" }, ntm_geiger = { "anlagen", "Geigerzähler" }, zirnox_reactor = { "anlagen", "ZIRNOX" },
    research_reactor = { "anlagen", "Forschungsreaktor" }, ntm_pwr_control = { "anlagen", "PWR" }, watz_reactor = { "anlagen", "Watz" },
    breeding_reactor = { "anlagen", "Brutreaktor" }, ntm_pile_control = { "anlagen", "Graphit-Meiler" },
    dfc_emitter = { "anlagen", "DFC-Emitter" }, dfc_receiver = { "anlagen", "DFC-Empfänger" }, dfc_injector = { "anlagen", "DFC-Injektor" },
    dfc_stabilizer = { "anlagen", "DFC-Stabilisator" }, ntm_coker = { "anlagen", "Koker" }, reactor_control = { "anlagen", "Reaktorsteuerung" },
    ntm_fusion_torus = { "anlagen", "Fusion" }, rbmk_crane = { "anlagen", "RBMK-Kran" },
    ntm_turret = { "sonstige", "Geschütz (keine Automatik)" }, ntm_artillery = { "sonstige", "Artillerie (keine Automatik)" },
    ntm_launch_pad = { "sonstige", "Startrampe (keine Automatik)" }, ntm_custom_launch_pad = { "sonstige", "Startrampe (keine Automatik)" },
    me_controller = { "lager", "ME-Controller" }, me_interface = { "lager", "ME-Interface" }, me_exportbus = { "lager", "ME-Exportbus" },
    me_importbus = { "lager", "ME-Importbus" },
    gpu = { "system", "Grafikkarte" }, screen = { "system", "Bildschirm" }, keyboard = { "system", "Tastatur" },
    filesystem = { "system", "Speicher" }, modem = { "system", "Netzwerk/Funk" }, data = { "system", "Data Card" },
    internet = { "system", "Internet Card" }, eeprom = { "system", "EEPROM" }, computer = { "system", "Computer" },
    tunnel = { "system", "Linked Card" }, hologram = { "sonstige", "Hologramm" }, geolyzer = { "sonstige", "Geolyzer" },
    navigation = { "sonstige", "Navigation" }, transposer = { "sonstige", "Transposer" }, chunkloader = { "sonstige", "Chunkloader" },
    sound = { "sonstige", "Soundkarte" }, chat_box = { "sonstige", "Chat Box" }, tape_drive = { "sonstige", "Bandlaufwerk" },
    printer3d = { "sonstige", "3D-Drucker" }, disk_drive = { "system", "Laufwerk" }, database = { "lager", "Datenbank" },
}
D.TYPES = T
D.CATS = { { id = "sicherheit", text = "SICHERHEIT" }, { id = "anlagen", text = "ANLAGEN" }, { id = "lager", text = "LAGER" },
           { id = "sonstige", text = "SONSTIGE" }, { id = "system", text = "SYSTEM" } }
function D.kind(t)
    local d = T[t]
    if d then return d[1], d[2] end
    if t:match("^rbmk_") or t:match("^ntm_") or t:match("^dfc_") or t:match("_reactor$") or t:match("^radio_") then return "anlagen", t end
    if t:match("^os_") then return "sicherheit", t end
    if t:match("^me_") then return "lager", t end
    return "sonstige", t
end
-- Infrastruktur, die nicht als Geraet zaehlt
local INFRA = { computer = true, eeprom = true, filesystem = true, keyboard = true, gpu = true, screen = true }

-- Verzeichnis neu aufbauen ------------------------------------------------
function D.rebuild()
    local list, by = {}, {}
    local function add(addr, t, node)
        local cat, name = D.kind(t)
        local e = { addr = addr, type = t, node = node, cat = cat, kind = name, infra = INFRA[t] or nil,
                    weapon = O.WEAPON[t] or nil }
        list[#list + 1] = e
        by[addr] = e
    end
    for addr, t in component.list() do add(addr, t, nil) end
    for _, u in ipairs(U.list) do
        if U.isNode(u) and u.comps and not u.waiting then
            for addr, t in pairs(u.comps) do if not by[addr] then add(addr, t, u.addr) end end
        end
    end
    table.sort(list, function(a, b)
        if a.cat ~= b.cat then return a.cat < b.cat end
        return D.label(a) < D.label(b)
    end)
    D.list, D.byAddr = list, by
    D.ver = D.ver + 1
    K.dirty = true
end
function D.label(e)
    if type(e) == "string" then e = D.byAddr[e] if not e then return "?" end end
    return D.names[e.addr] or (e.kind .. " " .. e.addr:sub(1, 4))
end
function D.rename(addr, name)
    D.names[addr] = (name and name ~= "") and name:sub(1, 24) or nil
    S.save(NAMEFILE, D.names)
    D.rebuild()
end
function D.of(cat, typePattern)
    local out = {}
    for _, e in ipairs(D.list) do
        if (not cat or e.cat == cat) and (not typePattern or e.type:match(typePattern)) and not e.infra then out[#out + 1] = e end
    end
    return out
end
function D.where(e)
    if not e.node then return "dieser Rechner" end
    local u = U.byAddr[e.node]
    return u and ("Knoten " .. U.label(u)) or "Knoten ?"
end
function D.online(e)
    if type(e) == "string" then e = D.byAddr[e] end
    if not e then return false end
    if not e.node then return true end
    local u = U.byAddr[e.node]
    return u and u.online or false
end
-- Komponenten-Grenze der CPU (16 bei Tier 3)
local capCache
function D.limit()
    local n = 0
    for _ in component.list() do n = n + 1 end
    if not capCache then
        capCache = 16
        pcall(function()
            for _, i in pairs(computer.getDeviceInfo()) do
                if i.class == "processor" and i.description == "CPU" and tonumber(i.capacity or "") then capCache = tonumber(i.capacity) end
            end
        end)
    end
    return n, capCache
end
K.on("component_added", function(_, t) if t == "computer" then capCache = nil end end)

-- Aufrufe -------------------------------------------------------------------
-- cb(res): res = { true, Wert, ... } oder { false, Fehler }
local function sendCalls(node, list)
    D.q = D.q + 1
    local q = D.q
    local calls = {}
    for i, it in ipairs(list) do calls[i] = it.c end
    D.pend[q] = { list = list, t = computer.uptime(), node = node }
    if not N.sendBig(node, { t = "CALL", q = q, c = calls, aes = N.aes }) then
        D.pend[q] = nil
        for _, it in ipairs(list) do if it.cb then pcall(it.cb, { false, "Funk aus" }) end end
    end
end
function D.call(addr, m, p, cb, opts)
    local e = D.byAddr[addr]
    if opts and opts.weaponCheck ~= false and e and e.weapon and opts.auto then
        local r = { false, "Waffen werden nicht automatisch bedient" }
        if cb then cb(r) end
        return r
    end
    local c = { a = addr, m = m, p = p, f = opts and opts.f, x = opts and opts.x }
    if not e or not e.node then
        local r = O.call(c)
        if cb then cb(r) end
        return r
    end
    local u = U.byAddr[e.node]
    if not u or not u.online then
        local r = { false, "Knoten offline" }
        if cb then cb(r) end
        return r
    end
    sendCalls(e.node, { { c = c, cb = cb } })
end
-- Wert mit Zwischenspeicher: liefert das letzte Ergebnis (oder nil) und
-- sorgt dafuer, dass der Dienst es regelmaessig neu holt, solange es gebraucht wird
function D.get(addr, m, p, every, opts)
    local key = addr .. "|" .. m .. "|" .. (p and N.ser(p) or "") .. "|" .. ((opts and opts.key) or "")
    local w = D.want[key]
    local now = computer.uptime()
    if not w then
        w = { addr = addr, m = m, p = p, every = every or 2, opts = opts }
        D.want[key] = w
        D.kick = true
    end
    w.asked = now
    if opts and opts.x then w.opts = opts end
    return w.r, w.t and (now - w.t) or nil
end
function D.refresh(addr, m, p, opts)
    local key = addr .. "|" .. m .. "|" .. (p and N.ser(p) or "") .. "|" .. ((opts and opts.key) or "")
    local w = D.want[key]
    if w then w.t = nil D.kick = true end
end
-- Antworten der Knoten
U.onNode[#U.onNode + 1] = function(u, m, dist, mode)
    if m.t == "RES" then
        local p = D.pend[m.q]
        if not p then return end
        D.pend[m.q] = nil
        for i, it in ipairs(p.list) do
            local r = (m.r or {})[i] or { false, "keine Antwort" }
            if it.cb then pcall(it.cb, r) end
        end
        K.dirty = true
    elseif m.t == "UP" then
        u.kind = "node"
        u.secure = mode == "E"
        local peer = N.peers[u.addr]
        u.wired = dist == 0 or (peer and peer.wiredT and computer.uptime() - peer.wiredT < 30) or false
        u.rulesN = m.rules
        if m.comps then u.comps = m.comps D.rebuild() if u.rulesSent ~= D.rulesVer then D.pushRules(u.addr) end end
    elseif m.t == "EV" and m.ev == "sig" then
        local a = m.a or {}
        D.emit(tostring(m.s), table.unpack(a, 1, 8))
    elseif m.t == "EV" and m.ev == "rule" then
        D.ruleFired(m.id, m.v, m.why, m.done, u)
    end
end

-- Ereignisse -----------------------------------------------------------------
-- fn(Geraeteadresse, ...) fuer Signale von Geraeten (lokal und auf Knoten)
function D.on(name, fn)
    D.listeners[name] = D.listeners[name] or {}
    table.insert(D.listeners[name], fn)
end
function D.emit(name, ...)
    for _, fn in ipairs(D.listeners[name] or {}) do
        local ok, err = pcall(fn, ...)
        if not ok then K.log("FEHLER", "Ereignis " .. name .. ": " .. tostring(err)) end
    end
    for _, fn in ipairs(D.listeners["*"] or {}) do pcall(fn, name, ...) end
end
local SYS = { modem_message = true, touch = true, drag = true, drop = true, scroll = true, key_down = true, key_up = true,
              clipboard = true, screen_resized = true, component_added = true, component_removed = true, interrupted = true,
              component_available = true, component_unavailable = true, internet_ready = true }
K.on("*", function(ev)
    local name, addr = ev[1], ev[2]
    if SYS[name] or type(addr) ~= "string" then return end
    if not D.byAddr[addr] then return end
    D.emit(name, table.unpack(ev, 2, ev.n))
end)
K.on("component_added", function() D.dirtyList = true end)
K.on("component_removed", function() D.dirtyList = true end)

-- Waechter-Regeln ----------------------------------------------------------
-- D.rules = { { id, name, a, m, p, i, k, op, v, every, act = {...}, kind, hull, core, cool }, ... }
D.rulesVer = 1
function D.saveRules() S.save(RULEFILE, D.rules) D.rulesVer = D.rulesVer + 1 D.pushRules() end
function D.pushRules(onlyNode)
    local byNode, loc = {}, {}
    for _, r in ipairs(D.rules) do
        if not r.off then
            local e = D.byAddr[r.a]
            if e and e.node then byNode[e.node] = byNode[e.node] or {} table.insert(byNode[e.node], r)
            elseif e then loc[#loc + 1] = r end
        end
    end
    if not onlyNode then O.setRules(loc) end
    for _, u in ipairs(U.nodes()) do
        if u.online and (not onlyNode or onlyNode == u.addr) then
            U.cmd(u.addr, "rules", { list = byNode[u.addr] or {} }, "Regeln")
            u.rulesSent = D.rulesVer
        end
    end
end
function D.ruleFired(id, v, why, done, u)
    local r
    for _, x in ipairs(D.rules) do if x.id == id then r = x end end
    local name = r and r.name or tostring(id)
    local text = "Wächter „" .. name .. "“ hat ausgelöst" .. (why and (": " .. why) or (v and (" (" .. tostring(math.floor(v * 10) / 10) .. ")") or ""))
    K.notify(text, "bad", "anlagen")
    K.log("WARN", text .. " -> " .. table.concat(done or {}, ", "))
    -- Massnahmen ueber SICHERHEIT (Alarm, Redstone-Ausgaenge)
    if r and K.sec then
        if r.alarm then K.sec.alarm(true, name) end
        for _, id in ipairs(r.outs or {}) do K.sec.trigger(id, "Wächter " .. name) end
    end
    table.insert(D.ruleLog, 1, { clock = K.clock(), text = text, done = done })
    while #D.ruleLog > 30 do table.remove(D.ruleLog) end
    if K.onRule then pcall(K.onRule, r, v, why) end
end

-- Internet (eigene Karte oder ueber einen Knoten) ---------------------------
function D.inetNode()
    for _, u in ipairs(U.nodes()) do if u.online and u.inet then return u end end
end
-- nur aus einem Dienst aufrufen (wartet). Liefert Text, Code oder nil, Fehler
function D.httpViaNode(url, body, headers, method, needSecure)
    local u = D.inetNode()
    if not u then return nil, "Keine Internet Card - weder hier noch an einem Knoten" end
    if needSecure and not (u.secure or u.wired) then
        return nil, "Der Knoten " .. U.label(u) .. " ist nur gesiegelt per Funk verbunden - für geheime Daten AES (Data Card Tier 2 an beiden) oder Kabel nötig"
    end
    local res
    sendCalls(u.addr, { { c = { m = "__http", p = { url, body, headers, method } }, cb = function(r) res = r end } })
    D.pend[D.q].long = true
    local dl = computer.uptime() + 75
    while not res and computer.uptime() < dl do K.sleep(0.1) end
    if not res then return nil, "Knoten antwortet nicht" end
    if not res[1] then return nil, tostring(res[2]) end
    local r = res[2] or {}
    return r.body or "", tonumber(r.code) or 0
end

-- Dienst: Werte holen, Zeitueberschreitungen, lokale Regeln ------------------
function D.service()
    D.rebuild()
    D.pushRules()
    local lastClean = computer.uptime()
    while true do
        local now = computer.uptime()
        if D.dirtyList then D.dirtyList = false D.rebuild() end
        -- gewuenschte Werte holen (lokal sofort, Knoten gebuendelt)
        local batches = {}
        local changed = false
        for key, w in pairs(D.want) do
            if now - (w.asked or 0) > 30 then D.want[key] = nil
            elseif now - (w.asked or 0) < 6 and not w.busy and (not w.t or now - w.t >= w.every) then
                local e = D.byAddr[w.addr]
                local c = { a = w.addr, m = w.m, p = w.p, f = w.opts and w.opts.f, x = w.opts and w.opts.x }
                if e and e.node then
                    local u = U.byAddr[e.node]
                    if u and u.online then
                        w.busy = true
                        batches[e.node] = batches[e.node] or {}
                        table.insert(batches[e.node], { c = c, cb = function(r) w.r, w.t, w.busy = r, computer.uptime(), nil end })
                    else
                        w.r, w.t = { false, "Knoten offline" }, now
                    end
                elseif e then
                    w.r, w.t = O.call(c), computer.uptime()
                    changed = true
                else
                    w.r, w.t = { false, "nicht angeschlossen" }, now
                end
            end
        end
        for node, list in pairs(batches) do sendCalls(node, list) end
        if changed then K.dirty = true end
        -- Zeitueberschreitung
        for q, p in pairs(D.pend) do
            if now - p.t > (p.long and 80 or 6) then
                D.pend[q] = nil
                for _, it in ipairs(p.list) do if it.cb then pcall(it.cb, { false, "keine Antwort vom Knoten" }) end end
                K.dirty = true
            end
        end
        -- lokale Waechter
        O.tick(now, function(id, v, why, done) D.ruleFired(id, v, why, done, nil) end)
        if now - lastClean > 60 then lastClean = now end
        D.kick = false
        local t = 0
        while t < 0.5 and not D.kick do K.sleep(0.1) t = t + 0.1 end
    end
end

return D
end
