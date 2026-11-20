-- Server-only configuration (not sent to clients).
VeylServerConfig = {
    AccountIdentifier = 'license',
    DefaultMaxCharacters = 3,

    StartingMoney = { cash = 500, bank = 2500, crypto = 0 },
    MaxSingleMoneyChange = 10000000,       -- per call, whole dollars
    MoneyWriteRetries = 5,                 -- legacy AddMoney/RemoveMoney write-through retries

    SaveIntervalMs = 5 * 60000,            -- metadata/position autosave
    PaycheckIntervalMinutes = 15,
    PayOnlyPrimaryJob = true,              -- extra memberships never multiply income

    StartingNationality = 'American',
    MinBirthYear = 1930,
    MaxBirthYear = 2008,

    -- Metadata schema: type, default, range. Unknown keys may be set by server code but are not range-checked.
    Metadata = {
        hunger = { type = 'number', default = 100, min = 0, max = 100 },
        thirst = { type = 'number', default = 100, min = 0, max = 100 },
        stress = { type = 'number', default = 0, min = 0, max = 100 },
        health = { type = 'number', default = 200, min = 0, max = 200 },
        armor = { type = 'number', default = 0, min = 0, max = 100 },
        isdead = { type = 'boolean', default = false },
        inlaststand = { type = 'boolean', default = false },
        ishandcuffed = { type = 'boolean', default = false },
        licences = { type = 'table', default = { driver = true, weapon = false, business = false } },
        callsign = { type = 'string', default = 'NO CALLSIGN' },
        jailtime = { type = 'number', default = 0, min = 0, max = 100000 },
    },
}
