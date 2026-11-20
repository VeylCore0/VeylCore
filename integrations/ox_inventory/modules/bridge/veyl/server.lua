-- ox_inventory framework bridge for VeylCore (server). Install to ox_inventory/modules/bridge/veyl/
-- and set:  setr inventory:framework "veyl"  and  set inventory:accounts "[]"
-- Written against ox_inventory v2.48.1. Money stays numeric in veyl_core: no money items, no sync loop.

local Inventory = require 'modules.inventory.server'
local db = require 'modules.mysql.server'

local VEYL = exports.veyl_core

-- ox reads the player and vehicle tables at setup: wait (bounded) for the VeylCore services that own them.
local function waitReady(resource, timeoutMs)
    local deadline = GetGameTimer() + timeoutMs
    while GetResourceState(resource) ~= 'started' or GlobalState['veyl:ready:' .. resource] ~= true do
        if GetGameTimer() > deadline then
            error(('ox_inventory (veyl bridge): %s did not become ready within %ds'):format(resource, timeoutMs / 1000), 0)
        end
        Wait(100)
    end
end

waitReady('veyl_core', 60000)
waitReady('veyl_vehicles', 60000)

db.setup({
    user = { table = 'veyl_players', col = 'citizenid' },
    vehicle = { table = 'veyl_player_vehicles', col = 'id' },
})

local function setupPlayer(playerData)
    if not playerData or not playerData.citizenid then return end
    server.setPlayerInventory({
        source = playerData.source,
        identifier = playerData.citizenid,
        name = ('%s %s'):format(playerData.charinfo.firstname or '', playerData.charinfo.lastname or ''),
        charinfo = playerData.charinfo,
    })
end

AddEventHandler('VeylCore:Server:PlayerLoaded', function(src)
    setupPlayer(VEYL:GetPlayerData(src))
end)

AddEventHandler('VeylCore:Server:OnPlayerUnload', function(src)
    server.playerDropped(src)
end)

AddEventHandler('VeylCore:Server:OnGroupUpdate', function(src, groupName, groupGrade)
    local inventory = Inventory(src)
    if not inventory or not inventory.player then return end
    inventory.player.groups[groupName] = groupGrade or nil
end)

-- ox_inventory restarted while players are online.
SetTimeout(500, function()
    for _, playerData in ipairs(VEYL:GetPlayersData()) do setupPlayer(playerData) end
end)

---@diagnostic disable-next-line: duplicate-set-field
function server.setPlayerData(player)
    local charinfo = player.charinfo or {}
    return {
        source = player.source,
        name = player.name,
        groups = VEYL:GetGroups(player.source),
        sex = charinfo.gender,
        dateofbirth = charinfo.birthdate,
    }
end

---@diagnostic disable-next-line: duplicate-set-field
function server.hasLicense(inv, license)
    local licences = VEYL:GetMetadata(inv.id, 'licences')
    return type(licences) == 'table' and licences[license] == true
end

---@diagnostic disable-next-line: duplicate-set-field
function server.buyLicense(inv, license)
    local licences = VEYL:GetMetadata(inv.id, 'licences')
    if type(licences) ~= 'table' then return false end
    if licences[license.name] then return false, 'already_have' end
    -- Payment goes through the core money service (cash), never a money item.
    if not VEYL:RemoveMoney(inv.id, 'cash', license.price, ('License: %s'):format(license.name)) then
        return false, 'can_not_afford'
    end
    licences[license.name] = true
    VEYL:SetMetadata(inv.id, 'licences', licences)
    return true, 'have_purchased'
end

---@diagnostic disable-next-line: duplicate-set-field
function server.isPlayerBoss(_, group, grade)
    return VEYL:IsGradeBoss(group, grade)
end

---@diagnostic disable-next-line: duplicate-set-field
function server.getOwnedVehicleId(entityId)
    return Entity(entityId).state.veylOwnedId
end
