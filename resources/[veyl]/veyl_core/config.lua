VeylConfig = {
    ServerName = 'VeylCore',

    -- Character slots a new account receives.
    DefaultMaxCharacters = 3,

    -- Identifier used as the stable account key. 'license' (Rockstar license) is always present.
    AccountIdentifier = 'license',

    -- How often (ms) the client re-announces itself until the server confirms the session.
    ClientReadyRetryMs = 5000,
    ClientReadyMaxAttempts = 12,
}
