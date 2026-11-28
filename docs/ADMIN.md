# Staff menu (`veyl_admin`)

Type **/admin** to open the staff menu. It needs the `veyl.admin` permission (`add_ace group.admin veyl.admin allow`), which your admins already have. Nobody else can open it, and the server checks the permission again on every single click, so a modified client gets nothing.

```cfg
ensure veyl_admin      # after veyl_lib, veyl_core, veyl_inventory
add_ace group.admin veyl.admin allow
# optional: lets this group act on other admins, and (if AnyAdminMayRestart = false) restart resources
add_ace group.owner veyl.admin.super allow
```

A key can be set in `config.lua` (`Key = 'F10'`); players can also rebind it in the game's key settings.

## What is in it

| Section | What you can do |
|---|---|
| **Dashboard** | Players online, open reports, active bans, uptime, the world clock and weather, an announcement box to everyone. |
| **Players** | A live list (search by id, name, character, job). Pick one to **go to, bring, spectate, freeze, revive, heal, kill**; **message** them on screen; **warn** (kept on their record); **kick**; **ban** (hours, or 0 = permanent, by licence); see their **identifiers, health, armour, wallet, job, gang, inventory and warnings**; **give or take money** (cash, bank, crypto, with a reason), **set job or gang**, **give or take an item**. |
| **Self tools** | **Noclip** (WASD, Shift fast, Ctrl slow, Q up, E down, six speeds), **god mode**, **invisible**, **player names** over heads, heal, full armour, teleport to waypoint, copy coordinates. |
| **Vehicles** | Spawn any vehicle by model (optional plate) or from the quick list; repair, clean, flip upright or delete the car you are in or next to. |
| **World** | Weather, time presets or an exact time, freeze time and weather, remove abandoned vehicles near you (never owned, dealer or job ones). |
| **Reports** | Players' `/report` messages, open first. Close them from here. |
| **Bans** | Active bans with reason, who and until when. Unban. |
| **Audit log** | The latest 100 audit entries; filter by action, resource or citizen id. |
| **Server** | Uptime, players, resources up; start, stop or restart a resource (veyl_core, veyl_lib, veyl_admin, oxmysql and veyl_ui are protected from stopping). |

The older commands (`/vplayers`, `/vtp`, `/vbring`, `/vrevive`, `/vkick`, `/vgivemoney`, `/vsetjob`, `/vgiveitem`, `/vreports` and the rest) still work.

## Safety

- Every action is written to the audit log with who did what to whom.
- Money and items use the same durable, operation-keyed calls as the rest of the game, so a retry never doubles anything.
- Kick, kill, freeze, ban and taking money or items refuse a target who is also staff, unless you have `veyl.admin.super`.
- Bans are by Rockstar licence, checked when someone connects, so a new name does not help. Timed bans end by themselves.
- Resource commands only accept real resource names and the three actions start, stop and restart. Time and weather values are validated before they reach the world resource.
- Spawning a vehicle, noclip, god mode and invisibility ask the server first and are logged.

## Settings (`config.lua`)

`Command`, `Key`, the weather list, `AnyAdminMayRestart` (true: every admin; false: only `veyl.admin.super`), `ShowAllResources`, `ProtectedResources`, noclip speeds and the quick vehicle list.

## Tests and limits

42 server checks run against a real database (permissions on every callback, each action and its refusals, warnings, bans and the connection check, reports, logs, world, resources, staff protection). The menu has 24 browser checks. Not tested in game: noclip, spectate, god mode, invisibility, vehicle spawning, the overhead names and the clean-up (they are client natives), and the screen opening over the world. Spectate needs the other player's ped to stream in, so it flies you near them first and returns you when you press Backspace.
