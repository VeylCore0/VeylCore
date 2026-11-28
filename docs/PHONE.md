# Phone (`veyl_phone`)

The phone is split in two:

- **The base** (`resources/[veyl]/veyl_phone`, Lua). It owns all data and rules: numbers, settings, apps, notifications, contacts, messages, calls and mail. The server checks every action.
- **The UI** (`packages/phone-ui`, React and Vite). It only displays data and asks the base to do things. Its build output goes to `resources/[veyl]/veyl_phone/web/dist/` (committed, like the other UIs).

The rest of this page is the contract between the two. A UI that follows it needs no Lua changes.

## The phone UI

A tall phone that slides up from the bottom right, with a Dynamic Island for calls, a glass home screen with a time and weather widget, a notification centre (tap the status bar), dark and light themes, five wallpapers, accent colours and phone cases.

**Phone size:** Settings, Appearance, Phone size. Small, Default, Large, or a slider from 60% to 140%. It is saved per character and never grows taller than the screen.

**Share my number:** the share button in Contacts lists people next to you; they get a prompt and choose whether to save you. Range, how long the prompt lasts and the per-person cooldown are in `PhoneConfig.Share`.

Built-in apps: **Phone** (keypad, recents, favourites, full-screen call screen), **Messages** (direct and group chats, read receipts, location and contact cards, new chat), **Contacts**, **Mail**, **App Store**, **Settings**, **Calculator** and **Clock** (city time, stopwatch, timer). Apps that other resources register with `RegisterApp` show up on the home screen on their own.

Escape closes the innermost thing first (a sheet, then a thread, then the app, then the phone). The home bar goes home.

**Previewing and building**

- `npm run preview`, then pick **Phone** in the toolbar. Buttons add a message, a group message, an incoming call, a notification and a mail; the mode box shows the empty, error and no-voice states. The demo backend is `packages/preview/src/phoneMock.ts` and behaves like the real server (replies, read receipts, calls that connect).
- `npm run build -w @veyl/phone-ui` writes the UI into the resource.
- All class names start with `ph-`, and modifiers are namespaced (`k-primary`, `cb-red`...), so no other UI's stylesheet can change the phone.

## For server owners

