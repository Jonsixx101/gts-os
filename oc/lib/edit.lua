-- ======================================================================
-- GTS OS (OpenComputers) - edit: Texteditor (Notizen, Dateien)
-- ======================================================================
-- Mit Tastatur: Pfeile, Pos1/Ende, Bild auf/ab, Entf, Enter, Tab,
-- Strg+S speichern, Einfuegen (Mittelklick/Zwischenablage).
-- Ohne Tastatur: Zeile antippen -> Eingabefeld fuer diese Zeile.
-- Lua-Dateien werden eingefaerbt (Schluesselwoerter, Texte, Kommentare).
return function(K, G, UI)
local C = G.C
local E = {}
local KW = {}
for w in ("and break do else elseif end false for function goto if in local nil not or repeat return then true until while"):gmatch("%S+") do KW[w] = true end

local function split(text)
    local lines = {}
    text = tostring(text or ""):gsub("\r\n", "\n"):gsub("\t", "    ")
    for l in (text .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = l end
    if #lines == 0 then lines[1] = "" end
    return lines
end

-- Farben einer Lua-Zeile: Liste von { text, farbe }
local function luaSpans(line)
    local out = {}
    local i, n = 1, #line
    local function push(t, c) if t ~= "" then out[#out + 1] = { t, c } end end
    while i <= n do
        local c = line:sub(i, i)
        if line:sub(i, i + 1) == "--" then push(line:sub(i), C.muted) break
        elseif c == '"' or c == "'" then
            local j = i + 1
            while j <= n and line:sub(j, j) ~= c do if line:sub(j, j) == "\\" then j = j + 1 end j = j + 1 end
            push(line:sub(i, j), C.warn) i = j + 1
        elseif c:match("[%a_]") then
            local w = line:match("^[%w_]+", i)
            push(w, KW[w] and C.accent or C.text) i = i + #w
        elseif c:match("%d") then
            local w = line:match("^[%w%.]+", i)
            push(w, C.info) i = i + #w
        else
            local w = line:match("^[^%w_\"'%-]+", i) or c
            push(w, C.dim) i = i + #w
        end
    end
    return out
end

function E.new(text, opts)
    opts = opts or {}
    local ed = { lines = split(text), cx = 1, cy = 1, top = 1, left = 1, dirty = false, opts = opts, ro = opts.readonly }
    function ed:text() return table.concat(self.lines, "\n") end
    function ed:set(t) self.lines = split(t) self.cx, self.cy, self.top, self.left = 1, 1, 1, 1 self.dirty = false end
    local function len(s) return G.len(s) end
    function ed:clamp()
        self.cy = math.max(1, math.min(#self.lines, self.cy))
        self.cx = math.max(1, math.min(len(self.lines[self.cy]) + 1, self.cx))
    end
    function ed:changed() self.dirty = true if self.opts.onChange then self.opts.onChange() end end
    function ed:insert(s)
        if self.ro then return end
        for i, part in ipairs(split(s)) do
            if i > 1 then self:newline() end
            local l = self.lines[self.cy]
            self.lines[self.cy] = G.sub(l, 1, self.cx - 1) .. part .. G.sub(l, self.cx)
            self.cx = self.cx + len(part)
        end
        self:changed()
    end
    function ed:newline()
        if self.ro then return end
        local l = self.lines[self.cy]
        local indent = l:match("^%s*") or ""
        if self.cx <= #indent then indent = "" end
        table.insert(self.lines, self.cy + 1, indent .. G.sub(l, self.cx))
        self.lines[self.cy] = G.sub(l, 1, self.cx - 1)
        self.cy, self.cx = self.cy + 1, len(indent) + 1
        self:changed()
    end
    function ed:backspace()
        if self.ro then return end
        if self.cx > 1 then
            local l = self.lines[self.cy]
            self.lines[self.cy] = G.sub(l, 1, self.cx - 2) .. G.sub(l, self.cx)
            self.cx = self.cx - 1
        elseif self.cy > 1 then
            local prev = self.lines[self.cy - 1]
            self.cx = len(prev) + 1
            self.lines[self.cy - 1] = prev .. self.lines[self.cy]
            table.remove(self.lines, self.cy)
            self.cy = self.cy - 1
        else return end
        self:changed()
    end
    function ed:delete()
        if self.ro then return end
        local l = self.lines[self.cy]
        if self.cx <= len(l) then
            self.lines[self.cy] = G.sub(l, 1, self.cx - 1) .. G.sub(l, self.cx + 1)
        elseif self.cy < #self.lines then
            self.lines[self.cy] = l .. self.lines[self.cy + 1]
            table.remove(self.lines, self.cy + 1)
        else return end
        self:changed()
    end
    function ed:deleteLine(i)
        if self.ro then return end
        i = i or self.cy
        if #self.lines == 1 then self.lines[1] = "" else table.remove(self.lines, i) end
        self:clamp()
        self:changed()
    end
    -- Zeile ueber ein Eingabefeld bearbeiten (fuer Bildschirme ohne Tastatur)
    function ed:editLine(i)
        if self.ro then return end
        i = i or self.cy
        UI.prompt({ title = "Zeile " .. i, text = self.lines[i] or "", select = false, maxLen = 200, onOk = function(t)
            self.lines[i] = t
            self.cy, self.cx = i, len(t) + 1
            self:changed()
        end })
    end
    function ed:appendLine()
        if self.ro then return end
        UI.prompt({ title = "Neue Zeile", maxLen = 200, onOk = function(t)
            if #self.lines == 1 and self.lines[1] == "" then self.lines[1] = t else
                table.insert(self.lines, self.cy + 1, t)
                self.cy = self.cy + 1
            end
            self.cx = len(t) + 1
            self:changed()
        end })
    end
    function ed:key(char, code)
        local kb = require("keyboard")
        local ctrl = kb.isControlDown and kb.isControlDown()
        if ctrl and (code == 31) then if self.opts.onSave then self.opts.onSave() end return true end   -- Strg+S
        if code == 200 then self.cy = self.cy - 1
        elseif code == 208 then self.cy = self.cy + 1
        elseif code == 203 then
            if self.cx > 1 then self.cx = self.cx - 1 elseif self.cy > 1 then self.cy = self.cy - 1 self.cx = math.huge end
        elseif code == 205 then
            if self.cx <= len(self.lines[self.cy]) then self.cx = self.cx + 1 elseif self.cy < #self.lines then self.cy = self.cy + 1 self.cx = 1 end
        elseif code == 199 then self.cx = 1
        elseif code == 207 then self.cx = math.huge
        elseif code == 201 then self.cy = self.cy - (self.h or 10)
        elseif code == 209 then self.cy = self.cy + (self.h or 10)
        elseif code == 28 then self:newline()
        elseif code == 14 then self:backspace()
        elseif code == 211 then self:delete()
        elseif code == 15 then self:insert("    ")
        elseif char and char >= 32 and not ctrl then
            self:insert(unicode and unicode.char(char) or string.char(char))
        else
            return false
        end
        self:clamp()
        return true
    end
    function ed:paste(t) self:insert(t) self:clamp() end
    function ed:scroll(dir)
        self.top = math.max(1, math.min(math.max(1, #self.lines - (self.h or 10) + 1), self.top + dir * 3))
    end

    -- Zeichnen: Textflaeche mit Zeilennummern und Cursor
    function ed:draw(x, y, w, h, focused)
        self.h = h
        local numW = self.opts.numbers ~= false and (#tostring(#self.lines) + 2) or 0
        local tw = w - numW - 1
        self:clamp()
        if self.cy < self.top then self.top = self.cy end
        if self.cy > self.top + h - 1 then self.top = self.cy - h + 1 end
        if self.cx < self.left then self.left = self.cx end
        if self.cx > self.left + tw - 1 then self.left = self.cx - tw + 1 end
        G.fill(x, y, w, h, C.bg2)
        if numW > 0 then G.fill(x, y, numW, h, C.bg) end
        local oldClip = G.getClip()
        G.setClip(x, y, w - 1, h)
        for row = 0, h - 1 do
            local i = self.top + row
            local l = self.lines[i]
            if not l then break end
            if numW > 0 then G.right(x + numW - 2, y + row, tostring(i), i == self.cy and C.dim or C.line, C.bg) end
            local tx = x + numW + 1
            local vis = G.sub(l, self.left, self.left + tw - 1)
            if self.opts.lua then
                local cx = tx
                local skip = self.left - 1
                for _, sp in ipairs(luaSpans(l)) do
                    local t = sp[1]
                    local tl = len(t)
                    if skip >= tl then skip = skip - tl
                    else
                        if skip > 0 then t = G.sub(t, skip + 1) skip = 0 end
                        cx = G.text(cx, y + row, t, sp[2], C.bg2)
                    end
                    if cx > x + w - 1 then break end
                end
            else
                G.text(tx, y + row, vis, C.text, C.bg2)
            end
            if self.left > 1 and len(l) >= self.left then G.put(tx - 1, y + row, "‹", C.muted, C.bg2) end
            if len(l) > self.left + tw - 1 then G.put(x + w - 1, y + row, "›", C.muted, C.bg2) end
        end
        if oldClip then G.setClip(oldClip.x1, oldClip.y1, oldClip.x2 - oldClip.x1 + 1, oldClip.y2 - oldClip.y1 + 1) else G.setClip() end
        -- Cursor
        if focused ~= false and not self.ro then
            local px, py = x + numW + 1 + self.cx - self.left, y + self.cy - self.top
            if px >= x and px < x + w and py >= y and py < y + h then
                local c = G.getCell(px, py)
                G.put(px, py, (c and c ~= "" and c) or " ", C.onAccent, C.accent)
            end
        end
        -- Bildlauf
        if #self.lines > h then
            local frac = (self.top - 1) / math.max(1, #self.lines - h)
            local sh = math.max(1, math.floor(h * h / #self.lines))
            local sy = y + math.floor((h - sh) * frac + 0.5)
            for yy = y, y + h - 1 do G.put(x + w - 1, yy, (yy >= sy and yy < sy + sh) and "┃" or "│", (yy >= sy and yy < sy + sh) and C.dim or C.line, C.bg2) end
        end
        -- Antippen: Cursor setzen bzw. Zeile bearbeiten (ohne Tastatur)
        UI.region(x, y, w, h, function(rx, ry)
            local i = self.top + ry - 1
            if i > #self.lines then i = #self.lines end
            self.cy = i
            self.cx = self.left + math.max(0, rx - numW - 2)
            self:clamp()
            if not K.hasKeyboard and not self.ro then self:editLine(i) end
        end)
        UI.onScroll(x, y, w, h, function(dir) self:scroll(-dir) end)
    end
    return ed
end

return E
end
