# Vehicle customs (`veyl_customs`)

Vehicle customisation and the mechanic business: a live preview of the real car model, a Paint Studio, server-priced checkout, mechanic work orders with versioned quotes, parts stock, service bays, a workshop dashboard and saved builds.

## Install / start order

```
ensure veyl_vehicles     # needs migration 004_props_version (applied automatically)
ensure veyl_interact
ensure veyl_target       # optional: vehicle options for mechanics
ensure veyl_world        # optional: lighting preview (local only)
ensure veyl_business     # optional: shop money into a business account
ensure veyl_mechanic
ensure veyl_customs
```

The page is built from `packages/customs-ui` (`npm run build -w @veyl/customs-ui`, also part of `npm run build`) into `veyl_customs/web/dist`.

**Back up the database first.** Migrations only add tables and one column (`veyl_player_vehicles.props_version`). Rollback: stop `veyl_customs`, `DROP TABLE customs_orders, customs_order_lines, customs_stock, customs_part_orders, customs_tx, customs_builds, customs_shop_settings, customs_audit;` and delete its rows from `veyl_migrations` (`resource = 'veyl_customs'`). The extra column is harmless to leave.

## How players use it

**Self-service** (shops with `mode = 'self'` or `'both'`, and `'mechanic'` shops with `selfFallback` while no staff is on duty): drive in, stop at the entrance marker, *Customise vehicle*.

**Mechanic shops:** the customer can *Request service* at the desk. An on-duty mechanic targets the car, *Write a customs quote*, builds it in the same customiser and *Save quote* (a draft). In the dashboard they *Send quote*; the customer sees it with `/customsquote` (or *My quotes* at the desk) and approves that exact version (paying then) or rejects it. The mechanic *Start work* (a free bay is reserved), then installs each line at the car: target it, *Install approved work*, a short animated job per item. When the last line is in, the order completes and the customer is told.

**Customiser:** top tabs Performance, Bodywork, Wheels, Paint, Lighting, Details (only options the vehicle has; motorcycles hide car-only items). Left panel: pick an item, then a value; each row shows this shop's price (from the server). Bottom: drag to rotate, scroll to zoom, hold **Space** to compare with the original, *Reset view*, *Photo* (hides the page; any click / E / Esc brings it back), *Saved builds*, the build total and *Review build*. Review lists every change with its price; remove single lines or *Undo all*; *Get final quote* then pay (card / cash). **Esc** steps back and asks before discarding unsaved changes.

**Paint Studio:** Primary / Secondary / Pearl; saturation-brightness square, hue slider, hex and RGB entry; finishes; saved swatches (per character, right-click to remove); named colour pairs. Picker changes are a temporary preview; *Add to build* puts the paint into the cart. Lighting buttons (Studio / Daylight / Sunset / Night) change only your own screen through `veyl_world`; without it they are disabled with a note.

## What is customisable

From `shared/catalog.lua`, each with its own semantics:

| Kind | Options |
|---|---|
| Indexed mods (`SetVehicleMod`, -1 = stock) | engine, brakes, transmission, suspension, armour (levels capped by `Config.Performance`), spoiler, bumpers, skirts, exhaust, roll cage, grille, hood, fenders, roof, arch covers, aerials, trim, fuel tank, engine block, air filter, struts, wheels (front 23 / bike rear 24), horn, livery mod, interior parts (trim, ornaments, dashboard, dials, door speakers, seats, steering wheel, shifter, plaques), plate holder, vanity plates |
| Toggle mods | turbo, xenon headlights, tyre smoke |
| Index settings | wheel type, wheel colour, window tint, plate style (style only, never the plate text), xenon colour, interior / dashboard colour, pearlescent |
| Livery | `SetVehicleLivery` (only if the model has liveries) |
| Extras | each extra the model has, on/off |
| Paint | primary / secondary: an indexed GTA paint + optional custom RGB |
| Neon | which tubes are on + colour (cars only) |

Counts and names come from the game for the actual model after `SetVehicleModKit(0)`; slots with zero options are hidden. Wheel lists refresh when the wheel type changes.

**Paint finishes** are explicit GTA paint indexes: Metallic = 0, Classic = 147, Matte = 12, Brushed metal = 117, Chrome = 120. A custom RGB colour is drawn over that index, so the index gives the finish. Pearl shows only on metallic. There is no "Gloss" native, so there is no Gloss button.

## Rules the server enforces

