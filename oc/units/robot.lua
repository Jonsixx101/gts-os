-- ======================================================================
-- GTS-Robot (kommt per Funk vom GTS OS, laeuft im Lader)
-- ======================================================================
-- Position relativ zum Startplatz: x = nach vorn (Blick beim Start),
-- z = nach rechts, y = hoch. Blick f: 0 = +x, 1 = +z, 2 = -x, 3 = -z.
-- Zu Hause steht der Robot auf einer Kiste (Abladen nach unten) und neben
-- einem Charger.
local ctx = ...
local VERSION = "1.1"
local cp = component or require("component")
local pc = computer or require("computer")
local function first(t) for a in cp.list(t) do return cp.proxy(a) end end
local rb = first("robot")
local geo = first("geolyzer")
local mo = ctx.modem
local OS = ctx.os
local DOWN, UP, BACK, FRONT = 0, 1, 2, 3
local DX = { [0] = 1, [1] = 0, [2] = -1, [3] = 0 }
local DZ = { [0] = 0, [1] = 1, [2] = 0, [3] = -1 }

local cfg = { beat = 5, homeAt = 20, name = ctx.name ~= "" and ctx.name or nil, light = 0x4C9AFF }
local pos = { x = 0, y = 0, z = 0, f = 0 }
local task = { kind = "idle" }
local status = "bereit"
local lastBeat = -99
local osAes = ctx.osAes == true
local mined = 0
local plan = {}          -- Schritte des Auftrags (Koroutine)
local worker

local function energy() return pc.energy() / pc.maxEnergy() end
local function send(t) pcall(mo.send, OS, ctx.port, ctx.pack(t, ctx.aes and osAes)) end
local function setStatus(s) status = s end
pcall(rb.setLightColor, cfg.light)

local function turnTo(f)
  while pos.f ~= f do
    if (f - pos.f) % 4 == 1 then rb.turn(true) pos.f = (pos.f + 1) % 4
    else rb.turn(false) pos.f = (pos.f + 3) % 4 end
  end
end
local function yield() coroutine.yield() end
-- ein Feld in Richtung (dir = "f" vorn, "u" hoch, "d" runter); dig = abbauen erlaubt
local function step(dir, dig)
  local side = (dir == "u") and UP or (dir == "d" and DOWN or FRONT)
  for _ = 1, 4 do
    if rb.move(side) then
      if dir == "u" then pos.y = pos.y + 1 elseif dir == "d" then pos.y = pos.y - 1
      else pos.x = pos.x + DX[pos.f] pos.z = pos.z + DZ[pos.f] end
      return true
    end
    if dig and rb.detect(side) then
      if rb.swing(side) then mined = mined + 1 end
    else
      yield()
    end
  end
  return false
end
local function moveAxis(axis, target, dig)
  while pos[axis] ~= target do
    if axis == "y" then
      if not step(pos.y < target and "u" or "d", dig) then return false end
    else
      local d = target - pos[axis]
      local f = (axis == "x") and (d > 0 and 0 or 2) or (d > 0 and 1 or 3)
      turnTo(f)
      if not step("f", dig) then return false end
    end
    yield()
  end
  return true
end
-- Weg: erst y hoch (ueber Hindernisse), dann x, z, dann y
local function goTo(p, dig)
  for _ = 1, 6 do
    local ok = true
    if p.y > pos.y then ok = moveAxis("y", p.y, dig) end
    ok = ok and moveAxis("x", p.x, dig) and moveAxis("z", p.z, dig) and moveAxis("y", p.y, dig)
    if ok then return true end
    -- Hindernis: eine Ebene hoeher versuchen
    if not step("u", false) then break end
  end
  return pos.x == p.x and pos.y == p.y and pos.z == p.z
end
local function invFull()
  local n = rb.inventorySize()
  return n > 0 and rb.count(n) > 0
end
local function unload()
  for s = 1, rb.inventorySize() do
    if rb.count(s) > 0 then rb.select(s) rb.drop(DOWN) end
  end
  rb.select(1)
end
local function goHome()
  goTo({ x = pos.x, y = 0, z = pos.z }, false)
  local ok = goTo({ x = 0, y = 0, z = 0 }, false)
  turnTo(0)
  return ok
end

