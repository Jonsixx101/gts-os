-- GTS OS (OpenComputers) - Einrichtung beim ersten Start
local K, G, UI, S = ...
local C = G.C
local A = { step = 1 }
local STEPS = 6

local function codeTwice(title, key, after)
    UI.keypad({ title = title, maxLen = 8, cancel = false, onOk = function(a)
        if #a < 4 then K.notify("Mindestens 4 Ziffern", "warn") return codeTwice(title, key, after) end
        UI.keypad({ title = "Nochmal: " .. title, maxLen = 8, cancel = false, onOk = function(b)
            if a ~= b then K.notify("Nicht gleich - nochmal", "warn") return codeTwice(title, key, after) end
            K.set[key] = K.hash(a)
            K.save()
            after()
        end })
    end })
end

function A.draw(x, y, w, h)
    G.clear(C.bg)
    K.stars(5)
    local cw = math.min(w - 4, 76)
    local ch = math.min(h - 2, 24)
    local cx = x + math.floor((w - cw) / 2)
    local cy = y + math.floor((h - ch) / 2)
    local ix, iy, iw, ih = UI.card(cx, cy, cw, ch, "EINRICHTUNG  ·  SCHRITT " .. A.step .. " / " .. STEPS)
    G.thinBar(ix, iy, iw, A.step / STEPS, C.accent, C.line, C.card)
    local ty = iy + 2
    local function title(t) G.text(ix, ty, t, C.text, C.card) ty = ty + 2 end
    local function text(t) ty = UI.para(ix, ty, iw, t, C.dim) + 1 end
    local by = iy + ih - 2
    local function next(label, fn)
        UI.button({ x = ix + iw - UI.btnW(label or "WEITER"), y = by, text = label or "WEITER", style = "primary",
                    onClick = fn or function() A.step = A.step + 1 end })
    end
    local function back()
        if A.step > 1 then UI.button({ x = ix, y = by, text = "ZURÜCK", style = "ghost", onClick = function() A.step = A.step - 1 end }) end
    end
    if A.step == 1 then
        G.big(ix, ty, "GTS", C.accent)
        G.text(ix + 14, ty + 1, "OS für OpenComputers", C.text, C.card)
        ty = ty + 4
        text("Willkommen! In ein paar Schritten ist alles eingerichtet: dein Name, Sperrcode, Admin-Code, Schwarm-Passwort und das Aussehen.")
        G.text(ix, ty, "Dein Spielername:", C.muted, C.card)
        UI.button({ x = ix + 19, y = ty, w = 24, text = K.set.owner ~= "" and K.set.owner or "antippen ...", style = "subtle", align = "left",
                    onClick = function() UI.prompt({ title = "Dein Spielername", text = K.set.owner, maxLen = 16, onOk = function(t) K.setting("owner", t) end }) end })
        next()
    elseif A.step == 2 then
        title("Sperrcode")
        text("Der Sperrcode schützt das OS, wenn du weg bist (Auto-Sperre nach " .. K.set.autoLock .. " min). Standard ist 3344 - nimm lieber einen eigenen.")
        G.text(ix, ty, K.set.codeHash and "✓ eigener Code gesetzt" or "Noch Standard: 3344", K.set.codeHash and C.accent or C.warn, C.card)
        UI.button({ x = ix, y = ty + 2, text = "CODE FESTLEGEN", style = "secondary", onClick = function() codeTwice("Sperrcode", "codeHash", function() end) end })
        back() next()
    elseif A.step == 3 then
        title("Admin-Code")
        text("Nur mit dem Admin-Code kommt man in die Shell, an Lua und an die Sicherheits-Einstellungen. Strg+Alt+C beendet GTS OS nicht. Wer ohne Code an den Rechner will, landet immer wieder im Sperrbildschirm.")
        G.text(ix, ty, K.set.adminHash and "✓ Admin-Code gesetzt" or "Noch kein Admin-Code", K.set.adminHash and C.accent or C.warn, C.card)
        UI.button({ x = ix, y = ty + 2, text = "ADMIN-CODE FESTLEGEN", style = "secondary", onClick = function() codeTwice("Admin-Code", "adminHash", function() end) end })
        back() next()
    elseif A.step == 4 then
        title("Schwarm-Passwort")
        text("Alle Drohnen, Robots und dieser Rechner funken verschlüsselt mit demselben Passwort. Es wird in jede Drohnen-EEPROM geschrieben.")
        local net = K.net
        if not net.ready then
            G.text(ix, ty, "Funk nicht bereit: " .. tostring(net.reason), C.bad, C.card)
            text("Du kannst das später in SYSTEM > EINSTELLUNGEN machen.")
        else
            G.text(ix, ty, net.isDefault and "Noch Standard (gts) - unsicher" or "✓ eigenes Passwort", net.isDefault and C.warn or C.accent, C.card)
            UI.button({ x = ix, y = ty + 2, text = "PASSWORT FESTLEGEN", style = "secondary", onClick = function()
                UI.prompt({ title = "Schwarm-Passwort", mask = true, maxLen = 32, validate = function(t) if #t < 4 then return "Mindestens 4 Zeichen" end end,
                            onOk = function(t) net.setPassword(t) end })
            end })
        end
        back() next()
    elseif A.step == 5 then
        title("Aussehen")
        G.text(ix, ty, "Thema", C.muted, C.card)
        local tx = ix + 10
        for _, id in ipairs(G.THEME_ORDER) do
            tx = UI.chip(tx, ty, G.THEMES[id].name, K.set.theme == id, function() K.setting("theme", id) G.applyTheme(K.set.theme, K.set.accent) end) + 1
        end
        ty = ty + 2
        G.text(ix, ty, "Akzent", C.muted, C.card)
        tx = ix + 10
        for i, id in ipairs(G.ACCENT_ORDER) do
            if tx + 10 > ix + iw then ty = ty + 2 tx = ix + 10 end
            tx = UI.chip(tx, ty, G.ACCENTS[id].name, K.set.accent == id, function() K.setting("accent", id) G.applyTheme(K.set.theme, K.set.accent) end) + 1
        end
        ty = ty + 2
        UI.button({ x = ix, y = ty, w = 16, text = "Beispiel", style = "primary" })
        UI.button({ x = ix + 17, y = ty, w = 16, text = "Knopf", style = "secondary" })
        G.bar(ix + 35, ty, iw - 35, 0.62, C.accent, C.line)
        back() next()
    else
        title("Fertig!")
        text("GTS OS ist eingerichtet. Als Nächstes: in DROHNEN > EINRICHTEN die erste Drohnen-EEPROM schreiben.")
        if not K.set.adminHash then G.text(ix, ty, "Hinweis: ohne Admin-Code schützt nur der Sperrcode die Shell.", C.warn, C.card) end
        back()
        next("LOS GEHT'S", function()
            K.setting("setupDone", true)
            K.locked = false
            K.lastInput = require("computer").uptime()
            K.open("home")
        end)
    end
end
return A
