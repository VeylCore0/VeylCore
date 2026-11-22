# Weapons (`veyl_inventory/data/weapons.lua`)

Weapons are inventory items. Every weapon in `data/weapons.lua` becomes an item named after it (`weapon_pistol`, `weapon_pumpshotgun`, …), plus five ammo items (`ammo_pistol`, `ammo_smg`, `ammo_rifle`, `ammo_shotgun`, `ammo_sniper`).

## Using them

- **Draw:** use the weapon from the inventory or the hotbar (1–5). Use it again to holster.
- **Ammo** is the matching ammo items in your pockets: the gun holds exactly what you carry, and every shot uses one.
- If the weapon leaves your pockets (dropped, given, searched, confiscated in prison), it leaves your hands within 2 s.
- Going down or being cuffed holsters it. Weapons that did not come from the inventory (pickups) are taken away.

## Getting them

- **Ammu-Nation** (11 stores): pistols, shotguns, a musket, melee weapons, pistol and shotgun ammo. Needs a **weapon licence** (`metadata.licences.weapon`, granted by the police or staff).
- **Staff:** `/vgiveitem <id> weapon_carbinerifle 1` and `/vgiveitem <id> ammo_rifle 120`.

## Adding a weapon

```lua
weapon_specialcarbine = { label = 'Special Carbine', weight = 3900, ammo = 'ammo_rifle' },
weapon_knife          = { label = 'Knife', weight = 300 },                 -- melee: no ammo
```

The key is the GTA weapon name. Put `hash = 'weapon_x'` when the item name differs. A definition with the same name in `data/items.lua` wins, if you need to customise one. Pictures go in `web/images/<name>.png` (`veylcheck` lists the missing ones).

## Stores

`veyl_shops/config.lua` now places every base-game store: 9 **24/7**, 5 **LTD Gasoline**, 5 **Rob's Liquor** (drinks and snacks) and 11 **Ammu-Nation**, each with its blip. Each store type shares one catalog at the top of the file. Any shop can require a licence with `licence = 'weapon'`.
