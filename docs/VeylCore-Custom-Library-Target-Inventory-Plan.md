# VeylCore — Custom Library, Target & Inventory Rebuild Plan

**Version:** 1.0  
**Prepared:** November 20, 2026  
**Resources:** `veyl_lib`, `veyl_target`, `veyl_inventory`  
**Primary framework:** VeylCore  
**UI direction:** Original dark-and-violet VeylCore interface

Build three native VeylCore resources covering the roles currently filled by ox_lib, ox_target, and ox_inventory. Give them original code, documented APIs, a shared visual system, and custom menus. Deliver them as one coordinated package while keeping each resource independently maintainable.

This is a development plan, not a completed script pack. All VeylCore APIs, file paths, defaults, and examples below are proposed implementation contracts. Compatibility must be demonstrated against named resource versions.

## 1. Scope and relationship to the framework plan

| Current dependency | Custom resource | Main responsibility |
| --- | --- | --- |
| `ox_lib` | `veyl_lib` | Utility modules, callbacks, custom menus/dialogs, progress, notifications, zones, and UI focus coordination |
| `ox_target` | `veyl_target` | Entity/zone targeting, option filtering, interaction selection, and a custom targeting overlay |
| `ox_inventory` | `veyl_inventory` | Authoritative item storage, item use, transfers, weapons, stashes, shops, crafting, and custom inventory UI |

This companion plan changes the intended end state of the VeylCore framework plan:

- `veyl_inventory` becomes the inventory engine and owns item definitions, slots, quantities, and metadata.
- New native resources import `@veyl_lib/init.lua` and use the `vlib` namespace.
- `veyl_target` becomes the targeting provider. Existing `veyl_interact` calls may forward to it during migration.
- General-purpose menu and utility UI moves into `veyl_lib`. Existing `veyl_ui` calls may forward during migration; do not run a competing focus manager.
- `veyl_core` continues to own characters, personal money, jobs, gangs, permissions, and character metadata.
- `oxmysql` may remain the SQL driver. Replacing the three requested systems does not require building a database driver.

The final native VeylCore profile must boot and complete its acceptance scenarios with ox_lib, ox_target, and ox_inventory stopped. Until that gate passes, upstream dependencies remain part of the documented transitional profile.

### Release scope

| Release | Included | Deferred |
| --- | --- | --- |
| Vertical-slice prototype | Custom menu, one NPC/zone interaction, basic player inventory, a stash, one consumable, and reconnect persistence | Weapons, broad compatibility, public deployment |
| Closed alpha | Full target registrations, normal inventory operations, hotbar, drops/giving, vehicle storage, shops, and core integration | Advanced containers and broad third-party support |
| Production candidate | Weapons/ammo/components, crafting, durability, documented compatibility subset, conversion/rollback, and restart/concurrency checks | Optional features outside the server's actual dependency audit |
| Expansion | Trade window, advanced containers, additional utility modules, developer editors, and additional framework adapters | No automatic promise to reproduce every upstream module |

Start with native VeylCore support. QBCore/QBox adapters are separate compatibility targets. Their host framework and other resources may still require ox components; those profiles cannot be described as independent of ox until their full dependency chains have been checked.

## 2. Architecture and ownership

### Runtime dependencies

| Resource | Required dependencies in the native profile | Optional integration |
| --- | --- | --- |
| `veyl_lib` | FiveM runtime and its packaged UI assets | Framework adapters supplied by consumers; no dependency on core or inventory |
| `veyl_core` | `veyl_lib`, SQL driver | Registers character/group services used by adapters |
| `veyl_inventory` | `veyl_lib`, SQL driver, configured VeylCore adapter | Target integration, vehicle service, medical/item effects |
| `veyl_target` | `veyl_lib` | Core group adapter and inventory count adapter |
| Gameplay resources | Only the services they actually use | Separate compatibility shims when needed |

`veyl_lib` must work without a logged-in character. It cannot call inventory/core during its bootstrap. Core initialization cannot wait for target to start. Inventory must support an ordinary key/menu open path so it does not depend on target to function.

Target registers optional group/item adapters after their providers become ready. An option requiring unavailable data stays unavailable; it must not become unrestricted. Do not create circular manifest dependencies to solve readiness.

### Shared UI code

Use Lua for FiveM services and React with TypeScript for the NUI applications. Keep common components, theme tokens, icons, and message types in a build-time package such as `packages/veyl-ui/`.

Each resource ships its own compiled UI assets:

- `veyl_lib` hosts utility menus, dialogs, progress, notifications, and prompts.
- `veyl_target` hosts a lightweight interaction overlay.
- `veyl_inventory` hosts item grids and its embedded context menus/dialogs.

The shared component package is not a fourth required FiveM resource. Pin frontend dependencies and ship production builds so the server owner does not need a development web server.

### Authority rules

| Data or decision | Authoritative owner |
| --- | --- |
| Character identity, group membership, cash/bank | `veyl_core` |
| Item definitions, quantities, slots, metadata, inventory revision | `veyl_inventory` server |
| Whether a stash/shop/transfer is authorized | Inventory server plus current core/vehicle rules |
| Which target appears under the crosshair | Target client, as presentation only |
| Whether an interaction pays money or grants an item | The responsible server gameplay handler |
| Focus allocation and modal coordination | `veyl_lib` client broker, applied by the resource owning the NUI page |
| Colors, layouts, filtering, drag preview | NUI; never authority for persistent game state |

## 3. Custom menu and inventory UI

### Visual direction

