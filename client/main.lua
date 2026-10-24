local isOpen, busy = false, false

local function T() return Config.Text[Config.Locale] or Config.Text.en end
local function dbg(msg) print(('^3[ziks-bugreport]^7 %s'):format(msg)) end

local function notify(text, kind)
    SendNUIMessage({ type = 'toast', text = text, kind = kind or 'info' })
end

-- ===== tiny request/response over net events (no ox_lib needed) =====
local pending, seq = {}, 0
RegisterNetEvent('ziks-bugreport:reply', function(id, ...)
    local p = pending[id]
    if p then pending[id] = nil p:resolve(table.pack(...)) end
end)

local function serverCall(name, ...)
    seq = seq + 1
    local id, p = seq, promise.new()
    pending[id] = p
    TriggerServerEvent('ziks-bugreport:call', id, name, ...)
    SetTimeout(120000, function()
        if pending[id] then pending[id] = nil p:resolve(table.pack(false, 'timeout')) end
    end)
    local r = Citizen.Await(p)
    return table.unpack(r, 1, r.n)
end

-- ===== screenshot =====
local function stripPrefix(d)
    if not d then return nil end
    local i = d:find(',', 1, true)
    if i and d:sub(1, 5) == 'data:' then d = d:sub(i + 1) end
    return d
end

local function grab(cb)
    local done = false
    local ok, err = pcall(function()
        exports['screenshot-basic']:requestScreenshot({ encoding = 'jpg', quality = Config.Screenshot.quality }, function(data)
            if done then return end
            done = true
            cb(type(data) == 'string' and data ~= '' and data or nil)
        end)
    end)
    if not ok then
        done = true
        dbg('screenshot-basic export error: ' .. tostring(err))
        cb(nil)
        return
    end
    SetTimeout(8000, function() if not done then done = true dbg('screenshot timeout') cb(nil) end end)
end

-- ===== context =====
local WEATHERS = { 'CLEAR', 'EXTRASUNNY', 'CLOUDS', 'OVERCAST', 'RAIN', 'CLEARING', 'THUNDER', 'SMOG', 'FOGGY', 'XMAS', 'SNOW', 'SNOWLIGHT', 'BLIZZARD', 'HALLOWEEN', 'NEUTRAL' }

local function collect()
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local s1, s2 = GetStreetNameAtCoord(c.x, c.y, c.z)
    local street = GetStreetNameFromHashKey(s1)
    local cross = s2 ~= 0 and GetStreetNameFromHashKey(s2) or nil
    local zone = GetLabelText(GetNameOfZone(c.x, c.y, c.z))
    local veh = GetVehiclePedIsIn(ped, false)
    local vehicle
    if veh ~= 0 then
        vehicle = {
            model = GetDisplayNameFromVehicleModel(GetEntityModel(veh)),
            plate = GetVehicleNumberPlateText(veh),
            speed = math.floor(GetEntitySpeed(veh) * 3.6),
            engine = math.floor(GetVehicleEngineHealth(veh)),
        }
    end
    local weather = 'unknown'
    local wh = GetPrevWeatherTypeHashName()
    for _, w in ipairs(WEATHERS) do
        if GetHashKey(w) == wh then weather = w break end
    end
    -- what the player is looking at (10 m ray from the camera)
    local looking
    local cam, rot = GetGameplayCamCoord(), GetGameplayCamRot(2)
    local rz, rx = math.rad(rot.z), math.rad(rot.x)
    local dir = vector3(-math.sin(rz) * math.abs(math.cos(rx)), math.cos(rz) * math.abs(math.cos(rx)), math.sin(rx))
    local h = StartExpensiveSynchronousShapeTestLosProbe(cam.x, cam.y, cam.z, cam.x + dir.x * 10.0, cam.y + dir.y * 10.0, cam.z + dir.z * 10.0, 287, ped, 4)
    local status, hit, endc, _, ent = GetShapeTestResult(h)
    if status == 2 and (hit == true or hit == 1) and ent and ent ~= 0 then
        -- map/streamed entities can fail native reads; never abort the report for it
        local ok, result = pcall(function()
            if not DoesEntityExist(ent) then return nil end
            local et = GetEntityType(ent)
            if et ~= 1 and et ~= 2 and et ~= 3 then return nil end
            local model = GetEntityModel(ent)
            return {
                type = ({ 'ped', 'vehicle', 'object' })[et], model = model,
                name = et == 2 and GetDisplayNameFromVehicleModel(model) or nil,
                plate = et == 2 and GetVehicleNumberPlateText(ent) or nil,
                networked = NetworkGetEntityIsNetworked(ent), x = endc.x, y = endc.y, z = endc.z,
            }
        end)
        if ok then looking = result end
    end
    local nearVeh
    if veh == 0 then
        local nv = GetClosestVehicle(c.x, c.y, c.z, 8.0, 0, 70)
        if nv ~= 0 then nearVeh = { model = GetDisplayNameFromVehicleModel(GetEntityModel(nv)), plate = GetVehicleNumberPlateText(nv), dist = #(GetEntityCoords(nv) - c) } end
    end
    local ft = GetFrameTime()
    return {
        time = ('%02d:%02d'):format(GetClockHours(), GetClockMinutes()), weather = weather,
        looking = looking, nearVehicle = nearVeh,
        inWater = IsEntityInWater(ped), swimming = IsPedSwimming(ped), falling = IsPedFalling(ped), ragdoll = IsPedRagdoll(ped),
        onFoot = IsPedOnFoot(ped), armed = IsPedArmed(ped, 4),
        coords = { x = c.x, y = c.y, z = c.z, h = GetEntityHeading(ped) },
        street = street, cross = cross, zone = zone,
        interior = GetInteriorFromEntity(ped),
        vehicle = vehicle,
        health = GetEntityHealth(ped), armor = GetPedArmour(ped),
        fps = ft > 0 and math.floor(1.0 / ft + 0.5) or 0,
        dead = IsEntityDead(ped),
        res = { GetActiveScreenResolution() },
    }
end

-- ===== UI =====
local function open()
    if isOpen or busy then return end
    busy = true
    local left, reason, canSeverity = serverCall('canReport')
    busy = false
    if left == false then notify(T().failed, 'error') return end
    if left and left > 0 then
        notify((reason == 'cap') and T().capped or T().cooldown:format(left), 'error')
        return
    end
    isOpen = true
    SetNuiFocus(true, true)
    local cats = {}
    for _, c in ipairs(Config.Categories) do cats[#cats + 1] = { id = c.id, label = c[Config.Locale] or c.en } end
    local i = collect()
    SendNUIMessage({
        type = 'open', text = T(), categories = cats, severity = canSeverity == true, allowShot = Config.Attach.screenshot ~= false,
        ctx = {
            pos = ('%.1f, %.1f, %.1f'):format(i.coords.x, i.coords.y, i.coords.z),
            street = (i.street or '') .. (i.cross and (' / ' .. i.cross) or ''),
            zone = i.zone, fps = i.fps, health = i.health, armor = i.armor,
            vehicle = i.vehicle and ((i.vehicle.model or '') .. ' · ' .. (i.vehicle.plate or '')) or nil,
        },
    })
end

local function close()
    isOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ type = 'close' })
