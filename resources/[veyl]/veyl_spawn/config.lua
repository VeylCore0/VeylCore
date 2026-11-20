SpawnConfig = {
    -- First spawn and fallback location (Legion Square).
    DefaultSpawn = vector4(195.17, -933.77, 30.69, 144.0),

    -- Where players respawn after the death timer (Pillbox Hill Medical Center entrance).
    HospitalSpawn = vector4(298.0, -584.5, 43.26, 70.0),
    RespawnDelaySeconds = 15,

    -- Periodic position save for loaded characters (ms).
    SaveIntervalMs = 120000,

    -- Seconds the client waits for collision around the spawn point before continuing anyway.
    CollisionTimeoutMs = 7000,
}
