# veyl_drugs: criminal enterprise (fictional)

This is a drug-gameplay resource for VeylCore. All production is abstract game mechanics: fictional varieties, care
meters and challenges. There are no real recipes or instructions.

## Milestone status

| Milestone | Scope | Status |
| --- | --- | --- |
| **A** | Framework adapters, persistence, migrations, secure inventory operations | ✅ Built |
| **B** | Weed, coca and mushrooms: grow anywhere, placement, living plants, quality, harvest, supplier, Grow Journal | ✅ Built |
| C | Processing benches and challenges, packaging and branding, meth / ecstasy / LSD / Veyl-X | Not started |
| D | Street sales, buyer contacts, economy and demand, progression tracks | Not started |
| E | Crews and permissions, territories, police discovery and seizure, admin tools | Not started |
| F | Visual polish, prop tuning, performance measurement, live integration testing | Not started |

Nothing from C–F appears in-game yet. The UI has no placeholder buttons for them.

## What exists in this framework (and what doesn't)

| Integration | Used for | Real API |
| --- | --- | --- |
| Inventory | Items, metadata, use, take/give | `veyl_inventory` durable exports: `GiveItem`, `TakeItem`, `CanCarry`, `GetOperation` (operation ids), `RegisterUseHandler`, `GetItemCount` |
| Money | Supplier purchases | `veyl_core` `DebitOnce` / `CreditOnce` |
| Identity / online | Ownership, offline protection | `veyl_core` `GetCitizenId`, `GetSourceByCitizenId` |
| Targeting | Plant options on local props, supplier ped | `veyl_target` `addLocalEntity` / `removeLocalEntity`, `veyl_interact` `AddPed` |
| UI | Menus, dialogs, progress, focus | `veyl_lib` (`vlib.createScreen`, `registerMenu`, `inputDialog`, `alertDialog`, `progress`) |
| **Properties** | Interior planting | **No property/housing resource exists.** Adapter = `none`: interiors follow `Placement.AllowInteriors` (default `false`) |
| **Phone** | Buyer messages (milestone D) | **No phone resource.** Adapter = `standalone` (the Grow Journal tablet) |
| **Police / dispatch / evidence** | Discovery and seizure (milestone E) | Only the `police` job in `veyl_core` exists. There is no dispatch or MDT yet |
| Crews | Shared access (milestone E) | Core gangs exist (`veyl_core/shared/gangs.lua`); the crew adapter is not built yet. **Until then plants are owner-only** |

## Installation

1. Start order (already added to `server.cfg.example` and the txAdmin recipe):
   ```cfg
   ensure veyl_inventory
   ensure veyl_target
   ensure veyl_interact
   ...
   ensure veyl_weedprops   # custom weed models (stream resource, kept outside this repo)
   ensure veyl_drugs
   ```
   `veyl_weedprops` lives in `server/resources/veyl_weedprops` on your server. It is not in the GitHub repo, so a
   fresh install needs it copied in. Without it, weed falls back to the base-game Biker DLC weed props.
2. Restart the server. Migration `001_plants` creates three tables:
   - `veyl_drug_plants`
   - `veyl_drug_logs`
   - `veyl_drug_supplier_stock`
3. The items live in `veyl_inventory/data/items.lua`; their metadata schemas are in `veyl_inventory/server/items.lua`.
   Images come from the RAINMAD gallery and are listed in `web/images/CREDITS.md`.

## Gameplay (milestones A–B)

### Getting supplies

The **Garden Supplier** (ped, no blip) is at Grapeseed (`DrugsConfig.Supplier.coords`). It sells:

| Item | What it's for |
| --- | --- |
| Seeds | One item per variety (variety stored in metadata) |
| Plant Pot | Planting in a pot instead of the ground |
| Grow Tub | Required for mushrooms |
| Grow Nutrients | Care |
| Grow Journal | The tracking tablet |

Payment is cash only. Stock is limited and restocks every 30 minutes, and stock is saved across restarts.

### Planting

