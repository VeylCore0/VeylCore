# Mini games (`veyl_minigames`)

```
ensure veyl_minigames   # after veyl_ui
```

## Lockpick

A round lock with a pick that sweeps around it. Press **Space**, **E** or click when the pick is inside the gold zone to set a pin. Each pin makes the zone smaller and the pick faster, and it may change direction. A miss strains the pick (the bar under the pins); too many misses and it breaks. **Esc** gives up.

| Difficulty | Pins | Zone | Misses allowed |
|---|---|---|---|
| `easy` | 3 | 46° | 4 |
| `medium` | 4 | 36° | 3 |
| `hard` | 5 | 28° | 3 |

Used by: store registers (medium) and safes (hard) in `veyl_robbery`, and picking door locks in `veyl_doorlocks` (medium; with the game, your skill decides instead of the door's random lockpick chance). `/lockpicktest [easy|medium|hard]` lets anyone try it.

From another resource (client):

```lua
local p = promise.new()
exports.veyl_minigames:Lockpick({ difficulty = 'hard', title = 'Crack the safe' }, function(ok) p:resolve(ok) end)
local success = Citizen.Await(p)
```

Options: `difficulty`, `pins` (1–8), `misses`, `zone` (degrees), `speed` (degrees per second), `title`, `subtitle`. The result is decided on the client, so use it to gate an action the server still checks (item, distance, time), as the robbery and door scripts do.