end

RegisterCommand(Config.Command, open, false)
RegisterKeyMapping(Config.Command, 'Bug report', 'keyboard', Config.Key)

RegisterNUICallback('close', function(_, cb) close() cb('ok') end)

RegisterNUICallback('retake', function(_, cb)
    cb('ok')
    SendNUIMessage({ type = 'blank', on = true })
    Wait(250) -- let the panel disappear before capturing
    grab(function(d)
        SendNUIMessage({ type = 'blank', on = false })
        SendNUIMessage({ type = 'shot', shot = d and ('data:image/jpeg;base64,' .. stripPrefix(d)) or nil })
        if not d then notify(T().shot_failed, 'error') end
    end)
end)

-- Screenshot transport: ONE latent event (streamed at a fixed rate, no reliable-buffer overflow).
-- The NUI page is https, so a plain-http upload from it is blocked as mixed content.
local shotAck
RegisterNetEvent('ziks-bugreport:shotAck', function(n) shotAck = n end)

local function sendShot(data)
    shotAck = nil
    TriggerLatentServerEvent('ziks-bugreport:shot', 1000000, data)
    local waited = 0
    while shotAck ~= #data do
        Wait(50)
        waited = waited + 50
        if waited > 90000 then dbg('screenshot upload did not finish') return false end
    end
    return true
end

RegisterNUICallback('submit', function(form, cb)
    if type(form) ~= 'table' then cb({ ok = false }) return end
    local info = collect()
    local data = type(form.shotData) == 'string' and stripPrefix(form.shotData) or nil
    if data and #data > Config.Screenshot.maxBytes then dbg(('screenshot too large (%d bytes), skipped'):format(#data)) data = nil end
    local withShot = form.includeShot == true and data ~= nil
    if withShot and not sendShot(data) then
        cb({ ok = false, why = 'screenshot upload failed' })
        return
    end
    local ok, state = serverCall('submit', {
        title = form.title, description = form.description, reproduction = form.reproduction,
        expected = form.expected, actual = form.actual, console = form.console,
        category = form.category, severity = form.severity, shot = withShot,
    }, info)
    if ok then
        notify(state == 'queued' and T().queued or T().sent, 'success')
        close()
    end
    cb({ ok = ok and true or false, why = (not ok) and tostring(state or '') or nil })
end)

AddEventHandler('onResourceStop', function(name)
    if name == GetCurrentResourceName() and isOpen then SetNuiFocus(false, false) end
end)