Use a seed from your inventory to enter placement mode.

- **Preview:** a see-through preview follows where you look. Its outline is **green** when the spot is valid and
  **red** when it isn't, with the reason shown below it.
- **Controls:** **E** place, **R** or the mouse wheel rotate, **G** switch between ground and pot (when you carry a
  pot), **Esc** or **Backspace** cancel.
- **Checks (client and server):** distance, slope (22° max), spacing (1.1 m), restricted zones (police stations,
  hospitals, Legion Square, City Hall), people, vehicles and objects in the way, crowding (24 plants within 20 m), your
  limit (30), interiors, and routing bucket.
- **Items:** cancelling or a failed placement takes nothing. The server takes the seed (plus the pot or tub) only when
  it accepts the placement.

### Plant care

Target a plant to see its options:

| Option | Who sees it | Uses | Time |
| --- | --- | --- | --- |
| Inspect | Everyone | — | — |
| Water | Owner | 1 Water Bottle | 3.5 s |
| Add nutrients | Owner | 1 Grow Nutrients | 4.5 s |
| Harvest | Owner, when ready | — | 6 s |
| Remove plant | Owner | — (asks to confirm) | 4 s |

Strangers who inspect only see what you could tell by looking at the plant.

### Growth

| Rule | Detail |
| --- | --- |
| Stages | 4 visible stages, each with a different prop |
| Meters | Water and care drain over time; health falls only while water or care is empty |
| Offline protection | While the owner is offline, drain is 4× slower and health never drops below 40, so plants never die offline |
| Ready window | A ready plant keeps its value for 48 hours, then slowly wilts (never below 25) |
| Quality | Comes from how well the plant was kept while it grew (care score), capped by the variety, then graded **Standard / Premium / Exotic** |

**Harvest metadata:** each harvest carries `{ product, variety, varietyLabel, grade, quality, batch }`, and the
inventory shows it under the item. Stacks only merge when all of these match, so batches never mix.

### Varieties (trade-offs)

| Product | Variety | Trade-off |
| --- | --- | --- |
| Cannabis | Violet Haze | Balanced (3 h, yield 6, cap 92) |
| | Silverleaf | Low maintenance, slower (4.5 h), larger yield 7, cap 74 |
| | Nightbloom | Demanding care, small yield 4, can reach Exotic (cap 100), higher buyer demand |
| Coca | Andes Mist | High ceiling (90), yield 5 |
| | Red Ridge | Large yield 7, lower ceiling (70) |
| Mushrooms (tub only) | Mooncap | Thirsty, high ceiling (98) |
| | Forest Cap | Quick (2.5 h) and forgiving, cap 72 |

### Grow Journal

Use the item or `/growjournal` (requires the item) to open the tablet.

- **Shows:** stats (plants, ready, needing attention, locations), plus All, Ready and Needs-attention filters, search,
  and a details panel with meters, time left, expected yield, current quality and location.
- **Waypoint:** sets a waypoint to the plant. The journal **cannot** tend plants remotely.
- **Settings:** a reduced-motion option.

## Server authority and durability

| Path | Guarantee |
| --- | --- |
| Placement | A `pending` row with a unique operation id, then the seed and container are taken with operation ids, then the plant becomes `growing`. Replaying the same request plants nothing. At startup, an interrupted placement is finished if its seed was taken, or dropped (and the seed refunded) if it wasn't |
| Actions | Server-issued token and duration. The server re-checks permission, distance and bucket at completion. Too-fast, replayed and remote completions are refused and logged as suspicious. The care item is taken with an operation id |
| Harvest | A conditional claim (`growing → harvesting`) means only one player can win. Then `GiveItem` with operation `harvest:<id>`. If the inventory is full, the claim is released and nothing is lost. A timeout is settled from the inventory operation record (delivered once) |
| Growth | Computed from timestamps every 5 minutes in memory and written in batches every 10 minutes and on every action. Server downtime counts as offline time |
| Streaming | The server sends only plants within 120 m in your routing bucket (spatial grid, max 250). Props spawn within 90 m and are cleaned up on despawn, logout and resource stop. Plant locations are never broadcast globally |
| Supplier | Stock is reserved, then `DebitOnce`, then `GiveItem` (same operation id). It refunds once if the items can't be handed over. Inventory space is checked before paying |

