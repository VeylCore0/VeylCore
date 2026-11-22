# Moving from QBCore or QBox (`veyl_migrate`)

Imports characters from the QBCore / QBox tables (`players`, `player_vehicles`) in the same database.

1. **Back up the database** (`tools/backup-db.ps1`, see [OPERATIONS.md](OPERATIONS.md)).
2. Start VeylCore once so its tables exist, then `ensure veyl_migrate`.
3. In the server console: `veylmigrate` — a **dry run** that changes nothing and reports how many characters, items, vehicles and dollars would move, plus any items and jobs VeylCore does not know.
4. Add missing items to `veyl_inventory/data/items.lua` or jobs to `veyl_core/shared/jobs.lua` if you want them kept, and run the dry run again.
5. `veylmigrate apply` to import. Remove `veyl_migrate` from server.cfg afterwards.

| Imported | From |
|---|---|
| Account | `license` (the same Rockstar licence VeylCore uses) |
| Character | `charinfo` (name, birth date, gender, nationality, phone), citizen ID kept |
| Money | cash, bank, crypto |
| Job / gang | name and grade, when it exists in VeylCore (otherwise unemployed / none) |
| Status | hunger, thirst, stress, licences, callsign, handcuffs; last position |
| Inventory | qb-inventory and ox_inventory layouts, items that exist in VeylCore |
| Vehicles | model, plate, mods, garage, fuel, engine, body; impounded stays impounded |

Characters whose citizen ID already exists in VeylCore are skipped, so running it twice never duplicates anything. Phone data, apartments, stashes and trunks are not imported.