Use a restrained dark interface with violet selection states, sharp item artwork, readable spacing, and short transitions. Keep VeylCore's mascot on help/onboarding screens. Gameplay menus should emphasize the action and its result.

| Token | Starting design value |
| --- | --- |
| Main surface | `#11121A` |
| Raised panel | `#1B1D2A` |
| Border | `#343247` |
| Primary accent | `#8B5CF6` |
| Selected outline / focus ring | `#C4B5FD` |
| Primary text | `#F5F3FF` |
| Secondary text | `#B8B2C8` |
| Success / warning / error | `#4ADE80` / `#FBBF24` / `#F87171`, always accompanied by text or an icon |
| Corners and spacing | 10–12 px corners; 8 px spacing increments |
| Typography | Packaged readable sans-serif; 14–16 px body text at the reference resolution |
| Motion | Approximately 120–180 ms transitions; reduced-motion option |

These are design starting points. Verify text contrast and readability on bright and dark in-game scenes before approving the theme. Package fonts and essential icons/images locally.

### Screen specifications

| Screen | Layout and content | Interaction behavior |
| --- | --- | --- |
| Context/action menu | Approximately 400 px panel; title, optional breadcrumb, icon rows, description, status/price, and footer controls | Mouse or arrows; Enter selects; Escape closes or returns; disabled rows explain why |
| Form dialog | Centered compact form with text/number/select/checkbox controls and visible validation | Tab navigation; submit once; cancel returns a distinct result |
| Confirmation dialog | Action name, consequence, confirm/cancel buttons | Destructive actions use explicit labels such as “Drop 5 items” |
| Notifications | Consistent corner stack with icon, title, message, and lifetime | Merge repeated messages where appropriate; no input focus |
| Progress | Small lower-screen bar or ring with action label and cancel hint | Cancel/death/resource-stop clean up controls, animations, and props |
| Text prompt | Small key badge and action text near the lower center | Never takes mouse focus; updates only when content changes |
| Target overlay | Small custom reticle and compact option list near the aim point | Hold-to-target by default; wheel/arrows select; a mapped key confirms; optional click-selection mode |
| Inventory | Two main panels: personal inventory and the current stash/trunk/shop; search/filter, weight, slots, item details, and hotbar | Drag/drop, quick-transfer, split quantity, use/give/drop, and keyboard alternatives |
| Shop | Item grid with unit price, quantity, basket summary, and wallet/account selector where supported | Final prices and availability come from the server |
| Crafting | Recipe list, materials needed/owned, duration, and output preview | Server controls recipe, ingredients, duration, and completion |

### Inventory layout details

Use a maximum width around 1120 px and a viewport limit around 94vw, with a maximum height around 86vh. The proposed default player inventory is 30 slots and 30,000 grams, both configurable. Use five columns when space permits and responsive column counts at smaller widths.

Show item image, quantity, durability when applicable, and a clear selection state. Hover or keyboard selection opens a detail panel with description, weight, and approved metadata. Hide private metadata unless the viewer is authorized.

The five hotbar positions reference inventory items/slots; they do not hold duplicate items. When an item moves or disappears, the server-defined binding behavior updates the hotbar. Display weight in readable units while storing integer grams.

Right-click actions, split dialogs, and tooltips inside inventory use the shared component package within the inventory page. They do not open a second resource's modal over the inventory.

Invalid drops, full inventories, stale data, and lost access need visible feedback. Animate a pending move, then apply the server-confirmed result. Never show a permanent successful transfer before the server acknowledges it.

### Focus, inputs, and black-screen prevention

Implement one modal focus broker in `veyl_lib`. A requesting resource receives an ownership token and applies focus within its own resource. Cfx NUI focus belongs to the current resource and uses a focus stack, so one helper must not assume it can focus any other resource's page directly. [S9]

Rules:

1. Only one full modal owns keyboard/mouse input at a time. Queue or reject conflicting requests with a defined result.
2. Passive target prompts, notifications, and text hints never steal input focus.
3. Opening a target action menu closes the target overlay before granting modal focus.
4. Escape, logout, death where appropriate, resource stop, and UI startup failure release the owning token and restore controls.
5. A restarted broker clears stale ownership and asks every surviving UI resource to close/reset before new focus is granted.
6. Do not change the game camera or fade the screen for ordinary menus. Any feature that does change them must own its cleanup.
7. Keep the NUI page transparent and hidden until an explicit open message. A missing asset must produce a bounded error, not an opaque screen.

Every NUI request has a request ID, action ID, and defined success/failure response. Always resolve the NUI callback, including validation errors, so requests do not hang. Registered Lua handlers determine the operation; the browser cannot supply an arbitrary server event, export, command, price, or item grant. [S10]

## 4. `veyl_lib` development plan

Ox_lib spans UI, callbacks, caching, streaming, zones, and many other utilities. Its Lua import also establishes globals; reproducing menus alone will not satisfy resources that depend on those other behaviors. Audit actual usage and implement a documented subset first. [S1]

### First library modules

