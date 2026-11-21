# veyl_phone

An original smartphone for VeylCore. It sits bottom-right, scales from 0.75x to 1.3x, and lets the player keep walking while it is open. This release covers **milestones 1–3**: device and identity, home screen and settings, contacts, messages, calls, notifications, and the developer API. Apps from later milestones (camera, banking, services, social and the rest) are **not listed at all** until they are built; there are no placeholder icons.

## Install

```cfg
ensure veyl_phone        # after veyl_core, veyl_inventory, veyl_lib (and pma-voice if you use calls)
```

- The `phone` item is required (`PhoneConfig.RequireItem`). It is sold at the General Store for $400. Set `RequireItem = false` to skip the item check.
- Press **F1** to open (rebindable in GTA Settings → Key Bindings → FiveM). **Esc** closes. **Enter** unlocks.
- Tables are created automatically by migration `001_phone`.

## Identity and device rules

- The account and number belong to the **character**, not the item. A replacement phone restores that character's data. Holding someone else's phone item never grants access to their account.
- Numbers are 7 digits (`555-1234`), unique per character and never reused. A deleted character's number reports "not in service".
- A character has an active phone session only while they carry a phone. Without one, messages are stored and delivered later, and calls report "unavailable".
- Switching character ends the old session at once: any call in progress ends, and the new character's data is loaded.

## Messages: what the states mean

| State | Meaning |
|---|---|
| **Sent** | Stored on the server. The recipient may be offline. |
| **Delivered** | The recipient's phone acknowledged it. Offline recipients get pending messages when they next sign in. |
| **Read** | The recipient opened the conversation **and** has read receipts on. With receipts off, it stays Delivered. |

- **Groups:** up to 12 members. Admins can rename, add and remove members. If the last admin leaves, the longest-standing member becomes admin.
- **Group ticks:** count only the members who can actually receive the message.
- **Blocking:** a blocked person's direct messages are refused, and their group messages are hidden from you. Their calls hear "unavailable", the same answer as an offline number, so blocking is never revealed.
- **Location pins:** use the sender's **server-side** position, so they can't be spoofed.
- **Retries:** sending reuses a client operation id, so a retried send never creates a duplicate.

## Calls and voice

Calls need **pma-voice**. When it is not started, the dialler shows: *"Calls need a voice resource. Install and start pma-voice to enable calling."* The server refuses `callStart` with `VOICE_UNAVAILABLE`. No fake ringing is ever shown.

With pma-voice running:

- **States:** ringing → connected → ended.
- **Ending a call:** a call ends on hang-up, decline, a ring timeout (30 s, which sends a missed-call notification), do-not-disturb, disconnect, character change or resource stop.
- **Voice channel:** both parties join channel `5000 + call id` and leave it (channel 0) whenever the call ends.
- **Busy:** a second caller hears "The line is busy".
- **Mute:** stops the other person hearing you.
- **Speakerphone:** not offered, because pma-voice has no documented speakerphone API.

## Settings

Each character's settings are stored server-side and validated, so unknown values fall back to defaults:

- **Appearance:** wallpaper, accent, phone size and position.
- **Sound:** ringtone, notification sound, both volumes, silent.
- **Focus and privacy:** do-not-disturb, lock-screen previews (full / sender only / hidden), read receipts.
- **Home screen:** widgets (clock and weather, recent chats, bank balance with a hide toggle), reduced motion, and the layout. Hold an app to rearrange it or make folders.

**Weather and time** come from `veyl_world` (`GlobalState.veylWorld`). **Bank balance** comes from the core ledger.

## Developer API

### Server exports

```lua
-- Post a notification (stored, deduplicated, pushed if the phone is live). Returns the id, or nil if `dedupe` was already used.
exports.veyl_phone:Notify(citizenid, { app = 'invoices', title = 'Mechanic invoice', body = '#12 · $640', route = 'invoices', dedupe = 'invoice:12' })

exports.veyl_phone:SetBadge(citizenid, 'invoices', 3)    -- badge on your app icon (in memory; re-send it on veyl_phone:sessionStarted)
exports.veyl_phone:GetNumber(citizenid)                  -- '5551234' or nil
exports.veyl_phone:GetCitizenByNumber('555-1234')        -- citizenid or nil (deleted characters excluded)
exports.veyl_phone:OpenApp(source, 'messages')           -- opens the phone on that player's client (only if they have a phone)
```

### Server events

| Event | Arguments | Notes |
|---|---|---|
| `veyl_phone:ready` | none | Startup is finished. |
| `veyl_phone:sessionStarted` | `src, { cid, number, ... }` | A player's phone came online. |
| `veyl_phone:sessionEnded` | `src, session, reason` | `reason` is `dropped`, `logout` or `character_changed`. |

### Client exports

```lua
-- A home-screen shortcut owned by your resource. Tapping it closes the phone and fires `event` locally.
-- No remote or untrusted code ever runs. It is removed when your resource stops.
exports.veyl_phone:RegisterApp({ id = 'invoices', label = 'Invoices', icon = 'receipt', color = '#d08b4f', event = 'myres:openInvoices' })
exports.veyl_phone:IsOpen()
exports.veyl_phone:Open('contacts')
```

Register again in `onClientResourceStart` for `veyl_phone`, so your app survives a phone restart.

**Worked example:** `veyl_mechanic` adds an **Invoices** app, sends a notification for every invoice, and keeps an unpaid-count badge. See the end of `veyl_mechanic/client.lua` and `syncPhoneBadge` in `veyl_mechanic/server.lua`. Every phone call there is guarded with `GetResourceState('veyl_phone') == 'started'`, so the mechanic works without the phone.

## Security

- The NUI can call only the whitelisted phone callbacks (the `ALLOWED` list in `client/main.lua`). Each callback re-checks the session and conversation membership on the server.
- Every write is validated: lengths, number format, enum values.
- Rate limits: messages, calls and settings saves are throttled per player.
- Contacts, blocks, notifications and settings are always scoped to the calling character.

## Tests that were run

| Suite | Result |
|---|---|
| Server code against **real MariaDB** (a throwaway database), using the real `server/*.lua` | 59 checks passed |
| Browser flows in the preview: lock → home → messages → delivered tick, banners, contacts, dialler → connected → hang-up, incoming call, settings, empty and error states, 1280×720 fit | 23 flows passed |
| `veyl_mechanic` server tests after the integration | 19 checks passed |
| Lua lint and TypeScript typecheck | clean |

The server suite covered:
- identity, and settings sanitising;
- contact isolation;
- the sent → delivered → read states, including with read receipts off;
- offline delivery;
- unauthorised thread and send attempts;
- groups and admin rules;
- blocking, including inside groups;
- idempotent sends;
- calls: no voice, busy, answer/hang-up voice channels, timeout and missed call, cancel, decline, disconnect, DND, character change;
- notification dedupe and bounded history;
- deleted-character numbers.

**Not verified in game yet:** the prop and animation, real pma-voice audio, and F1 focus behaviour. Restart through txAdmin and check them.

## Limitations

- **Calls:** off until pma-voice is installed. No speakerphone.
- **Camera and gallery:** not built. No screenshot resource is installed.
- **Later milestones (4–7):** banking, business directory, classifieds, social, jobs, services, maps, garage, properties, deliveries, events and criminal contacts are not built, so they are hidden.
- **Badges:** held in memory. Resources should re-send them on `veyl_phone:sessionStarted`.
