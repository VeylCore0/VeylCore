# VeylCore — FiveM Framework & Script Development Plan

**Planning version:** 1.0  
**Prepared:** November 16, 2026  
**Project:** VeylCore, a custom FiveM roleplay framework  
**Resource prefix:** `veyl_`

This is a development blueprint. The resource names, interfaces, and features below are proposed work, not claims that these scripts already exist.

## 1. Project direction

Build a modular framework with a small core and separate gameplay resources. Give VeylCore its own player lifecycle, permissions, data contracts, and visual identity. Reuse selected infrastructure where it saves development effort, with explicit adapters for anything that expects another framework.

The first playable target is a complete, persistent loop:

1. Connect and choose a character.
2. Create an appearance and spawn.
3. Start a package-delivery shift.
4. Receive an assigned van and complete a route.
5. Earn a server-calculated payout.
6. Buy and use a food item.
7. Disconnect and reconnect with the correct character, money, and inventory.

Develop this loop before expanding the city into every job and criminal activity.

### Working assumptions

| Area | Proposed starting decision |
| --- | --- |
| Core | Independent VeylCore player/session and permission services |
| Gameplay scripting | Lua for client and server resources |
| Interface | NUI using HTML, CSS, and TypeScript; one shared visual system |
| Persistence | MariaDB with a tested, pinned SQL driver release |
| Inventory | Start with an ox_inventory integration through a custom VeylCore bridge |
| Interaction | One `veyl_interact` API, backed by your own implementation or one selected target provider |
| Money | Numeric cash and bank balances owned by one banking service; no duplicate cash-item balance |
| Starting map | Standard GTA map with a small set of test locations and stock vehicles |
| Runtime | One explicitly tested GTA edition and FXServer artifact/build combination |
| Compatibility | Native VeylCore scripts first; individual QBox/QBCore/ESX integrations evaluated later |
| Brand | Violet highlights, dark panels, readable text, and the cute mascot in loading/help screens |

If you choose a completely custom inventory, treat that as a separate substantial workstream and replace the inventory integration milestone. Avoid maintaining two active inventory authorities.

Existing `fw_` resources should be reviewed for their dependencies before being ported. A folder rename alone does not establish VeylCore compatibility.

## 2. Framework boundaries

| Component | Owns | Must not become a second owner of |
| --- | --- | --- |
| `veyl_core` | Accounts, active sessions, character ownership checks, lifecycle events, permissions, common request handling, audit facilities | Inventory slots, vehicle storage, or separate money balances |
| `veyl_characters` | Character records, character slots, selection and creation flow | Live player sessions independently of the core |
| `veyl_banking` | Cash, bank and business accounts, ledger entries, approved payouts and transfers | Inventory item state |
| `veyl_inventory` + chosen provider | Item operations and access rules; the provider remains the canonical slot store | A second copy of the provider's inventory |
| `veyl_jobs` | Job definitions, grades, membership, duty and payroll eligibility | Untracked direct money creation |
| `veyl_vehicles` | Vehicle IDs, ownership, key grants, controlled spawning, fuel and vehicle condition | Garage-specific duplicate ownership records |
| `veyl_medical` | Injury, incapacitation, treatment and respawn decisions | Conflicting death logic in every job |
| Activity scripts | Their own mission state and completion rules | Direct edits to another resource's private database tables |

Core startup must not require every optional gameplay script. Publish readiness states so dependent scripts can report a missing service clearly.

## 3. Script catalog

Build the first version of each script around a small complete feature set. Expansion columns are backlog, not launch requirements.

### Foundation

| Resource | First version | Later expansion |
| --- | --- | --- |
| `veyl_core` | Account/character mapping, session lifecycle, permission checks, versioned migrations, bounded callbacks, audit records | Developer diagnostics and capability discovery |
| `veyl_ui` | Notifications, progress bars, confirmation dialogs, input forms, shared styling and focus cleanup | Theme settings, accessible scaling and reusable tablet components |
| `veyl_interact` | Ped, entity and zone interactions with distance checks and an E-key fallback | Group filters, dynamic options and developer zone tools |
| `veyl_admin` | Player list, reports, teleport tools, permission checks and action logs | Spectate, staff notes and constrained economy diagnostics |
| `veyl_world` | Shared clock/weather, configurable ambient population and session cleanup | Night-only aurora, scheduled world events and seasonal presets |

