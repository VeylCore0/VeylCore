# Police (`veyl_police`)

Cuffs, escort, vehicles, searches, citations, impound and duty points for on-duty officers (`Jobs` in `config.lua`, default `police`).

```
ensure veyl_police   # after veyl_inventory, veyl_vehicles, veyl_interact and veyl_target
```

## Duty

The **Go on / off duty** spot at Mission Row (`Stations`), or `/duty` anywhere. Every option below needs you on duty. Dispatch (F6, Y, F9) is in [DISPATCH.md](DISPATCH.md).

## On a person (target key)

| Option | When | What happens |
|---|---|---|
| **Cuff** | Not cuffed, not in a vehicle | Paired arrest animation (3.5 s), then cuffed |
| **Uncuff** | Cuffed | Handcuffs off |
| **Escort / let go** | Cuffed or downed | They are attached at your side and move with you; select again to let go |
| **Search** | Cuffed or downed (`SearchRequires`) | Their pockets open beside yours; take or give items. Closes if you walk away or they are released |
| **Write citation** | Anyone | Amount and reason. Charged to their bank if it covers it, otherwise left unpaid |

**Cuffed players** keep their hands behind their back, can walk but not run, jump, fight, enter vehicles or use weapons, and cannot open the inventory, phone, emotes or target menus. Cuffs survive logging out (`metadata.ishandcuffed`).

## On a vehicle

| Option | What happens |
|---|---|
| **Place in vehicle** | The person you are escorting goes into a free rear seat |
| **Take out of vehicle** | Everyone cuffed or downed in it gets out |
| **Impound** | 8 s, vehicle must be empty. Owned vehicles go to the impound lot ($750 to release); other vehicles are removed |

## Citations

Stored in `veyl_police_citations` (amount, reason, officer, paid or unpaid). Players pay unpaid ones with `/citations`. The MDT shows a person's citations.

## Staff

`/uncuff <id>`: needs `veyl.police.manage` or `veyl.admin`.

## For other resources

Server exports: `IsCuffed(src)`, `SetCuffed(src, on)`, `GetCitations(citizenid, limit)`.
State bags (readable by every client): `cuffed`, `escortedBy`.

Every cuff, uncuff, search, citation and impound is written to the audit log.

## Not included yet

An armory, police vehicles and evidence. The armory can be a `veyl_shops` shop limited to the police job (`groups`).
