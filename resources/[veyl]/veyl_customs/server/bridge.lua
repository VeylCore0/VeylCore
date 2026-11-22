-- veyl_customs server adapters: every call into other VeylCore resources goes through here (see docs/CUSTOMS.md,
-- "Integration inventory"). Nothing outside this file names another resource's exports.

Bridge = {}

local function await(res, name, ...) return Veyl.Await(res, name, 15000, ...) end

-- Money (veyl_core durable money: idempotent by operation id) -------------------------------------------------
function Bridge.Debit(citizenid, method, amount, reason, opId) return await('veyl_core', 'DebitOnce', citizenid, method, amount, reason, opId) end
function Bridge.Credit(citizenid, method, amount, reason, opId) return await('veyl_core', 'CreditOnce', citizenid, method, amount, reason, opId) end

-- Vehicles (veyl_vehicles: owned rows, saved looks, live entities) -------------------------------------------
function Bridge.OwnedIdFromEntity(entity) return exports.veyl_vehicles:GetOwnedVehicleIdFromEntity(entity) end
function Bridge.GetOwnedProps(ownedId) return await('veyl_vehicles', 'GetOwnedProps', ownedId) end
function Bridge.ApplyOwnedProps(ownedId, props, expectedVersion) return await('veyl_vehicles', 'ApplyOwnedProps', ownedId, props, expectedVersion) end

-- Business accounts (veyl_business; optional) -----------------------------------------------------------------
local function bizUp() return GetResourceState('veyl_business') == 'started' end
function Bridge.BusinessCredit(id, amount, reason, actor)
    if not id or not bizUp() or amount <= 0 then return Veyl.Ok() end
    return await('veyl_business', 'CreditAccount', id, amount, reason, actor)
end
function Bridge.BusinessDebit(id, amount, reason, actor)
    if not id or not bizUp() then return Veyl.Err('UNAVAILABLE', 'This shop has no business account') end
    return await('veyl_business', 'DebitAccount', id, amount, reason, actor)
end

-- Players and jobs (veyl_core) ----------------------------------------------------------------------------------
function Bridge.Player(src) return Veyl.GetPlayerData(src) end
function Bridge.Name(pd) return pd and pd.charinfo and ('%s %s'):format(pd.charinfo.firstname or '', pd.charinfo.lastname or '') or 'Unknown' end
function Bridge.JobDef(job) return exports.veyl_core:GetJob(job) end
function Bridge.IsBossGrade(job, grade) return exports.veyl_core:IsGradeBoss(job, grade) end

--- Staff info of src for a shop: { grade, onduty, manager } or nil.
function Bridge.Staff(src, shop)
    if not shop.job then return nil end
    local pd = Veyl.GetPlayerData(src)
    local g = pd and pd.jobs and pd.jobs[shop.job]
    if g == nil then return nil end
    return { grade = g, onduty = pd.job.name == shop.job and pd.job.onduty == true,
             manager = g >= (shop.manageGrade or 99) or Bridge.IsBossGrade(shop.job, g) }
end

-- Notifications and metadata -----------------------------------------------------------------------------------
function Bridge.Notify(src, msg, kind) if src and GetPlayerName(src) then Veyl.Notify(src, msg, kind or 'info') end end
function Bridge.GetMeta(src, key) return exports.veyl_core:GetMetadata(src, key) end
function Bridge.SetMeta(src, key, value) return exports.veyl_core:SetMetadata(src, key, value) end
function Bridge.SrcByCitizen(citizenid)
    for _, s in ipairs(GetPlayers()) do
        local id = tonumber(s)
        if Veyl.GetCitizenId(id) == citizenid then return id end
    end
end
