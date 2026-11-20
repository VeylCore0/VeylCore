# veyl_lib, veyl_target and veyl_inventory: API and status

This covers the **first sprint** of [VeylCore-Custom-Library-Target-Inventory-Plan.md](VeylCore-Custom-Library-Target-Inventory-Plan.md).
Each row has one of these statuses:

- ✅ **booted**: loads cleanly on the dev server
- 🟡 **implemented**: written but not yet exercised in-game
- 📋 **planned**: a later phase; not built

Nothing below has been tested by a player in-game yet.

**Boot evidence (Nov 20, 2026, native profile from `start_38435_dev_server.bat`):**
- ox_lib, ox_target and ox_inventory were stopped.
- `veyl_lib ready (v0.3.0)` and `veyl_inventory applied migration 001_engine`, `ready (10 item definitions)`.
- Every `veyl_*` service reported ready, and there were no script errors.

## veyl_lib

Import it with `shared_script '@veyl_lib/init.lua'`. This defines `vlib` and, on the client, `vcache`. It never touches
`lib`, `cache` or `require`.

| Module | API | Status |
| --- | --- | --- |
| Bootstrap | lazy, side-aware module loader; `vlib.name/version/context/resource` | ✅ |
| Menus | `vlib.registerMenu(def, onSelect?)`, `vlib.showMenu(id)`, `vlib.hideMenu()`, `vlib.getOpenMenu()`; child menus (`option.menu`), breadcrumb, back, disabled rows with a reason | 🟡 |
| Forms / alerts | `vlib.inputDialog(title, fields, opts)` → values or `nil`; `vlib.alertDialog({...})` → `'confirm'` or `'cancel'` | 🟡 |
| Notify / text UI | `vlib.notify(data)` (client) or `vlib.notify(src, data)` (server); `vlib.showTextUI(text, key)` / `hideTextUI()` | 🟡 |
| Progress | `vlib.progress({ label, duration, canCancel, disable, anim, prop })` → boolean; `progressActive()`, `cancelProgress()` | 🟡 |
| Focus broker | `exports.veyl_lib:RequestFocus(kind)` → token or `nil, 'busy'`; `ReleaseFocus(token)`; `IsModalOpen()`; events `veyl_lib:focusRevoked`, `veyl_lib:brokerReset` | 🟡 |
| Callbacks | server: `vlib.callback.register('<resource>:<name>', fn, { cooldownMs })`; client: `vlib.callback.await(name, { timeoutMs }, ...)`, `awaitResult`, `cancelAll`, and a callback form | 🟡 |
| Cache / keybinds | `vcache.ped/vehicle/seat/weapon`, `vlib.onCache(key, fn)`, `vlib.addKeybind({...})` (rebindable) | 🟡 |
| Points / zones | `vlib.points.new({ coords, distance, onEnter, onExit, nearby })` with a grid index; `vlib.zones.sphere/box` with `contains`/`distance` | 🟡 |
| Streaming | `vlib.requestModel/requestAnimDict/requestPtfx` (bounded, cleaned up on stop) | 🟡 |
| Locale / helpers | `vlib.locale()`, `vlib.t()`, `vlib.print`, `vlib.validate`, `vlib.table`, `vlib.math` | 🟡 |
| Commands | `vlib.addCommand(name, { restricted = ace }, fn)` (server) | 🟡 |
| Server→client callbacks, polygon zones, skill checks, radial menu, hooks module | | 📋 |

Rules:
- Only plain data reaches the NUI. Option callbacks stay in the calling resource.
- Every NUI request is resolved, and every modal result closes the modal before the consumer runs.
- The page is transparent until it receives an open message. If assets fail, the request is rejected after 10 s instead of showing a black screen.

## veyl_target

Client exports:
- `addSphereZone`, `addBoxZone`, `removeZone`, `zoneExists`
- `addEntity` (network ids), `removeEntity`
- `addLocalEntity` (handles), `removeLocalEntity`
- `addModel`, `removeModel`
- `addGlobalPed/Vehicle/Object/Player` and the matching `removeGlobal…`
- `disableTargeting`, `isActive`

| Feature | Status |
| --- | --- |
| Hold Left Alt to target (rebindable, or toggle with `setr veyl_target:toggle true`); scroll or arrow keys to select; E or left click to confirm | 🟡 |
| One asynchronous camera ray plus a nearby-zone index; order is priority, then distance, then registration order | 🟡 |
| Option fields: `name` (stable), `label`, `icon`, `distance`, `priority`, `groups`, `items`, `canInteract`, `args`, and exactly one action: `onSelect`, `export`, `event`, `serverEvent` or `command` | 🟡 |
| Bad registrations raise an error naming the resource, the option/zone and the field | 🟡 |
| `groups`/`items` filters use VeylCore PlayerData and veyl_inventory counts. If that data is missing, the option is hidden, never shown unrestricted | 🟡 |
| `serverEvent` sends `{ netId, coords, name, args }` and never a local handle. **Server handlers must re-validate** | 🟡 |
| Developer outlines with `setr veyl_target:debug true` | 🟡 |
| Polygon zones, bone/offset vehicle points, submenus, cursor mode | 📋 |

