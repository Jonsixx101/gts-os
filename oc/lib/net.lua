-- ======================================================================
-- GTS OS (OpenComputers) - net: verschluesselter Funk mit der Data Card
-- ======================================================================
-- Rahmen (ein String je Funkpaket):
--   "G1" .. Art .. Zaehler(16 Ziffern) .. [IV 16 Byte] .. Inhalt .. Siegel(16)
--   Art "E" = AES-128-CBC verschluesselt (Data Card Tier 2 auf beiden Seiten)
--   Art "S" = nur gesiegelt (lesbar, aber nicht faelschbar; Tier 1 reicht)
--   Siegel  = sha256(M .. sha256(M .. Absender .. Rahmen))[1..16]
--   Zaehler = Echtzeit in ms * 1000 (+ laufende Nummer), je Absender nur
--             steigend; erster Kontakt hoechstens 120 s alt.
-- Schluessel K aus dem Schwarm-Passwort (64 Runden SHA-256);
-- E = sha256("E"..K)[1..16], M = sha256("M"..K).
-- Inhalt: Lua-Tabelle als Text (gleiches Format wie im Drohnen-Lader).
-- SHA-256 kommt aus crypto.lua (Data Card, sonst Lua) - der Rechner braucht
-- darum keine eigene Data Card; ohne Tier-2-Karte gibt es nur kein AES.
-- Netz- und Funkkarte: eine Wireless-Karte spricht auch ueber Kabel.
return function(K, S)
local component = require("component")
local computer = require("computer")
local N = { peers = {}, last = {}, ready = false, reason = "nicht gestartet", seq = 0, port = 4711,
            stats = { rx = 0, tx = 0, bad = 0, foreign = 0 } }
local KEYFILE = K.ROOT .. "/data/schluessel.db"
local modem, data
local encKey, macKey, rawKey

local Cr = K.Cr
local sha = Cr.sha256
local hex, unhex = Cr.hex, Cr.unhex
N.hex, N.unhex = hex, unhex

