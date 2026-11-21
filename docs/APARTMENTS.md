# veyl_apartments

Private homes in the **Starlite Motel** (Zydrec's free `zydrec-starlitemotel` MLO in East Vinewood). Players can:

- lease a room at the front desk;
- enter through their own door;
- add roommates and hand out guest passes;
- let visitors in from the doorbell;
- use storage and a wardrobe;
- furnish the room;
- manage everything from the phone app or the `/apartment` panel.

## Install

```cfg
ensure veyl_inventory
ensure veyl_interact
ensure veyl_phone            # optional (resident app + notifications)
ensure zydrec-starlitemotel  # the MLO (must start before veyl_apartments)
ensure veyl_apartments
```

- **Getting the MLO:** the txAdmin recipe downloads it automatically, pinned to v1.1.0. For a manual install, get it from https://github.com/Zydrec/zydrec-starlitemotel. Credit: Zydrec. It's free to use and share, but not to sell.
- **Database:** tables are created automatically (migration `001_apartments`).
- **Items:** none are needed. Keys are digital and checked on the server.
- **Building the UI:** `npm run build` builds `packages/apartments-ui` into `veyl_apartments/web/dist`. The built files are committed.

Other resources this release changes:
- `veyl_inventory`: stashes can name an `authorize` export.
- `veyl_spawn`: asks `ResolveSpawn` where to place a player.
- `veyl_appearance`: new outfit exports.
- `veyl_garages` and `veyl_vehicles`: their exports from the phone update are reused.

## What the MLO actually contains (and what was built for it)

I decoded the MLO's compiled files (`stream/ymap/mlo_placements/*.ymap`, `stream/ytyp/zydrec_sm_interior.ytyp`) rather than guessing coordinates:

| Found | Value |
|---|---|
| Rooms | **30** separate placements of one interior archetype, `zydrec_sm_int`. |
| Layout | 3 floors (z 73.674 / 76.775 / 79.833 in v1.0.2), U-shaped: East wing 4 rooms, South wing 3, West wing 3 per floor. |
| Room size | 8.95 m × 5.61 m × 2.82 m. Bounds in local space: min (-4.518, -2.650, -1.541), max (4.436, 2.957, 1.275). |
| Door | `zydrec_sm_prop_door` at local (4.454, -1.707, -0.399), on the front wall facing the courtyard walkway. |
| Windows | One front window, one back window. |
| Furniture | None. The rooms are empty by design. |
| Lobby, reception, elevators, gym, laundry, rooftop, mailboxes | **None.** Upper floors are reached by exterior walkways. |
| v1.1.0 changes | Ground-floor rooms moved up 0.045 m. The installed version is read at start, so v1.0.2 and v1.1.0 both line up. |

`data/starlite.lua` was generated from these files. Room numbers follow the MLO's placement order (`milo_` = room 1, …, `milo__29` = room 30). If the numbers painted on the doors differ in game, edit `number` there.

### Architecture: physical rooms, private worlds

The motel is **physical mode**: 30 distinct rooms, so there are 30 leasable units. I did not build instanced or hybrid modes for this MLO, because it has no shared lobby or elevator to connect them.

| Concern | How it's handled |
|---|---|
| Getting in | Every room's real MLO door is locked on every client with the game's door system. You enter with **Enter** at your door: the server checks the lease, your permissions, your distance, that you're not in a vehicle, not dead, and not in a configured restraint state. Then it fades you inside. |
| Privacy | Inside, you are put in a **routing bucket for that unit**. People outside, or in other rooms, can't see you, collide with you, or interact with you. Furniture spawns only on the clients inside that home. |
| Stable ids | The unit id (`veyl_apartment_units.id`) is stored. The bucket number (`BucketBase + id`) is never stored; it's recomputed at runtime. |
| Leaving | **Leave** is always allowed, even after access is revoked. `/aptstuck` is an emergency exit that works from inside any room's walls. Transitions wait for collision and the interior to load, find the floor, and always fade back in. |
| Voice | I could not verify voice isolation between buckets: pma-voice isn't installed, and native voice handling of buckets is unconfirmed. **Test it live.** |

## Leasing and rent

The front desk is an outdoor counter. The MLO has no office, so the counter stands in the middle of the courtyard, at a point derived from the ground-floor door positions. Its ground height is found in game, and `/aptpos` prints positions if you want to move it.

At the desk, a player:
1. Picks a room by floor and wing.
2. Reads the terms.
3. Optionally takes a **tour**: a vacant room in a private world, 90 s, no storage or furniture. Their original position is restored afterwards.
4. Signs.

| Rule | Detail |
|---|---|
| Price | $450 every 7 days, plus a $450 deposit. The first period and the deposit are charged when signing. Change this in `AptTypes`. |
| One room, one live lease | Enforced by a database unique key on pending/active leases. Two players can never lease the same room. |
| Double clicks | Every request carries an id, and repeats return the first result. |
| Rent ids | Each period has its own operation id (`apt:rent:<lease>:<period>`). Automatic and manual payments share it, so a period is charged **once**, including across restarts and timeouts. |
| Schedule | Server timestamps in the database. Runs for offline players. Checks every 60 s in batches of 25. |
| Reminders | 24 h before rent is due. |
| Failed payments | The lease becomes overdue and is retried every 6 h, never in a loop. |
| Eviction | After 3 days overdue (`EvictionPolicy = 'end_lease'`, or `'notify_only'` to only notify). |
| Moving out | Type `MOVE OUT`. The deposit is refunded if no rent is owed. Rent already paid isn't refunded. |
| Leases stuck pending | A lease whose first payment never confirmed (crash or timeout) is resolved from the ledger after 2 minutes. |
| Deleted characters | Ending the lease of a deleted (soft-deleted) character is checked by the billing tick. |

### Belongings are never deleted

- **Storage is keyed by the lease**, not the room: `apt_l<lease>` is shared, and `apt_l<lease>_k<citizenid>` is a roommate's locker. When a lease ends, **nothing is moved**: its stashes switch to *recovery*.
- **Collecting:** the owner opens them at the front desk (**Parcels & storage**) for `RecoveryDays` (14). After that, residents can't open them. **Staff still can** (`/aptstorage`), and they're never deleted automatically.
- **Furniture** goes back to its buyers as stored pieces. They follow the buyer to their next home, or can be sold back.
- **Removed roommates:** their locker goes to recovery for them, and their furniture leaves with them.

## Keys and permissions

| Role | Gets |
|---|---|
| **Leaseholder** | Everything: enter, storage, wardrobe, furniture, guests, roommates, lease. |
| **Roommate** | Chosen by the leaseholder from enter / storage / wardrobe / furniture / guests. Roommates and lease can't be delegated. Up to 2 roommates. Invites expire after 24 h. |
| **Guest** | Enter only, until the pass expires: up to 72 h, optionally one visit. Revoking takes effect immediately. |

- **Checked every time:** permissions are checked on the server for every action, including every storage open and every inventory move (through `veyl_inventory`'s `authorize` hook).
- **Revoked while inside:** protected actions stop at once, and after 20 s (`RevokedExitSeconds`) the person is walked out through the door.
- **Single-visit passes** stay valid until the guest leaves.
- **Rent help:** roommates can send the leaseholder a recorded contribution (a real bank transfer). Nobody is charged automatically.

## Visitors

| Feature | How it works |
|---|---|
| **Knock** | At any door, or the **visitor directory** at the front desk. The directory only lists residents who opted in, and shows their name only, never the room. |
| Who's asked | The leaseholder, plus roommates with the guest permission, as a card in game with Allow entry / Decline / Ignore / Block, plus a phone notification. |
| Allow entry | Creates a **15-minute, single-visit** pass and tells the visitor the room number. It never grants permanent access. |
| No answer | Vacant rooms, blocked visitors and residents who are offline all answer **"No one answered"**, so nothing leaks. |
| Limits | 20 s cooldown per visitor per home, at most 3 pending requests, and requests expire after 60 s. |

## Furniture

- **Catalog:** 47 pieces across 8 categories. Every model name was checked against the base-game object list. Models missing on a player's game build are greyed out.
- **Preview first:** the ghost is green or red with the reason. Controls are on screen: mouse aim, arrow nudge, wheel / Q / E to rotate, PgUp / PgDn for height, Shift for fine steps, G to toggle follow-aim, Enter to confirm, Backspace to cancel. **You pay only when the server accepts the spot**, and cancelling or a rejected spot costs nothing.
- **Server checks:** inside the room's walls (0.25 m margin), a 1.3 m doorway kept clear, the entry spot kept clear, height limits, 0.35 m spacing between pieces, the room's piece limit (25), and allow-listed models only.
- **Purchases** reserve their row first and charge with an operation id. A crash between charging and placing is resolved from the ledger.
- **Ownership:** the buyer owns a piece. Only the buyer can sell it back (50%), and only once.
- **Not offered:** storage furniture (nothing can hold items), sit / lie interactions and light toggles. These need per-model offsets and animations calibrated in game.

## Wardrobe, parcels, noticeboard, maintenance, phone

- **Wardrobe** (inside, needs the wardrobe permission): save, rename, wear and delete outfits. It uses `veyl_appearance`'s own outfits, so there's no duplicate appearance system.
- **Parcels:** other resources call `exports.veyl_apartments:SendParcel(citizenid, { sender, label, items = { { name, count, metadata? } }, sourceOp })`. Parcels wait at the front desk, and drivers never get into homes. Each item is delivered once. A full inventory hands over nothing and the parcel is kept. Uncollected parcels return after 14 days. **No VeylCore resource sends parcels yet**; this is the API for future deliveries.
- **Noticeboard** (front desk): residents post announcements, roommate-wanted notices, events and items for sale. Posts last 7 days, with a 60 s cooldown and 3 active posts per resident. A post is hidden after 3 reports, and staff can remove it.
- **Maintenance:** residents file a request with a category and preferred time, and can allow one time-limited entry. Staff with ACE `veyl.apartments.maintenance` accept, schedule, start (this issues a 60-minute single-visit pass only if the resident allowed entry) and complete (which revokes the pass). If nobody accepts within 30 minutes, the front desk closes the request (`NpcFallbackMinutes`, set it to nil to turn this off).
- **Phone:** an **Apartments** app (via `RegisterApp`) opens the same resident panel as `/apartment`, using the same server logic. Without `veyl_phone`, the panel still works, and notifications fall back to in-game toasts.
- **Parking:** this is hidden until you set `parking = '<veyl_garages garage id>'` on the building. There are no verified parking-bay coordinates for the motel yet. Owned vehicles are never touched by lease changes.

## Reconnects and restarts

- **On spawn**, `veyl_spawn` asks `ResolveSpawn`:
  - **Still allowed in:** you go back inside your home's private world.
  - **Not allowed any more:** you go to that room's door.
  - **Disconnected during a tour:** you go back to where the tour started.
  - **Saved position inside a room but no record:** you go to that room's door.
  - **Hospital respawn:** the "inside" record is cleared.
- **On resource restart**, players inside get their context back from the database. Furniture is reloaded idempotently (no duplicates), and stashes re-register. If `veyl_inventory` restarts, the stashes re-register too.

## Staff

| Command | ACE | Does |
|---|---|---|
| `/aptfind [room#/leaseId/citizenid]` | `veyl.apartments.view` | Find leases. |
| `/aptinfo <leaseId>` | view | Lease, roommates, guests, last payments, storage state, furniture counts. |
| `/aptpos` | view | Your world position, and your local position if you're inside a room (for configuring). |
| `/aptend <leaseId> <reason>` | `veyl.apartments.manage` | End a lease. A reason is required. Storage and furniture go to recovery. |
| `/aptkick <unitId>` | manage | Walk everyone in a room out. |
| `/aptunit <unitId> enable\|disable` | manage | Take a room off the market. |
| `/aptstorage <stashId>` | manage | Open any apartment or recovery stash. |
| `/aptpass <leaseId>` | manage | A 15-minute single-visit pass for yourself. The resident is notified. |

`veyl.admin` also allows all of these. Every use is audited.

## Tests that were run

| Suite | Result |
|---|---|
| Server code against **real MariaDB** (throwaway database, the real `server/*.lua`) | **115 checks passed** |
| Browser flows (preview): leasing, tour, dashboard tabs, keys, rent, maintenance, move-out confirmation, furniture catalog and placement hand-off, desk (directory, parcels, recovery, noticeboard), wardrobe, doorbell, 1280×720 and 2560×1080 | **39 flows passed** |
| MLO data | Placements decoded from v1.0.2 (installed) and v1.0.2 vs v1.1.0 compared. Room-1 door world position checked. |
| Furniture models | 47/47 found in the base-game object list. |
| Lua lint and TypeScript typecheck | Clean. |

Server suite coverage:
- **Leasing:** catalog at the desk; two players and one room; a race against a pending lease; double clicks; insufficient funds; one lease per character.
- **Billing:** offline rent; repeated ticks; crash between charge and record; timeouts; manual plus automatic payment on the same period; pay-ahead limit; reminders; overdue, retry delay and eviction.
- **Access:** entry rules (distance, vehicle, restraint, strangers, vacant rooms); private bucket; storage authorization.
- **Guests and roommates:** guest passes (single visit, expiry, revoke while inside, then walked out); roommates (invite, accept, lockers, permission narrowing, non-delegable permissions).
- **Visitors:** doorbell (answer rights, allow into the real home, block, vacant room); directory privacy.
- **Furniture:** bounds; unknown model; retry without a double charge; spacing; move; double sale; insufficient funds.
- **Spawning:** reconnect inside; hospital; saved inside a room; tours.
- **Front desk:** parcels (idempotent, full inventory, double collection, wrong person); noticeboard; maintenance pass lifecycle; dashboard dates.
- **Endings:** recovery storage (owner only, desk only, window); move-out refund (once); furniture following you to a new lease; deleted characters.

## Needs testing on your live server

- **Door locking** on the MLO door entity, and that it can't be opened by walking into it.
- **The ground probe** at the front desk and at each room's inside and outside points (especially floors 2–3), and that transitions never leave you under the floor.
- **Routing-bucket isolation in practice:** two households in neighbouring rooms, voice (once a voice resource is installed), and furniture visibility.
- **Painted door numbers** against the room numbers in `data/starlite.lua`.
- **Furniture placement feel:** the ghost, the controls and the outline colours.
- **Phone app:** shortcut and notification taps.

## Known limitations

- **One building, one apartment type.** The MLO has one interior.
- **No elevators or amenities.** None exist in this MLO, so no elevator panel or amenity markers are shown.
- **Front desk position:** it's an outdoor counter at a derived courtyard point. Move it if it stands somewhere awkward.
- **Furniture extras:** no sit / lie, light toggles or storage furniture yet.
- **Parking** needs a verified garage id.
- **Parcels** have the API only; no current resource delivers to homes.
