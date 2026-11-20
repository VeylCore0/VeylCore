# VeylCore

A FiveM roleplay framework that should feel familiar to QBCore and QBox developers. It keeps its own core
(`veyl_core`), the `veyl_` resource prefix and its violet branding. This release follows **plan v2**
([docs/VeylCore-Framework-Development-Plan.md](docs/VeylCore-Framework-Development-Plan.md)):

- **QB-style PlayerData:** `citizenid`, `cid`, `charinfo`, `money`, `job`/`jobs`, `gang`/`gangs`, `metadata` and `position`.
- **One core owns player state:** characters, personal cash/bank/crypto, metadata, multijob/multigang membership, permissions and lifecycle.
- **Two access styles, one backend:** direct exports (`exports.veyl_core:GetPlayer(source)`) and a QB-style
  `GetCoreObject()` facade. An optional `qb-core` shim lets supported QBCore scripts run unmodified.
- **ox stack:** `oxmysql`, `ox_lib`, `ox_target`, and `ox_inventory` with a real VeylCore framework bridge.
- **Separate gameplay resources:** banking UI, jobs UI, keys, fuel, shops, delivery and so on, each replaceable.

## Status

| Check | Result |
| --- | --- |
| Lua / JS syntax (all files) | ✅ Parsed cleanly |
| v1 boot (FXServer, game build 3751, oxmysql 2.14.3, MariaDB 10.4.32) | ✅ Clean, all services ready |
| **v2 boot with the ox stack** | ⏳ Needs a server restart through txAdmin (see the commit/PR notes) |
| In-game acceptance scenarios | ❌ Not run yet (needs real players; checklist below) |

## Resources

| Resource | Role |
| --- | --- |
| `veyl_core` | Accounts, characters, PlayerData, personal money and ledger, metadata, jobs/gangs, permissions, paychecks, lifecycle events, native exports and the core-object facade |
| `[compat]/qb-core` | Optional QBCore shim: `GetCoreObject`, QBCore events, `QBCore:Notify`, `@qb-core/shared/locale.lua` |
| `veyl_ui` | One UI route for notify, progress, confirm, input and menu. Uses ox_lib by default (violet theme), or VeylCore's own NUI |
| `veyl_interact` | One interaction API: zones, NPCs and entities through ox_target, with an E-key fallback |
| `veyl_characters` | Character select/create/delete screen. The core validates everything |
| `veyl_appearance` | Freemode ped editor, saved per `citizenid` |
| `veyl_spawn` | Bounded spawn stages, last position, hospital respawn, death state in core metadata |
| `veyl_inventory` | ox_inventory adapter: repeat-safe give/remove, usable-item pipeline, stashes |
| `veyl_needs` | Hunger/thirst/stress decay and food effects on core metadata (server-side) |
| `veyl_hud` | Health, armor, needs, stamina, oxygen, voice, money, job, speed/fuel/lock |
| `veyl_banking` | Bank counters: deposit, withdraw, transfer, history, `/givecash` (all through core money) |
| `veyl_jobs` | `/duty`, `/job`, `/jobs` (choose primary among memberships), `/quitjob` |
| `veyl_vehicles` | Authorized server spawns, vehicle ids, cleanup ownership, `veyl_player_vehicles` table |
| `veyl_vehiclekeys` | Key grants, `L` to lock/unlock, key-required driving |
| `veyl_fuel` | Server-side consumption, fuel stations, refuelling paid through core money |
| `veyl_shops` | 24/7 stores: server prices, durable debit, item grant, refund/review reconciliation |
| `veyl_delivery` | GoPostal route: depot NPC, assigned van and key, server-validated stops, one-time payout |
| `veyl_world` | Synced clock and weather, population settings |
| `veyl_admin` | Staff tools with ACE checks and audit records, `/report` |
| `[examples]/veyl_qbexample` | A QBCore-style resource running on VeylCore through the shim |

## Installation

1. Install the pinned dependencies listed in [docs/DEPENDENCIES.md](docs/DEPENDENCIES.md): oxmysql, ox_lib, ox_target and ox_inventory.
2. Install the ox_inventory integration. It copies the bridge into `ox_inventory/modules/bridge/veyl`, adds the
   VeylCore items, and turns off ox's money-item shops (a backup is kept):
   ```powershell
   powershell -ExecutionPolicy Bypass -File integrations\install-ox-integration.ps1 -OxInventoryPath "C:\path\to\resources\[ox]\ox_inventory"
   ```
3. Copy `resources/[veyl]` into your server's resources folder, or link it.
4. Create an empty database. Every resource creates and migrates its own tables on first start.
5. Merge [server.cfg.example](server.cfg.example) into your config. Keep the `inventory:*` convars and the start order.
   Don't run upstream `qb-core`, `spawnmanager` or `basic-gamemode` alongside it.
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
- **No money items:** `inventory:accounts "[]"` keeps ox_inventory from creating money items, and the bridge never syncs balances.
- **Shop purchases are recorded operations:**
  - `pending → paid → delivered`
  - `paid → refunded` when the item grant fails
  - `pending → failed` when the debit is refused
  - `paid → review` when the grant's outcome is unknown after an interruption. Staff decide; it's never auto-refunded, so it can't double-pay.

## Player commands

`F2`/`TAB` inventory (ox), `L` lock, `/logout`, `/appearance`, `/cash`, `/givecash [id] [amount]`, `/job`, `/jobs`,
`/duty`, `/quitjob`, `/hud`, `/report [message]`, and `/qbexample` / `/qbexample_cb` (example).

Staff (`veyl.admin`): `/vplayers` `/vtp` `/vbring` `/vtpm` `/vcoords` `/vrevive` `/vkick` `/vgivemoney` `/vtakemoney`
`/vsetjob` `/vaddjob` `/vremovejob` `/vsetgang` `/vgiveitem` `/vreports` `/vclosereport` `/vtime` `/vweather`
`/vfreezetime` `/veyl_sessions`

## Known gaps and deviations

- **ox_target groups:** ox_target has no VeylCore framework module, so its own `groups` option isn't enforced.
  `veyl_interact` applies group filters against VeylCore PlayerData instead, and servers validate every action anyway.
- **Callbacks:** VeylCore resources use VeylCore's bounded callbacks (timeouts, rate limits, in-flight limits)
  rather than `lib.callback`, because the plan requires a timeout on every wait. The QB shim implements
  QB-style callbacks with request ids.
- **Item metadata:** handled by ox_inventory. An interrupted grant leaves its operation `pending`, meaning
  "unknown", and exactly-once item delivery across a crash is not claimed.
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
