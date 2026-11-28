-- veyl_production: general settings. All production here is fictional game logic with invented items; nothing models real processes.
-- Branches: only `botanical` is built so far. Field and supplier branches will plug into the same engines (plants, workstations,
-- properties, progression); the config keys below already allow more branches.

ProductionConfig = ProductionConfig or {}
local C = ProductionConfig

C.Debug = false

-- Command that opens the production tablet from anywhere (also reachable from the supply NPC and from inside your lab).
C.Command = 'production'

-- How far (metres) the server lets a player be from a thing they act on. The client checks the same numbers for prompts only.
C.Distance = { Interact = 3.5, Plant = 3.5, Workstation = 3.5, Gather = 4.0, Shop = 5.0, Property = 4.5, Place = 6.0 }

-- Actions that can only happen this often (seconds) per player, as a cheap guard against spam. Gathering also has per-spot cooldowns.
C.Cooldowns = { Place = 2, Water = 1, Harvest = 2, Purchase = 1, Gather = 2 }

C.ActionMs = { Place = 3500, Water = 2500, Harvest = 4500, Pickup = 2500, Pack = 3000 }

-- Placement preview rules (plants and workstations). Placed objects need open ground within this slope.
C.Placement = {
    MaxDistance = 6.0, MaxSlopeDegrees = 22.0, RotateStep = 15.0,
    MinSpacing = 0.9,               -- plants / workstations need this much room between each other
    AllowInteriors = false,         -- outside labs: placing indoors in the open world (no property) is refused unless true
    MaxPlantsPerPlayer = 12,
    MaxWorkstationsPerPlayer = 2,   -- portable ones outside a laboratory
    RestrictedZones = {             -- { label, coords, radius }: nothing can be placed inside these
        { label = 'Mission Row PD', coords = vector3(441.0, -981.0, 30.7), radius = 80.0 },
        { label = 'Pillbox Hospital', coords = vector3(298.0, -584.0, 43.3), radius = 70.0 },
        { label = 'Legion Square', coords = vector3(195.0, -934.0, 30.7), radius = 60.0 },
    },
}

-- Cleanup: placed objects of players who have not been seen for this long are recovered (returned to the owner's pickup list is not
-- supported; they are removed and logged). 0 disables it.
C.AbandonedAfterDays = 0

-- Branch display data for the tablet.
C.Branches = {
    botanical = { label = 'Botanical', icon = 'leaf', color = '#7bd88f', enabled = true },
    field = { label = 'Field Operations', icon = 'compass', color = '#5ab0ff', enabled = false },
    supplier = { label = 'Supplier Operations', icon = 'truck', color = '#c58bff', enabled = false },
}

-- Logging. Each event type can be switched on or off; set Webhook to a Discord webhook URL to also post them. Secrets
-- (access codes) are never logged.
C.Logging = {
    Console = true,
    Webhook = '',
    Events = { purchase = true, sale = true, gather = true, plant = true, harvest = true, craft = true, property = true, upgrade = true, permission = true, raid = true, reward = true, security = true },
}

C.UI = { Brand = 'VEYL PRODUCTION', Accent = '#8b5fd6', Accent2 = '#3f8bff', Currency = '$' }