- **Start order:** `ensure veyl_phone` after `veyl_core`, `veyl_inventory` and `pma-voice`. Calls are disabled, with a message saying why, when pma-voice isn't running.
- **Item:** characters need the `phone` item (`PhoneConfig.RequireItem`) to open the phone and to be reachable. The number belongs to the character, so a new phone item gives back the same number and data.
- **Key:** F1 by default (`PhoneConfig.OpenKey`). Players can rebind it in the FiveM key settings.
- **Data:** the base uses `veyl_ph_*` tables. On first start it copies numbers, display names, contacts and blocked numbers from the previous phone's `veyl_phone_*` tables. It never changes or drops those old tables, so you can delete them yourself once you're happy.
- **Account and PIN:** each character can create an account (an email like `name@veylid.com` and a password) and set a 4-digit PIN. With a PIN on, the phone is locked every time it is opened (after a 10 second grace period), and the **server** refuses every request except answering calls until the PIN is entered; a locked phone is sent no messages, contacts, numbers or apps. Five wrong tries lock it for 5 minutes (stored in the database, so a restart does not reset it). Passwords and PINs are salted and hashed; nothing readable is stored. A forgotten PIN is reset with the account password, or by staff with `phonepinreset <citizenid>` in the server console (or a player with the `phone.admin` permission). Settings are in `PhoneConfig.Account` (email domain, lengths) and `PhoneConfig.Lock` (grace, attempts, lockout).
- **Flock sign up and log in:** Flock opens on a **Sign up / Log in** screen; nothing else in it works until you are logged in (the server refuses every other Flock call with `NOT_LOGGED_IN`). Sign up with a `@handle` (3-15 letters, numbers or `_`), a display name and a password (6-64 characters, typed twice); log in with the handle and password. **Edit profile or log out** is at the bottom of the feed: it edits your handle, name and bio, and has **Log out** (asks first). Passwords are salted and hashed, like the phone account's. Five wrong passwords lock that character out for 5 minutes, and a wrong handle gives the same answer as a wrong password. An account belongs to the handle, not the character: posts, follows and likes stay when you log out, you can log in to the same account from another character, and one character can make or switch between several accounts. A character stays logged in until it logs out (it is stored, so a restart does not log it out). Accounts made before this change get a **Protect @handle** screen the first time their character opens Flock: choose a password and you are logged in (until then nobody can log in to it). Tables: `veyl_phone_flock_profiles.pass_hash` and `veyl_phone_flock_sessions` (migration `v2_008_flock_accounts`).
- **SIM cards:** the SIM is the phone line. It carries the **number and the contacts**; the phone keeps everything else (PIN, settings, mail, photos). A phone without a SIM has no service: no calls, texts, Flock, money transfers and so on, and the status bar says *No SIM*. Notes, contacts, the gallery, settings and the account/PIN screens still work. Buy a `sim_card` (shops, $50), open the inventory and drag the card into the **SIM slot** on the body panel (no menu or tray). The card in that slot is the phone's SIM: drag it out and the service goes. A new card keeps the character's own number. **Taking the SIM out** of the slot takes the number and a copy of the contacts with the card (the card item is marked with its number the first time it goes in), and the phone loses both (it gets a spare number until another SIM goes in). **Whoever inserts that card**, you again or a player you gave it to, gets that number and those contacts. Characters that already had a phone when this shipped keep service. `PhoneConfig.Sim = { Required = true, Item = 'sim_card' }` (`Required = false` turns the feature off). The SIM tray uses the inventory's item hooks: an item definition lists `actions = { { id, label, icon, tray = true } }`; a resource answers the action with `exports.veyl_inventory:RegisterItemAction(item, actionId, fn(ctx))` (`ctx` has `source`, `citizenid`, `item`, `slot`, `metadata`, `arg = { op, slot }`; return `ok, message`) and describes the box with `exports.veyl_inventory:RegisterItemTray(item, actionId, fn(ctx))` (return `{ title, accepts, current?, hint?, emptyLabel?, insertLabel?, removeLabel? }`). The server checks the clicked slot really holds that item.
- **First-run setup:** the first time a character opens the phone they see a short setup (account, then PIN). Every step can be skipped and everything can be done later in Settings, Account & Security.
- **Config:** `config.lua` covers apps, presets (wallpapers, accents, ringtones, themes, cases), limits, call ring time and animations.
- **Tablet item:** using a `tablet` opens a small menu with MDT and Dispatch (for police and EMS), My home, and Phone. It is handled by this resource (`client/tablet.lua`).

## For other resources (stable API)

| Side | Call | Notes |
|---|---|---|
| server | `exports.veyl_phone:Notify(citizenid, { app, title, body?, route?, dedupe? })` → id or nil | Stored, so it works for offline characters. Pushed live when online. A `dedupe` key is stored once only. |
| server | `exports.veyl_phone:SetBadge(citizenid, app, count)` | The number on an app icon. `0` clears it. Stored. |
| server | `exports.veyl_phone:SendMail(citizenid, from, subject, body)` → id or nil | One-way mail (receipts, bills, offers). |
| server | `exports.veyl_phone:SendSystemMessage(number, body)` → boolean | A text from the reserved number `000-0000`, so replies never reach a real player. |
| server | `exports.veyl_phone:GetCitizenByNumber(number)` → citizenid or nil | Accepts `5551234` or `555-1234`. |
| server | `exports.veyl_phone:GetNumber(citizenid)` → `'5551234'` or nil | |
| server | `exports.veyl_phone:GetEmail(citizenid)` → email or nil, `GetCitizenByEmail(email)` → citizenid or nil | The phone account's email (nil until the character creates an account). |
| server | `exports.veyl_phone:IsReachable(citizenid)`, `IsInCall(source)`, `EndCall(source)` | |
| server | event `veyl_phone:sessionStarted (src, session)` / `veyl_phone:sessionEnded (src, session, reason)` | `session = { src, cid, number, name, settings }` |
| client | `exports.veyl_phone:RegisterApp({ id, label, icon?, color?, event })` | A home-screen app owned by your resource. Tapping it closes the phone and triggers `event` on that client. It is removed when your resource stops. |
| client | `exports.veyl_phone:Open(app?, route?)`, `Close()`, `IsOpen()`, `IsInCall()`, `UnregisterApp(id)` | |
| client | event `veyl_phone:openApp (app, route)` | Can also be triggered from the server with `TriggerClientEvent`. |

