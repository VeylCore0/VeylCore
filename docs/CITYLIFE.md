# City life: jobs, gathering and crafting

Three resources, started after `veyl_delivery`:

```
ensure veyl_citizenjobs   # trucking, garbage, taxi, tow
ensure veyl_gathering     # mining, hunting, farming, buyers
ensure veyl_crafting      # benches and recipes
```

All coordinates are starting values. Check them in game with `/vcoords` and move them in each `config.lua`.

## City jobs (`veyl_citizenjobs`)

Talk to the depot worker, then choose **Start a shift**. If you are unemployed you are signed on to that job; if you already have another job, switch first (`/jobs` or the phone's Jobs app). The vehicle is spawned for you with keys. **Finish shift** at the depot; **Cancel** pays nothing for unfinished work.

| Job | Depot | What you do | Pay |
|---|---|---|---|
| **Trucking** (`trucker`) | Port of Los Santos | Drive the box truck to the marked drop-off and unload it (8 s). Bring the truck back for a bonus | $150 + $95 per km, + $120 for returning the truck |
| **Sanitation** (`garbage`) | Strawberry | 8 bin stops. At each: take a bag from the bins, throw it in the back of the truck (1–3 bags per stop). 35 % chance per bag of a recyclable (plastic, glass, rubber, scrap metal) | $22 per bag, + $200 for finishing the route and bringing the truck back (paid at the depot) |
| **Taxi** (`taxi`) | Mirror Park | Pull up at the marked passenger, drive them to their destination. A new fare is marked straight after | $40 + $110 per km + tip, paid on each drop-off |
| **Tow** (`tow`) | Davis | Drive the flatbed to the breakdown, hook it (5 s, the car sits on the bed), drop it at the yard | $320 per tow, paid on each drop |

The server checks every step: distance to the target, that your work vehicle is there, that you are driving it (taxi), and a minimum time per step (no teleport payouts). Pay goes to the bank with one operation id per step, so it is never paid twice. Leaving the job, disconnecting or losing the vehicle ends the shift.

## Gathering (`veyl_gathering`)

| Activity | Where | Needs | Gets |
|---|---|---|---|
| **Mining** | Davis Quartz quarry (10 rocks; a rock refills after 2.5 min) | A `pickaxe` (YouTool, Sandy Shores, or craft one) | Stone, coal, iron ore, copper ore, sometimes gold ore |
| **Farming** | Grapeseed (wheat, tomatoes, potatoes, lettuce, orange trees, cows) | Nothing | Produce and milk (each point refills after 2 min) |
| **Hunting** | Paleto Forest, Tongva Hills, Mount Chiliad foothills (shown as areas on the map) | A weapon to hunt with, and a `weapon_knife` to skin | Raw meat, deer / boar hides, coyote pelts, sometimes antlers |

Animals appear around hunters inside a hunting area (up to 3 each) and are registered with the server; only those can be skinned, once, when dead and within 3 m. A **hunting licence** ($750, City Hall) is needed to buy the musket at **Hunting Supplies** (Paleto).

**Skills:** mining, farming and hunting each gain xp (stored in the character's `metadata.skills`). Every 100 xp (up to level 5) adds a 6 % chance of an extra item.

**Buyers** (cash): the **ore & metal buyer** at the foundry (ores, ingots, gold bars, scrap), the **butcher** in Paleto (meat, hides, antlers), the **farmers' market** in Grapeseed (produce, milk). Prices are in `GatheringConfig.Buyers`.

Ores and potatoes / lettuce / milk / oranges also feed the businesses (Burger Shot, Bean Machine, the nightclub bar).

## Crafting (`veyl_crafting`)

Benches (menu shows what you can make, what is missing and the time):

| Bench | Where | Who | Makes |
|---|---|---|---|
| **Foundry** | El Burro Heights | Anyone | Iron / copper ingots, gold bars, glass |
| **Public workshop** | YouTool, Sandy Shores | Anyone | Lockpicks, repair kits, tyre kits, pickaxes, radios, fishing rods, plant pots, flashlights |
| **Parts bench** | LS Customs | Mechanics and tuner shop staff | Engine parts, body panels, tyre kits, performance kits (brakes, suspension, transmission, engine, turbo) |
| **Backroom bench** | Not on the map | Anyone who finds it | Fake plates, pistol ammo, body armour, thermite |

Recipes have a **crafting level** (every 100 crafting xp = 1 level, up to 10). Materials are checked when you start and again when you finish, and only taken on finish after the full time. If there is no room for the result, the materials are given back.

**Body armour** (`armor_vest`): use it to put on full armour.

## Items added

Materials: `stone`, `coal`, `iron_ore`, `copper_ore`, `gold_ore`, `iron_ingot`, `copper_ingot`, `gold_bar`, `plastic`, `glass`, `rubber`. Hunting / farming: `raw_meat`, `deer_hide`, `boar_hide`, `coyote_pelt`, `deer_antlers`, `tomato`, `wheat`, `orange`. Tools and gear: `pickaxe`, `fake_plate`, `armor_vest`, `perf_engine`, `perf_brakes`, `perf_transmission`, `perf_suspension`, `perf_turbo`. Drinks: `beer`, `whiskey`, `cocktail`. They have no pictures yet (the inventory shows the name).

## Not checked in game yet

Every depot, rock, farm point, bench and buyer position; the tow hook offset on the flatbed; animal spawning on hills; the taxi passenger getting in and out. Lua parses and the new SQL was run on MariaDB.
