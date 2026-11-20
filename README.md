# VeylCore

A modular FiveM roleplay framework with a small core and separate gameplay resources (`veyl_` prefix).
This release implements **milestones 0–2** of the [development plan](docs/VeylCore-Framework-Development-Plan.md):
the first complete persistent loop.

> Connect → create/select a character → customise appearance → spawn → start a GoPostal delivery shift →
> drive the assigned van → deliver packages → get paid once (server-calculated) → buy food at a 24/7 → eat it →
> disconnect and reconnect with the same character, money, inventory and position.

## Status

| Check | Result |
| --- | --- |
| Server boot (FXServer build 3751 + OneSync, MariaDB 10.4.32, oxmysql 2.14.3) | ✅ All 16 resources start and report ready, no script errors |
| Database migrations | ✅ Applied once, recorded in `veyl_migrations` |
| Lua / JS syntax (68 files) | ✅ Parsed cleanly |
| In-game client testing | ❌ **Not yet run.** The acceptance scenarios below still need two real players |

## Resources

| Resource | What it does |
| --- | --- |
| `veyl_core` | Accounts (Rockstar license), sessions, active-character ownership, ACE permissions, audit log, shared `Veyl` library (callbacks, migrations, readiness, locks) |
| `veyl_ui` | Notifications, progress bars, confirm dialogs, input forms, menus. The single owner of modal NUI focus |
| `veyl_world` | Server-synced clock and weather, ambient population/dispatch settings |
| `veyl_interact` | One interaction API: zones, NPCs and entities with an E-key prompt and per-resource cleanup |
| `veyl_characters` | Character slots, creation, ownership-checked selection, soft delete with name confirmation |
| `veyl_appearance` | Freemode ped editor (heritage, hair, clothing, props) with live preview; saved per character |
| `veyl_spawn` | Bounded spawn pipeline with fallbacks, last-location persistence, basic death → hospital respawn |
| `veyl_banking` | Cash/bank accounts, ledger with unique operation IDs, repeat-safe debit/credit/transfer, Fleeca bank counters, `/givecash` |
| `veyl_inventory` | Built-in item provider: use/give, personal stashes, weight limits, repeat-safe grants |
| `veyl_needs` | Persisted hunger/thirst/stress, consumable effects, starvation damage |
| `veyl_jobs` | Job definitions/grades, assignments, duty, repeat-safe paychecks |
| `veyl_hud` | Health, armor, needs, stamina, oxygen, cash/bank, job, vehicle speed/fuel/lock |
| `veyl_vehicles` | Authorized server-side spawns, key grants, locks (`L`), server-side fuel and fuel stations, cleanup ownership |
| `veyl_shops` | 24/7 stores with server-owned prices; purchase records with refund and restart reconciliation |
| `veyl_delivery` | GoPostal depot NPC, assigned van, randomized stops, server-validated package state, one-time payout |
| `veyl_admin` | Staff commands with server-side permission checks and audit records, `/report` system |

## Installation

