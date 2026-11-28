# Boosting (`veyl_boosting`)

Fictional vehicle-recovery contracts for roleplay. Players open an encrypted tablet, take a contract that matches their rank, find the vehicle in a marked area, "access" it with a short signal-sync puzzle, deliver it to a handoff point and get paid. Reputation unlocks ranks, vehicles and harder contracts. Heat, an optional police alert, crews, daily and weekly challenges and a full audit trail are included.

Everything that matters is decided on the server: which contracts you may take, the state of a contract, whether the puzzle was solved, whether the vehicle is the right one and in the right place, the payout and the reputation. The tablet only shows things and asks.

This is game design only. Nothing here describes how to defeat real vehicle security.

## Install

1. Start order (after the VeylCore resources it uses):

```cfg
ensure veyl_core
ensure veyl_lib
ensure veyl_inventory
ensure veyl_interact
ensure veyl_target
ensure veyl_vehicles
ensure veyl_boosting
```

2. **Database.** Nothing to run by hand: the resource creates and migrates its tables at start (`server/database.lua`, tracked so each migration runs once). `sql/install.sql` has the same schema if you want to review or install it yourself. It needs `oxmysql` (the database connector VeylCore already uses).
3. **Item.** The `boosting_tablet` item is defined in `veyl_inventory/data/items.lua` (using it opens the tablet). Put it in a shop or give it with your admin tools. Opening the tablet through the contact NPC or the phone app never needs the item; `Tablet.RequireItem = true` makes the `/boosting` command need it.
4. **Optional:** `screenshot-basic` is not needed. `veyl_dispatch` (or another dispatch resource through the adapter) enables police alerts. `veyl_phone` adds a Boosting app. `veyl_vehiclekeys` gives the crew keys when a vehicle is accessed.
5. Restart and watch the console. The first start migrates; players who had reputation in the first version of boosting keep it (multiplied by `LegacyRepMultiplier`, 5 by default, to land in the new ranks).

## For players

- Find **Ghost**, the underground contact (marked in `config/locations.lua`), use `/boosting`, the **Boosting** phone app or the tablet item.
- **Contracts** shows one card per contract type. Locked ones say what they need (rank, reputation, a cooldown, a prerequisite). Press **View**, then **Accept**.
- **Solo** contracts start immediately. **Crew** contracts wait in *reserved* until the leader presses **Start**, so members can still join.
- A circle on the map shows where the vehicle is. Walk up to it and use **Access the vehicle**. Watch the symbols, repeat them. Three wrong answers fail the attempt and you wait before trying again. Failing adds heat.
- With the vehicle unlocked the handoff point is revealed. Drive there, park on the marker, **get out** and use **Hand over the vehicle**.
- Vehicles that burn, vanish or are taken too far gone fail the contract. Time limits and penalties are in `config/contracts.lua`.

## What the server enforces

| Rule | Where |
|---|---|
| Contract states move only along `reserved → active → vehicle_acquired → delivery_started → completed`, or to `failed` / `expired` / `cancelled`. Any other move is refused and logged. | `shared/constants.lua`, `transition()` in `server/contracts.lua` |
| Eligibility (rank, reputation, cooldown, prerequisite, max active, minimum police, event) is checked when the list is built **and again** on accept. | `Contracts.lockReason` |
| The vehicle, plate, model, position and condition are checked at delivery against what the server spawned. A client-sent vehicle id is only a lookup key, never trusted. | `Contracts.deliver` |
| The puzzle sequences and the verdict stay on the server; answers have timing limits (too fast is treated as cheating). | `Contracts.accessBegin/accessSubmit` |
| Payout and reputation are computed on the server from the contract, the vehicle's condition and the clock. Each person is credited once per contract through `CreditOnce` with the operation id `boost:<contract>:<citizen>`. A crash between "decided" and "paid" is recovered at start. | `Contracts.complete`, `Contracts.reconcile` |
| One contract per player, leader-only accept/start/cancel, crew membership and stage locks. | `server/crews.lua` |
| Callbacks are rate limited by VeylCore, take plain values, and forged requests are counted in `veyl_boost_audit`. | `server/security.lua`, `server/main.lua` |
| Vehicles are removed on failure, completion (after a delay), disconnect timeout and resource stop. Contracts interrupted by a restart end without a penalty. | `Contracts.finish/shutdown/reconcile` |

## Configuration

Everything tunable is in `config/`:

| File | What |
|---|---|
| `main.lua` | Debug, tablet item and command, offer timing, the puzzle (length, stages, strikes, timing), delivery rules, cleanup and restart policy, tracker, blips, admin permission, UI theme |
| `contracts.lua` | Contract templates: badge, difficulty, vehicle tiers, ranks, solo/group, vehicle count, time limit, pay multiplier, reputation, fast bonus, heat profile, tracker, cooldown, max active, minimum police, prerequisites, event. Also the reputation penalties |
| `vehicles.lua` | The vehicle catalogue: model, label, tier, difficulty, base reward, reputation needed, condition for full pay, solo and group eligibility |
| `progression.lua` | Ranks and perks, the old-reputation multiplier, daily and weekly challenges |
| `heat.lua` | Heat decay and levels, what high heat does, the police adapter (resource, jobs, code, radius, blip) |
| `crews.lua` | Crew size, invite range and time, which stages allow joining and leaving, reward split and group bonus |
| `locations.lua` | The contact NPC, vehicle spawn points, handoff points |

