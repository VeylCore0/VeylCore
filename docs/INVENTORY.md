# Inventory (`veyl_inventory`)

Server-owned items in slots, with a three-column screen: your **body and equipment**, your **pockets and backpack**, and whatever is **open beside you** (a stash, a vehicle trunk or glovebox, the ground, or a shop).

Everything is decided on the server. The page can only ask: move this slot to that slot, use this slot, give or drop this stack. Moves are locked, revision-checked and recorded with an operation id, so a repeat never doubles anything and a stale screen cannot overwrite newer state.

## What is where

| Container | Ref | Notes |
|---|---|---|
| Pockets | `primary` | `PlayerSlots`, `PlayerMaxWeight`. The first `HotbarSlots` slots are the number keys. |
| Backpack | `backpack` | `Backpack = { Enabled, Slots, MaxWeight }`. It exists only while a **Backpack item** is worn in the backpack slot of the body panel (drag it in or double-click it); take it off and the panel closes. What is inside stays saved. While it is closed nothing in it can be moved, counted, taken or given to. Items can be used, given and dropped from it. |
| Equipment | `equip` | One slot per entry in `Equipment`. A slot only takes an item whose definition has the same `equip`, one at a time. |
| Stash, trunk, glovebox, ground | `secondary` | Registered stashes (`RegisterStash`), keyed stashes (`veyl_vehicles` registers `veh_trunk` and `veh_glovebox`) and ground drops. |
| Shop | (own panel) | Opened by `veyl_shops` when `ShopsConfig.UseInventoryUi` is on. |

**SIM card:** the SIM slot on the body panel takes only SIM cards. The card in it is the phone's SIM (veyl_phone reads the slot through `GetEquipmentSlot` and follows the inventory's `veyl_inventory:changed` event); the inventory also offers `SetEquipmentMetadata` (write a number on the card) and `PutInEquipment` (place an item in an empty slot) for resources that need them.

Pockets, backpack and equipment all count as "you have it" (the backpack only while it is worn): `GetItemCount`, `Search` and `GetSlotWithItem` look through all three, `TakeItem` takes from the pockets first and then the backpack and what is worn, and `GiveItem` falls back to the backpack when the pockets are full. A phone in its equipment slot still counts for the phone app.

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
headset = { label = 'Headset', description = 'Over-ear headset.', image = 'headset.png', weight = 200, stack = false,
    equip = 'ears',                                                 -- which equipment slot it fits
    wear = { kind = 'prop', id = 2, drawable = 0, texture = 0 } },   -- what the character shows while it is worn
```

- `equip` is the slot id from `Equipment`. The server refuses a move into the wrong slot.
- `wear` is applied by the client while the item is equipped (`kind = 'prop'` for hats 0, glasses 1, ears 2; `'component'` for masks and the like; `'armor'` with `amount`). Taking it off puts the slot back how it was. Drawable and texture numbers depend on the ped model, so tune them.
- `category` sets the filter chip; otherwise it is worked out (weapons and ammo, consumables, equipment, goods, other).

## Hat, glasses and mask come from your look

These three slots are tied to `veyl_appearance`. What your saved look has on shows up as an item (`clothing_hat`, `clothing_glasses`, `clothing_mask`, carrying its style `d` and colour `t`) in the slot, made for you when you load in or when a clothing store, outfit or the editor changes your look. Move the item out of the slot and it comes off your look (saved, and shown straight away); wear one and its style and colour go on your look. Only these three work this way: every other slot is plain inventory. The link is two small exports in `veyl_appearance` (`GetWorn`, `SetWorn`) and a `veyl_appearance:saved` event, so the look stays the single saved record.

## Shops in the inventory

`veyl_shops` still owns prices, stock, licences and money. With `UseInventoryUi = true` its counter opens the inventory with the shop in the right-hand column: pick a product, set the quantity and cash or bank, press Buy. The request goes through the same `checkout` callback and settlement as before (one debit, durable grants, refunds for anything not delivered). Double click buys one. With `false`, or without `veyl_inventory`, the separate shop screen is used.

## Exports

Unchanged, plus: `GetItemCount`, `Search`, `GetSlotWithItem` and `TakeItem` span pockets, backpack and equipment; `CanCarry` and `GiveItem` consider the backpack; `openShop(catalog, shopId)` (client, only accepted from `veyl_shops`).

## Tests

The server logic runs against a real MariaDB with the framework stubbed (52 checks, plus 13 for the SIM sync in veyl_phone): container loading, slot rules (right slot, wrong slot, one at a time, no cross-player access), backpack weight, counts and takes across containers, give falling back to the backpack, persistence after a reload, the backpack opening and closing as the bag is worn and removed, and unloading. The page flows (equip by drag and double click, menus, filters, search, shift-click, shop buying) pass 28 checks in the preview.

Not tested in game: the wearable props on a real ped (drawable numbers), hover and drag in CEF at your resolution, and the shop panel against a live `veyl_shops`.