| Module | Initial behavior | Completion requirement |
| --- | --- | --- |
| Bootstrap | `@veyl_lib/init.lua` creates `vlib` and a separate `vcache` namespace | Side-aware imports; no overwrite of upstream `lib`, `cache`, or global `require` |
| Menus | Register/show/hide action menus, child menus, disabled rows, metadata, and selection callbacks | Stable option IDs; no callable Lua functions serialized into NUI |
| Forms / alerts | Input validation, selections, confirmations, and cancellation | Explicit result types and keyboard operation |
| Notify / text UI | Notification queue, deduplication, and key prompts | No modal focus and reliable replacement/removal |
| Progress / skill check | Cancelable actions, animations/props, visual skill checks | Timers and cleanup; client success is never sufficient proof for a valuable reward |
| Callbacks | Registered client/server request handlers, awaiting and callback forms | Request IDs, bounded payloads, timeouts, sender matching, rate limits, and disconnect cleanup |
| Cache / keybinds | Ped/vehicle/seat change notifications and rebindable controls | Event/change-driven updates where possible; no repeated heavy lookups by every consumer |
| Points / zones | Nearby-point queries, spheres, rotated boxes, and later polygons | Spatial indexing, enter/exit behavior, height checks, and resource-owned cleanup |
| Streaming | Request models, animations, and particle assets | Invalid-name rejection, timeouts, and ownership/refcount cleanup |
| Locale / helpers | Locale fallback, validation, basic table/math helpers, logging | Deterministic results, bounded input, and documented client/server scope |
| Hooks / commands | Registered hooks and server command wrappers | Owner tracking, unregister on stop, and permission checks by the responsible service |

Radial menus, advanced vehicle-property helpers, scheduling/cron, DUI/scaleform helpers, and JavaScript SDK parity are later modules unless the dependency audit makes one a release blocker. Mark their status explicitly.

### API conventions

Use lowercase method names in `vlib`, a separate versioned message protocol, and a documented distinction between client-only, server-only, and shared functions. Native network actions return `{ ok, code, data }`; menus, handles, and local queries retain their own documented result types.

Proposed examples:

```lua
-- Proposed client API after importing @veyl_lib/init.lua.
vlib.notify({ title = 'VeylCore', message = 'Shift available', type = 'info' })

vlib.registerMenu({
    id = 'delivery:depot',
    title = 'Delivery Depot',
    options = {
        { id = 'start', label = 'Start shift', description = 'Collect a van and route' },
        { id = 'history', label = 'Route history', description = 'View completed shifts' }
    }
}, function(optionId)
    -- Request the chosen action through a validated gameplay handler.
end)

vlib.showMenu('delivery:depot')
```

For native callbacks, define explicit options such as `timeoutMs` and `cooldownMs`; do not combine them. An ox compatibility adapter must preserve ox's callback `delay` as a retrigger delay, not reinterpret it as a network timeout. Preserve multiple return values and `nil` positions when bridging legacy callbacks. [S2]

Correlate each response to its expected caller, handler, connection generation, and request ID. Ignore late or duplicate responses. Cancel pending requests during logout and resource shutdown. Do not make privileged operations available merely because a callback name is registered.

## 5. `veyl_target` development plan

### Targeting behavior

Build one client targeting loop with an asynchronous camera shape test and a nearby-zone index. Evaluate only relevant registrations. Avoid a loop per target and avoid scanning every entity/model registration every frame.

| Feature | Planned behavior |
| --- | --- |
| Entity types | Peds, players, vehicles, and objects, with separate global filters |
| Model registrations | One or multiple model hashes/names; named options can be removed |
| Networked entities | Register by network ID; validate entity existence and identity when selected |
| Local entities | Register by local handle; never treat the handle as a server entity ID |
| Zones | Sphere and rotated box first; polygon with thickness before zone-parity claims |
| Vehicle interaction | Bone and offset targeting for trunk, doors, hood, and other configured points |
| Conditions | Distance, group/grade, duty, item count, and a local display predicate |
| Option organization | Stable owner/name IDs, ordering, submenus, and cleanup on resource stop |
| Controls | Configurable hold/toggle targeting, rebindable selection, optional cursor mode |
| Developer mode | Zone outlines, selected entity/model data, and option-filter reasons; permissioned developer tools |

Define deterministic overlap rules: priority, then relevant hit distance, then stable registration order. A target lost because the player moves away, the entity disappears, or a modal opens must stop being selectable immediately.

Validate zone vectors and dimensions on registration. Accept the documented native vector type; normalize imported table representations in adapters. Bad input returns an error identifying the resource, option/zone, and invalid field instead of causing a later `vec3` crash.

### Native API and adapters

Proposed native exports include `addModel`, `addEntity`, `addLocalEntity`, global registrations by entity type, `addBoxZone`, `addSphereZone`, `addPolyZone`, corresponding removals, `removeZone`, `zoneExists`, and `disableTargeting`.

These names deliberately ease conversion, but only implemented and tested methods are supported. In the ox API, `addEntity` uses network IDs while `addLocalEntity` uses client handles; preserve that distinction. [S3]

Proposed native zone example:

```lua
-- Client; illustrative coordinates must be replaced with your configured depot.
local depotZone = exports.veyl_target:addBoxZone({
    name = 'delivery_depot',
    coords = vec3(0.0, 0.0, 72.0),
    size = vec3(1.5, 1.5, 2.0),
    rotation = 0.0,
    options = {
        {
            name = 'delivery_open',
            label = 'Delivery Depot',
            distance = 2.0,
            onSelect = function()
                vlib.showMenu('delivery:depot')
            end
        }
    }
})
```

### Safe action dispatch

Native options should have one declared action. An ox adapter may accept legacy action fields, but must choose exactly one using the documented precedence and translate entity data correctly. Ox prioritizes selection callbacks before exports, client events, server events, and commands. [S4]