-- Werte -> Lua-Text (nur einfache Daten)
local function ser(v)
    local t = type(v)
    if t == "string" then return string.format("%q", v):gsub("\\\n", "\\n") end
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "0" end
        if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%d", v) end
        return string.format("%.6g", v)
    end
    if t == "boolean" then return tostring(v) end
    if t ~= "table" then return "nil" end
    local out = {}
    local n = #v
    for i = 1, n do out[#out + 1] = ser(v[i]) end
    for k, x in pairs(v) do
        if not (type(k) == "number" and k >= 1 and k <= n and k % 1 == 0) then
            local ks = (type(k) == "string" and k:match("^[%a_][%w_]*$")) and k or ("[" .. ser(k) .. "]")
            out[#out + 1] = ks .. "=" .. ser(x)
        end
    end
    return "{" .. table.concat(out, ",") .. "}"
end
N.ser = ser
local function unser(s)
    if type(s) ~= "string" or #s > 60000 then return nil end
    local f = load("return " .. s, "=netz", "t", {})
    if not f then return nil end
    local ok, v = pcall(f)
    if ok then return v end
end
N.unser = unser

-- Schluessel ------------------------------------------------------------
function N.derive(pw)
    local h = sha("GTS-OC-1|" .. pw)
    for _ = 1, 64 do h = sha(h .. pw) end
    return h
end
local function setKey(k)
    rawKey = k
    encKey = sha("E" .. k):sub(1, 16)
    macKey = sha("M" .. k)
    N.last = {}
end
function N.keyHex() return rawKey and hex(rawKey) end
function N.setPassword(pw)
    local k = N.derive(pw)
    setKey(k)
    N.isDefault = (pw == "gts")
    S.save(KEYFILE, { key = hex(k), default = N.isDefault })
    K.log("INFO", "Schwarm-Passwort gesetzt")
    return true
end

-- Siegel und Rahmen ---------------------------------------------------------
local function seal(src, body)
    return sha(macKey .. sha(macKey .. src .. body)):sub(1, 16)
end
function N.nextCtr()
    local c = K.realMs() * 1000
    if c <= (N.lastCtr or 0) then c = N.lastCtr + 1 end
    N.lastCtr = c
    return c
end
-- Tabelle -> Rahmen (encrypt: nur wenn beide Seiten AES koennen)
function N.pack(tbl, encrypt)
    local body = ser(tbl)
    local ctr = string.format("%016.0f", N.nextCtr())
    local frame
    if encrypt and data and data.encrypt then
        local iv = data.random(16)
        frame = "G1E" .. ctr .. iv .. data.encrypt(body, encKey, iv)
    else
        frame = "G1S" .. ctr .. body
    end
    return frame .. seal(modem.address, frame)
end
-- Rahmen -> Tabelle oder nil, Grund
function N.unpack(frame, from)
    if type(frame) ~= "string" or #frame < 35 or frame:sub(1, 2) ~= "G1" then return nil, "fremd" end
    local mode = frame:sub(3, 3)
    local body, tag = frame:sub(1, -17), frame:sub(-16)
    if seal(from, body) ~= tag then return nil, "siegel" end
    local ctr = tonumber(frame:sub(4, 19))
    if not ctr then return nil, "zaehler" end
    local last = N.last[from]
    if last then
        -- gleicher Zaehler: dieselbe Nachricht zweimal (Wireless-Karte am Kabel sendet ueber beide Wege)
        if ctr == last then return nil, "doppelt" end
        if ctr < last then return nil, "wiederholt" end
    elseif math.abs(ctr / 1000 - K.realMs()) > 120000 then
        return nil, "zu alt"
    end
    local text
    if mode == "E" then
        if not (data and data.decrypt) then return nil, "kein AES" end
        local ok, plain = pcall(data.decrypt, body:sub(36), encKey, body:sub(20, 35))
        if not ok then return nil, "entschluesseln" end
        text = plain
    elseif mode == "S" then
        text = body:sub(20)
    else
        return nil, "art"
    end
    local t = unser(text)
    if type(t) ~= "table" then return nil, "inhalt" end
    N.last[from] = ctr
    return t, mode
end

-- Senden ---------------------------------------------------------------
function N.send(addr, tbl)
    if not N.ready then return false end
    tbl.to = addr
    local peer = N.peers[addr]
    local ok, err = pcall(function() modem.send(addr, N.port, N.pack(tbl, peer and peer.aes and N.aes)) end)
    if ok then N.stats.tx = N.stats.tx + 1 else K.log("WARN", "senden: " .. tostring(err)) end
    return ok
end
-- grosse Tabellen in Teilen (FR); die Gegenseite setzt sie zusammen
N.fid = 0
function N.sendBig(addr, tbl)
    tbl.to = addr
    local s = ser(tbl)
    if #s <= 3000 then return N.send(addr, tbl) end
    N.fid = N.fid + 1
    local n = math.ceil(#s / 3000)
    local ok = true
    for i = 1, n do ok = N.send(addr, { t = "FR", id = N.fid, n = i, of = n, d = s:sub((i - 1) * 3000 + 1, i * 3000) }) and ok end
    return ok
end
function N.broadcast(tbl)
    if not N.ready then return false end
    local ok = pcall(function() modem.broadcast(N.port, N.pack(tbl, false)) end)
    if ok then N.stats.tx = N.stats.tx + 1 end
    return ok
end

-- Empfang -------------------------------------------------------------
N.listeners = {}
function N.on(fn) N.listeners[#N.listeners + 1] = fn end
local function onMessage(localAddr, from, port, dist, frame)
    if not N.ready or port ~= N.port or localAddr ~= modem.address then return end
    local t, mode = N.unpack(frame, from)
    if dist == 0 and (t or mode == "doppelt") then
        -- per Kabel angekommen (Funk hat Abstand > 0)
        N.peers[from] = N.peers[from] or {}
        N.peers[from].wiredT = computer.uptime()
    end
    if not t then
        if mode == "fremd" then N.stats.foreign = N.stats.foreign + 1
        elseif mode ~= "doppelt" then N.stats.bad = N.stats.bad + 1 N.lastBad = { from = from, why = mode, t = computer.uptime() } end
        return
    end
    if t.to and t.to ~= modem.address then return end
    N.stats.rx = N.stats.rx + 1
    N.peers[from] = N.peers[from] or {}
    if t.aes ~= nil then N.peers[from].aes = t.aes == true end
    if dist > 0 or not N.peers[from].dist then N.peers[from].dist = dist end
    N.peers[from].seen = computer.uptime()
    N.peers[from].secure = (mode == "E")
    for _, fn in ipairs(N.listeners) do
        local ok, err = pcall(fn, from, t, dist, mode)
        if not ok then K.log("FEHLER", "netz: " .. tostring(err)) end
    end
end

function N.start()
    N.ready = false
    modem, data = nil, nil
    for addr in component.list("modem") do
        local p = component.proxy(addr)
        if not modem or (p.isWireless() and not modem.isWireless()) then modem = p end
    end
    for addr in component.list("data") do data = component.proxy(addr) break end
    N.modem, N.data = modem, data
    if not modem then N.reason = "keine Netzwerk-/Funkkarte" return false end
    N.aes = (data and data.encrypt) ~= nil
    N.port = tonumber(K.set.port) or 4711
    local stored = S.load(KEYFILE)
    if stored and stored.key and #stored.key == 64 then
        setKey(unhex(stored.key))
        N.isDefault = stored.default == true
    else
        N.setPassword("gts")
    end
    pcall(modem.open, N.port)
    if modem.isWireless() then pcall(modem.setStrength, 400) end
    N.ready = true
    N.reason = nil
    N.wireless = modem.isWireless()
    return true
end

K.on("modem_message", onMessage)
K.on("component_added", function(_, kind) if kind == "modem" or kind == "data" then N.start() end end)
K.on("component_removed", function(_, kind) if kind == "modem" or kind == "data" then N.start() end end)
return N
end
