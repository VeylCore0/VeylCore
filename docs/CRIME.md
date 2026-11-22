# Crime expansion

```
ensure veyl_crime
ensure veyl_heists
ensure veyl_boosting
```

## Heists (`veyl_heists`)

| Place | Police | Steps | Loot |
|---|---|---|---|
| **Fleeca** ×6 (Legion, Hawick, Del Perro, Rockford, Great Ocean, Route 68) | 3 | Hack the panel (hacking device, 50 % break) → drill 4 deposit boxes (drill) | $1.5k–3.5k marked bills per box |
| **Paleto bank** | 5 | Thermite the vault door → hack → drill 6 boxes | $3.5k–7k per box |
| **Vangelico** | 2 | Smash 12 display cases with a weapon drawn | Watches, chains, rings |

The first step sets off an urgent dispatch call. One bank job at a time; cooldowns 60 min (Fleeca), 120 min (Paleto), 45 min (Vangelico).

## Money

- **Marked bills** (1 bill = $1) from heists. **Laundromat** (Vespucci): wash up to $5,000 at a time for a 30 % fee, every 10 min.
- **Fence** (El Rancho): buys watches $600, chains $400, rings $900 for cash.

## Black market (`veyl_crime`)

Buy a **Black USB Drive** ($5,000 cash) from the shady contact in Vespucci. With it in your pockets, the **Silk Road** phone app (or `/darkweb`) opens: lockpicks, thermite, hacking devices, drills, spray paint, lab chemicals, weapon attachments, unregistered guns (serial *SCRATCHED*) and SMG / rifle ammo. Pay cash; the package waits 30 min at a random **dead drop** (GPS set): search the dumpster. Three open orders at most.

## Drug corners and turf

- Target a local → **Offer drugs**: 65 % buy (1–3 units), 20 % refuse, 15 % call the police (dispatch). Price by product and quality; the brand shows on the sale.
- Products: weed baggies, joints, coke, meth, ecstasy, LSD, Veyl-X.
- **Turf** (Grove Street, Davis, Rancho, Vespucci Beach, Mirror Park, Sandy Shores): sales (+2 rep per unit) and **tags** (use spray paint, +25 rep, once per 30 min per gang) build your gang's rep. The gang with most rep controls the area: its members sell for **20 % more**. Rep fades 10 % a day. `/turf` shows who controls what.
- **Gang stashes:** members-only storage (`GangStashes`).

## Labs and branding

Four labs: meth (Sandy Shores), ecstasy pill press (Vespucci), LSD blotter lab (Grapeseed), Veyl-X (Mount Chiliad). Chemicals from the dark web; each batch has a random quality. `/brand <name>` puts your brand on everything you cook.

## Boosting (`veyl_boosting`)

`/boosting` or the **Boosting** phone app: take a contract (class D–S by your rep, police minimums for higher classes). Find the car in the marked area, **Hotwire** it (lockpick, 15 s) to get the key. Class B and up have a **tracker** that pings the police every 20 s until you **Disable tracker** (hacking device). Deliver at the drop-off (park, get out, *Deliver*): cash by class (less if damaged) and rep. 30 min limit; one contract every 15 min.

## Weapons

- Ammu-Nation guns have a **registered serial** (MDT profiles list them). Black-market guns are SCRATCHED.
- **Attachments** (suppressor, flashlight, extended mag, scope, grip): use one with a weapon drawn; it stays on the weapon. `/removeattachments` takes them off.
