-- Job definitions. Grade keys are strings; payment is the paycheck per interval (config/server.lua).
-- open = players may sign themselves on through the job's own activity (e.g. the delivery depot).
return {
    unemployed = {
        label = 'Civilian',
        defaultDuty = true,
        offDutyPay = false,
        grades = {
            ['0'] = { name = 'Resident', payment = 0 },
        },
    },
    delivery = {
        label = 'GoPostal',
        type = 'civilian',
        open = true,
        defaultDuty = true,
        offDutyPay = false,
        grades = {
            ['0'] = { name = 'Courier', payment = 25 },
            ['1'] = { name = 'Senior Courier', payment = 40 },
        },
    },
    police = {
        label = 'Police Department',
        type = 'leo',
        defaultDuty = false,
        offDutyPay = false,
        grades = {
            ['0'] = { name = 'Cadet', payment = 100 },
            ['1'] = { name = 'Officer', payment = 150 },
            ['2'] = { name = 'Sergeant', payment = 200 },
            ['3'] = { name = 'Chief', payment = 250, isboss = true },
        },
    },
    ambulance = {
        label = 'EMS',
        type = 'ems',
        defaultDuty = false,
        offDutyPay = false,
        grades = {
            ['0'] = { name = 'Trainee', payment = 90 },
            ['1'] = { name = 'Paramedic', payment = 140 },
            ['2'] = { name = 'Chief', payment = 220, isboss = true },
        },
    },
    mechanic = {
        label = 'Mechanic',
        type = 'mechanic',
        defaultDuty = false,
        offDutyPay = false,
        grades = {
            ['0'] = { name = 'Apprentice', payment = 60 },
            ['1'] = { name = 'Mechanic', payment = 90 },
            ['2'] = { name = 'Owner', payment = 130, isboss = true },
        },
    },
}
