-- Contract templates. A player sees one card per template they can take; the vehicle and place are rolled by the server.
--   id, label, description
--   badge          the tag on the card: 'STANDARD' | 'PREMIUM' | 'HIGH RISK' | 'TIMED' | 'CREW' | 'EVENT'
--   difficulty     1-5 (shown as risk; also added to the vehicle's difficulty for the access puzzle)
--   tiers          vehicle tiers it draws from (config/vehicles.lua)
--   minRank / maxRank   rank index range (1 = Rookie ... 6 = Executive, see config/progression.lua); minRep / maxRep also apply
--   mode           'solo' | 'group' | 'both'; minCrew / maxCrew for group play
--   vehicles       how many vehicles the contract has (all must be delivered)
--   timeLimit      minutes, starts when the contract starts
--   reward         { min, max } multiplier on the vehicle's baseReward; repReward = reputation on completion
--   fastBonus      { within = fraction of the time limit, mult = 1.x } extra pay for finishing quickly
--   heat           { chance = alert chance at access, gain = heat added on an alert, onFail = heat on a failed attempt }
--   tracked        a tracker pings dispatch until disabled
--   cooldown       seconds before the same player can take this template again
--   maxActive      most simultaneous instances of this template on the server
--   minPolice      police on duty required (0 = none)
--   requires       optional { template = 'standard_recovery', completed = 3 }
--   event          only offered while an admin has started the event (/boosting event on)

BoostingConfig = BoostingConfig or {}

BoostingConfig.Templates = {
    {
        id = 'standard_recovery', label = 'Vehicle Recovery', badge = 'STANDARD',
        description = 'Recover the target vehicle and bring it to the handoff zone.',
        difficulty = 1, tiers = { 'standard' }, minRank = 1, minRep = 0, mode = 'both', minCrew = 1, maxCrew = 2, vehicles = 1,
        timeLimit = 30, reward = { 0.9, 1.4 }, repReward = 25, heat = { chance = 0.15, gain = 8, onFail = 12 },
        tracked = false, cooldown = 120, maxActive = 6, minPolice = 0,
    },
    {
        id = 'premium_recovery', label = 'Premium Recovery', badge = 'PREMIUM',
        description = 'Recover a high-value vehicle. More attention, better money.',
        difficulty = 3, tiers = { 'premium' }, minRank = 2, minRep = 100, mode = 'both', minCrew = 1, maxCrew = 3, vehicles = 1,
        timeLimit = 45, reward = { 1.0, 1.5 }, repReward = 45, heat = { chance = 0.35, gain = 14, onFail = 18 },
        tracked = false, cooldown = 300, maxActive = 4, minPolice = 0,
    },
    {
        id = 'high_risk', label = 'High-Risk Recovery', badge = 'HIGH RISK',
        description = 'A challenging contract for experienced operators. The vehicle carries a tracker.',
        difficulty = 5, tiers = { 'luxury' }, minRank = 3, minRep = 300, mode = 'both', minCrew = 1, maxCrew = 4, vehicles = 1,
        timeLimit = 60, reward = { 1.1, 1.7 }, repReward = 80, heat = { chance = 0.6, gain = 22, onFail = 28 },
        tracked = true, cooldown = 600, maxActive = 3, minPolice = 1,
    },
    {
        id = 'timed_delivery', label = 'Timed Delivery', badge = 'TIMED',
        description = 'The buyer will not wait. Deliver before the clock runs out for a bonus.',
        difficulty = 2, tiers = { 'standard', 'premium' }, minRank = 2, minRep = 100, mode = 'solo', minCrew = 1, maxCrew = 1, vehicles = 1,
        timeLimit = 20, reward = { 1.2, 1.7 }, repReward = 40, fastBonus = { within = 0.6, mult = 1.15 },
        heat = { chance = 0.25, gain = 10, onFail = 14 }, tracked = false, cooldown = 240, maxActive = 4, minPolice = 0,
    },
    {
        id = 'group_operation', label = 'Group Operation', badge = 'CREW',
        description = 'Several vehicles, one buyer. Bring a crew and deliver them all.',
        difficulty = 4, tiers = { 'premium' }, minRank = 3, minRep = 300, mode = 'group', minCrew = 2, maxCrew = 4, vehicles = 2,
        timeLimit = 60, reward = { 1.0, 1.4 }, repReward = 95, heat = { chance = 0.5, gain = 18, onFail = 24 },
        tracked = false, cooldown = 900, maxActive = 3, minPolice = 1, requires = { template = 'premium_recovery', completed = 2 },
    },
    {
        id = 'special_event', label = 'Special Event Contract', badge = 'EVENT',
        description = 'A limited-time contract that only exists while an event is running.',
        difficulty = 5, tiers = { 'luxury' }, minRank = 4, minRep = 700, mode = 'both', minCrew = 1, maxCrew = 4, vehicles = 1,
        timeLimit = 60, reward = { 1.8, 2.6 }, repReward = 150, heat = { chance = 0.7, gain = 26, onFail = 30 },
        tracked = true, cooldown = 1800, maxActive = 2, minPolice = 0, event = true,
    },
}

-- Penalties (reputation) for ending a contract badly.
BoostingConfig.Penalties = {
    failed = 6,              -- vehicle lost or destroyed
    expired = 4,             -- ran out of time
    cancelledActive = 0,     -- cancelled before the vehicle was acquired
    cancelledAcquired = 8,   -- abandoned after acquiring the vehicle
    accessFail = 2,          -- a failed access attempt
}
