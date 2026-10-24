local RES = GetCurrentResourceName()
local function T() return Config.Text[Config.Locale] or Config.Text.en end
local function log(msg) print(('^3[ziks-bugreport]^7 %s'):format(msg)) end

-- ===== framework adapter (Qbox / QBCore / ESX / standalone). Only player info is framework specific. =====
local QBCore, ESX
local function framework()
    if GetResourceState('qbx_core') == 'started' then return 'qbx' end
    if GetResourceState('qb-core') == 'started' then return 'qb' end
    if GetResourceState('es_extended') == 'started' then return 'esx' end
    return 'standalone'
end

local function inventory(src, fallback)
    local out = {}
    if GetResourceState('ox_inventory') == 'started' then
        local ok, items = pcall(function() return exports.ox_inventory:GetInventoryItems(src) end)
        if ok and type(items) == 'table' then
            for _, it in pairs(items) do
                if type(it) == 'table' and it.name then out[#out + 1] = { name = it.name, count = it.count or 1, slot = it.slot, metadata = it.metadata } end
            end
            return out
        end
    end
    if type(fallback) == 'table' then
        for _, it in pairs(fallback) do
            if type(it) == 'table' and it.name and (it.count or it.amount or 1) > 0 then
                out[#out + 1] = { name = it.name, count = it.amount or it.count or 1, slot = it.slot, metadata = it.info or it.metadata }
            end
        end
    end
    return out
end

-- returns { fw, id, char, job, jobLabel, grade, duty, gang, cash, bank, items, raw }
local function playerInfo(src)
    local fw = framework()
    local r = { fw = fw }
    local ok = pcall(function()
        if fw == 'qbx' or fw == 'qb' then
            local P
            if fw == 'qbx' then P = exports.qbx_core:GetPlayer(src)
            else QBCore = QBCore or exports['qb-core']:GetCoreObject() P = QBCore.Functions.GetPlayer(src) end
            local pd = P and P.PlayerData
            if not pd then return end
            local ci = pd.charinfo or {}
            r.id = pd.citizenid
            r.char = ci.firstname and (ci.firstname .. ' ' .. (ci.lastname or '')) or nil
            r.job, r.jobLabel = pd.job and pd.job.name, pd.job and pd.job.label
            r.grade, r.duty = pd.job and pd.job.grade and (pd.job.grade.level or pd.job.grade.name), pd.job and pd.job.onduty
            r.gang = pd.gang and pd.gang.name
            r.cash, r.bank = pd.money and pd.money.cash, pd.money and pd.money.bank
            r.items = Config.Attach.inventory and inventory(src, pd.items) or nil
            r.raw = pd
        elseif fw == 'esx' then
            ESX = ESX or exports.es_extended:getSharedObject()
            local x = ESX.GetPlayerFromId(src)
            if not x then return end
            local acc = function(n) local a = x.getAccount and x.getAccount(n) return a and a.money end
            r.id = x.identifier
            r.char = x.getName and x.getName() or nil
            r.job, r.jobLabel, r.grade = x.job and x.job.name, x.job and x.job.label, x.job and x.job.grade
            r.cash, r.bank = acc('money'), acc('bank')
            r.items = Config.Attach.inventory and inventory(src, x.getInventory and x.getInventory(true) or x.inventory) or nil
            r.raw = { identifier = x.identifier, job = x.job, accounts = x.getAccounts and x.getAccounts() or nil, group = x.getGroup and x.getGroup() or nil, metadata = x.metadata }
        else
            r.items = Config.Attach.inventory and inventory(src) or nil
        end
    end)
    if not ok then r.fw = fw .. ' (lookup failed)' end
    return r
end

local function discordId(src)
    local d = GetPlayerIdentifierByType(src, 'discord')
    return d and d:gsub('^discord:', '') or nil
end

-- ===== rate limits =====
local last, hourly, inflight = {}, {}, {}
local function limitKey(src) return GetPlayerIdentifierByType(src, 'license') or ('src:' .. src) end

local function limitLeft(k)
    local now = os.time()
    if last[k] and now - last[k] < Config.Cooldown then return Config.Cooldown - (now - last[k]), 'cooldown' end
    local keep = {}
    for _, t in ipairs(hourly[k] or {}) do if now - t < 3600 then keep[#keep + 1] = t end end
    hourly[k] = keep
    if #keep >= Config.HourlyCap then return 3600 - (now - keep[1]), 'cap' end
    return 0
end

local function canSeverity(src)
    return Config.SeverityForAll == true or IsPlayerAceAllowed(src, Config.SeverityAce)
end

local function clip(s, n)
    if type(s) ~= 'string' then return '' end
    s = s:gsub('^%s+', ''):gsub('%s+$', '')
    if #s > n then s = s:sub(1, n) end
    return s
end

-- ===== request/response for the client (no ox_lib) =====
local handlers = {}
RegisterNetEvent('ziks-bugreport:call', function(id, name, ...)
    local src = source
    local h = handlers[name]
    if type(id) ~= 'number' or not h then return end
    local args = table.pack(...)
    CreateThread(function()
        local r = table.pack(xpcall(h, debug.traceback, src, table.unpack(args, 1, args.n)))
        if not r[1] then
            log('^1' .. name .. ' error:^7 ' .. tostring(r[2]))
            TriggerClientEvent('ziks-bugreport:reply', src, id, false, 'server error (see console)')
            return
        end
        TriggerClientEvent('ziks-bugreport:reply', src, id, table.unpack(r, 2, r.n))
    end)
end)

-- ===== screenshot transport (one latent event from the client) =====
local shots = {}
RegisterNetEvent('ziks-bugreport:shot', function(data)
    local src = source
    if type(data) ~= 'string' or #data > Config.Screenshot.maxBytes + 1000 then return end
    shots[src] = { body = data, at = os.time() }
    TriggerClientEvent('ziks-bugreport:shotAck', src, #data)
end)
AddEventHandler('playerDropped', function() shots[source] = nil inflight[source] = nil end)
CreateThread(function()
    while true do
        Wait(60000)
        local now = os.time()
        for k, v in pairs(shots) do if now - v.at > 300 then shots[k] = nil end end
    end
end)

-- ===== server console capture =====
local ARING, ERING = 400, 200
local cAll, cAllPos, cAllN = {}, 0, 0
local cErr, cErrPos, cErrN = {}, 0, 0
local ERR_WORDS = { 'SCRIPT ERROR', 'rror', 'attempt to', 'stack traceback', 'Failed', 'Could not', 'nil value', 'No such export' }
if RegisterConsoleListener then
    RegisterConsoleListener(function(channel, message)
        if type(message) ~= 'string' then return end
        local line = message:gsub('%^%d', ''):gsub('[\r\n]+$', '')
        if line == '' or line:find('[ziks-bugreport]', 1, true) or line:find('hitch warning', 1, true) then return end
        local entry = ('[%s] %s'):format(tostring(channel), line:sub(1, 300))
        cAllPos = cAllPos % ARING + 1
        cAll[cAllPos] = entry
        if cAllN < ARING then cAllN = cAllN + 1 end
        for i = 1, #ERR_WORDS do
            if line:find(ERR_WORDS[i], 1, true) then
                cErrPos = cErrPos % ERING + 1
                cErr[cErrPos] = entry
                if cErrN < ERING then cErrN = cErrN + 1 end
                return
            end
        end
    end)
end

local function ring(buf, pos, n, size, max)
    local out = {}
    for i = math.min(n, max) - 1, 0, -1 do out[#out + 1] = buf[(pos - i - 1) % size + 1] end
    return out
end

local function resourceList()
    local started, bad = {}, {}
    for i = 0, GetNumResources() - 1 do
        local n = GetResourceByFindIndex(i)
        if n then
            local st = GetResourceState(n)
            if st == 'started' then
                started[#started + 1] = n .. '@' .. (GetResourceMetadata(n, 'version', 0) or '?')
            elseif st ~= 'uninitialized' and st ~= 'unknown' and st ~= 'stopped' then
                bad[#bad + 1] = n .. ' [' .. st .. ']'
            end
        end
    end
    table.sort(started) table.sort(bad)
    return started, bad
end

-- ===== delivery: server/webhook.js does the HTTPS multipart upload =====
local deliveries, dseq = {}, 0
AddEventHandler('ziks-bugreport:delivered', function(id, status, info)
    local p = deliveries[id]
    if p then deliveries[id] = nil p:resolve({ status = status, info = info }) end
end)

local function deliver(report)
    dseq = dseq + 1
    local id, p = dseq, promise.new()
    deliveries[id] = p
    TriggerEvent('ziks-bugreport:deliver', id, report)
    SetTimeout(240000, function() if deliveries[id] then deliveries[id] = nil p:resolve({ status = 'retry', info = 'timeout' }) end end)
    local r = Citizen.Await(p)
    return r.status, r.info -- 'ok' | 'retry' | 'fail'
end

local QUEUE_FILE, QUEUE_MAX = 'queue.json', 10
local queue = {}
local function persistQueue() SaveResourceFile(RES, QUEUE_FILE, json.encode(queue), -1) end

-- ===== build the report =====
local function f2(v) return tonumber(v) or 0 end
local function s(v, n) return clip(tostring(v == nil and '' or v), n or 80) end

local function buildReport(src, f, info)
    local L = T()
    local P = playerInfo(src)
    local co = type(info.coords) == 'table' and info.coords or {}
    local sev = canSeverity(src) and ({ low = 1, normal = 1, high = 1, critical = 1 })[f.severity] and f.severity or 'normal'
    local catLabel = f.category
    for _, c in ipairs(Config.Categories) do if c.id == f.category then catLabel = c[Config.Locale] or c.en end end

    local shotB64
    if f.shot and Config.Attach.screenshot ~= false and shots[src] then
        local d = shots[src].body
        local i = d:find(',', 1, true)
        if i and d:sub(1, 5) == 'data:' then d = d:sub(i + 1) end
        shotB64 = d
    end
    shots[src] = nil

    local env = {
        ('Position: %.2f, %.2f, %.2f  heading %.0f'):format(f2(co.x), f2(co.y), f2(co.z), f2(co.h)),
        ('Street: %s%s  Zone: %s  Interior: %s'):format(s(info.street, 60), info.cross and (' / ' .. s(info.cross, 60)) or '', s(info.zone, 60), tostring(f2(info.interior))),
        ('Health: %s  Armor: %s  Dead: %s'):format(f2(info.health), f2(info.armor), tostring(info.dead == true)),
        ('FPS: %s  Ping: %s ms  Resolution: %s'):format(f2(info.fps), GetPlayerPing(src), type(info.res) == 'table' and (s(info.res[1], 6) .. 'x' .. s(info.res[2], 6)) or '?'),
        ('Players online: %s  Server uptime: %s min  Routing bucket: %s'):format(#GetPlayers(), math.floor(GetGameTimer() / 60000), GetPlayerRoutingBucket(src)),
        ('Game time: %s  Weather: %s'):format(s(info.time, 8), s(info.weather, 20)),
        ('State: onFoot=%s inWater=%s swimming=%s falling=%s ragdoll=%s armed=%s'):format(tostring(info.onFoot), tostring(info.inWater), tostring(info.swimming), tostring(info.falling), tostring(info.ragdoll), tostring(info.armed)),
    }
    local vehLine
    if type(info.vehicle) == 'table' then
        local v = info.vehicle
        vehLine = ('%s · %s · %s km/h · engine %s'):format(s(v.model, 30), s(v.plate, 12), f2(v.speed), f2(v.engine))
        env[#env + 1] = 'Vehicle: ' .. vehLine
    end
    if type(info.looking) == 'table' then
        local l = info.looking
        env[#env + 1] = ('Looking at: %s model=%s%s%s networked=%s at %.1f, %.1f, %.1f'):format(s(l.type, 12), s(l.model, 14), l.name and (' (' .. s(l.name, 30) .. ')') or '', l.plate and (' plate ' .. s(l.plate, 12)) or '', tostring(l.networked), f2(l.x), f2(l.y), f2(l.z))
    end
    if type(info.nearVehicle) == 'table' then
        local v = info.nearVehicle
        env[#env + 1] = ('Nearest vehicle: %s plate %s %.1f m'):format(s(v.model, 30), s(v.plate, 12), f2(v.dist))
    end
    env[#env + 1] = ('Framework: %s  Character: %s  ID: %s'):format(P.fw, s(P.char, 60), s(P.id, 60))
    if P.job then
        env[#env + 1] = ('Job: %s (%s) grade %s onduty=%s  Gang: %s  Cash: %s  Bank: %s'):format(s(P.job, 30), s(P.jobLabel, 40), s(P.grade, 20), tostring(P.duty), s(P.gang, 30), s(P.cash, 16), s(P.bank, 16))
    end
    if P.items and #P.items > 0 then
        local its = {}
        for _, it in ipairs(P.items) do its[#its + 1] = it.name .. ' x' .. tostring(it.count) end
        table.sort(its)
        env[#env + 1] = 'Inventory: ' .. table.concat(its, ', '):sub(1, 3000)
    end

    local sections = { '== Environment ==', table.concat(env, '\n') }
    local function section(title, body) if body and body ~= '' then sections[#sections + 1] = '\n== ' .. title .. ' ==\n' .. body end end
    local pasted = clip(f.console, 3000)
    section('F8 console (pasted by the player)', pasted)
    if Config.Attach.console ~= false then
        section('Server console errors (recent)', table.concat(ring(cErr, cErrPos, cErrN, ERING, 40), '\n'))
        section('Server console (last lines)', table.concat(ring(cAll, cAllPos, cAllN, ARING, ARING), '\n'))
    end
    if Config.Attach.resources ~= false then
        local started, bad = resourceList()
        section('Resources not running cleanly', table.concat(bad, '\n'))
        section('Started resources (' .. #started .. ')', table.concat(started, ', '))
    end

    local playerJson
    if Config.Attach.playerData ~= false then
        local ids = {}
        for i = 0, GetNumPlayerIdentifiers(src) - 1 do
            local id = GetPlayerIdentifier(src, i)
            if id and not id:find('^ip:') then ids[#ids + 1] = id end -- never send IPs
        end
        local ok, j = pcall(json.encode, { source = src, name = GetPlayerName(src), framework = P.fw, identifiers = ids, player = P.raw, inventory = P.items, client = info })
        if ok and type(j) == 'string' and #j < 2000000 then playerJson = j end
    end

    local ping = Config.PingRoles and Config.PingRoles[sev]
    return {
        title = clip(f.title, 150),
        description = clip(f.description, 2000),
        steps = clip(f.reproduction, 1500), expected = clip(f.expected, 600), actual = clip(f.actual, 600),
        category = s(catLabel, 40), severity = sev, severityLabel = L[sev] or sev,
        reporter = {
            name = s(GetPlayerName(src), 64), char = P.char and s(P.char, 64) or nil, server_id = src,
            discord = discordId(src), license = GetPlayerIdentifierByType(src, 'license'),
        },
        location = ('%s%s · %s'):format(s(info.street, 60), info.cross and (' / ' .. s(info.cross, 60)) or '', s(info.zone, 60)),
        coords = ('%.2f, %.2f, %.2f'):format(f2(co.x), f2(co.y), f2(co.z)),
        vehicle = vehLine,
        client = ('FPS %s · ping %s ms · %s'):format(f2(info.fps), GetPlayerPing(src), P.job and (s(P.jobLabel or P.job, 30)) or P.fw),
        build = clip(GetConvar('version', ''), 120),
        server = clip(GetConvar('sv_projectName', GetConvar('sv_hostname', '')), 100):gsub('%^%d', ''),
        reportText = Config.Attach.reportFile ~= false and table.concat(sections, '\n') or nil,
        playerJson = playerJson,
        screenshot = shotB64,
        pingRole = (ping and ping ~= '') and tostring(ping) or nil,
        forum = Config.Forum == true,
        forumTag = Config.ForumTags and Config.ForumTags[sev] or nil,
        labels = { category = L.e_category, severity = L.e_severity, reporter = L.e_reporter, location = L.e_location, vehicle = L.e_vehicle, client = L.e_client, steps = L.e_steps, expected = L.e_expected, actual = L.e_actual, none = L.e_none },
        at = os.time(),
    }
end

handlers.canReport = function(src)
    local left, reason = limitLeft(limitKey(src))
    return left, reason, canSeverity(src)
end

handlers.submit = function(src, f, info)
    if type(f) ~= 'table' or type(info) ~= 'table' then return false, 'bad request' end
    if GetConvar('ziks_bugreport_webhook', '') == '' then
        log('^1ziks_bugreport_webhook is not set^7 - add `set ziks_bugreport_webhook "https://discord.com/api/webhooks/..."` to server.cfg')
        return false, 'webhook not configured'
    end
    local k = limitKey(src)
    if inflight[src] or limitLeft(k) > 0 then return false, 'rate limited' end
    if clip(f.title, 150) == '' then return false, 'title required' end
    inflight[src] = true
    local ok, report = pcall(buildReport, src, f, info)
    if not ok then inflight[src] = nil error(report) end
    local status, why = deliver(report)
    inflight[src] = nil
    if status == 'fail' then
        log('^1rejected by Discord:^7 ' .. tostring(why))
        return false, tostring(why)
    end
    last[k] = os.time()
    hourly[k] = hourly[k] or {}
    hourly[k][#hourly[k] + 1] = os.time()
    if status == 'retry' then
        if #queue >= QUEUE_MAX then table.remove(queue, 1) end
        queue[#queue + 1] = report
        persistQueue()
        log(('Discord unavailable (%s) - report queued (%d in queue)'):format(tostring(why), #queue))
        return true, 'queued'
    end
    log(('report from %s (%s) sent: %s'):format(GetPlayerName(src), src, report.title))
    return true, 'sent'
end

-- retry queued reports every 2 minutes
CreateThread(function()
    local raw = LoadResourceFile(RES, QUEUE_FILE)
    if raw and raw ~= '' then
        local ok, d = pcall(json.decode, raw)
        if ok and type(d) == 'table' then queue = d end
    end
    while true do
        Wait(120000)
        if #queue > 0 then
            local rest = {}
            for _, r in ipairs(queue) do
                local st = deliver(r)
                if st == 'retry' then rest[#rest + 1] = r end
            end
            queue = rest
            persistQueue()
        end
    end
end)
