# Pinned runtime and dependencies

Pin exact versions and never track moving branches on a live server.

## Native profile (current)

| Component | Pinned version | Notes |
| --- | --- | --- |
| GTA V game build | 3751 (`sv_enforceGameBuild 3751`) | |
| FXServer artifact | Dev server artifact (bundled with txAdmin 8.1.2) | Record the exact artifact number on release |
| Database | MariaDB 10.4.32 (XAMPP) | |
| oxmysql | v2.14.3 | SQL driver only. Building a driver is outside the plan's scope |
| pma-voice | commit 6c9d96e (main, Jun 2026; reports 7.0.1) | Proximity voice and phone calls. The last tagged release (v6.6.2) is from 2022. See [VOICE.md](VOICE.md) |
| veyl_lib / veyl_target / veyl_inventory | 0.3.0 (this repo) | First sprint. See [API-STATUS.md](API-STATUS.md) |
| UI build toolchain (build time only) | Node 18+, react 18.3.1, vite 5.4.11, typescript 5.6.3, @vitejs/plugin-react 4.3.4, @fontsource/inter 5.1.0 | Compiled output is committed in each resource's `web/dist` |

ox_lib, ox_target and ox_inventory are **not** used. They must not run beside the native profile. In particular,
ox_inventory and veyl_inventory must never both own a character's items.

## Transitional ox profile (v0.2, commit 9715b7a)

This profile was tested to boot cleanly on Nov 20, 2026 with:
- oxmysql v2.14.3, ox_lib v3.42.2, ox_target v1.18.1 and ox_inventory v2.48.1
- `integrations/ox_inventory` (installed with `integrations/install-ox-integration.ps1`)
- `setr inventory:framework "veyl"` and `set inventory:accounts "[]"`

Use it only to roll back. Inventory data does not move automatically between the two profiles: the converter is planned
for phase 7.
