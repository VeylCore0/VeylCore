# Vehicles: garages, dealership and mechanic

Three resources build on `veyl_vehicles`. It is the only resource that writes ownership and storage state in
`veyl_player_vehicles`, and the only one that spawns VeylCore vehicles. Keys (`veyl_vehiclekeys`) and fuel (`veyl_fuel`)
are still separate resources that react to its spawn and remove events.

Start order:

```cfg
ensure veyl_vehicles
ensure veyl_vehiclekeys
ensure veyl_fuel
...
ensure veyl_shops
ensure veyl_garages
ensure veyl_dealership
ensure veyl_mechanic
```

## Owned-vehicle service (`veyl_vehicles`)

| Export (server, `Veyl.Await`) | What it guarantees |
| --- | --- |
| `RegisterOwnedVehicle(citizenid, model, { label?, garage?, opId? })` | One row per `opId`, ever. A repeat returns the first vehicle (`existing = true`). The plate is unique |
| `GetOwnedVehicles(citizenid)` | Public rows: id, model, plate, state, garage, fuel/engine/body %, impound fee/reason, `out` |
| `SpawnOwnedVehicle(src, citizenid, ownedId, vector4, { from = 'garaged'\|'impound', garage? })` | Reserves the row first (`state → out` only if it is still where the caller says), so two requests never create two copies. Applies the saved plate, fuel, condition and looks. On a failed spawn the reservation is undone |
| `StoreOwnedVehicle(src, citizenid, netId, garage, props)` | Owner only, nobody inside. Saves fuel, engine and body (read on the server) plus bounded, type-checked looks |
| `ImpoundOwnedVehicle(ownedId, reason, fee)` (plain export) | Staff/police tools. Removes a live copy |

Lifecycle rules:
- **Abandoned:** an owned vehicle that disappears without being parked is impounded with `ImpoundFee` (default $500).
- **Wrecked:** a wrecked owned vehicle is impounded and the wreck is cleared after `WreckClearMs`.
- **Restart:** vehicles that were out when the server stopped go back to their last garage, free.

## Vehicle pictures

`veyl_vehicles/web/images/<model>.webp` holds a picture of every base-game model (all 876 in `veyl_core/shared/vehicles.lua`). The pictures come from the FiveM vehicle-models reference and are resized to 360 px wide, about 9 MB in total. Both the garage list and the dealership cards and detail panel use them. If an add-on model has no picture, the UI falls back to the plain car icon. To add one, drop a `<model>.webp` into that folder.

## Garages (`veyl_garages`)

There are four public garages (Legion Square, Pink Cage, Sandy Shores, Paleto) and the impound lot, each with a blip.

- **Opening:** target the garage sign and choose *Open garage*. The list shows the vehicles parked here, or all your
  vehicles with where they are, plus their fuel, engine and body condition.
- **Taking out:** the client picks the first clear parking space. The server only accepts space numbers from its own
  config.
- **Parking:** target your own empty vehicle within 35 m of a garage and choose *Park in garage*.
- **Impound lot:** pay the release fee (cash or bank) with one `DebitOnce`, keyed by an operation id. A retried release
  reuses that id, so it is never charged twice. If the spawn fails after payment, the vehicle stays at the lot as paid.

## Dealership (`veyl_dealership`)

The dealership is Premium Deluxe Motorsport. Talk to the salesperson (*Browse vehicles*).

- **Catalog and prices:** both come from `veyl_core/shared/vehicles.lua` (`shop = 'pdm'`). It lists all 876 base-game models from the FiveM reference; 549 civilian road vehicles are for sale
  in 12 categories (armed, armoured and arena variants are cataloged but never sold; prices are per-category defaults you can edit).
- **Purchase:** confirm the dialog, then the server runs `DebitOnce('dealer:<citizenid>:<op>')`, then
  `RegisterOwnedVehicle(created_op = same op)`.
  - The car is delivered to the bay if it's clear. Otherwise it's parked at `FallbackGarage` (Legion).
  - A stale price returns `PRICE_CHANGED` with the real price.
  - If registration fails, the payment is refunded once. A retry of a refunded purchase is refused, so it can't become a
    free car.

## Mechanic (`veyl_mechanic`)