## UI contract

### Page lifecycle

The page is a `vlib.createScreen` screen named `phone`, with `keepInput` on, so the player can keep walking while it's open.

1. **On load**, POST `ui:ready`. The phone can't open until the page has done this (5 s timeout).
2. **While a text field has focus**, POST `ui:typing` with `{ typing: true }`, and `{ typing: false }` on blur. Otherwise W/A/S/D walk the player while they type.
3. **To close** (Escape, the home bar, a close button), POST `close`. Never just hide yourself.
4. **The page stays loaded while the phone is closed.** It keeps receiving pushes, so it should:
   - play the ringtone;
   - show a small incoming-call banner;
   - show notification peeks in a corner.

   It has no mouse focus in that state. The player presses F1 to open the phone and answer.

POST helper (every callback answers JSON):

```ts
const post = <T = unknown>(name: string, body: unknown = {}) =>
  fetch(`https://veyl_phone/${name}`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) })
    .then((r) => r.json() as Promise<Res<T>>);
```

### Messages to the page

Every message is `window.postMessage({ action, data, session? })`.

| action | data | when |
|---|---|---|
| `phone:session` | `Hello` + `external` | The character loaded, or the phone item was picked up (phone still closed). Store it: number, settings, call state. |
| `phone:open` | `Hello` + `external`, `world`, `open: { app?, route? }` | The phone opens. If `open.app` is set, go straight to that app and route. |
| `phone:close` | none | Closed by the game (key, death, menu, item lost). Go back to the closed state. |
| `phone:navigate` | `{ app, route? }` | Already open, and a script asked for an app. |
| `phone:tick` | `{ world: World }` | Once a second while open (status-bar clock and weather). |
| `phone:apps` | `{ external: ExternalApp[] }` | A resource registered or removed an app. |
| `phone:push` | `{ event, data }` | Live server events (below). |
| `phone:reset` | `{ reason? }` or none | Logout, or the session ended (`no_device`, `logout`, ...). Clear everything. |

### Callbacks from the page

| callback | body | answer |
|---|---|---|
| `ui:ready` | `{}` | `{ ok: true }` |
| `ui:typing` | `{ typing: boolean }` | `{ ok: true }` |
| `close` | `{}` | `{ ok: true }` |
| `api` | `{ name, args: unknown[] }` (at most 4 args) | `Res<T>`: the server's answer (see the API table) |
| `waypoint` | `{ x, y }` | `{ ok, message }`. Sets a GPS waypoint (location messages). |
| `location` | `{}` | `{ ok, data: { label } }`. Street and area where the player stands. |
| `openExternal` | `{ id }` | `{ ok }`. Opens a registered app. The phone closes itself. |

Every answer has this shape:

```ts
type Res<T = unknown> = { ok: boolean; code?: ErrorCode; message?: string; data?: T };
type ErrorCode = 'NO_SESSION' | 'NO_DEVICE' | 'NOT_READY' | 'INVALID_INPUT' | 'NOT_FOUND' | 'ALREADY_EXISTS' | 'LIMIT_REACHED'
  | 'RATE_LIMITED' | 'BUSY' | 'UNAVAILABLE' | 'VOICE_UNAVAILABLE' | 'INVALID_STATE' | 'NO_PERMISSION' | 'DATABASE_ERROR' | 'NO_SERVICE' | 'INTERNAL' | string;
