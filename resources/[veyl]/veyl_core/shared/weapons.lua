-- Weapon catalog keyed by hash name. Inventory items/metadata remain owned by ox_inventory.
return {
    weapon_unarmed = { name = 'weapon_unarmed', label = 'Fists', ammotype = nil, damagereason = 'Melee killed' },
    weapon_flashlight = { name = 'weapon_flashlight', label = 'Flashlight', ammotype = nil, damagereason = 'Melee killed' },
    weapon_nightstick = { name = 'weapon_nightstick', label = 'Nightstick', ammotype = nil, damagereason = 'Melee killed' },
    weapon_stungun = { name = 'weapon_stungun', label = 'Taser', ammotype = 'AMMO_STUNGUN', damagereason = 'Died' },
    weapon_pistol = { name = 'weapon_pistol', label = 'Pistol', ammotype = 'AMMO_PISTOL', damagereason = 'Pistoled' },
}
