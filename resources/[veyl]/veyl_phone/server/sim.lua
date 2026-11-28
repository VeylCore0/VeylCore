-- SIM cards. The SIM is the phone line: it carries the number and the contacts, the phone keeps everything else (PIN, settings,
-- mail, photos). A phone with no SIM has no service (see OFFLINE_OK in core.lua).
--
--   * A SIM card is an inventory item with its own slot on the body panel (veyl_inventory, equipment slot 'sim'). The card in that slot
--     IS the phone's SIM: drag one in and the phone has service, drag it out and it does not. There is no tray or menu.
--   * A new card from a shop has no number yet: the first time it goes in it takes the character's own number and is marked with it.
--   * Taking a SIM out takes its number and a copy of the contacts with it; the phone gets a spare number and an empty address book.
--   * Whoever puts that card in (you again, or a player you gave it to) gets that number and those contacts.
--
-- The inventory tells us when a character's equipment changes (the server event veyl_inventory:changed) and this file brings the phone
-- line in step with whatever is in the slot. The inventory is the source of truth; the account row only records what we last applied.
local SIM = PhoneConfig.Sim or {}
local ITEM = SIM.Item or 'sim_card'
local SLOT = 'sim'

local function newId()
    local chars, id = '0123456789abcdef', ''
    for _ = 1, 12 do local i = math.random(#chars) id = id .. chars:sub(i, i) end
    return id
end

--- Copies the contacts into the SIM (as JSON) so they travel with it.
local function snapshotContacts(cid)
    local rows = MySQL.query.await('SELECT name, number, note, favorite FROM veyl_ph_contacts WHERE owner_cid = ? ORDER BY name', { cid }) or {}
    return json.encode(rows)
end

local function restoreContacts(cid, encoded)
    local rows = type(encoded) == 'string' and json.decode(encoded) or nil
    for _, c in ipairs(rows or {}) do
        MySQL.update.await('INSERT IGNORE INTO veyl_ph_contacts (owner_cid, name, number, note, favorite) VALUES (?, ?, ?, ?, ?)',
            { cid, c.name, c.number, c.note, (c.favorite == 1 or c.favorite == true) and 1 or 0 })
    end
end

local function moveSession(s, from, to)
    if not s then return end
    if Phone.byNumber[from] == s then Phone.byNumber[from] = nil end
    s.number = to
    Phone.byNumber[to] = s
end

local function announce(s)
    if s then Phone.Push(s.src, 'sim', { sim = s.sim == true, hello = Phone.HelloFor(s.src) }) end
end

local function notify(s, text, kind)
    if s and s.src then Veyl.Notify(s.src, text, kind or 'info') end
end

--- What is in the SIM slot right now: { name, metadata } or nil.
local function card(cid)
    local ok, it = pcall(function() return exports.veyl_inventory:GetEquipmentSlot(cid, SLOT) end)
    if ok and type(it) == 'table' and it.name == ITEM then return it end
    return nil
end

--- The line goes away with the card: contacts are saved on the card's record, the phone gets a spare number.
local function detach(cid, acc, s)
    local id = acc.sim_id
    if not id then
        -- A character from before SIM cards had no record yet: the line they had becomes the card's.
        id = newId()
        MySQL.insert.await('INSERT INTO veyl_ph_sims (id, number) VALUES (?, ?)', { id, acc.number })
    end
    MySQL.update.await('UPDATE veyl_ph_sims SET contacts = ? WHERE id = ?', { snapshotContacts(cid), id })
    MySQL.update.await('DELETE FROM veyl_ph_contacts WHERE owner_cid = ?', { cid })
    local spare = Phone.NewNumber() or acc.number
    MySQL.update.await('UPDATE veyl_ph_accounts SET sim = 0, sim_slot = 0, sim_id = NULL, number = ? WHERE citizenid = ?', { spare, cid })
    moveSession(s, acc.number, spare)
    if s then s.sim = false announce(s) notify(s, 'SIM card removed. Your number and contacts went with it.') end
end

--- A card is in the slot: the phone takes its number and contacts, or a new card is marked with this character's number.
local function attach(cid, it, acc, s)
    local meta = it.metadata or {}
    if type(meta.sim) == 'string' then
        local row = MySQL.single.await('SELECT id, number, contacts FROM veyl_ph_sims WHERE id = ?', { meta.sim })
        if not row then notify(s, 'This SIM card is dead.', 'error') return false end
        local ok = pcall(MySQL.update.await, 'UPDATE veyl_ph_accounts SET number = ?, sim_id = ?, sim = 1, sim_slot = 1 WHERE citizenid = ?', { row.number, row.id, cid })
        if not ok then notify(s, 'This SIM card cannot be used right now.', 'error') return false end
        restoreContacts(cid, row.contacts)
        MySQL.update.await('UPDATE veyl_ph_sims SET contacts = NULL WHERE id = ?', { row.id })
        moveSession(s, acc.number, row.number)
        if s then s.sim = true announce(s) notify(s, ('SIM inserted. Your number is now %s.'):format(PhoneUtil.Format(row.number)), 'success') end
        return true
    end
    -- A new card keeps the number this character already has, and from now on remembers it.
    local id = newId()
    MySQL.insert.await('INSERT INTO veyl_ph_sims (id, number) VALUES (?, ?)', { id, acc.number })
    local res = Veyl.Await('veyl_inventory', 'SetEquipmentMetadata', 15000, cid, SLOT, { sim = id, number = acc.number }, 'phonesim:' .. id)
    if not (res and res.ok) then
        MySQL.update.await('DELETE FROM veyl_ph_sims WHERE id = ?', { id })
        notify(s, 'Could not set the SIM card up. Try again.', 'error')
        return false
    end
    MySQL.update.await('UPDATE veyl_ph_accounts SET sim_id = ?, sim = 1, sim_slot = 1 WHERE citizenid = ?', { id, cid })
    if s then s.sim = true announce(s) notify(s, 'SIM card inserted. Your phone has service.', 'success') end
    return true
end

--- Brings the phone line in step with the SIM slot. Safe to call any time and any number of times.
local syncing, again = {}, {}
function Phone.SimSync(cid)
    if syncing[cid] then again[cid] = true return end   -- already working on it: run once more when it finishes
    syncing[cid] = true
    local ok, err = pcall(Phone.SimSyncNow, cid)
    syncing[cid] = nil
    if again[cid] then again[cid] = nil Phone.SimSync(cid) end
    if not ok then print(('^1[veyl_phone] SIM sync for %s failed: %s^7'):format(cid, tostring(err))) end
end

function Phone.SimSyncNow(cid)
    if not (PhoneConfig.Sim and PhoneConfig.Sim.Required) then return end
    local acc = MySQL.single.await('SELECT number, sim, sim_id, sim_slot FROM veyl_ph_accounts WHERE citizenid = ?', { cid })
    if not acc then return end
    local s = Phone.byCid and Phone.byCid[cid] or nil
    local it = card(cid)
    local active = (acc.sim == 1 or acc.sim == true)
    local slotManaged = (acc.sim_slot == 1 or acc.sim_slot == true)
    if it then
        local id = type(it.metadata) == 'table' and it.metadata.sim or nil
        if active and slotManaged and id and id == acc.sim_id then return end   -- already the line
        if active then detach(cid, acc, s) acc = MySQL.single.await('SELECT number, sim, sim_id, sim_slot FROM veyl_ph_accounts WHERE citizenid = ?', { cid }) end
        attach(cid, it, acc, s)
    elseif active and slotManaged then
        detach(cid, acc, s)
    elseif active and not slotManaged then
        -- A character from before the SIM slot: their line becomes a real card in the slot, so it can be taken out like any other.
        local id = acc.sim_id
        if not id then
            id = newId()
            MySQL.insert.await('INSERT INTO veyl_ph_sims (id, number) VALUES (?, ?)', { id, acc.number })
            MySQL.update.await('UPDATE veyl_ph_accounts SET sim_id = ? WHERE citizenid = ?', { id, cid })
        end
        local res = Veyl.Await('veyl_inventory', 'PutInEquipment', 15000, cid, SLOT, ITEM, { sim = id, number = acc.number }, 'phonesim:legacy:' .. cid)
        if res and (res.ok or res.code == 'DUPLICATE_OPERATION') then
            MySQL.update.await('UPDATE veyl_ph_accounts SET sim_slot = 1 WHERE citizenid = ?', { cid })
        end
        -- Otherwise (slot taken by something else, inventory not ready) they keep service as before and we try again next time.
    end
end

-- The inventory says a character's equipment changed.
AddEventHandler('veyl_inventory:changed', function(invId)
    if type(invId) ~= 'string' or invId:sub(1, 6) ~= 'equip:' then return end
    local cid = invId:sub(7)
    CreateThread(function() Phone.SimSync(cid) end)
end)

-- A phone session just started (the player opened their phone): make sure the line matches the slot before service is judged.
AddEventHandler('veyl_phone:sessionStarted', function(src, s)
    local ok = pcall(Phone.SimSync, s.cid)
    if ok then
        local acc = MySQL.single.await('SELECT number, sim FROM veyl_ph_accounts WHERE citizenid = ?', { s.cid })
        if acc then
            s.sim = acc.sim == 1 or acc.sim == true
            if acc.number ~= s.number then moveSession(s, s.number, acc.number) end
        end
    end
end)