NUI returns an option/session ID, not executable routing information. The client resolves it from its registry and rechecks that it is still applicable. Server actions independently validate current distance, group, entity, activity state, cooldown, and ownership.

Client group/item filters improve the UI only. Registering a zone or showing “Open police armory” does not authorize the player to open it on the server. Local-only targets that initiate a server action must use a server-known location/action identifier instead of sending an unusable local entity handle.

## 6. `veyl_inventory` development plan

Build the server item engine before the full drag-and-drop interface. The UI must operate on the same verified services used by server scripts. Ox exposes item, capacity, stash, and hook interfaces; use its documented contracts to identify migration needs, while defining VeylCore's own internal model. [S5, S6]

### Item model

| Field / concept | VeylCore rule |
| --- | --- |
| Item name | Stable internal identifier, separate from the display label |
| Definition | Label, description, local image, integer weight, stack rules, usability, and permitted metadata |
| Instance | Item type, positive integer count, slot, normalized metadata, and unique ID where required |
| Stack identity | Item type plus all gameplay-relevant metadata; different serials/ownership/durability/expiry must not merge silently |
| Quantity | Validate type, range, and integer count on the server; reject zero, negative, fractional, missing, or overflowing values |
| Metadata | Server schema and size limits; derive labels/images only from allowed fields |
| Durability | Defined numeric scale and/or expiry timestamp; conversion must preserve the source meaning |
| Unique items | Server-generated serial/instance identity with database uniqueness where appropriate |
| Use behavior | Registered trusted handler, requirements, duration, consumption rule, and cancellation behavior |

Proposed definition file:

```lua
-- veyl_inventory/data/items.lua; proposed VeylCore schema.
return {
    water_bottle = {
        label = 'Water Bottle',
        description = 'A bottle of drinking water.',
        image = 'water_bottle.webp',
        weight = 500,
        stack = true,
        maxStack = 10,
        use = { handler = 'drink_water', durationMs = 2500, consumeCount = 1 }
    },
    identity_card = {
        label = 'Identity Card',
        image = 'identity_card.webp',
        weight = 10,
        stack = false,
        metadataSchema = 'identity_card'
    }
}
```

The server resolves `drink_water` from a registered handler and derives the effect. The NUI cannot submit new handlers, custom effects, or authoritative metadata. Upstream item definitions may encode consumption, degradation, exports, and client effects differently; convert those meanings explicitly. [S7]

### Features and release priority

| Area | Required behavior | Gate |
| --- | --- | --- |
| Player inventory | Slots, weight, metadata, add/remove/count, move/swap/split/merge | Prototype |
| Personal/shared stashes | Server registration, explicit access rules, ownership, and concurrent access | Prototype |
| Item use | Validated use, reservation, progress, cancel, consumption, and effect | Prototype |
| Persistence | Character load/unload, durable mutations, revision checks, and recovery | Prototype |
| Hotbar / give / drops | Stable bindings, nearby recipient validation, scoped drops, and cleanup | Closed alpha |
| Vehicle storage | Trunk/glovebox linked to a stable vehicle ID, with current access checks | Closed alpha |
| Shops | Catalog, prices, stock, core-money settlement, and capacity checks | Closed alpha |
| Weapons | Unique weapon items, equip/unequip, ammo, components, durability, and reconnect handling | Production candidate |
| Crafting | Server recipes, ingredient reservations, duration, cancellation, and atomic output | Production candidate |
| Containers | Bags with separate inventory identity, type restrictions, and capacity | After base inventory stabilizes |
| Advanced features | Trade windows, evidence workflows, searchable history, and custom item actions | Expansion driven by actual use |

Do not allow recursive containers in the first container release. A bag cannot contain itself, and moving a container must preserve its contents and access rules. Public release is blocked if enabled server gameplay requires an inventory feature still marked deferred.

### Database design

| Proposed table | Main fields / constraints |
| --- | --- |
| `veyl_inventories` | Stable ID, type, owner/character/vehicle reference, slot count, capacity, revision, and schema version |
| `veyl_inventory_slots` | Inventory ID, slot, item name, count, metadata JSON, optional unique instance ID; unique inventory/slot pair |
| `veyl_inventory_operations` | Operation ID, actor/character, operation kind, affected inventories, request fingerprint, outcome, and timestamps |
| `veyl_inventory_drops` | Drop identity, inventory reference, position, routing bucket, lifetime, and recovery state |
| `veyl_inventory_reservations` | Item-use/crafting reservation, item identity/count, operation, expiry, and terminal result |
| `veyl_inventory_audit` | Important transfers/grants/removals, reason, actor, and operation correlation |
| `veyl_shop_stock` | Shop/SKU stock and outstanding reservations where finite stock is enabled |

Keep inventory access sessions in server memory and regenerate them after reconnect/restart. A session records the actor's current character generation and authorized inventory context. Its token is a request correlation mechanism, not a substitute for authorization.

Use one canonical store for all player/stash/vehicle item quantities. Do not copy live items into `players.inventory`, a QB-style cache, and a separate inventory table as competing authorities. Any legacy `PlayerData.items` view must be derived.

### Transfer algorithm

Every move, swap, split, give, or drop follows this sequence:

