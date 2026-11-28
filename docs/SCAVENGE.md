# Dumpster diving (`veyl_scavenge`)

Target any trash can, bin or dumpster, or a garbage bag, and **Search** it. What can be found is set in `resources/[veyl]/veyl_scavenge/config.lua`.

## Adding loot

Open `config.lua`, find the kind (`dumpsters` or `bags`) and add a line to its `Loot` list:

```lua
{ item = 'plastic', weight = 30, min = 1, max = 4 },   -- an item
{ money = { 2, 18 }, weight = 10, label = 'loose change' },   -- cash
```

`weight` is how common it is compared with the other lines (bigger = more common; `EmptyWeight` is the chance of finding nothing). The item name must exist in `veyl_inventory/data/items.lua`; unknown names are skipped and reported in the server console at start. Each search makes `Rolls` draws, so one search can give several things.

Other settings per kind: how long the search takes, the animation, how long a prop stays picked over for you and for everyone, the optional hazard (a small injury chance), and the list of prop `Models`. Add a model name there and it becomes searchable. Global: `Distance`, `MaxSearchesPerHour`, `MinSecondsBetween`.

## What the server decides

The client only says which kind of prop it is searching and where. The server checks you are close enough and not in a vehicle, applies the prop and player cooldowns and the hourly cap, times the search (finishing early is refused), rolls the loot itself and hands it over with durable inventory and money operations, so retries never double anything. The client can never name an item or an amount.

Limit: the server does not know where props are, only where the player is, so a modified client could "search" thin air next to itself. The cooldowns and the hourly cap keep that from being worth much; there is no way around it without the server knowing every prop.

## Install

```cfg
ensure veyl_scavenge   # after veyl_core, veyl_lib, veyl_inventory, veyl_target
```

No database, no new items (the default loot uses items that already exist). Tested with a harness (12 checks: bad input, distance, timing, one payout per search, cooldowns, weights, hourly cap). Not tested in game: whether every listed prop model exists in your game build (missing ones are skipped by the client).