## Assets

| Prop | Status |
| --- | --- |
| Cannabis: `veyl_weedprops` (`an_weed_<colour>_01_small_01a` → `_01_small_01c` → `_med_01b` → `_lrg_01b`) | Custom stream resource. Varieties use purple (Violet Haze), white (Silverleaf), blue (Nightbloom) and yellow (Sunburst). The base-game `bkr_prop_weed_*` set is the product fallback |
| Coca: `h4_prop_bush_cocaplant_01` (Cayo Perico Heist DLC) | Base game, free, no download. GTA has one coca bush size, so the four stages draw it at 35 / 60 / 85 / 100 % scale (72 % max in a pot). Confirmed in the [GTA V object list dump](https://github.com/DurtyFree/gta-v-data-dumps) |
| Mushroom tub: `prop_weed_tub_01/01b`; stage cluster `prop_veg_crop_03_cab` | Stand-ins |
| Watering can `prop_wateringcan`, scissors `prop_cs_scissors` | Base game |

- **Missing models:** any configured model missing from your game build falls back to `prop_plant_01a`, with one console
  warning per model. Custom coca or mushroom props would improve the look. No custom assets are required.
- **Item images:** downloaded from the RAINMAD FiveM image gallery. It publishes no explicit licence, so check before
  public redistribution.

## Tests

### Run (outside the game)

| Check | Result |
| --- | --- |
| Server code in a Lua VM with an in-memory DB, inventory and money service, 44 checks. Covered: the growth model (determinism, offline floor, online death, care to quality, variety caps, Exotic reachable, overripe floor); placement (variety, distance, interiors, restricted zone, pot item, mushrooms tub-only, in-vehicle, success takes one seed, replay, spacing, wrong variety); actions (stranger blocked, stranger inspect redacted, busy, too-fast, replayed token, item taken once, remote refused, not-ready harvest); harvest (inventory full keeps the plant, delivered once with metadata, gone afterwards, no second harvest, only one of two simultaneous claims wins, timeout reported as pending); startup recovery (timed-out harvest delivered once, interrupted placements finished or dropped); supplier (stock, charge and delivery, repeat not charged, full inventory refused before paying, stock limit, distance) | ✅ 44/44 |
| Browser preview (journal and grow HUD): 12 checks. Covered: filters, search, keyboard selection, waypoint, reduced motion, Escape order, empty state, passive overlays have no pointer events, no full-screen backdrop | ✅ 12/12 |
| Browser preview: the journal fits at 1280×720, 1920×1080 and 3440×1440 | ✅ 3/3 |
| Lua syntax (181 files), all 10 UI builds | ✅ |

### Needs your live server

- [ ] Props render at each stage; adjust prop names in `config/products.lua` if any fall back.
- [ ] The placement outline colours (`SetEntityDrawOutline`) and the slope check on real terrain.
- [ ] Two players next to the same ready plant, both pressing Harvest. (Until crews exist, only the owner can harvest,
      so this needs a second character added as crew in milestone E. The database race itself is covered above.)
- [ ] A full inventory at harvest; disconnecting mid-action; restarting `veyl_drugs` with plants out; reconnecting.
- [ ] A separate routing bucket: plants in bucket 0 are not visible in bucket 1.
- [ ] Performance with many plants in one field: watch client frame time with 25+ plants in view, and server tick time.
      No performance figures are claimed until they're measured.

## Known limitations and blockers

- **Interiors:** off by default, because there is no property system to ask for permission.
- **Shared access:** plants are owner-only until milestone E adds crews.
- **Police:** police can't interact with plants yet (milestone E).
- **Coca and mushroom props:** these use generic stand-in props.
