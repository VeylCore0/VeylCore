# VeylCore

A FiveM roleplay framework that should feel familiar to QBCore and QBox developers. It keeps its own core
(`veyl_core`), the `veyl_` resource prefix and its violet branding. This release follows **plan v2**
([docs/VeylCore-Framework-Development-Plan.md](docs/VeylCore-Framework-Development-Plan.md)):

- **QB-style PlayerData:** `citizenid`, `cid`, `charinfo`, `money`, `job`/`jobs`, `gang`/`gangs`, `metadata` and `position`.
- **One core owns player state:** characters, personal cash/bank/crypto, metadata, multijob/multigang membership, permissions and lifecycle.
- **Two access styles, one backend:** direct exports (`exports.veyl_core:GetPlayer(source)`) and a QB-style
  `GetCoreObject()` facade. An optional `qb-core` shim lets supported QBCore scripts run unmodified.
- **Native library, targeting and inventory:** `veyl_lib`, `veyl_target` and the `veyl_inventory` engine replace ox_lib, ox_target and ox_inventory
  ([library/target/inventory plan](docs/VeylCore-Custom-Library-Target-Inventory-Plan.md), first sprint, see [docs/API-STATUS.md](docs/API-STATUS.md)).
  The only external runtime dependency is `oxmysql`.
- **Separate gameplay resources:** banking UI, jobs UI, keys, fuel, shops, delivery and so on, each replaceable.

## Status

| Check | Result |
| --- | --- |
| Lua / JS syntax (all files) | ✅ Parsed cleanly |
| v1 boot (FXServer, game build 3751, oxmysql 2.14.3, MariaDB 10.4.32) | ✅ Clean, all services ready |
| v2 boot with the ox stack (txAdmin, `start_38435_dev_server.bat`) | ✅ Clean: all services ready, QB facade OK, ox_inventory bridge loaded |
| **Native profile boot** (veyl_lib, veyl_target, veyl_inventory; ox stopped) | ✅ Clean: all services ready, inventory engine migrated, no script errors |
| UI builds (React + TypeScript, Vite) | ✅ `npm run build` / `npm run typecheck` pass |
| UI suite browser preview (20 scripted interactions, 3 resolutions) | ✅ See docs/UI-SUITE.md |
| In-game acceptance scenarios | ❌ Not run yet (needs real players; checklist below) |

## Resources