-- Abbauen: Flaeche w (nach vorn) x l (nach rechts), d Ebenen nach unten.
-- Beginnt im Feld VOR dem Robot (sein eigenes Feld und die Kiste darunter
-- bleiben heil), auf seiner Hoehe.
local function digArea(a)
  local w, l, d = math.max(1, a.w or 3), math.max(1, a.l or 3), math.max(1, a.d or 1)
  local sx, sy, sz = pos.x + 1, pos.y, pos.z
  for layer = 0, d - 1 do
    for row = 0, l - 1 do
      for col = 0, w - 1 do
        local cx = (row % 2 == 0) and col or (w - 1 - col)
        local target = { x = sx + cx, y = sy - layer, z = sz + row }
        if not goTo(target, true) then setStatus("komme nicht weiter") return false end
        if invFull() or energy() < cfg.homeAt / 100 then
          local back = { x = pos.x, y = pos.y, z = pos.z }
          setStatus("leeren/laden")
          goHome()
          unload()
          while energy() < 0.9 do yield() end
          goTo({ x = back.x, y = 0, z = back.z }, false)
          goTo(back, true)
          setStatus("baut ab")
        end
      end
    end
    send({ t = "EV", ev = "progress", layer = layer + 1, of = d, mined = mined })
  end
  return true
end

local function scan(a)
  if not geo then return false, "kein Geolyzer" end
  local r = math.min(4, a.r or 2)
  local hits = {}
  for dx = -r, r do
    for dz = -r, r do
      local ok, col = pcall(geo.scan, dx, dz)
      if ok and type(col) == "table" then
        for i, v in ipairs(col) do
          if v and v >= 2.5 and v < 50 then hits[#hits + 1] = { x = pos.x + dx, y = pos.y + i - 33, z = pos.z + dz, h = math.floor(v * 10) / 10 } end
        end
      end
      yield()
    end
  end
  table.sort(hits, function(p, q) return p.h > q.h end)
  while #hits > 24 do table.remove(hits) end
  send({ t = "EV", ev = "scan", hits = hits })
  return true
end

local function startTask(kind, a)
  task = { kind = kind, a = a }
  worker = coroutine.create(function()
    if kind == "goto" then setStatus("faehrt") local ok = goTo({ x = a.x, y = a.y, z = a.z }, a.dig == true) setStatus(ok and "angekommen" or "blockiert")
    elseif kind == "home" then setStatus("heim") goHome() setStatus("zu Hause")
    elseif kind == "dig" then setStatus("baut ab") local ok = digArea(a) goHome() unload() setStatus(ok and "fertig" or status)
    elseif kind == "unload" then goHome() unload() setStatus("abgeladen")
    elseif kind == "scan" then setStatus("scannt") local ok, err = scan(a) setStatus(ok and "Scan fertig" or err)
    end
    send({ t = "DONE", task = kind, mined = mined })
  end)
end

local function handle(m)
  if m.aes ~= nil then osAes = m.aes == true end
  if m.t ~= "CMD" then return end
  local a = m.args or {}
  local ok, msg = true, nil
  if m.cmd == "goto" or m.cmd == "home" or m.cmd == "dig" or m.cmd == "unload" or m.cmd == "scan" then startTask(m.cmd, a)
  elseif m.cmd == "stop" then worker = nil task = { kind = "idle" } setStatus("gestoppt")
  elseif m.cmd == "light" then cfg.light = tonumber(a.c) or 0xFFFFFF pcall(rb.setLightColor, cfg.light)
  elseif m.cmd == "name" then cfg.name = tostring(a.name or ""):sub(1, 16)
  elseif m.cmd == "here" then pos = { x = 0, y = 0, z = 0, f = 0 }
  elseif m.cmd == "cfg" then for k, v in pairs(a) do if cfg[k] ~= nil then cfg[k] = v end end
  elseif m.cmd == "restart" then send({ t = "ACK", seq = m.seq, ok = true }) error("Neustart", 0)
  elseif m.cmd == "ping" then pcall(pc.beep, 1000, 0.1)
  else ok, msg = false, "unbekannt: " .. tostring(m.cmd) end
  send({ t = "ACK", seq = m.seq, ok = ok, msg = msg })
  lastBeat = -99
end

local function beat()
  lastBeat = pc.uptime()
  local used = 0
  for s = 1, rb.inventorySize() do if rb.count(s) > 0 then used = used + 1 end end
  local dur = rb.durability and select(1, rb.durability()) or nil
  send({ t = "UP", kind = "robot", v = VERSION, name = cfg.name, e = energy(), x = pos.x, y = pos.y, z = pos.z, f = pos.f,
         task = task.kind, st = status, light = cfg.light, inv = used, invMax = rb.inventorySize(), tool = dur,
         geo = geo ~= nil, mined = mined, aes = ctx.aes })
end

beat()
while true do
  local ev = table.pack(pc.pullSignal(worker and 0 or 0.25))
  if ev[1] == "modem_message" and ev[4] == ctx.port then
    local m = ctx.unpack(ev[6], ev[3])
    if m then handle(m) end
  end
  if worker then
    local ok, err = coroutine.resume(worker)
    if not ok then setStatus("Fehler: " .. tostring(err)) worker = nil task = { kind = "idle" }
    elseif coroutine.status(worker) == "dead" then worker = nil task = { kind = "idle" } lastBeat = -99 end
  end
  if pc.uptime() - lastBeat > cfg.beat then beat() end
end
