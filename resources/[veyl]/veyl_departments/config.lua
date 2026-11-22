-- veyl_departments: vehicle garages and supply lockers for emergency services. On-duty members only.
-- grade = the lowest job grade allowed. Locations are for the base-game Mission Row PD and Pillbox Hill: move them
-- to your MLOs if they differ.

DepartmentsConfig = {
    Departments = {
        police = {
            label = 'LSPD', jobs = { 'police' }, platePrefix = 'LSPD',
            garage = {
                menu = vector3(454.6, -1017.4, 28.4),
                spawn = vector4(448.16, -1017.41, 28.56, 90.65),
                vehicles = {
                    { model = 'police', label = 'Police Cruiser', grade = 0 },
                    { model = 'police2', label = 'Police Buffalo', grade = 1 },
                    { model = 'police3', label = 'Police Interceptor', grade = 1 },
                    { model = 'policeb', label = 'Police Bike', grade = 1 },
                    { model = 'policet', label = 'Police Transporter', grade = 1 },
                    { model = 'fbi', label = 'Unmarked Buffalo', grade = 2 },
                    { model = 'fbi2', label = 'Unmarked Granger', grade = 2 },
                },
            },
            supplies = {
                coords = vector3(461.4, -981.0, 30.69), label = 'Equipment locker', cooldownSeconds = 600,
                items = {
                    { item = 'radio', count = 1 },
                    { item = 'flashlight', count = 1 },
                    { item = 'first_aid_kit', count = 1 },
                    { item = 'gauze', count = 3 },
                    { item = 'bandage', count = 5 },
                    { item = 'door_ram', count = 1, grade = 1 },
                },
            },
        },
        ems = {
            label = 'EMS', jobs = { 'ambulance' }, platePrefix = 'EMS',
            garage = {
                menu = vector3(299.0, -576.3, 43.26),
                spawn = vector4(294.58, -574.76, 43.18, 35.79),
                vehicles = {
                    { model = 'ambulance', label = 'Ambulance', grade = 0 },
                    { model = 'lguard', label = 'Response Truck', grade = 1 },
                },
            },
            supplies = {
                coords = vector3(306.3, -601.5, 43.28), label = 'Medical supplies', cooldownSeconds = 600,
                items = {
                    { item = 'medkit', count = 3 },
                    { item = 'gauze', count = 10 },
                    { item = 'painkillers', count = 5 },
                    { item = 'first_aid_kit', count = 3 },
                    { item = 'bandage', count = 10 },
                    { item = 'radio', count = 1 },
                },
            },
        },
    },
    ReturnDistance = 25.0,   -- how close to the garage a department vehicle must be to return it
}
