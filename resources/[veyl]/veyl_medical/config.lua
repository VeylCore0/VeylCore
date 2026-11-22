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

    -- Voice (pma-voice only; ignored without it). Range in metres while downed / unconscious; nil = leave unchanged.
    VoiceRangeDowned = 1.5,          -- badly hurt: a whisper
    VoiceRangeUnconscious = 0.1,     -- cannot be heard

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

-- Injuries, treatment items and beds (server/injuries.lua, client/injuries.lua)
MedicalConfig.Injuries = {
    MinDamage = 5,                   -- hits smaller than this are ignored
    BleedSecondsPerLevel = 30,       -- bleeding level 1 loses health every 30 s, level 4 every 7.5 s
    BleedDamage = 2,
    LimpAt = 2,                      -- leg severity that makes you limp and stops sprinting
    ShakeAt = 2,                     -- head severity that shakes your view
    PainkillerSeconds = 300,
}

MedicalConfig.Items = {
    gauze = { item = 'gauze', bleeding = -2 },                 -- slows bleeding
    painkillers = { item = 'painkillers', heal = 10 },        -- hides limp and shake for PainkillerSeconds
    medkit = { item = 'medkit', heal = 60, bleeding = -99 },   -- stops bleeding; does not fix fractures
}

-- Hospital beds (Pillbox). Adjust to your hospital MLO: x, y, z of the mattress and the heading of the patient.
MedicalConfig.Beds = {
    vector4(353.1, -584.6, 43.11, 152.0),
    vector4(356.79, -585.86, 43.11, 152.0),
    vector4(354.12, -593.12, 43.1, 336.0),
    vector4(350.79, -591.8, 43.1, 336.0),
    vector4(346.99, -590.48, 43.1, 336.0),
    vector4(360.32, -587.19, 43.02, 152.0),
}
MedicalConfig.BedDistance = 40.0     -- how close to the beds EMS must be to put someone in one
