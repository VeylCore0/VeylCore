-- veyl_medical configuration. Times are seconds; money is whole dollars.
--
-- alive --(health reaches 0)--> downed --(bleed out)--> unconscious --(respawn timer)--> hospital
--            ^                     |                          |
--            +---- revived by EMS, or helped up with a first aid kit (downed only) ----+

MedicalConfig = {
    -- Jobs whose on-duty members are EMS (can revive anyone and treat injuries, receive "person down" alerts).
    EMSJobs = { 'ambulance' },

    BleedOutSeconds = 300,           -- downed -> unconscious
    RespawnSeconds = 300,            -- unconscious -> may respawn, while any EMS is on duty
    RespawnSecondsNoEMS = 60,        -- ... when no EMS is on duty
    RespawnFee = 500,                -- charged on hospital respawn (bank first, then cash; waived if you have neither)

    ReviveSeconds = 10,              -- how long a revive takes (EMS)
    HelpUpSeconds = 15,              -- how long a civilian takes with a first aid kit
    TreatSeconds = 8,                -- EMS treating someone who is hurt but conscious
    ActionDistance = 3.0,
    CiviliansCanHelpUp = true,       -- anyone with a first aid kit can help up a DOWNED (not unconscious) person
    FirstAidItem = 'first_aid_kit',
    HealthAfterHelpUp = 130,         -- of 200
    HealthAfterRespawn = 200,

    CallCooldownSeconds = 60,        -- "call for help" (G) while downed
    AlertBlipSeconds = 90,

    -- Pillbox Hill: respawn point and the reception check-in (treatment by staff when EMS are not around).
    Hospital = {
        label = 'Pillbox Hill Medical Center',
        respawn = vector4(298.0, -584.5, 43.26, 70.0),
        reception = vector4(308.19, -595.35, 43.29, 340.0),
        receptionPed = 's_m_m_doctor_01',
        blip = { sprite = 61, colour = 1, scale = 0.8 },
    },
    CheckInFee = 250,
    CheckInSeconds = 12,
    CheckInMaxEMS = 1,               -- check-in is only open while fewer than this many EMS are on duty (1 = none)
}
