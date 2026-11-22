-- veyl_management configuration. Anyone holding a grade marked isboss = true (veyl_core/shared/jobs.lua and gangs.lua)
-- can manage that job or gang. Bosses can only hire into, promote to, demote or fire grades BELOW their own.

ManagementConfig = {
    -- Job offices: the boss menu opens here (a target zone visible to members of that job).
    Offices = {
        { job = 'police',    coords = vector3(461.45, -986.20, 30.73), label = 'Police management' },
        { job = 'ambulance', coords = vector3(311.21, -599.36, 43.29), label = 'EMS management' },
        { job = 'mechanic',  coords = vector3(-347.29, -133.27, 39.01), label = 'LS Customs management' },
        { job = 'beanmachine', coords = vector3(-635.7, 227.9, 81.88), label = 'Bean Machine management' },
        { job = 'burgershot', coords = vector3(-1178.1, -896.0, 13.97), label = 'Burger Shot management' },
    },
    OfficeRadius = 1.5,

    -- true: /bossmenu opens the job menu anywhere. false: only at the job's office.
    JobMenuAnywhere = false,
    JobCommand = 'bossmenu',
    -- Gangs have no office; their boss menu always opens with this command.
    GangCommand = 'gangmenu',

    HireDistance = 5.0,   -- how close a person must be to receive a job offer
    OfferSeconds = 30,    -- how long they have to accept
}
