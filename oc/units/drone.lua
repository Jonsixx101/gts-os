-- ======================================================================
-- GTS-Drohne (kommt per Funk vom GTS OS, laeuft im Lader)
-- ======================================================================
-- Position: relativ zum Startplatz (dort steht der Charger), mit
-- Navigation-Upgrade in Kartenkoordinaten nachgefuehrt.
-- Fliegt auf Reisehoehe (Start + cruise), dann waagerecht, dann runter.
-- Akku unter homeAt %: heim zum Charger, laden bis 95 %, Auftrag weiter.
-- Das GTS OS kann eine naehere freie Ladestation vorgeben (Befehl charge).
-- Aufklaerung (recon): Rundflug um die Basis, der Bewegungssensor meldet.
local ctx = ...
local VERSION = "1.1"
local cp = component or require("component")
local pc = computer or require("computer")
local function first(t) for a in cp.list(t) do return cp.proxy(a) end end
local dr = first("drone")
local nav = first("navigation")
local ms = first("motion_sensor")
local cl = first("chunkloader")
local mo = ctx.modem
local OS = ctx.os

local cfg = { cruise = 8, homeAt = 25, beat = 5, light = 0x3DDC84, sens = true, name = ctx.name ~= "" and ctx.name or nil, spot = false }
local pos = { x = 0, y = 0, z = 0 }      -- geplant (Ziel der letzten Bewegung)
local navHome
if nav then local x, y, z = nav.getPosition() if x then navHome = { x = x, y = y, z = z } end end
local task = { kind = "idle" }
local legs = {}                          -- Wegstrecke: Liste von Punkten
local leg                                -- { p, t0, best, bestT }
local status = "bereit"
local blocked = 0
local events = {}
local seenName = {}
local lastBeat = -99
local charging = false
local resume                             -- Auftrag nach dem Laden

local function energy() return pc.energy() / pc.maxEnergy() end
local osAes = ctx.osAes == true
local function send(t)
  pcall(mo.send, OS, ctx.port, ctx.pack(t, ctx.aes and osAes))
end
local function setStatus(s)
  status = s
  pcall(dr.setStatusText, (cfg.name or "GTS") .. "\n" .. s)
end
local function light(c) cfg.light = c pcall(dr.setLightColor, c) end
light(cfg.light)

local function refreshPos()
  if nav and navHome then
    local x, y, z = nav.getPosition()
    if x then pos = { x = x - navHome.x, y = y - navHome.y, z = z - navHome.z } return true end
  end
end