### Player systems

| Resource | First version | Later expansion |
| --- | --- | --- |
| `veyl_characters` | Multiple character slots, identity creation, selection, ownership validation and safe deletion confirmation | Slot rules and staff recovery workflow |
| `veyl_appearance` | Ped customization, saved clothing and appearance restoration | Barber/tattoo shops, outfit sharing and job outfits |
| `veyl_spawn` | First spawn, approved spawn points, last-location recovery and readiness checks | Housing spawns and scene-specific return points |
| `veyl_inventory` | VeylCore adapter, item use/give/remove, stashes, shops and access validation | Crafting integrations, containers and more item metadata |
| `veyl_hud` | Health, armor, hunger, thirst, stress, stamina, oxygen and vehicle speed/fuel | Voice indicator through an adapter, seatbelt display and layout settings |
| `veyl_needs` | Persisted hunger/thirst, consumable effects and bounded status updates | Stress activities, configurable effects and recovery locations |

### Economy and employment

| Resource | First version | Later expansion |
| --- | --- | --- |
| `veyl_banking` | Cash/bank accounts, deposits, withdrawals, transfers, transaction history and duplicate-operation protection | Business accounts, invoices and configured virtual currencies |
| `veyl_jobs` | Job definitions, grades, duty, assignment and server-approved paychecks | Multijob, applications, boss menus and department budgets |
| `veyl_shops` | General store, server-owned prices, purchase validation and inventory-capacity handling | Limited stock, suppliers and restocking |
| `veyl_cityhall` | ID replacement, licenses and a list of available jobs | Applications, permits and appointments |
| `veyl_businesses` | Ownership, employees, invoices, company balance and permissioned withdrawals | Stock orders, workstations and business upgrades |
| `veyl_delivery` | Depot NPC, assigned van, randomized package stops and validated payout | Team routes, business deliveries, route reputation and fragile packages |

### Vehicles

| Resource | First version | Later expansion |
| --- | --- | --- |
| `veyl_vehicles` | Stable vehicle IDs, ownership, temporary job vehicles, keys/locks, fuel and saved condition | Key sharing, lockpicking hooks, insurance and persistent world parking |
| `veyl_garages` | Store/retrieve owned vehicles, spawn reservation and impound state | Shared/job garages and private property garages |
| `veyl_dealership` | Catalog, purchase confirmation and ownership registration | Staff sales, test drives, trade-ins and financing |
| `veyl_mechanic` | Repair actions, part consumption, service invoices and duty access | Inspections, tuning, wear and tow contracts |

Keys and fuel start as modules inside `veyl_vehicles`. Split them into resources later only when a clear integration or maintenance need justifies it.

### Emergency services and justice roleplay

| Resource | First version | Later expansion |
| --- | --- | --- |
| `veyl_police` | Duty, cuffs, escort/search permissions, citations, impound requests and basic evidence records | Warrants, detailed evidence workflows, K9 and tactical equipment |
| `veyl_medical` | Incapacitation, EMS calls, revive/treatment, hospital respawn and persisted injury state | Injury types, medical items, beds and treatment records |
| `veyl_dispatch` | Authorized call creation, duty-based recipients, blips, acknowledgments and expiry | Unit status, panic button and dispatch-center interface |
| `veyl_mdt` | Authorized character/vehicle lookup, reports, citations and case links | Warrants, mugshots, evidence attachments and department controls |
| `veyl_prison` | Server-set sentences, persisted remaining time and controlled release | Prison jobs, visits and rehabilitation activities |
| `veyl_doorlocks` | Registered doors, job/grade/key access and synchronized lock state | Business controls, temporary access and breach integrations |

Use one dispatch service as the authority. External dispatch or MDT resources need explicit adapters and a tested supported-version list.

### Civilian life

