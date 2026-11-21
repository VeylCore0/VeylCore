# VeylCore UI suite: Inventory, Shop, Banking, HUD and Target

Five interfaces built from the concept images in `packages/preview/public/concepts/`. All five use one design system,
`packages/veyl-ui`, which holds the tokens, the V mark and wordmark, line icons, controls, localization strings and
message types.

They are written in React + TypeScript and built with Vite. Each resource ships its compiled `web/dist`, so a server
never needs Node.

| Screen | Resource | Opens with | Focus |
| --- | --- | --- | --- |
| Inventory | `veyl_inventory` | **F2** (rebindable); stash target/E prompt | Modal (veyl_lib token) |
| Shop | `veyl_shops` | Target the 24/7 clerk → *Shop at 24/7 Supermarket* | Modal |
| Banking | `veyl_banking` | Target a Fleeca counter → *Use bank* | Modal |
| HUD | `veyl_hud` | Always on once a character is loaded; `/hud`, `/hudsettings` | Passive (never focused) |
| Target | `veyl_target` | Hold **Left Alt**; scroll/arrows to choose; **E** or click | Passive overlay |

Modal screens use `vlib.createScreen` (veyl_lib). It:
- requests a focus token, so only one modal can own input;
- waits up to 5 s for the page, then gives up with a clear message instead of a black screen;
- always releases focus on Escape, Close, revoke, broker reset, death, logout and resource stop.

Every NUI request is resolved with `{ ok, code?, message?, data? }`.

## Message envelope

- **Lua → NUI:** `SendNUIMessage({ action, session, data })`. `session` changes every time a screen opens.
- **NUI → Lua:** `POST https://<own resource>/<action>` with `{ v: 1, requestId, ...payload }`.
- TypeScript types live in [`packages/veyl-ui/src/messages.ts`](../packages/veyl-ui/src/messages.ts). Lua validates every field it reads.

### Inventory (`veyl_inventory`)

| Lua → NUI | Data |
| --- | --- |
| `inventory:open` | `InventoryOpen` (primary, secondary?, items, imagePath, hotbarSlots) |
| `inventory:delta` / `inventory:snapshot` | server-confirmed changes only |
| `inventory:close` | — |

| NUI → Lua | Payload | Server callback |
| --- | --- | --- |
| `move` | `{ opId, from{ref,slot}, to{ref,slot}, count?, revisions }` | `veyl_inventory:move` (locked transaction; `STALE` → snapshot) |
| `use` | `{ slot }` | `useStart` → progress → `useComplete` (reserved, server-timed) |
| `nearby` | — | `veyl_inventory:nearby` (≤ 3 m, same routing bucket) |
| `give` | `{ opId, slot, count, target, revision }` | `veyl_inventory:give` (re-checks recipient, then transfers) |
| `close` | — | `veyl_inventory:close` |

Hotbar keys **1–5** use the items in personal slots 1–5. They only reference those slots; nothing is copied.

### Shop (`veyl_shops`)

| NUI → Lua | Payload | Notes |
| --- | --- | --- |
| `checkout` | `{ opId, method, lines: [{ index, count }], expectedTotal }` | The server recomputes prices. If they changed it returns `PRICE_CHANGED` and a fresh catalog. A timeout leads to a `status(opId)` query before reporting failure |

Settlement (`veyl_shop_checkouts`):
1. One `DebitOnce` covers the whole basket.
2. Each line is granted with operation `<checkout>:<n>`.
3. Only a line whose grant provably failed is refunded, using `<line>:refund`.
4. Interrupted checkouts are reconciled at startup and every 10 minutes.
5. Repeating a request with the same op id returns the stored result.

### Banking (`veyl_banking`)

| NUI → Lua | Payload |
| --- | --- |
| `overview` | — |
| `history` | `{ offset, filter: 'all' \| 'in' \| 'out' }` (10 per page) |
| `deposit` / `withdraw` | `{ amount, opId }` (whole dollars) |
| `resolveRecipient` | `{ account }` → `{ token, name, accountMasked }` (token valid for 90 s) |
| `transfer` | `{ token, amount, reference, opId }` |

All money goes through `veyl_core` (`TransferMoney` with `bank:<citizenid>:<opId>`). A timed-out request is checked
with `status(opId)` before the UI reports it.

New core exports:
- `GetMoneyHistoryPage(citizenid, limit, offset, direction)`
- `ResolveBankAccount(account)`, which returns only a masked name

### HUD (`veyl_hud`)

`hud:frame` sends a partial `HudFrame`. Each section is sent only when it changes:

