-- GTS OS (OpenComputers) - DATEIEN: Ordner ansehen, Dateien lesen/bearbeiten
-- Systemordner (GTS OS, OpenOS) und die Schluessel-Dateien in /gts/data
-- brauchen den Admin-Code: zum Aendern - und /gts/data auch zum Lesen.
local K, G, UI, S = ...
local fs = require("filesystem")
local C = G.C
local E = K.lib("edit")(K, G, UI)
local A = { path = "/home", page = { page = 1 }, sel = nil, view = nil, ed = nil }
local MAXEDIT = 64 * 1024

local function join(a, b) return (a == "/" and "" or a) .. "/" .. b end
local function parent(p) return p:match("^(.*)/[^/]+$") or "/" end
local function norm(p) p = p:gsub("/+", "/") if #p > 1 then p = p:gsub("/$", "") end return p == "" and "/" or p end
local PROTECT = { "^/gts", "^/boot", "^/lib", "^/bin", "^/etc", "^/usr", "^/init%.lua$", "^/home/%.shrc$" }
local SECRET = { "^/gts/data" }
local function matches(list, p) for _, pat in ipairs(list) do if p:match(pat) then return true end end return false end
local function protected(p) return matches(PROTECT, norm(p)) end
local function secret(p) return matches(SECRET, norm(p)) end
-- Aktion nur mit Admin-Code (wenn noetig)
local function guarded(p, title, fn)
    if (protected(p) or secret(p)) and not K.isAdmin() then K.askAdmin(title or "Admin-Code (Systemdatei)", fn) else fn() end
end

