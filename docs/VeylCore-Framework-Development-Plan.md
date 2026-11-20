# VeylCore — FiveM Framework & Script Development Plan

**Planning version:** 2.0 — QBCore / QBox direction  
**Originally prepared:** November 16, 2026  
**Revised:** November 20, 2026  
**Project:** VeylCore, a custom FiveM roleplay framework  
**Resource prefix:** `veyl_`  
**Main resource:** `veyl_core`

Build VeylCore with QBCore's familiar player structure and scripting conventions, combined with QBox's export-based approach, modular resources, and ox integrations. Keep VeylCore's name, violet branding, and custom gameplay ecosystem.

This document specifies planned development. VeylCore exports, compatibility features, configurations, and resources below are proposals to implement and test; they are not existing downloadable framework functionality.

## 1. Project direction

VeylCore should feel familiar to someone who already develops QBCore or QBox scripts. A developer should be able to find a player's `citizenid`, read `PlayerData.job`, add money through the core, configure jobs in a shared file, and build a separate gameplay resource without learning a completely different framework model.

QBCore supports a core object and direct exports. QBox emphasizes direct exports and imported modules; its QBCore bridge supplies the legacy core object. VeylCore will adopt both access styles over one implementation. QBox itself does not expose `exports.qbx_core:GetCoreObject()`. [S1, S3]

### Design choices

| Area | VeylCore decision |
| --- | --- |
| Foundation | One custom `veyl_core` resource owns players, characters, personal money, metadata, jobs, gangs, and lifecycle |
| Familiar development | Offer `GetCoreObject()`, `Functions`, `Shared`, and player methods for developers accustomed to QBCore |
| Native development | Prefer direct `veyl_core` exports, small modules, and `ox_lib` callbacks in new VeylCore resources |
| Player format | Use familiar `PlayerData` fields: `citizenid`, `charinfo`, `money`, `job`, `gang`, `metadata`, and `position` |
| Multiple memberships | Support multiple jobs and gangs in the data model, with one primary job and one primary gang |
| Shared definitions | Easy-to-edit job, gang, vehicle, weapon, and location definitions; inventory remains the item-definition authority |
| Compatibility | Develop a documented QBCore bridge early; port selected native QBox integrations against explicit contracts |
| Dependencies | Begin with `oxmysql`, `ox_lib`, `ox_inventory`, and `ox_target`, using pinned and tested versions |
| Resource ecosystem | Separate police, ambulance, garages, banking, shops, delivery, housing, and other gameplay resources |
| UI | VeylCore character screens, HUD, branding, and shared styling, with one chosen utility UI provider |
| Installation | Clean database migrations, a documented start order, a starter resource pack, and a tested installation recipe |

The working scope remains an independent VeylCore implementation with familiar interfaces. This plan does not silently turn the project into a renamed upstream fork. If upstream code is incorporated, record its origin and retain its applicable license and notices.

### First playable target

1. Connect and choose or create a character.
2. Customize appearance and spawn without a stuck loading screen.
3. Start a package-delivery shift and receive an assigned van.
4. Finish a route and receive a server-calculated payment through `veyl_core`.
5. Buy and use food through the selected inventory integration.
6. Reconnect with the correct identity, money, inventory, job, and saved status.
7. Run a small QBCore-style example resource through the compatibility bridge.

Keep the first city small: one delivery depot, one shop, a bank/ATM, a starter dealership, one garage, and one hospital. Expand after persistence and compatibility gates pass.

## 2. Core architecture and resource boundaries

### What belongs in `veyl_core`

The core owns account identification, character records, login/logout, player objects, personal balances, metadata, job/gang definitions and membership, permissions, saving, and framework events. It also exposes documented commands, hooks, usable-item registration adapters, and a client player-data cache.

Character selection screens and gameplay menus remain replaceable resources. They ask the core to load or change data; they do not create a second player system.

| Component | Owns | Integration rule |
| --- | --- | --- |
| `veyl_core` | Account/character identity, live players, personal cash/bank balances, metadata, job/gang memberships, permissions, lifecycle, and core migrations | One authority for all framework player state |
| `veyl_characters` | Character selection and creation UI | Core validates slots, character ownership, creation, deletion, and login |
| `veyl_spawn` / `veyl_appearance` | Spawn selection, world placement, appearance editing and restoration | Coordinate with the core's loading session and explicit readiness stages |
| `veyl_banking` | Banking UI, ATMs, business accounts, invoices, and business transaction history | Personal cash/bank mutations always go through the core money service |
| `veyl_jobs` / `veyl_management` | Job selection, duty UI, boss menus, hiring, firing, and grade changes | Core owns definitions, memberships, active job, and paycheck eligibility |
| `veyl_gangs` | Gang menus, stash access workflows, territory, and gang activities | Core owns memberships, grades, and primary gang |
| `veyl_inventory` + `ox_inventory` | VeylCore item adapter, usable-item integration, inventory access rules; ox owns item slots and metadata | Do not persist a competing `PlayerData.items` inventory |
| `veyl_vehicles` | Stable vehicle IDs, ownership, saved properties, controlled spawning, and storage state | Garages, keys, dealerships, and jobs use this service |
| `veyl_vehiclekeys` / `veyl_fuel` | Key grants/lock interactions and fuel behavior respectively | Separate, replaceable integrations; no duplicate vehicle ownership records |
| `veyl_medical` | Injury, incapacitation, treatment, and respawn rules | Core stores agreed medical metadata; one medical system decides transitions |
| Activity resources | Routes, mission state, rewards, and activity-specific records | Use framework APIs; never update another resource's private tables |

Removing `veyl_banking` must not remove a player's personal cash/bank balance or break core money exports. Removing a boss menu must not remove job membership. Removing a gameplay resource must not stop the core from starting.