## veyl_inventory (engine)

veyl_inventory is the only item authority. Item definitions live in `data/items.lua` on the server only, and slots,
quantities, metadata and revisions are stored in `veyl_inventory_slots` / `veyl_inventories`.

### Transfer guarantees

Moves, splits, merges and swaps between `primary` (pockets) and `secondary` (the open stash):

- The client sends only refs, slots, a count, expected revisions and an operation id.
- The server re-checks the character, the session generation, distance and stash groups/ownership on every request.
- Inventories are locked in sorted order, and every check is repeated on a copy while locked.
- One DB transaction holds the slots, the revisions and the operation record. Nothing is acknowledged or applied before the commit.
- A repeated operation id returns the stored result, and an id reused for a different request is rejected.
- If the client's revisions are stale, the server returns `STALE` and pushes a fresh snapshot.

### Item use

1. `useStart` reserves the exact slot and item instance.
2. The player sees a progress bar.
3. `useComplete` checks the elapsed time against the server-side duration, then commits the consumption, the reservation
   status and the `use:<id>` operation in one transaction.
4. The handler then runs exactly once.

A repeated completion returns "Already used". Reservations expire, and any still active are expired at restart.

### Server exports (`target` = a player source or an inventory id)

| Kind | Exports | Status |
| --- | --- | --- |
| Reads | `Items(name?)`, `GetInventory`, `GetInventoryItems`, `GetItemCount`, `GetSlot`, `GetSlotWithItem`, `GetSlotsWithItem`, `Search(target, 'count'\|'slots', item)`, `CanCarryItem` (preview only) | 🟡 |
| Legacy sync | `AddItem(target, item, count, metadata)` / `RemoveItem(...)` → `success, resultOrError`. Applied to memory, then written behind in order, and refused while a durable operation holds the inventory | 🟡 |
| Durable async (trailing callback) | `GiveItem(citizenid, item, count, metadata, opId)`, `TakeItem(...)`, `CanCarry(...)`, `GetOperation(opId)` → `{ status = 'done' }` or `nil` (operations are atomic with their effect) | 🟡 |
| Registration | `RegisterStash({ id, label, slots, maxWeight, owner, coords, radius, groups })`, `RegisterUseHandler(name, fn(ctx))`, `RegisterUsableItem(item, fn(src, item))` (QB path), `GetUsableItem` | 🟡 |
| Client | `openInventory('stash'?, id)`, `closeInventory`, `useSlot`, `GetItemCounts`, `GetItemCount`, `Items`, `IsOpen`; key **F2** (rebindable) | 🟡 |
| Hooks, hotbar, give/drop, vehicle storage, shops with stock, weapons, crafting, containers | | 📋 later phases |
| Purchase protocol with `ReserveFunds` / `CommitFunds` / `ReleaseFunds` | | 📋 phase 5. veyl_shops still uses `DebitOnce` → `GiveItem` → refund. Because `GiveItem` is now atomic with its operation record, reconciliation can tell "delivered" from "not delivered" exactly |

Test items: `water_bottle` (consumable), `identity_card` (unique, schema-checked metadata), `scrap_metal` (stackable
material), plus `sprunk`, `coffee`, `sandwich`, `burger`, `bandage`, `phone`, `qbexample_token`.

Stashes (config): `legion_lockers` (personal) and `legion_shared` (shared crate) near Legion Square.

Migration note: the unused `veyl_inventory_ops` table from the v0.2 adapter can be dropped. The ox → native data
converter (phase 7) is not built.

## Sprint acceptance checklist (in-game, still to run)

- [ ] Menu, form and alert: keyboard-only use, Escape, focus restored, and `restart veyl_lib` while one is open
- [ ] Target: NPC (depot), zone (stash) and vehicle (delivery van) options; options hide when groups/items are missing
- [ ] Inventory: drag, split, merge, swap, Ctrl-click and keyboard; pending state until the server delta arrives
- [ ] Two players take the last item from `legion_shared` at the same time: exactly one succeeds
- [ ] Opposite simultaneous transfers: no deadlock, consistent totals
- [ ] Use water: progress, then consumed once; cancel leaves the item; a repeated completion gives no second effect
- [ ] Walk away from an open stash: the next move is refused and the stash closes
- [ ] Disconnect and reconnect: items and positions restore from the DB
