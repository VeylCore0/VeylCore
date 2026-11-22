# Store robbery (`veyl_robbery`)

Every **24/7**, **LTD Gasoline** and **Rob's Liquor** can be robbed (each shop marked `robbable = true` in `veyl_shops/config.lua`). Hold the target key (**ALT**) and aim at the counter: the clerk's *Shop* prompt and the robbery option do not get in each other's way.

| Target | Needs | Time | Take |
|---|---|---|---|
| **Register** (at the clerk) | A weapon in hand (gun or melee) | 25 s | $400 – $900 cash |
| **Safe** (back room) | A lockpick (25 % chance it breaks) | 60 s | $1,500 – $3,500 cash |

- At least **2 on-duty police** (`MinPolice`); on-duty officers cannot rob.
- The moment it starts, police get an urgent **Store robbery** dispatch call with the store (silent alarm).
- Cooldowns: 30 min per store and target, 10 min per robber.
- Walking away, going down or being cuffed before it finishes gets nothing.

Safe positions are in `Safes` (by shop id) in `config.lua`; they assume the base-game store interiors, so check them on your map. A store without a safe entry has a register only. Rewards, times and cooldowns are in the same file.