### Proposed core layout

Paths below are relative to `veyl_core/` and describe implementation responsibilities.

| Path | Responsibility |
| --- | --- |
| `fxmanifest.lua` | Resource metadata, ordered scripts, and hard dependencies |
| `config/shared.lua` | Public defaults safe to expose to clients |
| `config/server.lua` | Server-only character rules, economy limits, permissions, and save settings |
| `config/client.lua` | Client behavior, display defaults, and controls |
| `shared/jobs.lua` / `shared/gangs.lua` | Group definitions and grades |
| `shared/vehicles.lua` / `shared/weapons.lua` / `shared/locations.lua` | Shared catalogs; no inventory quantities |
| `server/players.lua` / `server/characters.lua` | Player sessions, character ownership, load, logout, and save |
| `server/money.lua` / `server/groups.lua` / `server/metadata.lua` | Validated mutations and persistence |
| `server/permissions.lua` / `server/commands.lua` | ACE-backed permissions and command checks |
| `server/exports.lua` / `client/exports.lua` | Public native interfaces |
| `client/playerdata.lua` / `client/events.lua` | Local player cache and lifecycle notifications |
| `modules/playerdata.lua` / `modules/lib.lua` | Optional imports for client data and small shared helpers |
| `bridge/qb/` | QBCore object, player-method, callback, and event translation |
| `locales/` | Translatable messages and errors |
| `migrations/` | Versioned core schema updates |

Load configuration before code that reads it. Use explicit ordering for dependent scripts instead of relying on wildcard order. Server-only configuration, identifiers, credentials, and permission data must not be placed in shared scripts.

## 3. Player data, APIs, and shared configuration

### Player data contract

The field names intentionally follow the QB ecosystem. QBox also distinguishes a primary job/gang from maps of all memberships. The exact VeylCore defaults and extensions below are design decisions. [S2, S4]

| Field | Proposed VeylCore meaning |
| --- | --- |
| `source` | Temporary server player ID while online; never a database identity |
| `citizenid` | Unique, stable character ID, preserved during supported imports |
| `cid` | Character slot within an account; not globally unique |
| `license` | Server-side platform/account identifier used during ownership checks |
| `charinfo` | First/last name, birthdate, gender, nationality, phone, and account reference; any `charinfo.cid` alias derives from the same slot |
| `money` | Numeric personal `cash` and `bank`; optional configured `crypto` later |
| `job` | Primary job with name, label, type, grade, duty, pay, and boss status |
| `jobs` | Map of job name to numeric grade for all memberships |
| `gang` | Primary gang with name, label, grade, and boss status |
| `gangs` | Map of gang name to numeric grade for all memberships |
| `metadata` | Validated persistent status, licenses, callsign, medical flags, and approved activity metadata |
| `position` | Last valid position and heading, with a defined JSON serialization |
| `items` | Optional bridge-generated inventory view only; ox_inventory remains authoritative |

Use `unemployed` and `none` as default primary groups. Represent `job.grade` and `gang.grade` as tables containing at least `name` and numeric `level`. Derive labels, wages, and boss flags from server definitions rather than accepting them from clients. Exclude default groups from membership maps.

Standard metadata should include `hunger`, `thirst`, `stress`, `health`, `armor`, `isdead`, `inlaststand`, `ishandcuffed`, and `licences`. Each key needs a type, default, allowed range, and authorized writer. New optional data should have safe defaults for older characters.

Keep the full player record server-side. Send an allowlisted view only to the owning client; expose only necessary public fields to other players. Clients never authorize actions from their copy of `PlayerData`.

### Two access styles, one backend

These examples show proposed VeylCore interfaces. They become usable only after implementation.

Preferred direct export style for new scripts:

```lua
-- Server: read the authenticated player's primary job.
local player = exports.veyl_core:GetPlayer(source)
if not player then return end

local citizenid = player.PlayerData.citizenid
local jobName = player.PlayerData.job.name
```

Familiar core-object style:

```lua
-- Server: a facade over the same VeylCore player service.
local VeylCore = exports.veyl_core:GetCoreObject({ 'Functions' })
local player = VeylCore.Functions.GetPlayer(source)
if not player then return end

local citizenid = player.PlayerData.citizenid
local jobName = player.PlayerData.job.name
```

`GetCoreObject()` should support a filtered selection and expose documented `Functions`, `Shared`, and `Commands` sections. Wrappers must call the same native services, with no separate player registry, balance cache, or save thread.

### Initial API surface

The signatures in this table are VeylCore proposals. Record exact types, return values, side, errors, and availability in the implementation docs.

