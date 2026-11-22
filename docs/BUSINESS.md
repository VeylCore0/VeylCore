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