1. Receive only operation/session IDs, source and destination slots, requested count, and expected revisions.
2. Resolve both inventories on the server; validate actor, current character, proximity, routing bucket, ownership, group/duty access, and allowed operation.
3. Acquire per-inventory locks in a consistent order. Start a database transaction and use row locks or revision-based conditional updates to protect persisted state.
4. Re-read/validate quantities, metadata, stack rules, slot restrictions, capacity, and any item reservations under the lock.
5. Run bounded validation hooks. Write both inventory changes, revisions, and the successful operation record in the same transaction.
6. Commit, update server caches, and publish deltas to authorized viewers. If commit fails, do not acknowledge success or apply a permanent UI change.
7. On a duplicate operation ID, verify that its actor and request fingerprint match, then return the stored result. Reject attempts to reuse the ID for a different request.

`CanCarryItem` is a helpful preview. The mutating operation must check capacity again under the lock, because another request can change it between calls. Swaps check the resulting capacity and slot rules on both sides.

Use revision numbers in client messages. If an update is missing or a request is stale, return an authoritative refresh. Do not accept a full browser-supplied inventory as a save payload. Recheck access for every mutation and close secondary inventories when permission, distance, or instance changes.

### Use, crafting, weapons, and drops

- **Item use:** reserve the exact item/count, issue a server-owned action, and validate completion/cancellation. Apply the durable consumption and retry-safe server effect with one operation identity. A client progress result alone cannot authorize healing, rewards, or repeated effects.
- **Crafting:** reserve inputs during the action. At completion, validate recipe/access and commit input consumption plus output creation atomically where they share the inventory store. A canceled or expired action follows one documented reservation-release rule.
- **Weapons:** keep serials, components, allowed ammo, and equipped item identity in inventory state. Reconcile equip/reload/unequip against possession and reservations; clear unauthorized or stale equipped state on death, logout, and resource restart. Treat client ammo reports as bounded observations, never permission to grant ammo.
- **Drops:** store item ownership in a drop inventory, separate from its visible world prop. Use current location/bucket checks. Recover or expire drops with an explicit policy so a missing/deleted prop never duplicates or silently deletes valuable items.
- **Vehicle storage:** derive identity from the vehicle service, with a documented migration mapping for legacy plate-based IDs. Recheck key/lock/distance rules during use.

Maintain one weapon/inventory integration per player. Inventory item-use effects must not run once through a legacy usable-item callback and again through the native handler.

### Money and purchases

Personal cash/bank remains in `veyl_core`; inventory does not create a second spendable cash-item balance. A purchase must coordinate money, stock, and item delivery durably.

The initial proposed coordination contract is:

1. Reserve stock and create a purchase operation with server-calculated price.
2. Ask core to reserve funds under that operation ID; reserved funds are no longer spendable.
3. Commit item delivery and its unique operation receipt in inventory storage, with a final capacity check.
4. Finalize the reserved debit and stock consumption. A failure after delivery leaves a recoverable settlement task, not an automatic refund.
5. Release funds/stock only after durable records prove delivery did not occur. Recovery uses the same IDs and outcomes.

Proposed core calls such as `ReserveFunds`, `CommitFunds`, and `ReleaseFunds` are new work, not existing upstream exports. Core must not expire/refund an unresolved reservation independently while inventory may have delivered. Use service APIs to inspect the operation and reconcile it. Test interruption at every boundary.

If a shared transaction coordinator is implemented instead, document its lock order and service boundaries. Do not improvise with two independent `RemoveMoney` / `AddItem` calls.

### Native exports and hook contracts

| Surface | Proposed native operations |
| --- | --- |
| Server reads | `Items`, `GetInventory`, `GetItemCount`, `GetSlot`, `Search`, `CanCarryItem` |
| Server mutations | `AddItem`, `RemoveItem`, `SetMetadata`, `SetDurability`, and operation-aware internal transfer/use methods |
| Server registration | `RegisterStash`, `RegisterShop`, `RegisterCrafting`, `RegisterUsableItem` |
| Server extension | `RegisterHook`, `RemoveHook`, and committed-action notifications |
| Client requests | `openInventory`, `closeInventory`, `useItem`, and hotbar actions; server checks remain mandatory |

Document exact identifiers, arguments, result shapes, errors, and resource permissions before implementation. `AddItem` / `RemoveItem` return `success, resultOrError`; operation-aware native paths also accept a trusted operation context. Do not expose unrestricted grant/remove network events.

Validation hooks can reject an operation or produce an allowed pure metadata transformation. They must not recursively mutate inventory or perform unrelated side effects. Post-commit notifications carry an operation ID for repeat-safe downstream work. Hooks need duration limits, filters, owner tracking, and cleanup. Upstream hook guidance similarly separates validation from follow-up effects. [S6]

## 7. Compatibility and conversion strategy

### Two distinct deliverables

| Deliverable | What it proves |
| --- | --- |
| Native VeylCore suite | Its documented VeylCore APIs work without the three upstream resources |
| Compatibility package | A named subset of upstream imports/exports/events works for a specific tested resource/version |

Audit real consumer resources before choosing bridge scope. Record static imports, exports, globals, events, convars, framework detection, SQL access, item definitions, weapon integration, and hooks. Include callbacks invoked dynamically; a text search alone cannot prove complete coverage.

### Initial mapping