| Capability | Native VeylCore API | Familiar facade |
| --- | --- | --- |
| Find online player | `GetPlayer(source)`, `GetPlayerByCitizenId(citizenid)` | `VeylCore.Functions.GetPlayer(...)` and matching lookup |
| Read local player | Client `GetPlayerData()`; optional `Veyl.PlayerData` module | Client `VeylCore.Functions.GetPlayerData()` |
| Money | Server `GetMoney(source, type)`, `AddMoney(source, type, amount, reason)`, `RemoveMoney(...)`, `SetMoney(...)` | `Player.Functions.GetMoney(type)`, `AddMoney(type, amount, reason)`, and matching methods |
| Metadata | Server `GetMetadata(source, key)`, `SetMetadata(source, key, value)` | `Player.Functions.GetMetaData(key)` / `SetMetaData(key, value)` |
| Primary job/duty | Server `SetJob(source, name, grade)`, `SetJobDuty(source, enabled)` | `Player.Functions.SetJob(name, grade)` / `SetJobDuty(enabled)` |
| Primary gang | Server `SetGang(source, name, grade)` | `Player.Functions.SetGang(name, grade)` |
| Multiple jobs | Server `AddPlayerToJob(citizenid, name, grade)`, `RemovePlayerFromJob(citizenid, name)`, `SetPlayerPrimaryJob(citizenid, name)` | Explicit additions; do not hide them behind ambiguous `SetJob` behavior |
| Multiple gangs | Server `AddPlayerToGang(...)`, `RemovePlayerFromGang(...)`, `SetPlayerPrimaryGang(...)` | Same membership-versus-selection distinction |
| Group checks | Server `HasGroup(source, filter)`, `HasPrimaryGroup(source, filter)` | Documented wrappers with separate duty requirements |
| Shared catalogs | `GetJobs()`, `GetGangs()`, `GetVehicles()`, `GetWeapons()` | `VeylCore.Shared.Jobs`, `.Gangs`, `.Vehicles`, `.Weapons` |
| Items | `veyl_inventory` operations and item-definition lookup | Supported item wrappers delegate to the inventory adapter |
| Notifications | Side-specific `Notify(...)` routed through the UI provider | `VeylCore.Functions.Notify(...)` |
| Commands/permissions | Server `HasPermission(source, action)` and ACE-backed registration | Supported `Commands.Add` / permission wrappers |
| Callbacks | `lib.callback.register` / `lib.callback.await` for native resources | A tested translation for supported QB callback signatures |

Player lookups return an object or `nil`. Money mutations and familiar player setters return success booleans; native calls may also return a documented error code. Keep the legacy return contract when translating. Use `{ ok, code, message, data }` for VeylCore UI/action responses, not as a replacement for a QB function's boolean return.

Define `SetJob` as replacement of the old primary membership with the requested job/grade, while preserving unrelated memberships. `SetPlayerPrimaryJob` selects an existing membership without removing other jobs. Apply the equivalent distinction to gangs. QBox separates these operations, and its `SetJob` removes the previous primary job. [S5]

Generic money exports are server-only. Delivery and other reward systems must additionally use an operation-aware core method such as proposed `CreditOnce(citizenid, type, amount, reason, operationId)`. A legacy `AddMoney` call without an operation identity cannot by itself prevent a script from paying twice.

### Shared definitions

QBCore's shared configuration approach makes jobs and catalogs easy for server owners to edit. VeylCore should retain that convenience while exposing exports for resource integration. [S6]

Proposed `shared/jobs.lua` example:

```lua
return {
    unemployed = {
        label = 'Civilian',
        defaultDuty = true,
        offDutyPay = false,
        grades = {
            ['0'] = { name = 'Resident', payment = 0 }
        }
    },
    police = {
        label = 'Police Department',
        type = 'leo',
        defaultDuty = false,
        offDutyPay = false,
        grades = {
            ['0'] = { name = 'Cadet', payment = 100 },
            ['1'] = { name = 'Officer', payment = 150 },
            ['2'] = { name = 'Sergeant', payment = 200 },
            ['3'] = { name = 'Chief', payment = 250, isboss = true }
        }
    }
}
```

Payments are example configuration values. Payroll timing, eligibility, and limits belong in server configuration. Only the selected primary job pays a normal paycheck by default; having several memberships must not silently multiply income.

Load and validate definitions at startup. Grades use string keys in configuration and numeric levels in player data, with explicit conversion. Runtime registry changes must be documented as temporary unless saved through an approved configuration workflow.

`Shared.Items` should be a compatibility view derived from the inventory provider. Avoid maintaining an unrelated second item catalog that drifts from ox_inventory. Map legacy item fields only where behavior can be preserved.

## 4. QBCore and QBox compatibility

Compatibility is a planned product feature with a published support matrix. It requires correct arguments, returns, events, load timing, and dependency behavior—not just similar function names. QBox's own compatibility guidance identifies direct database access, internal-file imports, and separate inventory/UI dependencies as common exceptions. [S7]

### QBCore bridge: first compatibility target

Provide a small optional resource named `qb-core` that depends on `veyl_core` and exposes the supported QBCore entry points. Its `GetCoreObject()` returns a QB-shaped facade backed entirely by VeylCore. The shim is the only resource occupying the `qb-core` name; do not start upstream qb-core beside it.

Cfx also provides a manifest `provide` replacement mechanism. Use one tested packaging strategy; an alias declaration alone does not implement APIs or supply imported files. The initial plan uses an explicit shim so its supported exports and files are visible. [S8]

| Bridge area | Initial implementation target |
| --- | --- |
| Object entry point | `exports['qb-core']:GetCoreObject()` and supported filtered selections |
| Players | Lookup, common `PlayerData` reads, and supported `Player.Functions` mutations |
| Economy | Personal money reads/writes routed to the core, with matching legacy returns |
| Jobs and gangs | Primary group, grades, duty, and definition views |
| Metadata | Supported keys and legacy `GetMetaData` / `SetMetaData` casing |
| Shared tables | Jobs, gangs, vehicles, weapons, and an explicit inventory item view |
| Callbacks | Supported client/server QB callbacks with unique request IDs, timeouts, cleanup, and validation |
| Notifications | Type, duration, and argument conversion to the selected VeylCore UI provider |
| Usable items | Supported `CreateUseableItem` registration routed into one inventory use pipeline |
| Commands | Supported command registration and permission mapping |
| Events | Tested QB lifecycle, player-data, job, gang, duty, and money notifications |

### Event contracts

Define VeylCore lifecycle events first, then emit compatibility notifications at the matching phase. Initial names below are proposed; the compatibility names refer to QB ecosystem APIs. QBox documents distinct local/server and networked/client events, including a client loaded notification after spawning. [S9, S10]

