-- veyl_police server: cuffs, escort, vehicles, searches, citations and impound. Every action is re-checked here:
-- the officer must be on duty, close enough, and the target in the right state.
--
-- Restraint state: core metadata 'ishandcuffed' (persists across logout) mirrored to the replicated player state bag
-- 'cuffed'. Escorting: state bag 'escortedBy' (the officer's server id).

-- Mail to the phone (veyl_phone SendMail); skipped when the phone is not running.
local function mail(cid, from, subject, body) if GetResourceState('veyl_phone') == 'started' then pcall(function() exports.veyl_phone:SendMail(cid, from, subject, body) end) end end
local C = PoliceConfig
local escorts = {} -- [target] = officer

local function core(name, ...) return Veyl.Await('veyl_core', name, 15000, ...) end

Veyl.Startup({ 'veyl_core', 'veyl_inventory' }, function()
    local ok = Veyl.Migrate({
        { id = '001_citations', sql = {
            [[CREATE TABLE IF NOT EXISTS veyl_police_citations (
                id INT UNSIGNED NOT NULL AUTO_INCREMENT,
                citizenid VARCHAR(16) NOT NULL,
                officer_cid VARCHAR(16) NOT NULL,
                officer_name VARCHAR(64) NOT NULL,
                amount INT UNSIGNED NOT NULL,
                reason VARCHAR(160) NOT NULL,
                status ENUM('unpaid','paid','void') NOT NULL DEFAULT 'unpaid',
                created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
                paid_at TIMESTAMP NULL,
                PRIMARY KEY (id),
                KEY idx_cid (citizenid, status)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
        } },
    })
    if not ok then return false end
    -- Resource restart: put restraint state back on the state bags.
    for _, s in ipairs(GetPlayers()) do
        s = tonumber(s)
        local pd = Veyl.GetPlayerData(s)
        if pd and pd.metadata.ishandcuffed then Player(s).state:set('cuffed', true, true) end
    end
    return true
end)

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function isOfficer(src)
    local pd = Veyl.GetPlayerData(src)
    if not pd or not pd.job.onduty then return false end
    for _, j in ipairs(C.Jobs) do if pd.job.name == j then return true, pd end end
    return false
end

local function near(a, b, dist)
    local pa, pb = Veyl.GetPlayerCoords(a), Veyl.GetPlayerCoords(b)
    return pa ~= nil and pb ~= nil and #(pa - pb) <= (dist or C.ActionDistance) + 1.0
end

local function name(pd)
    return pd and ('%s %s'):format(pd.charinfo.firstname or '', pd.charinfo.lastname or '') or 'Unknown'
end

local function isCuffed(src) return Player(src).state.cuffed == true end
local function isDown(src) return Player(src).state.medical ~= nil end

local function setCuffed(src, on)
    Player(src).state:set('cuffed', on or nil, true)
    exports.veyl_core:SetMetadata(src, 'ishandcuffed', on == true)
    if not on and escorts[src] then
        escorts[src] = nil
        Player(src).state:set('escortedBy', nil, true)
    end
end

--- Common checks for an officer acting on a player. Returns officer pd, target pd or nil, err.
local function officerOn(src, target)
    local ok, pd = isOfficer(src)
    if not ok then return nil, nil, Veyl.Err('NO_PERMISSION', 'You need to be an on-duty officer') end
    target = tonumber(target)
    local tpd = target and target ~= src and Veyl.GetPlayerData(target)
    if not tpd then return nil, nil, Veyl.Err('NOT_FOUND', 'Nobody there') end
    if not near(src, target) then return nil, nil, Veyl.Err('TOO_FAR', 'Move closer') end
    return pd, tpd
end

---------------------------------------------------------------------------
-- Cuffs
---------------------------------------------------------------------------
Veyl.RegisterCallback('cuff', function(src, _, target)
    local pd, tpd, err = officerOn(src, target)
    if not pd then return err end
    target = tonumber(target)
    if isCuffed(target) then return Veyl.Err('INVALID_STATE', 'Already cuffed') end
    if GetVehiclePedIsIn(GetPlayerPed(target), false) ~= 0 then return Veyl.Err('INVALID_STATE', 'Get them out of the vehicle first') end
    TriggerClientEvent('veyl_police:cuffAnim', target, src, C.CuffSeconds)
    SetTimeout(math.floor(C.CuffSeconds * 1000), function()
        if GetPlayerName(target) and not isCuffed(target) then
            setCuffed(target, true)
            Veyl.Notify(target, 'You have been handcuffed.', 'warning')
        end
    end)
    Veyl.Audit(src, 'police_cuff', { target = tpd.citizenid })
    return Veyl.Ok({ seconds = C.CuffSeconds }, ('You cuffed %s'):format(name(tpd)))
end, { cooldown = 1500 })

Veyl.RegisterCallback('uncuff', function(src, _, target)
    local pd, tpd, err = officerOn(src, target)
    if not pd then return err end
    target = tonumber(target)
    if not isCuffed(target) then return Veyl.Err('INVALID_STATE', 'They are not cuffed') end
    setCuffed(target, false)
    Veyl.Notify(target, 'Your handcuffs were removed.', 'success')
    Veyl.Audit(src, 'police_uncuff', { target = tpd.citizenid })
    return Veyl.Ok(nil, 'Handcuffs removed')
end, { cooldown = 1000 })

---------------------------------------------------------------------------
-- Escort and vehicles
---------------------------------------------------------------------------
Veyl.RegisterCallback('escort', function(src, _, target)
    local pd, tpd, err = officerOn(src, target)
    if not pd then return err end
    target = tonumber(target)
    if escorts[target] == src then
        escorts[target] = nil
        Player(target).state:set('escortedBy', nil, true)
        return Veyl.Ok({ escorting = false }, 'You let go')
    end
    if not isCuffed(target) and not isDown(target) then return Veyl.Err('INVALID_STATE', 'They need to be cuffed or down') end
    if escorts[target] then return Veyl.Err('INVALID_STATE', 'Someone else is escorting them') end
    for t, o in pairs(escorts) do if o == src then escorts[t] = nil Player(t).state:set('escortedBy', nil, true) end end
    escorts[target] = src
    Player(target).state:set('escortedBy', src, true)
    return Veyl.Ok({ escorting = true }, ('Escorting %s'):format(name(tpd)))
end, { cooldown = 800 })

local function vehicleNear(src, netId)
    local veh = NetworkGetEntityFromNetworkId(tonumber(netId) or 0)
    if not veh or veh == 0 or not DoesEntityExist(veh) or GetEntityType(veh) ~= 2 then return nil end
    local pc = Veyl.GetPlayerCoords(src)
    if not pc or #(pc - GetEntityCoords(veh)) > 6.0 then return nil end
    return veh
end

Veyl.RegisterCallback('putInVehicle', function(src, _, netId)
    if not isOfficer(src) then return Veyl.Err('NO_PERMISSION', 'You need to be an on-duty officer') end
    local veh = vehicleNear(src, netId)
    if not veh then return Veyl.Err('TOO_FAR', 'Stand next to the vehicle') end
    local target
    for t, o in pairs(escorts) do if o == src then target = t end end
    if not target then return Veyl.Err('INVALID_STATE', 'Escort someone first') end
    escorts[target] = nil
    Player(target).state:set('escortedBy', nil, true)
    TriggerClientEvent('veyl_police:enterVehicle', target, netId)
    return Veyl.Ok(nil, 'Placed in the vehicle')
end, { cooldown = 1000 })

Veyl.RegisterCallback('takeOut', function(src, _, netId)
    if not isOfficer(src) then return Veyl.Err('NO_PERMISSION', 'You need to be an on-duty officer') end
    local veh = vehicleNear(src, netId)
    if not veh then return Veyl.Err('TOO_FAR', 'Stand next to the vehicle') end
    local n = 0
    for _, s in ipairs(GetPlayers()) do
        s = tonumber(s)
        if (isCuffed(s) or isDown(s)) and GetVehiclePedIsIn(GetPlayerPed(s), false) == veh then
            TriggerClientEvent('veyl_police:leaveVehicle', s)
            n = n + 1
        end
    end
    if n == 0 then return Veyl.Err('NOT_FOUND', 'Nobody restrained in this vehicle') end
    return Veyl.Ok(nil, 'Taken out of the vehicle')
end, { cooldown = 1000 })

---------------------------------------------------------------------------
-- Search: the target's pockets open beside the officer's (a stash pointing at their inventory)
---------------------------------------------------------------------------
local searching = {} -- [officer src] = target src

local function searchAllowed(src, target)
    if not isOfficer(src) or not target or not GetPlayerName(target) then return false end
    if not near(src, target) then return false end
    if C.SearchRequires == 'cuffed_or_down' and not isCuffed(target) and not isDown(target) then return false end
    return true
end

Veyl.RegisterCallback('search', function(src, _, target)
    local pd, tpd, err = officerOn(src, target)
    if not pd then return err end
    target = tonumber(target)
    if not searchAllowed(src, target) then return Veyl.Err('INVALID_STATE', 'They need to be cuffed or down') end
    local id = ('police_search_%s'):format(tpd.citizenid)
    exports.veyl_inventory:RegisterStash({
        id = id, label = ('Search: %s'):format(name(tpd)), slots = 50, maxWeight = 120000,
        inventory = 'player:' .. tpd.citizenid, authorize = { resource = GetCurrentResourceName(), export = 'AuthorizeSearch' },
    })
    searching[src] = target
    Veyl.Notify(target, 'You are being searched.', 'warning')
    Veyl.Audit(src, 'police_search', { target = tpd.citizenid })
    return Veyl.Ok({ stash = id })
end, { cooldown = 1500 })

-- Called by veyl_inventory on every open and every move while the search is on screen.
exports('AuthorizeSearch', function(src, _, stashId)
    local target = searching[src]
    if not target then return false, 'NO_PERMISSION' end
    local tcid = Veyl.GetCitizenId(target)
    if not tcid or stashId ~= ('police_search_%s'):format(tcid) then return false, 'NO_PERMISSION' end
    if not searchAllowed(src, target) then return false, 'TOO_FAR' end
    return true
end)

---------------------------------------------------------------------------
-- Citations
---------------------------------------------------------------------------
Veyl.RegisterCallback('cite', function(src, _, target, amount, reason)
    local pd, tpd, err = officerOn(src, target)
    if not pd then return err end
    amount = math.floor(tonumber(amount) or 0)
    if amount < 1 or amount > C.Citations.Max then return Veyl.Err('INVALID_INPUT', ('Amount must be $1 - $%d'):format(C.Citations.Max)) end
    if type(reason) ~= 'string' then return Veyl.Err('INVALID_INPUT', 'Give a reason') end
    reason = reason:gsub('[%c]', ''):sub(1, 160)
    if #reason < 3 then return Veyl.Err('INVALID_INPUT', 'Give a reason') end
    local id = MySQL.insert.await('INSERT INTO veyl_police_citations (citizenid, officer_cid, officer_name, amount, reason) VALUES (?, ?, ?, ?, ?)',
        { tpd.citizenid, pd.citizenid, name(pd), amount, reason })
    if not id then return Veyl.Err('DATABASE_ERROR', 'Could not write the citation') end
    local paid = false
    if C.Citations.ChargeImmediately then
        local r = core('DebitOnce', tpd.citizenid, 'bank', amount, ('Citation #%d: %s'):format(id, reason), 'citation:' .. id)
        if r.ok or r.code == 'DUPLICATE_OPERATION' then
            MySQL.update.await("UPDATE veyl_police_citations SET status = 'paid', paid_at = NOW() WHERE id = ?", { id })
            paid = true
        end
    end
    Veyl.Notify(tonumber(target), paid and ('Citation #%d: $%d for %s. Paid from your bank.'):format(id, amount, reason)
        or ('Citation #%d: $%d for %s. Unpaid: use /citations to pay.'):format(id, amount, reason), 'warning', 9000)
    Veyl.Audit(src, 'police_citation', { id = id, target = tpd.citizenid, amount = amount, paid = paid })
    mail(tpd.citizenid, 'Los Santos Police Department', ('Citation #%d: $%d'):format(id, amount), ('You were cited for: %s\nAmount: $%d\nOfficer: %s\nStatus: %s'):format(reason, amount, name(pd), paid and 'paid from your bank' or 'unpaid (use /citations to pay)'))
    return Veyl.Ok({ id = id, paid = paid }, ('Citation #%d written (%s)'):format(id, paid and 'paid' or 'unpaid'))
end, { cooldown = 2000 })

Veyl.RegisterCallback('myCitations', function(_, citizenid)
    return Veyl.Ok(MySQL.query.await([[SELECT id, amount, reason, officer_name, UNIX_TIMESTAMP(created_at) AS at FROM veyl_police_citations
        WHERE citizenid = ? AND status = 'unpaid' ORDER BY id]], { citizenid }) or {})
end, { cooldown = 1000 })

Veyl.RegisterCallback('payCitation', function(src, citizenid, id, method)
    id = tonumber(id)
    method = method == 'cash' and 'cash' or 'bank'
    local row = id and MySQL.single.await("SELECT * FROM veyl_police_citations WHERE id = ? AND citizenid = ? AND status = 'unpaid'", { id, citizenid })
    if not row then return Veyl.Err('NOT_FOUND', 'No unpaid citation with that number') end
    local r = core('DebitOnce', citizenid, method, row.amount, ('Citation #%d: %s'):format(id, row.reason), 'citation:' .. id)
    if not r.ok and r.code ~= 'DUPLICATE_OPERATION' then
        return Veyl.Err(r.code or 'INSUFFICIENT_FUNDS', r.code == 'INSUFFICIENT_FUNDS' and 'Not enough money' or (r.message or 'Payment failed'))
    end
    MySQL.update.await("UPDATE veyl_police_citations SET status = 'paid', paid_at = NOW() WHERE id = ?", { id })
    Veyl.Audit(src, 'police_citation_paid', { id = id, method = method })
    return Veyl.Ok(nil, ('Citation #%d paid'):format(id))
end, { cooldown = 1500 })

exports('GetCitations', function(citizenid, limit)
    return MySQL.query.await([[SELECT id, amount, reason, officer_name, status, UNIX_TIMESTAMP(created_at) AS at FROM veyl_police_citations
        WHERE citizenid = ? ORDER BY id DESC LIMIT ?]], { citizenid, tonumber(limit) or 50 }) or {}
end)

---------------------------------------------------------------------------
-- Impound
---------------------------------------------------------------------------
local impounding = {} -- [src] = { netId, at, token }

Veyl.RegisterCallback('impoundStart', function(src, _, netId)
    if not isOfficer(src) then return Veyl.Err('NO_PERMISSION', 'You need to be an on-duty officer') end
    local veh = vehicleNear(src, netId)
    if not veh then return Veyl.Err('TOO_FAR', 'Stand next to the vehicle') end
    if GetPedInVehicleSeat(veh, -1) ~= 0 then return Veyl.Err('INVALID_STATE', 'Someone is driving it') end
    local token = Veyl.NewId()
    impounding[src] = { netId = netId, at = GetGameTimer(), token = token }
    return Veyl.Ok({ token = token, seconds = C.ImpoundSeconds })
end, { cooldown = 1000 })

Veyl.RegisterCallback('impoundFinish', function(src, _, token)
    local j = impounding[src]
    impounding[src] = nil
    if not j or j.token ~= token then return Veyl.Err('INVALID_STATE', 'Start again') end
    if GetGameTimer() - j.at < C.ImpoundSeconds * 1000 - 600 then return Veyl.Err('TOO_FAST', 'You stopped too early') end
    if not isOfficer(src) then return Veyl.Err('NO_PERMISSION', 'You need to be an on-duty officer') end
    local veh = vehicleNear(src, j.netId)
    if not veh then return Veyl.Err('TOO_FAR', 'Stand next to the vehicle') end
    for seat = -1, 6 do
        local ped = GetPedInVehicleSeat(veh, seat)
        if ped ~= 0 and IsPedAPlayer(ped) then return Veyl.Err('INVALID_STATE', 'The vehicle must be empty') end
    end
    local plate = GetVehicleNumberPlateText(veh)
    local owned = exports.veyl_vehicles:GetOwnedVehicleIdFromEntity(veh)
    if owned then
        exports.veyl_vehicles:ImpoundOwnedVehicle(owned, 'police', C.ImpoundFee)
    else
        local vid = exports.veyl_vehicles:GetVehicleIdFromEntity(veh)
        if vid then exports.veyl_vehicles:DeleteVehicle(vid) else DeleteEntity(veh) end
    end
    Veyl.Audit(src, 'police_impound', { plate = plate, owned = owned })
    return Veyl.Ok(nil, owned and ('%s sent to the impound lot ($%d to release)'):format(plate, C.ImpoundFee) or ('%s removed'):format(plate))
end, { cooldown = 1000 })

---------------------------------------------------------------------------
-- Staff: /uncuff <id>
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- Gunshot residue: the client reports firing; officers can test anyone close
---------------------------------------------------------------------------
local lastShot = {} -- [src] = os.time()
RegisterNetEvent('veyl_police:fired', function()
    local src = source
    if Player(src).state.medical then return end
    lastShot[src] = os.time()
end)

Veyl.RegisterCallback('gsr', function(src, _, target)
    local pd, tpd, err = officerOn(src, target)
    if not pd then return err end
    target = tonumber(target)
    local positive = lastShot[target] and os.time() - lastShot[target] <= C.GsrMinutes * 60
    Veyl.Audit(src, 'police_gsr', { target = tpd.citizenid, positive = positive == true })
    return Veyl.Ok({ positive = positive == true }, positive and ('GSR POSITIVE: %s fired a weapon recently'):format(name(tpd))
        or ('GSR negative for %s'):format(name(tpd)))
end, { cooldown = 3000 })

-- Washing (swimming) clears residue.
RegisterNetEvent('veyl_police:washed', function() lastShot[source] = nil end)

---------------------------------------------------------------------------
-- Check ID: the officer's MDT opens on this person
---------------------------------------------------------------------------
Veyl.RegisterCallback('identify', function(src, _, target)
    local pd, tpd, err = officerOn(src, target)
    if not pd then return err end
    target = tonumber(target)
    if C.IdentifyRequires == 'cuffed_or_down' and not isCuffed(target) and not isDown(target) then
        return Veyl.Err('INVALID_STATE', 'Ask for their ID, or detain them first')
    end
    Veyl.Audit(src, 'police_identify', { target = tpd.citizenid })
    return Veyl.Ok({ citizenid = tpd.citizenid, name = name(tpd) })
end, { cooldown = 1500 })

--- RecordCitation(officerSrc, citizenid, amount, reason) -> Veyl.Ok({ id, paid }) / Veyl.Err. Used by the MDT;
--- works for people who are not in the city (charged when the bank covers it, otherwise left unpaid).
exports('RecordCitation', function(officerSrc, citizenid, amount, reason)
    local ok, pd = isOfficer(officerSrc)
    if not ok then return Veyl.Err('NO_PERMISSION', 'You need to be an on-duty officer') end
    amount = math.floor(tonumber(amount) or 0)
    if amount < 1 or amount > C.Citations.Max then return Veyl.Err('INVALID_INPUT', ('Amount must be $1 - $%d'):format(C.Citations.Max)) end
    reason = type(reason) == 'string' and reason:gsub('[%c]', ''):sub(1, 160) or ''
    if #reason < 3 then return Veyl.Err('INVALID_INPUT', 'Give a reason') end
    if not MySQL.scalar.await('SELECT 1 FROM veyl_players WHERE citizenid = ?', { citizenid }) then return Veyl.Err('NOT_FOUND', 'Unknown person') end
    local id = MySQL.insert.await('INSERT INTO veyl_police_citations (citizenid, officer_cid, officer_name, amount, reason) VALUES (?, ?, ?, ?, ?)',
        { citizenid, pd.citizenid, name(pd), amount, reason })
    local paid = false
    if C.Citations.ChargeImmediately then
        local r = core('DebitOnce', citizenid, 'bank', amount, ('Citation #%d: %s'):format(id, reason), 'citation:' .. id)
        if r.ok or r.code == 'DUPLICATE_OPERATION' then
            MySQL.update.await("UPDATE veyl_police_citations SET status = 'paid', paid_at = NOW() WHERE id = ?", { id })
            paid = true
        end
    end
    local tsrc = exports.veyl_core:GetSourceByCitizenId(citizenid)
    if tsrc then Veyl.Notify(tsrc, ('Citation #%d: $%d for %s. %s'):format(id, amount, reason, paid and 'Paid from your bank.' or 'Unpaid: use /citations to pay.'), 'warning', 9000) end
    Veyl.Audit(officerSrc, 'police_citation', { id = id, target = citizenid, amount = amount, paid = paid, via = 'mdt' })
    mail(citizenid, 'Los Santos Police Department', ('Citation #%d: $%d'):format(id, amount), ('You were cited for: %s\nAmount: $%d\nOfficer: %s\nStatus: %s'):format(reason, amount, name(pd), paid and 'paid from your bank' or 'unpaid (use /citations to pay)'))
    return Veyl.Ok({ id = id, paid = paid }, ('Citation #%d written (%s)'):format(id, paid and 'paid' or 'unpaid'))
end)

RegisterCommand(C.UnCuffCommand, function(src, args)
    if src ~= 0 and not (Veyl.HasPermission(src, 'police.manage') or Veyl.HasPermission(src, 'admin')) then
        return Veyl.Notify(src, 'You do not have permission to use this command.', 'error')
    end
    local t = tonumber(args[1])
    if not t or not Veyl.GetCitizenId(t) then
        if src == 0 then print('Usage: uncuff <id>') else Veyl.Notify(src, 'Usage: /uncuff <id>', 'error') end
        return
    end
    setCuffed(t, false)
    Veyl.Notify(t, 'Your handcuffs were removed.', 'success')
    Veyl.Audit(src, 'police_staff_uncuff', { target = Veyl.GetCitizenId(t) })
end, false)

---------------------------------------------------------------------------
-- Housekeeping
---------------------------------------------------------------------------
AddEventHandler('VeylCore:Server:PlayerLoaded', function(src)
    src = tonumber(src)
    local pd = src and Veyl.GetPlayerData(src)
    if pd and pd.metadata.ishandcuffed then Player(src).state:set('cuffed', true, true) end
end)

AddEventHandler('playerDropped', function()
    local src = source
    escorts[src], searching[src], impounding[src] = nil, nil, nil
    for t, o in pairs(escorts) do if o == src then escorts[t] = nil Player(t).state:set('escortedBy', nil, true) end end
end)

exports('IsCuffed', function(src) return isCuffed(tonumber(src)) end)
exports('SetCuffed', function(src, on) setCuffed(tonumber(src), on == true) return true end)
