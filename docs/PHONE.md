# veyl_phone

An original smartphone for VeylCore. It sits bottom-right, scales from 0.75x to 1.3x, and lets the player keep walking while it is open. It includes device and identity, the home screen and settings, contacts, messages, calls, notifications, the developer API, and an **App Store** with Flock (social), Bank, Garage, Marketplace, Notes and Calculator. Apps that aren't built yet are **not listed at all**; there are no placeholder icons.

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

## Apps and the App Store

Phone, Messages, Contacts, Settings and the **App Store** are built in and can't be removed. Other apps are installed per character from the App Store. A new phone comes with Flock, Bank, Garage and Calculator. Marketplace and Notes are installed from the store. Apps that aren't built yet are not listed. Change the list, labels and what comes preinstalled in `PhoneConfig.Apps`.

| App | What it does | Where the data lives |
|---|---|---|
| **App Store** | Browse apps by category, with a detail page; Get / Remove / Open. | `settings.installed` (validated: only real, removable apps). |
| **Flock** | Original social feed. See below. | `veyl_phone_flock_*` tables. |
| **Bank** | Balance (with a hide toggle), cash on hand, recent activity and full history. **Send money** to a phone number, a contact or a bank account number. | Core ledger (see below). |
| **Garage** | Every vehicle you own, with its picture, plate, state, fuel/engine/body, place and impound fee. The pin sets a waypoint. | Read-only from `veyl_vehicles`; garage locations from `veyl_garages`. |
| **Marketplace** | Classified listings in Vehicles, Items, Services, Property and Other, plus *My listings*. A listing shows the seller's phone number, with **Message** and **Call** buttons. | `veyl_phone_market`. |
| **Notes** | Private notes with search. The title comes from the first line if you leave it blank. Notes save when you go back. | `veyl_phone_notes`. Up to 100 per character. |
| **Calculator** | Chained operations, %, ±, keyboard input. Dividing by zero shows Error. | On the phone only. |

**Flock:**
- **Profile:** one `@handle` per character (3–15 letters, numbers or _), with a display name and bio.
- **Posts:** 280 characters. Replies (one level deep) and likes.
- **Feeds:** Everyone and Following. Profiles show post and follower counts.
- **Notifications:** replying to someone or @mentioning them (existing handles only) sends them a notification that opens the post.
- **Moderation:** you can delete your own posts; staff with the core `admin` permission can remove any post, and the removal is logged.

**Bank transfers:**
- They use the same ledger as `veyl_banking`.
- The recipient is looked up on the server and shown by name before you confirm, and the confirmation expires after 90 s.
- Each send carries a request id. A retry with the same id can never pay twice, and "Check status" tells you whether a send that timed out went through.
- Each transfer is capped at `PhoneConfig.Bank.MaxTransfer`.
- The recipient gets a phone notification.
- Deposits and withdrawals still need a bank or ATM.

**Garage waypoints:**
- **Parked:** the waypoint goes to the vehicle's garage.
- **Impounded:** it goes to the impound lot.
- **Out on the road:** it goes to the vehicle's live position, which `veyl_vehicles` only reveals to the owner.

**Marketplace rules:**
- Listings expire after 7 days.
- Each player can have up to 5 active listings.
- No money moves through the app.
- Sellers can remove their own listings; staff can remove any.

### Exports added for the phone

| Resource | Export | Returns |
|---|---|---|
| `veyl_garages` | `GetPlaces()` | `{ id, label, kind, x, y, z }` for each garage and the impound lot. |
| `veyl_vehicles` | `GetOwnedVehicleCoords(citizenid, ownedId)` (async) | The live position, only for that owner's vehicle while it is out. |

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
| App server code (App Store, Notes, Flock, Bank, Garage, Marketplace) against real MariaDB | 61 checks passed |
| App browser flows: install/remove, Flock post/like/reply/profile/handle setup, Bank send with balance update, Garage pictures and waypoints, Marketplace filter/post/message seller, Notes save, Calculator, error state | 37 flows passed |
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
- **Not built yet (hidden):** business directory, jobs, services/dispatch, maps, properties, deliveries, events and criminal contacts.
- **Flock:** no images. Posts are text only, because there is no screenshot resource.
- **Badges:** held in memory. Resources should re-send them on `veyl_phone:sessionStarted`.

## In-hand prop

The phone in the player's hand is `sd_phone_black` from the **sd-phone** prop pack (Samuels Development, streamed models only; it is not a phone script and does not conflict with `veyl_phone`). Start it before the phone:

```
ensure sd-phone
ensure veyl_phone
```

The model welds to the right hand (bone 28422) at zero offset, like GTA's own phone. If the pack is not running, the base-game `prop_npc_phone_02` is used (`Animations.prop` / `fallbackProp` in `config.lua`). Other colours from the pack (`sd_phone_blue`, `sd_phone_red`, …) work the same way.