```

On `ok: false`, show `message`: it is written for players. On `ok: true`, `message` (when present) is a short confirmation you may toast.

### Server API (via `api`)

Call as `post('api', { name, args: [...] })`.

**Session and settings**

| name | args | data |
|---|---|---|
| `hello` | none | `Hello` (also starts or refreshes the session) |
| `settingsSave` | `[Partial<Settings>]` | `Settings` (cleaned: unknown keys dropped, bad values reset to the default) |
| `profileSave` | `[name: string]` (2–48 chars) | `{ name }` |
| `appInstall` | `[appId, install: boolean]` | `{ apps: App[] }` (core apps can't be removed) |
| `homeSave` | `[order: string[]]` | `{ home: string[] }` (built-in and external app ids, in home-screen order) |

**Notifications**

| name | args | data |
|---|---|---|
| `notifications` | `[beforeId?]` | `{ items: Notification[], unread, more }` (newest first, one page) |
| `notificationsRead` | `[ids: number[] \| 'all']` | `{ unread }` |
| `notificationsClear` | `[ids: number[] \| 'all']` | `{ unread }` |

**Contacts**

| name | args | data |
|---|---|---|
| `contacts` | none | `Contact[]` (favourites first, then by name) |
| `contactSave` | `[{ id?, name, number, note?, favorite? }]` | `Contact`. Without `id`, saving an existing number updates that contact. |
| `contactDelete` | `[id]` | none |
| `blocks` | none | `{ number, display }[]` |
| `block` | `[number, on: boolean]` | `{ blocked }` |

**Messages**

| name | args | data |
|---|---|---|
| `conversations` | none | `Conversation[]` (latest activity first) |
| `thread` | `[conversationId, beforeId?]` | `{ conversation, messages: Message[] (oldest first), more }` |
| `send` | `[SendInput]` | `{ conversation, message }` |
| `read` | `[conversationId]` | `{ unread }` (total unread messages). Call it when a thread is open and visible. |
| `leave` | `[conversationId]` | none. Leaves a group, or hides a direct chat until the next message. |
| `mute` | `[conversationId, on]` | `{ muted }` |
| `groupCreate` | `[{ name, numbers: string[] }]` | `Conversation` |
| `groupRename` | `[conversationId, name]` | `{ name }` (admins only) |
| `groupAdd` | `[conversationId, number]` | none (admins only) |
| `groupRemove` | `[conversationId, number]` | none (admins only) |

**Calls**

| name | args | data |
|---|---|---|
| `callStart` | `[number]` | `Call` (state `outgoing`) |
| `callAnswer` | `[callId]` | `Call` (state `connected`) |
| `callDecline` | `[callId]` | none |
| `callEnd` | `[callId?]` | none (hang up, or cancel while ringing) |
| `recents` | none | `Recent[]` (last 50) |

**Account and PIN**

| name | args | data |
|---|---|---|
| `unlock` | `[pin]` | The full `Hello` (the phone is unlocked). Errors: `WRONG_PIN` (`data.left` tries), `LOCKED_OUT` (`data.seconds`). Works while locked. |
| `lock` | none | Called by the game when the phone is put away. The next `hello` is locked once the grace period ends. |
| `pinSet` | `[{ pin, current? }]` | `{ hasPin }`. `current` is required to change an existing PIN. |
| `pinRemove` | `[current]` | `{ hasPin: false }` |
| `pinReset` | `[{ password, pin }]` | The full `Hello`. Forgot PIN: the account password proves it is you. `NO_ACCOUNT` when the phone has none. Works while locked. |
| `accountCheck` | `[name]` | `{ available, email?, reason? }`, for live feedback while typing |
| `accountCreate` | `[{ username, password }]` | `{ email }`. Once per phone. |
| `passwordChange` | `[{ current, new }]` | none |
| `setupFinish` | none | none. The first-run setup was finished or skipped. |

While a phone is locked the server answers every other request with `LOCKED`, except `hello`, `unlock`, `lock`, `pinReset` and answering, declining or ending a call.

**Share my number**

| name | args | data |
|---|---|---|
| `nearby` | none | `Nearby[]`: people within `PhoneConfig.Share.Range` (4 m) who have a phone, are not in airplane mode and have not blocked you. Closest first. |
| `shareNumber` | `[serverId]` | none. Sends them a prompt. Refused when too far, blocked, in airplane mode, or sent to the same person in the last 30 s. |
| `shareAnswer` | `[id, accept: boolean]` | `{ saved }`. Accepting saves the sender as a contact (an existing contact is left as it is) and notifies them. A decline is never reported back. |

**Mail**

| name | args | data |
|---|---|---|
| `mailList` | `[beforeId?]` | `{ items: MailItem[], unread, more }` |
| `mailRead` | `[id]` | `Mail & { unread }` (marks it read) |
| `mailDelete` | `[id]` | `{ unread }` |

**Sending messages safely:** create a `clientOp` once per message (8–64 chars, for example `` `${Date.now().toString(36)}-${crypto.randomUUID()}` ``) and reuse it on retries. The server never posts the same `clientOp` twice. Show the message as pending until the answer arrives, then replace it with `data.message`.

### Apps: server calls (`api`)

Every call below needs a live session; with no SIM card (`hello.sim === false`) all but the on-phone tools answer `NO_SERVICE`.

| app | calls (`name(args) → data`) |
|---|---|
| Notes | `notes() → Note[]`, `noteSave({ id?, title, body })`, `noteDelete(id)` |
| Bank | `bankOverview() → { name, bank, cash, account, accountMasked, recent[] }`, `bankHistory(offset) → { rows, nextOffset }`, `bankResolve(target) → { token, name, label }`, `bankSend(token, amount, reference, clientOp)`, `bankStatus(clientOp)` |
| Garage | `garageList() → { vehicles[], valetFee }`, `garageLocate(ownedId) → { x, y, label }`, `garageValet(ownedId, spot)` (the page first calls `valetSpot` for the spot) |
| Marketplace | `marketList(category, beforeId)`, `marketPost({ title, body, price, category })`, `marketDelete(id)` |
| Flock | `flockMe`, `flockSignup(handle, display, password)`, `flockLogin(handle, password)`, `flockLogout`, `flockClaim(password)`, `flockSetup(handle, display, bio)`, `flockFeed(mode, beforeId)`, `flockThread(id)`, `flockUser(handle, beforeId)`, `flockPost({ body, replyTo? })`, `flockLike(id, on)`, `flockDelete(id)`, `flockFollow(handle, on)` |
| Maps | `mapsData() → { saved[], shared[], places[], shareMinutes[] }`, `placeSave(label)` (saves where you stand), `placeDelete(id)`, `shareLocation(number, minutes, live)` |
| Services | `servicesData() → { services[], mine[], duty, queue? }`, `serviceRequest(service, message)`, `serviceTake(id) → { x, y }`, `serviceClose(id)` |
| Voicemail | `voicemailList()`, `voicemailLeave(number, body)`, `voicemailRead(id)`, `voicemailDelete(id)` |
| Camera | `photoSave(dataUrl)`, `photoList()`, `photoGet(id) → { image }`, `photoDelete(id)` |
| Jobs | `jobsData() → { mine[], primary, onduty, jobLabel, board[], apps[], inbox? }`, `jobsDuty()`, `jobsPrimary(name)`, `jobsApply(job, message)`, `jobsAppClose(id)` |
| Bills | `billsData() → { bills[], standing[], score }`, `billPay(kind, id, 'cash' \| 'bank')`, `standingCreate(number, amount, days, note)`, `standingCancel(id)` |
| Music | `speakerPlay(station)`, `speakerStop()` |
| News | `newsList() → { articles[], reporter }`, `newsPost(title, body, breaking)` |
| Racing | `raceData() → { tracks[], open[] }`, `raceBoard(trackId)`, `raceTrackSave(name, points[])`, `raceHost(trackId)`, `raceJoin(id)`, `raceStart(id)` |

Extra client callbacks the apps use (answered by `veyl_phone`'s client script, not the server): `cameraShot` → `{ image }` (needs `screenshot-basic`), `musicStations` → the station list from `PhoneConfig.Music.Stations`, `raceMark` → `{ x, y, z }` of the player or their vehicle, `valetSpot` → the nearest road spot. The page also receives `phone:speakers` (`[{ id, station, volume }]`, other players' phones playing out loud, volume by distance) and should mix one stream per entry.

### Pushes (`phone:push` → `{ event, data }`)

| event | data | UI behaviour |
|---|---|---|
| `sim` | `{ sim, hello? }` | A SIM card went in or came out. Take the fresh `hello` (the number changes with the SIM), clear cached conversations and notifications, and show *No SIM* when `sim` is `false`. Server calls other than the on-phone tools return `NO_SERVICE` while it is `false`. |
| `notification` | `{ notification: Notification, unread, silent }` | Peek banner (play `notifySound` unless `silent`), add it to the list. |
| `badge` | `{ app, count }` | Update the icon badge (`0` = none). |
| `message` | `{ conversation: Conversation, message: Message, silent }` | Upsert the conversation and append the message if that thread is open. If the thread is visible, call `read`. Otherwise show a banner (sound unless `silent`). Messages from blocked numbers never arrive. |
| `read` | `{ conversationId, number, lastReadId }` | Read receipt: messages with `id <= lastReadId` were read by `number`. |
| `conversation` | `{ conversation }` or `{ removed: conversationId }` | Group created, renamed or changed, or you were removed. |
| `call` | `Call` | The single source of truth for the call screen (states below). |
| `mail` | `{ mail: MailItem, unread, silent }` | Banner, then update the inbox. |
| `share` | `ShareRequest` | A nearby player shared their number: show a prompt (save or not), valid until `expires`. Answer with `shareAnswer`. |

**Call states:**

- `incoming`: ring (`ringtone` at `volume` unless `silent`/`dnd`). Show Answer and Decline, even while closed, as a banner.
- `outgoing`: show "Calling...".
- `connected`: in-call screen with a timer from `answeredAt`.
- `ended`: show `reason` for about 2 s, then close the call screen.

Reasons are `cancelled`, `declined`, `timeout`, `hangup`, `busy`, `unavailable`, `dropped` and `voice_failed`.

`callStart` can also fail straight away with `UNAVAILABLE`, `BUSY`, `NOT_FOUND` or `VOICE_UNAVAILABLE`. Show its `message`.

### Types

```ts
type Hello = {
  locked: boolean;           // a PIN is set and not entered: apps/unread/badges are empty and number, name and email are blank
  security: { email?: string | null; hasPin: boolean; setupDone: boolean; grace: number; domain: string; passwordMin: number };
  number: string;            // '5551234'
  display: string;           // '555-1234' (hide it when settings.streamer)
  name: string;              // display name
  settings: Settings;
  apps: App[];               // built-in apps from config (only show `installed` ones on the home screen)
  voice: { available: boolean; provider?: string; reason?: string };
  call: Call | null;         // a call already in progress (reopen into the call screen)
  unread: { messages: number; notifications: number; mail: number };
  badges: Record<string, number>;   // app id -> badge count (any app, including external ones)
  presets: { wallpapers: string[]; accents: string[]; ringtones: string[]; notifySounds: string[]; themes: string[]; cases: string[] };
  limits: { message: number; groupMembers: number; groupName: number; name: number; pageSize: number };
  serverTime: number;        // unix seconds (all `time` fields are unix seconds)
  external?: ExternalApp[];  // added by the client on phone:open / phone:session
  world?: World;             // phone:open only
  open?: { app?: string; route?: string };
};
type Settings = {
  wallpaper: string; accent: string; ringtone: string; notifySound: string; theme: 'dark' | 'light'; case: string;
  volume: number /* 0-100 */; brightness: number /* 20-100 */; size: number /* 60-140, percent of the automatic size */;
  dnd: boolean; airplane: boolean; silent: boolean; streamer: boolean;
  installed: string[];       // non-core apps installed from the App Store
  home: string[];            // home-screen order (empty = default order)
};
type App = { id: string; label: string; description?: string; core: boolean; dock: boolean; installed: boolean };
type ExternalApp = { id: string; label: string; icon: string; color: string };   // icon is a name hint, e.g. 'home', 'car', 'receipt'
type World = { hour: number; minute: number; weather?: string };
type Notification = { id: number; app: string; title: string; body: string; route?: string; read: boolean; time: number };
type Contact = { id: number; name: string; number: string; display: string; note?: string; favorite: boolean };
type Conversation = {
  id: number; kind: 'direct' | 'group'; title: string;   // contact name / formatted number / group name
  peer?: string;                                        // direct: the other number ('0000000' = system messages, no replies)
  members: { number: string; display: string; admin: boolean }[];
  muted: boolean; admin: boolean; unread: number; last: Message | null;
  peerReadId?: number;                                  // direct: the other side has read up to this message id
};
type Message = {
  id: number; conversationId: number; sender: string; senderDisplay?: string; mine: boolean; time: number;
  kind: 'text' | 'location' | 'contact' | 'system';
  body: string;                                         // text; location label; contact name; system line
  payload?: { x: number; y: number } | { number: string; name: string };
};
type SendInput = ({ conversationId: number } | { to: string }) & { clientOp: string } & (
  { kind?: 'text'; body: string } | { kind: 'location'; body?: string } | { kind: 'contact'; payload: { number: string; name?: string } });