| VeylCore notification | Compatibility target | Timing rule |
| --- | --- | --- |
| `VeylCore:Client:OnPlayerLoaded` | `QBCore:Client:OnPlayerLoaded` | Owning client has its data and the initial spawn has completed |
| `VeylCore:Client:OnPlayerUnload` | Supported QB unload contract | Clear the old character cache and cancel outstanding character requests |
| `VeylCore:Player:SetPlayerData` | `QBCore:Player:SetPlayerData` | Send an allowlisted current view to the owning client |
| `VeylCore:Client:OnJobUpdate` | `QBCore:Client:OnJobUpdate` | After the server commits the active job/grade change |
| `VeylCore:Client:OnGangUpdate` | `QBCore:Client:OnGangUpdate` | After the server commits the active gang/grade change |
| `VeylCore:Client:SetDuty` | `QBCore:Client:SetDuty` | After an authorized duty transition |
| `VeylCore:Client:OnMoneyChange` | `QBCore:Client:OnMoneyChange` | After a successful mutation; match the pinned target's payload |

Server notifications must be local server events with documented payloads, not unrestricted network commands. Client acknowledgments may advance a validated loading session but must not choose the character, money, or permission state.

Emit one notification per namespace for each transition. Native resources subscribe to the native namespace; legacy resources use the bridge namespace. Do not forward both directions or trigger load events repeatedly after resource restarts. Resources starting late read the current cache through an export/module.

### Native QBox scripts

Make porting native QBox resources straightforward by keeping familiar player data, group operations, direct exports, and small modules. This does not make VeylCore an automatic drop-in implementation of `qbx_core`.

| Script dependency | Planned treatment |
| --- | --- |
| Documented QBCore object APIs | Run through the tested QB bridge subset |
| `exports.qbx_core:*` | Add a VeylCore adapter or change calls against an exact supported API map |
| `@qbx_core/modules/*.lua` | Replace imports with implemented VeylCore equivalents; a resource rename is insufficient |
| `QBX.PlayerData` | Migrate to the proposed `Veyl.PlayerData` cache or an explicitly tested wrapper |
| `qb-inventory`, `qb-target`, `qb-menu`, `qb-input` | Port each dependency or implement a separate, limited adapter |
| Direct SQL against core tables | Migrate to APIs or document a version-specific conversion; do not promise schema equivalence |
| Protected scripts with fixed resource detection | Test the actual resource and ask its developer for support when required |
| ESX-only resources | Separate future integration work; outside the initial compatibility milestone |

Publish a matrix with resource name/version, required APIs, dependency adapters, test results, and known limitations. Until tested, list integrations as planned. Never advertise universal QBCore/QBox compatibility.

## 5. Dependencies and integration plan

| System | Starting choice | Required VeylCore work |
| --- | --- | --- |
| Database | MariaDB with a pinned `oxmysql` release | Parameterized queries, migrations, transactions, and outage handling |
| Common utilities | `ox_lib` | Native callbacks, cache/zone utilities, menus, input, progress, and notifications where selected |
| Inventory | `ox_inventory` | A real VeylCore framework bridge for identity, groups, licenses, lifecycle, vehicles, and item use |
| Interaction | `ox_target` behind `veyl_interact` | Register/remove options, map group checks, and provide configured E-key alternatives |
| Appearance | One pinned appearance provider behind `veyl_appearance` | Character ownership checks, save/load mapping, outfits, and lifecycle integration |
| Voice | One tested voice provider, with `pma-voice` as the initial candidate | Voice/radio/call state adapters and recovery after reconnect |
| Vehicle keys / fuel | Separate VeylCore resources with documented adapter points | Exactly one active keys provider and one active fuel provider |
| Utility UI | `ox_lib` initially, with VeylCore styling where supported | `veyl_ui` owns routing/focus coordination; avoid two progress bars or notification systems |
| Custom screens | NUI with HTML, CSS, and TypeScript | Character selection, HUD settings, banking, admin, and other branded interfaces |

The published ox_inventory framework options do not include VeylCore. Adding a `veyl` configuration value or selecting `qbx` does not supply a bridge. Implement the missing integration against a pinned release and test it before advertising inventory support. [S11, S12]

### Inventory and cash rules

Keep numeric cash/bank as the chosen personal economy model. Do not also maintain spendable money items. The VeylCore inventory integration must route purchases and deposits through the core money service, or disable incompatible provider purchase flows and use `veyl_shops` to coordinate payment and item delivery.

Implement and test:

- Stable `citizenid` mapping for inventory ownership and reconnects.
- Job/gang grade mapping, primary-group and duty requirements where applicable.
- Character unload and item-use cleanup without leaking state to the next character.
- Usable-item callbacks without double consumption or double effects.
- Metadata-aware capacity, add/remove, stash, shop, and vehicle-storage operations.
- A defined bridge view for any supported legacy `PlayerData.items` reads.
- No automatic synchronization loop that alternately overwrites core money and inventory money.

The inventory provider owns item definitions, slots, quantities, durability, and weapon metadata. `veyl_inventory` is an adapter, not a second inventory engine.

### Startup order and readiness

| Stage | Resources / responsibility |
| --- | --- |
| 1 | `oxmysql`, then `ox_lib`; configuration available before dependent scripts |
| 2 | `veyl_core` starts its services and migrations; optional `qb-core` shim starts after it |
| 3 | `ox_target`, then `ox_inventory` with its implemented VeylCore integration |
| 4 | `veyl_inventory`, `veyl_ui`, `veyl_interact`, world, and base vehicle services |
| 5 | Appearance, spawn, character UI, HUD, needs, and medical dependencies |
| 6 | Banking, jobs/management, shops, delivery, and other activity resources |

The provider-side inventory bridge may depend on `veyl_core`, but must not require a facade that itself waits on ox_inventory. Keep `veyl_core` independent of `veyl_inventory` at startup. Queue provider-specific registrations or return `NOT_READY` until the provider is ready.

