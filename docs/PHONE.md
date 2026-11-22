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
- **Camera and gallery:** needs the free `screenshot-basic` resource. Without it the Camera app shows "The server needs the screenshot-basic resource for photos". No selfies yet.
- **Not built yet:** business directory, deliveries, events, criminal contacts, photo messages and vehicle insurance.
- **Flock:** no images. Posts are text only, because there is no screenshot resource.
- **Badges:** held in memory. Resources should re-send them on `veyl_phone:sessionStarted`.

## In-hand prop

The phone in the player's hand is `sd_phone_black` from the **sd-phone** prop pack (Samuels Development, streamed models only; it is not a phone script and does not conflict with `veyl_phone`). Start it before the phone:

```
ensure sd-phone
ensure veyl_phone
```

The model welds to the right hand (bone 28422) at zero offset, like GTA's own phone. If the pack is not running, the base-game `prop_npc_phone_02` is used (`Animations.prop` / `fallbackProp` in `config.lua`). Other colours from the pack (`sd_phone_blue`, `sd_phone_red`, …) work the same way.

## Phone 2.0, phase 1

New apps (preinstalled):

| App | What it does |
|---|---|
| **Maps** | City places (City Hall, hospital, police, LS Customs, impound, Bean Machine, Burger Shot…, `MapPlaces`), your saved places (save where you stand), and locations shared with you. *Share* sends your location (or live location, which follows you) to a phone number for 15 / 30 / 60 min. Tap anything to set GPS |
| **Services** | Request Police, EMS, Mechanic, Taxi, Bean Machine or Burger Shot (`Services`) with a message: police / EMS requests also become dispatch calls; every on-duty member gets a notification. On duty yourself? The **Queue** tab lists open requests: *Take it* (GPS + tells the caller you are coming), *Close* |
| **Mail** | Inbox. Citations, medical bills, City Hall receipts and job offers arrive here |
| **Voicemail** | Messages left for you, and leaving one for any number (blocked numbers are silently ignored) |

Settings → Wallpaper & colour also has **Theme** (dark / light) and **Phone case**, the colour of the `sd_phone_<colour>` prop in your hand.

Other resources can send mail, also to offline characters:

```lua
exports.veyl_phone:SendMail(citizenid, 'Sender name', 'Subject', 'Body text')
```

Tables: `veyl_phone_places`, `veyl_phone_shared_locations`, `veyl_phone_service_requests`, `veyl_phone_mail`, `veyl_phone_voicemail` (migration `003_phone2`).

## Phone 2.0, phase 2

| App | What it does |
|---|---|
| **Camera** | Takes a photo of the game view with `screenshot-basic` (`ensure screenshot-basic` before `veyl_phone`) and saves it to the **Gallery** tab (up to `Camera.Max`, JPEG quality `Camera.Quality`). Tap a photo to view or delete it |
| **Jobs** | Your jobs with grade and pay, *Clock in / out*, *Make main*. The **Job board** lists City Hall's board (`exports.veyl_cityhall:GetJobBoard()`); jobs you cannot walk into get *Apply*. Bosses get an **Applicants** tab and a notification for each application |
| **Bills** | Unpaid mechanic invoices and police citations, paid from the bank with the same operation ids as the in-person flows (`invoice:<id>`, `citation:<id>`), so a bill is never charged twice. **Standing orders** to any phone number every 1–30 days (checked every 5 minutes; three failures cancel it). **Credit score** 300–850 from bills paid, bills unpaid, failed standing orders and bank balance |
| **Music** | Built-in stations generated in the phone (Veyl Radio, Lo-Fi Beach, Night Drive) plus any internet radio in `Music.Stations`. Keeps playing with the phone closed. **Speaker on** plays it for everyone within `Music.SpeakerRange` m, louder the closer they are |
| **News** | Weazel News stories. On-duty `weazel` job members (`News.Jobs`) get a pen button; *Breaking news* notifies every online phone |
| **Racing** | **+** records a track: drive it and tap *Add checkpoint* (2–40). *Host* opens a race; players within `Racing.JoinRadius` m of the start *Join*; the host *Starts* (5 s countdown). Checkpoints are checked by the server (position, order, start time); finish times go to the leaderboard (*Times*). `/quitrace` leaves |

