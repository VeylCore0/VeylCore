-- veyl_mdt client: opens the MDT for on-duty officers and forwards its requests to the server.

local C = MdtConfig
local screen = vlib.createScreen({ name = 'mdt' })

local function isOfficer()
    local job = (Veyl.PlayerData or {}).job
    if not job or not job.onduty then return false end
    for _, j in ipairs(C.Jobs) do if job.name == j then return true end end
    return false
end

local function open()
    if screen:isOpen() then return screen:close('toggle') end
    if not isOfficer() then return Veyl.Notify('The MDT is for on-duty officers', 'error') end
    if LocalPlayer.state.medical or LocalPlayer.state.cuffed then return end
    local res = Veyl.Callback('veyl_mdt', 'dashboard')
    if not res.ok then return Veyl.NotifyResult(res) end
    local ok, reason = screen:open('mdt:open', res.data)
    if not ok and reason == 'busy' then Veyl.Notify('Close the open menu first.', 'warning') end
end

RegisterCommand(C.Command, function() CreateThread(open) end, false)
vlib.addKeybind({ name = 'veyl_mdt', description = 'Open the MDT (police)', defaultKey = C.Key, onPressed = function() CreateThread(open) end })

local ALLOWED = { dashboard = true, searchPeople = true, person = true, saveNotes = true, issueWarrant = true, closeWarrant = true,
    searchVehicle = true, vehicle = true, flagVehicle = true, reports = true, report = true, saveReport = true, sentence = true }
RegisterNUICallback('api', function(data, cb)
    if not screen:isOpen() or type(data) ~= 'table' or not ALLOWED[data.name] then return cb({ ok = false, code = 'INVALID_INPUT' }) end
    local args = type(data.args) == 'table' and data.args or {}
    CreateThread(function()
        local res = Veyl.CallbackTimeout('veyl_mdt', data.name, 15000, table.unpack(args, 1, 5))
        cb({ ok = res.ok, code = res.code, message = res.message, data = res.data })
    end)
end)

-- Going off duty closes it.
RegisterNetEvent('VeylCore:Client:SetDuty', function(onDuty) if not onDuty and screen:isOpen() then screen:close('off_duty') end end)