Publish separate states for database ready, core services ready, character authenticated, inventory loaded, appearance loaded, and spawn complete. Only permit gameplay after required stages succeed. Every wait has a timeout, cleanup, and a useful error. A hard dependency belongs in the manifest; optional systems use availability checks. [S8, S12]

Pin exact dependency releases/commits, FXServer artifact, game edition/build, database version, and integration patches in the release manifest. Never assume an upstream update preserves an untested bridge.

## 6. Resource catalog

Build each resource around a small complete feature set. Expansion columns are backlog, not launch requirements. Native resources use direct VeylCore exports; the compatibility bridge remains available for supported legacy scripts.

### Foundation

| Resource | First version | Later expansion |
| --- | --- | --- |
| `veyl_core` | Player lifecycle, character data, personal money, metadata, jobs/gangs, permissions, migrations, exports, and core-object facade | Diagnostics, controlled hooks, connection queue, and capability discovery |
| Optional `qb-core` shim | Supported QBCore exports/object/events backed by `veyl_core` | Additional APIs driven by the compatibility test matrix |
| `veyl_ui` | Shared visual rules, notifications/progress/menu routing, focus cleanup, and common NUI components | Themes, accessible scaling, and tablet components |
| `veyl_interact` | Entity, ped, and zone interaction through ox_target; configured E-key fallback | Custom interaction provider and developer tools |
| `veyl_admin` | Player list, reports, teleport tools, ACE checks, and action logs | Spectate, staff notes, economy diagnostics, and character recovery |
| `veyl_world` | Shared clock/weather, configurable population, and cleanup | Night-only aurora, scheduled events, and seasonal presets |

### Player systems

| Resource | First version | Later expansion |
| --- | --- | --- |
| `veyl_characters` | Character selection/creation UI calling core-owned lifecycle APIs | Slot presentation, previews, and recovery workflow |
| `veyl_appearance` | Appearance editing, clothing save/load, and provider adapter | Barber/tattoo shops, outfits, and job clothing |
| `veyl_spawn` | Initial spawn, approved locations, last-position recovery, and loading cleanup | Housing spawns and scene-specific return points |
| `veyl_inventory` | Framework/provider adapter, item operations, stash access, and usable-item integration | Containers, crafting adapters, and additional metadata workflows |
| `veyl_hud` | Health, armor, hunger, thirst, stress, stamina, oxygen, speed, fuel, and voice state | Seatbelt display and layout settings |
| `veyl_needs` | Consumables and status changes using core metadata | Stress activities and configurable recovery effects |

### Economy and employment

| Resource | First version | Later expansion |
| --- | --- | --- |
| `veyl_banking` | Bank/ATM UI, personal transfers through core, transaction display | Business accounts, invoices, and business-to-player settlements |
| `veyl_jobs` | Job selection and duty UI using core membership APIs | Applications and role-specific job boards |
| `veyl_management` | Boss menu, hire/fire/promote, employee list, and server authorization | Department budgets and management dashboards |
| `veyl_shops` | Store catalogs, server-owned prices, payment/item coordination, and capacity checks | Limited stock, suppliers, and restocking |
| `veyl_cityhall` | ID replacement, licenses, and available jobs | Permits and appointments |
| `veyl_businesses` | Ownership, employee workflow, stock, and business permissions | Orders, workstations, and upgrades |
| `veyl_delivery` | Depot NPC, assigned van, randomized route, and validated payout | Team routes, reputation, fragile packages, and business deliveries |

Core owns paycheck calculation and eligibility; banking displays transactions and handles business-account workflows. Business resources use the same core group memberships and banking company accounts rather than duplicating employees or balances.

### Vehicles

| Resource | First version | Later expansion |
| --- | --- | --- |
| `veyl_vehicles` | Stable IDs, ownership, job vehicles, saved properties, and authorized spawning | Persistent world parking and insurance records |
| `veyl_vehiclekeys` | Key access, locks, temporary job keys, and sharing | Lockpicking/hotwiring integrations |
| `veyl_fuel` | One fuel provider, consumption, refueling, and saved levels | Electric charging and configurable fuel types |
| `veyl_garages` | Store/retrieve, spawn reservation, and impound | Shared/job garages and private property garages |
| `veyl_dealership` | Catalog, purchase validation, and ownership registration | Staff sales, test drives, trade-ins, and financing |
| `veyl_mechanic` | Repairs, part consumption, invoices, and duty access | Tuning, inspections, wear, and tow contracts |

### Emergency services and justice roleplay

| Resource | First version | Later expansion |
| --- | --- | --- |
| `veyl_police` | Duty, cuffs, escort/search rules, citations, impound, and evidence records | Warrants, K9, tactical equipment, and detailed evidence workflows |
| `veyl_medical` | Incapacitation, EMS calls, treatment/revive, hospital respawn, and core medical metadata | Injury types, beds, medical items, and records |
| `veyl_dispatch` | Validated calls, duty-based recipients, blips, acknowledgments, and expiry | Unit status, panic button, and dispatch-center UI |
| `veyl_mdt` | Authorized person/vehicle lookup, reports, citations, and case links | Warrants, mugshots, attachments, and department controls |
| `veyl_prison` | Server-set sentences, persisted time, and controlled release | Prison jobs, visits, and rehabilitation activities |
| `veyl_doorlocks` | Registered doors, group/key access, and synchronized locks | Business controls, temporary access, and breaches |

Use one active dispatch service and one active medical system. External MDT/dispatch integrations, including existing server resources, require explicit adapters and tested versions.

### Civilian life

