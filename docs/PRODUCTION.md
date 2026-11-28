# Production (`veyl_production`)

A fictional production game for VeylCore: buy supplies, gather, plant and tend, harvest, process on workstations, and run player-owned laboratories. Everything is invented game logic with abstract items and timers. Nothing models a real process.

## What is built and what is not

| Part | Status |
|---|---|
| Shared engines: placement, plant lifecycle, workstation queues, properties, progression, quality, logging, police hooks | Built and tested |
| **Botanical branch**: supply shop, buyer, gathering, plants, workstations, laboratories | Built and tested |
| **Field operations branch** (field zones, searching, branch growing) | **Not built.** The config already allows more branches; the tablet lists them greyed out and does nothing with them |
| **Supplier operations branch** (supplier runs, hazards) | **Not built** |

Why: the spec is a multi-week project. This is the shared infrastructure plus one complete branch, so the other two branches only need their own config and their own actions on top of the same engines. Nothing in the UI is a placeholder: every button works.

`veyl_drugs` is a separate, older resource and keeps running untouched. The two share nothing (own tables, items and UI), so you can run both, or drop `veyl_drugs` later.

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
| `veyl_lib` | `vlib.createScreen` (`open`, `send`, `close`, `isOpen`), `vlib.progress`, `vlib.alertDialog`, `vlib.inputDialog` | existing resources (`veyl_cityhall`, `veyl_drugs`) |
| `veyl_inventory` | durable `GiveItem / TakeItem / CanCarry`, `GetItemCount`, `GetInventoryItems`, `RemoveItem` (stash id as target), `RegisterStash` with `authorize`, `RegisterUseHandler`, `openInventory('stash', id)`, item definitions and metadata schemas in the inventory's own data files | `veyl_inventory/server/exports.lua`, `stashes.lua`, `client/ui.lua` |
| `veyl_interact` | `AddPed`, `AddZone`, `Remove` | `veyl_interact/client.lua` |
| `veyl_target` | `addSphereZone`, `removeZone`, `addLocalEntity`, `removeLocalEntity` | `veyl_target/client/main.lua` |

Limits worth knowing: VeylCore has no property or housing resource (laboratories are built here); the inventory has no call to resize or inspect an unloaded stash (see above); items are registered by editing the inventory's data files rather than at runtime; dispatch is optional.

Natives used: placement ray tests, `CreateObject`, `RequestIpl`, routing buckets (`SetPlayerRoutingBucket`). In-game checks of these are not done here.

## Tests

The server logic ran against a real MariaDB with VeylCore stubbed (120 checks): migrations, shop (price, stock, restock, level locks, forged names and quantities, cannot afford), gathering (distance, token, too-early finish, cooldown, one reward), plants (placement rules, caps, care, growth to ready, neglect, harvest quality metadata, failed-grant recovery, no double harvest), benches (placement, queue order, quality-first input use, cancel refunds, claim once, pack-up rules, restart), buyer (price by quality), laboratories (purchase, double-buy, entry, codes with lockout, staff roles and live access removal, upgrades with cost and cap, sell, buyback, transfer), police (disabled by default, raid timing, window, seizure), progression, and restarts. The tablet, shop, buyer and bench pages were clicked through in the preview (24 flows).

Not tested: in-game spawning, the placement preview, targeting, the interior teleport and IPL, and CEF rendering. Try these on a development server first.

## Admin

`/prodadmin diag` reports stuck batches (finished a day ago, never collected), batches whose bench is gone and plants whose lab no longer exists; `/prodadmin fix` cancels the orphaned ones. Everything notable is also in `veyl_prod_audit`, which can post to a Discord webhook (`Logging.Webhook`).

## Troubleshooting

- **"Production is starting up":** migrations did not finish; check the console for SQL errors.
- **Seeds do nothing:** `veyl_inventory` must be restarted after the new items, and the use handlers register once it is up.
- **Plants do not show:** `veyl_target` must be started; props appear within about 60 m.
- **Can not enter a lab:** it must be owned; locked labs need staff access or the code.
- **Interior is empty or you fall:** the IPL did not load; check `Interiors.*.ipl` or point it at your MLO.