| Resource | First version | Later expansion |
| --- | --- | --- |
| `veyl_housing` | A small apartment offering, ownership/access, stash and wardrobe | Furnishing, rentals, keys and property sales |
| `veyl_crafting` | Recipes, materials, workstations, server-validated completion and inventory delivery | Work orders, job restrictions, quality and progression |
| `veyl_civilianjobs` | Add one modular activity at a time: recycling, fishing, trucking or taxi work | Hunting, mining, sanitation and cooperative contracts |
| `veyl_emotes` | Searchable emote menu, favorites, cancel controls and local roleplay text actions | Paired emotes, props and job-specific interactions |

### Criminal gameplay

| Resource | First version | Later expansion |
| --- | --- | --- |
| `veyl_robberies` | One store-robbery loop with requirements, attempt state, cooldown, dispatch and reward validation | Houses, warehouses, banks and larger team heists |
| `veyl_drugs` | One fictional in-game production and sale loop with supply limits | More products, quality, buyers and territory effects |
| `veyl_boosting` | Vehicle contracts, search area, controlled vehicle spawn, recovery and delivery checks | Hacking, VIN scratching, transfers, history and leaderboard |
| `veyl_blackmarket` | Limited stock, restricted catalog, server-side purchases and contact locations | Reputation access and rotating stock |
| `veyl_gangs` | Groups, ranks, member permissions and a shared stash | Territory, reputation and controlled rival activities |

Robberies and boosting should create calls through `veyl_dispatch`, pay through `veyl_banking`, and use the shared vehicle/inventory services.

### Optional expansion

| Resource | First version | Later expansion |
| --- | --- | --- |
| `veyl_phone` | Contacts, messages, calls through a voice integration, and basic service requests | Banking, business, classifieds, gallery and job apps |
| `veyl_skills` | Server-awarded experience with activity-specific limits | Specializations and unlocks |
| `veyl_lottery` | In-game tickets with stored outcomes and one-time redemption | Scratchers, draws and shop integration |
| `veyl_racing` | Checkpoint routes, race sessions, results and server-validated entries | Ghosts, classes, seasons and leaderboards |

An optional `veyl_bridge` can expose a documented subset of another framework's APIs. It is a compatibility project, not a promise that all third-party scripts will work.

## 4. Build order and completion gates

These are milestones, not calendar estimates. Finish and demonstrate each gate before expanding its scope.

| Milestone | Work | Completion gate |
| --- | --- | --- |
| 0 — Foundation | Select runtime/dependency versions; build minimal core, UI, world and admin tools | Clean boot; database migrations run once; missing dependencies produce a clear error; unauthorized admin actions are rejected |
| 1 — Persistent character | Characters, appearance, spawn, needs and HUD | Two players can create separate characters, switch/reconnect, and restore the correct data without cross-character leaks |
| 2 — First complete activity | Banking, inventory integration, jobs, interaction, shops, vehicle service and delivery | A player completes the full delivery-to-purchase loop; duplicate completion requests never produce a second payout |
| 3 — Closed city alpha | Garages, dealership, city hall, emotes and basic medical recovery; add a tested voice provider | Vehicle purchases survive reconnects; simultaneous retrieval cannot spawn two copies; death/rejoin and voice recovery work |
| 4 — Service roleplay | Doorlocks, dispatch, police, EMS expansion, prison, basic MDT and mechanic | Two players can run an arrest, medical response or impound from start to finish with correct duty permissions and records |
| 5 — Public beta | Limited business/housing content, one extra civilian job and one robbery | A realistic player session passes persistence, economy, staff-support and restart checks; restore procedure is demonstrated |
| 6 — Expansion | Crafting, more civilian work, boosting, drugs, gangs, phone and optional systems | Each new activity uses the existing services and passes its own abuse, interruption and persistence checks |

Keep the initial city small: one delivery depot, one general shop, a bank/ATM, a starter dealership, one garage and one hospital location. Add locations through configuration once the loop works.

### First development backlog

