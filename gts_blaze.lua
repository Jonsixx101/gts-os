-- ======================================================================
-- GTS BLAZE-JAEGER v1.0                    (CC: Tweaked, MC 1.21.1)
-- Eine Turtle jagt Blazes in einem Spawner-Raum und bringt die Blaze Rods
-- in eine (Ender-)Kiste. Als startup.lua auf die Turtle.
-- ======================================================================
-- AUFBAU
--   Turtle: Diamant-Schwert + Environment Detector (Advanced Peripherals)
--   Inventar: ein Kompass (einmal zum Einmessen), etwas Kohle zum Start.
--   Startplatz: auf dem REDSTONE-BLOCK, Blick in den Raum, die Kiste
--   (z.B. Ender Chest) direkt HINTER der Turtle.
--
-- WIE SIE ARBEITET
--   - Alle 2 s ein Scan mit dem Environment Detector (Radius 8, kostenlos).
--   - Sie faehrt auf kuerzestem Weg neben den naechsten Blaze und schlaegt
--     zu (vorn, oben oder unten). Was ein Turtle-Schwert toetet, landet
--     direkt im Inventar - kein Aufsaugen noetig. Sie zaehlt als Spieler,
--     darum fallen auch Blaze Rods. Liegt doch etwas herum, saugt sie es
--     beim Vorbeifahren auf.
--   - Sie faehrt nur im Raum (RAUM unten) und baut NIE etwas ab. Waende
--     und den Spawner merkt sie sich, wenn sie dagegen stoesst.
--   - Inventar voll -> zurueck auf den Redstone-Block, alles in die Kiste.
--     Ein paar Rods behaelt sie als Brennstoff und tankt sich selbst.
--   - Nach einem Neustart findet sie den Weg zurueck (Position wird bei
--     jedem Schritt gespeichert, der Redstone-Block bestaetigt die Basis).
--
-- WICHTIG: Ein Spawner spawnt nur, wenn ein Spieler im Umkreis von 16
-- Bloecken ist.
--
-- TASTEN: [H] Basis hier neu setzen   [R] Raum neu lernen   [Q] Ende
-- ======================================================================

local VERSION = "1.0"

local CONFIG = {
    -- Raum, gezaehlt ab dem Startplatz (Blick = vorn): so weit darf sie.
    ahead      = 7,     -- Bloecke nach vorn
    side       = 3,     -- Bloecke nach links und nach rechts
    height     = 2,     -- Hoehe (Startplatz = unterste Ebene)

    targets    = { "blaze" },   -- Mob-Namen (Teilwort, klein)
    scanRadius = 8,     -- bis 8 kostet der Scan nichts
    keepRods   = 8,     -- so viele Rods bleiben als Brennstoff an Bord
    unloadRods = 16,    -- alle 16 Rods (zusaetzlich zur Reserve) abladen
    unloadSlots = 12,   -- oder ab so vielen belegten Slots
    refuelBelow = 400,  -- unter diesem Tank wird nachgetankt
    refuelTo   = 2000,
    idleHome   = 30,    -- so viele Sek. ohne Blaze -> zur Basis, abladen

    -- Chat Box im Inventar (optional): wird nur kurz gegen den Detector
    -- getauscht - wenn gerade kein Blaze da ist oder nach dem Abladen.
    chatName   = "Lord",          -- Absender im Chat
    sayMin     = 600,   -- Sprueche: alle 10 Minuten einer
    sayMax     = 600,
    chatRange  = -1,    -- -1 = so weit die Chat Box darf
    stateFile  = "/.blaze_state",
}

local ROD = "minecraft:blaze_rod"
local FUEL = { ["minecraft:coal"] = true, ["minecraft:charcoal"] = true, ["minecraft:coal_block"] = true,
               ["minecraft:blaze_rod"] = true, ["minecraft:lava_bucket"] = true }
-- Werkzeuge bleiben an Bord (werden nie in die Kiste gelegt)
local KEEP = { ["minecraft:compass"] = true, ["advancedperipherals:chat_box"] = true,
               ["advancedperipherals:environment_detector"] = true }