Rewards: `vehicle baseReward × template multiplier (rolled once when the offer is made) × heat multiplier × condition modifier × fast bonus × group bonus`, split between the crew.

### Police alerts

`integrations/dispatch_adapter.lua` is the only place that talks to a dispatch resource. It is off if `Police.Enabled` is false or the resource in `Police.Resource` is not started, and then `minPolice` is ignored too. To use another dispatch resource, change `D.send` in that file. Alerts are rate limited per player and point at the area, not the exact spot, when `InvestigationZone` is on.

### Admin

`/boostadmin` (console, or a player with the `boosting.admin` permission):

- `event on|off`: start or stop event contracts.
- `rep <server id> <amount>`, `heat <server id> <amount>`: adjust a player.
- `cancel <server id>`: end their contract without penalty logic beyond the normal cancel rules.
- no arguments: live contracts, event state, dispatch and police counts.

Everything an admin does is written to `veyl_boost_audit`, next to the normal contract history.

## Verified API audit

Checked against the repository source (not assumed):

| Resource | Used | Where it was verified |
|---|---|---|
| `veyl_core` | `Veyl.Startup`, `Veyl.Migrate`, `Veyl.RegisterCallback(name, fn(src, citizenid, ...), { cooldown, permission })`, `Veyl.Callback / CallbackTimeout`, `Veyl.Await`, `Veyl.Ok / Err`, `Veyl.GetPlayerData / GetPlayerCoords / GetCitizenId`, `Veyl.HasPermission`, `Veyl.Audit`, `Veyl.NewId`, `Veyl.Notify / NotifyResult`, money service `CreditOnce` | `veyl_core/lib/server.lua`, `lib/client.lua`, existing resources |
| `veyl_lib` | `vlib.createScreen` (`open`, `close`, `send`, `isOpen`), `vlib.progress` | `veyl_lib`, `veyl_cityhall/client/main.lua` |
| `veyl_inventory` | `GetItemCount`, `RemoveItem`, `RegisterUseHandler`, item definitions in `data/items.lua` | `veyl_inventory/server/exports.lua` |
| `veyl_interact` | `AddPed`, `AddZone`, `Remove` | `veyl_interact/client.lua` |
| `veyl_target` | `addGlobalVehicle`, `removeGlobalVehicle` | `veyl_target/client/main.lua` |
| `veyl_vehicles` (not one of the five) | `SpawnAuthorizedVehicle`, `DeleteVehicle` | `veyl_vehicles/server.lua`. VeylCore spawns every server-owned vehicle through this service, so it is a declared dependency |

Not available in VeylCore, so built here: a boosting data model, the contract engine, the dispatch adapter (VeylCore has `veyl_dispatch`, but the adapter keeps boosting independent of it), and the tablet.

Natives used for vehicle checks (`GetVehicleEngineHealth`, `GetVehicleBodyHealth`, `GetEntityModel`, `GetVehicleNumberPlateText`, `NetworkGetEntityFromNetworkId`, `GetPedInVehicleSeat`) are the OneSync server-side natives; the older boosting already used the body-health one.

## Tests that were run

The server logic runs against a real MariaDB in a test harness with VeylCore stubbed out (87 checks): schema and migrations, eligibility and locks, accept and start, forged requests, the puzzle (too far, wrong vehicle, three strikes, too fast, a real win), delivery (not started, wrong place, in the vehicle, wrong plate, wreck, success), payout once and no replay, reputation and statistics, challenges, cooldowns, time-out, lost vehicle, cancel, heat levels and cooling, dispatch on and off, crews (nearby list, invite, accept, leadership, removal, locks), group contracts and shares, disconnect grace, restart reconciliation and recovery of unpaid rewards. The tablet and the puzzle were clicked through in the preview (22 flows).

Not tested here: in-game behaviour (spawning, targeting, blips, vehicle damage), real multi-player latency and the FiveM browser (CEF) rendering. Run through the admin test below on a dev server.

## Admin test guide

1. `/boostadmin` → shows live contracts and whether dispatch is on.
2. As a player: `/boosting` (or the contact) → take **Vehicle Recovery**. A circle appears. Find the vehicle, **Access** it, solve the puzzle, drive to the handoff, step out, hand it over. Check the cash, reputation and the Activity list.
3. `/boostadmin rep <id> 400` and `/boostadmin event on` to see higher contracts. `/boostadmin heat <id> 80` to see easy contracts hide and pay rise.
4. Crew: stand next to a second player, Crew → Invite, accept, take **Premium Recovery** (reserved), press Start. Disconnect one player and reconnect: they get the contract back.
5. Restart the resource mid-contract: the contract ends as `expired` (`server_restart`) with no penalty and the vehicles are gone.

## Troubleshooting

- **"Boosting is starting up"**: migrations did not finish. Look for SQL errors; check `oxmysql`.
- **Contract falls through on start**: `veyl_vehicles` could not spawn the model. Check the model names in `config/vehicles.lua` and the spawn points.
- **No contacts or prompts**: `veyl_interact` / `veyl_target` must be started first; restart `veyl_boosting` after them.
- **Alerts never reach police**: `Police.Resource` must be started and export `Alert`; `Police.Enabled` must be true.
- **Vehicle shows blank in the tablet**: the picture comes from `veyl_vehicles/web/images/<model>.webp`; add the file for custom models.
- Suspicious activity and every contract event are in `veyl_boost_audit` (`event = 'suspicious'`).