| Resource | Role |
| --- | --- |
| `veyl_core` | Accounts, characters, PlayerData, personal money and ledger, metadata, jobs/gangs, permissions, paychecks, lifecycle events, native exports and the core-object facade |
| `[compat]/qb-core` | Optional QBCore shim: `GetCoreObject`, QBCore events, `QBCore:Notify`, `@qb-core/shared/locale.lua` |
| `veyl_lib` | Library (`vlib`/`vcache`): custom React menus, forms, alerts, notifications, progress, text prompts, the single focus broker, bounded callbacks, points/zones, streaming, keybinds, locale |
| `veyl_target` | Targeting: one raycast loop, sphere/box zones, entity/local/model/global options, a custom overlay, group/item display filters |
| `veyl_ui` | Compatibility layer: the older `Veyl.UI.*` calls forward to veyl_lib |
| `veyl_interact` | Older interaction API, forwarding to veyl_target (E-key fallback) |
| `veyl_characters` | Character select/create/delete screen. The core validates everything |
| `veyl_appearance` | Character creator, clothing stores and barbers (blips, prices, saved outfits), saved per `citizenid` |
| `veyl_spawn` | Bounded spawn stages, last position, hospital respawn, death state in core metadata |
| `veyl_inventory` | Inventory engine: server-owned items, slots, metadata and revisions; locked transactional moves with operation ids; stashes; reserved item use; React grid UI |
| `veyl_needs` | Hunger/thirst/stress decay and food effects on core metadata (server-side) |
| `veyl_hud` | Health, armor, needs, stamina, oxygen, voice, money, job, speed/fuel/lock |
| `veyl_banking` | Bank counters: deposit, withdraw, transfer, history, `/givecash` (all through core money) |
| `veyl_jobs` | `/duty`, `/job`, `/jobs` (choose primary among memberships), `/quitjob` |
| `veyl_vehicles` | Authorized server spawns, vehicle ids, cleanup ownership, `veyl_player_vehicles` table |
| `veyl_vehiclekeys` | Key grants, `L` to lock/unlock, key-required driving |
| `veyl_fuel` | Server-side consumption, fuel stations, refuelling paid through core money |
| `veyl_shops` | 24/7 stores: server prices, durable debit, item grant, refund/review reconciliation |
| `veyl_garages` | 4 garages + impound lot: take out / park owned vehicles, paid impound release ([docs/VEHICLES.md](docs/VEHICLES.md)) |
| `veyl_dealership` | Premium Deluxe Motorsport: catalog, confirmed purchase, ownership registration and delivery |
| `veyl_mechanic` | LS Customs: on-duty repairs that use parts, service invoices (`/invoices`, or the phone Invoices app) |
| `veyl_drugs` | Fictional criminal enterprise, milestones A-B: grow-anywhere weed/coca/mushrooms, quality, harvest, supplier, Grow Journal ([docs/DRUGS.md](docs/DRUGS.md)) |
| `veyl_phone` | Smartphone: per-character numbers, contacts, messages with honest sent/delivered/read, groups, blocking, pma-voice calls, notifications, app API, and an App Store with Flock (social), Bank, Garage, Marketplace, Notes and Calculator ([docs/PHONE.md](docs/PHONE.md)) |
| `veyl_apartments` | Starlite Motel homes (30 physical MLO rooms): leasing, idempotent rent, private worlds, keys, roommates, doorbell, storage with recovery, wardrobe, furniture, parcels, noticeboard, maintenance, phone app ([docs/APARTMENTS.md](docs/APARTMENTS.md)) |
| `veyl_loadscreen` | Loading screen: real load progress and status, live player count, city updates, rotating tips, Discord/rules links and Veyl Radio (original generated music or your own files). Edit `config.lua` |
| `veyl_delivery` | GoPostal route: depot NPC, assigned van and key, server-validated stops, one-time payout |
| `veyl_world` | Synced clock and weather, population settings |
| `veyl_admin` | Staff tools with ACE checks and audit records, `/report` |
| `[examples]/veyl_qbexample` | A QBCore-style resource running on VeylCore through the shim |

## UI suite

Inventory, Shop, Banking, HUD and Target follow the VeylCore concept designs (charcoal and violet, V mark). The
screens, message schemas and test results are in [docs/UI-SUITE.md](docs/UI-SUITE.md). To review all five screens in a
browser without FiveM, run `npm run preview`. It includes a "compare with concept" overlay.

## Installation

### With txAdmin (recommended)

1. In txAdmin's setup wizard, choose **Remote URL Template** and paste the raw URL of [`recipe.yaml`](recipe.yaml):
   `https://raw.githubusercontent.com/VeylCore0/VeylCore/main/recipe.yaml`
2. Enter your license key and database details. The recipe:
   - downloads cfx-server-data, oxmysql v2.14.3 and VeylCore (pinned commit);
   - creates the database;
   - writes `server.cfg` in the correct start order.
3. Start the server. Tables are created automatically on first boot, so there is no `.sql` to import.

> txAdmin downloads anonymously, so the GitHub repository must be **public** for the recipe to work.

### Manual

1. Install the pinned dependency listed in [docs/DEPENDENCIES.md](docs/DEPENDENCIES.md): **oxmysql** only.
2. The compiled UIs (`web/dist`) are committed. To change a UI, edit `packages/*`, then run `npm install` and
   `npm run build` at the repo root (Node 18+).
3. Copy `resources/[veyl]` into your server's resources folder, or link it.
4. Create an empty database. Every resource creates and migrates its own tables on first start.
5. Merge [server.cfg.example](server.cfg.example) into your config and keep its start order. Don't run ox_lib, ox_target,
   ox_inventory, upstream `qb-core`, `spawnmanager` or `basic-gamemode` alongside it.
