-- Police: alerts, laboratory raids and seizure. OFF by default. Raids only need the police job; alerts additionally need a dispatch
-- resource configured below. Nothing here assumes a dispatch API beyond the adapter in server/police.lua.

ProductionConfig = ProductionConfig or {}

ProductionConfig.Police = {
    Enabled = false,                 -- master switch for alerts AND raids
    Jobs = { 'police' },             -- jobs that count as police (must be on duty)
    MinOnDuty = 1,                   -- police needed on duty before raids are allowed
    Dispatch = {
        Enabled = false,             -- needs Enabled = true too
        Resource = 'veyl_dispatch',  -- must be started and export `Alert`
        Code = '10-66', Priority = 2, Title = 'Suspicious activity', Radius = 200.0,
        Anonymous = true,            -- the message says an anonymous caller reported it
        Blip = { sprite = 51, colour = 1 },
    },
    -- Activities that can raise an alert: chance 0-1, per-player cooldown in seconds.
    Alerts = {
        plant = { chance = 0.15, cooldown = 300 },
        harvest = { chance = 0.2, cooldown = 300 },
        workstation = { chance = 0.2, cooldown = 300 },
        property_entry = { chance = 0.1, cooldown = 600 },
        field_search = { chance = 0.08, cooldown = 300 },
        supply_run = { chance = 0.25, cooldown = 300 },
        hazard = { chance = 0.3, cooldown = 600 },
        street_sale = { chance = 0.12, cooldown = 300 },
    },
    Raid = {
        BreachSeconds = 25,          -- base time to breach a door; security upgrades add to it
        DurationMinutes = 10,        -- how long police can open the lab's storage after a breach
        CooldownMinutes = 120,       -- the same lab cannot be raided again for this long
        SeizeItems = {               -- items taken by "Seize". Empty list = everything in storage.
            'prod_leaf', 'prod_blend', 'prod_pack', 'prod_wild_herb',
            'prod_field_bloom', 'prod_field_extract', 'prod_field_pack', 'prod_field_find',
            'prod_supply_kit', 'prod_compound', 'prod_batch_pack',
        },
        SeizeBenches = true,         -- running batches in the lab are cancelled and queued inputs lost
    },
}