| Resource | First version | Later expansion |
| --- | --- | --- |
| `veyl_housing` | Starter apartments, ownership/access, stash, and wardrobe | Furnishing, rentals, keys, and property sales |
| `veyl_crafting` | Recipes, materials, workstations, validated completion, and delivery | Work orders, group restrictions, quality, and progression |
| `veyl_civilianjobs` | One modular activity at a time: recycling, fishing, trucking, or taxi | Hunting, mining, sanitation, and cooperative contracts |
| `veyl_emotes` | Search, favorites, cancellation, and roleplay text actions | Paired emotes, props, and job interactions |

### Criminal gameplay

| Resource | First version | Later expansion |
| --- | --- | --- |
| `veyl_robberies` | One store robbery with requirements, attempt state, cooldown, dispatch, and reward validation | Houses, warehouses, banks, and team heists |
| `veyl_drugs` | One fictional production/sale loop with supply limits | Products, quality, buyers, and territory effects |
| `veyl_boosting` | Contracts, search area, controlled vehicle spawn, recovery, and delivery | Hacking, VIN scratching, transfers, history, profiles, and leaderboard |
| `veyl_blackmarket` | Restricted catalog, limited stock, validated purchases, and contact locations | Reputation access and rotating stock |
| `veyl_gangs` | Menus, group-authorized stash workflow, and activities using core memberships | Territory, reputation, and rival activities |

Robberies and boosting use `veyl_dispatch`, the core money service, and shared inventory/vehicle APIs. Keep all reward amounts and completion decisions on the server.

### Optional expansion

| Resource | First version | Later expansion |
| --- | --- | --- |
| `veyl_phone` | Contacts, messages, voice-integrated calls, and service requests | Banking, classifieds, gallery, business, and job apps |
| `veyl_skills` | Server-awarded experience with activity limits | Specializations and unlocks |
| `veyl_lottery` | In-game tickets, stored outcomes, and one-time redemption | Scratchers, draws, and shop integration |
| `veyl_racing` | Routes, sessions, results, and validated entries | Classes, seasons, ghosts, and leaderboards |

Review existing `fw_` resources before porting. Preserve their working gameplay where practical, then adapt framework, inventory, target, vehicle, and dispatch calls. A folder rename alone does not establish compatibility.

## 7. Build order and completion gates

These are milestones, not calendar estimates. Finish each gate before expanding the city.

| Milestone | Work | Completion gate |
| --- | --- | --- |
| 0 — Core foundation | Pin runtime/dependencies; schemas, definitions, player registry, permissions, native exports, and core-object facade | Clean boot; migrations run once; both API styles read the same player state; missing dependencies report clearly |
| 1 — Persistent player | Core character lifecycle, money, metadata, multijob/multigang data, character UI, appearance, spawn, HUD, and needs | Two accounts and multiple characters reconnect correctly; no cross-character state; money works without banking UI |
| 2 — Integrations and QB bridge | Inventory, target, utility UI, job/duty menus, and the defined compatibility subset | Native and QB-style sample resources read/mutate the same player; callbacks and events work once; inventory and group permissions agree |
| 3 — First complete activity | Banking UI, shop, base vehicle service, keys/fuel, and delivery | Complete delivery-to-purchase loop; duplicate route completion pays once; full inventory has a defined refund/recovery outcome |
| 4 — Closed city alpha | Garages, dealership, city hall, emotes, basic medical recovery, management, and voice | Vehicle ownership survives reconnect; no duplicate retrieval; duty changes and boss checks hold; death/rejoin and voice recover |
| 5 — Service roleplay | Doorlocks, dispatch, police, EMS expansion, prison, MDT, and mechanic | Complete arrest, medical, and impound scenarios with correct records and current authorization |
| 6 — Public beta | Limited housing/businesses, one extra civilian job, one robbery, migration tooling, and installation recipe | Full session/restart and backup-restore checks pass; tested compatibility list published; clean installation reproduced |
| 7 — Expansion | More jobs, crafting, boosting, drugs, gang activities, phone, and optional systems | Each addition uses existing services and passes interruption, persistence, permission, and reward checks |

### First development backlog

1. Record supported game edition/build, FXServer artifact, database version, and pinned dependencies.
2. Define stable account ID, `citizenid`, character slot, and transient session generation separately.
3. Implement core migrations and a repeatable clean install.
4. Build `PlayerData`, shared jobs/gangs, player registry, and server-only mutation services.
5. Implement direct exports and the core-object facade over the same backend.
6. Add ACE-backed permissions, commands, logs, and basic admin diagnostics.
7. Implement character selection authentication, logout, saving, and request invalidation.
8. Integrate appearance/spawn with timeouts and camera/focus cleanup.
9. Complete the inventory bridge and numeric-currency integration.
10. Implement the documented QB shim and representative compatibility scenarios.
11. Add job/duty menus, shop, vehicles, keys, fuel, and banking UI.
12. Build and demonstrate the delivery-to-shop loop before expanding gameplay.

## 8. Database, money consistency, and migration

### Data ownership

Table names below are proposed. A familiar name such as `players` is not a guarantee of upstream SQL compatibility.

| Store | Owner | Purpose |
| --- | --- | --- |
| `accounts` | Core | Stable account identity, character-slot rules, and account-level settings |
| `players` | Core | One character per `citizenid`, owner mapping, charinfo, personal money, metadata, and saved position |
| `player_groups` | Core | Job/gang memberships and grades; primary selection is maintained consistently |
| Core money ledger and operation records | Core | Durable personal money changes, transfers, repeat-safe credits, and audit reasons |
| Runtime sessions | Core, in memory | Current source/character mapping and session generation; never reuse source as permanent identity |
| Provider inventory storage | ox_inventory | Canonical items, slots, and metadata mapped to the character |
| Appearance storage | Appearance provider | Character-linked model, components, and outfits |
| `player_vehicles` / key grants | Vehicle and keys services | Ownership, stable vehicle ID, saved properties, storage state, and access |
| Business accounts and ledger | Banking | Company balances and business settlements; no second personal balance |
| Activity runs | Activity resource | Mission owner, state, assigned entities, reward operation, and terminal status |
| Audit records | Core and service owners | Permission changes, economy changes, item actions, and staff operations |

