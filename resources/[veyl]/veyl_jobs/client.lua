-- veyl_jobs client commands.

RegisterCommand('duty', function()
    Veyl.NotifyResult(Veyl.Callback('veyl_jobs', 'toggleDuty'))
end, false)

RegisterCommand('job', function()
    local job = LocalPlayer.state.veylJob
    if not job then return Veyl.Notify('No job loaded', 'error') end
    Veyl.Notify(('%s - %s (%s)'):format(job.label, job.gradeLabel, job.onDuty and 'on duty' or 'off duty'), 'info')
end, false)

RegisterCommand('quitjob', function()
    if Veyl.UI.Confirm({ title = 'Quit job', message = 'Are you sure you want to quit your current job?' }) then
        Veyl.NotifyResult(Veyl.Callback('veyl_jobs', 'quit'))
    end
end, false)
