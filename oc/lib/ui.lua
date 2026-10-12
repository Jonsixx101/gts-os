-- ======================================================================
-- GTS OS (OpenComputers) - ui: Bedienelemente (Immediate Mode)
-- ======================================================================
-- Jede Ansicht wird komplett neu gezeichnet; Knoepfe melden dabei ihre
-- Flaeche an. Ein Klick sucht die oberste Flaeche. Wie im GTS OS fuer
-- ComputerCraft: header, button, card, list (mit Seiten), tabs, chips,
-- Eingabe-Dialog mit Bildschirm-Tastatur, Ziffernblock, Bestaetigen.
return function(G)
local UI = {}
local C = G.C
local regions = {}
local scrollers = {}
UI.armed = nil          -- { key, t } zweistufige Knoepfe ("SICHER?")
UI.modal = nil          -- offener Dialog (Eingabe/Frage/Ziffernblock)
UI.now = function() return 0 end

function UI.begin()
    regions = {}
    scrollers = {}
end
function UI.region(x, y, w, h, fn, opts)
    regions[#regions + 1] = { x = x, y = y, w = w, h = h, fn = fn, modal = UI.drawingModal, opts = opts }
end
function UI.onScroll(x, y, w, h, fn) scrollers[#scrollers + 1] = { x = x, y = y, w = w, h = h, fn = fn } end

-- Klick: oberste passende Flaeche; bei offenem Dialog nur dessen Flaechen
function UI.click(x, y, button, player)
    for i = #regions, 1, -1 do
        local r = regions[i]
        if x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h then
            if UI.modal and not r.modal then break end
            local ok, err = pcall(r.fn, x - r.x + 1, y - r.y + 1, button, player)
            if not ok then UI.lastError = err end
            return true, err
        end
    end
    if UI.modal and UI.modal.dismiss ~= false then
        local m = UI.modal
        UI.modal = nil
        if m.onCancel then pcall(m.onCancel) end
        return true
    end
    return false
end
function UI.scroll(x, y, dir)
    for i = #scrollers, 1, -1 do
        local s = scrollers[i]
        if x >= s.x and x < s.x + s.w and y >= s.y and y < s.y + s.h then pcall(s.fn, dir) return true end
    end
    return false
end

-- ---------------------------------------------------------------------
-- Text
-- ---------------------------------------------------------------------
function UI.wrap(text, w)
    local out = {}
    for para in (tostring(text) .. "\n"):gmatch("(.-)\n") do
        local line = ""
        for word in para:gmatch("%S+") do
            if G.len(line) + G.len(word) + (line == "" and 0 or 1) > w then
                if line ~= "" then out[#out + 1] = line end
                while G.len(word) > w do out[#out + 1] = G.sub(word, 1, w) word = G.sub(word, w + 1) end
                line = word
            else
                line = (line == "") and word or (line .. " " .. word)
            end
        end
        out[#out + 1] = line
    end
    while #out > 1 and out[#out] == "" do out[#out] = nil end
    return out
end
-- Absatz zeichnen, liefert die naechste freie Zeile
function UI.para(x, y, w, text, f, maxLines)
    local lines = UI.wrap(text, w)
    for i, l in ipairs(lines) do
        if maxLines and i > maxLines then break end
        G.text(x, y, l, f or C.dim)
        y = y + 1
    end
    return y
end

-- ---------------------------------------------------------------------
-- Knoepfe
-- ---------------------------------------------------------------------
local STYLES = {
    primary   = { b = C.accent, f = C.onAccent },
    secondary = { b = C.raised, f = C.text },
    ghost     = { b = nil, f = C.dim },
    danger    = { b = C.bad, f = C.white },
    warn      = { b = C.warn, f = C.shadow },
    subtle    = { b = C.card, f = C.text },
    accent    = { b = C.accentDim, f = C.text },
}
UI.STYLES = STYLES
function UI.btnW(text) return G.len(text) + 4 end

-- o = { x, y, w, h, text, style, onClick, disabled, confirm = "id", fg, bg, align }
function UI.button(o)
    local text = tostring(o.text or "")
    local h = o.h or 1
    local st = STYLES[o.style or "secondary"] or STYLES.secondary
    local armed = o.confirm and UI.armed and UI.armed.key == o.confirm and UI.now() - UI.armed.t < 4
    if armed then st = STYLES.danger text = o.confirmText or "SICHER?" end
    local w = o.w or UI.btnW(text)
    if armed and o.w and o.w < UI.btnW(text) and not o.fixed then w = UI.btnW(text) end
    local parent = G.getBg(o.x, o.y)
    local sb = st.b
    if (o.style == "subtle") then
        -- immer eine Stufe heller als der Untergrund
        sb = (parent == C.card) and C.raised or ((parent == C.raised) and C.line or C.card)
    elseif (o.style or "secondary") == "secondary" and parent == C.raised then
        sb = C.line
    end
    local b = o.bg or sb or parent
    local f = o.fg or st.f
    if o.disabled then b, f = (sb and ((parent == C.card) and C.bg2 or C.card) or parent), C.muted end
    if h >= 3 and o.soft ~= false then
        G.softBox(o.x, o.y, w, h, b, parent)
    else
        G.fill(o.x, o.y, w, h, b)
    end
    local ty = o.y + math.floor((h - 1) / 2)
    if o.align == "left" then
        G.text(o.x + 1, ty, G.fit(text, w - 2), f, b)
    else
        G.center(o.x, ty, w, text, f, b)
    end
    if o.sub and h >= 3 then G.center(o.x, ty + 1, w, o.sub, o.disabled and C.muted or (st.b and f or C.muted), b) end
    if not o.disabled and o.onClick then
        UI.region(o.x, o.y, w, h, function(...)
            if o.confirm and not armed then
                UI.armed = { key = o.confirm, t = UI.now() }
                return
            end
            UI.armed = nil
            o.onClick(...)
        end)
    end
    return o.x + w
end
-- Reihe rechtsbuendig: list = { {text=..., style=..., onClick=...}, ... }
function UI.buttonsRight(list, y, xr, xl)
    local total = 0
    for _, b in ipairs(list) do total = total + (b.w or UI.btnW(b.text)) + 1 end
    local x = xr - total + 2
    if xl and x < xl then
        -- zu eng: Knoepfe kuerzen
        local each = math.max(3, math.floor((xr - xl + 1) / #list) - 1)
        x = xl
        for _, b in ipairs(list) do b.w = each end
    end
    local first = x
    for _, b in ipairs(list) do
        b.x, b.y = x, y
        x = UI.button(b) + 1
    end
    return first
end
-- Reihe von links; liefert x nach dem letzten Knopf
function UI.row(list, x, y, gap)
    for _, b in ipairs(list) do
        b.x, b.y = x, y
        x = UI.button(b) + (gap or 1)
    end
    return x
end

-- Chips (kleine Umschalter)
function UI.chip(x, y, text, active, onClick, color)
    local w = G.len(text) + 2
    local parent = G.getBg(x, y)
    local b = active and (color or C.accent) or C.raised
    local f = active and C.onAccent or C.dim
    G.fill(x, y, w, 1, b)
    G.text(x + 1, y, text, f, b)
    if onClick then UI.region(x, y, w, 1, onClick) end
    return x + w
end
-- Segment-Leiste (Reiter)
function UI.tabs(x, y, w, list, active, onPick)
    local cx = x
    for i, t in ipairs(list) do
        local label = type(t) == "table" and t.text or t
        local id = type(t) == "table" and (t.id or label) or label
        local tw = G.len(label) + 2
        if cx + tw - 1 > x + w - 1 then break end
        local on = id == active
        G.fill(cx, y, tw, 1, on and C.raised or C.bg2)
        G.text(cx + 1, y, label, on and C.text or C.muted)
        if on then for i = 0, tw - 1 do G.put(cx + i, y + 1, "▔", C.accent, G.getBg(cx + i, y + 1)) end end
        UI.region(cx, y, tw, 1, function() onPick(id) end)
        cx = cx + tw
    end
    return cx
end

-- Schalter  ( ●   ) / (   ● )
function UI.toggle(x, y, on, onClick)
    local b = on and C.accent or C.line
    G.fill(x, y, 5, 1, b)
    G.text(on and x + 3 or x + 1, y, "●", on and C.onAccent or C.dim, b)
    G.text(x + 5, y, " " .. (on and "AN " or "AUS"), on and C.accent or C.muted)
    UI.region(x, y, 9, 1, onClick)
    return x + 9
end

-- ---------------------------------------------------------------------
-- Flaechen
-- ---------------------------------------------------------------------
-- Karte mit weichen Kanten; liefert Innenbereich (x, y, w, h)
function UI.card(x, y, w, h, title, opts)
    opts = opts or {}
    local b = opts.bg or C.card
    G.softBox(x, y, w, h, b, G.getBg(x, y))
    local iy = y + 1
    if title then
        G.text(x + 2, iy, G.fit(title, w - 4), opts.titleColor or C.muted, b)
        if opts.right then G.right(x + w - 3, iy, opts.right, opts.rightColor or C.muted, b) end
        iy = iy + 1
    end
    return x + 2, iy, w - 4, y + h - 1 - iy
end
-- Schluessel/Wert-Zeile
function UI.kv(x, y, w, key, value, color, keyW)
    keyW = keyW or math.min(16, math.floor(w * 0.42))
    G.text(x, y, G.fit(key, keyW - 1), C.muted)
    G.text(x + keyW, y, G.fit(tostring(value), w - keyW), color or C.text)
end
function UI.empty(x, y, w, title, hint)
    G.center(x, y, w, title, C.text)
    if hint then
        local yy = y + 1
        for _, l in ipairs(UI.wrap(hint, w - 4)) do G.center(x, yy, w, l, C.muted) yy = yy + 1 end
        return yy
    end
    return y + 1
end
-- Statuspunkt
function UI.dot(x, y, color) G.put(x, y, "●", color) end
-- Fortschritt mit Prozent rechts
function UI.meter(x, y, w, frac, color, label)
    local lw = label and (G.len(label) + 1) or 0
    G.bar(x, y, w - lw, frac, color or C.accent, C.line)
    if label then G.text(x + w - lw + 1, y, label, C.dim) end
end

-- Liste mit Seiten. state = { page = 1 }; draw(item, x, y, w, index)
-- Liefert die Zeile nach der Liste.
function UI.list(state, items, x, y, w, h, rowH, draw, opts)
    opts = opts or {}
    local n = #items
    local per = math.max(1, math.floor(h / rowH))
    local pages = math.max(1, math.ceil(n / per))
    if n > per then
        per = math.max(1, math.floor((h - 1) / rowH))
        pages = math.max(1, math.ceil(n / per))
    end
    state.page = math.max(1, math.min(state.page or 1, pages))
    local first = (state.page - 1) * per + 1
    for i = first, math.min(n, first + per - 1) do
        local ry = y + (i - first) * rowH
        draw(items[i], x, ry, w, i)
    end
    UI.onScroll(x, y, w, h, function(dir)
        state.page = math.max(1, math.min(pages, state.page + (dir < 0 and 1 or -1)))
    end)
    if pages > 1 then
        local py = y + h - 1
        local label = " " .. state.page .. " / " .. pages .. " "
        local cx = x + math.floor((w - G.len(label)) / 2)
        UI.button({ x = cx - 5, y = py, w = 4, text = "◀", style = "subtle", disabled = state.page <= 1,
                    onClick = function() state.page = state.page - 1 end })
        G.text(cx, py, label, C.dim)
        UI.button({ x = cx + G.len(label) + 1, y = py, w = 4, text = "▶", style = "subtle", disabled = state.page >= pages,
                    onClick = function() state.page = state.page + 1 end })
    end
    return y + h, pages
end

-- ---------------------------------------------------------------------
-- Dialoge
-- ---------------------------------------------------------------------
-- Eingabe: o = { title, text, mask, hint, maxLen, numeric, onOk(text), onCancel, osk }
function UI.prompt(o)
    o.text = o.text or ""
    -- vorbelegter Text ist "markiert": der erste Tastendruck ersetzt ihn
    o.fresh = o.text ~= "" and o.select ~= false
    o.kind = "prompt"
    o.shift = false
    UI.modal = o
end
function UI.ask(title, text, onYes, yesText, style)
    UI.modal = { kind = "ask", title = title, text = text, onYes = onYes, yesText = yesText or "OK", style = style or "primary" }
end
function UI.keypad(o)
    o.kind = "keypad"
    o.text = ""
    UI.modal = o
end
function UI.closeModal() UI.modal = nil end

local function modalBox(w, h)
    local SW, SH = G.size()
    w, h = math.min(w, SW - 2), math.min(h, SH - 2)
    local x = math.floor((SW - w) / 2) + 1
    local y = math.floor((SH - h) / 2) + 1
    -- Abdunkeln: Rahmen der Flaeche mit Schatten
    G.softBox(x, y, w, h, C.raised, G.getBg(x, y))
    G.shadow(x + 1, y + h, w, G.getBg(x + 1, y + h))
    return x, y, w, h
end

local OSK = { "1234567890", "qwertzuiop", "asdfghjkl", "yxcvbnm.-_" }
function UI.drawModal(hasKeyboard)
    local m = UI.modal
    if not m then return end
    UI.drawingModal = true
    local SW, SH = G.size()
    if m.kind == "ask" then
        local lines = UI.wrap(m.text or "", 44)
        local x, y, w, h = modalBox(50, 7 + #lines)
        G.text(x + 3, y + 1, G.fit(m.title, w - 6), C.text, C.raised)
        for i, l in ipairs(lines) do G.text(x + 3, y + 2 + i, l, C.dim, C.raised) end
        UI.buttonsRight({
            { text = "ABBRECHEN", style = "subtle", onClick = function() UI.modal = nil if m.onCancel then m.onCancel() end end },
            { text = m.yesText, style = m.style, onClick = function() UI.modal = nil if m.onYes then m.onYes() end end },
        }, y + h - 2, x + w - 3)
    elseif m.kind == "prompt" then
        local osk = (m.osk ~= false) and (m.forceOsk or not hasKeyboard)
        local w = 56
        local h = (osk and 15 or 8) + (m.hint and 1 or 0)
        local x, y
        x, y, w, h = modalBox(w, h)
        G.text(x + 3, y + 1, G.fit(m.title or "Eingabe", w - 6), C.text, C.raised)
        local fy = y + 3
        G.fill(x + 3, fy, w - 6, 1, C.bg2)
        local shown = m.mask and string.rep("•", G.len(m.text)) or m.text
        local vis = w - 8
        if G.len(shown) > vis then shown = G.sub(shown, G.len(shown) - vis + 1) end
        G.text(x + 4, fy, shown, m.fresh and C.white or C.text, m.fresh and C.accentDim or C.bg2)
        G.text(x + 4 + G.len(shown), fy, "▏", C.accent, C.bg2)
        G.thinBar(x + 3, fy + 1, w - 6, 1, C.accent, C.accent, C.raised)
        local yy = fy + 2
        if m.hint then G.text(x + 3, yy, G.fit(m.hint, w - 6), C.muted, C.raised) yy = yy + 1 end
        if m.err then G.text(x + 3, yy, G.fit(m.err, w - 6), C.bad, C.raised) end
        if osk then
            local ky = yy + 1
            local keyW = math.max(3, math.floor((w - 6) / 10))
            for r, row in ipairs(OSK) do
                local kx = x + 3 + math.floor((w - 6 - #row * keyW) / 2)
                for c in row:gmatch(".") do
                    local label = (m.shift and c:upper()) or c
                    if (m.numeric or m.signed) and not c:match("%d") then
                        UI.button({ x = kx, y = ky, w = keyW - 1, text = label, style = "subtle", disabled = true })
                    else
                        UI.button({ x = kx, y = ky, w = keyW - 1, text = label, style = "subtle", onClick = function()
                            if m.fresh then m.text = "" m.fresh = false end
                            if not m.maxLen or G.len(m.text) < m.maxLen then m.text = m.text .. label end
                            m.shift = false
                        end })
                    end
                    kx = kx + keyW
                end
                ky = ky + 1 + (r < #OSK and 1 or 0)
            end
            local bx = x + 3
            bx = UI.button({ x = bx, y = ky, text = "⇧", w = 5, style = m.shift and "primary" or "subtle", onClick = function() m.shift = not m.shift end }) + 1
            bx = UI.button({ x = bx, y = ky, text = "LEER", w = 12, style = "subtle", onClick = function() if m.fresh then m.text = "" m.fresh = false end m.text = m.text .. " " end }) + 1
            bx = UI.button({ x = bx, y = ky, text = "⌫", w = 5, style = "subtle", onClick = function() if m.fresh then m.text = "" m.fresh = false end m.text = G.sub(m.text, 1, G.len(m.text) - 1) end }) + 1
            if m.numeric or m.signed then
                UI.button({ x = bx, y = ky, text = "−", w = 5, style = "subtle", onClick = function()
                    if m.fresh then m.text = "" m.fresh = false end
                    if m.text:sub(1, 1) == "-" then m.text = m.text:sub(2) else m.text = "-" .. m.text end
                end })
            end
        end
        UI.buttonsRight({
            { text = "ABBRECHEN", style = "subtle", onClick = function() UI.modal = nil if m.onCancel then m.onCancel() end end },
            { text = m.okText or "OK", style = "primary", onClick = function() UI.submit() end },
        }, y + h - 2, x + w - 3)
    elseif m.kind == "keypad" then
        local x, y, w, h = modalBox(30, 19)
        G.center(x, y + 1, w, m.title or "Code", C.text, C.raised)
        local dots = ""
        for i = 1, math.max(4, #m.text) do dots = dots .. (i <= #m.text and "● " or "○ ") end
        G.center(x, y + 3, w, dots, m.err and C.bad or C.accent, C.raised)
        if m.err then G.center(x, y + 4, w, m.err, C.bad, C.raised) end
        local keys = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "⌫", "0", "OK" }
        for i, k in ipairs(keys) do
            local col, row = (i - 1) % 3, math.floor((i - 1) / 3)
            local kx, ky = x + 3 + col * 8, y + 6 + row * 3
            UI.button({ x = kx, y = ky, w = 7, h = 3, text = k, style = (k == "OK") and "primary" or "subtle", onClick = function()
                m.err = nil
                if k == "⌫" then m.text = m.text:sub(1, -2)
                elseif k == "OK" then UI.submit()
                elseif #m.text < (m.maxLen or 8) then m.text = m.text .. k
                    if m.autoLen and #m.text >= m.autoLen then UI.submit() end
                end
            end })
        end
        if m.cancel ~= false then
            UI.button({ x = x + w - 4, y = y + 1, w = 3, text = "✕", style = "ghost", onClick = function() UI.modal = nil if m.onCancel then m.onCancel() end end })
        end
    end
    UI.drawingModal = false
end
function UI.submit()
    local m = UI.modal
    if not m then return end
    if m.kind == "prompt" and m.validate then
        local err = m.validate(m.text)
        if err then m.err = err return end
    end
    if m.keepOpen then m.err = nil else UI.modal = nil end
    if m.onOk then m.onOk(m.text, m) end
end
-- Tastatur fuer offene Dialoge; true = verbraucht
function UI.key(char, code)
    local m = UI.modal
    if not m then return false end
    if code == 28 then UI.submit() return true end
    if code == 1 then UI.modal = nil if m.onCancel then m.onCancel() end return true end
    if m.kind == "ask" then return true end
    if code == 14 then
        if m.fresh then m.text = "" m.fresh = false end
        m.text = G.sub(m.text, 1, G.len(m.text) - 1)
        m.err = nil
        return true
    end
    if code == 203 or code == 205 or code == 199 or code == 207 then m.fresh = false return true end
    if char and char >= 32 then
        if m.fresh then m.text = "" m.fresh = false end
        local c = unicode and unicode.char(char) or string.char(char)
        if m.numeric and not c:match("%d") then return true end
        if m.signed and not c:match("[%d%-]") then return true end
        if m.kind == "keypad" and not c:match("%d") then return true end
        local maxLen = m.maxLen or (m.kind == "keypad" and 8) or 200
        if G.len(m.text) < maxLen then m.text = m.text .. c end
        m.err = nil
        if m.kind == "keypad" and m.autoLen and #m.text >= m.autoLen then UI.submit() end
        return true
    end
    return true
end
function UI.paste(text)
    local m = UI.modal
    if m and m.kind == "prompt" then
        if m.fresh then m.text = "" m.fresh = false end
        m.text = m.text .. tostring(text):gsub("[\r\n]", "")
        return true
    end
    return false
end

return UI
end
