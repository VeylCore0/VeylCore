-- SIM cards. The SIM is the phone line: it carries the number and the contacts, the phone keeps everything else (PIN, settings,
-- mail, photos). A phone with no SIM has no service (see OFFLINE_OK in core.lua).
--
--   * Right-click the phone in the inventory > SIM card opens a tray: put a SIM card in, or take the current one out.
--   * A new card from a shop has no number yet: inserting it keeps the character's own number.
--   * Taking a SIM out gives you a SIM card item that remembers the number and a copy of the contacts, and the phone loses both.
--   * Whoever inserts that card (you again, or a player you gave it to) gets that number and those contacts.
--
-- The inventory runs this through its item action and tray hooks (RegisterItemAction / RegisterItemTray), and only when the
-- clicked slot really holds a phone.
local SIM = PhoneConfig.Sim or {}
local ITEM = SIM.Item or 'sim_card'

local function newId()
    local chars, id = '0123456789abcdef', ''
    for _ = 1, 12 do local i = math.random(#chars) id = id .. chars:sub(i, i) end
    return id
end

local function inv(fn) local ok, a, b = pcall(fn) return ok and a or nil, ok and b or nil end

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
    if Phone.byNumber[from] == s then Phone.byNumber[from] = nil end
    s.number = to
    Phone.byNumber[to] = s
end

local function announce(s)
    Phone.Push(s.src, 'sim', { sim = s.sim == true, hello = Phone.HelloFor(s.src) })
end

--- Puts the SIM card in inventory slot `slot` into the phone.
function Phone.SimInsert(src, cid, slot)
    local s = Phone.Session(src)
    if not s then return false, 'Your phone is not ready yet. Open it once first.' end
    if s.sim then return false, 'There is already a SIM card in this phone. Take it out first.' end
    if math.type(slot) ~= 'integer' then return false, 'Pick a SIM card.' end
    local it = inv(function() return exports.veyl_inventory:GetSlot(src, slot) end)
    if not it or it.name ~= ITEM then return false, 'That is not a SIM card.' end
    local meta = it.metadata or {}
    local card
    if type(meta.sim) == 'string' then
        card = MySQL.single.await('SELECT id, number, contacts FROM veyl_ph_sims WHERE id = ?', { meta.sim })
        if not card then return false, 'This SIM card is dead.' end
    end
    -- Claim the phone first so two inserts cannot both win, then take the card.
    if (MySQL.update.await('UPDATE veyl_ph_accounts SET sim = 1 WHERE citizenid = ? AND sim = 0', { cid }) or 0) < 1 then
        return false, 'There is already a SIM card in this phone. Take it out first.'
    end
    local removed = inv(function() return exports.veyl_inventory:RemoveItem(src, ITEM, 1, next(meta) and meta or nil) end)
    if not removed then
        MySQL.update.await('UPDATE veyl_ph_accounts SET sim = 0 WHERE citizenid = ? AND sim = 1', { cid })
        return false, 'You need a SIM card. Buy one at a store.'
    end
    local acc = MySQL.single.await('SELECT number FROM veyl_ph_accounts WHERE citizenid = ?', { cid })
    local old = acc and acc.number or s.number
    if card then
        -- A used card brings its own number and its contacts.
        local ok = pcall(MySQL.update.await, 'UPDATE veyl_ph_accounts SET number = ?, sim_id = ? WHERE citizenid = ?', { card.number, card.id, cid })
        if not ok then
            -- The number is somehow taken: give the card back and leave the phone as it was.
            inv(function() return exports.veyl_inventory:AddItem(src, ITEM, 1, meta) end)
            MySQL.update.await('UPDATE veyl_ph_accounts SET sim = 0 WHERE citizenid = ? AND sim = 1', { cid })
            return false, 'This SIM card cannot be used right now.'
        end
        restoreContacts(cid, card.contacts)
        MySQL.update.await('UPDATE veyl_ph_sims SET contacts = NULL WHERE id = ?', { card.id })
        moveSession(s, old, card.number)
    else
        -- A new card keeps the number this character already has.
        local id = newId()
        MySQL.insert.await('INSERT INTO veyl_ph_sims (id, number) VALUES (?, ?)', { id, old })
        MySQL.update.await('UPDATE veyl_ph_accounts SET sim_id = ? WHERE citizenid = ?', { id, cid })
    end
    s.sim = true
    announce(s)
    return true, card and ('SIM inserted. Your number is now %s.'):format(PhoneUtil.Format(card.number)) or 'SIM card inserted. Your phone has service.'
end

--- Takes the SIM out: the player gets a SIM card item holding the number and contacts, the phone goes to no service.
function Phone.SimRemove(src, cid)
    local s = Phone.Session(src)
    if not s then return false, 'Your phone is not ready yet.' end
    if not s.sim then return false, 'There is no SIM card in this phone.' end
    if Calls.StateFor(src) then return false, 'Hang up before taking the SIM out.' end
    local canCarry = inv(function() return exports.veyl_inventory:CanCarryItem(src, ITEM, 1, { sim = 'xxxxxxxxxxxx', number = '0000000' }) end)
    if not canCarry then return false, 'You cannot carry the SIM card. Make room first.' end
    if (MySQL.update.await('UPDATE veyl_ph_accounts SET sim = 0 WHERE citizenid = ? AND sim = 1', { cid }) or 0) < 1 then
        return false, 'There is no SIM card in this phone.'
    end
    local acc = MySQL.single.await('SELECT number, sim_id FROM veyl_ph_accounts WHERE citizenid = ?', { cid })
    if not acc then return false, 'Something went wrong.' end
    local id = acc.sim_id
    if not id then
        -- A character from before SIM cards: the line they already have becomes their first SIM.
        id = newId()
        MySQL.insert.await('INSERT INTO veyl_ph_sims (id, number) VALUES (?, ?)', { id, acc.number })
    end
    MySQL.update.await('UPDATE veyl_ph_sims SET contacts = ? WHERE id = ?', { snapshotContacts(cid), id })
    local given = inv(function() return exports.veyl_inventory:AddItem(src, ITEM, 1, { sim = id, number = acc.number }) end)
    if not given then
        MySQL.update.await('UPDATE veyl_ph_sims SET contacts = NULL WHERE id = ?', { id })
        MySQL.update.await('UPDATE veyl_ph_accounts SET sim = 1, sim_id = ? WHERE citizenid = ?', { id, cid })
        return false, 'You cannot carry the SIM card. Make room first.'
    end
    -- The card now holds the contacts: the phone forgets them and gets a spare number until another SIM goes in.
    MySQL.update.await('DELETE FROM veyl_ph_contacts WHERE owner_cid = ?', { cid })
    local spare = Phone.NewNumber()
    MySQL.update.await('UPDATE veyl_ph_accounts SET sim_id = NULL, number = ? WHERE citizenid = ?', { spare or acc.number, cid })
    moveSession(s, acc.number, spare or acc.number)
    s.sim = false
    announce(s)
    return true, 'SIM card removed. Your number and contacts went with it.'
end

local function act(ctx)
    local op = ctx.arg and ctx.arg.op
    if op == 'insert' then return Phone.SimInsert(ctx.source, ctx.citizenid, ctx.arg.slot) end
    if op == 'remove' then return Phone.SimRemove(ctx.source, ctx.citizenid) end
    return false, 'Pick insert or remove.'
end

local function tray(ctx)
    local s = Phone.Session(ctx.source)
    local current
    if s and s.sim then current = { label = 'SIM card', detail = PhoneUtil.Format(s.number), image = 'sim_card.png' } end
    return {
        title = 'SIM card', accepts = ITEM, current = current,
        emptyLabel = 'No SIM card inserted', insertLabel = 'Insert', removeLabel = 'Take out',
        hint = current and 'Taking the SIM out takes the number and contacts with it. Whoever inserts it gets them.'
            or 'A new card keeps your number. A used one brings its own number and contacts.',
    }
end

local function register()
    exports.veyl_inventory:RegisterItemAction('phone', 'sim', act)
    exports.veyl_inventory:RegisterItemTray('phone', 'sim', tray)
end

CreateThread(function()
    while GetResourceState('veyl_inventory') ~= 'started' do Wait(1000) end
    Wait(1000)
    register()
end)
-- Re-register if the inventory restarts.
AddEventHandler('onResourceStart', function(res)
    if res ~= 'veyl_inventory' then return end
    CreateThread(function() Wait(2000) register() end)
end)