| Upstream usage | Native direction | Compatibility work |
| --- | --- | --- |
| `@ox_lib/init.lua`, `lib.*`, `cache` | `@veyl_lib/init.lua`, `vlib.*`, `vcache` | Implement actual loader/module behavior for the claimed subset; translate return values and lifecycle |
| `lib.registerContext` / `showContext` | Native menu registration/show methods | Map options, submenus, metadata, ordering, close/back callbacks, and selection behavior |
| ox callbacks | Native callback module | Preserve argument/return semantics and retrigger delays separately from timeouts |
| ox target registration exports | `exports.veyl_target:*` | Preserve network/local entity meaning, option conditions, removals, and action dispatch |
| Inventory item/capacity exports | `exports.veyl_inventory:*` | Match each supported method's slots, metadata filters, errors, and callback behavior |
| Stash/shop registrations | Native server registration | Convert owner/group/location meaning and verify current access rules |
| Inventory hooks/events | Native pre/post action interfaces | Match supported event names, payloads, cancellation, and registration IDs |
| Upstream NUI files / private modules / direct SQL | Explicit source port | No automatic compatibility claim |

Ox context menus contain behavior beyond a title and rows, including nested navigation and close callbacks; the adapter needs behavior tests as well as visual checks. [S8]

After native ports work, optional compatibility resources may occupy the old `ox_lib`, `ox_target`, or `ox_inventory` names. Those are shims backed by VeylCore; the original resource with that name must be stopped. A manifest replacement declaration does not implement exports or supply `@ox_lib/init.lua` and its imported files. [S11]

Never define the same resource name twice. During staging, original and new resources may exist under different names, but route each consumer to one chosen provider. Only one inventory may mutate a given character's active inventory.

### Compatibility register

For every target resource, record version/commit, used API list, implemented adapters, pass/fail scenarios, and unresolved dependencies. Label each integration `native`, `bridge-tested`, `requires-port`, or `unsupported`.

Unsupported calls return a clear error naming the missing API and resource. Do not return fake success, empty inventories, or default permissions to make a script appear compatible.

## 8. Data migration and retirement of ox resources

### Migration phases

1. **Inventory the dependency chain.** Identify every consumer of the three ox resources, including framework code and inventory/weapon integrations. Pin the source versions and schema.
2. **Build the library and UI.** Native VeylCore consumers can move to `veyl_lib` gradually while unported consumers continue using the real ox_lib. Use distinct namespaces and select one active modal flow at a time.
3. **Replace target per consumer.** Convert registrations and remove their old registrations. Do not run two targeting overlays for the same control/interaction.
4. **Build inventory on isolated test data.** Use a staging database and test characters. Do not have the new inventory write to live ox tables.
5. **Rehearse conversion offline.** Convert a consistent backup, validate it, and run the gameplay scenarios against the new store.
6. **Cut over in maintenance.** Stop writes, take a final consistent backup, run the tested converter once, validate, switch consumers, and start one active inventory provider.
7. **Retire remaining upstream dependencies.** Remove each ox resource only when the dependency register and full native-profile boot test prove it is unused.

### Converter requirements

| Data | Required treatment |
| --- | --- |
| Player inventories | Preserve character ownership, quantities, valid slot assignments, and item metadata |
| Stashes / trunks / gloveboxes | Preserve contents and map IDs/owners/vehicles; migrate access policy separately |
| Weapons / ammo / attachments | Map item names, serials, loaded ammo, compatible components, and durability |
| Containers | Preserve parent/content relationships or quarantine unsupported container types with a recoverable record |
| Item definitions and images | Translate behavior and packaged asset paths; record unknown items or missing artwork |
| Durability / expiry | Convert documented scales/timestamps; never treat an expiry timestamp as a percentage |
| Missing or unknown items | Quarantine with original data and an admin resolution report; never silently discard |
| Cash items | Require an explicit conversion policy that prevents both item money and numeric money being credited |

The converter needs dry-run mode, a source-version/checksum record, repeat-safe execution, row/item/quantity totals, and a report of every transformation and rejected record. Validate metadata and unique IDs, not just total item counts. Do not infer item use behavior from labels.

### Rollback

Keep the pre-cutover database and resource/config package together. Before reopening, reverting those paired snapshots is the simplest rollback. Once players create new transactions on VeylCore, restoring only the old inventory snapshot would lose or duplicate progress. After live writes begin, rollback requires maintenance plus an explicit reconciliation/reverse-conversion process, or a forward fix.

This plan does not modify a live server or convert any existing database. Those actions belong to implementation and deployment after the acceptance gates pass.

## 9. Build order and completion gates

Build the library first, target next, and the inventory engine before the full inventory interface. Each gate is a demonstrable result, not a calendar promise.

| Phase | Implementation work | Gate to continue |
| --- | --- | --- |
| 0 — Contracts and design | Dependency audit, supported API list, item model, data ownership, message schemas, and UI screens | Scope/status matrix complete; no unresolved ownership or startup cycles |
| 1 — UI foundation | Shared components, custom menu/form/notification/progress screens, and focus broker | All screens open/close with keyboard/mouse; error, cancellation, and restart paths restore controls |
| 2 — Library runtime | Bootstrap, callbacks, cache, keybinds, locale, streaming, points/zones, and cleanup | Native sample resources run without ox_lib; callbacks and imports pass lifecycle/error checks |
| 3 — Target | Raycast, target registry, sphere/box zones, entity types, conditions, and custom overlay | NPC, vehicle, and zone actions work; unavailable permissions hide actions; server rechecks protect execution |
| 4 — Inventory engine | Definitions, database, transactions, revisions, item operations, personal inventory, and one stash | Two players transfer items concurrently without quantity/metadata corruption; reconnect/crash recovery passes |
| 5 — Inventory UI and first loop | Two-panel grids, hotbar, split/use/give/drop, item details, one consumable, and one shop with durable settlement | Target depot, open menu, earn a payout, buy/use food, stash an item, and reconnect correctly |
| 6 — Gameplay completeness | Vehicle storage, expanded shops/stock, weapons/ammo/components, crafting, and required durability behavior | Every enabled server gameplay dependency is supported; interruption and concurrency scenarios pass |
| 7 — Compatibility and migration | Named ox API subset, converted consumers, converter, recovery reports, and rollback rehearsal | Each supported integration has evidence; converted data reconciles with the source snapshot |
| 8 — Release candidate | Clean installation, package builds, documentation, permissions, profiler results, and final dependency removal | Full native VeylCore scenario passes with all three original ox resources stopped |

