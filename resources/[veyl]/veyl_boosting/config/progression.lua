-- Reputation ranks and challenges.

BoostingConfig = BoostingConfig or {}

-- Ranks, lowest first. `rep` is the reputation needed. Rank index is what templates use for minRank / maxRank.
BoostingConfig.Ranks = {
    { id = 'rookie',     label = 'Rookie',     rep = 0 },
    { id = 'runner',     label = 'Runner',     rep = 100 },
    { id = 'operator',   label = 'Operator',   rep = 300 },
    { id = 'specialist', label = 'Specialist', rep = 700 },
    { id = 'elite',      label = 'Elite',      rep = 1500 },
    { id = 'executive',  label = 'Executive',  rep = 3000 },
}

-- Rewards unlocked at a rank (shown on the Reputation page; the real gates are templates' minRank and vehicles' minRep).
BoostingConfig.RankPerks = {
    runner = 'Premium contracts',
    operator = 'High-risk contracts and group operations',
    specialist = 'Event contracts and fast-lane luxury vehicles',
    elite = 'Hypercar contracts',
    executive = 'All contracts and the best payouts',
}

-- Rep carried over from the old boosting system (the first version) is multiplied by this when the data is imported.
BoostingConfig.LegacyRepMultiplier = 5

-- Challenges. metric: 'completed' (contracts finished) or 'earned' (money earned from contracts).
-- Progress is stored per player per period; the reward is paid once, when the goal is reached.
BoostingConfig.Challenges = {
    daily = {
        { id = 'daily_complete', label = 'Complete 1 Contract', metric = 'completed', goal = 1, reward = 10000 },
        { id = 'daily_earn',     label = 'Earn $12,000',        metric = 'earned',    goal = 12000, reward = 5000 },
    },
    weekly = {
        { id = 'weekly_complete', label = 'Complete 8 Contracts', metric = 'completed', goal = 8, reward = 45000 },
    },
}
