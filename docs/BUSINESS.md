# Businesses (`veyl_business`)

Player-owned businesses: **Bean Machine** (West Vinewood) and **Burger Shot** (Del Perro). Each is a job (`beanmachine`, `burgershot` in `veyl_core/shared/jobs.lua`).

```
ensure veyl_business   # after veyl_inventory and veyl_interact; veyl_management for hiring
```

## Owning one

At the **Business office**: buy it with a **business licence** (City Hall) and the price from your bank (Bean Machine $75,000, Burger Shot $90,000). You become its Owner (top grade) and it becomes your main job. One business per character. Selling returns 50 %; staff keep their jobs and the business account stays with the business.

Hire, promote and fire staff at the same spot with the boss menu (`veyl_management`).

## Running it

| Point | Who | What |
|---|---|---|
| **Business office** | Managers and the owner | Business account balance, deposit, withdraw, the last 10 transactions |
| | Shift Lead and up (`OrderGrade`) | **Order ingredients**, paid from the business account, delivered to your pockets |
| **Stockroom** | All staff | Shared storage for ingredients and products |
| **Workstations** (espresso machine, sandwich counter, grill, fryer) | On-duty staff | Turn ingredients into products (coffee, sandwiches, burgers, fries) |
| **Register** | On-duty staff | Charge a customer at the counter: they choose card, cash or decline. The sale goes to the business account; the employee earns 10 % commission |

Every account change is in `veyl_business_ledger`. Locations, prices, ingredients and recipes are in `config.lua`; move the points to your MLOs.

## More businesses

| Business | Job | Price | Special |
|---|---|---|---|
| **Hands On Car Wash** (Strawberry) | `carwash` | $60,000 | Two wash bays: drive in, pay $60 (card or cash), the vehicle is cleaned. The money goes to the business account |
| **Bahama Mamas** nightclub | `nightclub` | $150,000 | Bar station mixes cocktails (orange + Sprunk); beer and whiskey are ordered; $50 cover at the door goes to the account |
| **Pawn & Jewelry** (Strawberry) | `pawnshop` | $85,000 | Anyone sells valuables at the counter for cash. With an owner, the account pays the full price and the goods go to the stockroom to resell; with no owner the city pays 60 % and keeps them |
| **Tuner Shop** | `tunershop` | $175,000 | On-duty tuners install performance kits (engine, brakes, transmission, suspension, turbo) on the vehicle in the bay, then charge at the register. Kits are ordered or made at the LS Customs parts bench. The upgrade is saved when the owner parks the vehicle in a garage |

Services are a `services` list in each business's config (`wash`, `cover`, `pawn`, `tune`).
