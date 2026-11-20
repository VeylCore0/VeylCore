-- veyl_jobs client commands.

RegisterCommand('duty', function()
    Veyl.NotifyResult(Veyl.Callback('veyl_jobs', 'toggleDuty'))
end, false)

RegisterCommand('job', function()
    local job = (Veyl.PlayerData or {}).job
    if not job then return Veyl.Notify('No job loaded', 'error') end
    Veyl.Notify(('%s - %s (%s)'):format(job.label, job.grade.name, job.onduty and 'on duty' or 'off duty'), 'info')
end, false)

RegisterCommand('jobs', function()
    local res = Veyl.Callback('veyl_jobs', 'memberships')
    if not res.ok then return Veyl.NotifyResult(res) end
    local items = {}
    for i, j in ipairs(res.data) do
        items[i] = { label = j.label, description = j.grade, right = j.primary and 'Primary' or nil, value = j.name, disabled = j.primary }
    end
    local choice = Veyl.UI.Menu({ title = 'My jobs', subtitle = 'Choose your primary job', items = items })
    if choice then Veyl.NotifyResult(Veyl.Callback('veyl_jobs', 'setPrimary', choice)) end
end, false)

RegisterCommand('quitjob', function()
    if Veyl.UI.Confirm({ title = 'Quit job', message = 'Are you sure you want to quit your current job?' }) then
        Veyl.NotifyResult(Veyl.Callback('veyl_jobs', 'quit'))
    end
end, false)
