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
| `Functions.GetPlayer(src)` | 🟡 | Returns `{ PlayerData, Functions }`. `PlayerData.items` is a read-only view built from ox_inventory |
| `Functions.GetPlayerByCitizenId`, `GetPlayerByPhone`, `GetPlayers`, `GetQBPlayers`, `GetIdentifier`, `GetSource` | 🟡 | |
| `Functions.Notify` (server/client) and `QBCore:Notify` event | 🟡 | `primary` is mapped to `info` |
| `Functions.HasPermission`, `Kick`, `GetDutyCount`, `HasItem` | 🟡 | Permissions are ACE `veyl.<perm>`. `IsPlayerBanned` always returns false (use txAdmin bans) |
| `Functions.CreateCallback` / client `TriggerCallback` | 🟡 | Request ids, a 30 s client timeout, and pending requests cleared on unload |
| `Functions.CreateUseableItem`, `CanUseItem` | 🟡 | Routed into veyl_inventory's single use pipeline. The item must exist in ox_inventory's `data/items.lua` |
| Client `GetPlayerData`, `GetPlate`, `GetClosestPlayer`, `GetClosestVehicle`, `Progressbar` | 🟡 | `Progressbar` maps onto veyl_ui progress; props aren't supported |
| `Commands.Add(name, help, args, required, cb, permission)` | 🟡 | ACE-backed |
| `Shared.Jobs/Gangs/Vehicles/Weapons/Items` + helpers (`RandomStr`, `RandomInt`, `SplitStr`, `Trim`, `FirstToUpper`, `Round`) | 🟡 | `Items` is a view of ox_inventory definitions taken when `GetCoreObject` is called. Weapons are keyed by hash |
| Client callbacks from the server (`CreateClientCallback`), `SpawnVehicle`, `DrawText3D`, and similar | ❌ | Use native VeylCore or ox_lib equivalents |

## Player.Functions

| Method | Status | Notes |
| --- | --- | --- |
| `AddMoney`, `RemoveMoney`, `SetMoney`, `GetMoney` | 🟡 | Boolean contract, through the core ledger |
| `SetJob`, `SetGang`, `SetJobDuty` | 🟡 | `SetJob` replaces the previous primary membership (QBox semantics) |
| `SetMetaData`, `GetMetaData` | 🟡 | Checked against the metadata schema |
| `AddItem`, `RemoveItem`, `GetItemByName`, `GetItemsByName`, `HasItem` | 🟡 | Delegated to ox_inventory |
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
| `qb-inventory`, `qb-target`, `qb-menu`, `qb-input` | ❌ | Use ox_inventory, ox_target or veyl_interact, and veyl_ui/ox_lib |
| Direct SQL against QB `players` tables | ❌ | VeylCore uses `veyl_players` and related tables; use the exports |

## Third-party resources

| Resource | Version | Status | Notes |
| --- | --- | --- | --- |
| ox_inventory | 2.48.1 | 🟡 | VeylCore bridge in `integrations/ox_inventory`; money items and default shops are disabled |
| ox_target | 1.18.1 | 🟡 | Through veyl_interact; the native `groups` option isn't enforced (no VeylCore framework module) |
| ox_lib | 3.42.2 | 🟡 | veyl_ui provider (notify, progress, alert, input, context) |
| `[examples]/veyl_qbexample` | 0.2.0 | 🟡 | Reference QB-style resource |
