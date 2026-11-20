	-- >>> VeylCore items (inserted by integrations/install-ox-integration.ps1) >>>
	['sandwich'] = {
		label = 'Sandwich',
		weight = 300,
		client = {
			anim = 'eating',
			prop = 'burger',
			usetime = 3000,
			notification = 'You ate a sandwich'
		},
	},

	['coffee'] = {
		label = 'Bean Machine Coffee',
		weight = 300,
		client = {
			anim = { dict = 'mp_player_intdrink', clip = 'loop_bottle' },
			prop = { model = `p_amb_coffeecup_01`, pos = vec3(0.0, 0.0, 0.0), rot = vec3(0.0, 0.0, 0.0) },
			usetime = 2500,
			notification = 'You drank a coffee'
		},
	},

	['qbexample_token'] = {
		label = 'QB Example Token',
		weight = 10,
		description = 'Used by veyl_qbexample to demonstrate QB CreateUseableItem on VeylCore',
		server = { export = 'veyl_inventory.useItem' },
		client = { usetime = 500 },
	},
	-- <<< VeylCore items <<<
