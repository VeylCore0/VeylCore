-- veyl_jobs server: job selection and duty UI. veyl_core owns definitions, memberships, duty and paychecks.

Veyl.Startup({ 'veyl_core' }, function() return true end)

Veyl.RegisterCallback('toggleDuty', function(src)
    local pd = Veyl.GetPlayerData(src)
    if pd.job.name == 'unemployed' then return Veyl.Err('INVALID_STATE', 'You do not have a job') end
    exports.veyl_core:SetJobDuty(src, not pd.job.onduty)
    return Veyl.Ok(nil, pd.job.onduty and 'You are now off duty' or 'You are now on duty')
end, { cooldown = 3000 })

Veyl.RegisterCallback('memberships', function(src)
    local pd = Veyl.GetPlayerData(src)
    local jobs = exports.veyl_core:GetJobs()
    local list = { { name = 'unemployed', label = jobs.unemployed.label, grade = 'Resident', primary = pd.job.name == 'unemployed' } }
    for name, level in pairs(pd.jobs) do
        local def = jobs[name]
        if def then
            local g = def.grades[tostring(level)]
            list[#list + 1] = { name = name, label = def.label, grade = g and g.name or tostring(level), primary = pd.job.name == name }
        end
    end
    return Veyl.Ok(list)
end, { cooldown = 500 })

Veyl.RegisterCallback('setPrimary', function(_, citizenid, name)
    if not Veyl.Validate.str(name, 1, 32) then return Veyl.Err('INVALID_INPUT', 'Invalid job') end
    if not exports.veyl_core:SetPlayerPrimaryJob(citizenid, name) then
        return Veyl.Err('NO_PERMISSION', 'You are not a member of that job')
    end
    return Veyl.Ok(nil, 'Primary job changed')
end, { cooldown = 3000 })

Veyl.RegisterCallback('quit', function(src, citizenid)
    local pd = Veyl.GetPlayerData(src)
    local def = exports.veyl_core:GetJob(pd.job.name)
    if pd.job.name == 'unemployed' then return Veyl.Err('INVALID_STATE', 'You do not have a job') end
    if not def or not def.open then return Veyl.Err('NO_PERMISSION', 'Ask your supervisor to release you') end
    exports.veyl_core:RemovePlayerFromJob(citizenid, pd.job.name)
    Veyl.Audit(src, 'job_quit', { job = pd.job.name })
    return Veyl.Ok(nil, 'You quit ' .. def.label)
end, { cooldown = 3000 })