| Section | Update rule |
| --- | --- |
| `vehicle` | every 100 ms while in a vehicle; `false` on foot |
| `compass` | when the heading moves by 1° or more |
| `status`, `voice`, `info`, `settings` | every 250 ms, sent only if changed |
| `minimap` | rectangle measured every 2 s; `false` when the radar is hidden |

Providers:
- **Voice:** pma-voice is auto-detected once and supplies the range. Otherwise the HUD shows native talking only, with range unavailable.
- **Fuel:** the `veylFuel` state bag, falling back to the game's fuel level.
- **Seatbelt:** `veyl_vehicles` provides one (key **B**, rebindable). It publishes `LocalPlayer.state.seatbelt`, which the HUD reads
  (`HudConfig.Seatbelt = 'statebag'`). Buckled: you can't exit until you unbuckle. Unbuckled: a hard crash above 45 mph ejects you.

### Target (`veyl_target`)

`target:state` carries:
- `active`, `options[{ index, label, icon }]` and `selected`;
- `title`: the zone's `title`, otherwise Vehicle, Person, Player, Object or Area;
- `state` and `stateIcon`, e.g. Locked or Unlocked;
- `keys`: the labels from `TargetConfig.KeyLabels`.

The NUI never chooses an action: Lua resolves the selected option index from its own registry.

`veyl_vehiclekeys` registers these vehicle options:
- **Unlock** or **Lock vehicle**, only when you hold the key and the lock state matches;
- **Inspect vehicle**.

## Browser preview (development only)

```bash
npm install
npm run preview        # http://localhost:5173
```

The bar at the bottom offers:
- a screen selector;
- states: normal, loading, empty, error, restricted, pending;
- a blurred concept backdrop and a **compare** slider that overlays the concept image;
- **reopen**.

Preview data is in `packages/preview/src/fixtures.ts`. It goes through `setDevNuiHandler`, which only works outside FiveM,
so it can never fake success in production.

## Tests run (Nov 20, 2026)

| Check | Result |
| --- | --- |
| `npm run build` (6 apps: tsc + Vite production build) | ✅ |
| Preview type-check | ✅ |
| Lua syntax check (150 files) | ✅ 0 errors |
| Visual review against the concepts at 1280×720, 1920×1080 and 3440×1440 (headless Chrome screenshots) | ✅ Layouts match. Inventory rows scroll inside the panel at 720p as intended |
| 20 scripted browser-preview interactions (select, drag-move, give dialog, Escape, shop add/pay/clear/out-of-stock, bank deposit validation, confirmed transfer, history paging, error state) | ✅ 20/20, no page errors |
| **In-game (FiveM) checks** | ❌ Not run yet. See the checklist below |

Browser-preview checks prove only the UI behaviour. They do not prove the server side or multiplayer behaviour.

## In-game acceptance checklist

- [ ] Every screen: Escape/Close restores movement; `restart <resource>` while open restores controls; no black overlay
- [ ] Inventory: drag, Shift-click quick transfer, right-click menu, split, give to a player at 1 m / 5 m (5 m refused), hotbar 1–5
- [ ] Two players take the last item from `legion_shared` at once: exactly one succeeds
- [ ] Shop: pay with cash and with bank; a full inventory refunds only undelivered lines; double-click Pay charges once
- [ ] Bank: deposit, withdraw, transfer to a second character's account number; unknown account; insufficient funds; history pages
- [ ] HUD: values update; vehicle display only while driving; MPH/KMH and scale persist after reconnect; minimap frame aligns
  at your resolution and safezone
- [ ] Target: vehicle Locked/Unlocked state and actions; zone titles (Bank, Storage, Fuel pump); options vanish when you walk away

## Known limitations

- **Item art:** PNGs from the RAINMAD image gallery (see `veyl_inventory/web/images/CREDITS.md`); `jacket.svg` is still a
  placeholder. To add an item image, put a PNG/WebP in `veyl_inventory/web/images/` (name it `<item>.png` or set `image =` in
  `data/items.lua`). A missing image shows a deliberate fallback tile.
- **Drop:** shown but disabled with a reason, because ground drops are a later inventory phase. **Open trunk** isn't offered for the same reason (vehicle storage).
- **Shop stock:** stock is unlimited. Finite stock and reservations are planned, and the UI already renders stock and out-of-stock states.
- **Banking:** personal accounts only; there are no business accounts yet.
- **Target:** cursor-selection mode is not implemented; selection uses scroll/arrows and E or click.
- **Voice range:** needs pma-voice.