The phase-5 loop requires a small core adapter and testable core-money integration. If the core does not exist yet, use a clearly marked development stub for UI work and complete the real integration before passing that gate.

### First implementation sprint

1. Create the three resource skeletons and the shared UI package.
2. Define the native API/status document and NUI message types before writing consumer scripts.
3. Implement `veyl_lib` bootstrap, one action menu, notification, input dialog, and focus cleanup.
4. Add callback request IDs, timeouts, validation, and character/resource cleanup.
5. Add one sphere/box zone and one local-NPC target action that opens the custom menu.
6. Define three test items: water, a unique ID card, and a stackable material.
7. Implement one player inventory and one shared stash with transactional moves and revisions.
8. Connect a minimal inventory grid to those server services and verify two-player transfers.
9. Demonstrate item use, cancellation, disconnect, and reconnect before adding weapons or broad bridges.

## 10. Security, reliability, and validation

Server handlers derive the actor from the connection, validate the current character, and recheck all valuable actions. Reject malformed numbers, oversized metadata, forged inventory IDs, stale sessions, and arbitrary routing requests. Client checks and state bags are presentation aids, not authorization. This follows Cfx's guidance to validate network-triggered actions on the server. [S12]

Library callbacks that return client observations cannot authorize money/items on their own. Namespaced action IDs prevent accidental collisions but are not secrets or access controls. Put elevated inventory inspection/grant tools behind server permissions and record a reason.

### Acceptance matrix

| Scenario | Expected result |
| --- | --- |
| Utility menu open/close, keyboard-only use | Correct selection, cancellation, and focus restoration |
| Target opens a menu while inventory is active | Defined queue/reject behavior; no competing cursors or hidden modal |
| Resource stops while a modal/progress action is active | Focus, controls, animations, and owned props are cleaned up |
| UI assets fail or readiness times out | Visible bounded error; no permanent black overlay |
| Duplicate or late callback response | Original request resolves once; old session is unaffected |
| Resource restart re-registers targets | No stale or duplicate options |
| Invalid vector, size, or export name | Clear registration error identifying the caller and field/API |
| Entity disappears or a network ID is reused | Stale interaction cannot authorize the wrong entity |
| Target item/group condition changes | Display updates; server still rejects unauthorized actions |
| Two people take the last stash item | Exactly one successful transfer |
| Opposite simultaneous transfers | Consistent lock ordering; no unbounded deadlock or partial transfer |
| Duplicate drag/drop request | Stored result returned once; no duplicate mutation |
| Overweight destination or incompatible stack metadata | Transfer rejected without loss or silent metadata merging |
| Give to someone who moves away or changes bucket | Server rejects and preserves both inventories |
| Job/ownership access revoked while stash is open | Further access/mutations stop immediately |
| Disconnect or database failure during transfer | Both sides commit together or neither changes |
| Item-use completion sent twice or after cancellation | Effect/consumption follows one durable operation outcome |
| Craft interrupted or output inventory becomes full | Inputs/output follow the documented reservation/recovery policy |
| Purchase fails before/after delivery | Funds, stock, and items reconcile; no refund after successful delivery without explicit recovery |
| Weapon reload, unequip, death, and reconnect | Item identity, ammo, components, and equipped state remain consistent |
| Drop prop disappears or server restarts | Stored drop contents follow the configured recovery/expiry policy |
| Character switch reuses a server source | Previous character's requests and caches cannot affect the new one |
| Data conversion reruns | No duplicate items, owners, serials, or monetary credits |
| Final boot with original ox resources stopped | All advertised native features work; missing third-party dependencies are surfaced |

These tests are requirements for the future implementation. No FiveM runtime tests have been performed for this planning document.

### Performance plan

Measure idle, active targeting, many nearby registrations, inventory open, a busy shared stash, multiple simultaneous shop purchases, and resource restart. Record client/server frame cost, NUI rendering cost, Lua allocations, network payloads, SQL timing, lock contention, and total entities. Use Cfx profiler tooling and NUI developer tools as appropriate. [S9, S13]

Use results to set budgets for the actual host and target player count. Do not advertise a fixed player capacity or “0.00 ms” without measurements. Initial engineering goals are:

- No SQL calls or server callback round trips in per-frame target filtering.
- Spatial lookup and cached display data rather than full registry scans.
- Inventory deltas for ordinary changes, with snapshots for initial load/resync.
- No NUI rerender/message traffic when a hidden screen has no changes.
- Bounded queues, operation sizes, hook runtime, and retry counts.
- Large grids render efficiently and remain responsive with long labels and metadata.

## 11. Repository layout and release package

