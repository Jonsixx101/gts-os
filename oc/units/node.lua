-- ======================================================================
-- GTS-Knoten (kommt per Funk/Kabel vom GTS OS, laeuft im Lader)
-- ======================================================================
-- Ein Knoten ist ein Rechner ohne Bildschirm mit GTS-EEPROM: er meldet
-- seine Komponenten (Tueren, Reaktoren, ME-Netz ...), fuehrt Aufrufe des
-- GTS OS aus, leitet Ereignisse weiter und haelt Waechter-Regeln auch
-- dann ein, wenn das GTS OS gerade aus ist.
-- Vor diesem Text setzt das GTS OS ops.lua (O) und crypto.lua (Cr).
local ctx = ...
local VERSION = "1.1"
local cp = component or require("component")
local pc = computer or require("computer")
local mo, da, OS = ctx.modem, ctx.data, ctx.os
local cfg = { beat = 5, name = ctx.name ~= "" and ctx.name or nil }

-- grosse Rahmen in Lua siegeln (Data Card: zu teuer fuer den Puffer)
ctx.h = function(s)
  if #s <= 256 then
    local ok, r = pcall(da.sha256, s)
    if ok and type(r) == "string" and #r == 32 then return r end
  end
  return Cr.luaSha256(s)
end

local osAes = ctx.osAes == true
local function send(t) pcall(mo.send, OS, ctx.port, ctx.pack(t, ctx.aes and osAes)) end
-- grosse Antworten in Teilen (das GTS OS setzt sie zusammen)
local fid = 0
local function sendBig(t)
  local s = ctx.ser(t)
  if #s <= 3000 then send(t) return end
  fid = fid + 1
  local n = math.ceil(#s / 3000)
  for i = 1, n do send({ t = "FR", id = fid, n = i, of = n, d = s:sub((i - 1) * 3000 + 1, i * 3000) }) end
end

-- Komponenten -------------------------------------------------------------
local cv, sentCv = 1, 0
local function comps()
  local t = {}
  for a, ty in cp.list() do t[a] = ty end
  return t
end
local function first(t) for a in cp.list(t) do return cp.proxy(a) end end

-- Internet fuer das GTS OS (z.B. KI, Updates), nur wenn hier eine Internet Card steckt
local queue = {}
local function http(p)
  local inet = first("internet")
  if not inet then error("keine Internet Card am Knoten", 0) end
  local h, e = inet.request(p[1], p[2], p[3], p[4])
  if not h then error(tostring(e), 0) end
  local dl = pc.uptime() + 60
  while true do
    local ok, done = pcall(h.finishConnect)
    if not ok then
      local okr, code = pcall(h.response)
      pcall(h.close)
      if okr and tonumber(code) then return { code = tonumber(code), body = "" } end
      error(tostring(done), 0)
    end
    if done then break end
    if pc.uptime() > dl then pcall(h.close) error("Zeitüberschreitung", 0) end
    local ev = table.pack(pc.pullSignal(0.1))
    if ev[1] then queue[#queue + 1] = ev end
  end
  local code = h.response()
  if code and code >= 400 then pcall(h.close) return { code = code, body = "" } end
  local parts = {}
  while true do
    local ok, chunk = pcall(h.read, 8192)
    if not ok or chunk == nil then break end
    if chunk == "" then
      local ev = table.pack(pc.pullSignal(0.05))
      if ev[1] then queue[#queue + 1] = ev end
    else parts[#parts + 1] = chunk end
    if pc.uptime() > dl then break end
  end
  pcall(h.close)
  return { code = code or 200, body = table.concat(parts) }
end

local function calls(list)
  local out = {}
  for i, c in ipairs(list or {}) do
    if c.m == "__http" then
      local ok, r = pcall(http, c.p or {})
      out[i] = { ok, r }
    else
      out[i] = O.call(c)
    end
  end
  return out
end

-- Ereignisse der eigenen Komponenten weiterleiten (Leser, Melder, Redstone ...)
local SKIP = { modem_message = true, key_down = true, key_up = true, touch = true, drag = true, drop = true, scroll = true,
               clipboard = true, screen_resized = true, interrupted = true, component_available = true,
               component_unavailable = true }
local evq, evSec, evN = {}, 0, 0
local function forward(ev)
  local now = math.floor(pc.uptime())
  if now ~= evSec then evSec, evN = now, 0 end
  evN = evN + 1
  if evN > 12 then return end                 -- hoechstens 12 je Sekunde
  local a = {}
  for i = 2, math.min(ev.n, 9) do
    local v = ev[i]
    local tv = type(v)
    if tv == "string" or tv == "number" or tv == "boolean" then a[i - 1] = v end
  end
  evq[#evq + 1] = { t = "EV", ev = "sig", s = ev[1], a = a }
end

local function beat(full)
  local t = { t = "UP", kind = "node", v = VERSION, name = cfg.name, e = pc.energy() / pc.maxEnergy(), mem = pc.freeMemory(),
              tot = pc.totalMemory(), cv = cv, rules = #O.rules, aes = ctx.aes, inet = first("internet") ~= nil }
  if full or sentCv ~= cv then t.comps = comps() sentCv = cv end
  sendBig(t)
end

local frag = {}
local function handle(m)
  if m.aes ~= nil then osAes = m.aes == true end
  if m.t == "FR" then
    local f = frag[m.id] or { n = 0, t = pc.uptime() }
    frag[m.id] = f
    if not f[m.n] then f[m.n] = m.d f.n = f.n + 1 end
    if f.n < m.of then return end
    frag[m.id] = nil
    local fn = load("return " .. table.concat(f, "", 1, m.of), "=fr", "t", {})
    local ok, inner = pcall(fn or error)
    if ok and type(inner) == "table" and inner.t ~= "FR" then return handle(inner) end
    return
  end
  if m.t == "CALL" then
    sendBig({ t = "RES", q = m.q, r = calls(m.c) })
    return
  end
  if m.t ~= "CMD" then return end
  local a = m.args or {}
  local ok, msg = true, nil
  if m.cmd == "comps" then sentCv = 0
  elseif m.cmd == "rules" then msg = O.setRules(a.list) .. " Regeln"
  elseif m.cmd == "cfg" then for k, v in pairs(a) do if cfg[k] ~= nil then cfg[k] = v end end
  elseif m.cmd == "name" then cfg.name = tostring(a.name or ""):sub(1, 16)
  elseif m.cmd == "ping" then pcall(pc.beep, 1200, 0.1)
  elseif m.cmd == "restart" then send({ t = "ACK", seq = m.seq, ok = true }) error("Neustart", 0)
  else ok, msg = false, "unbekannt: " .. tostring(m.cmd) end
  send({ t = "ACK", seq = m.seq, ok = ok, msg = msg })
end

local function emit(id, v, why, done)
  evq[#evq + 1] = { t = "EV", ev = "rule", id = id, v = v, why = why, done = done }
end

ctx.say("GTS-Knoten " .. (cfg.name or ""))
local lastBeat = -99
beat(true)
lastBeat = pc.uptime()
while true do
  local ev = table.remove(queue, 1) or table.pack(pc.pullSignal(0.25))
  local name = ev[1]
  if name == "modem_message" then
    if ev[4] == ctx.port then
      local m = ctx.unpack(ev[6], ev[3])
      if m then OS = ev[3] handle(m) end
    end
  elseif name == "component_added" or name == "component_removed" then
    cv = cv + 1
  elseif name and not SKIP[name] then
    forward(ev)
  end
  O.tick(pc.uptime(), emit)
  while #evq > 0 do send(table.remove(evq, 1)) end
  if pc.uptime() - lastBeat > cfg.beat or sentCv ~= cv then lastBeat = pc.uptime() beat(false) end
end