6. Start the server. Each service prints `[veyl_*] ready`. Anything that can't start prints `NOT READY` and the stage that failed.

## Scripting against VeylCore

**Native (preferred for new resources)**

```lua
local player = exports.veyl_core:GetPlayer(source)            -- { PlayerData, Functions } or nil
if not player then return end
local job = player.PlayerData.job.name

-- Repeat-safe reward: the same operation id can never pay twice.
local res = Veyl.Await('veyl_core', 'CreditOnce', 15000, player.PlayerData.citizenid, 'bank', 250,
    'Mission reward', ('mission:%d'):format(runId))
```

**Familiar core object**

```lua
local VeylCore = exports.veyl_core:GetCoreObject({ 'Functions', 'Shared' })   -- or exports['qb-core']:GetCoreObject()
local Player = VeylCore.Functions.GetPlayer(source)
Player.Functions.AddMoney('cash', 100, 'tip')   -- legacy boolean contract
```

Both styles read and change the same live player. There's no second registry, balance cache or save thread.

### Core server exports

| Area | Exports |
| --- | --- |
| Players | `GetPlayer(src)`, `GetPlayerByCitizenId(cid)`, `GetPlayerData(src)`, `GetPlayersData()`, `GetPlayers()`, `GetCitizenId(src)`, `GetSourceByCitizenId(cid)`, `GetSessionGeneration(src)`, `IsSpawned(src)`, `Save(src)`, `Logout(src)` |
| Money (legacy, boolean) | `GetMoney(src, type)`, `AddMoney(src, type, amount, reason)`, `RemoveMoney(...)`, `SetMoney(...)` |
| Money (durable, async) | `CreditOnce(cid, type, amount, reason, opId)`, `DebitOnce(...)`, `TransferMoney(fromCid, fromType, toCid, toType, amount, reason, opId)`, `GetMoneyOperation(opId)`, `GetMoneyHistory(cid, limit)` |
| Metadata | `GetMetadata(src, key)`, `SetMetadata(src, key, value)`, `SetMetadataMany(src, values)` |
| Jobs/gangs | `SetJob(src, name, grade)`, `SetGang(...)`, `SetJobDuty(src, bool)`, `AddPlayerToJob(cid, name, grade)`, `RemovePlayerFromJob(cid, name)`, `SetPlayerPrimaryJob(cid, name)`, gang equivalents, `GetGroups(src)`, `HasGroup(src, filter)`, `HasPrimaryGroup(src, filter)`, `IsGradeBoss(name, grade)` |
| Catalogs | `GetJobs()`, `GetJob(name)`, `GetGangs()`, `GetVehicles()`, `GetWeapons()`, `GetLocations()` |
| Other | `HasPermission(src, perm)` (ACE `veyl.<perm>`), `Notify(src, msg, type, ms)`, `Audit(src, resource, action, data)`, `GetCoreObject(filter)` |

"Async" exports take a trailing callback. Call them with `Veyl.Await(resource, export, timeoutMs, ...)` from
`@veyl_core/lib/shared.lua`.

`SetJob` replaces the previous primary membership. `SetPlayerPrimaryJob` only selects among existing memberships.
Only the primary job earns a paycheck.

### Events (one per namespace per transition)

| VeylCore | QBCore (via the shim) | When |
| --- | --- | --- |
| server `VeylCore:Server:PlayerLoaded (src, cid)` | `QBCore:Server:PlayerLoaded (Player)` | Character authenticated and loaded |
| client `VeylCore:Client:OnPlayerLoaded` | `QBCore:Client:OnPlayerLoaded` | After the first spawn completes |
| server/client `…OnPlayerUnload` | `QBCore:Server:OnPlayerUnload` / `QBCore:Client:OnPlayerUnload` | Logout, character switch or drop |
| client `VeylCore:Player:SetPlayerData (data)` | `QBCore:Player:SetPlayerData` | Allowlisted view after any change |
| `VeylCore:*:OnJobUpdate`, `OnGangUpdate`, `SetDuty`, `OnMoneyChange` | QBCore equivalents | After the server commits |
| server `VeylCore:Server:OnGroupUpdate (src, name, grade?)` | n/a | Membership added, changed or removed |

