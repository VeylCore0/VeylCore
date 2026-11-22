# Notifications and progress

Notifications (middle of the right edge by default), timed progress bars and hold-to-interact rings are drawn by **veyl_lib** (page: `packages/lib-ui`). Every existing call keeps working and gets the new look: `Veyl.Notify`, `Veyl.NotifyResult`, `Veyl.UI.Progress`, `vlib.notify`, `vlib.progress`, `exports.veyl_lib:Notify / StartProgress / CancelProgress / IsProgressActive`, and the `veyl_lib:notify` / `veyl_ui:notify` events.

Nothing here takes NUI focus: notifications and progress never grab the mouse or keyboard. Gameplay keys (cancel, hold) are read by the client with control natives.

## Look and settings

`veyl_lib/resource/client/ui_config.lua` (sent to the page when it loads):

| Setting | Default | |
|---|---|---|
| `Theme` | background `#151D22` at 86 %, text `#F7FAFC` / `#AAB6BF`, success `#A5F3D0`, info `#8BD4EE`, warning `#F0C374`, error `#EF9298`, `scale` 1.0, `reducedMotion` false | the same colours as the Ocean Drive HUD |
| `Notifications.position` | `center-right` (also `center-left`, `top-right`, `top-left`, `top-center`) | `offsetX` 1.6 % from the edge; `offsetY` moves it up (−) / down (+) from the middle, or down from the top |
| `Notifications.width` | 23 rem | |
| `maxVisible` / `maxQueue` | 4 / 20 | extra messages wait; beyond 20 the oldest waiting one is dropped |
| `defaultDuration` | 5000 ms (clamped 1.5–30 s) | |
| `duplicates` | `merge` | identical messages (or the same `id`) become one card with a ×2, ×3 counter; `stack` shows each |
| `restartOnUpdate` | true | a merge or `UpdateNotification` restarts the timer |
| `sound` / `volume` | on / 0.35 | a short soft tone per type (generated, no files) |
| `dismissKey` | none | Settings → Key Bindings → FiveM → *Dismiss newest notification* |
| `Progress.offsetY` / `width` | 11 % / 26 rem | bottom centre |
| `cancelControl` / `cancelLabel` | 73 / `X` | |
| `completeMs` | 900 | how long the green "done" state shows (0 = off) |
| `Hold.control` / `label` | 38 / `E` | |

The close (×) button on a card only appears while veyl_lib's own menu or dialog has the cursor; otherwise cards expire on their own (or with the dismiss key).

## Notifications

`exports.veyl_lib:Notify(options) -> id` (also `vlib.notify(options)` and `TriggerClientEvent('veyl_lib:notify', src, options)` from the server).

| Option | |
|---|---|
| `id` | your own id: sending it again updates that card (counter + 1) instead of adding one |
| `type` | `success`, `info` (default), `warning`, `error` |
| `title` | bold first line (80 chars) |
| `description` or `message` | text below (400 chars, wraps; long text is clamped to 3 lines) |
| `icon` | `check`, `info`, `warning`, `error`, `wrench`, `money`, `car`, `lock`, `key`, `hand`, `box`, `fuel`, `heart`, `clock`, `bell`, `message` (default: the type's icon) |
| `duration` | ms |
| `layout` | `standard` (title + text + line), `compact` (one line), `payment` (text + amount on the right). Chosen automatically when left out |
| `amount` | payment amount: a number shows as `+$250` / `−$250` |
| `sound` | `false` = silent |
| `showDuration` | `false` hides the thin time line |

`UpdateNotification(id, changes)` changes a visible or waiting card. `DismissNotification(id)` removes it; `DismissAllNotifications()` clears everything.

```lua
-- Success
exports.veyl_lib:Notify({ type = 'success', title = 'Vehicle stored', description = 'Your Sultan is safe in Legion Garage.' })
-- Error
exports.veyl_lib:Notify({ type = 'error', title = 'Action unavailable', description = 'You need a lockpick to continue.' })
-- Payment
exports.veyl_lib:Notify({ type = 'success', layout = 'payment', title = 'Payment received', amount = 250 })
-- Old style still works (compact card)
Veyl.Notify('Saved', 'success')
```

## Timed progress

`exports.veyl_lib:StartProgress(options, cb(completed, reason))`, or in a thread `local completed, reason = vlib.progress(options)`. `Veyl.UI.Progress` (veyl_ui) still returns true / false.

| Option | |
|---|---|
| `id` | name for your action (used in `CancelProgress(id)`) |
| `label`, `icon`, `duration` (250 ms – 120 s), `color` (`#rrggbb`) | |
| `canCancel` | default true; shows the X keycap. `cancelControl`, `cancelLabel` override the key |
| `disable` | `{ move = true, car = true, combat = true }` (combat is blocked unless `false`). With `move`, walking away cancels; with `car`, getting into / out of a vehicle cancels |
| `anim` | `{ dict, clip, flag }`, or `scenario = 'WORLD_HUMAN_WELDING'` |
| `prop` | `{ model, bone, pos, rot }` or a list of up to 3 |
| `completeLabel`, `showComplete` | the short green state at the end (default "<label> complete") |
| `replace` | `true` cancels the running action first; otherwise a second action is refused with reason `busy` |

**Result:** called exactly once. `completed` is true only when the full time passed. `reason` is `completed`, `cancelled` (key or `CancelProgress`), `dead`, `logout`, `moved`, `vehicle`, `replaced`, `caller_stopped` (your resource stopped) or `busy`. On every ending the animation, scenario and props are removed and controls come back.

**The bar never grants anything.** Your server must still check the time and requirements itself (every VeylCore job already does).

```lua
-- Cancellable vehicle repair
local done, reason = vlib.progress({ id = 'repair', label = 'Repairing vehicle', icon = 'wrench', duration = 9000,
    disable = { move = true, car = true }, anim = { dict = 'mini@repair', clip = 'fixing_a_ped', flag = 1 }, completeLabel = 'Repair complete' })
if done then TriggerServerEvent('myjob:repairFinished') else print('repair stopped:', reason) end

-- Non-cancellable timed action
vlib.progress({ label = 'Signing the contract', icon = 'box', duration = 4000, canCancel = false, disable = { move = true } })
```

## Hold to interact

`exports.veyl_lib:StartHoldProgress(options, cb(completed, reason))` or `vlib.holdProgress(options)`. A keycap in a ring that fills while the key is held.

| Option | |
|---|---|
| `label`, `subLabel` (default "Release to cancel", `false` hides it), `keyLabel`, `control` | key defaults to E (38) |
| `duration` | how long to hold |
| `decay` | leave out (or 0) to cancel on release; a number (e.g. `1.5`) lets the ring drain at that speed instead |
| `disable`, `anim`, `replace`, `completeLabel` | as above |

Start it when the player presses the key (e.g. from an interaction); there is a short grace period to start holding. Completes exactly once; releasing early returns `false, 'released'`.

```lua
local unlocked = vlib.holdProgress({ label = 'Hold to unlock', duration = 2500, keyLabel = 'E', completeLabel = 'Unlocked' })
if unlocked then TriggerServerEvent('mydoor:unlock') end
```

## Checked here / still to check

Checked: the page type-checks and builds; the Lua parses. Still to check in game: every type and layout, a burst of more than 4 (queue), duplicate merging, expiry and the dismiss key, completion / cancel / busy / replace, hold completion and early release, death / logout / resource-stop cleanup, and the look at 1080p, 1440p, 4K and ultrawide.