-- ---------- Zustand ----------
local pos = { x = 0, y = 0, z = 0, f = 0 }   -- relativ zur Basis, f = 0: Blick wie beim Start
local S = {
    compass = nil,       -- Himmelsrichtung von f = 0 (0 = N, 1 = O, 2 = S, 3 = W)
    blocked = {},        -- gelernte Hindernisse "x,y,z" = true
    rods = 0,            -- Rods in die Kiste gebracht
    hits = 0,
}
local status, note, seen = "Start", "-", 0
local blazeCells = {}      -- Felder mit Blaze laut letztem Scan: nur dorthin wird geschlagen
local misses, missed      -- Selbstkontrolle der Richtung (siehe Ablauf)
local flags = {}          -- Wuensche der Tasten an die Jagd ([H], [R])

local DX = { [0] = 1, [1] = 0, [2] = -1, [3] = 0 }
local DZ = { [0] = 0, [1] = 1, [2] = 0, [3] = -1 }
local CV = { [0] = { 0, -1 }, [1] = { 1, 0 }, [2] = { 0, 1 }, [3] = { -1, 0 } }   -- N O S W in Welt-x/z
local COMPASS = { [0] = "N", [1] = "O", [2] = "S", [3] = "W" }

local function key(x, y, z) return x .. "," .. y .. "," .. z end