type Call = {
  id: number; state: 'incoming' | 'outgoing' | 'connected' | 'ended'; reason?: string;
  peer: { number: string; display: string }; startedAt: number; answeredAt?: number;
};
type Nearby = { id: number; name: string; distance: number };
type ShareRequest = { id: number; from: { name: string; number: string; display: string }; expires: number };
type Recent = { id: number; direction: 'in' | 'out'; number: string; display: string; missed: boolean; reason?: string; time: number; duration: number };
type MailItem = { id: number; from: string; subject: string; preview: string; read: boolean; time: number };
type Mail = { id: number; from: string; subject: string; body: string; read: boolean; time: number };
```

### Built-in apps the UI provides

These come from `PhoneConfig.Apps`:

- **Phone:** dialer, recents and the call screen.
- **Messages, Contacts, Settings, Mail, App Store.**
- **Calculator and Clock:** client-only.
- **Bank, Garage, Maps, Services, Jobs, Bills, Camera, Music, News, Racing, Flock, Marketplace, Notes, Voicemail:** the app calls are listed under *Apps: server calls*.

Only show apps that are listed in `hello.apps` (and `installed`) or in `external`. Tapping an external app calls `openExternal`. Routes are free-form strings each app defines, like `phone/recents` from a missed-call notification or `apartments` from the apartments resource. Unknown routes just open the app.

### Lock screen and setup

- When `hello.locked` is true, draw only the PIN screen and call `unlock`. Do not render anything else, and do not show message or mail text in banners (the UI hides previews whenever a PIN is set and the phone is locked or put away).
- When `hello.security.setupDone` is false (and the phone is not locked), show the setup flow; call `setupFinish` when it is finished or skipped.

### Rules the UI must keep

- Never trust or invent server state. Every change goes through `api`, and the answer or a push updates the screen.
- Show the server's `message` on errors. Keep inputs within `limits`.
- Respect `settings`:
  - `theme`, `accent`, `wallpaper`, `brightness`, `volume`;
  - `silent` and `dnd`: no sounds;
  - `streamer`: hide your own number;
  - `airplane`: a status icon (the server refuses sends and calls).
- Text from players is plain text. Never render it as HTML.
