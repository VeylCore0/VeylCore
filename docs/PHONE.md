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
  | 'RATE_LIMITED' | 'BUSY' | 'UNAVAILABLE' | 'VOICE_UNAVAILABLE' | 'INVALID_STATE' | 'NO_PERMISSION' | 'DATABASE_ERROR' | 'INTERNAL' | string;
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

### Pushes (`phone:push` → `{ event, data }`)

| event | data | UI behaviour |
|---|---|---|
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

Only show apps that are listed in `hello.apps` (and `installed`) or in `external`. Tapping an external app calls `openExternal`. Routes are free-form strings each app defines, like `phone/recents` from a missed-call notification or `apartments` from the apartments resource. Unknown routes just open the app.

### Rules the UI must keep

- Never trust or invent server state. Every change goes through `api`, and the answer or a push updates the screen.
- Show the server's `message` on errors. Keep inputs within `limits`.
- Respect `settings`:
  - `theme`, `accent`, `wallpaper`, `brightness`, `volume`;
  - `silent` and `dnd`: no sounds;
  - `streamer`: hide your own number;
  - `airplane`: a status icon (the server refuses sends and calls).
- Text from players is plain text. Never render it as HTML.