1. **Requirements:** FXServer with OneSync enabled, MariaDB/MySQL, and [oxmysql](https://github.com/overextended/oxmysql/releases) (tested with v2.14.3).
2. Copy `resources/[veyl]` into your server's `resources` folder, or create a junction or symlink to it.
3. Create a database such as `veylcore`. Tables are created automatically by each resource's migrations on first start.
4. Merge [`server.cfg.example`](server.cfg.example) into your `server.cfg`:
   - set `mysql_connection_string`
   - `ensure oxmysql` and the `veyl_*` resources in the listed order
   - **remove** `spawnmanager` and `basic-gamemode` (VeylCore owns spawning)
   - grant staff `add_ace group.admin veyl.admin allow`
5. Start the server and look for `[veyl_*] ready` lines. If a service prints `NOT READY`, the line names the failed stage.

## Player controls & commands

| Input | Action |
| --- | --- |
| `E` | Interact (NPCs, banks, stashes, fuel pumps, delivery stops, van) |
| `F2` / `/inventory` | Inventory (rebindable in Settings → Key Bindings → FiveM) |
| `L` / `/vehlock` | Lock or unlock a VeylCore vehicle you have keys for |
| `X` | Cancel the current progress action |
| `/logout` | Return to character selection |
| `/appearance` | Open the appearance editor (`AppearanceConfig.AllowCommand`) |
| `/cash`, `/givecash [id] [amount]` | Show balances, hand cash to a nearby player |
| `/job`, `/duty`, `/quitjob` | Job info, toggle duty, leave an open job |
| `/hud` | Toggle the HUD |
| `/report [message]` | Send a report to staff |

## Staff commands (require `veyl.admin`)

`/vplayers` `/vtp [id]` `/vbring [id]` `/vtpm` `/vcoords` `/vrevive [id]` `/vkick [id] [reason]`
`/vgivemoney [id] [cash|bank] [amount] [reason]` `/vtakemoney …` `/vsetjob [id] [job] [grade]`
`/vgiveitem [id] [item] [count]` `/vreports` `/vclosereport [id]` `/vtime [h] [m]` `/vweather [type]` `/vfreezetime` `/veyl_sessions`

Unauthorized attempts are rejected server-side and written to `veyl_audit`.

## Architecture

### Ownership

Each resource owns its tables and migrates them itself. Other resources change that data only through the
owner's exports:

- `veyl_core` owns sessions (`source` → account → active character). It never treats `source` as a permanent ID.
- `veyl_banking` is the only code that changes balances (`server/ledger.lua`).
- `veyl_inventory` with the configured provider is the only inventory authority.
- `veyl_vehicles` is the only resource that spawns VeylCore vehicles. Each vehicle records the resource that owns
  its cleanup.

### Lifecycle events

| Server event | Args | When |
| --- | --- | --- |
| `veyl:sessionStarted` | `src, accountId` | Client announced and account loaded |
| `veyl:characterLoaded` | `src, charId, charInfo` | Character activated (also sent to the client) |
| `veyl:characterUnloading` | `src, charId, reason` | Before unload. Save from cached state synchronously |
| `veyl:characterUnloaded` | `src, charId, reason` | After unload (`logout`, `switch`, `dropped`) |
| `veyl:playerSpawned` / `veyl:playerRespawned` | `src, charId` | Spawn pipeline finished / hospital respawn |
| `veyl_inventory:itemUsed` | `src, charId, item, def` | After the item was removed |
| `veyl_jobs:updated` | `src, charId, job` | Job or duty changed |
| `veyl_vehicles:destroyed` / `veyl_vehicles:removed` | `vehicleId[, reason]` | Vehicle lifecycle |

### Requests and responses

Every client → server request uses `Veyl.Callback(resource, name, ...)`. Handlers are registered with
`Veyl.RegisterCallback(name, handler, { cooldown, requireCharacter, permission })` and include:

- readiness checks (`NOT_READY`)
- one in-flight request per player and callback (`BUSY`)
- rate limiting (`RATE_LIMITED`)
- a client timeout (`TIMEOUT`)

All responses use one shape: `{ ok, code, message, data }`. The codes are in `veyl_core/lib/shared.lua`.

### Async exports

Exports that touch the database or UI take a callback as their last argument. Call them with
`Veyl.Await(resource, export, timeoutMs, ...)`, so cross-resource calls never yield inside another resource's stack.

```lua
-- fxmanifest.lua of your resource
shared_script '@veyl_core/lib/shared.lua'
server_scripts { '@oxmysql/lib/MySQL.lua', '@veyl_core/lib/server.lua', 'server.lua' }
client_scripts { '@veyl_core/lib/client.lua', 'client.lua' }
```

| Resource | Export (server) | Notes |
| --- | --- | --- |
| `veyl_core` | `GetPlayer(src)`, `GetCharacterId(src)`, `GetSourceByCharacter(id)`, `GetPlayers()`, `HasPermission(src, perm)`, `Audit(src, res, action, data)` | sync |
| `veyl_banking` | `TryDebit(charId, 'cash'\|'bank', amount, reason, opId)`, `Credit(...)`, `Transfer(route, amount, reason, opId)`, `GetBalances(charId)`, `GetOperation(opId)` | async; same `opId` never applies twice |
| `veyl_inventory` | `CanCarry(charId, item, count)`, `GiveItem(charId, item, count, metadata, opId)`, `RemoveItem(charId, item, count, opId)`, `GetItemCount`, `GetItems`, `GetOperation` | async |
| `veyl_jobs` | `GetJob(charId)`, `IsOnDuty(charId, job)`, `SetDuty(src, bool)` (sync), `SetJob(charId, job, grade, reason)` (async) | |
| `veyl_vehicles` | `SpawnAuthorizedVehicle(req)` (async), `DeleteVehicle`, `GiveKey`, `RevokeKey`, `HasKey`, `GetVehicle` | caller owns cleanup |
| `veyl_needs` | `GetNeeds(charId)`, `AddStress(charId, amount)` | sync |

### Money and inventory consistency

Each balance change is one DB transaction: a balance update plus a ledger row with a `UNIQUE` `op_id`. It runs
under a per-account lock, and a `CHECK (balance >= 0)` constraint backs it up.

Shop purchases are recorded operations that move through these states:

- `pending` → `paid` → `delivered`
- `paid` → `refunded`, when the grant fails
- `pending` → `failed`, when the debit is refused

Reconciliation checks banking and inventory op records at startup and every 10 minutes. It resolves anything left
in `pending` or `paid`.

The delivery payout's op id is `delivery:<runId>`, so repeated finish requests cannot pay twice. Runs left `active`
by a restart are closed as `abandoned` and can never pay later.

## Delivery job

The depot is the GoPostal blip. The flow:

1. Talk to the manager. The first time, you are signed on as a Courier.
2. Take a package from the back of your van.
3. Drive to the marked address and deliver it.
4. Repeat until the route is done.
5. Return the van to the depot and finish for `$85/stop`, plus a `$150` bonus if all stops are done and the van is back.

The server validates distance to the van and the door, the current stop, package state, and the minimum time between
stops.

If you cancel, disconnect, switch character, leave the job, or the van is destroyed, the run ends unpaid.

> ⚠️ The depot, van spawn and stop **coordinates are starting values and have not been checked in-game**. Stand at
> each spot, run `/vcoords`, and update `veyl_delivery/config.lua`.

## Deviations from the plan (on purpose)

- **Inventory:** ships a built-in provider instead of ox_inventory. ox_inventory has no VeylCore bridge. It would
  need a custom framework bridge and its own testing, and running two inventory authorities breaks the plan's own rule.
  `server/provider_builtin.lua` defines the provider contract a future ox bridge must implement. Item metadata is
  accepted but not stored yet.
- **NUI** is plain HTML/CSS/JS with no build step, instead of TypeScript.
- **Medical:** death handling is a basic timer and hospital respawn in `veyl_spawn` until `veyl_medical` (milestone 3) exists.
- **Mascot:** the character screen uses a placeholder emblem. Drop the mascot art into `veyl_characters/web` when it's ready.

## Not yet built (later milestones)

- Garages, dealership and owned vehicles
- City hall, police, EMS, dispatch, MDT, prison and doorlocks
- Housing and businesses
- Crafting
- Criminal activities
- Phone, voice integration and the QB/ESX bridge

## Acceptance scenarios (to run in-game)

- [ ] Two accounts create/select characters; neither can load or modify the other's
- [ ] Rapid `/logout` and reselect: old requests don't affect the new character
- [ ] Spam "Finish shift": exactly one payout (`SELECT * FROM veyl_bank_ledger WHERE op_id LIKE 'delivery:%'`)
- [ ] Two simultaneous purchases with limited funds: no negative balance, no duplicate items
- [ ] Full inventory during purchase: refunded, `veyl_shop_purchases.status = 'refunded'`
- [ ] Stop `veyl_ui` / `veyl_characters` with a menu open: cursor, controls and camera recover
- [ ] Disconnect mid-route, reconnect: run is `abandoned`, van removed, no payout
- [ ] Restart the server: money, items, job, needs and position restore
