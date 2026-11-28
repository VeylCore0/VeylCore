-- Admin farms (/drugadmin) and selling to pedestrians.

ProductionConfig = ProductionConfig or {}

-- Farms are added in game by staff with the `production.admin` permission: stand where a farm should be, open /drugadmin, pick the kind and
-- add points as you walk. Players then search the points for the rewards below (same rules as field zones: per-player and per-point cooldowns,
-- a timed search, everything decided by the server). A preset is only the starting point: rewards, level and timings are edited per farm in the menu.
--   reward: { item, chance, min, max, level? }   the first reward always pays; the rest roll their chance
ProductionConfig.Farms = {
    Permission = 'production.admin',
    MaxFarms = 40, MaxPoints = 30, MaxRewards = 10,
    Presets = {
        weed = {
            label = 'Weed farm', branch = 'botanical', level = 1, prop = 'bkr_prop_weed_lrg_01b', respawn = 10, cooldown = 30,
            rewards = {
                { item = 'prod_leaf', chance = 1.0, min = 1, max = 3 },
                { item = 'prod_seed_ember', chance = 0.25, min = 1, max = 2 },
                { item = 'prod_seed_violet', chance = 0.08, min = 1, max = 1, level = 2 },
                { item = 'prod_seed_azure', chance = 0.02, min = 1, max = 1, level = 4 },
            },
        },
        coke = {
            label = 'Coke farm', branch = 'field', level = 1, prop = 'h4_prop_bush_cocaplant_01', respawn = 12, cooldown = 40,
            rewards = {
                { item = 'prod_field_bloom', chance = 1.0, min = 1, max = 3 },
                { item = 'prod_fseed_dawn', chance = 0.2, min = 1, max = 2 },
                { item = 'prod_fseed_dusk', chance = 0.05, min = 1, max = 1, level = 3 },
            },
        },
        mushroom = {
            label = 'Mushroom patch', branch = 'field', level = 1, prop = 'prop_veg_crop_03_cab', respawn = 12, cooldown = 40,
            rewards = {
                { item = 'prod_field_find', chance = 1.0, min = 1, max = 3 },
                { item = 'prod_spores_forest', chance = 0.1, min = 1, max = 1, level = 2 },
                { item = 'prod_spores_moon', chance = 0.03, min = 1, max = 1, level = 4 },
            },
        },
        custom = {
            label = 'Custom farm', branch = 'field', level = 1, prop = 'prop_plant_fern_01', respawn = 12, cooldown = 40,
            rewards = { { item = 'prod_wild_herb', chance = 1.0, min = 1, max = 2 } },
        },
    },
    -- Items an admin may put in a farm's rewards (nothing that is a bench or a card).
    ExcludeItems = { prod_workstation = true, prod_field_station = true, prod_supplier_station = true, prod_access_card = true, prod_respirator = true },
}

-- Selling to pedestrians: target a ped, "Offer product", pick what to sell. The server decides whether they are interested, what they pay
-- and how much they take; the same ped will not deal twice for a while (for anyone).
ProductionConfig.Street = {
    Enabled = true,
    Distance = 3.0,
    -- Only finished goods: harvests and ingredients are for the buyer.
    Items = { 'prod_pack', 'prod_field_pack', 'prod_field_extract', 'prod_mushroom_dry', 'prod_batch_pack', 'prod_ecstasy', 'prod_lsd', 'prod_veylx' },
    PriceMultiplier = 0.7,        -- of what the buyer pays (the buyer is safer, the street is quick)
    AcceptChance = 0.55,          -- a ped is interested at all
    Quantity = { 1, 3 },          -- how many units a ped takes
    PlayerCooldown = 6,           -- seconds between two offers by the same player
    PedCooldown = 900,            -- seconds before anyone can deal with the same ped again
    MaxOffersPerHour = 25,
    OfferSeconds = 45,            -- the offer expires after this long
    PoliceAlert = 'street_sale',  -- alert rule in config/police.lua (only used when police alerts are on)
    RefuseMessages = { 'No thanks.', 'Not interested.', 'Get lost.', 'I do not do that.', 'Leave me alone.' },
    -- Pedestrians that never deal (models). Police, military and medics, in addition to anything a player controls.
    BlockedModels = {
        's_m_y_cop_01', 's_f_y_cop_01', 's_m_y_sheriff_01', 's_f_y_sheriff_01', 's_m_y_hwaycop_01', 's_m_m_snowcop_01', 's_m_y_ranger_01', 's_f_y_ranger_01',
        's_m_y_swat_01', 's_m_m_armoured_01', 's_m_m_armoured_02', 's_m_y_marine_01', 's_m_y_marine_02', 's_m_y_marine_03', 's_m_m_paramedic_01', 's_m_m_fiboffice_01',
        's_m_m_fiboffice_02', 's_m_y_fireman_01', 's_m_m_security_01', 'csb_cop', 'ig_fbisuit_01',
    },
}