- **One session per player and per vehicle**, only for owned vehicles that are out, inside the shop radius. Self-service: only the owner. Quotes: on-duty staff of that shop's job.
- **Preview isolation:** the car you see is a local, non-networked copy standing exactly where your car is (or at a shop's optional `preview` point). Your real car, and you if seated, are hidden on your screen only while the session is open, and the copy and the real car cannot collide. The real vehicle is never touched by the preview, so unpaid changes cannot be driven or saved. Closing (any way: Esc, death, logout, disconnect, the real car or the copy disappearing, server session ending, resource stop) deletes the copy, restores the camera, focus, player and lighting.
- **Prices are server-side** (`Config.Prices` × shop multiplier, + labour %, + tax %). The client only sends option keys and values; each is validated against the catalogue (`CustomsCatalog.Clean`). Options a shop does not sell are refused.
- **Self-service checkout:** a quote has a version and expires (`QuoteMinutes`); checkout must name the current version. Workflow, recorded in `customs_tx`: `pending` → charge with `DebitOnce` (operation id `customs:self:<session>:<version>`) → `charged` → save looks with `ApplyOwnedProps` and the vehicle's `props_version` → `completed`. If saving fails (the car was changed elsewhere) the money is refunded (`CreditOnce`, `...:refund`) → `refunded`. On restart, `charged` rows are reconciled: a newer `props_version` means it was saved (completed), otherwise the customer is refunded. Money and the vehicle row are different resources, so this is a compensating workflow, not one transaction.
- **What is saved:** the vehicle's saved looks from the database plus only the purchased lines, never the client's whole property table. `veyl_vehicles` then treats those looks as authoritative for the live car: a later garage park cannot overwrite them with an older client report.
- **Durable id:** the order and the money refer to `veyl_player_vehicles.id`; the plate is a display copy and the network id is only used to find the live car (re-checked against the owned id).

## Mechanic orders

States: `draft → sent → approved → in_progress → completed`; `sent → rejected | expired` (after `SentQuoteHours`); `draft / sent / approved / in_progress → cancelled`. Every change is a conditional `UPDATE ... WHERE status = <expected>`, so two actions cannot both win.

- Editing a sent quote creates a **new version** in `draft`; it must be sent and approved again. The customer approves a specific version; an old version cannot be approved.
- Only the customer of that order can approve or reject.
- **Payment timing:** `on_approval` (the only mode implemented): the customer pays the total when approving. Parts are reserved and a free bay is reserved at approval.
- **Installing:** the server checks the order is in progress, the mechanic is on duty and assigned (or a manager), the car is in the shop and next to them, the minimum work time passed and the part is in stock. Then it saves that line onto the car (`ApplyOwnedProps`) and marks it installed.
- **Refund policy:** if an order is cancelled after payment, the customer gets back the price of every line not yet installed, plus that share of labour and tax. Installed work is kept and paid for. Reserved parts for uninstalled lines are released.
- **Shop money:** with `business` set, the shop's veyl_business account receives self-service payments immediately, and mechanic orders on completion (or the kept part on cancellation). Without it, the money is not credited anywhere (like the existing mechanic job, set `business` to change that).

## Dashboard (desk → *Workshop dashboard*, staff of the shop's job)

Overview, Work orders (search, filters, vehicle picture from `veyl_vehicles/web/images` or a car icon, plate, service, bay, mechanic, status in words), Service bays (state from approved / in-progress orders), Parts (stock, reserved, available, reorder threshold, incoming deliveries; managers order parts paid from the business account or their bank, delivered after `deliveryMinutes`), Team (online staff, grade, duty, active jobs; managers assign orders and set the price multiplier 0.8–2.0 and labour 0–30 %), History (closed orders, receipts, and for managers the audit trail). "Revenue today" = money kept for orders completed since midnight server time. Managers: grade ≥ `manageGrade` or a boss grade.

## Saved builds

Per character (`customs_builds`, max `MaxBuilds`): save the cart with a name, load (same model only), copy, delete, share with an 8-character code (holds only the model and options) and import a code. Loading only fills the preview cart; the server prices it again at this shop.

## Integration inventory (actual APIs used)

| Resource | API |
|---|---|
| veyl_core | `DebitOnce`, `CreditOnce` (durable money), `GetJob`, `IsGradeBoss`, `GetMetadata` / `SetMetadata` (swatches), `Veyl.GetPlayerData`, `Veyl.RegisterCallback`, `Veyl.Migrate` |
| veyl_vehicles | `GetOwnedVehicleIdFromEntity`, new `GetOwnedProps`, new `ApplyOwnedProps` (version-checked, authoritative), client `GetVehicleProperties` / `SetVehicleProperties` (format extended: custom RGB paint, custom tyres, interior / dashboard / xenon colour; stock mods are now really removed) |
| veyl_business | new `CreditAccount`, `DebitAccount`, `GetAccount` |
| veyl_world | new client `SetLocalPreview` (local time/weather preview) |
| veyl_lib | `createScreen` (focus), `progress`, `inputDialog` |
| veyl_interact / veyl_target | entrance and desk points; global vehicle options for mechanics |

All of these go through `server/bridge.lua` (server) or are named at their call sites in `client/main.lua`.

## Tested here

- Every Lua file parses; the page type-checks and builds.
- The catalogue (validation, forged values, round trip to the vehicle properties format) passed unit tests in a Lua VM.
- All migrations and the key queries ran on MariaDB in a throwaway database: version-checked saves (a stale write is refused), stock reservation (cannot over-reserve), conditional status changes (a second approval is refused), duplicate payment record refused, dashboard queries, deliveries.

## Not tested yet (needs the game)

Camera framing and clipping at each preview point, the preview copy and lighting at each shop, every mod / paint / neon combination on real models (cars and motorcycles), the UI at 1080p / 1440p / 4K / ultrawide, the full self-service and mechanic flows with two players, insufficient funds, payment and persistence failure paths, restarts mid-order, network owner changes while installing, death / disconnect cleanup, and garage store / retrieve round trips with purchased mods. Do not treat this as production-ready until those pass.

## Not built (optional modules)

Test drive, customer showroom, reviews, favourite mechanics and special-order parts are **not** included (no buttons for them exist). Lift / spray-booth animations are not included either: install interactions use standard animations anywhere in the shop.
