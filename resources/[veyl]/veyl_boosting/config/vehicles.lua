-- The vehicle catalogue. Contract templates draw from these by tier.
--   tier        'standard' | 'premium' | 'luxury'
--   difficulty  1-5: scales the access puzzle and (with baseReward) the pay
--   baseReward  the base payout before the contract's multiplier
--   minRep      reputation needed before the vehicle can appear on a contract
--   condition   full = engine/body (0-1) at or above which the vehicle pays in full
--   solo / group  which contract modes may use it
-- Model names must exist in the game; images come from veyl_vehicles/web/images/<model>.webp.

BoostingConfig = BoostingConfig or {}

BoostingConfig.Vehicles = {
    -- Standard
    { model = 'blista',       label = 'Blista',           tier = 'standard', difficulty = 1, baseReward = 1000, minRep = 0,   condition = { full = 0.6 }, solo = true, group = true },
    { model = 'asea',         label = 'Asea',             tier = 'standard', difficulty = 1, baseReward = 1100, minRep = 0,   condition = { full = 0.6 }, solo = true, group = true },
    { model = 'prairie',      label = 'Prairie',          tier = 'standard', difficulty = 1, baseReward = 1200, minRep = 0,   condition = { full = 0.6 }, solo = true, group = true },
    { model = 'sultan',       label = 'Sultan',           tier = 'standard', difficulty = 2, baseReward = 2000, minRep = 100, condition = { full = 0.65 }, solo = true, group = true },
    { model = 'buffalo',      label = 'Buffalo',          tier = 'standard', difficulty = 2, baseReward = 2300, minRep = 100, condition = { full = 0.65 }, solo = true, group = true },
    { model = 'felon',        label = 'Felon',            tier = 'standard', difficulty = 2, baseReward = 2100, minRep = 100, condition = { full = 0.65 }, solo = true, group = true },
    { model = 'oracle',       label = 'Oracle',           tier = 'standard', difficulty = 2, baseReward = 2200, minRep = 100, condition = { full = 0.65 }, solo = true, group = true },
    -- Premium
    { model = 'comet2',       label = 'Comet',            tier = 'premium',  difficulty = 3, baseReward = 4200, minRep = 300, condition = { full = 0.7 }, solo = true, group = true },
    { model = 'schafter3',    label = 'Schafter V12',     tier = 'premium',  difficulty = 3, baseReward = 4000, minRep = 300, condition = { full = 0.7 }, solo = true, group = true },
    { model = 'banshee',      label = 'Banshee',          tier = 'premium',  difficulty = 3, baseReward = 4600, minRep = 300, condition = { full = 0.7 }, solo = true, group = true },
    { model = 'feltzer2',     label = 'Feltzer',          tier = 'premium',  difficulty = 3, baseReward = 4300, minRep = 300, condition = { full = 0.7 }, solo = true, group = true },
    { model = 'carbonizzare', label = 'Carbonizzare',     tier = 'premium',  difficulty = 4, baseReward = 5200, minRep = 700, condition = { full = 0.7 }, solo = true, group = true },
    { model = 'jester',       label = 'Jester',           tier = 'premium',  difficulty = 4, baseReward = 6200, minRep = 700, condition = { full = 0.75 }, solo = true, group = true },
    { model = 'elegy2',       label = 'Elegy RH8',        tier = 'premium',  difficulty = 4, baseReward = 6000, minRep = 700, condition = { full = 0.75 }, solo = true, group = true },
    { model = 'massacro',     label = 'Massacro',         tier = 'premium',  difficulty = 4, baseReward = 6400, minRep = 700, condition = { full = 0.75 }, solo = true, group = true },
    -- Luxury
    { model = 'specter',      label = 'Specter',          tier = 'luxury',   difficulty = 4, baseReward = 8000, minRep = 700,  condition = { full = 0.8 }, solo = true, group = true },
    { model = 'neon',         label = 'Neon',             tier = 'luxury',   difficulty = 4, baseReward = 8500, minRep = 700,  condition = { full = 0.8 }, solo = true, group = true },
    { model = 'zentorno',     label = 'Zentorno',         tier = 'luxury',   difficulty = 5, baseReward = 11000, minRep = 1500, condition = { full = 0.8 }, solo = true, group = true },
    { model = 't20',          label = 'T20',              tier = 'luxury',   difficulty = 5, baseReward = 12500, minRep = 1500, condition = { full = 0.8 }, solo = false, group = true },
    { model = 'adder',        label = 'Adder',            tier = 'luxury',   difficulty = 5, baseReward = 13000, minRep = 1500, condition = { full = 0.8 }, solo = false, group = true },
    { model = 'osiris',       label = 'Osiris',           tier = 'luxury',   difficulty = 5, baseReward = 13500, minRep = 3000, condition = { full = 0.85 }, solo = false, group = true },
    { model = 'turismor',     label = 'Turismo R',        tier = 'luxury',   difficulty = 5, baseReward = 14500, minRep = 3000, condition = { full = 0.85 }, solo = false, group = true },
}

BoostingConfig.Tiers = {
    standard = { label = 'Standard', color = '#3f8bff' },
    premium  = { label = 'Premium',  color = '#8b5fd6' },
    luxury   = { label = 'Luxury',   color = '#e8a33a' },
}
