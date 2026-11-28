-- Shared constants.

ProdEnum = {
    PlantState = { growing = 'growing', ready = 'ready', dead = 'dead' },
    BatchState = { queued = 'queued', running = 'running', done = 'done', claimed = 'claimed', cancelled = 'cancelled' },
    Role = { owner = 'owner', employee = 'employee', guest = 'guest' },
    -- What each role may do in a laboratory.
    RolePerms = {
        owner = { enter = true, storage = true, bench = true, plants = true, manage = true, security = true, upgrade = true },
        employee = { enter = true, storage = true, bench = true, plants = true },
        guest = { enter = true },
    },
}
