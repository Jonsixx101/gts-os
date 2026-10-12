-- GTS OS (OpenComputers) - NOTIZEN: Merkzettel mit Editor
local K, G, UI, S = ...
local fs = require("filesystem")
local C = G.C
local E = K.lib("edit")(K, G, UI)
local DIR = K.ROOT .. "/data/notizen"
local IDX = K.ROOT .. "/data/notizen.db"
local A = { page = { page = 1 }, open = nil, ed = nil, query = nil }
local db = S.load(IDX, { list = {}, next = 1 })
local function save() S.save(IDX, db) end

local function file(id) return DIR .. "/" .. id .. ".txt" end
local function find(id) for i, n in ipairs(db.list) do if n.id == id then return n, i end end end
local function titleOf(text)
    for l in (text .. "\n"):gmatch("(.-)\n") do
        local t = l:gsub("^%s+", ""):gsub("^#+%s*", "")
        if t ~= "" then return t end
    end
    return "Leere Notiz"
end
local function dateText(ms)
    if not ms then return "" end
    local y, mo, d, h, mi = K.localTime(ms)
    local ny, nmo, nd = K.localTime()
    if y == ny and mo == nmo and d == nd then return string.format("heute %02d:%02d", h, mi) end
    return string.format("%02d.%02d.%d", d, mo, y)
end

local function store()
    if not A.open or not A.ed then return end
    local n = find(A.open)
    if not n then return end
    if A.ed.dirty then
        local text = A.ed:text()
        S.write(file(n.id), text)
        n.title = titleOf(text)
        n.preview = (text:match("\n%s*([^\n]+)") or ""):sub(1, 120)
        n.t = K.realMs()
        n.size = #text
        save()
        A.ed.dirty = false
    end
end
local function openNote(id)
    store()
    A.open = id
    A.ed = E.new(S.read(file(id)) or "", { numbers = false, onSave = function() store() K.notify("Gespeichert", "ok") end })
end
local function newNote(text)
    local id = db.next
    db.next = db.next + 1
    text = text or ""
    if not fs.exists(DIR) then fs.makeDirectory(DIR) end
    S.write(file(id), text)
    table.insert(db.list, 1, { id = id, title = titleOf(text), t = K.realMs(), size = #text, preview = "" })
    save()
    openNote(id)
    if not K.hasKeyboard and text == "" then A.ed:editLine(1) end
end
local function remove(id)
    local _, i = find(id)
    if i then table.remove(db.list, i) end
    fs.remove(file(id))
    save()
    if A.open == id then A.open, A.ed = nil, nil end
end

function A.leave() store() end
function A.unload() store() end
function A.enter(arg)
    if type(arg) == "table" and arg.new then newNote(arg.text) end
end

local function sorted()
    local out = {}
    for _, n in ipairs(db.list) do
        if not A.query or (n.title .. " " .. (n.preview or "")):lower():find(A.query:lower(), 1, true) then out[#out + 1] = n end
    end
    table.sort(out, function(a, b)
        if (a.pin and 1 or 0) ~= (b.pin and 1 or 0) then return a.pin == true end
        return (a.t or 0) > (b.t or 0)
    end)
    return out
end

local function drawList(x, y, w, h)
    local list = sorted()
    local ix, iy, iw, ih = UI.card(x, y, w, h, A.query and ("SUCHE: " .. A.query) or "ALLE NOTIZEN", { right = #list .. "" })
    UI.row({
        { text = "+ NEUE NOTIZ", style = "primary", onClick = function() newNote() end },
        { text = A.query and "SUCHE AUFHEBEN" or "SUCHEN", style = "secondary", onClick = function()
            if A.query then A.query = nil return end
            UI.prompt({ title = "Suchen nach", maxLen = 30, onOk = function(t) A.query = t ~= "" and t or nil A.page.page = 1 end })
        end },
    }, ix, iy)
    if #list == 0 then
        UI.empty(ix, iy + 4, iw, A.query and "Nichts gefunden" or "Noch keine Notizen",
                 not A.query and "Koordinaten, Einkaufslisten, Pläne - alles, was du nicht vergessen willst." or nil)
        return
    end
    UI.list(A.page, list, ix, iy + 2, iw, ih - 2, 3, function(n, rx, ry, rw)
        G.fill(rx - 1, ry, rw + 2, 2, C.raised)
        G.text(rx + 1, ry, G.fit((n.pin and "★ " or "") .. n.title, rw - 18), C.text, C.raised)
        G.right(rx + rw - 2, ry, dateText(n.t), C.muted, C.raised)
        G.text(rx + 1, ry + 1, G.fit(n.preview ~= "" and n.preview or " ", rw - 4), C.muted, C.raised)
        UI.region(rx - 1, ry, rw + 2, 2, function() openNote(n.id) end)
    end)
end

local function drawEditor(x, y, w, h)
    local n = find(A.open)
    if not n then A.open, A.ed = nil, nil return drawList(x, y, w, h) end
    local ed = A.ed
    local bx = UI.row({
        { text = "◀ ALLE", style = "subtle", onClick = function() store() A.open, A.ed = nil, nil end },
    }, x, y)
    G.text(bx + 1, y, G.fit(n.title, w - (bx - x) - 40), C.text)
    UI.buttonsRight({
        { text = n.pin and "★" or "☆", w = 3, style = n.pin and "accent" or "subtle", onClick = function() n.pin = not n.pin save() end },
        { text = ed.dirty and "SPEICHERN ●" or "GESPEICHERT", style = ed.dirty and "primary" or "subtle", onClick = function() store() end },
        { text = "LÖSCHEN", style = "subtle", confirm = "delnote", onClick = function() remove(n.id) end },
    }, y, x + w - 1)
    local eh = h - 2
    if not K.hasKeyboard then eh = eh - 2 end
    ed:draw(x, y + 2, w, eh)
    if not K.hasKeyboard then
        UI.row({
            { text = "+ ZEILE", style = "secondary", onClick = function() ed:appendLine() end },
            { text = "ZEILE ÄNDERN", style = "subtle", onClick = function() ed:editLine() end },
            { text = "ZEILE LÖSCHEN", style = "subtle", onClick = function() ed:deleteLine() end },
        }, x, y + h - 1)
        G.right(x + w - 1, y + h - 1, "Zeile antippen = bearbeiten", C.muted)
    else
        G.right(x + w - 1, y + 1, "Strg+S speichert · Zeile " .. ed.cy .. ", Spalte " .. ed.cx, C.muted)
    end
end

function A.draw(x, y, w, h)
    local pad = (w < 100) and 1 or 2
    x, w = x + pad, w - pad * 2
    G.text(x, y + 1, "NOTIZEN", C.text)
    G.text(x + 9, y + 1, "  " .. #db.list .. " Notiz" .. (#db.list == 1 and "" or "en"), C.muted)
    local top = y + 3
    if A.open then drawEditor(x, top, w, y + h - top - 1) else drawList(x, top, w, y + h - top - 1) end
end
function A.key(char, code)
    if A.ed and A.open then
        if code == 1 then store() A.open, A.ed = nil, nil return end
        A.ed:key(char, code)
    end
end
function A.paste(t) if A.ed and A.open then A.ed:paste(t) end end
function A.scroll(dir) if A.ed and A.open then A.ed:scroll(-dir) end end
-- fuer andere Apps (KI): Notiz anlegen
A.add = function(text) local cur = A.open newNote(text) store() if cur then openNote(cur) else A.open, A.ed = nil, nil end end
return A