| Path | Purpose |
| --- | --- |
| `resources/veyl_lib/` | Manifest, init loader, shared/client/server modules, locales, and compiled utility UI |
| `resources/veyl_target/` | Manifest, registrations, raycast/filter logic, adapters, configuration, and compiled overlay |
| `resources/veyl_inventory/` | Manifest, item data, transaction engine, framework adapter, use/weapon modules, migrations, and compiled inventory UI |
| `packages/veyl-ui/` | Shared frontend components, theme tokens, icons, and message types |
| `compat/` | Optional named compatibility packages; installed only for the chosen profile |
| `tools/migrate-inventory/` | Version-specific converter, validation report, and recovery instructions |
| `examples/` | Menu demo, target demo, item use, stash, shop, and a delivery interaction |
| `docs/` | API contracts, setup, permissions, support matrix, troubleshooting, and release notes |
| `tests/` | Unit/contract tests plus a development-only FiveM integration harness |

Keep first-party runtime resources separate from optional compatibility shims. Record original versus adapted code and retain applicable upstream license/attribution notices for any reused code or assets.

### Intended final start order

After implementing the native dependencies:

```cfg
ensure oxmysql
ensure veyl_lib
ensure veyl_core
ensure veyl_vehicles
ensure veyl_inventory
ensure veyl_target
# Start character/spawn/UI consumers and gameplay after their declared dependencies.
```

Vehicle integration is required only for the profile enabling vehicle storage. Configure the selected framework/provider profile before resource startup. Do not include original ox_lib/ox_target/ox_inventory in the final native profile; transitional configurations are separate files.

Each release must include compiled NUI assets, database migrations, example configuration, translations, documented exports/events, error meanings, ownership cleanup, exact supported versions, and a compatibility status list. Supply a tested clean-install example and a migration guide as separate procedures.

Changes to the old `veyl_inventory` adapter API must be versioned; keep a deliberate forwarding layer where needed so existing VeylCore consumers can migrate incrementally.

## 12. Copy-ready developer brief

> Build a native VeylCore suite replacing the roles of ox_lib, ox_target, and ox_inventory. Name the resources veyl_lib, veyl_target, and veyl_inventory. Use Lua for FiveM services and React/TypeScript for custom NUI. Create an original, consistent dark-and-violet design for menus, forms, notifications, progress, target interactions, item grids, shops, and crafting. Share frontend components at build time and ship compiled assets.
>
> Keep veyl_lib independent of the core and inventory. Import it through @veyl_lib/init.lua using vlib and vcache namespaces. Implement bounded callbacks, menu handling, focus coordination, cache/keybinds, zones/points, streaming, locale, and the documented initial utility set. Build target entity/model/zone registration with one efficient raycast loop, a custom overlay, client display filters, and server validation in the responsible gameplay handler.
>
> Make veyl_inventory the only item authority. Implement server-owned definitions and metadata, slot/weight rules, transactional transfers, revisions, operation IDs, reservations, durable persistence, item use, stashes, giving/drops, shops, vehicle storage, weapons/ammo/components, and crafting in the specified phases. Keep personal cash/bank in veyl_core. Coordinate purchases with durable funds/stock/item outcomes. Do not accept browser-supplied prices, rewards, item metadata, inventory snapshots, or arbitrary event names as authoritative.
>
> Start with the custom-menu/NPC/stash/consumable vertical slice. Finish and demonstrate each milestone before expanding scope. Provide explicit API contracts, cleanup, manifests, migrations, examples, acceptance evidence, performance measurements, and versioned compatibility adapters. Audit actual ox consumers and migrate them deliberately. Preserve inventory data through a dry-run converter and rehearsed rollback. A release qualifies as independent of the three original ox resources only after the full native VeylCore profile passes with them stopped. Mark every unimplemented feature and unsupported integration clearly.

## References

Upstream behavior checked November 20, 2026. VeylCore architecture, API names, UI design, database layout, and milestones above are proposed decisions. Sources document the existing interfaces and platform behavior used to plan conversion; they do not prove compatibility of an unbuilt replacement.

- **Project context:** [VeylCore Framework Development Plan](https://chatgpt.com/library?file_id=libfile_aa2bc2f8fe308191bf03c83fda2217eb&account_id=personal)
- **S1:** [Ox Lib — Modules and importing](https://overextended.dev/docs/ox_lib)
- **S2:** [Ox Lib — Lua client callbacks](https://overextended.dev/docs/ox_lib/Callback/Lua/Client)
- **S3:** [Ox Target — Client exports](https://overextended.dev/docs/ox_target/Functions/Client)
- **S4:** [Ox Target — Option fields and selection behavior](https://overextended.dev/docs/ox_target/TargetOptions)
- **S5:** [Ox Inventory — Server interfaces](https://overextended.dev/docs/ox_inventory/Functions/Server)
- **S6:** [Ox Inventory — Hooks](https://overextended.dev/docs/ox_inventory/Functions/Server/Hooks)
- **S7:** [Ox Inventory — Item definitions](https://overextended.dev/docs/ox_inventory/Guides/creatingItems)
- **S8:** [Ox Lib — Context menus](https://overextended.dev/docs/ox_lib/Interface/Client/context)
- **S9:** [Cfx — Fullscreen NUI and focus](https://docs.fivem.net/docs/scripting-manual/nui-development/full-screen-nui/)
- **S10:** [Cfx — NUI callbacks](https://docs.fivem.net/docs/scripting-manual/nui-development/nui-callbacks/)
- **S11:** [Cfx — Resource manifests](https://docs.fivem.net/docs/scripting-reference/resource-manifest/)
- **S12:** [Cfx — Secure your events](https://docs.fivem.net/docs/developers/server-security/)
- **S13:** [Cfx — Using the profiler](https://docs.fivem.net/docs/scripting-manual/debugging/using-profiler/)