-- Weg zum Ziel planen: hoch auf Reisehoehe, waagerecht, runter
local function route(p, direct)
  legs = {}
  local cy = math.max(pos.y, p.y, cfg.cruise)
  if direct or (math.abs(p.x - pos.x) + math.abs(p.z - pos.z) <= 2) then
    legs[1] = { x = p.x, y = p.y, z = p.z }
  else
    if pos.y < cy then legs[#legs + 1] = { x = pos.x, y = cy, z = pos.z } end
    legs[#legs + 1] = { x = p.x, y = cy, z = p.z }
    if p.y ~= cy then legs[#legs + 1] = { x = p.x, y = p.y, z = p.z } end
  end
  leg = nil
end

local function stepMove()
  if not leg then
    local p = table.remove(legs, 1)
    if not p then return true end
    pcall(dr.move, p.x - pos.x, p.y - pos.y, p.z - pos.z)
    pos = { x = p.x, y = p.y, z = p.z }
    leg = { p = p, t0 = pc.uptime(), best = math.huge, bestT = pc.uptime() }
    return false
  end
  local off = dr.getOffset()
  if off < 0.6 then
    refreshPos()
    leg = nil
    blocked = 0
    return #legs == 0
  end
  if off < leg.best - 0.05 then leg.best, leg.bestT = off, pc.uptime() end
  if pc.uptime() - leg.bestT > 2.5 then
    -- haengt fest: ein Stueck hoch und neu versuchen
    blocked = blocked + 1
    if blocked > 6 then
      setStatus("blockiert")
      events[#events + 1] = { t = "EV", ev = "blocked", x = pos.x, y = pos.y, z = pos.z }
      legs = {}
      leg = nil
      return true, "blockiert"
    end
    pcall(dr.move, 0, 2, 0)
    pos.y = pos.y + 2
    local rest = { leg.p }
    for _, l in ipairs(legs) do rest[#rest + 1] = l end
    for _, l in ipairs(rest) do if l.y < pos.y and l ~= rest[#rest] then l.y = pos.y end end
    legs = rest
    leg = nil
  end
  return false
end

local function goTo(p, direct) route(p, direct) end

-- Auftraege -------------------------------------------------------------
local function startTask(t)
  task = t
  t.step = 1
  if t.kind == "goto" then goTo(t.p) setStatus("fliegt")
  elseif t.kind == "home" then goTo({ x = 0, y = 0, z = 0 }) setStatus("heim")
  elseif t.kind == "patrol" then t.i = 1 goTo(t.points[1]) setStatus("Patrouille")
  elseif t.kind == "recon" then t.i = t.i or 1 goTo(t.points[t.i]) setStatus("Aufklärung")
  elseif t.kind == "charge" then goTo(t.p or { x = 0, y = 0, z = 0 }) setStatus("zum Laden")
  elseif t.kind == "guard" then goTo(t.p) setStatus("Wache")
  elseif t.kind == "courier" then t.phase = "hin" goTo(t.from) setStatus("Kurier: holen")
  elseif t.kind == "stop" or t.kind == "idle" then legs = {} leg = nil pcall(dr.move, 0, 0, 0) setStatus("bereit") task = { kind = "idle" } end
end

local function tickTask()
  local e = energy()
  if not charging and e < cfg.homeAt / 100 and task.kind ~= "home" and task.kind ~= "charge" then
    resume = task
    -- stand sie irgendwo (geparkt/angekommen): nach dem Laden dorthin zurueck
    if task.kind == "idle" and math.abs(pos.x) + math.abs(pos.y) + math.abs(pos.z) > 2 then
      resume = { kind = "goto", p = { x = pos.x, y = pos.y, z = pos.z } }
    end
    task = { kind = "charge", p = cfg.spot }
    goTo(cfg.spot or { x = 0, y = 0, z = 0 })
    setStatus("Akku leer - laden")
  end
  if task.kind == "charge" then
    if #legs == 0 and not leg then
      charging = true
      setStatus("lädt " .. math.floor(e * 100) .. "%")
      if e >= 0.95 then
        charging = false
        local r = resume
        resume = nil
        if r and r.kind ~= "idle" and r.kind ~= "charge" then startTask(r) else task = { kind = "idle" } setStatus("bereit") end
      end
    else
      stepMove()
    end
    return
  end
  if task.kind == "idle" then return end
  local done, why = stepMove()
  if not done then return end
  if why then task = { kind = "idle" } return end
  if task.kind == "goto" then
    setStatus("angekommen")
    send({ t = "DONE", task = "goto", x = pos.x, y = pos.y, z = pos.z })
    task = { kind = "idle" }
  elseif task.kind == "home" then
    setStatus("zu Hause")
    send({ t = "DONE", task = "home" })
    task = { kind = "idle" }
  elseif task.kind == "patrol" or task.kind == "recon" then
    task.i = task.i % #task.points + 1
    if task.i == 1 and not task.loop then setStatus("Patrouille fertig") task = { kind = "idle" } return end
    goTo(task.points[task.i])
  elseif task.kind == "guard" then
    -- in der Luft stehen bleiben; der Bewegungssensor meldet
  elseif task.kind == "courier" then
    if task.phase == "hin" then
      local got = 0
      for s = 1, (dr.inventorySize and dr.inventorySize() or 0) do
        dr.select(s)
        if dr.suck(0) then got = got + 1 end
      end
      task.phase = "zurueck"
      setStatus("Kurier: bringen")
      goTo(task.to)
    else
      for s = 1, (dr.inventorySize and dr.inventorySize() or 0) do dr.select(s) dr.drop(0) end
      task.rounds = (task.rounds or 1) - 1
      if task.rounds > 0 then task.phase = "hin" goTo(task.from) setStatus("Kurier: holen")
      else send({ t = "DONE", task = "courier" }) setStatus("Kurier fertig") task = { kind = "idle" } end
    end
  end
end

-- Befehle -------------------------------------------------------------
local function handle(m)
  if m.aes ~= nil then osAes = m.aes == true end
  if m.t ~= "CMD" then return end
  local a = m.args or {}
  local ok, msg = true, nil
  if m.cmd == "goto" then startTask({ kind = "goto", p = { x = a.x, y = a.y, z = a.z } })
  elseif m.cmd == "home" then startTask({ kind = "home" })
  elseif m.cmd == "stop" then startTask({ kind = "stop" })
  elseif m.cmd == "patrol" then
    if type(a.points) == "table" and #a.points > 0 then startTask({ kind = "patrol", points = a.points, loop = a.loop ~= false })
    else ok, msg = false, "keine Punkte" end
  elseif m.cmd == "recon" then
    if type(a.points) == "table" and #a.points > 1 then startTask({ kind = "recon", points = a.points, i = tonumber(a.start) or 1, loop = true })
    else ok, msg = false, "keine Punkte" end
  elseif m.cmd == "charge" then
    if task.kind ~= "charge" then
      resume = task
      if task.kind == "idle" and math.abs(pos.x) + math.abs(pos.y) + math.abs(pos.z) > 2 then
        resume = { kind = "goto", p = { x = pos.x, y = pos.y, z = pos.z } }
      end
    end
    startTask({ kind = "charge", p = { x = a.x, y = a.y, z = a.z } })
  elseif m.cmd == "guard" then startTask({ kind = "guard", p = { x = a.x, y = a.y, z = a.z } })
  elseif m.cmd == "courier" then startTask({ kind = "courier", from = a.from, to = a.to, rounds = a.rounds or 1 })
  elseif m.cmd == "light" then light(tonumber(a.c) or 0xFFFFFF)
  elseif m.cmd == "name" then cfg.name = tostring(a.name or ""):sub(1, 16) setStatus(status)
  elseif m.cmd == "cfg" then for k, v in pairs(a) do if cfg[k] ~= nil then cfg[k] = v end end
  elseif m.cmd == "here" then pos = { x = 0, y = 0, z = 0 } refreshPos()
    if nav then local x, y, z = nav.getPosition() if x then navHome = { x = x, y = y, z = z } end end
  elseif m.cmd == "chunk" then if cl then ok = pcall(cl.setActive, a.on == true) else ok, msg = false, "kein Chunkloader" end
  elseif m.cmd == "restart" then send({ t = "ACK", seq = m.seq, ok = true }) error("Neustart", 0)
  elseif m.cmd == "ping" then pcall(pc.beep, 1200, 0.1)
  else ok, msg = false, "unbekannt: " .. tostring(m.cmd) end
  send({ t = "ACK", seq = m.seq, ok = ok, msg = msg })
  lastBeat = -99
end

local function beat()
  lastBeat = pc.uptime()
  local inv = 0
  if dr.inventorySize then for s = 1, dr.inventorySize() do inv = inv + (dr.count(s) or 0) end end
  send({ t = "UP", kind = "drone", v = VERSION, name = cfg.name, e = energy(), x = pos.x, y = pos.y, z = pos.z,
         task = task.kind, st = status, light = cfg.light, nav = nav ~= nil and navHome ~= nil, ms = ms ~= nil,
         cl = cl ~= nil, inv = inv, aes = ctx.aes, charging = charging })
end

setStatus("bereit")
if cl then pcall(cl.setActive, true) end
beat()
while true do
  local ev = table.pack(pc.pullSignal(0.2))
  if ev[1] == "modem_message" and ev[4] == ctx.port then
    local m = ctx.unpack(ev[6], ev[3])
    if m then handle(m) end
  elseif ev[1] == "motion" and cfg.sens then
    local name = ev[6] or "?"
    if not seenName[name] or pc.uptime() - seenName[name] > 10 then
      seenName[name] = pc.uptime()
      events[#events + 1] = { t = "EV", ev = "motion", name = name, x = math.floor(pos.x + ev[3] + 0.5),
                              y = math.floor(pos.y + ev[4] + 0.5), z = math.floor(pos.z + ev[5] + 0.5) }
    end
  end
  tickTask()
  while #events > 0 do send(table.remove(events, 1)) end
  if pc.uptime() - lastBeat > cfg.beat then beat() end
end