local function entries(path)
    local out = {}
    local ok = pcall(function()
        for name in fs.list(path) do
            local dir = name:sub(-1) == "/"
            local n = dir and name:sub(1, -2) or name
            local full = join(path, n)
            out[#out + 1] = { name = n, dir = dir, path = full, size = dir and 0 or fs.size(full), t = fs.lastModified(full) }
        end
    end)
    table.sort(out, function(a, b) if a.dir ~= b.dir then return a.dir end return a.name:lower() < b.name:lower() end)
    return out, ok
end
local function dateText(ms)
    if not ms or ms < 1e11 then return "" end
    local y, mo, d, h, mi = K.localTime(ms)
    return string.format("%02d.%02d.%02d %02d:%02d", d, mo, y % 100, h, mi)
end

local function go(p)
    guarded(p, "Admin-Code (geschützter Ordner)", function()
        A.path, A.sel, A.page.page = norm(p), nil, 1
    end)
end
local function openFile(e, edit)
    guarded(e.path, "Admin-Code (Systemdatei)", function()
        if e.size > MAXEDIT then K.notify("Datei zu groß zum Anzeigen (" .. K.bytes(e.size) .. ")", "warn") return end
        local text = S.read(e.path) or ""
        local binary = text:find("[%z\1-\8\14-\31]") ~= nil
        if binary then K.notify("Binärdatei - Anzeige nicht möglich", "warn") return end
        A.view = e
        A.ed = E.new(text, { lua = e.name:match("%.lua$") ~= nil, readonly = not edit,
                              onSave = function() A.save() end })
    end)
end
function A.save()
    if not A.view or not A.ed or A.ed.ro then return end
    guarded(A.view.path, "Admin-Code (Systemdatei)", function()
        local ok, err = S.write(A.view.path, A.ed:text())
        if ok then
            pcall(fs.remove, A.view.path .. ".bak")
            A.ed.dirty = false
            K.notify("Gespeichert: " .. A.view.name, "ok")
            K.log("INFO", "Datei gespeichert " .. A.view.path)
        else K.notify("Fehler: " .. tostring(err), "bad") end
    end)
end
local function closeView()
    if A.ed and A.ed.dirty then
        UI.ask("Nicht gespeichert", "Änderungen an " .. A.view.name .. " verwerfen?", function() A.view, A.ed = nil, nil end, "VERWERFEN", "danger")
        return
    end
    A.view, A.ed = nil, nil
end

local function actions(e)
    local list = {
        { text = e.dir and "ÖFFNEN" or "ANSEHEN", style = "primary", onClick = function() if e.dir then go(e.path) else openFile(e, false) end end },
        { text = "BEARBEITEN", style = "secondary", skip = e.dir, onClick = function() openFile(e, true) end },
        { text = "UMBENENNEN", style = "subtle", onClick = function()
            guarded(e.path, nil, function()
                UI.prompt({ title = "Neuer Name", text = e.name, select = false, maxLen = 40,
                            validate = function(t) if t == "" or t:find("/") then return "Name ohne /" end if fs.exists(join(A.path, t)) then return "Gibt es schon" end end,
                            onOk = function(t) local ok, err = fs.rename(e.path, join(A.path, t)) if not ok then K.notify(tostring(err), "bad") end A.sel = nil end })
            end)
        end },
        { text = "LÖSCHEN", style = "subtle", confirm = "del" .. e.path, onClick = function()
            guarded(e.path, nil, function()
                if fs.remove(e.path) then K.notify(e.name .. " gelöscht", "ok") K.log("INFO", "gelöscht " .. e.path) A.sel = nil
                else K.notify("Löschen fehlgeschlagen", "bad") end
            end)
        end },
    }
    local out = {}
    for _, b in ipairs(list) do if not b.skip then out[#out + 1] = b end end
    return out
end

local function crumbs(x, y, w)
    local parts = {}
    for seg in A.path:gmatch("[^/]+") do parts[#parts + 1] = seg end
    local cx = UI.chip(x, y, "/", false, function() go("/") end) + 1
    local acc = ""
    for i, seg in ipairs(parts) do
        acc = acc .. "/" .. seg
        local p = acc
        if cx + G.len(seg) + 4 > x + w - 1 then G.text(cx, y, "…", C.muted) break end
        G.text(cx, y, "›", C.muted)
        cx = UI.chip(cx + 2, y, seg, i == #parts, function() go(p) end) + 1
    end
end

local function drawBrowser(x, y, w, h)
    local list, ok = entries(A.path)
    local wide = w >= 110
    local lw = wide and math.floor(w * 0.62) or w
    local proxy = fs.get(A.path)
    local used, total = 0, 0
    if proxy then pcall(function() used, total = proxy.spaceUsed(), proxy.spaceTotal() end) end
    local ix, iy, iw, ih = UI.card(x, y, lw, h, nil)
    crumbs(ix, iy, iw - 26)
    if total and total > 0 then
        G.right(ix + iw - 1, iy, K.bytes(used) .. " / " .. K.bytes(total), C.muted, C.card)
        G.bar(ix + iw - 10, iy + 1, 10, used / total, used / total > 0.9 and C.bad or C.accent, C.line)
    end
    UI.row({
        { text = "▲ HOCH", style = "subtle", disabled = A.path == "/", onClick = function() go(parent(A.path)) end },
        { text = "+ ORDNER", style = "subtle", onClick = function()
            guarded(A.path, nil, function()
                UI.prompt({ title = "Neuer Ordner", maxLen = 40, onOk = function(t) if t ~= "" then fs.makeDirectory(join(A.path, t)) end end })
            end)
        end },
        { text = "+ DATEI", style = "subtle", onClick = function()
            guarded(A.path, nil, function()
                UI.prompt({ title = "Neue Datei", text = "neu.txt", maxLen = 40, onOk = function(t)
                    if t == "" or fs.exists(join(A.path, t)) then return end
                    S.write(join(A.path, t), "")
                    pcall(fs.remove, join(A.path, t) .. ".bak")
                    openFile({ name = t, path = join(A.path, t), size = 0 }, true)
                end })
            end)
        end },
    }, ix, iy + 2)
    if not ok then G.text(ix, iy + 4, "Ordner nicht lesbar", C.bad, C.card) return end
    if #list == 0 then G.text(ix, iy + 4, "Leerer Ordner", C.muted, C.card) end
    local listH = ih - 4 - ((not wide and A.sel) and 2 or 0)
    UI.list(A.page, list, ix, iy + 4, iw, listH, 1, function(e, rx, ry, rw)
        local on = A.sel == e.path
        local b = on and C.raised or C.card
        if on then G.fill(rx - 1, ry, rw + 2, 1, C.raised) end
        G.text(rx, ry, e.dir and "▸" or "·", e.dir and C.accent or C.muted, b)
        local col = e.dir and C.text or (e.name:match("%.lua$") and C.info or C.dim)
        G.text(rx + 2, ry, G.fit(e.name .. (e.dir and "/" or ""), rw - 32), col, b)
        if (protected(e.path) or secret(e.path)) then G.text(rx + math.min(rw - 31, G.len(e.name) + 4), ry, "⚿", C.warn, b) end
        if not e.dir then G.right(rx + rw - 17, ry, K.bytes(e.size), C.muted, b) end
        G.right(rx + rw - 1, ry, dateText(e.t), C.muted, b)
        UI.region(rx - 1, ry, rw + 2, 1, function()
            if on then if e.dir then go(e.path) else openFile(e, false) end
            else A.sel = e.path end
        end)
    end)
    local sel
    for _, e in ipairs(list) do if e.path == A.sel then sel = e end end
    if wide then
        local dx, dy, dw, dh = UI.card(x + lw + 2, y, w - lw - 2, h, "AUSWAHL")
        if not sel then
            UI.para(dx, dy, dw, "Eintrag antippen zum Auswählen, nochmal antippen zum Öffnen. Mit ⚿ markierte Systemdateien brauchen den Admin-Code.", C.muted)
            return
        end
        G.text(dx, dy, G.fit(sel.name, dw), C.text, C.card)
        UI.kv(dx, dy + 2, dw, "Art", sel.dir and "Ordner" or (sel.name:match("%.(%w+)$") or "Datei"), nil, 12)
        if not sel.dir then UI.kv(dx, dy + 3, dw, "Größe", K.bytes(sel.size) .. " (" .. sel.size .. " B)", nil, 12) end
        UI.kv(dx, dy + 4, dw, "Geändert", dateText(sel.t), nil, 12)
        UI.kv(dx, dy + 5, dw, "Pfad", sel.path, C.dim, 12)
        if protected(sel.path) or secret(sel.path) then G.text(dx, dy + 6, "⚿ geschützt - Admin-Code nötig", C.warn, C.card) end
        local by = dy + 8
        for _, b in ipairs(actions(sel)) do
            b.x, b.y, b.w = dx, by, dw
            UI.button(b)
            by = by + 2
        end
    elseif sel then
        UI.row(actions(sel), ix, iy + ih - 1)
    end
end

local function drawViewer(x, y, w, h)
    local e, ed = A.view, A.ed
    local bx = UI.row({ { text = "◀ ZURÜCK", style = "subtle", onClick = closeView } }, x, y)
    G.text(bx + 1, y, G.fit(e.path, w - (bx - x) - 42), C.text)
    local btns = {}
    if ed.ro then
        btns[#btns + 1] = { text = "BEARBEITEN", style = "secondary", onClick = function()
            guarded(e.path, nil, function() ed.ro = false end)
        end }
    else
        btns[#btns + 1] = { text = ed.dirty and "SPEICHERN ●" or "GESPEICHERT", style = ed.dirty and "primary" or "subtle", onClick = A.save }
    end
    UI.buttonsRight(btns, y, x + w - 1)
    local info = #ed.lines .. (#ed.lines == 1 and " Zeile · " or " Zeilen · ") .. K.bytes(#ed:text()) .. (ed.ro and " · nur lesen" or (K.hasKeyboard and " · Strg+S speichert" or ""))
    G.right(x + w - 1, y + 1, info, C.muted)
    local eh = h - 2
    if not K.hasKeyboard and not ed.ro then eh = eh - 2 end
    ed:draw(x, y + 2, w, eh)
    if not K.hasKeyboard and not ed.ro then
        UI.row({
            { text = "+ ZEILE", style = "secondary", onClick = function() ed:appendLine() end },
            { text = "ZEILE LÖSCHEN", style = "subtle", onClick = function() ed:deleteLine() end },
        }, x, y + h - 1)
    end
end

function A.draw(x, y, w, h)
    local pad = (w < 100) and 1 or 2
    x, w = x + pad, w - pad * 2
    G.text(x, y + 1, "DATEIEN", C.text)
    G.text(x + 9, y + 1, "  " .. (A.view and A.view.name or A.path), C.muted)
    local top = y + 3
    if A.view then drawViewer(x, top, w, y + h - top - 1) else drawBrowser(x, top, w, y + h - top - 1) end
end
function A.key(char, code)
    if A.view and A.ed then
        if code == 1 then closeView() return end
        A.ed:key(char, code)
    elseif code == 14 then go(parent(A.path))
    end
end
function A.paste(t) if A.ed and A.view then A.ed:paste(t) end end
function A.scroll(dir) if A.ed and A.view then A.ed:scroll(-dir) end end
function A.enter(arg) if type(arg) == "string" then go(arg) end end
return A
