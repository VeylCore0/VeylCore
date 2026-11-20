JobsConfig = {
    DefaultJob = 'unemployed',
    PaycheckIntervalMinutes = 15,

    -- open = players may sign themselves on through the job's own activity (e.g. the delivery depot).
    -- pay = bank paycheck per interval while on duty.
    Jobs = {
        unemployed = { label = 'Civilian', grades = { [0] = { label = 'Civilian', pay = 0 } } },
        delivery = {
            label = 'GoPostal', open = true, defaultDuty = true,
            grades = { [0] = { label = 'Courier', pay = 25 }, [1] = { label = 'Senior Courier', pay = 40 } },
        },
        police = {
            label = 'LSPD',
            grades = {
                [0] = { label = 'Cadet', pay = 60 }, [1] = { label = 'Officer', pay = 80 },
                [2] = { label = 'Sergeant', pay = 100 }, [3] = { label = 'Chief', pay = 130, boss = true },
            },
        },
        ems = {
            label = 'EMS',
            grades = { [0] = { label = 'Trainee', pay = 60 }, [1] = { label = 'Paramedic', pay = 85 }, [2] = { label = 'Chief', pay = 120, boss = true } },
        },
    },
}
