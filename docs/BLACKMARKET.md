# Black market (`veyl_blackmarket`)

Every illegal item in the game, sold by dealers through a custom menu.

```cfg
ensure veyl_blackmarket     # after veyl_inventory and veyl_interact (veyl_production is optional, see Reputation)
```

## Where and how

Two dealers stand in the world (`Dealers` in `config.lua`): the Dock Fixer and the Scrapyard Dealer. Walk up to one and pick **See what he has**. Add as many as you like; every dealer sells the same catalogue. Blips are off by default (`blip.show`), so players have to find them.

The menu has a category list, search, a grid of items with price and stock, and a side panel with the item, a quantity box (with **Max**) and a **Buy** button. Locked items (not enough reputation) and sold-out items are greyed and cannot be bought.

## What is for sale

| Category | Items |
|---|---|
| Pistols | AP Pistol, Pistol .50, Heavy Pistol, Ceramic Pistol, Machine Pistol, Revolver |
| SMGs | Micro SMG, SMG, Assault SMG, Combat PDW, Mini SMG, Gusenberg |
| Shotguns & Rifles | Sawed-Off, Assault/Bullpup/Heavy Shotgun, Assault, Carbine, Advanced, Special Carbine, Bullpup, Compact rifles, Marksman, Sniper, Heavy Sniper |
| Melee | Brass Knuckles, Switchblade, Dagger, Battle Axe |
| Ammo & Mods | all five ammo types, suppressor, extended magazine, scope, grip, flashlight |
| Drugs | weed baggie, joint, coke, meth, ecstasy, LSD, Veyl-X |
| Lab Supplies | chemical precursor, solvent, lab glassware |
| Break-in Tools | lockpick, door ram, drill, thermite, spray paint, fake plate |
| Hacking & Fraud | hacking device, black USB drive, radio |

A few weapons (Pistol .50, Heavy Pistol, Revolver) are also sold at Ammu-Nation, but there they need a weapon licence; here you pay more and need none. Delete or add lines in `Catalog` to change that.

## What the server decides

The page can only ask for `view` and `buy`. Everything else is checked on the server:

- the dealer exists and you are within `Distance` of that dealer (the server's own coordinates);
- the optional access item (`Access.Item`, for example `usb_darkweb`);
- street reputation: each item has a `level`, compared with your veyl_production reputation;
- amount is a whole number from 1 to `MaxPerLine`; anything else is refused and logged;
- a cooldown between purchases (`PurchaseCooldown`);
- stock: held per item, restocks `restock` units every `RestockMinutes`, stored in `veyl_blackmarket_stock` so a restart does not refill it;
- room to carry it, checked before you pay;
- payment is a durable debit with an operation id, delivery is a durable item grant with the same id, and a failed delivery refunds the money and puts the stock back. A retry never charges twice.

Every purchase is audited. Other resources can listen for `veyl_blackmarket:purchased` (source, citizenid, item, quantity, total).

## Reputation

Items with `level` above 0 need that reputation level from veyl_production (`exports.veyl_production:GetReputation(citizenid)`, added with this resource). If veyl_production is not running, every level gate is open.

## Police

`Police.Enabled` (off by default) gives each purchase a `Chance` of sending an alert through a dispatch resource that exports `Alert`.

## Tests

86 checks of the server rules run against a real database: the catalogue is valid, view and buy, distance, reputation, cash, bad amounts and unknown items, a full inventory, stock running out and restocking, a failed delivery refunding, the cooldown, the access item and the level gate when veyl_production is missing. The menu has 18 browser checks (categories, search, quantity, buying, locked and sold-out items, Esc). Not tested in game: the dealer peds, the screen opening over the world, and the item images in the live inventory (four of them, Veyl-X, the two chemicals and the door ram, were missing and were added).
