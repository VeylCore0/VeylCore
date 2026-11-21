# veyl_doorlocks

Door locks you set up **in game**. You pick the door in the world, choose who can open it, and the lock state stays in sync for every player.

## Install

```cfg
ensure veyl_inventory
ensure veyl_interact
ensure veyl_doorlocks
add_ace group.admin veyl.doorlocks.admin allow   # or veyl.admin, which also works
```

- **Database:** tables are created automatically (migration `001_doorlocks`).
- **New items** in `veyl_inventory`:
  - `door_key` (a physical key for one door);
  - `lockpick`;
  - `door_ram`. It has no picture yet; the inventory shows its fallback icon.

## Setting up a door (staff)

1. Type **`/doorlock`**. The editor lists every door, nearest first.
2. Press **New door**. The editor hides and you aim at the door in the world:
   - **E** adds the door you're looking at, or removes it if it's already selected. Up to 4 doors per entry, for double doors and gate pairs.
   - **Enter** finishes; **Backspace** cancels.
   - The hint says **"Door found"** when the game knows the object as a door. Other objects can be added anyway, but only real doors can be locked.
3. Fill in the form, then **Save door**. Every player gets the change immediately.

| Section | Settings |
|---|---|
| **Door** | Name; locked by default; interaction distance (1–10 m); lock again automatically (never, or 5 s up to 1 h); hidden (no prompt, for scripts only). |
| **Who can open it** | Jobs (at or above a chosen grade), optionally only while on duty; gangs (minimum grade); specific people (add an online player by server id, or type a citizen id); items that open it (for example a keycard); whether physical keys for this door work. |
| **Business controls** | Manager jobs and grades. |
| **Breaching** | Can be lockpicked (success chance); can be breached with a door ram (optionally limited to on-duty jobs); how long until a breached door locks again. |

From the list you can also lock or unlock any door, **Go to** it, see its **Log** (the last 50 actions), **Edit** it (including **Re-pick doors**) or **Delete** it, which asks first.

## Using doors (players)

- **Opening:** walk up to a door to see its name and whether it's locked. Choose **Unlock** or **Lock**; the server checks that you're close and allowed in.
- **Access is checked in this order:** specific people → jobs (and duty) → gangs → items → physical keys → temporary access → staff. Staff use is logged.
- **Breaching:**
  - **Pick the lock** needs a lockpick and takes 6 s. It succeeds at the door's chance; a failed attempt may snap the pick (35%).
  - **Breach with ram** needs a door ram and takes 4 s, and can be limited to on-duty jobs.
  - **Server checks:** the server times both actions (finishing early is refused), and each attempt can be completed only once.
  - **Relocking:** breached doors lock themselves again after the configured time.

## Business controls (managers)

Managers, meaning the jobs and grades set in the editor (and staff), get **Manage access** at the door:

| Control | What it does |
|---|---|
| **Open for business** | Keeps the door unlocked, with no auto-lock, until someone closes it. |
| **Temporary access** | Give someone access for 1 hour to 7 days, by phone number or as a nearby player. Remove it any time; it also expires on its own. |
| **Cut a key** | Puts a physical key in your pockets. Hand it to anyone, and whoever holds it can use the door. Limited to 20 keys per lock. |
| **Change the locks** | Every key cut so far stops working. Jobs, gangs and temporary access are not affected. |

## For developers

```lua
exports.veyl_doorlocks:IsLocked(doorId)                 -- true/false (nil = unknown door)
exports.veyl_doorlocks:SetLocked(doorId, locked, reason) -- logged as your resource
exports.veyl_doorlocks:HasAccess(source, doorId)
exports.veyl_doorlocks:GetDoorByName('MRPD Front Desk')  -- id
exports.veyl_doorlocks:Breach(doorId, relockSeconds?, reason?) -- for heist/police scripts with their own minigame

-- server events
AddEventHandler('veyl_doorlocks:changed', function(doorId, locked, by, reason) end)
AddEventHandler('veyl_doorlocks:breachStarted', function(src, doorId, method, coords) end) -- e.g. alert police
AddEventHandler('veyl_doorlocks:breached', function(src, doorId, method, coords) end)
```

## Config (`config.lua`)

| Setting | Default |
|---|---|
| Command | `/doorlock` |
| Editor permission | `veyl.doorlocks.admin` or `veyl.admin` |
| Staff can use every door | `AdminBypass = true` |
| State after a restart | Each door's default (`StateOnRestart = 'default'`), or `'last'` to keep the last state |
| Breach timings and lockpick break chance | 6 s lockpick, 4 s ram, 35% break chance, relock after 300 s |
| Limits | Grant length up to 7 days, 25 grants per door, 20 keys per lock, log kept for 30 days |

## Tests that were run

| Suite | Result |
|---|---|
| Server code against **real MariaDB**, using the real `server/main.lua` | **48 checks passed** |
| Browser flows in the preview: list, lock toggle, log, edit form (jobs, people, breaching), new door → pick → name → save, delete confirmation, Escape, manager panel, door hint, 1280×720 | **21 flows passed** |
| Lua lint and TypeScript typecheck | Clean |

The server suite covered:
- editor rights and validation (names, entity count, coordinates, unknown jobs and items, markup);
- what clients receive (no access lists);
- distance;
- job grade and duty;
- people, gangs, items and staff;
- auto-lock;
- rate limit;
- open for business;
- grants (give, revoke, expiry, nearby only);
- keys (cut once per request, any holder, change locks, limit);
- lockpick and ram (item, duty, too fast, chance, relock, single-use token);
- exports;
- restart state;
- delete.

**Needs your live server:**
- aim-picking real MLO and base-game doors;
- double doors swinging together;
- that sliding gates respond to the door system;
- the key-card and lockpick animations.

## Limitations

- **Only real doors lock.** Doors must be objects the game treats as doors (the editor says "Door found"). Static props can't be locked.
- **No built-in police alert.** Lockpicking has no alert of its own: there's no dispatch resource yet. Listen for `veyl_doorlocks:breachStarted` to add one.
- **The door ram has no picture yet.** Add `door_ram.png` to `veyl_inventory/web/images` if you have one.
