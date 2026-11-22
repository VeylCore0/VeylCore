-- veyl_mdt configuration.

MdtConfig = {
    Jobs = { 'police' },     -- on-duty members of these jobs can use the MDT
    Command = 'mdt',
    Key = 'F10',             -- rebindable in Settings > Key Bindings > FiveM
    -- Licences shown on a profile (keys of metadata.licences)
    Licences = {
        { key = 'driver', label = "Driver's licence" },
        { key = 'weapon', label = 'Weapon licence' },
        { key = 'business', label = 'Business licence' },
    },
}

-- Officers at or above this police grade can grant or revoke licences from a profile.
MdtConfig.LicenceGrade = 2

-- Penal code. Picking charges on a profile adds up the fine and prison months; reports list their charges.
-- fine in dollars, months of prison (0 = fine only).
MdtConfig.Charges = {
    -- Traffic
    { id = 'speeding', label = 'Speeding', category = 'Traffic', fine = 250, months = 0 },
    { id = 'reckless', label = 'Reckless driving', category = 'Traffic', fine = 750, months = 0 },
    { id = 'redlight', label = 'Running a red light', category = 'Traffic', fine = 200, months = 0 },
    { id = 'nolicence', label = 'Driving without a licence', category = 'Traffic', fine = 500, months = 0 },
    { id = 'dui', label = 'Driving under the influence', category = 'Traffic', fine = 1500, months = 5 },
    { id = 'hitrun', label = 'Hit and run', category = 'Traffic', fine = 2000, months = 10 },
    { id = 'evading', label = 'Evading police', category = 'Traffic', fine = 2500, months = 15 },
    -- Public order
    { id = 'trespass', label = 'Trespassing', category = 'Public order', fine = 400, months = 0 },
    { id = 'disorderly', label = 'Disorderly conduct', category = 'Public order', fine = 300, months = 0 },
    { id = 'obstruction', label = 'Obstruction of justice', category = 'Public order', fine = 1000, months = 5 },
    { id = 'resisting', label = 'Resisting arrest', category = 'Public order', fine = 1000, months = 8 },
    { id = 'impersonation', label = 'Impersonating an officer', category = 'Public order', fine = 3000, months = 15 },
    { id = 'falsereport', label = 'Filing a false report', category = 'Public order', fine = 800, months = 3 },
    -- Violence
    { id = 'assault', label = 'Assault', category = 'Violence', fine = 1200, months = 8 },
    { id = 'assaultdw', label = 'Assault with a deadly weapon', category = 'Violence', fine = 3000, months = 20 },
    { id = 'assaultleo', label = 'Assault on an officer', category = 'Violence', fine = 4000, months = 25 },
    { id = 'kidnapping', label = 'Kidnapping', category = 'Violence', fine = 5000, months = 30 },
    { id = 'attemptedmurder', label = 'Attempted murder', category = 'Violence', fine = 8000, months = 45 },
    { id = 'manslaughter', label = 'Manslaughter', category = 'Violence', fine = 7000, months = 40 },
    { id = 'murder', label = 'Murder', category = 'Violence', fine = 15000, months = 90 },
    -- Property
    { id = 'theft', label = 'Petty theft', category = 'Property', fine = 500, months = 3 },
    { id = 'gta', label = 'Grand theft auto', category = 'Property', fine = 2500, months = 15 },
    { id = 'burglary', label = 'Burglary', category = 'Property', fine = 3000, months = 15 },
    { id = 'robbery', label = 'Robbery', category = 'Property', fine = 4000, months = 20 },
    { id = 'armedrobbery', label = 'Armed robbery', category = 'Property', fine = 6000, months = 30 },
    { id = 'vandalism', label = 'Vandalism', category = 'Property', fine = 600, months = 0 },
    -- Weapons and drugs
    { id = 'weaponnolicence', label = 'Carrying a firearm without a licence', category = 'Weapons & drugs', fine = 2000, months = 10 },
    { id = 'brandishing', label = 'Brandishing a weapon', category = 'Weapons & drugs', fine = 1500, months = 8 },
    { id = 'possession', label = 'Possession of a controlled substance', category = 'Weapons & drugs', fine = 1000, months = 5 },
    { id = 'intent', label = 'Possession with intent to sell', category = 'Weapons & drugs', fine = 3500, months = 20 },
    { id = 'cultivation', label = 'Cultivation of a controlled substance', category = 'Weapons & drugs', fine = 4000, months = 25 },
}
