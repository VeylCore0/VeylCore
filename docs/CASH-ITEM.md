# Cash as an item

Cash shows in your pockets as the **Cash** item (`money`, the cash-roll picture). Your cash balance in `veyl_core` stays the authority (ledger, operation ids, HUD); the item mirrors it both ways (`veyl_inventory/server/cash.lua`):

- **Cash changes in the core** (wages, shops, robbery rewards, fines, ATM withdrawals...): the item count is set to your new balance.
- **The item leaves or enters your pockets through the inventory** (drop it, put it in a stash or trunk, give it to someone, pick it up, a script uses `AddItem` / `GiveItem` with `money`): the same amount is debited or credited in the core with a durable operation id (`invcash:<inventory>:<revision>`), so it can never apply twice.

So you can hand someone cash by giving them the item, stash cash in a trunk or apartment, and drop it on the ground; police and robbers searching pockets see it.

Details:
- The item weighs nothing. One drag moves at most 100,000.
- If your pockets have no free slot when your cash goes up, the item catches up on the next cash change (your balance is still right).
- Change the item name with `InventoryConfig.CashItem` (default `money`).
