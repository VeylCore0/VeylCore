# City Hall (`veyl_cityhall`)

The City Hall desk handles identity documents, licences and the job board. Talk to the clerk and choose **City services**.

```
ensure veyl_cityhall   # after veyl_inventory and veyl_interact
```

The desk is at the Alta Street civic offices by default (`Desk.coords` in `config.lua`). If you use a City Hall MLO, move the clerk there.

## What players can do

| Tab | What it does |
|---|---|
| **Identity** | Shows the character's details and prints cards: an identity card, and driver's or weapon licence cards for licences the character holds. |
| **Licences** | Shows which licences the character holds. Licences with a price can be bought here; the rest show "Not sold here". |
| **Job board** | Lists the jobs in `JobBoard` with their pay per rank. Jobs marked `open = true` in `veyl_core/shared/jobs.lua` can be taken on the spot. Every job can set a GPS waypoint. |

Using a card from the inventory shows it to everyone within `ShowDistance` (3 m) for `ShowSeconds` (8 s). The card appears on the right of their screen and never takes focus.

## Payments

Each purchase is one core `DebitOnce` keyed `cityhall:<citizenid>:<op id>`. The card is then given with `GiveItem` using the same id plus `:item`. If the card cannot be delivered, the fee is refunded once (`:refund`). Pressing a button twice, or a timeout followed by a retry, never charges twice.

## Licences

Licences are stored on the character as `metadata.licences` (`driver`, `weapon`, `business`). Set `price = nil` on a licence to stop City Hall selling it.

`/licence <server id> <licence> <on|off>` grants or revokes a licence. It is allowed for:

- staff with `veyl.cityhall.manage` or `veyl.admin` (from anywhere);
- on-duty members of the groups in `GrantGroups` for that licence, standing within 10 m of the person. By default, police rank 2 and up can grant weapon licences and rank 1 and up can grant driver's licences.

```
add_ace group.admin veyl.cityhall.manage allow   # or veyl.admin, which also works
```

Every purchase, job change and licence change is written to the audit log.

## Items

`identity_card`, `driver_license` and `weapon_license` are defined in `veyl_inventory/data/items.lua`. The licence cards use the `licence_card` metadata schema (name, birth date, citizen ID, issue date).
