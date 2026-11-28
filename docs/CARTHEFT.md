# Car theft (`veyl_cartheft`)

Ambient cars are locked. There are three ways in, and loot waits in the trunk and glovebox of cars nobody owns.

```cfg
ensure veyl_minigames
ensure veyl_vehicles
ensure veyl_cartheft     # after veyl_inventory, veyl_target, veyl_minigames and veyl_vehicles
```

## What happens

- **Every parked ambient car is locked** as it comes into range. Cars a pedestrian is driving are never locked (a lock on a car with an AI driver makes the driver stop, get out and walk off); instead their driver cannot be dragged out without a gun. Cars VeylCore manages (owned, dealer, job and mission vehicles) are never touched, and neither are cycles, boats, aircraft and trains (`Lock.ExcludeClasses`).
- **Point a gun at a driver.** Hold your aim for about three seconds: the driver brakes, puts their hands up and, most of the time (`Carjack.SuccessChance`), pulls over to the kerb, gets out and runs, leaving you the keys. Lower your gun and they get their nerve back and drive off; sometimes they just floor it.
- **Lockpick a parked car.** Look at it, pick **Lockpick the door** (you need a `lockpick`). A tumbler minigame plays: a needle sweeps a bar and you hit the green zone each round, which shrinks. Three misses snap the pick, and a failed attempt can use up the lockpick (`BreakChanceOnFail`). The car alarm may go off.
- **Hotwire it.** Inside, the engine stays dead and a prompt says *Press H to hotwire it*. A wiring minigame plays: match every coloured wire to its terminal before time runs out (wrong terminals are strikes). Success gives you the keys.
- **The keys** are to that plate, last `KeysMinutes` and are lost on a server restart. They are not the keys of owned vehicles (`veyl_vehiclekeys` handles those).
- **Trunk and glovebox loot:** the first time a car nobody owns has its trunk or glovebox opened, a few random items are put inside (once per plate every `Loot.RerollHours`). The tables, with weights and amounts, are at the bottom of `config.lua`. The trunk needs the car unlocked or its keys, as before.
- **Police alerts** are off by default (`Police.Enabled` and `Police.Dispatch.Enabled`, and a dispatch resource that exports `Alert`).

## The minigames (`veyl_minigames`)

Two new ones next to the pin lockpick, usable by any resource:

```lua
exports.veyl_minigames:CarLockpick({ difficulty = 'easy' | 'medium' | 'hard', rounds = 4 }, function(success) end)
exports.veyl_minigames:Hotwire({ difficulty = 'medium', wires = 4, seconds = 30 }, function(success) end)
```

Try them with `/tumblertest [difficulty]` and `/hotwiretest [difficulty]`.

## What the server decides

Every attempt starts and ends with the server. It checks the car (real, not VeylCore-managed), distance, that nobody is in a car you are picking, the item, a cooldown and, for the end, a token plus a minimum time (a tumbler round cannot be done faster than `MinMsPerRound`, the hotwire not faster than `Hotwire.MinMs`, the aim held for nearly `HoldMs`). A wrong or reused token, or a finish that is too early, is refused and logged. The client only reports success, so a modified client could claim a win, but only after the real minimum time and only for the cars and distances the server allowed. If you do not trust the client score at all, raise `MinMsPerRound` and `Hotwire.MinMs`.

## Exports

`HasKey(citizenid, plate)` and `GiveKey(citizenid, plate)` for other resources; `EnsureLoot(stashId, storageKey)` is called by `veyl_vehicles` and `veyl_inventory` gained `GiveToKeyedStash` for it.

## Tests and limits

36 checks of the server rules run against a real database (starts, tokens, timing, cooldowns, items, keys and their expiry, loot once per plate and only for cars nobody owns); the minigame pages are tested in a browser (success, failure, give up, the old lockpick still opening). Not tested in game: locking the traffic and how the lock state syncs between players near the same car, the peds' reactions, the help text and animations. Door lock state on cars controlled by another player's game may need a retry; `Lock.Radius` and the loop are the places to tune.
