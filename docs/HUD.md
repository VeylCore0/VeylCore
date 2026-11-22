# HUD (`veyl_hud`, Ocean Drive)

The player HUD: status, voice, money, location, the native GTA minimap, vehicle instruments for each vehicle type, a settings menu and a position editor. Same resource name as before; nothing else needs to change.

```
ensure pma-voice     # optional, before veyl_hud
ensure veyl_hud      # after veyl_lib and veyl_core
```

## Files

| Path | What it is |
|---|---|
| `config.lua` | Server defaults: providers, vehicle classes and model overrides, hidden GTA components, new-player defaults |
| `bridge/framework.lua` | VeylCore: `Veyl.PlayerData` (money, `metadata.hunger/thirst/stress`), `LocalPlayer.state.isLoggedIn`, `VeylCore:Client:OnPlayerUnload`, `LocalPlayer.state.medical` |
| `bridge/voice.lua` | pma-voice state bags `proximity` and `radioActive`; native `NetworkIsPlayerTalking` fallback |
| `bridge/fuel.lua` | `veyl_fuel` state bag `veylFuel`; `GetVehicleFuelLevel` fallback; `none` |
| `bridge/seatbelt.lua` | Reads `LocalPlayer.state.seatbelt` from `veyl_vehicles/seatbelt.lua` (key B). The HUD adds no seatbelt state or keybind |
| `bridge/postal.lua` | Optional postal dataset |
| `client/settings.lua` | Per-player settings in KVP `veyl_hud:settings:v2` (versioned, validated, clamped; the v1 scale and speed unit are migrated) |
| `client/minimap.lua` | Native radar placement, square / circle, display mode, north-up, restore |
| `client/main.lua` | Update loops, vehicle telemetry, menu and NUI callbacks |
| `packages/hud-ui` | The page (React + Vite, built into `web/dist`) |

Integration points actually used: no exports from other resources are called in update loops. State bags (`proximity`, `radioActive`, `seatbelt`, `medical`, `veylFuel`) and `Veyl.PlayerData` are read; `exports.veyl_lib:RequestFocus / ReleaseFocus / IsModalOpen` are used for the menu's focus.

## What players see

- **On foot:** minimap (bottom left) with the location strip above it (direction, street, postal) and the status group beside it (health, armor, hunger, thirst, stress, stamina, oxygen underwater), voice under it; brand + ID, cash, bank and clock top right.
- **Car:** speed, MPH / KMH, mint RPM arc with a pink redline, gear (`N`, `R`, `-` with the engine off), fuel, engine warning, seatbelt (with an alert beep when unbuckled above 12 mph).
- **Motorcycle:** as the car, without seatbelt.
- **Boat:** ground speed (KTS / MPH / KMH), heading, fuel. No RPM (GTA's boat RPM is not meaningful; `BoatRpm` turns it on), no gears or seatbelt.
- **Helicopter:** **GS** (ground speed: GTA has no airspeed sensor, so it is not called airspeed), altitude **AGL** (height above ground) or **ALT** (world height above sea level), heading, vertical speed in ft/min or m/s, fuel, engine warning.
- **BMX / bicycle:** speed, bicycle icon, speed arc, stamina. No fuel, RPM, engine, gear or seatbelt.
- **Planes and trains:** no instruments (planes are not treated as helicopters).

Values: health uses GTA's offset (100 = dead) and the ped's real maximum; stamina is shown as *remaining* (`100 - GetPlayerSprintStaminaRemaining`, which counts stamina used); oxygen is relative to the air you had when you went under. Unavailable values are hidden, never shown as 0.

## Settings menu

`/hud` (or a key bound in Settings → Key Bindings → FiveM → *Open HUD settings*). Changes preview live; **Save changes** stores them, **Cancel**, **Close** and **Escape** restore the last saved settings, **Reset defaults** previews the defaults until you save.

**Edit HUD positions** (Overview or Minimap): drag the minimap, status, voice, vehicle instruments, top-right info and location strip. Safe-area guides, optional snapping, *Reset* for the selected group, *Save positions* / *Cancel*. Positions are fractions of the screen, clamped to the safe area, so they survive resolution changes. Dragging the minimap moves the real GTA radar.

## Circle minimap

Choose *Circle* in the Minimap tab. It uses GTA's round clip (`SetMinimapClipType(1)`) and a larger circle layout. For a cleaner edge you can add a round mask texture: a `circlemap.ytd` with a texture named `radarmasksm` (the one shipped by the free "circle minimap" resources; check its licence) in `veyl_hud/stream/`. When it is there the HUD swaps it in automatically.

The outline around the map is square-cornered for the square map and round for the circle. If it is a few pixels off at your resolution, drag the map slightly in the position editor.

## Postal codes (optional)

Off by default (no codes are ever invented). To show postals, add your postal map's coordinate list as `veyl_hud/data/postals.json`, a JSON array of `{ "code": "8042", "x": -1200.5, "y": -850.2 }`, and set `HudConfig.Postal.provider = 'file'`.

## Changes from the previous HUD

- Rebuilt layout and styling (Ocean Drive), split into bridges, settings, minimap and main modules.
- `/hud` now opens the settings menu (the HUD itself is toggled with *Enable HUD*). The old `/hudsettings` list menu is replaced; `/hudsettings` opens the new menu.
- Vehicle instruments per vehicle type instead of one generic speedometer.
- Kept: hidden GTA health/armour bars, hidden native cash / name components, weapon wheel disabled (inventory weapons), diffed NUI updates.

## Validation

Checked here (static): every Lua file parses (luaparse, Lua 5.3 syntax with FiveM hash literals stripped); the page type-checks and builds.

Still to check in game: on foot, car, motorcycle, boat, helicopter, BMX; entering, leaving and switching vehicles as driver and passenger; death and respawn; voice talking and radio; fuel with and without `veyl_fuel`; square / circle switching (with the asset); the pause map; Save / Cancel / Reset and persistence after reconnect; the position editor at 1080p, 1440p, 4K and 21:9; restarting the resource while seated in a vehicle and with the menu open (no cursor or focus should remain). The minimap outline is calculated from GTA's own layout formula; if it is off by a few pixels on your screen, drag the map slightly in the editor.
