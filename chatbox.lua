-- ======================================================================
-- CHATBOX - Nachrichten unter eigenem Namen in den Minecraft-Chat
-- (CC: Tweaked + Advanced Peripherals Chat Box)          by Jonsi
-- In /scripts ablegen, dann erscheint es in GTS OS unter LUA APPS.
-- Ablauf: Name eingeben, Nachricht eingeben, abschicken - wieder von vorn.
-- Name leer lassen + ENTER = beenden.
-- ======================================================================

local MAX_TRIES = 6        -- Versuche, falls die Chat Box gerade abkuehlt
-- Klammern um den Namen (Advanced Peripherals: genau 2 Zeichen, Standard "[]").
-- Im Chat steht dann "<Name> Text" - wie bei einem normalen Spieler.
local BRACKETS = "<>"
local history = {}         -- zuletzt benutzte Namen (Pfeil hoch beim Eingeben)

local function color(c)
    if term.isColor() then term.setTextColor(c) end
end

local function header()
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
    color(colors.lime)
    print("CHATBOX")
    color(colors.lightGray)
    print("Name leer lassen + ENTER = beenden")
    print()
end

-- Chat Box suchen: direkt am Computer oder am Kabel (Wired Modem).
local function findBox()
    return peripheral.find("chat_box")
end

-- Nachricht abschicken. Die Chat Box hat eine kurze Abkuehlzeit, dann
-- kommt "nil, Fehlertext" zurueck - kurz warten und nochmal versuchen.
local function send(box, name, text)
    local lastErr
    for _ = 1, MAX_TRIES do
        local ok, res, err
        if box.sendMessageToPlayer then       -- Advanced Peripherals 0.7
            ok, res, err = pcall(box.sendMessage, text, name, BRACKETS)
        else                                  -- 0.8: Optionen als Tabelle
            ok, res, err = pcall(box.sendMessage, text, { prefix = name, brackets = BRACKETS })
        end
        if ok and res then return true end
        lastErr = ok and err or res
        sleep(0.5)
    end
    return false, tostring(lastErr or "unbekannter Fehler")
end

local function ask(label, hist)
    color(colors.white)
    write(label)
    color(colors.yellow)
    local s = read(nil, hist)
    color(colors.white)
    return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

header()
local box = findBox()
if not box then
    color(colors.red)
    print("Keine Chat Box gefunden.")
    color(colors.lightGray)
    print("Stell sie direkt an den Computer oder")
    print("haeng sie per Wired Modem ans Kabel.")
    color(colors.white)
    return
end

while true do
    local name = ask("Name:      ", history)
    if name == "" then break end
    if history[#history] ~= name then history[#history + 1] = name end

    local text = ask("Nachricht: ")
    if text == "" then
        color(colors.lightGray)
        print("(nichts gesendet)")
    else
        box = findBox() or box    -- falls die Box zwischendurch umgestellt wurde
        local ok, err = send(box, name, text)
        if ok then
            color(colors.lime)
            print("Gesendet: <" .. name .. "> " .. text)
        else
            color(colors.red)
            print("Nicht gesendet: " .. err)
        end
    end
    print()
end

color(colors.lightGray)
print("Tschuess!")
color(colors.white)
