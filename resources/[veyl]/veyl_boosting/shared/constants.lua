-- Shared constants: contract states and the only legal moves between them.

BoostingShared = {}

BoostingShared.States = {
    'available', 'reserved', 'active', 'vehicle_acquired', 'delivery_started', 'completed', 'failed', 'expired', 'cancelled',
}

-- state -> the states it may move to. Anything else is rejected, whoever asks.
BoostingShared.Transitions = {
    reserved = { active = true, cancelled = true, expired = true },
    active = { vehicle_acquired = true, failed = true, expired = true, cancelled = true },
    vehicle_acquired = { delivery_started = true, failed = true, expired = true, cancelled = true },
    delivery_started = { completed = true, failed = true, expired = true, cancelled = true },
}

BoostingShared.Live = { reserved = true, active = true, vehicle_acquired = true, delivery_started = true }
BoostingShared.Ended = { completed = true, failed = true, expired = true, cancelled = true }

BoostingShared.Glyphs = { 'A', 'B', 'C', 'D', 'E', 'F', 'G', 'H' }   -- the puzzle uses indexes into the page's symbol set
