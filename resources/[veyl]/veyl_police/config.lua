-- veyl_police configuration.

PoliceConfig = {
    Jobs = { 'police' },          -- on-duty members of these jobs are officers
    ActionDistance = 2.5,

    -- Duty points (a target spot visible to members of the police job)
    Stations = {
        { label = 'Mission Row PD', duty = vector3(441.8, -982.0, 30.69) },
    },

    CuffSeconds = 3.5,            -- the paired arrest animation
    SearchRequires = 'cuffed_or_down', -- 'cuffed_or_down' | 'any' (anyone can be searched)

    Citations = {
        Max = 25000,              -- largest single citation
        -- Charged to the bank straight away when the balance covers it; otherwise it stays unpaid (/citations to pay).
        ChargeImmediately = true,
    },

    ImpoundSeconds = 8,
    ImpoundFee = 750,             -- what the owner pays at the impound lot

    UnCuffCommand = 'uncuff',     -- staff: /uncuff <id> (veyl.police.manage or veyl.admin)
}
