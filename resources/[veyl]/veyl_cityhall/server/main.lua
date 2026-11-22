-- veyl_cityhall server: identity documents, licences and the job board.
--
-- A purchase is keyed 'cityhall:<citizenid>:<client op id>':
--   DebitOnce(op)  ->  GiveItem(op..':item') or the licence is set  ->  done
--   if the card could not be delivered, the fee is refunded once with CreditOnce(op..':refund').
-- A repeated request with the same op id never charges twice (the core and the inventory both refuse repeats).

local C = CityHallConfig
local deskPos = vector3(C.Desk.coords.x, C.Desk.coords.y, C.Desk.coords.z)

Veyl.Startup({ 'veyl_core', 'veyl_inventory' }, function()
    exports.veyl_inventory:RegisterUseHandler('cityhall_show', function(ctx) ShowDocument(ctx.source, ctx.item, ctx.metadata) end)
    return true
end)

local function core(name, ...) return Veyl.Await('veyl_core', name, 15000, ...) end
local function inv(name, ...) return Veyl.Await('veyl_inventory', name, 15000, ...) end

local function atDesk(src)
    local pc = Veyl.GetPlayerCoords(src)
    return pc ~= nil and #(pc - deskPos) <= C.UseDistance + 2.0
end

local function licencesOf(src)
    local l = exports.veyl_core:GetMetadata(src, 'licences')
    return type(l) == 'table' and l or {}
end

local function setLicence(src, key, value)
    local l = licencesOf(src)
    l[key] = value == true
    return exports.veyl_core:SetMetadata(src, 'licences', l)
end