1. Record the supported game edition, artifact/build, database version, external resource releases and pinned commits.
2. Define account ID, character ID and transient session ID separately.
3. Create migrations and a clean install path.
4. Implement player loading/unloading and session ownership.
5. Add bounded request handling, error codes and audit records.
6. Add basic admin diagnostics and server-side permission enforcement.
7. Build character creation and appearance persistence.
8. Add spawn readiness, timeouts, camera/focus cleanup and a fallback location.
9. Implement the cash/bank ledger and repeat-safe money operations.
10. Implement and test the chosen inventory bridge and readiness contract.
11. Add interactions, jobs, one shop and the vehicle service.
12. Build the delivery loop and run the acceptance scenarios below.

## 5. External resources and integration plan

| System | Proposed approach | Required integration work |
| --- | --- | --- |
| SQL | Use a pinned, tested oxmysql release behind the framework's database layer | Connection handling, migrations, transaction errors and outage behavior |
| Inventory | Keep ox_inventory as the slot/item authority; expose VeylCore-facing calls through `veyl_inventory` | Custom framework bridge, stable character mapping, groups, vehicles, item-use callbacks and reconnect cleanup |
| Common library | Use ox_lib where required by dependencies; keep VeylCore's API and styling explicit | Decide which component owns callbacks, dialogs and progress UI so two systems do not fight for focus |
| Targeting | Choose your custom interaction implementation or ox_target as the provider | Register/remove interactions through one adapter and clean up on resource stop |
| Appearance / voice | Evaluate a compatible provider for the selected runtime | Character load/save and radio/call/duty hooks; test the actual chosen releases |
| QBox / QBCore / ESX scripts | Port individually or implement a narrow tested bridge | Map exports, events, identifiers, groups, money, inventory, vehicle state and expected lifecycle behavior |

The current ox_inventory documentation describes custom-framework integration work; VeylCore is not one of its listed native frameworks. Its repository also does not guarantee third-party resource compatibility. [S5–S6]

Use the upstream Overextended repositories as the reference for current candidate releases. The CommunityOx organization is marked archived; older fork instructions should not be assumed current. Pin and test dependencies rather than tracking moving branches on a live server. [S7–S8]

### Startup dependency direction

1. External SQL/library dependencies.
2. Core and shared UI/world services.
3. Banking and job/group services needed by the inventory bridge.
4. Chosen inventory provider with its VeylCore integration.
5. VeylCore inventory facade and other base services.
6. Character UI/spawn, HUD and interactions after their prerequisites are ready.
7. Activity resources.

Keep the core independent of the inventory facade to avoid a startup cycle. Character loading must wait for required services without blocking forever. Declare hard dependencies in resource manifests; use capability checks for optional features. Cfx resource manifests support dependency declarations. [S4]

## 6. Data and API plan

### Data ownership

| Record | Purpose |
| --- | --- |
| Accounts | Stable account identity and allowed character slots |
| Characters | Identity, account relationship, selected appearance reference and saved state |
| Sessions | Runtime player source mapped to the active character; never treat source as a permanent ID |
| Job assignments | Job, grade, duty and membership |
| Accounts / ledger / operation IDs | Cash, bank and company balances, auditable movements, duplicate-request protection |
| Provider inventory tables | Canonical items and metadata, with VeylCore identifiers mapped consistently |
| Vehicles / key grants | Stable vehicle ID, ownership, keys, saved condition and garage/impound state |
| Activity runs | Mission owner, permitted steps, assigned entities, rewards and terminal status |
| Audit records | Important money, item, permission and staff actions |

Use integer currency units, parameterized queries, unique operation identifiers and constraints that match the chosen database design. Save critical transactions before acknowledging success; routine status/location updates can use scheduled persistence.

### Proposed interfaces

These names are design proposals, not existing exports to paste into another script.

| Resource | Proposed server interface | Meaning |
| --- | --- | --- |
| `veyl_core` | `GetPlayer(source)` | Obtain the current authenticated session/character context |
| `veyl_core` | `HasPermission(source, permission)` | Check an action-specific permission |
| `veyl_banking` | `TryDebit(characterId, account, amount, reason, operationId)` | Attempt a validated, repeat-safe debit |
| `veyl_banking` | `Transfer(fromAccount, toAccount, amount, reason, operationId)` | Transfer through the single ledger service |
| `veyl_inventory` | `CanCarry(characterId, item, count, metadata)` | Ask the selected inventory provider about capacity |
| `veyl_inventory` | `GiveItem(characterId, item, count, metadata, operationId)` | Perform an audited grant with retry behavior defined by the adapter |
| `veyl_jobs` | `SetDuty(source, enabled)` | Apply duty state after validating eligibility |
| `veyl_vehicles` | `SpawnAuthorizedVehicle(request)` | Reserve and spawn an owned or assigned vehicle |
| `veyl_dispatch` | `CreateCall(call)` | Create a server-approved call for permitted recipients |

