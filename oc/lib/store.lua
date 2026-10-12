-- ======================================================================
-- GTS OS (OpenComputers) - store: Dateien sicher lesen und schreiben
-- ======================================================================
-- Schreiben: erst "<datei>.neu", dann umbenennen; die alte Fassung bleibt
-- als "<datei>.bak". Lesen nimmt bei Bedarf .bak bzw. eine fertige .neu.
local fs = require("filesystem")
local ser = require("serialization")
local S = {}

function S.read(path)
    local h = io.open(path, "r")
    if not h then return nil end
    local s = h:read("*a")
    h:close()
    return s
end

function S.write(path, text)
    local dir = path:match("^(.*)/[^/]*$")
    if dir and dir ~= "" and not fs.exists(dir) then fs.makeDirectory(dir) end
    local tmp = path .. ".neu"
    local h, err = io.open(tmp, "w")
    if not h then return false, err end
    local ok, werr = pcall(h.write, h, text)
    h:close()
    if not ok then fs.remove(tmp) return false, werr end
    if fs.exists(path) then
        if fs.exists(path .. ".bak") then fs.remove(path .. ".bak") end
        fs.rename(path, path .. ".bak")
    end
    fs.rename(tmp, path)
    return true
end

function S.load(path, default)
    for _, p in ipairs({ path, path .. ".neu", path .. ".bak" }) do
        local s = S.read(p)
        if s and s ~= "" then
            local t = ser.unserialize(s)
            if type(t) == "table" then return t end
        end
    end
    return default
end

function S.save(path, t)
    return S.write(path, ser.serialize(t))
end

-- Groesse eines Ordners (Bytes)
function S.treeSize(path)
    local n = 0
    if not fs.exists(path) then return 0 end
    if not fs.isDirectory(path) then return fs.size(path) end
    for name in fs.list(path) do
        local p = path .. "/" .. name:gsub("/$", "")
        if name:sub(-1) == "/" then n = n + S.treeSize(p) else n = n + fs.size(p) end
    end
    return n
end

function S.copy(a, b)
    local s = S.read(a)
    if not s then return false end
    return S.write(b, s)
end

return S