Shared job/gang definitions come from validated configuration. Membership rows are canonical for membership; `PlayerData.job`, `.jobs`, `.gang`, and `.gangs` are derived views maintained by the core. Do not store divergent copies in boss menus, job selectors, or business resources.

### Durable economy

Use integer currency units and reject invalid types, negative amounts, non-finite values, and amounts outside configured bounds. Perform balance checks and updates under transaction/concurrency control. Commit critical money changes before acknowledging success, then update the online view and emit notifications.

Personal transfers must debit and credit in one transaction. A business-to-personal settlement must either share a transaction through a defined persistence interface or use durable operation tracking and recovery across services. It must never become two unrelated money calls with an unhandled failure between them.

Banking UI, paychecks, shops, rewards, and admin adjustments all use the same core personal-money service. Routine location/status saves must not overwrite newer balances or group changes from stale player snapshots.

### Money plus inventory

A database money transaction and an external inventory export are not automatically atomic. Purchases, crafting, and item rewards need a complete operation:

1. Validate the request, bind it to the current character/session, and reserve a unique operation.
2. Check stock, capacity, funds, eligibility, and ownership on the server.
3. Record progress durably and perform each service mutation once.
4. Resolve interruption through an audited refund, retry-safe delivery, or explicit reconciliation.
5. Resume/reconcile incomplete operations after a restart before allowing an unsafe retry.

An operation ID on a money credit does not make `AddItem` repeat-safe. The inventory integration must establish whether delivery happened before repeating it. Do not claim exactly-once item delivery until the crash boundary has been demonstrated.

### Existing QBCore / QBox servers

Provide a version-specific, offline import workflow after the fresh-install path is stable:

- Read a backup or staging copy; record source framework and schema versions.
- Preserve unique citizen IDs and owner links; detect collisions before importing.
- Map charinfo, cash/bank, optional currencies, metadata, positions, memberships, and primary groups explicitly.
- Convert inventory items/metadata through the selected provider's supported conversion path.
- Map vehicles, properties, garage states, housing, and phone data only where an adapter exists.
- Produce a dry-run report with row counts, rejected records, balances, and unresolved mappings.
- Rehearse login, purchases, garages, and restore/rollback before any live cutover.

API compatibility and database migration are separate deliverables. Existing QB scripts may still require edits even if character data imports successfully. Core data should be accessed through exports, consistent with QBox's developer guidance. [S13]


## 9. Delivery job specification

Use `veyl_delivery` as the first real activity because it exercises most of the framework.

| Step | Player experience | Server responsibility |
| --- | --- | --- |
| Start | Speak to the depot NPC and choose a shift | Confirm eligibility and no conflicting active run |
| Vehicle | Receive a delivery van and temporary key | Record the vehicle/run relationship and permitted spawn |
| Collect | Pick up packages at the depot | Record the actual assigned packages and route |
| Deliver | Carry a package to the assigned address | Check run, current stop, proximity and package ownership |
| Complete | See the route summary | Record completion and credit through the core using the route's unique reward operation |
| Return | Return the van or end the shift | Revoke temporary keys, release reservations and clean up entities |

Use the core job/duty APIs for shift eligibility and the vehicle/key services for the assigned van. Bind the run to the character and a validated session, not only the temporary player source.

Store the route and reward rules on the server. A client minigame or progress-bar result is only one signal and must not be the sole reward authority.

Define cancellation, vehicle destruction, disconnect, reconnect and resource-stop behavior. A canceled route must not become payable again because the player reconnects.

## 10. UI and reliability requirements

Use violet as an accent across the character screen, HUD settings, shops, banking and admin tools. Keep the mascot in onboarding/loading/help areas and let gameplay screens prioritize readable information.

Every interface needs:

- A clear close action and consistent Escape behavior.
- Focus and camera cleanup on close, resource stop and failed initialization.
- Loading, success, empty and error states.
- Protection against repeated clicks while a request is pending.
- Layout checks at 16:9, 16:10 and ultrawide resolutions.
- Rebindable controls where applicable.
- Packaged assets for essential screens rather than a dependency on a remote image URL.

NUI resources have their own pages and focus behavior; treat focus ownership as a shared design problem. [S17]

To prevent the “awaiting resources” and invisible-UI problems you have encountered before, make each initialization stage observable. If player data, inventory or spawn preparation times out, show the failed stage and allow a controlled retry. Do not leave a permanent black overlay or an endless readiness loop.

## 11. Security and persistence requirements

Validate job/grade, ownership, location, inventory, money, cooldown and current activity state using server-owned data. Rate-limit exposed actions and validate identifiers, strings and counts before mutation. Cfx's event-security guidance emphasizes server-side checks and treating client-triggered events as untrusted. [S14]

Keep monetary authority and permissions outside client-writable presentation state. State bags can carry useful synchronized display information, but their default write policies are not a substitute for authorization. [S15]

Use server-controlled mission vehicles and entities where appropriate, with an explicit lifetime and cleanup owner. OneSync provides server entity creation and synchronization capabilities; persistence across a server restart still requires your database and restoration logic. [S16]

Store credentials and service secrets only on the server. Record economy adjustments and privileged actions with a reason. Security checks support abuse prevention; they do not justify promising an “unhackable” framework.

## 12. Acceptance scenarios

These are tests to implement and run during development. No runtime tests have been performed as part of this planning deliverable.

