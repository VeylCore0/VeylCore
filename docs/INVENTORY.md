# Inventory (`veyl_inventory`)

Server-owned items in slots, with a three-column screen: your **body and equipment**, your **pockets and backpack**, and whatever is **open beside you** (a stash, a vehicle trunk or glovebox, the ground, or a shop).

Everything is decided on the server. The page can only ask: move this slot to that slot, use this slot, give or drop this stack. Moves are locked, revision-checked and recorded with an operation id, so a repeat never doubles anything and a stale screen cannot overwrite newer state.

## What is where

| Container | Ref | Notes |
|---|---|---|
| Pockets | `primary` | `PlayerSlots`, `PlayerMaxWeight`. The first `HotbarSlots` slots are the number keys. |
| Backpack | `backpack` | `Backpack = { Enabled, Slots, MaxWeight }`. Items can be used, given and dropped from it. |
| Equipment | `equip` | One slot per entry in `Equipment`. A slot only takes an item whose definition has the same `equip`, one at a time. |
| Stash, trunk, glovebox, ground | `secondary` | Registered stashes (`RegisterStash`), keyed stashes (`veyl_vehicles` registers `veh_trunk` and `veh_glovebox`) and ground drops. |
| Shop | (own panel) | Opened by `veyl_shops` when `ShopsConfig.UseInventoryUi` is on. |

Pockets, backpack and equipment all count as "you have it": `GetItemCount`, `Search` and `GetSlotWithItem` look through all three, `TakeItem` takes from the pockets first and then the backpack and what is worn, and `GiveItem` falls back to the backpack when the pockets are full. A phone in its equipment slot still counts for the phone app.

## The screen

- **Body panel:** equipment slots left and right of a body figure (headset, mask, glasses, armour, hat; ID, phone, tablet, key), a cash tile, and personal information (job, name, citizen id, phone number, what you carry against what you can carry).
- **Pockets:** search box and an amount box (0 means the whole stack), category chips, hotbar numbers 1 to `HotbarSlots`.
- **Mouse:** drag to move, `Shift` + click to send across (pockets to storage or backpack, storage to pockets, worn to pockets), double click to use or wear, right click for the menu (use, equip, split, give, move, drop, plus any item actions), hover for a tooltip (description, weight, quality, serial, anything the server stored on the item). `Del` drops, `Esc` closes.
- **Search and categories** only dim non-matching slots; the server state is untouched.

## Config (`config.lua`)

```lua
Backpack = { Enabled = true, Slots = 15, MaxWeight = 15000, Label = 'Backpack' },
Equipment = { { id = 'hat', label = 'Hat', icon = 'hat', side = 'left' }, ... },   -- order is the slot number
Categories = { { id = 'all', label = 'All' }, { id = 'weapons', ... }, ... },
```

The icon names the panel knows: `headset`, `mask`, `glasses`, `shield`, `hat`, `id`, `phone`, `tablet`, `key`. Slot count and weight apply to new characters; for existing ones a slot count only ever grows.

## Items (`data/items.lua`)

```lua
baseball_cap = { label = 'Baseball Cap', description = 'A plain cap.', image = 'baseball_cap.png', weight = 150, stack = false,
    equip = 'hat',                                                   -- which equipment slot it fits
    wear = { kind = 'prop', id = 0, drawable = 9, texture = 0 } },   -- what the character shows while it is worn
```

- `equip` is the slot id from `Equipment`. The server refuses a move into the wrong slot.
- `wear` is applied by the client while the item is equipped (`kind = 'prop'` for hats 0, glasses 1, ears 2; `'component'` for masks and the like; `'armor'` with `amount`). Taking it off puts the slot back how it was. Drawable and texture numbers depend on the ped model, so tune them.
- `category` sets the filter chip; otherwise it is worked out (weapons and ammo, consumables, equipment, goods, other).

## Shops in the inventory

`veyl_shops` still owns prices, stock, licences and money. With `UseInventoryUi = true` its counter opens the inventory with the shop in the right-hand column: pick a product, set the quantity and cash or bank, press Buy. The request goes through the same `checkout` callback and settlement as before (one debit, durable grants, refunds for anything not delivered). Double click buys one. With `false`, or without `veyl_inventory`, the separate shop screen is used.

## Exports

Unchanged, plus: `GetItemCount`, `Search`, `GetSlotWithItem` and `TakeItem` span pockets, backpack and equipment; `CanCarry` and `GiveItem` consider the backpack; `openShop(catalog, shopId)` (client, only accepted from `veyl_shops`).

## Tests

The server logic runs against a real MariaDB with the framework stubbed (`26 checks`): container loading, slot rules (right slot, wrong slot, one at a time, no cross-player access), backpack weight, counts and takes across containers, give falling back to the backpack, persistence after a reload, and unloading. The page flows (equip by drag and double click, menus, filters, search, shift-click, shop buying) pass 21 checks in the preview.

Not tested in game: the wearable props on a real ped (drawable numbers), hover and drag in CEF at your resolution, and the shop panel against a live `veyl_shops`.
