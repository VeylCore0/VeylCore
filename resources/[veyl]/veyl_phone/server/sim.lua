-- SIM cards. A phone without one has no service (see OFFLINE_OK in core.lua). Buy a `sim_card` item, then right-click the phone
-- in the inventory and pick "Insert SIM card": the card is used up and the line goes live. The inventory runs this through
-- its item action hook (veyl_inventory RegisterItemAction), only when the clicked slot really holds a phone.
local SIM = PhoneConfig.Sim or {}

local function insert(ctx)
    local src, cid = ctx.source, ctx.citizenid
    local s = Phone.Session(src)
    if not s then return false, 'Your phone is not ready yet. Open it once first.' end
    if s.sim then return false, 'There is already a SIM card in this phone.' end
    -- Claim first (only one insert can win), then take the card; give the claim back if the card is gone.
    local claimed = MySQL.update.await('UPDATE veyl_ph_accounts SET sim = 1 WHERE citizenid = ? AND sim = 0', { cid })
    if (claimed or 0) < 1 then return false, 'There is already a SIM card in this phone.' end
    local okRemove, removed = pcall(function() return exports.veyl_inventory:RemoveItem(src, SIM.Item or 'sim_card', 1) end)
    if not okRemove or not removed then
        MySQL.update.await('UPDATE veyl_ph_accounts SET sim = 0 WHERE citizenid = ? AND sim = 1', { cid })
        return false, 'You need a SIM card. Buy one at a store.'
    end
    s.sim = true
    Phone.Push(src, 'sim', { sim = true })
    return true, 'SIM card inserted. Your phone has service.'
end

CreateThread(function()
    while GetResourceState('veyl_inventory') ~= 'started' do Wait(1000) end
    Wait(1000)
    exports.veyl_inventory:RegisterItemAction('phone', 'insert_sim', insert)
end)
-- Re-register if the inventory restarts.
AddEventHandler('onResourceStart', function(res)
    if res ~= 'veyl_inventory' then return end
    CreateThread(function() Wait(2000) exports.veyl_inventory:RegisterItemAction('phone', 'insert_sim', insert) end)
end)

Phone.InsertSim = insert
