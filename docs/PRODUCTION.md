# Production (`veyl_production`)

The drug system for VeylCore (it replaced the old `veyl_drugs`, which is removed): buy supplies, gather, plant and tend, harvest, process on workstations, and run player-owned laboratories. It is game logic with item names, timers and quality, and nothing models a real process. **Botanical** is weed (Violet Haze, Silverleaf, Nightbloom: bud, trimmed bud, bagged weed on a Weed Table). **Field operations** is coca and mushrooms: Red Ridge and Andes Mist coca become coke on a Coke Table, and Forest Cap and Mooncap mushrooms are grown from spores (found in field zones, bought at the outfitter or sifted from wild mushrooms) and dried. **Supplier operations** is the chemical supply runs and the Meth Station with the fumes hazard: crystal (level 1), ecstasy (2), LSD tabs (3) and Veyl-X (5), each behind a skill check. Cannabis uses the custom `veyl_weedprops` models, so start it before `veyl_production`. The ids (`prod_*`) are generic; names, descriptions and images are just labels you can change in `config/`, `shared/items.lua` and `veyl_inventory/data/items.lua`.

## What is built and what is not

| Part | Status |
|---|---|
| Shared engines: placement, plant lifecycle, workstation queues, properties, progression, quality, logging, police hooks | Built and tested |
| **Botanical branch**: supply shop, buyer, gathering, plants, workstations, laboratories | Built and tested |
| **Field operations branch**: outfitter shop, field zones with several search points, field plants, field workstation recipes, field laboratory | Built and tested |
| **Supplier operations branch**: supplier contacts and runs, supply-kit recipes with a skill check, a fictional fumes hazard, supplier laboratory | Built and tested |

The three branches run on the same engines (placement, plants, workstation queues, properties, progression); each only adds its own config (`config/botanical.lua`, `config/field_operations.lua`, `config/supplier_operations.lua`) and its own actions. Switch a branch off with `Branches.<name>.enabled` in `config/main.lua`. Nothing in the UI is a placeholder: every button works.

Not built: dispute or war mechanics between crews over territory (control is by influence only).

`veyl_drugs` is gone: its code, UI package and docs were deleted, and its items that nothing else uses were removed from `veyl_inventory`. Its database tables were left alone so you can look at or export the old data first. When you do not need it, drop them: `DROP TABLE IF EXISTS veyl_drug_plants, veyl_drug_logs, veyl_drug_supplier_stock, veyl_drug_equipment, veyl_drug_crafts;`. Players still holding a removed item (for example Cannabis Seed) will see it as an unknown item.

## Install

```cfg
ensure veyl_core
ensure veyl_lib
ensure veyl_inventory
ensure veyl_interact
ensure veyl_target
ensure veyl_production
```

1. **Database.** Nothing to run by hand: the tables are created and migrated at start (`server/database.lua`, tracked by `Veyl.Migrate`). `sql/install.sql` has the same schema. It needs `oxmysql`, which VeylCore already uses.
2. **Items.** The `prod_*` items are defined in `veyl_inventory/data/items.lua` with their quality schema (`prod_product`) in `veyl_inventory/server/items.lua`, and their images in `veyl_inventory/web/images/`. That is how VeylCore registers items; `shared/items.lua` lists the same names for this resource. Restart `veyl_inventory` and `veyl_production` after updating.
3. **Open:** the supplier and buyer peds, gathering spots and laboratory doors are in the world (see `config/`), `/production` opens the tablet anywhere.
4. **Admin permission:** `production.admin` (through `Veyl.HasPermission`) opens any lab storage and allows `/prodadmin`.

## Playing it

- **Supplier** (Sandy Shores by default): seeds, planters, water, tonic, and a Prep Table (level 2). Stock refills over time.
- **Gather** at wild spots with the target prompt for herbs, tonic, water and the odd seed. Each spot has a cooldown for you.
- **Plant:** use a seed from your inventory. A ghost follows where you look: green is fine, red says why not. `E` places, `R` or scroll rotates, `Esc` cancels. Seeds and a planter are used up only when the server accepts it.
- **Tend:** target a plant to inspect, water, feed, harvest or remove it. Meters fall over real time, also while you are offline. Steady care means better quality; neglect stalls growth and then kills the plant.
- **Process:** set up a Prep Table, use it to queue recipes (blend, pack, mix tonic). Batches have timers that survive restarts; collect them when ready.
- **Sell** finished goods to the buyer. Price depends on quality (Poor ×0.6 up to Flawless ×2.0).
- **Laboratories:** buy one at its street door or in the Properties page. Inside you get private storage, lab benches (more slots with upgrades), plants and staff. Lock it, set an access code, add employees (storage, benches, plants) or guests (enter only). Upgrades: storage, bench slots, equipment, security. Sell it back for 60% and buy it back for a day, or give it to a nearby player.

