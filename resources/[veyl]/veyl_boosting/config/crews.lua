-- Crews: cooperative contracts.

BoostingConfig = BoostingConfig or {}

BoostingConfig.Crews = {
    MaxSize = 4,
    InviteRange = 8.0,               -- metres: you can only invite nearby players
    InviteSeconds = 45,              -- how long an invite stays open
    -- Members can join or leave only while the contract is in one of these states (a crew with no contract is always free).
    JoinStates = { reserved = true },
    LeaveStates = { reserved = true, active = true, vehicle_acquired = true, delivery_started = true },
    -- Reward split: 'equal' (everyone the same) or 'leader' (the leader takes LeaderBonus off the top, the rest is shared equally).
    Split = 'equal',
    LeaderBonus = 0.10,
    -- Each extra crew member adds this much to the total pay (so crews earn more than a solo player, but less each).
    GroupPayBonus = 0.15,
    LogSize = 30,
}
