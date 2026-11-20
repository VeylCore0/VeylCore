BankingConfig = {
    -- Whole-dollar integer units. Never use floats for money.
    StartingCash = 500,
    StartingBank = 2500,

    MaxSingleTransaction = 1000000,
    GiveCashDistance = 3.0,
    BankUseDistance = 3.0,

    -- Bank counters (Fleeca branches). Interact with E to deposit / withdraw / transfer.
    Banks = {
        vector3(149.91, -1040.46, 29.37),
        vector3(314.23, -278.83, 54.17),
        vector3(-350.80, -49.57, 49.04),
        vector3(-1212.98, -330.84, 37.79),
        vector3(-2962.58, 482.63, 15.70),
        vector3(1175.06, 2706.64, 38.09),
        vector3(-112.20, 6469.29, 31.63),
    },
}
