-- veyl_management client: office zones, /bossmenu and /gangmenu, the management screen and job offers.

local C = ManagementConfig
local screen = vlib.createScreen({ name = 'management' })

local function reply(cb, res) cb({ ok = res.ok, code = res.code, message = res.message, data = res.data }) end

local function openGroup(kind, name)
    if not Veyl.IsLoaded() then return end
    local res = Veyl.Callback('veyl_management', 'open', kind, name)
    if not res.ok then return Veyl.NotifyResult(res) end
    local ok, reason = screen:open('management:open', res.data)
    if not ok then Veyl.Notify(reason == 'busy' and 'Close the open menu first.' or 'The boss menu is unavailable right now.', 'warning') end
end

--- Opens the menu for the one group you run, or asks which one when you run several.
local function openFor(kind)
    local res = Veyl.Callback('veyl_management', 'myGroups', kind)
    if not res.ok then return Veyl.NotifyResult(res) end
    local list = res.data
    if kind == 'job' and not C.JobMenuAnywhere then
        local here = {}
        for _, g in ipairs(list) do if g.office then here[#here + 1] = g end end
        if #list > 0 and #here == 0 then return Veyl.Notify('Use the boss menu at your office.', 'error') end
        list = here
    end
    if #list == 0 then return Veyl.Notify(kind == 'gang' and 'You do not run a gang.' or 'You are not a boss of any job.', 'error') end
    if #list == 1 then return openGroup(kind, list[1].name) end
    local items = {}
    for i, g in ipairs(list) do items[i] = { label = g.label, value = g.name } end
    local choice = Veyl.UI.Menu({ title = 'Boss menu', subtitle = 'Which one do you want to manage?', items = items })
    if choice then openGroup(kind, choice) end
end

RegisterCommand(C.JobCommand, function() CreateThread(function() openFor('job') end) end, false)
RegisterCommand(C.GangCommand, function() CreateThread(function() openFor('gang') end) end, false)
AddEventHandler('veyl_management:office', function(args)
    if type(args) == 'table' and args.job then CreateThread(function() openGroup('job', args.job) end) end
end)

local ALLOWED = { open = true, setGrade = true, fire = true, hire = true }
RegisterNUICallback('api', function(data, cb)
    if not screen:isOpen() or type(data) ~= 'table' or not ALLOWED[data.name] then return cb({ ok = false, code = 'INVALID_INPUT' }) end
    local args = type(data.args) == 'table' and data.args or {}
    CreateThread(function() reply(cb, Veyl.CallbackTimeout('veyl_management', data.name, 15000, table.unpack(args, 1, 4))) end)
end)

---------------------------------------------------------------------------
-- Offers
---------------------------------------------------------------------------
RegisterNetEvent('veyl_management:offer', function(token, info)
    if type(info) ~= 'table' then return end
    CreateThread(function()
        local what = info.kind == 'gang' and ('%s invites you to join as %s.') or ('%s offers you a job as %s.')
        local accepted = Veyl.UI.Confirm({
            title = info.kind == 'gang' and 'Gang invite' or 'Job offer',
            message = what:format(info.label, info.rank) .. (' You have %d seconds to answer.'):format(info.seconds or 30),
            confirmLabel = 'Accept', cancelLabel = 'Decline',
        })
        Veyl.NotifyResult(Veyl.CallbackTimeout('veyl_management', 'answerOffer', 10000, token, accepted == true))
    end)
end)

---------------------------------------------------------------------------
-- Office zones (shown to members of that job; the server checks the boss grade)
---------------------------------------------------------------------------
CreateThread(function()
    while GetResourceState('veyl_interact') ~= 'started' do Wait(250) end
    for i, o in ipairs(C.Offices) do
        exports.veyl_interact:AddZone({
            id = ('veyl_management_%d'):format(i), coords = o.coords, radius = C.OfficeRadius, title = o.label,
            options = { { label = 'Boss menu', icon = 'briefcase', event = 'veyl_management:office', args = { job = o.job }, groups = o.job } },
        })
    end
end)