local function sorted(map)
    local out = {}
    for key, def in pairs(map) do out[#out + 1] = { key = key, def = def } end
    table.sort(out, function(a, b) return (a.def.order or 99) < (b.def.order or 99) end)
    return out
end

--- What is printed on a card. Only schema keys (veyl_inventory/server/items.lua) are allowed.
local function cardMetadata(pd, item)
    local ci = pd.charinfo or {}
    local meta = { firstname = ci.firstname or '', lastname = ci.lastname or '', citizenid = pd.citizenid, birthdate = ci.birthdate or '' }
    if item == 'identity_card' then return meta end
    meta.issued = os.date('%Y-%m-%d')
    return meta
end

---------------------------------------------------------------------------
-- Desk screen
---------------------------------------------------------------------------
local function overview(src)
    local pd = Veyl.GetPlayerData(src)
    local ci = pd.charinfo or {}
    local held = licencesOf(src)
    local licences, documents, board = {}, {}, {}
    for _, e in ipairs(sorted(C.Licences)) do
        licences[#licences + 1] = { key = e.key, label = e.def.label, description = e.def.description, price = e.def.price, held = held[e.key] == true }
    end
    for _, e in ipairs(sorted(C.Documents)) do
        local req = e.def.requires
        documents[#documents + 1] = {
            key = e.key, label = e.def.label, description = e.def.description, price = e.def.price,
            requires = req, requiresLabel = req and C.Licences[req] and C.Licences[req].label or nil,
            allowed = not req or held[req] == true,
        }
    end
    local jobs = exports.veyl_core:GetJobs()
    for _, j in ipairs(C.JobBoard) do
        local def = jobs[j.job]
        if def then
            local pays = {}
            for g, grade in pairs(def.grades) do pays[#pays + 1] = { grade = tonumber(g), name = grade.name, pay = grade.payment or 0 } end
            table.sort(pays, function(a, b) return a.grade < b.grade end)
            board[#board + 1] = {
                job = j.job, label = def.label, description = j.description, open = def.open == true, apply = j.apply,
                locationLabel = j.locationLabel, hasLocation = j.location ~= nil, grades = pays,
                member = pd.jobs[j.job] ~= nil, current = pd.job.name == j.job,
            }
        end
    end
    return {
        person = {
            firstname = ci.firstname, lastname = ci.lastname, birthdate = ci.birthdate, gender = ci.gender,
            nationality = ci.nationality, phone = ci.phone, citizenid = pd.citizenid,
            job = pd.job.label, grade = pd.job.grade and pd.job.grade.name or nil,
        },
        licences = licences, documents = documents, jobs = board,
        methods = C.PaymentMethods, balances = { cash = pd.money.cash or 0, bank = pd.money.bank or 0 },
    }
end

Veyl.RegisterCallback('overview', function(src)
    if not atDesk(src) then return Veyl.Err('TOO_FAR', 'You need to be at the City Hall desk') end
    return Veyl.Ok(overview(src))
end, { cooldown = 500 })

---------------------------------------------------------------------------
-- Purchases
---------------------------------------------------------------------------
local function validMethod(m)
    for _, x in ipairs(C.PaymentMethods) do if x == m then return true end end
    return false
end

--- buy({ kind = 'licence'|'document', key, method, opId })
Veyl.RegisterCallback('buy', function(src, citizenid, req)
    if type(req) ~= 'table' then return Veyl.Err('INVALID_INPUT', 'Invalid request') end
    local kind, key, method, opId = req.kind, req.key, req.method, req.opId
    if not Veyl.Validate.str(opId, 6, 48, '^[%w%-]+$') then return Veyl.Err('INVALID_INPUT', 'Invalid request') end
    if not validMethod(method) then return Veyl.Err('INVALID_INPUT', 'Choose cash or bank') end
    if not atDesk(src) then return Veyl.Err('TOO_FAR', 'You need to be at the City Hall desk') end
    local held = licencesOf(src)
    local def, reason
    if kind == 'licence' then
        def = C.Licences[key]
        if not def then return Veyl.Err('NOT_FOUND', 'Unknown licence') end
        if held[key] then return Veyl.Err('INVALID_STATE', 'You already hold this licence') end
        if not def.price then return Veyl.Err('NO_PERMISSION', 'City Hall cannot issue this licence') end
        reason = 'City Hall: ' .. def.label
    elseif kind == 'document' then
        def = C.Documents[key]
        if not def then return Veyl.Err('NOT_FOUND', 'Unknown document') end
        if def.requires and not held[def.requires] then
            return Veyl.Err('NO_PERMISSION', ('You need a %s first'):format((C.Licences[def.requires] or {}).label or def.requires))
        end
        reason = 'City Hall: ' .. def.label
    else
        return Veyl.Err('INVALID_INPUT', 'Invalid request')
    end

    local pd = Veyl.GetPlayerData(src)
    local op = ('cityhall:%s:%s'):format(citizenid, opId)
    local meta = kind == 'document' and cardMetadata(pd, key) or nil
    if kind == 'document' then
        local fit = inv('CanCarry', citizenid, key, 1, meta)
        if not fit.ok then return Veyl.Err(fit.code or 'INVENTORY_FULL', 'Make room in your pockets first') end
    end

    local price = math.floor(tonumber(def.price) or 0)
    if price > 0 then
        local paid = core('DebitOnce', citizenid, method, price, reason, op)
        if not paid.ok and paid.code ~= 'DUPLICATE_OPERATION' then
            if paid.code == 'INSUFFICIENT_FUNDS' then return Veyl.Err('INSUFFICIENT_FUNDS', ('Not enough %s'):format(method == 'bank' and 'in the bank' or 'cash')) end
            return Veyl.Err(paid.code or 'INTERNAL', paid.message or 'Payment failed')
        end
    end

    if kind == 'document' then
        local given = inv('GiveItem', citizenid, key, 1, meta, op .. ':item')
        if not given.ok and given.code ~= 'DUPLICATE_OPERATION' then
            if price > 0 then core('CreditOnce', citizenid, method, price, reason .. ' (refund)', op .. ':refund') end
            return Veyl.Err(given.code or 'INTERNAL', 'The card could not be printed. You were refunded.')
        end
    else
        if not setLicence(src, key, true) then
            if price > 0 then core('CreditOnce', citizenid, method, price, reason .. ' (refund)', op .. ':refund') end
            return Veyl.Err('INTERNAL', 'The licence could not be issued. You were refunded.')
        end
    end
    Veyl.Audit(src, 'cityhall_buy', { kind = kind, key = key, price = price, method = method, op = op })
    return Veyl.Ok(overview(src), kind == 'document' and (def.label .. ' printed') or (def.label .. ' issued'))
end, { cooldown = 1500 })

---------------------------------------------------------------------------
-- Job board
---------------------------------------------------------------------------
local function boardEntry(job)
    for _, j in ipairs(C.JobBoard) do if j.job == job then return j end end
    return nil
end

Veyl.RegisterCallback('takeJob', function(src, citizenid, job)
    local entry = type(job) == 'string' and boardEntry(job)
    local def = entry and exports.veyl_core:GetJob(job)
    if not def then return Veyl.Err('NOT_FOUND', 'Unknown job') end
    if not atDesk(src) then return Veyl.Err('TOO_FAR', 'You need to be at the City Hall desk') end
    if not def.open then return Veyl.Err('NO_PERMISSION', entry.apply or 'This job takes applications') end
    local pd = Veyl.GetPlayerData(src)
    if pd.job.name == job then return Veyl.Err('INVALID_STATE', 'You already work here') end
    if pd.jobs[job] ~= nil then
        exports.veyl_core:SetPlayerPrimaryJob(citizenid, job)
    elseif pd.job.name == 'unemployed' then
        if not exports.veyl_core:SetJob(src, job, 0) then return Veyl.Err('INTERNAL', 'Could not sign you on') end
    else
        -- Keep the current job as a membership and add this one as the new primary.
        if not exports.veyl_core:AddPlayerToJob(citizenid, job, 0) then return Veyl.Err('INTERNAL', 'Could not sign you on') end
        exports.veyl_core:SetPlayerPrimaryJob(citizenid, job)
    end
    Veyl.Audit(src, 'cityhall_take_job', { job = job })
    return Veyl.Ok(overview(src), ('You now work for %s'):format(def.label))
end, { cooldown = 2000 })

Veyl.RegisterCallback('jobLocation', function(_, _, job)
    local entry = type(job) == 'string' and boardEntry(job)
    if not entry or not entry.location then return Veyl.Err('NOT_FOUND', 'No location for this job') end
    return Veyl.Ok({ x = entry.location.x, y = entry.location.y, label = entry.locationLabel })
end, { cooldown = 500 })

---------------------------------------------------------------------------
-- Showing a card (inventory "use")
---------------------------------------------------------------------------
local TITLES = { identity_card = 'Identity card', driver_license = "Driver's licence", weapon_license = 'Weapon licence' }

function ShowDocument(src, item, meta)
    if not TITLES[item] or type(meta) ~= 'table' then return end
    local pc = Veyl.GetPlayerCoords(src)
    if not pc then return end
    local card = {
        kind = item, title = TITLES[item], firstname = meta.firstname, lastname = meta.lastname,
        birthdate = meta.birthdate, citizenid = meta.citizenid, issued = meta.issued,
    }
    local shownTo = 0
    for _, s in ipairs(GetPlayers()) do
        s = tonumber(s)
        local p = s ~= src and Veyl.GetPlayerCoords(s)
        if p and #(p - pc) <= C.ShowDistance then
            TriggerClientEvent('veyl_cityhall:showCard', s, card, C.ShowSeconds)
            shownTo = shownTo + 1
        end
    end
    card.self = true
    TriggerClientEvent('veyl_cityhall:showCard', src, card, C.ShowSeconds)
    TriggerClientEvent('veyl_cityhall:shown', src, shownTo)
end

---------------------------------------------------------------------------
-- /licence <server id> <licence> <on|off>: staff, or the groups in GrantGroups for that licence
---------------------------------------------------------------------------
local function mayGrant(src, key)
    if src == 0 or Veyl.HasPermission(src, 'cityhall.manage') or Veyl.HasPermission(src, 'admin') then return true end
    local filter = C.GrantGroups[key]
    if not filter then return false end
    local pd = Veyl.GetPlayerData(src)
    if not pd or not pd.job.onduty then return false end
    local min = filter[pd.job.name]
    return min ~= nil and (pd.job.grade and pd.job.grade.level or 0) >= min
end

RegisterCommand('licence', function(src, args)
    local function reply(msg, kind)
        if src == 0 then print('[veyl_cityhall] ' .. msg) else Veyl.Notify(src, msg, kind or 'info') end
    end
    local target, key, state = tonumber(args[1]), args[2], args[3]
    if not target or not C.Licences[key or ''] or (state ~= 'on' and state ~= 'off') then
        local keys = {}
        for k in pairs(C.Licences) do keys[#keys + 1] = k end
        return reply(('Usage: /licence <id> <%s> <on|off>'):format(table.concat(keys, '|')), 'error')
    end
    if not mayGrant(src, key) then return reply('You cannot change this licence.', 'error') end
    local tpd = Veyl.GetPlayerData(target)
    if not tpd then return reply('No character with that id is online.', 'error') end
    if src ~= 0 and target ~= src then
        local a, b = Veyl.GetPlayerCoords(src), Veyl.GetPlayerCoords(target)
        if not (Veyl.HasPermission(src, 'cityhall.manage') or Veyl.HasPermission(src, 'admin')) and (not a or not b or #(a - b) > 10.0) then
            return reply('Stand near the person.', 'error')
        end
    end
    if not setLicence(target, key, state == 'on') then return reply('Could not update the licence.', 'error') end
    local label = C.Licences[key].label
    local name = ('%s %s'):format(tpd.charinfo.firstname or '', tpd.charinfo.lastname or '')
    reply(('%s %s for %s'):format(label, state == 'on' and 'granted' or 'revoked', name), 'success')
    Veyl.Notify(target, ('Your %s was %s.'):format(label:lower(), state == 'on' and 'granted' or 'revoked'), state == 'on' and 'success' or 'warning')
    Veyl.Audit(src, 'cityhall_licence', { target = tpd.citizenid, licence = key, state = state })
end, false)
