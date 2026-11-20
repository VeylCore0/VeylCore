-- veyl_core paychecks: the core owns calculation and eligibility.
-- Only the primary job pays (memberships never multiply income). One paycheck per character per interval slot:
-- the operation id 'pay:<citizenid>:<slot>' makes a second payment for the same slot impossible.

CreateThread(function()
    local interval = VeylServerConfig.PaycheckIntervalMinutes * 60
    local lastSlot = math.floor(os.time() / interval)
    while true do
        Wait(30000)
        local slot = math.floor(os.time() / interval)
        if slot ~= lastSlot and Veyl.IsReady() then
            lastSlot = slot
            for src, p in pairs(Core.Players) do
                local def = VeylShared.Jobs[p.job]
                local grade = VeylShared.GetGrade('job', p.job, p.jobs[p.job] or 0)
                if def and grade and grade.payment > 0 and (p.onduty or def.offDutyPay) then
                    local citizenid = p.citizenid
                    CreateThread(function()
                        local res = Money.CreditOnce(citizenid, 'bank', grade.payment, ('Paycheck: %s'):format(def.label),
                            ('pay:%s:%d'):format(citizenid, slot), 'veyl_core')
                        if res.ok and Core.ByCitizen[citizenid] == src then
                            TriggerClientEvent('veyl_ui:notify', src, { message = ('Paycheck received: $%d'):format(grade.payment), type = 'success' })
                        elseif not res.ok and res.code ~= 'DUPLICATE_OPERATION' then
                            print(('^3[veyl_core] paycheck failed for %s: %s^7'):format(citizenid, res.code))
                        end
                    end)
                end
            end
        end
    end
end)