local function save()
    local h = fs.open(CONFIG.stateFile, "w")
    if not h then return end
    local list = {}
    for k in pairs(S.blocked) do list[#list + 1] = k end
    h.write(textutils.serialize({ pos = pos, compass = S.compass, blocked = list,
                                  rods = S.rods, hits = S.hits, dirHits = S.dirHits, dirSrc = S.dirSrc }))
    h.close()
end

local function load()
    if not fs.exists(CONFIG.stateFile) then return false end
    local h = fs.open(CONFIG.stateFile, "r")
    local t = h and textutils.unserialize(h.readAll() or "")
    if h then h.close() end
    if type(t) ~= "table" then return false end
    if type(t.pos) == "table" then
        for _, k in ipairs({ "x", "y", "z", "f" }) do
            if type(t.pos[k]) == "number" then pos[k] = t.pos[k] end
        end
    end
    S.compass = tonumber(t.compass)
    for _, k in ipairs(type(t.blocked) == "table" and t.blocked or {}) do S.blocked[k] = true end
    S.rods, S.hits = tonumber(t.rods) or 0, tonumber(t.hits) or 0
    S.dirHits, S.dirSrc = tonumber(t.dirHits) or 0, t.dirSrc
    return true
end

local function setStatus(text) status = text os.queueEvent("blaze_ui") end
local function setNote(text) note = tostring(text) os.queueEvent("blaze_ui") end

-- ---------- Raum ----------
local function inRoom(x, y, z)
    return x >= 0 and x <= CONFIG.ahead and z >= -CONFIG.side and z <= CONFIG.side
           and y >= 0 and y < CONFIG.height
end

-- ---------- Werkzeuge ----------
local detSide
for _, side in ipairs({ "left", "right" }) do
    if peripheral.getType(side) == "environment_detector" then detSide = side end
end

local function findSlot(name)
    for slot = 1, 16 do
        local it = turtle.getItemDetail(slot)
        if it and it.name == name then return slot end
    end
end

-- Legt ein Werkzeug aus dem Inventar kurz an die Detector-Seite, ruft
-- fn(seite) auf und legt den Detector wieder an. Nur im Stand benutzen.
local function withSwap(item, ptype, fn)
    local slot = findSlot(item)
    if not (slot and detSide) then return nil end
    local equip = (detSide == "left") and turtle.equipLeft or turtle.equipRight
    turtle.select(slot)
    if not equip() then turtle.select(1) return nil end
    local res
    for _ = 1, 10 do
        if peripheral.getType(detSide) == ptype then
            local ok, r = pcall(fn, detSide)
            if ok then res = r end
            break
        end
        os.sleep(0.1)
    end
    turtle.select(slot)               -- hier liegt jetzt der Detector
    equip()
    for _ = 1, 10 do
        if peripheral.getType(detSide) == "environment_detector" then break end
        os.sleep(0.1)
    end
    turtle.select(1)
    return res
end

-- Himmelsrichtung per Kompass.
local FACING = { north = 0, east = 1, south = 2, west = 3 }
local function readCompass()
    return withSwap("minecraft:compass", "compass", function(side)
        return FACING[tostring(peripheral.call(side, "getFacing")):lower()]
    end)
end

-- ---------- Chat Box: Sprueche und Meldungen ----------
local CHATBOX = "advancedperipherals:chat_box"
local SAYINGS = {
    -- aus der Freundesgruppe
    "Meddl Leude! Bin wida am Blazes Jaga",
    "Feierbaelle? do lach i",
    "De Blazes fliegen, da Lord ned. Gwinna duad drozdem da Lord",
    "Denn was braucht Nahrung um zu wachsen? Richtig, Wasser!",
    "Brot kann schimmeln, was koennt ihr?",
    "Ich fahr nicht gerne Motorrad, weil es cool ist, ich fahr gerne Motorrad, weil ich es gerne fahr. Basta. Abgesehen davon, fahr ich kein Motorrad.",
    "Haette Columbus Amerika nie entdeckt, waeren Indianer heute sowas wie Elfen.",
    "Ich bin eine sehr fette Turtle, aber auch eine sehr fitte Turtle.",
    "Die ham a riesige Bombe nei gschmasst!",
    "was zuggstn so",
    "Hagebuddne, Hagebuddne, Hagebuddne",
    "Hagebuddne",
    "Bekomme ich eigentlich Geld, wenn ich verrecke?",
    -- vom Lord selbst
    "Etzala geht's los, etzala wird gejagt.",
    "Des is fei a ganz schee hoisse Ecke do im Nether.",
    "Meddl! Wieder a Staebla fir die Kistn.",
    "Ich bin der Lord, und die Blazes ham etz a Problem.",
    "Etzala amol a Paus? Na, do kummt scho widder aner.",
    "Meddl Leude, die Kistn wird voll und voller.",
    "Des is mei Spawner und mei Raum, gell.",
    "Etzala werd gscheid aufgraeumt im Nether.",
    "Meddl! Der Lord hod Hunger auf Blaze Rods.",
    "Der Lord faehrt langsam, aber er kummt immer an.",
    "Wer den Redstone-Block klaut, kriegt Aerger mit dem Lord.",
    "Meddl! A Rod fir mich, a Rod fir die Kistn.",
    "Meddl Leude, Brennstoff mach i mir selber.",
    "Meddl! Wer des liest, is nah gnug am Spawner. Dankschee!",
    "So a Feierbaal, des kitzelt bloss.",
    "Der Lord zaehlt bis 64, dann geht's in die Kistn.",
    "Meddl Leude, heid laeufts wie gschmiert.",
}
local chatQueue, chatSince = {}, nil
local nextSay = os.clock() + math.random(CONFIG.sayMin, CONFIG.sayMax)
local sayBag = {}

local function queueChat(text)
    if #chatQueue >= 5 then return end
    chatQueue[#chatQueue + 1] = text
    chatSince = chatSince or os.clock()
end

-- Spruch faellig? (gemischt, keiner doppelt, bis alle 30 dran waren)
local function maybeSay()
    if os.clock() < nextSay then return end
    nextSay = os.clock() + math.random(CONFIG.sayMin, CONFIG.sayMax)
    if #sayBag == 0 then
        for i = 1, #SAYINGS do sayBag[i] = i end
        for i = #sayBag, 2, -1 do
            local j = math.random(i)
            sayBag[i], sayBag[j] = sayBag[j], sayBag[i]
        end
    end
    queueChat(SAYINGS[table.remove(sayBag)])
end

-- Alles Wartende in EINEM kurzen Tausch senden.
local function flushChat()
    if #chatQueue == 0 then return end
    if not findSlot(CHATBOX) then chatQueue, chatSince = {}, nil return end
    local list = chatQueue
    chatQueue, chatSince = {}, nil
    withSwap(CHATBOX, "chat_box", function(side)
        for i, text in ipairs(list) do
            if i > 1 then os.sleep(0.2) end         -- Abklingzeit der Chat Box
            peripheral.call(side, "sendMessage", text, CONFIG.chatName, "[]", nil, CONFIG.chatRange)
        end
        return true
    end)
end

-- ---------- Bewegung ----------
local MOVE   = { fwd = turtle.forward, up = turtle.up, down = turtle.down }
local DETECT = { fwd = turtle.detect, up = turtle.detectUp, down = turtle.detectDown }
local ATTACK = { fwd = turtle.attack, up = turtle.attackUp, down = turtle.attackDown }
local SUCK   = { fwd = turtle.suck, up = turtle.suckUp, down = turtle.suckDown }

local function face(f)
    local d = (f - pos.f) % 4
    if d == 1 then turtle.turnRight()
    elseif d == 2 then turtle.turnRight() turtle.turnRight()
    elseif d == 3 then turtle.turnLeft() end
    pos.f = f
    save()
end

local function target(dir)
    if dir == "up" then return pos.x, pos.y + 1, pos.z end
    if dir == "down" then return pos.x, pos.y - 1, pos.z end
    return pos.x + DX[pos.f], pos.y, pos.z + DZ[pos.f]
end

-- Saugt herumliegende Items ein - aber nur aus dem Raum, nie aus einer
-- Kiste (sonst holte sie sich die Rods aus der Ender-Chest zurueck).
local function pickUp(dir)
    local tx, ty, tz = target(dir)
    if inRoom(tx, ty, tz) and not S.blocked[key(tx, ty, tz)] then return SUCK[dir]() end
    return false
end

-- Schlaegt so lange zu, wie etwas getroffen wird. Rueckgabe: Treffer.
-- Nur auf Felder, auf denen der letzte Scan einen Blaze gesehen hat - so
-- trifft sie nie einen Spieler, der im Raum steht.
local function strike(dir)
    local tx, ty, tz = target(dir)
    if not blazeCells[key(tx, ty, tz)] then return 0 end
    -- Nach einem Treffer ist ein Mob eine halbe Sekunde unverwundbar; dann
    -- liefert attack() false. Darum kurz warten und nachschlagen.
    local n, misses = 0, 0
    for _ = 1, 20 do
        if ATTACK[dir]() then
            n, misses = n + 1, 0
        else
            misses = misses + 1
            if misses >= 3 then break end
            os.sleep(0.25)
        end
    end
    if n > 0 then
        S.hits = S.hits + n
        pickUp(dir)                                          -- falls doch etwas herumliegt
    end
    return n
end

-- Ein Schritt. Ein Mob im Weg wird geschlagen, ein Block nie abgebaut.
local function step(dir)
    local tx, ty, tz = target(dir)
    if not inRoom(tx, ty, tz) then return false, "Raum" end
    for _ = 1, 6 do
        if MOVE[dir]() then
            pos.x, pos.y, pos.z = tx, ty, tz
            save()
            return true
        end
        if turtle.getFuelLevel() == 0 then return false, "Tank leer" end
        if DETECT[dir]() then
            S.blocked[key(tx, ty, tz)] = true
            save()
            return false, "Block"
        end
        if strike(dir) == 0 then os.sleep(0.5) end   -- kein Blaze (z.B. ein Spieler): warten
    end
    return false, "versperrt"
end

-- Kuerzester Weg (Breitensuche im Raum) zu einem der Ziele.
-- goals: { ["x,y,z"] = info }. Rueckgabe: Liste der Felder, Ziel-Info.
local function findPath(goals)
    local start = key(pos.x, pos.y, pos.z)
    if goals[start] then return {}, goals[start] end
    local prev, queue, head = { [start] = false }, { { pos.x, pos.y, pos.z } }, 1
    while head <= #queue do
        local c = queue[head]
        head = head + 1
        for _, d in ipairs({ { 1, 0, 0 }, { -1, 0, 0 }, { 0, 0, 1 }, { 0, 0, -1 }, { 0, 1, 0 }, { 0, -1, 0 } }) do
            local x, y, z = c[1] + d[1], c[2] + d[2], c[3] + d[3]
            local k = key(x, y, z)
            if prev[k] == nil and inRoom(x, y, z) and not S.blocked[k] then
                prev[k] = key(c[1], c[2], c[3])
                if goals[k] then
                    local path, cur = {}, k
                    while cur ~= start do
                        local px, py, pz = cur:match("^(-?%d+),(-?%d+),(-?%d+)$")
                        table.insert(path, 1, { tonumber(px), tonumber(py), tonumber(pz) })
                        cur = prev[cur]
                    end
                    return path, goals[k]
                end
                queue[#queue + 1] = { x, y, z }
            end
        end
    end
    return nil
end

-- Faehrt zum Nachbarfeld (x, y, z).
local function stepTo(x, y, z)
    if y > pos.y then return step("up") end
    if y < pos.y then return step("down") end
    for f = 0, 3 do
        if pos.x + DX[f] == x and pos.z + DZ[f] == z then
            face(f)
            return step("fwd")
        end
    end
    return false
end

-- Faehrt hoechstens maxSteps Schritte auf dem Weg; unterwegs Schlaege nach
-- oben/unten/vorn, falls ein Blaze gerade dort ist.
local function follow(path, maxSteps)
    for i = 1, math.min(#path, maxSteps or #path) do
        local c = path[i]
        local ok = stepTo(c[1], c[2], c[3])
        if not ok then return false end
        pickUp("fwd")
    end
    return true
end

local function goHome()
    if pos.x == 0 and pos.y == 0 and pos.z == 0 then face(0) return true end
    setStatus("Zur Basis")
    for _ = 1, 20 do
        local path = findPath({ [key(0, 0, 0)] = true })
        if not path then
            S.blocked = {}                  -- verlernt: Raum neu lernen
            path = findPath({ [key(0, 0, 0)] = true })
            if not path then return false end
        end
        if follow(path) then break end
    end
    if not (pos.x == 0 and pos.y == 0 and pos.z == 0) then return false end
    face(0)
    return true
end

-- ---------- Inventar ----------
local function count(name)
    local n = 0
    for slot = 1, 16 do
        local it = turtle.getItemDetail(slot)
        if it and it.name == name then n = n + it.count end
    end
    return n
end

local function usedSlots()
    local n = 0
    for slot = 1, 16 do if turtle.getItemCount(slot) > 0 then n = n + 1 end end
    return n
end

local function refuel(target)
    local level = turtle.getFuelLevel()
    if level == "unlimited" then return end
    for slot = 1, 16 do
        if turtle.getFuelLevel() >= target then break end
        local it = turtle.getItemDetail(slot)
        if it and FUEL[it.name] then
            turtle.select(slot)
            while turtle.getFuelLevel() < target and turtle.getItemCount(slot) > 0 do
                if it.name == ROD and count(ROD) <= 2 then break end   -- nicht alles verbrennen
                if not turtle.refuel(1) then break end
            end
        end
    end
    turtle.select(1)
end

local function needUnload()
    return count(ROD) >= CONFIG.unloadRods + CONFIG.keepRods or usedSlots() >= CONFIG.unloadSlots
end

-- An der Basis: alles in die Kiste dahinter (Kompass und keepRods Rods bleiben).
local function unload()
    if not goHome() then return false, "Basis nicht erreichbar" end
    face(2)
    local keep = CONFIG.keepRods
    local moved, full = 0, false
    local stacksBefore = math.floor(S.rods / 64)
    for slot = 1, 16 do
        local it = turtle.getItemDetail(slot)
        if it and not KEEP[it.name] and not (FUEL[it.name] and it.name ~= ROD) then
            local give = it.count
            if it.name == ROD then
                local stay = math.min(keep, it.count)
                keep, give = keep - stay, it.count - stay
            end
            if give > 0 then
                turtle.select(slot)
                local before = turtle.getItemCount(slot)
                turtle.drop(give)
                local gone = before - turtle.getItemCount(slot)
                if it.name == ROD then S.rods = S.rods + gone end
                moved = moved + gone
                if gone < give then full = true break end
            end
        end
    end
    turtle.select(1)
    face(0)
    save()
    local stacks = math.floor(S.rods / 64) - stacksBefore
    if stacks > 0 then
        queueChat("Meddl! " .. (stacks == 1 and "1 Stack" or (stacks .. " Stacks")) .. " Blaze Rods eingelagert, insgesamt "
                  .. S.rods .. " Rods in der Kistn.")
    end
    if full then return false, "Kiste voll" end
    return true, moved
end

-- ---------- Blazes finden ----------
-- Versatz in Welt-Achsen -> Versatz relativ zur Turtle (vorn/rechts).
local function toRel(bx, bz)
    local f, r = CV[S.compass], CV[(S.compass + 1) % 4]
    -- Basis-Richtung f=0 + aktuelle Drehung spielt keine Rolle: pos ist relativ zur Basis
    return bx * f[1] + bz * f[2], bx * r[1] + bz * r[2]
end

local function isTarget(name)
    name = tostring(name):lower()
    for _, t in ipairs(CONFIG.targets) do
        if name:find(t, 1, true) then return true end
    end
    return false
end

-- Liste der Blazes: { x, y, z } = unterstes Feld (relativ zur Basis).
local function scan()
    if not detSide then return nil, "kein Environment Detector" end
    for _ = 1, 6 do
        local ok, list, err = pcall(peripheral.call, detSide, "scanEntities", CONFIG.scanRadius)
        if ok and type(list) == "table" then
            local out = {}
            blazeCells = {}
            for _, e in ipairs(list) do
                if type(e) == "table" and isTarget(e.name) and type(e.x) == "number" then
                    local bx, by, bz = math.floor(e.x), math.floor(e.y), math.floor(e.z)
                    local rx, rz = toRel(bx, bz)
                    local b = { x = pos.x + rx, y = pos.y + by, z = pos.z + rz }
                    out[#out + 1] = b
                    for dy = 0, 1 do blazeCells[key(b.x, b.y + dy, b.z)] = true end
                end
            end
            return out
        end
        os.sleep(0.5)                          -- Abklingzeit des Scanners
        err = ok and err or list
    end
    return nil, "Scan klappt nicht"
end

-- Felder, von denen aus ein Blaze getroffen wird (mit Schlagrichtung).
local function attackSpots(blazes)
    local goals = {}
    for _, b in ipairs(blazes) do
        for dy = 0, 1 do                        -- ein Blaze ist knapp 2 Bloecke hoch
            local y = b.y + dy
            for f = 0, 3 do
                local x, z = b.x - DX[f], b.z - DZ[f]
                goals[key(x, y, z)] = goals[key(x, y, z)] or { dir = "fwd", f = f }
            end
        end
        goals[key(b.x, b.y - 1, b.z)] = goals[key(b.x, b.y - 1, b.z)] or { dir = "up" }
        goals[key(b.x, b.y + 2, b.z)] = goals[key(b.x, b.y + 2, b.z)] or { dir = "down" }
    end
    return goals
end

-- ---------- Ablauf ----------
local lastSeen = os.clock()

-- Selbstkontrolle der Himmelsrichtung: Steht sie oft am richtigen Platz und
-- trifft trotzdem nichts, stimmt die Richtung wohl nicht (falsch eingegeben).
-- Mit Kompass wird neu gemessen, sonst die naechste Richtung probiert.
misses = 0
missed = function()
    misses = misses + 1
    if misses < 8 then return end
    misses = 0
    if (S.dirHits or 0) >= 3 then return end          -- mit dieser Richtung schon getroffen: passt
    if pos.x == 0 and pos.y == 0 and pos.z == 0 and findSlot("minecraft:compass") then
        local c = readCompass()
        if c then
            local fixed = (c - pos.f) % 4
            if fixed ~= S.compass then S.compass, S.dirHits = fixed, 0 setNote("Richtung per Kompass korrigiert") end
            save()
            return
        end
    end
    S.compass, S.dirHits, S.dirSrc = (S.compass + 1) % 4, 0, "probiert"
    setNote("Trifft nichts - probiere Richtung " .. COMPASS[S.compass])
    save()
end

local function hunt()
    -- Wuensche der Tasten
    if flags.home then
        flags.home = nil
        pos.x, pos.y, pos.z, pos.f = 0, 0, 0, 0
        save()
        setNote("Basis hier gesetzt")
    end
    if flags.learn then
        flags.learn = nil
        S.blocked = {}
        save()
        setNote("Raum wird neu gelernt")
    end

    if turtle.getFuelLevel() ~= "unlimited" and turtle.getFuelLevel() < CONFIG.refuelBelow then
        refuel(CONFIG.refuelTo)
        if turtle.getFuelLevel() < 50 then
            goHome()
            setStatus("Tank leer")
            setNote("Kohle oder Blaze Rods in die Turtle legen")
            os.sleep(5)
            return
        end
    end
    if needUnload() then
        setStatus("Ablegen")
        local ok, res = unload()
        if not ok then
            setStatus("Wartet")
            setNote(res .. " - in 30 s neuer Versuch")
            os.sleep(30)
            return
        end
        setNote(res .. " Items in die Kiste")
        maybeSay()
        flushChat()                            -- steht eh gerade an der Basis
    end

    local blazes, err = scan()
    if not blazes then
        setStatus("Kein Scan")
        setNote(err)
        os.sleep(2)
        return
    end
    seen = #blazes
    if #blazes == 0 then
        setStatus("Wartet auf Blazes")
        maybeSay()
        flushChat()                            -- kein Blaze da: kurzer Tausch kostet nichts
        pickUp("fwd")
        if os.clock() - lastSeen > CONFIG.idleHome and (pos.x ~= 0 or pos.y ~= 0 or pos.z ~= 0) then
            unload()
        end
        os.sleep(1)
        return
    end
    lastSeen = os.clock()
    -- Meldung wartet schon lange (Dauerbetrieb): kurz zwischendurch senden
    maybeSay()
    if chatSince and os.clock() - chatSince > 120 then flushChat() end
    setStatus("Jagt (" .. #blazes .. ")")
    local path, spot = findPath(attackSpots(blazes))
    if not path then
        S.blocked = {}                         -- vielleicht Altes gelernt: neu versuchen
        path, spot = findPath(attackSpots(blazes))
    end
    if not path then
        setNote("Blaze nicht erreichbar")
        missed()
        os.sleep(1)
        return
    end
    -- hoechstens 3 Schritte, dann neu scannen (Blazes fliegen weiter)
    follow(path, 3)
    if #path <= 3 and spot then
        if spot.dir == "fwd" then face(spot.f) end
        if strike(spot.dir) > 0 then
            misses, S.dirHits = 0, (S.dirHits or 0) + 1
        else
            missed()
        end
    else
        strike("up") strike("down")
    end
    save()
end

local function huntLoop()
    while true do
        local ok, err = pcall(hunt)
        if not ok then
            if err == "Terminated" then error(err, 0) end
            setNote("Fehler: " .. tostring(err))
            os.sleep(2)
        end
    end
end

-- ---------- Bildschirm ----------
local THEME = {
    [colors.white] = 0xF0F4EE, [colors.orange] = 0xFB923C, [colors.yellow] = 0xFACC15,
    [colors.lime] = 0xA3E635, [colors.gray] = 0x1F2621, [colors.lightGray] = 0x8D998F,
    [colors.brown] = 0x333D35, [colors.red] = 0xEF4444, [colors.black] = 0x0E1110,
}
local function applyTheme(on)
    if not (term.isColour and term.isColour() and term.setPaletteColour) then return end
    pcall(function()
        for c, v in pairs(THEME) do
            if on then term.setPaletteColour(c, v) else term.setPaletteColour(c, term.nativePaletteColour(c)) end
        end
    end)
end
local function put(x, y, text, fg, bg)
    term.setCursorPos(x, y)
    term.setTextColor(fg or colors.white)
    term.setBackgroundColor(bg or colors.black)
    term.write(text)
end

local function draw()
    local w, h = term.getSize()
    term.setBackgroundColor(colors.black)
    term.clear()
    put(1, 1, string.rep(" ", w), colors.white, colors.gray)
    put(1, 1, "\149", colors.orange, colors.gray)
    put(3, 1, "BLAZE-JAEGER", colors.white, colors.gray)
    put(w - #VERSION - 1, 1, "v" .. VERSION, colors.lightGray, colors.gray)
    local function row(y, label, text, color)
        if y > h - 2 then return end
        put(2, y, label, colors.lightGray)
        put(12, y, tostring(text):sub(1, w - 12), color or colors.white)
    end
    local fuel = turtle.getFuelLevel()
    row(3, "STATUS", status, status:find("Jagt") and colors.orange or colors.lime)
    row(4, "BLAZES", seen .. " in Reichweite")
    row(5, "ROD", count(ROD) .. " an Bord, " .. S.rods .. " in der Kiste", colors.yellow)
    row(6, "TREFFER", S.hits)
    row(7, "TANK", tostring(fuel), (fuel ~= "unlimited" and fuel < CONFIG.refuelBelow) and colors.red or colors.white)
    row(8, "POSITION", pos.x .. " " .. pos.y .. " " .. pos.z .. (S.compass and ("  Blick " .. COMPASS[(S.compass + pos.f) % 4]
        .. " (" .. tostring(S.dirSrc or "?") .. ")") or ""))
    row(9, "DETECTOR", (detSide and detSide or "FEHLT") .. (findSlot(CHATBOX) and "  + Chat Box" or ""),
        detSide and colors.lightGray or colors.red)
    row(10, "LETZTE", note, colors.lightGray)
    put(2, h, " H ", colors.lime, colors.brown) put(5, h, "BASIS ", colors.white, colors.brown)
    put(12, h, " R ", colors.lime, colors.brown) put(15, h, "RAUM ", colors.white, colors.brown)
    put(21, h, " Q ", colors.lime, colors.brown) put(24, h, "ENDE ", colors.white, colors.brown)
end

local function uiLoop()
    draw()
    local redraw = os.startTimer(1)
    while true do
        local ev, a, b, c = os.pullEvent()
        local ch = (ev == "char") and a:lower() or nil
        if ev == "mouse_click" then
            local _, h = term.getSize()
            if c == h then ch = (b < 11) and "h" or (b < 20) and "r" or "q" end
        end
        if ch == "q" then return
        elseif ch == "h" then flags.home = true
        elseif ch == "r" then flags.learn = true end
        if ev == "timer" and a == redraw then redraw = os.startTimer(1) end
        if ev == "blaze_ui" or ev == "char" or ev == "mouse_click" or ev == "timer" or ev == "term_resize" then draw() end
    end
end

-- ---------- Start ----------
applyTheme(true)
load()
if not detSide then
    setNote("Environment Detector anbauen!")
end
-- Himmelsrichtung: Kompass, sonst einmal fragen (nur an der Basis gueltig).
-- Ein Kompass im Inventar gewinnt immer (bei jedem Start an der Basis).
local f0 = (pos.x == 0 and pos.y == 0 and pos.z == 0 and pos.f == 0) and readCompass() or nil
if f0 then
    if f0 ~= S.compass then S.dirHits = 0 end
    S.compass, S.dirSrc = f0, "Kompass"
    save()
elseif S.compass == nil and pos.x == 0 and pos.y == 0 and pos.z == 0 then
    do
        term.setBackgroundColor(colors.black)
        term.clear()
        put(2, 2, "BLAZE-JAEGER einrichten", colors.orange)
        put(2, 4, "Kein Kompass im Inventar.", colors.white)
        put(2, 5, "In welche Richtung schaut die", colors.white)
        put(2, 6, "Turtle (F3)? n / o / s / w", colors.white)
        put(2, 8, "> ", colors.lime)
        local dirs = { n = 0, o = 1, e = 1, s = 2, w = 3 }
        local answer
        for _ = 1, 5 do
            answer = (read() or ""):lower():sub(1, 1)
            if dirs[answer] then break end
            put(2, 9, "Bitte n, o, s oder w eingeben.", colors.red)
            put(2, 8, ">                    ", colors.lime)
            term.setCursorPos(4, 8)
        end
        S.compass, S.dirSrc = dirs[answer] or 0, dirs[answer] and "Eingabe" or "geraten"
    end
    save()
end
if pos.x == 0 and pos.y == 0 and pos.z == 0 then
    local ok, below = turtle.inspectDown()
    if not (ok and type(below) == "table" and tostring(below.name):find("redstone_block", 1, true)) then
        setNote("Hinweis: kein Redstone-Block unter der Basis")
    end
end
refuel(CONFIG.refuelTo)
goHome()

parallel.waitForAny(uiLoop, huntLoop)

save()
applyTheme(false)
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)
print("Blaze-Jaeger beendet. Neustart: Strg+R")