### Field operations

- **Outfitter** (field seeds, planters, water, tools). Stock refills over time like the other shops.
- **Field zones** (Alamo shore, Canyon floor by default): each zone has several search points. A prop shows at every point near you; target one and choose Search. The server checks you are within range on the ground plane, then gives a token; the reward comes only after the minimum search time. Each point has a global respawn (someone else just searched it) and you have your own cooldown on it.
- **Field plants** (Dawnroot, Duskbloom) use the same plant engine as botanical, with their own seeds, growth times and yields. Field recipes run on any workstation, and a field laboratory is on the property list.

### Supplier operations

- **Contacts** (a ped each, with level, fee, opening hours and a daily run limit). Taking a run charges the fee, picks a pickup and a drop at random and gives you a time limit.
- **Run:** go to the marked crate with an open-bed truck (a Bison, Sandking, Rebel and so on, listed in `Supplier.Truck.Models`), back it up next to the crate and load it: the crate is a networked prop attached to the truck bed, so everyone sees it ride along. Drive to the drop, park within `DropVehicleRadius`, walk to the marker and unload. The server checks the truck model, that it is beside the crate when you load and at the drop when you unload, that you are with it, that the trip was not faster than `MaxSpeed` allows and that the run has not expired. If the truck is gone the crate is lost (drop the run); after a server restart any allowed truck at the drop counts. Delivering fast enough earns a bonus on supply kits. A run is stored in `veyl_prod_runs` so it survives a reconnect, and expired runs are closed on start. Dropping a run does not refund the fee and starts a wait. Set `Truck.Required = false` to go back to carrying the crate on foot. The bed position is worked out from the truck's size; fix a model that sits wrong with `Truck.Offsets`.
- **Supply kits** feed the supplier recipes at a workstation. Those recipes use a **skill check**: the server issues a token, the client plays a few rounds of `veyl_minigames` lockpick, and the score comes back with the start request. The score can only move quality within `QualitySwing` (or reduce the yield to `ZeroYield`); it can never create or skip the inputs, timers or limits. If you cannot trust a client score at all, set `Skill.QualitySwing = 0`.
- **Hazard:** working at a hazardous station raises a fictional exposure meter on the server (the page just shows the number). Above the threshold you take small health damage; an item (`prod_respirator`) cuts exposure, and it falls when you step away. Nothing in it models a real substance.

## What the server enforces

| Rule | Where |
|---|---|
| Distance, ownership and permission checks come from the server's own view of the player. Client coordinates for placement are only a hint; they are re-checked (distance, restricted zones, spacing, interior bounds) | `Prod.Place.problem`, `server/plants.lua`, `server/workstations.lua` |
| Prices, stock and quality come from config and the item's stored metadata; the page only names an item and a quantity | `server/shop.lua` |
| Every inventory and money change is a durable operation with an id (`GiveItem`, `TakeItem`, `DebitOnce`, `CreditOnce`), so a retry never doubles or loses anything; multi-step actions undo the earlier steps if a later one fails | `server/inventory.lua` |
| Harvest is claimed once: a database claim stores the roll, and the grant uses an operation id built from it. A crash or failed grant releases the claim, a repeat gives the same result at most once | `Plants.harvest` |
| A batch is claimed once: its state flips from `active` to `claimed` atomically before the output is granted (reverted if the grant fails) | `Ws.claim` |
| Cooldowns (stored for long ones), action tokens with a minimum duration for gathering and raids, and a count of forged requests | `server/security.lua`, `server/gathering.lua` |
| Property purchase and upgrades use a conditional database update first, then charge, and revert if the charge fails; two clicks cannot both win | `server/properties.lua` |
| Access codes are salted, stretched SHA-256 hashes with an attempt limit and lockout; they are never logged | `server/crypto.lua`, `Props.enter` |
| Storage access is decided live by this resource (`AuthorizeStash`, called by `veyl_inventory` on every open and change), so removing someone's access takes effect at once | `Props.authorize` |

