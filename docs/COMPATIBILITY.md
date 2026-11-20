# VeylCore compatibility matrix

Compatibility is a tested subset, not a promise that any QBCore or QBox script will work. A status changes from
"implemented" to "tested" only after it's verified in-game on the pinned versions in [DEPENDENCIES.md](DEPENDENCIES.md).

Legend:
- ✅ **tested**: verified in-game
- 🟡 **implemented**: written but not yet verified in-game
- ❌ **not supported**

## QBCore object (`exports['qb-core']:GetCoreObject()` / `exports.veyl_core:GetCoreObject()`)

| API | Status | Notes |
| --- | --- | --- |
| `GetCoreObject(filter)` | 🟡 | Sections: `Functions`, `Shared`, `Commands`, `Config` (server); `Functions`, `Shared` (client) |
| `Functions.GetPlayer(src)` | 🟡 | Returns `{ PlayerData, Functions }`. `PlayerData.items` is a read-only view derived from veyl_inventory |
| `Functions.GetPlayerByCitizenId`, `GetPlayerByPhone`, `GetPlayers`, `GetQBPlayers`, `GetIdentifier`, `GetSource` | 🟡 | |
| `Functions.Notify` (server/client) and `QBCore:Notify` event | 🟡 | `primary` is mapped to `info` |
| `Functions.HasPermission`, `Kick`, `GetDutyCount`, `HasItem` | 🟡 | Permissions are ACE `veyl.<perm>`. `IsPlayerBanned` always returns false (use txAdmin bans) |
| `Functions.CreateCallback` / client `TriggerCallback` | 🟡 | Request ids, a 30 s client timeout, and pending requests cleared on unload |
| `Functions.CreateUseableItem`, `CanUseItem` | 🟡 | Routed into veyl_inventory's single use pipeline (used only when the item has no `use.handler`). The item must exist in `veyl_inventory/data/items.lua` |
| Client `GetPlayerData`, `GetPlate`, `GetClosestPlayer`, `GetClosestVehicle`, `Progressbar` | 🟡 | `Progressbar` maps onto veyl_lib progress (via veyl_ui); props aren't supported |
| `Commands.Add(name, help, args, required, cb, permission)` | 🟡 | ACE-backed |
| `Shared.Jobs/Gangs/Vehicles/Weapons/Items` + helpers (`RandomStr`, `RandomInt`, `SplitStr`, `Trim`, `FirstToUpper`, `Round`) | 🟡 | `Items` is a view of veyl_inventory definitions taken when `GetCoreObject` is called. Weapons are keyed by hash |
| Client callbacks from the server (`CreateClientCallback`), `SpawnVehicle`, `DrawText3D`, and similar | ❌ | Use native VeylCore or ox_lib equivalents |

## Player.Functions

| Method | Status | Notes |
| --- | --- | --- |
| `AddMoney`, `RemoveMoney`, `SetMoney`, `GetMoney` | 🟡 | Boolean contract, through the core ledger |
| `SetJob`, `SetGang`, `SetJobDuty` | 🟡 | `SetJob` replaces the previous primary membership (QBox semantics) |
| `SetMetaData`, `GetMetaData` | 🟡 | Checked against the metadata schema |
| `AddItem`, `RemoveItem`, `GetItemByName`, `GetItemsByName`, `HasItem` | 🟡 | Delegated to veyl_inventory (legacy synchronous contract) |
| `UpdatePlayerData`, `Save`, `Logout` | 🟡 | |
| `SetPlayerData(key, value)` | 🟡 partial | Only `metadata` is accepted; other keys are rejected with a warning |

## Events

| QBCore event | Status | Timing |
| --- | --- | --- |
| `QBCore:Server:PlayerLoaded (Player)` | 🟡 | Character authenticated and loaded |
| `QBCore:Client:OnPlayerLoaded` | 🟡 | After the first spawn completes |
| `QBCore:Server:OnPlayerUnload (src)`, `QBCore:Client:OnPlayerUnload` | 🟡 | Logout, switch or drop |
| `QBCore:Player:SetPlayerData (data)` | 🟡 | After every committed change (coalesced over 50 ms) |
| `QBCore:Server/Client:OnJobUpdate`, `OnGangUpdate`, `SetDuty`, `OnMoneyChange` | 🟡 | After the server commits |
| `QBCore:ToggleDuty` (client → server) | 🟡 | Only toggles the caller's own duty |
| `QBCore:Server:OnPlayerLoaded` (client → server) | ❌ | VeylCore emits loaded notifications server-side |

## Imports and dependencies

| Dependency | Status | Notes |
| --- | --- | --- |
| `@qb-core/shared/locale.lua` | 🟡 | Minimal `Locale` class |
| `exports.qbx_core:*`, `@qbx_core/modules/*` | ❌ | Port explicitly against the VeylCore API map |
| `qb-inventory`, `qb-target`, `qb-menu`, `qb-input` | ❌ | Port to veyl_inventory, veyl_target and veyl_lib |
| `@ox_lib/init.lua`, `exports.ox_target:*`, `exports.ox_inventory:*` | ❌ | No ox compatibility shim yet (plan phase 7). Port to `vlib.*` and `exports.veyl_target/veyl_inventory` |
| Direct SQL against QB `players` tables | ❌ | VeylCore uses `veyl_players` and related tables; use the exports |

## Third-party resources

| Resource | Version | Status | Notes |
| --- | --- | --- | --- |
| ox_lib / ox_target / ox_inventory | 3.42.2 / 1.18.1 / 2.48.1 | transitional only | Booted in profile v0.2; not part of the native profile |
| `[examples]/veyl_qbexample` | 0.2.0 | 🟡 | Boot self-check passes in both profiles |
