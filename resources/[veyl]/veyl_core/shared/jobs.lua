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
    weazel = {
        label = 'Weazel News',
        type = 'civilian',
        defaultDuty = false,
        offDutyPay = false,
        grades = {
            ['0'] = { name = 'Reporter', payment = 50 },
            ['1'] = { name = 'Senior Reporter', payment = 70 },
            ['2'] = { name = 'Editor in Chief', payment = 100, isboss = true },
        },
    },
    -- City jobs (veyl_citizenjobs): sign on at the depot; paid per run, not by the paycheck.
    trucker = {
        label = 'Trucking',
        type = 'civilian',
        open = true,
        defaultDuty = true,
        offDutyPay = false,
        grades = {
            ['0'] = { name = 'Driver', payment = 0 },
            ['1'] = { name = 'Senior Driver', payment = 0 },
        },
    },
    taxi = {
        label = 'Downtown Cab Co.',
        type = 'civilian',
        open = true,
        defaultDuty = true,
        offDutyPay = false,
        grades = {
            ['0'] = { name = 'Driver', payment = 0 },
            ['1'] = { name = 'Senior Driver', payment = 0 },
        },
    },
    tow = {
        label = 'Tow Truck',
        type = 'civilian',
        open = true,
        defaultDuty = true,
        offDutyPay = false,
        grades = {
            ['0'] = { name = 'Driver', payment = 0 },
            ['1'] = { name = 'Senior Driver', payment = 0 },
        },
    },
    garbage = {
        label = 'Sanitation',
        type = 'civilian',
        open = true,
        defaultDuty = true,
        offDutyPay = false,
        grades = {
            ['0'] = { name = 'Collector', payment = 0 },
            ['1'] = { name = 'Senior Collector', payment = 0 },
        },
    },
    -- More businesses (veyl_business)
    carwash = {
        label = 'Car Wash',
        type = 'business',
        defaultDuty = false,
        offDutyPay = false,
        grades = {
            ['0'] = { name = 'Attendant', payment = 25 },
            ['1'] = { name = 'Manager', payment = 45, isboss = true },
            ['2'] = { name = 'Owner', payment = 0, isboss = true },
        },
    },
    nightclub = {
        label = 'Nightclub',
        type = 'business',
        defaultDuty = false,
        offDutyPay = false,
        grades = {
            ['0'] = { name = 'Bartender', payment = 35 },
            ['1'] = { name = 'Bouncer', payment = 35 },
            ['2'] = { name = 'Manager', payment = 60, isboss = true },
            ['3'] = { name = 'Owner', payment = 0, isboss = true },
        },
    },
    pawnshop = {
        label = 'Pawn Shop',
        type = 'business',
        defaultDuty = false,
        offDutyPay = false,
        grades = {
            ['0'] = { name = 'Clerk', payment = 30 },
            ['1'] = { name = 'Manager', payment = 55, isboss = true },
            ['2'] = { name = 'Owner', payment = 0, isboss = true },
        },
    },
    tunershop = {
        label = 'Tuner Shop',
        type = 'business',
        defaultDuty = false,
        offDutyPay = false,
        grades = {
            ['0'] = { name = 'Tuner', payment = 40 },
            ['1'] = { name = 'Lead Tuner', payment = 65, isboss = true },
            ['2'] = { name = 'Owner', payment = 0, isboss = true },
        },
    },
    -- Player-owned businesses (veyl_business): the owner holds the top (boss) grade.
    beanmachine = {
        label = 'Bean Machine',
        type = 'business',
        defaultDuty = false,
        offDutyPay = false,
        grades = {
            ['0'] = { name = 'Barista', payment = 30 },
            ['1'] = { name = 'Shift Lead', payment = 45 },
            ['2'] = { name = 'Manager', payment = 60, isboss = true },
            ['3'] = { name = 'Owner', payment = 0, isboss = true },
        },
    },
    burgershot = {
        label = 'Burger Shot',
        type = 'business',
        defaultDuty = false,
        offDutyPay = false,
        grades = {
            ['0'] = { name = 'Cook', payment = 30 },
            ['1'] = { name = 'Shift Lead', payment = 45 },
            ['2'] = { name = 'Manager', payment = 60, isboss = true },
            ['3'] = { name = 'Owner', payment = 0, isboss = true },
        },
    },
}