| Scenario | Required result |
| --- | --- |
| Two accounts create/select characters | Neither can load or modify the other's character |
| Rapid character switching or reconnect | Old requests cannot affect the newly selected character |
| Native and core-object API calls | Both observe the same player and committed balances |
| QB shim loads before a legacy sample | Documented object/exports and return types work without an upstream core running |
| Native and QB event subscribers | Each namespace receives one correctly timed notification; no forwarding loop |
| Callback overlaps, timeout, or disconnect | Correct response reaches its request; abandoned requests cannot mutate a new session |
| Multiple jobs/gangs and primary changes | Memberships persist; selecting a primary does not unexpectedly delete other memberships |
| Forged boss flag or off-duty access | Server derives grade/permissions and rejects unauthorized actions |
| Banking UI stopped | Core cash/bank APIs continue to work and balances persist |
| Inventory/target provider unavailable | Clear unavailable state, bounded loading, and no invalid fallback export calls |
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
| QB/QBox migration rehearsal | Character ownership, balances, memberships, items, and vehicles match the approved conversion report |

Measure performance using repeatable scenes: idle at spawn, busy shop, active delivery, multi-user stash and vehicle retrieval. Record client resource usage, server hitch/profile data, SQL latency and entity counts. Set budgets from the actual host and intended player population; no “0.00 ms” or large-player-count promise without measurements. Cfx documents profiler tools for identifying expensive code paths. [S18]

## 13. Release package expectations

Each finished resource should include:

- `fxmanifest.lua`, explicit dependencies and supported versions.
- Separate client/server code, shared definitions, configuration and translations.
- Database migrations when it owns persistent data.
- A README with installation, configuration, exports/events, exact types/returns, and known limitations.
- A compatibility matrix distinguishing native support, bridge support, adapter requirements, and untested resources.
- Examples for both VeylCore access styles and the supported QBCore shim.
- Cleanup behavior for its UI, interactions, temporary entities and active tasks.
- A short acceptance checklist and evidence from the supported test environment.

Ship compiled interface assets when the resource requires a build step. Prepare a tested `server.cfg` example and installation recipe only after the full startup order works from a clean environment.

Keep development and live-server configuration separate. Back up before migrations and rehearse recovery. A public release should state exactly which runtime, dependencies and integrations were tested.

## 14. Copy-ready developer brief

> Build VeylCore as a custom FiveM framework that feels familiar to QBCore and QBox developers. Keep the `veyl_` resource prefix, `veyl_core` main resource, and VeylCore branding. Put character lifecycle, PlayerData, personal cash/bank, metadata, permissions, job/gang definitions, and multijob/multigang membership in the core. Provide QBox-style direct exports and a QBCore-style GetCoreObject facade over the same backend. Use familiar citizenid, charinfo, money, job, gang, and metadata fields. Keep new native resources on direct exports and ox_lib callbacks.
>
> Use pinned oxmysql, ox_lib, ox_inventory, and ox_target releases, with a real VeylCore inventory bridge and one numeric personal-currency authority. Keep banking UI, boss menus, character UI, police, medical, garages, vehicle keys, fuel, and activities in separate resources. Implement the specified QBCore compatibility shim early, and document exactly which APIs, events, return values, and dependencies it supports. Treat native QBox module imports and inventory/UI replacements as explicit porting work.
>
> Begin with the persistent-character milestone, then prove both scripting styles and the supported QB bridge before building the delivery-to-shop loop. Validate all money, items, group changes, and mission rewards on the server. Prevent duplicate payouts, cross-character requests, endless startup waits, and stuck camera/NUI focus. Include migrations, configuration, cleanup, installation instructions, examples, and acceptance evidence. Implement real behavior for the current milestone and mark future features as planned. Do not invent upstream exports or claim compatibility without testing the chosen versions.

## Technical sources

Primary references checked November 20, 2026. The VeylCore architecture, resource names, new interfaces, defaults, milestones, and examples are proposed design decisions. These references describe the upstream patterns and platform behavior informing the plan; they do not establish that VeylCore has implemented them.

- **S1:** [QBCore — Core Object](https://qbcore.org/docs/qb-core/core-object)
- **S2:** [QBCore — Player Data](https://docs.qbcore.org/qbcore-documentation/qb-core/player-data)
- **S3:** [QBox — Converting Resources](https://docs.qbox.re/migrating/converting-resources)
- **S4:** [QBox — Player Types](https://docs.qbox.re/resources/qbx_core/types/player)
- **S5:** [QBox — Server Exports](https://docs.qbox.re/resources/qbx_core/exports/server)
- **S6:** [QBCore — Shared Configuration](https://qbcore.org/docs/qb-core/shared)
- **S7:** [QBox — Compatibility FAQ](https://docs.qbox.re/faq)
- **S8:** [Cfx — Resource Manifest](https://docs.fivem.net/docs/scripting-reference/resource-manifest/)
- **S9:** [QBox — Client Events](https://docs.qbox.re/resources/qbx_core/events/client)
- **S10:** [QBox — Server Events](https://docs.qbox.re/resources/qbx_core/events/server)
- **S11:** [Overextended — ox_inventory Repository](https://github.com/overextended/ox_inventory)
- **S12:** [Overextended — ox_inventory Installation](https://overextended.dev/docs/ox_inventory)
- **S13:** [QBox — Developer's Guide](https://docs.qbox.re/developers)
- **S14:** [Cfx — Secure Your Events](https://docs.fivem.net/docs/developers/server-security/)
- **S15:** [Cfx — State Bags](https://docs.fivem.net/docs/scripting-manual/networking/state-bags/)
- **S16:** [Cfx — OneSync](https://docs.fivem.net/docs/scripting-reference/onesync/)
- **S17:** [Cfx — Fullscreen NUI](https://docs.fivem.net/docs/scripting-manual/nui-development/full-screen-nui/)
- **S18:** [Cfx — Using the Profiler](https://docs.fivem.net/docs/scripting-manual/debugging/using-profiler/)