The workshop is LS Customs (Burton). The parts counter there is restricted to the mechanic job; its stock is in
`veyl_shops` config.

- **Duty:** *Mechanic menu* at the desk (or `/mechanic` in the workshop) → go on or off duty. Mechanic must be your
  primary job.
- **Repairs:** target a vehicle inside the workshop while on duty. Options only appear when the vehicle needs that
  repair and you carry the part.

  | Option | Part used | Time |
  | --- | --- | --- |
  | Repair engine | Engine Parts | 12 s |
  | Repair bodywork | Body Panels | 10 s |
  | Replace tyres | Tyre Kit | 7 s |
  | Wash vehicle | Cleaning Kit | 5 s |

  The server times the job and removes exactly one part with a durable operation id. The vehicle's owner client applies
  the repair.
- **Invoices:** the mechanic menu → *Send invoice* lets you pick a nearby customer, an amount (up to $25,000) and the
  work done.
  - The customer is notified and uses `/invoices` to pay (cash or bank) or decline.
  - Payment is one `TransferMoney` keyed `invoice:<id>` from the customer to the mechanic's bank, so it can't be paid
    twice. Unpaid invoices stay in `veyl_invoices`.

## Tests run

| Check | Result |
| --- | --- |
| Browser preview: 19 scripted garage / impound / dealer interactions | ✅ 19/19, no page errors |
| Server code in a Lua VM with an in-memory DB and money service: purchase, repeat, refund guard, park, take out, double take-out, impound fee, restart recovery | ✅ 23/23 |
| Mechanic server in a Lua VM: duty, workshop, parts, timing, invoice send/pay/decline | ✅ 19/19 |
| Lua syntax (168 files), all UI builds | ✅ |
| **In-game** | ❌ Not run yet |

## Known limitations

- **Unverified locations:** garage, dealership and workshop coordinates are standard GTA spots that I haven't walked in
  game. They're all in each resource's `config.lua`.
- **Client-reported looks:** saved vehicle looks (mods, colours) are reported by the owner's client when parking. They
  are bounded and type-checked but not verified.
- **Invoice payee:** invoices pay the mechanic personally, because business accounts don't exist yet.
- **Not built yet:** the plan's later items (test drives, financing, trade-ins, shared/job garages). Tuning is done by the tuner shop and towing by the tow job (see BUSINESS.md and CITYLIFE.md).
  The dealership catalog shows a category icon rather than a picture of each vehicle.

## Trunks, gloveboxes, plates, transfers and insurance

- **Trunk:** look at a vehicle (target) → *Open trunk* (30 slots, 120 kg). It must be unlocked, unless you are inside. Motorcycles and bicycles have none. **Glovebox:** `/glovebox` (or a key in Settings → Key Bindings → FiveM) while seated (6 slots, 8 kg). Owned vehicles keep their trunk and glovebox for good (`stash:veh_trunk:own<id>`); other vehicles' storage lasts while the vehicle exists. Only vehicles spawned through `veyl_vehicles` have storage. This uses a new *keyed stash* in `veyl_inventory`: `RegisterStash({ keyed = true, authorize = ... })`, opened as `<id>@<key>`; the authorize export returns the storage key.
- **Custom plates:** drive into the **plate shop** (Legion, `PlateShop`) and stay seated: 2–8 letters / numbers, $5,000 from the bank, unique. Some words are blocked (`PlateShop.blocked`).
- **Fake plates:** the `fake_plate` item (backroom bench) is used at the back of a vehicle you have keys to; the registered plate is hidden. *Remove fake plate* on the vehicle puts the real one back and returns the item. `exports.veyl_vehicles:GetRealPlate(entity)` gives the real plate.
- **Sell / give:** target your own vehicle → *Sell / give vehicle*, pick a player standing next to it and a price (0 = gift). The buyer confirms and pays from the bank; ownership and keys move to them. Insurance does not transfer.
- **Insurance:** the insurance office (Rockford Hills, `Insurance`) sells cover at $350 a week (up to 8 weeks at a time). An insured vehicle that is wrecked or abandoned goes to the impound **with no fee and fully repaired**. Police impounds are still charged. Column `insured_until` (migration `003_insurance`).