## Laboratory interiors

A lab is a private instance: entering sets the player's routing bucket (`BucketBase + property index`) and teleports them into an interior, so one interior serves any number of labs. The default interior is the Biker DLC warehouse, loaded through its IPL (`config/properties.lua`). Benches and plants are placed freely inside the interior's radius; storage is opened from the exit point or the management page. To use your own MLO, add an entry to `Interiors` with its `spawn`, inside `door` and `radius`.

A player who disconnects inside a lab is put back at its door on their next load (`propRecover`).

**Storage capacity changes** apply when the stash is next loaded by the inventory (closing it unloads it), because `veyl_inventory` reads a stash's size when it loads it.

**Storage and selling:** the inventory cannot look into a stash that is not loaded, so selling or transferring does not check that storage is empty. A sale or transfer to a new person gives the new owner a fresh, empty storage; the old one stays behind, and staff with `production.admin` can still open it (every earlier storage stays registered). Selling it back to the same person (buyback) restores it. Tell players to empty it first. The sale confirmation says so.

## Police (off by default)

`config/police.lua`: `Enabled = false`. When enabled:

- **Raids** need the police job on duty (checked server-side) and `MinOnDuty` officers. Police breach the door (a timer on the server that security upgrades lengthen); a raid opens a window in which police can walk in and open the storage, and **Seize** removes the configured items from storage (open it once first so it is loaded) and cancels bench batches. A lab cannot be raided again for the cooldown.
- **Alerts** (plants, harvest, workstations, lab entry) have a chance and a per-player cooldown. They only go out when `Dispatch.Enabled = true` and the resource in `Dispatch.Resource` is started and exports `Alert` (VeylCore's `veyl_dispatch` does). Nothing else is assumed: to use another dispatch, change `Pol.send` in `server/police.lua`.

## Verified API audit

Checked against the repository source:

| Resource | Used | Verified in |
|---|---|---|
| `veyl_core` | `Veyl.Startup`, `Veyl.Migrate`, `Veyl.RegisterCallback(name, fn(src, citizenid, ...), { cooldown })`, `Veyl.Callback / CallbackTimeout / Await`, `Veyl.Ok / Err / NewId / Audit / Notify / NotifyResult`, `GetPlayerData / GetPlayerCoords / GetCitizenId / HasPermission`, `GetSourceByCitizenId`, durable `DebitOnce / CreditOnce` | `veyl_core/lib/*.lua`, `server/exports.lua` |
| `veyl_lib` | `vlib.createScreen` (`open`, `send`, `close`, `isOpen`), `vlib.progress`, `vlib.alertDialog`, `vlib.inputDialog` | existing resources (`veyl_cityhall`) |
| `veyl_inventory` | durable `GiveItem / TakeItem / CanCarry`, `GetItemCount`, `GetInventoryItems`, `RemoveItem` (stash id as target), `RegisterStash` with `authorize`, `RegisterUseHandler`, `openInventory('stash', id)`, item definitions and metadata schemas in the inventory's own data files | `veyl_inventory/server/exports.lua`, `stashes.lua`, `client/ui.lua` |
| `veyl_interact` | `AddPed`, `AddZone`, `Remove` | `veyl_interact/client.lua` |
| `veyl_target` | `addSphereZone`, `removeZone`, `addLocalEntity`, `removeLocalEntity` | `veyl_target/client/main.lua` |

Limits worth knowing: VeylCore has no property or housing resource (laboratories are built here); the inventory has no call to resize or inspect an unloaded stash (see above); items are registered by editing the inventory's data files rather than at runtime; dispatch is optional.

Natives used: placement ray tests, `CreateObject`, `RequestIpl`, routing buckets (`SetPlayerRoutingBucket`). In-game checks of these are not done here.

## Tests

The server logic ran against a real MariaDB with VeylCore stubbed (120 checks): migrations, shop (price, stock, restock, level locks, forged names and quantities, cannot afford), gathering (distance, token, too-early finish, cooldown, one reward), plants (placement rules, caps, care, growth to ready, neglect, harvest quality metadata, failed-grant recovery, no double harvest), benches (placement, queue order, quality-first input use, cancel refunds, claim once, pack-up rules, restart), buyer (price by quality), laboratories (purchase, double-buy, entry, codes with lockout, staff roles and live access removal, upgrades with cost and cap, sell, buyback, transfer), police (disabled by default, raid timing, window, seizure), progression, and restarts. The tablet, shop, buyer and bench pages were clicked through in the preview (24 flows).

Field and supplier branches add checks for: field points (range, per-point and per-player cooldown, token and minimum time), supplier runs (level, fee, hours, daily limit, pickup and drop distance, speed, expiry, one active run, cancel wait, idempotent delivery), skill-check tokens (single use, expiry, score clamp) and the hazard (exposure, protection, decay). The suite is 266 checks in all, including the admin farms, street sales, market, crews, territories, regulars, group runs and staff tools.

Not tested: in-game spawning, the placement preview, targeting, the interior teleport and IPL, and CEF rendering. Try these on a development server first.

## Market, territories, regulars, crews and staff tools

- **Market** (`server/market.lua`, `config/economy.lua`): every sale, at the buyer or on the street, pushes that item's price down (`Impact` per unit, never below `MinMult`) and the pressure drains over time (`RecoverPerHour`). A small daily swing makes prices differ from day to day. The buyer page and the tablet's **Street** page show the live price and whether demand is high, steady or the market is flooded.
- **Territories:** areas on the map (`Territories.Areas`) change the price and how willing peds are. Street sales there build **heat** (peds get cagey, police alerts get likelier) which cools by itself, and add **influence** for your crew, or for you without one. Whoever has the most influence (above `MinToControl`) holds the area, and its members get `ControlBonus` on street prices there. Influence decays by a share each hour.
- **Regulars:** a ped you sold to may want to deal with you again (`ChanceOnSale`). From the **Street** page you call one: the server picks a meeting spot in their area, you get a GPS point, and a private ped waits there (only you see them). They buy more than strangers and pay more as loyalty grows. A meeting works once, and each regular has a call cooldown.
- **Crews** (**Crew** page): a leader and up to `MaxMembers`. Members can use each other's outdoor plants and benches (the leader can switch this off; labs keep their own access), members' XP pools into a crew level, and each crew level adds `SellBonusPerLevel` to what members get when selling. Create (costs `CreateCost`), invite someone nearby, accept, remove, leave (leadership passes on) and close are all server checked.
- **Group supplier runs:** the person who starts a run can invite up to `Groups.MaxMembers - 1` people nearby from the Chemistry page. Everyone at the drop (within `Groups.DropRadius`) gets the kits, with `KitBonusPerExtra` more for each extra person. Only the leader loads and unloads the crate.
- **Fumes:** from `Hazard.StaminaAt` exposure you cannot sprint or jump and tire faster, as well as the health damage.
- **Staff tools (`/drugadmin`, `production.admin`):** besides farms, the menu has **Players** (who is online: their plants, benches, branch levels and crew; remove a plant, give or take XP, reset their cooldowns, read their log) and **Recent activity**. Every call re-checks the permission on the server and is logged.

## Admin farms (`/drugadmin`)

Staff with the `production.admin` permission get an in-game menu to place farms without touching config:

1. Stand where the farm should be and run `/drugadmin`, then **Add a farm here**. Pick a kind: **weed farm** (weed buds and seeds), **coke farm** (coca leaf and coca seeds), **mushroom patch** (wild mushrooms and spores) or **custom** (herbs, change it after). The spot you stand on is the first point.
2. Open the farm in the list to **add a point** at your position (walk, add, walk, add), remove a point, set GPS or teleport to it, or delete it. A prop appears at every point for everyone as soon as it is added.
3. **Rewards** lists what a search can give: pick an item, a chance (percent), least and most, and an optional level. The first reward always pays. **Name, level and timings** sets the level needed, how long a point stays picked over for everyone (respawn) and for the same player (cooldown), and the prop model.

Players search a farm's points like a field zone: a timed search, a per-point and a per-player cooldown, everything decided by the server. Farms are saved in `veyl_prod_farms`. The server checks the permission on every request, so a player who calls these callbacks by hand is refused and logged. Presets, limits and the allowed reward items are in `config/street.lua`. Weed farms count toward the botanical level, coke farms and mushroom patches toward field operations.

## Selling to pedestrians

Target any ped and pick **Offer product**. The server checks the ped (a real ped, not a player, not police or medics, close, alive), whether you carry anything sellable, then rolls whether they are interested (`AcceptChance`). If they are, you choose what to sell and how many; they take 1 to 3 units and pay `PriceMultiplier` (70%) of the buyer's price at your item's quality. A ped is used up for everyone for `PedCooldown` (15 minutes) whatever they answered, so asking again gains nothing, and there is a per-player offer limit per hour. Only finished goods can be sold this way (`Street.Items`). A sale or a refusal can raise a police alert with the `street_sale` rule in `config/police.lua` when police alerts are on.

Not tested in game: target options on pedestrians, the reactions (turning, standing still, wandering off) and whether every ambient ped has a network id on your server settings. This needs OneSync, because the server has to see the ped; if it cannot, the offer is refused with "Get closer to them".

## Admin

`/prodadmin diag` reports stuck batches (finished a day ago, never collected), batches whose bench is gone and plants whose lab no longer exists; `/prodadmin fix` cancels the orphaned ones. Everything notable is also in `veyl_prod_audit`, which can post to a Discord webhook (`Logging.Webhook`).

## Troubleshooting

- **"Production is starting up":** migrations did not finish; check the console for SQL errors.
- **Seeds do nothing:** `veyl_inventory` must be restarted after the new items, and the use handlers register once it is up.
- **Plants do not show:** `veyl_target` must be started; props appear within about 60 m.
- **Can not enter a lab:** it must be owned; locked labs need staff access or the code.
- **Interior is empty or you fall:** the IPL did not load; check `Interiors.*.ipl` or point it at your MLO.

## Plant stat cards and unlimited shops

- **Stat cards:** stand near a plant you tend and a card floats over it with health, growth, water and fertiliser rings, the variety and its stage. A ripe plant says *Ready to harvest*, a dead one *Dead*. Tune `ProductionConfig.Overlay` (`Distance`, `Max` cards at once, `Height`, `Enabled`). The numbers come from the server's plant list, refreshed every 15 seconds while a card is showing and after each water, feed or harvest.
- **Unlimited supplies:** `ProductionConfig.UnlimitedStock = true` (default) means the supply shops never run out and stock is not tracked. Set it to `false` for the old limited stock that refills over time.

- **Map blips:** a blip appears on each laboratory you own or work at, and only those (a lab you have not bought shows nothing). It appears after you buy, goes when you sell or lose access, and refreshes every minute otherwise. Tune or turn off with `ProductionConfig.Properties.Blip`.

- **Who can use `/drugadmin` and `/prodadmin`:** anyone with the `production.admin` permission, and also anyone with the general `veyl.admin` permission (the one `group.admin` gets in `server.cfg`), so full admins need no extra line.

## Labs that grow as you upgrade them

Each upgrade you buy changes what the lab looks like inside, the way the GTA Online biker businesses do. The three lab interiors are the Biker DLC ones, and each has switchable sets of props (tables, plants, lamps, hoses, presses, cameras and a steel door). The server sends only the four upgrade levels; your game switches the right sets on. If you buy an upgrade while standing inside, the screen fades, the new equipment appears and you get a message.

| Lab (interior) | Storage | Workstation slots (benches) | Equipment | Security |
|---|---|---|---|---|
| **Weed farm** (`biker_warehouse`) | product on the tables, then chairs, then drying racks | 3 → 5 → 7 → 9 grow rooms, each with its lamp and hose | standard kit, then upgraded kit, brighter lamps, then fans and mould buckets | cameras, then the steel door |
| **Meth lab** (`biker_field`, the field labs) | finished product appears | empty room → basic kit | basic → upgraded kit | steel door at level 2 |
| **Cocaine lockup** (`biker_supplier`, the supplier labs) | cut coke on the tables | the production line appears | basic → upgraded presses and tables, then the upgraded line | low → high security |

Turn it off with `ProductionConfig.Properties.Visuals = false`. The set names and the rules for each level are in `client/lablooks.lua`. Nothing here changes how the lab plays; it is only how it looks.
