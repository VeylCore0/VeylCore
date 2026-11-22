# Running a VeylCore server: restart, backup, clean install

## Health check

`veylcheck` in the server console (it also runs once, a minute after start):
- every `veyl_*` resource started and **ready** (a resource that failed its startup says NOT READY);
- `oxmysql` and `pma-voice` running;
- each resource's **database tables** present, migrations applied, character count;
- **OneSync** on, game build set, pma-voice overlay off, `spawnmanager` not running;
- items without a **picture** (they show a placeholder icon).

It ends with *Healthy* or *Needs attention* and a count of failures and warnings.

## Backups

```
powershell -ExecutionPolicy Bypass -File tools\backup-db.ps1 -ServerCfg ..\server\server.cfg
```

Reads `mysql_connection_string` from server.cfg, finds `mysqldump` (XAMPP, MariaDB or PATH; `-MySqlDump <path>` to choose), writes `backups\veylcore_<db>_<date>.sql` and keeps the newest 14 (`-Keep`). Schedule it with Windows Task Scheduler (daily, and before every update). Restore with `mysql -u <user> -p <db> < file.sql` while the server is stopped.

## Before a restart or update

1. Back up the database.
2. Update the code (`git pull`, or a new recipe pin).
3. Restart the **whole server** (not single resources): the HUD detects voice once, and new migrations run at start.
4. Run `veylcheck` and read any failures.

## Clean install checklist

1. txAdmin → recipe (`recipe.yaml`), OneSync on.
2. Start once. Every resource creates its own tables (no SQL import).
3. `veylcheck` → *Healthy*.
4. Give yourself admin: `add_principal identifier.fivem:<id> group.admin` in server.cfg.
5. In game: create a character, City Hall ID card, `/duty` as police, a test 911 call, a death and revive.
6. Move locations that depend on MLOs (hospital beds, business points, prison) in their `config.lua`.