Expose internal mutation methods as server-side interfaces. Clients submit bounded requests such as “buy catalog item 12”; they do not choose prices, balances, rewards or ownership.

Define one response shape, for example `{ ok, code, message, data }`, with documented errors such as `NOT_READY`, `NO_PERMISSION`, `INSUFFICIENT_FUNDS` and `INVENTORY_FULL`.

### Money and inventory consistency

Transfers within the banking database should use a transaction. A banking change plus an external inventory call is not automatically one transaction.

For purchases, crafting, payouts with items, and shared stashes, define the complete operation:

1. Validate the request and reserve the operation.
2. Verify capacity, funds, stock and ownership.
3. Commit through the relevant services with a durable operation record.
4. Resolve interrupted work through retry-safe delivery or compensation.
5. Reconcile incomplete operations after a restart.

The adapter must establish what happened before repeating an item grant. Never assume a unique banking operation ID also makes an inventory export repeat-safe.

## 7. Delivery job specification

Use `veyl_delivery` as the first real activity because it exercises most of the framework.

| Step | Player experience | Server responsibility |
| --- | --- | --- |
| Start | Speak to the depot NPC and choose a shift | Confirm eligibility and no conflicting active run |
| Vehicle | Receive a delivery van and temporary key | Record the vehicle/run relationship and permitted spawn |
| Collect | Pick up packages at the depot | Record the actual assigned packages and route |
| Deliver | Carry a package to the assigned address | Check run, current stop, proximity and package ownership |
| Complete | See the route summary | Record completion and pay the configured amount once |
| Return | Return the van or end the shift | Revoke temporary keys, release reservations and clean up entities |

Store the route and reward rules on the server. A client minigame or progress-bar result is only one signal and must not be the sole reward authority.

Define cancellation, vehicle destruction, disconnect, reconnect and resource-stop behavior. A canceled route must not become payable again because the player reconnects.

## 8. UI and reliability requirements

Use violet as an accent across the character screen, HUD settings, shops, banking and admin tools. Keep the mascot in onboarding/loading/help areas and let gameplay screens prioritize readable information.

Every interface needs:

- A clear close action and consistent Escape behavior.
- Focus and camera cleanup on close, resource stop and failed initialization.
- Loading, success, empty and error states.
- Protection against repeated clicks while a request is pending.
- Layout checks at 16:9, 16:10 and ultrawide resolutions.
- Rebindable controls where applicable.
- Packaged assets for essential screens rather than a dependency on a remote image URL.

NUI resources have their own pages and focus behavior; treat focus ownership as a shared design problem. [S9]

To prevent the “awaiting resources” and invisible-UI problems you have encountered before, make each initialization stage observable. If player data, inventory or spawn preparation times out, show the failed stage and allow a controlled retry. Do not leave a permanent black overlay or an endless readiness loop.

## 9. Security and persistence requirements

Validate job/grade, ownership, location, inventory, money, cooldown and current activity state using server-owned data. Rate-limit exposed actions and validate identifiers, strings and counts before mutation. Cfx's event-security guidance emphasizes server-side checks and treating client-triggered events as untrusted. [S1]

Keep monetary authority and permissions outside client-writable presentation state. State bags can carry useful synchronized display information, but their default write policies are not a substitute for authorization. [S3]

Use server-controlled mission vehicles and entities where appropriate, with an explicit lifetime and cleanup owner. OneSync provides server entity creation and synchronization capabilities; persistence across a server restart still requires your database and restoration logic. [S2]

Store credentials and service secrets only on the server. Record economy adjustments and privileged actions with a reason. Security checks support abuse prevention; they do not justify promising an “unhackable” framework.

