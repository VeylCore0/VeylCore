# Pinned runtime and dependencies

Pin exact versions. Never track moving branches on a live server: an upstream update can break an untested bridge.

| Component | Pinned version | Source |
| --- | --- | --- |
| GTA V game build | 3751 (`sv_enforceGameBuild 3751`) | — |
| FXServer artifact | The dev server's artifact (bundled with txAdmin 8.1.2). Record the exact artifact number on release | https://runtime.fivem.net/artifacts/fivem/build_server_windows/master/ |
| Database | MariaDB 10.4.32 (XAMPP) | — |
| oxmysql | v2.14.3 | https://github.com/overextended/oxmysql/releases/tag/v2.14.3 |
| ox_lib | v3.42.2 | https://github.com/overextended/ox_lib/releases/tag/v3.42.2 |
| ox_target | v1.18.1 | https://github.com/overextended/ox_target/releases/tag/v1.18.1 |
| ox_inventory | v2.48.1 + `integrations/install-ox-integration.ps1` | https://github.com/overextended/ox_inventory/releases/tag/v2.48.1 |

## ox_inventory integration notes

- The bridge lives in `ox_inventory/modules/bridge/veyl/`. ox loads it dynamically because of `setr inventory:framework "veyl"`,
  so none of ox's own code files are patched.
- `set inventory:accounts "[]"` turns off money items. VeylCore keeps numeric cash, bank and crypto in `veyl_core`.
- `data/shops.lua` is replaced with `return {}`, and the original is kept as `shops.lua.veyl-backup`. ox's default
  shops charge money items; `veyl_shops` sells instead.
- `data/items.lua` gets VeylCore items appended between marker comments (`sandwich`, `coffee`, `qbexample_token`).
- At startup the bridge waits up to 60 s for `veyl_core` and `veyl_vehicles` to be ready, because ox reads
  `veyl_players` and `veyl_player_vehicles` during setup.

When you upgrade ox_inventory, re-run the installer and re-test the acceptance checklist before using the new version.
