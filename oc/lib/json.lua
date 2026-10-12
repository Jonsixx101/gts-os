-- ======================================================================
-- GTS OS (OpenComputers) - json: kleines JSON (fuer die Claude-API)
-- ======================================================================
local J = {}
J.null = setmetatable({}, { __tostring = function() return "null" end })

local ESC = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n", ["\r"] = "\\r", ["\t"] = "\\t" }
-- Alles ausser ASCII als \uXXXX: der Server schreibt die Anfrage mit seinem
-- Standard-Zeichensatz (unter Windows oft nicht UTF-8) - so kommt nichts kaputt an.
local function u(cp)
    if cp < 0x10000 then return string.format("\\u%04x", cp) end
    cp = cp - 0x10000
    return string.format("\\u%04x\\u%04x", 0xD800 + math.floor(cp / 1024), 0xDC00 + cp % 1024)
end
local function str(s)
    s = s:gsub('[%c"\\]', function(c) return ESC[c] or string.format("\\u%04x", c:byte()) end)
    s = s:gsub("[\194-\244][\128-\191]*", function(seq)
        local b1 = seq:byte(1)
        local n = (b1 >= 0xF0) and 4 or ((b1 >= 0xE0) and 3 or 2)
        if #seq ~= n then return "?" end
        local cp = b1 % (n == 2 and 32 or (n == 3 and 16 or 8))
        for i = 2, n do cp = cp * 64 + seq:byte(i) % 64 end
        return u(cp)
    end)
    s = s:gsub("[\128-\255]", "?")
    return '"' .. s .. '"'
end
local function isArray(t)
    if next(t) == nil then return getmetatable(t) == J.ARRAY end
    local n = 0
    for k in pairs(t) do
        if type(k) ~= "number" or k < 1 or k % 1 ~= 0 then return false end
        n = math.max(n, k)
    end
    return n == #t
end
J.ARRAY = {}
function J.array(t) return setmetatable(t or {}, J.ARRAY) end

function J.encode(v)
    local t = type(v)
    if v == nil or v == J.null then return "null" end
    if t == "boolean" then return v and "true" or "false" end
    if t == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "null" end
        if v % 1 == 0 and math.abs(v) < 1e15 then return string.format("%d", v) end
        return string.format("%.14g", v)
    end
    if t == "string" then return str(v) end
    if t == "table" then
        local out = {}
        if isArray(v) then
            for i = 1, #v do out[i] = J.encode(v[i]) end
            return "[" .. table.concat(out, ",") .. "]"
        end
        local keys = {}
        for k in pairs(v) do keys[#keys + 1] = tostring(k) end
        table.sort(keys)
        for _, k in ipairs(keys) do
            local val = v[k]
            if val == nil then val = v[tonumber(k)] end
            out[#out + 1] = str(k) .. ":" .. J.encode(val)
        end
        return "{" .. table.concat(out, ",") .. "}"
    end
    error("JSON: Typ " .. t .. " geht nicht", 0)
end

local function utf8char(cp)
    if cp < 0x80 then return string.char(cp) end
    if cp < 0x800 then return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64) end
    if cp < 0x10000 then return string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64) end
    return string.char(0xF0 + math.floor(cp / 262144), 0x80 + math.floor(cp / 4096) % 64, 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
end

function J.decode(s)
    local pos = 1
    local function err(msg) error("JSON bei " .. pos .. ": " .. msg, 0) end
    local function ws() pos = s:find("[^ \t\r\n]", pos) or (#s + 1) end
    local value
    local function string_()
        pos = pos + 1
        local out = {}
        while true do
            local a, b = s:find('["\\]', pos)
            if not a then err("Text ohne Ende") end
            out[#out + 1] = s:sub(pos, a - 1)
            if s:sub(a, a) == '"' then pos = a + 1 break end
            local c = s:sub(a + 1, a + 1)
            if c == "u" then
                local cp = tonumber(s:sub(a + 2, a + 5), 16) or 63
                pos = a + 6
                if cp >= 0xD800 and cp <= 0xDBFF and s:sub(pos, pos + 1) == "\\u" then
                    local lo = tonumber(s:sub(pos + 2, pos + 5), 16) or 0
                    cp = 0x10000 + (cp - 0xD800) * 1024 + (lo - 0xDC00)
                    pos = pos + 6
                end
                out[#out + 1] = utf8char(cp)
            else
                out[#out + 1] = ({ b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" })[c] or c
                pos = a + 2
            end
        end
        return table.concat(out)
    end
    value = function()
        ws()
        local c = s:sub(pos, pos)
        if c == "{" then
            pos = pos + 1
            local t = {}
            ws()
            if s:sub(pos, pos) == "}" then pos = pos + 1 return t end
            while true do
                ws()
                if s:sub(pos, pos) ~= '"' then err("Schluessel erwartet") end
                local k = string_()
                ws()
                if s:sub(pos, pos) ~= ":" then err(": erwartet") end
                pos = pos + 1
                t[k] = value()
                ws()
                local d = s:sub(pos, pos)
                pos = pos + 1
                if d == "}" then return t end
                if d ~= "," then err(", oder } erwartet") end
            end
        elseif c == "[" then
            pos = pos + 1
            local t = J.array({})
            ws()
            if s:sub(pos, pos) == "]" then pos = pos + 1 return t end
            while true do
                t[#t + 1] = value()
                ws()
                local d = s:sub(pos, pos)
                pos = pos + 1
                if d == "]" then return t end
                if d ~= "," then err(", oder ] erwartet") end
            end
        elseif c == '"' then return string_()
        elseif s:sub(pos, pos + 3) == "true" then pos = pos + 4 return true
        elseif s:sub(pos, pos + 4) == "false" then pos = pos + 5 return false
        elseif s:sub(pos, pos + 3) == "null" then pos = pos + 4 return J.null
        else
            local num = s:match("^-?%d+%.?%d*[eE]?[%+%-]?%d*", pos)
            if not num or num == "" then err("unerwartet '" .. c .. "'") end
            pos = pos + #num
            return tonumber(num)
        end
    end
    local v = value()
    ws()
    if pos <= #s then err("Rest nach dem Wert") end
    return v
end

return J