## 10. Acceptance scenarios

These are tests to implement and run during development. No runtime tests have been performed as part of this planning deliverable.

| Scenario | Required result |
| --- | --- |
| Two accounts create/select characters | Neither can load or modify the other's character |
| Rapid character switching or reconnect | Old requests cannot affect the newly selected character |
| Repeated delivery-complete requests | Exactly one valid payout |
| Two simultaneous purchases with limited funds | No negative balance or duplicate fulfillment |
| Full inventory during purchase | No lost payment; defined retry/refund outcome |
| Two people access the same stash | Correct final item totals |
| Two simultaneous garage retrievals | At most one active owned-vehicle instance |
| Disconnect during a transaction | Operation resolves consistently on reconnect/recovery |
| Database fails during payout | No success message without durable success; no later double payout |
| Resource stops while UI is open | Cursor, controls and camera recover |
| Invalid remote event or forged job grade | Request rejected without changing state |
| Death and reconnect | Medical state restores according to configured rules |
| Duty change during dispatch | New calls and private records follow current authorization |
| Restore a database backup | Server loads consistent character, money, inventory and vehicle data |

Measure performance using repeatable scenes: idle at spawn, busy shop, active delivery, multi-user stash and vehicle retrieval. Record client resource usage, server hitch/profile data, SQL latency and entity counts. Set budgets from the actual host and intended player population; no “0.00 ms” or large-player-count promise without measurements. Cfx documents profiler tools for identifying expensive code paths. [S10]

## 11. Release package expectations

Each finished resource should include:

- `fxmanifest.lua`, explicit dependencies and supported versions.
- Separate client/server code, shared definitions, configuration and translations.
- Database migrations when it owns persistent data.
- A README with installation, configuration, exports/events and known limitations.
- Cleanup behavior for its UI, interactions, temporary entities and active tasks.
- A short acceptance checklist and evidence from the supported test environment.

Ship compiled interface assets when the resource requires a build step. Prepare a tested `server.cfg` example and installation recipe only after the full startup order works from a clean environment.

Keep development and live-server configuration separate. Back up before migrations and rehearse recovery. A public release should state exactly which runtime, dependencies and integrations were tested.

## 12. Copy-ready developer brief

> Build the next VeylCore milestone from this plan using the `veyl_` resource prefix. Implement one complete feature at a time against documented service interfaces. Begin with the core/player lifecycle and the delivery-to-shop test loop. Keep all money, inventory, permissions and mission rewards validated on the server. Reuse a single authoritative provider for each subsystem. Do not invent third-party exports or claim compatibility without inspecting and testing the chosen versions. Include migrations, configuration, cleanup, installation notes and the acceptance results for the milestone. Mark unfinished features clearly rather than wiring placeholder success paths into gameplay.

## Technical sources

Primary references checked November 16, 2026. The architecture, scope and milestone choices above are proposed VeylCore design decisions.

- **S1:** [Cfx — Secure Your Events](https://docs.fivem.net/docs/developers/server-security/)
- **S2:** [Cfx — OneSync](https://docs.fivem.net/docs/scripting-reference/onesync/)
- **S3:** [Cfx — State Bags](https://docs.fivem.net/docs/scripting-manual/networking/state-bags/)
- **S4:** [Cfx — Resource Manifest](https://docs.fivem.net/docs/scripting-reference/resource-manifest/)
- **S5:** [Overextended — ox_inventory](https://github.com/overextended/ox_inventory)
- **S6:** [Overextended — Inventory installation and custom-framework documentation](https://github.com/overextended/overextended.github.io/blob/main/content/docs/ox_inventory/index.mdx)
- **S7:** [Overextended — oxmysql releases](https://github.com/overextended/oxmysql/releases)
- **S8:** [CommunityOx — Organization archive status](https://github.com/CommunityOx/)
- **S9:** [Cfx — Fullscreen NUI](https://docs.fivem.net/docs/scripting-manual/nui-development/full-screen-nui/)
- **S10:** [Cfx — Using the Profiler](https://docs.fivem.net/docs/scripting-manual/debugging/using-profiler/)

