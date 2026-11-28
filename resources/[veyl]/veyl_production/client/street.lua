-- Selling to pedestrians: "Offer product" on a ped. The server decides everything (is the ped real and in range, do they want it, what they
-- pay); this only points at the ped, shows what the server says you can sell, and plays a few reactions.

local S = ProductionConfig.Street
local busy = false
local OPTION = 'veyl_prod_street_offer'

-- Never offered to: people, animals, police, military and anyone in a vehicle or hurt. (The server checks again; this only hides the prompt.)
local BAD_TYPES = { [6] = true, [27] = true, [28] = true, [29] = true }

local function eligible(e)
    if not DoesEntityExist(e) or IsPedAPlayer(e) or IsPedDeadOrDying(e, true) or IsPedInAnyVehicle(e, false) then return false end
    if BAD_TYPES[GetPedType(e)] then return false end
    return NetworkGetEntityIsNetworked(e)
end

local function control(e)
    if NetworkHasControlOfEntity(e) then return true end
    NetworkRequestControlOfEntity(e)
    local t = GetGameTimer() + 800
    while not NetworkHasControlOfEntity(e) and GetGameTimer() < t do Wait(25) end
    return NetworkHasControlOfEntity(e)
end

local function hold(e)
    if control(e) then
        SetBlockingOfNonTemporaryEvents(e, true)
        TaskStandStill(e, 30000)
        TaskTurnPedToFaceEntity(e, PlayerPedId(), 1500)
    end
    TaskTurnPedToFaceEntity(PlayerPedId(), e, 800)
end

local function release(e, mood)
    if not DoesEntityExist(e) then return end
    if control(e) then
        ClearPedTasks(e)
        SetBlockingOfNonTemporaryEvents(e, false)
        if mood == 'bad' then TaskSmartFleePed(e, PlayerPedId(), 40.0, 8000, false, false) else TaskWanderStandard(e, 10.0, 10) end
    end
end

local function say(e, line) if DoesEntityExist(e) then PlayPedAmbientSpeechNative(e, line, 'SPEECH_PARAMS_FORCE_NORMAL') end end

local pickItem

local function ask(e, offer, item)
    local most = math.min(item.count, offer.left)
    local v = vlib.inputDialog(('Sell %s'):format(item.label), {
        { name = 'count', label = ('How many (they will take up to %d)'):format(offer.left), type = 'number', required = true, min = 1, max = most, default = most },
    }, { submitLabel = ('Sell at $%d each'):format(item.price) })
    if not v then return release(e) end
    local res = Veyl.CallbackTimeout('veyl_production', 'streetSell', 15000, offer.token, item.item, tonumber(v.count))
    Veyl.NotifyResult(res)
    if not res.ok then return release(e) end
    item.count = item.count - res.data.sold
    offer.left = res.data.left
    say(e, 'GENERIC_THANKS')
    if offer.left > 0 then
        for i = #offer.items, 1, -1 do if offer.items[i].count <= 0 then table.remove(offer.items, i) end end
        if #offer.items > 0 then return pickItem(e, offer) end
    end
    release(e)
end

function pickItem(e, offer)
    local opts = {}
    for i, it in ipairs(offer.items) do
        opts[#opts + 1] = { id = 'i' .. i, label = ('%s  x%d'):format(it.label, it.count), right = ('$%d each'):format(it.price),
            onSelect = function() CreateThread(function() ask(e, offer, it) end) end }
    end
    vlib.registerMenu({ id = 'prodstreet:offer', title = 'They are interested', subtitle = ('They will take %d more'):format(offer.left), options = opts,
        onClose = function() release(e) end })
    vlib.showMenu('prodstreet:offer')
end

local function offer(e)
    if busy then return end
    busy = true
    local netId = NetworkGetNetworkIdFromEntity(e)
    hold(e)
    local res = Veyl.CallbackTimeout('veyl_production', 'streetOffer', 15000, netId)
    busy = false
    if not res.ok then
        Veyl.NotifyResult(res)
        if res.code == 'NOT_INTERESTED' then say(e, 'GENERIC_NO') release(e, 'neutral') else release(e) end
        return
    end
    say(e, 'GENERIC_HOWS_IT_GOING')
    pickItem(e, res.data)
end

CreateThread(function()
    if not S.Enabled then return end
    while GetResourceState('veyl_target') ~= 'started' do Wait(500) end
    exports.veyl_target:addGlobalPed({
        { name = OPTION, label = 'Offer product', icon = 'bag', distance = S.Distance, priority = 0,
          canInteract = function(e) return not busy and eligible(e) end,
          onSelect = function(d) CreateThread(function() offer(d.entity) end) end },
    })
end)

AddEventHandler('onResourceStop', function(res)
    if res == GetCurrentResourceName() then pcall(function() exports.veyl_target:removeGlobalPed({ OPTION }) end) end
end)
