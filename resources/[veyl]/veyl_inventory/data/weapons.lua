-- VeylCore weapons and ammo. Every weapon here becomes an inventory item named after it (e.g. weapon_pistol).
-- Using the item draws the weapon; using it again holsters it. Ammo comes from the ammo item named in `ammo`
-- and is used up as you shoot. Melee and thrown weapons have no ammo item.
--
-- weight in grams. image defaults to <name>.png in web/images (a placeholder shows until you add it).
-- Spawn one with the staff command: /vgiveitem <id> weapon_pistol 1   and ammo: /vgiveitem <id> ammo_pistol 100

return {
    ammo = {
        ammo_pistol  = { label = 'Pistol Ammo', weight = 10, maxStack = 250, description = 'For pistols and SMGs that take pistol rounds.' },
        ammo_smg     = { label = 'SMG Ammo', weight = 10, maxStack = 250 },
        ammo_rifle   = { label = 'Rifle Ammo', weight = 15, maxStack = 250 },
        ammo_shotgun = { label = 'Shotgun Shells', weight = 30, maxStack = 100 },
        ammo_sniper  = { label = 'Sniper Rounds', weight = 40, maxStack = 60 },
    },

    weapons = {
        -- Melee
        weapon_knife        = { label = 'Knife', weight = 300 },
        weapon_bat          = { label = 'Baseball Bat', weight = 1100 },
        weapon_crowbar      = { label = 'Crowbar', weight = 1500 },
        weapon_golfclub     = { label = 'Golf Club', weight = 800 },
        weapon_hammer       = { label = 'Hammer', weight = 900 },
        weapon_hatchet      = { label = 'Hatchet', weight = 1000 },
        weapon_knuckle      = { label = 'Brass Knuckles', weight = 200 },
        weapon_machete      = { label = 'Machete', weight = 900 },
        weapon_switchblade  = { label = 'Switchblade', weight = 150 },
        weapon_nightstick   = { label = 'Nightstick', weight = 600 },
        weapon_wrench       = { label = 'Pipe Wrench', weight = 1200 },
        weapon_battleaxe    = { label = 'Battle Axe', weight = 2000 },
        weapon_poolcue      = { label = 'Pool Cue', weight = 500 },
        weapon_bottle       = { label = 'Broken Bottle', weight = 300 },
        weapon_dagger       = { label = 'Antique Dagger', weight = 400 },

        -- Pistols
        weapon_pistol       = { label = 'Pistol', weight = 1000, ammo = 'ammo_pistol' },
        weapon_combatpistol = { label = 'Combat Pistol', weight = 1000, ammo = 'ammo_pistol' },
        weapon_appistol     = { label = 'AP Pistol', weight = 1200, ammo = 'ammo_pistol' },
        weapon_pistol50     = { label = 'Pistol .50', weight = 1400, ammo = 'ammo_pistol' },
        weapon_snspistol    = { label = 'SNS Pistol', weight = 700, ammo = 'ammo_pistol' },
        weapon_heavypistol  = { label = 'Heavy Pistol', weight = 1300, ammo = 'ammo_pistol' },
        weapon_vintagepistol = { label = 'Vintage Pistol', weight = 900, ammo = 'ammo_pistol' },
        weapon_revolver     = { label = 'Heavy Revolver', weight = 1500, ammo = 'ammo_pistol' },
        weapon_doubleaction = { label = 'Double-Action Revolver', weight = 1300, ammo = 'ammo_pistol' },
        weapon_ceramicpistol = { label = 'Ceramic Pistol', weight = 800, ammo = 'ammo_pistol' },
        weapon_stungun      = { label = 'Taser', weight = 600 },

        -- SMGs
        weapon_microsmg     = { label = 'Micro SMG', weight = 1800, ammo = 'ammo_smg' },
        weapon_smg          = { label = 'SMG', weight = 2600, ammo = 'ammo_smg' },
        weapon_assaultsmg   = { label = 'Assault SMG', weight = 2800, ammo = 'ammo_smg' },
        weapon_combatpdw    = { label = 'Combat PDW', weight = 2700, ammo = 'ammo_smg' },
        weapon_machinepistol = { label = 'Machine Pistol', weight = 1600, ammo = 'ammo_pistol' },
        weapon_minismg      = { label = 'Mini SMG', weight = 1700, ammo = 'ammo_smg' },
        weapon_gusenberg    = { label = 'Gusenberg Sweeper', weight = 4500, ammo = 'ammo_smg' },

        -- Shotguns
        weapon_pumpshotgun  = { label = 'Pump Shotgun', weight = 3500, ammo = 'ammo_shotgun' },
        weapon_sawnoffshotgun = { label = 'Sawed-Off Shotgun', weight = 2800, ammo = 'ammo_shotgun' },
        weapon_assaultshotgun = { label = 'Assault Shotgun', weight = 4500, ammo = 'ammo_shotgun' },
        weapon_bullpupshotgun = { label = 'Bullpup Shotgun', weight = 3800, ammo = 'ammo_shotgun' },
        weapon_heavyshotgun = { label = 'Heavy Shotgun', weight = 4800, ammo = 'ammo_shotgun' },
        weapon_dbshotgun    = { label = 'Double Barrel Shotgun', weight = 3000, ammo = 'ammo_shotgun' },

        -- Rifles
        weapon_assaultrifle = { label = 'Assault Rifle', weight = 4000, ammo = 'ammo_rifle' },
        weapon_carbinerifle = { label = 'Carbine Rifle', weight = 3800, ammo = 'ammo_rifle' },
        weapon_advancedrifle = { label = 'Advanced Rifle', weight = 3700, ammo = 'ammo_rifle' },
        weapon_specialcarbine = { label = 'Special Carbine', weight = 3900, ammo = 'ammo_rifle' },
        weapon_bullpuprifle = { label = 'Bullpup Rifle', weight = 3600, ammo = 'ammo_rifle' },
        weapon_compactrifle = { label = 'Compact Rifle', weight = 3000, ammo = 'ammo_rifle' },

        -- Sniper
        weapon_sniperrifle  = { label = 'Sniper Rifle', weight = 6000, ammo = 'ammo_sniper' },
        weapon_heavysniper  = { label = 'Heavy Sniper', weight = 9000, ammo = 'ammo_sniper' },
        weapon_marksmanrifle = { label = 'Marksman Rifle', weight = 6500, ammo = 'ammo_sniper' },
        weapon_musket       = { label = 'Musket', weight = 5000, ammo = 'ammo_shotgun' },
    },
}