## Money and inventory consistency

- **One ledger:** every personal money change is one database transaction. It's a conditional `UPDATE … balance + delta >= 0`
  plus a ledger row with a `UNIQUE op_id`, applied in order through a per-character queue.
- **Repeat-safe rewards:** `CreditOnce`/`DebitOnce`/`TransferMoney` return only after the commit, and the same `op_id`
  can never apply twice. Legacy `AddMoney` keeps QB's boolean contract and writes through, with retries.
- **No money items:** veyl_inventory has no cash item. Money is numeric in veyl_core only.
- **Inventory:** every move, grant, removal and use is one transaction (slots + revision + operation record), done under
  sorted per-inventory locks, so a recorded operation happened and a missing one did not. See [docs/API-STATUS.md](docs/API-STATUS.md).
- **Shop purchases are recorded operations:**
  - `pending → paid → delivered`
  - `paid → refunded` when the item grant fails
  - `pending → failed` when the debit is refused
  - Because the grant is atomic with its operation record, reconciliation refunds exactly the purchases that were not delivered.
    The `review` state is only a safety net.

## Player commands

`F2` inventory, `1`–`5` hotbar, hold `Left Alt` to target (E/click to select), `L` lock, `/hudsettings`, `/logout`, `/appearance` (admins), `/cash`, `/givecash [id] [amount]`, `/job`, `/jobs`,
`/duty`, `/quitjob`, `/hud`, `/invoices`, `/mechanic`, `/growjournal`, `B` seatbelt, `/report [message]`, and `/qbexample` / `/qbexample_cb` (example).

Staff (`veyl.admin`): `/vplayers` `/vtp` `/vbring` `/vtpm` `/vcoords` `/vrevive` `/vkick` `/vgivemoney` `/vtakemoney`
`/vsetjob` `/vaddjob` `/vremovejob` `/vsetgang` `/vgiveitem` `/vreports` `/vclosereport` `/vtime` `/vweather`
`/vfreezetime` `/veyl_sessions`

## Known gaps and deviations

- **First sprint only** for veyl_lib, veyl_target and veyl_inventory. Hotbar, give/drop, vehicle storage, weapons,
  crafting, hooks and the ox → native data converter are later phases ([docs/API-STATUS.md](docs/API-STATUS.md)).
- **Callbacks:** older VeylCore resources still use `Veyl.Callback`. New code uses `vlib.callback`. Both are bounded
  (timeouts, rate limits, in-flight limits).
- **Shops** still use `DebitOnce` → `GiveItem` → refund. The plan's `ReserveFunds`/`CommitFunds` protocol comes in phase 5.
- **Locations:** delivery coordinates are starting values. Check them in-game with `/vcoords`.
- **Not built yet:** later milestones (management/boss menu, gangs UI, garages, dealership, city hall, police/EMS/dispatch,
  housing and so on), plus the offline QB/QBox data import tool.

## Acceptance checklist (to run in-game)

- [ ] Two accounts create/select characters; neither can load or modify the other's
- [ ] Rapid `/logout` and reselect: old requests don't affect the new character
- [ ] `/qbexample`: the QB and native views show the same balance change
- [ ] QB and native event subscribers each fire once (`QBCore:Client:OnPlayerLoaded` after spawn)
- [ ] Multiple jobs: `/vaddjob` then `/jobs` switches primary without losing memberships
- [ ] Stop `veyl_banking`: `AddMoney` and paychecks still work and balances persist
- [ ] Spam "Finish shift": exactly one `delivery:<run>` ledger row
- [ ] Two simultaneous purchases with limited funds: no negative balance, no duplicate items
- [ ] Full inventory during purchase: refunded (`veyl_shop_purchases.status = 'refunded'`)
- [ ] Disconnect mid-route: run `abandoned`, van removed, no payout
- [ ] Die and reconnect: respawn at the hospital
- [ ] Restart the server: money, items, job, metadata and position restore