**Installing screenshot-basic:** the GitHub repo (`citizenfx/screenshot-basic`) has no built files and normally builds itself at startup with FXServer's `yarn` / `webpack` resources. To avoid needing those, build it once: `npm install --ignore-scripts`, then run webpack 4 on `client.config.js`, `server.config.js` and `ui.config.js` (Node 17+ needs `NODE_OPTIONS=--openssl-legacy-provider`). Copy `dist/client.js`, `dist/server.js` and `dist/ui.html` into `resources/[standalone]/screenshot-basic/dist/` with an fxmanifest that drops the `dependency 'yarn'`, `dependency 'webpack'` and `webpack_config` lines.

**Garage:** parked vehicles have a key button for **valet delivery**: the vehicle is brought to the nearest road (within 80 m) for `Valet.Fee` from the bank; refunded if it cannot be spawned.

**Tablet:** the `tablet` item opens a menu: **MDT** and **Dispatch** for police / EMS, **My home** (apartments) and the phone. Give it with your admin tools; the image is a placeholder copy of `phone.png`.

The Weazel News job (`weazel`: Reporter, Senior Reporter, Editor in Chief) is in `veyl_core/shared/jobs.lua` and on the City Hall job board.

Tables: `veyl_phone_photos`, `veyl_phone_job_apps`, `veyl_phone_standing`, `veyl_phone_news`, `veyl_phone_race_tracks`, `veyl_phone_race_results` (migration `004_phone3`).

Checked here: Lua parses, the page type-checks and builds, the new tables and their queries run on MariaDB. Not checked in game yet: photos (needs screenshot-basic), valet spawn, speaker audio between two players, a full race with two players, and the tablet menu.

## Phone shell 2 (visual redesign)

Same resource, same data, same server APIs and exports: only the shell and the home screen were rebuilt.

- **Device:** taller phone with thin even bezels, a dark titanium frame with side buttons, rounded screen corners. Size (75–130 %), corner (bottom right / middle right / bottom left) and a fine **Move left/right** and **Move up/down** offset (±30 % of the screen) are in Settings → Size & position. **Text size** (small / default / large) is there too.
- **Dynamic Island:** a black pill at the top. During a call it widens to show the caller and the call time (or "Calling…"); tap it for mute, open call and hang up. It goes back to the pill when the call ends. It replaces the old green call bar.
- **Status bar:** game time on the left; Do Not Disturb / silent, signal, Wi-Fi and battery on the right. **Signal and battery are cosmetic** (always full): there is no signal or battery simulation, so nothing pretends to drain or charge.
- **Home:** Weather widget (the area you are in and the server weather; no temperature, because the server has no temperature and the phone will not invent one) and Calendar widget (weekday, date, month from the server clock). Apps on pages of 4 × 4 with page dots (scroll, swipe or tap a dot), a **Search** pill (Enter opens the first match), folders, and a frosted dock with Phone, Messages, Contacts and Settings. The home indicator sits under the dock.
- **Rearranging:** hold an app to enter edit mode, then **drag it onto another spot**; tap an app in edit mode for *Move earlier / later*, folders, or *Remove from folder*. Settings → Home screen → *Reset home screen layout*. The layout is saved per character.
- **Icons:** squircle icons with a soft gradient from each app's colour. Apartments, Boosting, Silk Road and Invoices (registered by veyl_apartments, veyl_boosting, veyl_crime and veyl_mechanic) now have matching icons.
- **Wallpaper:** new default **Sunset** (purple to peach with an original hills-and-towers silhouette). Existing phones keep the wallpaper they chose.

Settings added (validated on the server with safe defaults for older phones): , , , .

**Not in this pass** (listed so nothing pretends to work): photo / location messages and Flock images (no image sharing yet), recorded voicemail audio (Voicemail holds written messages, not recordings), a drawn map in Maps (it lists places and sets GPS), direct purchases in Marketplace (listings are classified ads), contact avatars and favourites. These need new work or a media/voice recording provider.

**Checked here:** the page type-checks and builds; the server settings code parses. Not checked in game yet: the look at 1080p / 1440p / 4K / ultrawide, the Dynamic Island during a real call, drag-to-reorder, and the position offsets.
