-- The economy around the street: crews, a market that reacts to what is sold, territories with heat, regulars you build up, and group supplier runs.

ProductionConfig = ProductionConfig or {}

-- Crews: a small group with a leader. Members share each other's plants and benches outdoors (the owner can switch that off), pool XP into
-- a crew level, and earn influence in territories together.
ProductionConfig.Crews = {
    Enabled = true,
    MaxMembers = 8,
    CreateCost = 2500,
    NameMin = 3, NameMax = 20,
    InviteSeconds = 60, InviteRange = 8.0,
    Levels = { 0, 400, 1200, 3000, 6000, 12000 },   -- crew XP needed for crew level 1..6 (members' XP also counts for the crew)
    SellBonusPerLevel = 0.01,                       -- every crew level adds this to what members get when selling (street and buyer)
}

-- Market: what you sell pushes that item's price down, and it recovers over time. A small daily swing means prices differ from day to day.
ProductionConfig.Market = {
    Enabled = true,
    Impact = 0.004,          -- price drop per unit sold (100 units is about -40%)
    MinMult = 0.55,          -- the price never goes below this share of the base
    RecoverPerHour = 60,     -- units of pressure that drain away every hour
    DailySwing = 0.08,       -- each item's price is +/- this much from day to day
}

-- Territories: areas of the map. Street sales inside one use its modifiers, build heat there, and add influence for your crew (or you, with no
-- crew); the crew with the most influence controls it and its members get ControlBonus on street prices there.
-- `meets` are places regulars will meet you.
ProductionConfig.Territories = {
    Areas = {
        { id = 'strawberry', label = 'Strawberry', center = vector3(80.0, -1680.0, 29.0), radius = 450.0, price = 1.00, accept = 1.00,
          meets = { vector3(120.7, -1775.2, 29.5), vector3(-37.9, -1584.6, 29.3), vector3(171.0, -1713.9, 29.3) } },
        { id = 'vinewood', label = 'Vinewood', center = vector3(300.0, 200.0, 104.0), radius = 600.0, price = 1.20, accept = 0.85,
          meets = { vector3(236.6, 164.4, 105.0), vector3(358.9, 275.4, 103.1), vector3(-18.0, 238.8, 109.5) } },
        { id = 'sandy', label = 'Sandy Shores', center = vector3(1850.0, 3700.0, 33.0), radius = 700.0, price = 0.90, accept = 1.25,
          meets = { vector3(1961.1, 3740.7, 32.3), vector3(1698.6, 3753.9, 34.4), vector3(1836.9, 3680.5, 33.8) } },
        { id = 'paleto', label = 'Paleto Bay', center = vector3(-200.0, 6300.0, 31.0), radius = 700.0, price = 0.95, accept = 1.15,
          meets = { vector3(-276.3, 6226.7, 31.5), vector3(-90.0, 6365.0, 31.5), vector3(-348.7, 6264.9, 31.5) } },
    },
    Influence = { PerUnit = 1.0, DecayPerHour = 0.04, ControlBonus = 0.10, MinToControl = 25 },
    -- Heat builds where you sell and cools by itself. Hot areas: peds are less likely to deal and police alerts are more likely.
    Heat = { PerSale = 10, DecayPerMinute = 2, Max = 100, AcceptPenalty = 0.004, AlertBonus = 0.015 },
    OutsideCell = 300.0,     -- outside every area, heat is tracked per square of this many metres
}

-- Regulars: peds who liked dealing with you. A regular buys more, pays better as loyalty grows and meets you at a spot you are sent to.
ProductionConfig.Regulars = {
    Enabled = true,
    Max = 10,
    ChanceOnSale = 0.22,         -- chance a sale to a ped makes them a regular
    CallCooldown = 1800,         -- seconds before you can call the same regular again
    MeetSeconds = 900,           -- the meeting is open this long
    MeetRadius = 6.0,
    Quantity = { 3, 8 },
    PriceBonusPerLoyalty = 0.01, MaxPriceBonus = 0.25,
    LoyaltyPerSale = 1,
    Names = { 'Marcus', 'Dee', 'Tyrell', 'Camila', 'Ray', 'Jo', 'Nico', 'Tasha', 'Vince', 'Lena', 'Omar', 'Keisha', 'Dante', 'Mia', 'Rico', 'Tess' },
    Models = { 'a_m_y_skater_01', 'a_f_y_hipster_01', 'a_m_y_hipster_01', 'a_m_y_stbla_01', 'a_f_y_vinewood_01', 'a_m_m_tramp_01', 'a_f_y_tourist_01', 'a_m_y_beach_01' },
}

-- Group supplier runs: the person who starts a run can bring others. Everyone at the drop when it is handed over gets the kits, and each extra
-- person adds a share to the amount.
ProductionConfig.Groups = {
    Enabled = true,
    MaxMembers = 3,              -- including the leader
    InviteSeconds = 45, InviteRange = 15.0,
    KitBonusPerExtra = 0.20,
    DropRadius = 14.0,           -- how close a member must be to the drop to be paid
}
