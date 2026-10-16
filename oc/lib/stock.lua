-- ======================================================================
-- GTS OS (OpenComputers) - stock: AE2-Auftraege und Vorrat halten
-- ======================================================================
-- Auftraege laufen ueber das ME-Netz (lokal oder an einem Knoten).
-- Vorrat: faellt ein Item unter den Mindestbestand, gibt GTS OS einen
-- Auftrag ueber die eingestellte Menge (hoechstens einer je Item gleichzeitig).
return function(K, S, D)
local computer = require("computer")
local FILE = K.ROOT .. "/data/vorrat.db"
local St = { jobs = {}, db = S.load(FILE, {}) }
St.db.rules = St.db.rules or {}
St.db.n = St.db.n or 0
function St.save() S.save(FILE, St.db) end

-- ME-Anschluss: Controller bevorzugt, sonst Interface
function St.me()
    local best
    for _, e in ipairs(D.of("lager")) do
        if e.type == "me_controller" and D.online(e) then return e end
        if e.type == "me_interface" and D.online(e) and not best then best = e end
    end
    return best
end
function St.filter(it) return { name = it.name, damage = it.damage } end

-- Auftrag: label nur zur Anzeige
function St.craft(it, amount, why)
    local me = St.me()
    if not me then return false, "Kein ME-Netz angeschlossen" end
    local job = { label = it.label or it.name, amount = amount, state = "wird gestartet", t = computer.uptime(), me = me.addr,
                  rule = it.rule, why = why }
    table.insert(St.jobs, 1, job)
    while #St.jobs > 30 do table.remove(St.jobs) end
    D.call(me.addr, "__craft", { St.filter(it), amount }, function(r)
        if r and r[1] and r[2] then job.rid, job.state = r[2], "läuft"
        else job.state = "abgelehnt: " .. tostring(r and r[2] or "?") end
        K.dirty = true
    end)
    K.log("INFO", "AE2-Auftrag: " .. amount .. "x " .. job.label .. (why and (" (" .. why .. ")") or ""))
    return true
end
function St.active(rule)
    for _, j in ipairs(St.jobs) do if j.rule == rule and (j.state == "läuft" or j.state == "wird gestartet") then return j end end
end

function St.addRule(it, min, batch)
    St.db.n = St.db.n + 1
    local r = { id = St.db.n, label = it.label or it.name, name = it.name, damage = it.damage, min = min, batch = batch, on = true }
    St.db.rules[#St.db.rules + 1] = r
    St.save()
    return r
end

function St.service()
    local nextRules = computer.uptime() + 20
    while true do
        local now = computer.uptime()
        -- Auftraege nachverfolgen
        for _, j in ipairs(St.jobs) do
            if j.rid and j.state == "läuft" and now - (j.polled or 0) > 5 then
                j.polled = now
                D.call(j.me, "__job", { j.rid }, function(r)
                    if r and r[1] and r[2] ~= "läuft" then
                        j.state = (r[2] == "unbekannt") and "fertig" or tostring(r[2])
                        if j.state == "fertig" and j.rule then K.log("INFO", "Vorrat aufgefüllt: " .. j.label) end
                        K.dirty = true
                    end
                end)
            end
        end
        -- Vorrat pruefen (jede Minute)
        if now >= nextRules then
            nextRules = now + 60
            local me = St.me()
            if me then
                for _, r in ipairs(St.db.rules) do
                    if r.on and not St.active(r.id) then
                        D.call(me.addr, "getItemsInNetwork", { { name = r.name, damage = r.damage } }, function(res)
                            if not res or not res[1] or type(res[2]) ~= "table" then return end
                            local have = 0
                            for _, it in pairs(res[2]) do if type(it) == "table" then have = have + (tonumber(it.size) or 0) end end
                            r.have, r.checked = have, K.clock()
                            if have < (r.min or 0) and not St.active(r.id) then
                                St.craft({ name = r.name, damage = r.damage, label = r.label, rule = r.id }, r.batch or 64, "Vorrat " .. have .. "/" .. r.min)
                            end
                        end, { f = { "size" } })
                    end
                end
            end
        end
        K.sleep(2)
    end
end

return St
end
